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
  include Shared::UpdateAncestors

  attr_accessor :user, :work_package

  def initialize(user:, work_package:)
    self.user = user
    self.work_package = work_package
  end

  def call(attributes: {}, send_notifications: true)
    reset

    as_user_and_sending(send_notifications) do
      update(attributes)
    end
  end

  protected

  attr_accessor :errors,
                :unit_of_work

  private

  def reset
    self.errors = []
    self.unit_of_work = []
  end

  def update(attributes)
    result = set_attributes(attributes)

    errors << result.errors

    if result.success?
      unit_of_work << work_package

      update_dependent attributes

      unit_of_work.uniq!
    end

    ServiceResult.new(success: save_if_valid,
                      errors: all_errors,
                      result: unit_of_work)
  end

  def save_if_valid
    errors.all?(&:empty?) && unit_of_work.all?(&:save)
  end

  def all_errors
    (errors + unit_of_work.map(&:errors)).uniq.reject(&:empty?)
  end

  def update_dependent(attributes)
    update_descendants
    update_ancestors

    cleanup(attributes) if errors.all?(&:empty?)

    reschedule_related
  end

  def set_attributes(attributes, wp = work_package)
    SetAttributesWorkPackageService
      .new(user: user,
           work_package: wp,
           contract: WorkPackages::UpdateContract)
      .call(attributes)
  end

  def update_descendants
    if work_package.project_id_changed?
      work_package.descendants.each do |descendant|
        result = move_descendant(descendant, work_package.project)

        if result.success?
          unit_of_work << descendant if descendant.changed?
        else
          errors << result.errors
        end
      end
    end
  end

  def update_ancestors
    super([work_package]).tap do |modified, modified_errors|
      self.unit_of_work += modified
      self.errors += modified_errors
    end
  end

  def move_descendant(descendant, project)
    WorkPackages::SetProjectAndDependentAttributesService
      .new(user: user,
           work_package: descendant,
           contract: WorkPackages::UpdateContract)
      .call(project)
  end

  def cleanup(attributes)
    project = attributes[:project_id] || attributes[:project]

    if project
      moved_work_packages = [work_package] + work_package.descendants
      delete_relations(moved_work_packages)
      move_time_entries(moved_work_packages, project)
    end
    if attributes.include?(:type_id) || attributes.include?(:type)
      reset_custom_values
    end
  end

  def delete_relations(work_packages)
    unless Setting.cross_project_work_package_relations?
      Relation
        .non_hierarchy_of_work_package(work_packages)
        .destroy_all
    end
  end

  def move_time_entries(work_packages, project_id)
    TimeEntry
      .on_work_packages(work_packages)
      .update_all(project_id: project_id)
  end

  def reset_custom_values
    work_package.reset_custom_values!
  end

  def reschedule_related
    result = WorkPackages::SetScheduleService
             .new(user: user,
                  work_packages: work_package)
             .call(work_package.changed.map(&:to_sym))

    self.errors += result.errors
    self.unit_of_work += result.result
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

  def call_and_assign(method, params, updated, errors)
    send(method, *params).tap do |updated_by_method, errors_by_method|
      errors += errors_by_method
      updated += updated_by_method
    end
  end
end
