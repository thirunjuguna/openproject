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
    # TODO: wrap in transaction
    as_user_and_sending(send_notifications) do
      update(attributes)
    end
  end

  private

  def update(attributes)
    result = set_attributes(attributes)

    all_valid = result.success? && work_package.save
    if all_valid
      cleanup_result, cleanup_errors = cleanup

      ServiceResult.new(success: cleanup_result,
                        errors: cleanup_errors)
    else
      ServiceResult.new(success: all_valid,
                        errors: result.success? ? work_package.errors : result.errors)
    end
  end

  def set_attributes(attributes)
    SetAttributesWorkPackageService
      .new(user: user,
           work_package: work_package,
           contract: WorkPackages::UpdateContract)
      .call(attributes)
  end

  def cleanup
    work_package.ancestors.each do |ancestor|
      recalculate_attributes_for(ancestor)
    end

    attributes = work_package.changes.dup
    result = true
    errors = work_package.errors

    if attributes.include?(:project_id)
      delete_relations
      move_time_entries
      result, errors = move_children
    end
    if attributes.include?(:type_id)
      reset_custom_values
    end

    [result, errors]
  end

  def delete_relations
    unless Setting.cross_project_work_package_relations?
      work_package.relations.non_hierarchy.direct.destroy_all
    end
  end

  def move_time_entries
    work_package.move_time_entries(work_package.project)
  end

  def reset_custom_values
    work_package.reset_custom_values!
  end

  def move_children
    work_package.children.each do |child|
      result, errors = WorkPackages::UpdateChildService
                       .new(user: user,
                            work_package: child)
                       .call(attributes: { project: work_package.project })

      return result, errors unless result
    end

    [true, work_package.errors]
  end

  def as_user_and_sending(send_notifications)
    User.execute_as user do
      JournalManager.with_send_notifications send_notifications do
        yield
      end
    end
  end

  def recalculate_attributes_for(wp)
    inherit_dates_from_children(wp)

    inherit_done_ratio_from_leaves(wp)

    inherit_estimated_hours_from_leaves(wp)

    # ancestors will be recursively updated
    if wp.changed?
      wp.journal_notes =
        I18n.t('work_package.updated_automatically_by_child_changes', child: "##{work_package.id}")

      # Ancestors will be updated by parent's after_save hook.
      wp.save(validate: false)
    end
  end

  def inherit_dates_from_children(wp)
    unless wp.children.empty?
      wp.start_date = [wp.children.minimum(:start_date), wp.children.minimum(:due_date)].compact.min
      wp.due_date   = [wp.children.maximum(:start_date), wp.children.maximum(:due_date)].compact.max
    end
  end

  def inherit_done_ratio_from_leaves(wp)
    return if WorkPackage.done_ratio_disabled?

    return if WorkPackage.use_status_for_done_ratio? && wp.status && wp.status.default_done_ratio

    # done ratio = weighted average ratio of leaves
    ratio = aggregate_done_ratio(wp)

    if ratio
      wp.done_ratio = ratio.round
    end
  end

  ##
  # done ratio = weighted average ratio of leaves
  def aggregate_done_ratio(wp)
    leaves_count = wp.leaves.count

    if leaves_count > 0
      average = leaf_average_estimated_hours(wp)
      progress = leaf_done_ratio_sum(wp, average) / (average * leaves_count)

      progress.round(2)
    end
  end

  def leaf_average_estimated_hours(wp)
    # 0 and nil shall be considered the same for estimated hours
    average = wp.leaves.where('estimated_hours > 0').average(:estimated_hours).to_f

    average.zero? ? 1 : average
  end

  def leaf_done_ratio_sum(wp, average_estimated_hours)
    # Do not take into account estimated_hours when it is either nil or set to 0.0
    sum_sql = <<-SQL
    COALESCE((CASE WHEN estimated_hours = 0.0 THEN NULL ELSE estimated_hours END), #{average_estimated_hours})
    * (CASE WHEN is_closed = #{wp.class.connection.quoted_true} THEN 100 ELSE COALESCE(done_ratio, 0) END)
    SQL

    wp.leaves.joins(:status).sum(sum_sql)
  end

  def inherit_estimated_hours_from_leaves(wp)
    # estimate = sum of leaves estimates
    wp.estimated_hours = wp.leaves.sum(:estimated_hours).to_f
    wp.estimated_hours = nil if wp.estimated_hours == 0.0
  end
end
