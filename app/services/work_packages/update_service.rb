#-- encoding: UTF-8

#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2017 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2017 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.rdoc for more details.
#++

class WorkPackages::UpdateService
  attr_accessor :user, :work_package

  def initialize(user:, work_package:)
    self.user = user
    self.work_package = work_package
  end

  def call(attributes: {}, send_notifications: true)
    as_user_and_sending(send_notifications) do
      update(attributes)
    end
  end

  private

  def update(attributes)
    unit_of_work = []
    errors = []

    result = set_attributes(attributes)

    if result.success?
      unit_of_work << work_package

      update_descendants.tap do |updated_descendants, descendants_errors|
        errors += descendants_errors
        unit_of_work += updated_descendants
      end

      if errors.all?(&:empty?) && unit_of_work.all?(&:save)
        cleanup(unit_of_work, attributes)
      end
    end

    ServiceResult.new(success: errors.all?(&:empty?),
                      errors: errors,
                      result: unit_of_work)
  end

  def set_attributes(attributes, wp = work_package)
    SetAttributesWorkPackageService
      .new(user: user,
           work_package: wp,
           contract: WorkPackages::UpdateContract)
      .call(attributes)
  end

  def update_descendants
    modified = []
    errors = []

    if work_package.project_id_changed?
      work_package.descendants.each do |descendant|
        result = move_descendant(descendant, work_package.project)

        if result.success?
          modified << descendant if descendant.changed?
        else
          errors << result.errors
        end
      end
    end

    [modified, errors]
  end

  def move_descendant(descendant, project)
    WorkPackages::SetProjectAndDependentAttributesService
      .new(user: user,
           work_package: descendant,
           contract: WorkPackages::UpdateContract)
      .call(project)
  end

  def cleanup(work_packages, attributes)
    # TODO: add updated and errors to return values
    update_ancestors(work_packages)

    if attributes.include?(:project_id)
      delete_relations(work_packages)
      move_time_entries(work_packages, attributes[:project_id])
    end
    if attributes.include?(:type_id)
      reset_custom_values
    end
  end

  def delete_relations(work_packages)
    unless Setting.cross_project_work_package_relations?
      Relation
        .where(from: work_packages)
        .or(Relation.where(to: work_packages))
        .direct
        .destroy_all
    end
  end

  def move_time_entries(work_packages, project_id)
    TimeEntry
      .on_work_packages(work_packages)
      .update_all(project_id: project_id)
  end

  def reset_custom_values(work_packages)
    work_packages.each(&:reset_custom_values!)
  end

  def update_ancestors(changed_work_packages)
    changes = changed_work_packages
              .map { |wp| wp.previous_changes.keys }
              .flatten
              .uniq
              .map(&:to_sym)
    modified = []
    errors = []

    work_package.ancestors.each do |ancestor|
      result = inherit_to_ancestor(ancestor, changes)

      if result.success?
        modified << ancestor if ancestor.changed?
      else
        errors << result.errors
      end
    end

    [modified, errors]
  end

  def inherit_to_ancestor(ancestor, changes)
    WorkPackages::UpdateInheritedAttributesService
      .new(user: user,
           work_package: ancestor,
           contract: WorkPackages::UpdateContract)
      .call(changes)
  end

  def as_user_and_sending(send_notifications)
    result = nil

    WorkPackage.transaction do
      User.execute_as user do
        JournalManager.with_send_notifications send_notifications do
          result = yield

          if result.failure?
            raise ActiveRecord::Rollback
          end
        end
      end
    end

    result
  end
end
