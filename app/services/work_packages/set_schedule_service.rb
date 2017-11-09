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

class WorkPackages::SetScheduleService
  attr_accessor :user, :work_packages

  def initialize(user:, work_packages:)
    self.user = user
    self.work_packages = work_packages
  end

  def call(attributes = %i(start_date due_date))
    altered = if (%i(parent parent_id) & attributes).any?
                schedule_by_parent
              else
                []
              end

    if (%i(start_date due_date) & attributes).any?
      altered += schedule_following
    end

    ServiceResult.new(success: true,
                      errors: [],
                      result: altered)
  end

  private

  def schedule_by_parent
    work_packages
      .select { |wp| wp.start_date.nil? && wp.parent }
      .each { |wp| wp.start_date = wp.parent.soonest_start }
  end

  # Finds all work packages that need to be rescheduled because of a rescheduling of the service's work package
  # and reschedules them.
  # The order of the rescheduling is important as successors' dates are calculated based on their predecessors' dates and
  # ancestors' dates based on their childrens' dates.
  # Thus, the work packages following (having a follows relation, direct or transitively) the service's work package
  # are first all loaded, and then sorted by their need to be scheduled before one another:
  # - predecessors are scheduled before their successors
  # - children/descendants are scheduled before their parents/ancestors
  def schedule_following
    altered = []

    WorkPackages::ScheduleDependency.new(work_packages).each do |scheduled, dependency|
      reschedule(scheduled, dependency)

      altered << scheduled if scheduled.changed?
    end

    altered
  end

  # Schedules work packages based on either
  #  - their descendants if they are parents
  #  - their predecessors (or predecessors of their ancestors) if they are leaves
  def reschedule(scheduled, dependency)
    #to_schedule = schedule.work_package

    if dependency.descendants.any?
      reschedule_ancestor(scheduled, dependency)
    else
      reschedule_by_follows(scheduled, dependency)
    end
  end

  # Inherits the start/due_date from the descendants of this work package. Only parent work packages are scheduled like this.
  # start_date receives the minimum of the dates (start_date and due_date) of the descendants
  # due_date receives the maximum of the dates (start_date and due_date) of the descendants
  def reschedule_ancestor(scheduled, dependency)
    scheduled.start_date = dependency.start_date
    scheduled.due_date = dependency.due_date
  end

  # Calculates the dates of a work package based on its follows relations. The follows relations of
  # ancestors are considered to be equal to own follows relations as they inhibit moving a work package
  # just the same. Only leaf work packages are calculated like this.
  # * work package is moved to a later date (delta positive):
  #  - all following work packages are moved by the same amount unless there is still a time buffer between work package and
  #    its predecessors (predecessors can also be acquired transitively by ancestors)
  # * work package moved to an earlier date (delta negative):
  #  - all following work packages are moved by the same amount unless a follows relation of the work package or one of its
  #    ancestors limits moving it. Then it is moved to the earliest date possible. This limitation is propagated transtitively
  #    to all following work packages.
  def reschedule_by_follows(scheduled, dependency)
    # TODO: move into schedule dependency
    delta = date_rescheduling_delta(dependency.follows_moved.first.to)

    unless delta.zero?
      required_delta = [dependency.max_date_of_followed - scheduled.start_date, [delta, 0].min].max

      scheduled.start_date += required_delta
      scheduled.due_date += required_delta
    end
  end

  def date_rescheduling_delta(predecessor)
    if predecessor.due_date.present?
      predecessor.due_date - (predecessor.due_date_was || predecessor.due_date)
    elsif predecessor.start_date.present?
      predecessor.start_date - (predecessor.start_date_was || predecessor.start_date)
    else
      0
    end
  end
end
