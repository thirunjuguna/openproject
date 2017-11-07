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
  attr_accessor :user,
                :work_package,
                :contract

  def initialize(user:, work_package:)
    self.user = user
    self.work_package = work_package
  end

  def call(attributes)
    inherit_attributes(attributes)

    set_journal_note if work_package.changed?

    ServiceResult.new(success: work_package.save,
                      errors: work_package.errors,
                      result: work_package)
  end

  private

  def inherit_attributes(attributes)
    relevant_attributes = (%i(estimated_hours done_ratio) & attributes)

    return unless relevant_attributes.any?

    leaves = work_package.leaves.select(*relevant_attributes, :status_id).includes(:status).to_a

    inherit_done_ratio(leaves)

    inherit_estimated_hours(leaves) if relevant_attributes.include?(:estimated_hours)
  end

  def set_journal_note
    work_package.journal_notes = I18n.t('work_package.updated_automatically_by_child_changes', child: "##{work_package.id}")
  end

  def inherit_done_ratio(leaves)
    return if WorkPackage.done_ratio_disabled?

    return if WorkPackage.use_status_for_done_ratio? && work_package.status && work_package.status.default_done_ratio

    # done ratio = weighted average ratio of leaves
    ratio = aggregate_done_ratio(leaves)

    if ratio
      work_package.done_ratio = ratio.round
    end
  end

  ##
  # done ratio = weighted average ratio of leaves
  def aggregate_done_ratio(leaves)
    leaves_count = leaves.size

    if leaves_count > 0
      average = average_estimated_hours(leaves)
      progress = done_ratio_sum(leaves, average) / (average * leaves_count)

      progress.round(2)
    end
  end

  def average_estimated_hours(leaves)
    # 0 and nil shall be considered the same for estimated hours
    sum = all_estimated_hours(leaves).sum.to_f
    count = all_estimated_hours(leaves).count

    count = 1 if count.zero?

    average = sum / count

    average.zero? ? 1 : average
  end

  def done_ratio_sum(leaves, average_estimated_hours)
    # Do not take into account estimated_hours when it is either nil or set to 0.0
    summands = leaves.map do |leaf|
      estimated_hours = if leaf.estimated_hours.to_f > 0
                          leaf.estimated_hours
                        else
                          average_estimated_hours
                        end

      done_ratio = if leaf.closed?
                     100
                   else
                     leaf.done_ratio || 0
                   end

      estimated_hours * done_ratio
    end

    summands.sum
  end

  def inherit_estimated_hours(leaves)
    work_package.estimated_hours = all_estimated_hours(leaves).sum.to_f
    work_package.estimated_hours = nil if work_package.estimated_hours.zero?
  end

  def all_estimated_hours(work_packages)
    work_packages.map(&:estimated_hours).reject { |hours| hours.to_f.zero? }
  end
end
