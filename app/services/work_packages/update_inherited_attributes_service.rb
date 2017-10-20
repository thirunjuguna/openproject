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

class WorkPackages::UpdateInheritedAttributesService
  include Concerns::Contracted

  attr_accessor :user,
                :work_package,
                :contract

  def initialize(user:, work_package:, contract:)
    self.user = user
    self.work_package = work_package

    self.contract = contract.new(work_package, user)
  end

  def call(attributes)
    inherit_attributes(attributes)

    ServiceResult.new(success: work_package.save,
                      errors: work_package.errors)
  end

  private

  def inherit_attributes(attributes)
    inherit_dates_from_children if (%i(start_date due_date) & attributes).any?

    inherit_done_ratio_from_leaves if (%i(estimated_hours done_ratio) & attributes).any?

    inherit_estimated_hours_from_leaves if attributes.include?(:estimated_hours)

    if work_package.changed?
      work_package.journal_notes =
        I18n.t('work_package.updated_automatically_by_child_changes', child: "##{work_package.id}")
    end
  end

  def inherit_dates_from_children
    # using min and max instead of minimum and maximum here
    # as the later go to the db (4 times)
    children = work_package.children.pluck(:start_date, :due_date)

    return if children.empty?

    dates = children.flatten.compact

    work_package.start_date = dates.min
    work_package.due_date   = dates.max
  end

  def inherit_done_ratio_from_leaves
    return if WorkPackage.done_ratio_disabled?

    return if WorkPackage.use_status_for_done_ratio? && work_package.status && work_package.status.default_done_ratio

    # done ratio = weighted average ratio of leaves
    ratio = aggregate_done_ratio

    if ratio
      work_package.done_ratio = ratio.round
    end
  end

  ##
  # done ratio = weighted average ratio of leaves
  def aggregate_done_ratio
    leaves_count = work_package.leaves.count

    if leaves_count > 0
      average = leaf_average_estimated_hours
      progress = leaf_done_ratio_sum(average) / (average * leaves_count)

      progress.round(2)
    end
  end

  def leaf_average_estimated_hours
    # 0 and nil shall be considered the same for estimated hours
    average = work_package.leaves.where('estimated_hours > 0').average(:estimated_hours).to_f

    average.zero? ? 1 : average
  end

  def leaf_done_ratio_sum(average_estimated_hours)
    # TODO: merge into a single sql statement
    # Do not take into account estimated_hours when it is either nil or set to 0.0
    sum_sql = <<-SQL
    COALESCE((CASE WHEN estimated_hours = 0.0 THEN NULL ELSE estimated_hours END), #{average_estimated_hours})
    * (CASE WHEN is_closed = #{work_package.class.connection.quoted_true} THEN 100 ELSE COALESCE(done_ratio, 0) END)
    SQL

    work_package.leaves.joins(:status).sum(sum_sql)
  end

  def inherit_estimated_hours_from_leaves
    # estimate = sum of leaves estimates
    work_package.estimated_hours = work_package.leaves.sum(:estimated_hours).to_f
    work_package.estimated_hours = nil if work_package.estimated_hours == 0.0
  end
end
