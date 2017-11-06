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

class WorkPackages::RescheduleService
  attr_accessor :user,
                :work_package

  def initialize(user:, work_package:)
    self.user = user
    self.work_package = work_package
  end

  def call(date)
    as_user_and_sending(true) do
      return if date.nil?

      update(date)
    end
  end

  def reschedule_leaves(date)
    work_package.leaves.map do |leaf|
      reschedule(leaf, date)
    end
  end

  def reschedule(scheduled, date)
    if scheduled.start_date.nil? || scheduled.start_date < date
      attributes = { due_date: date + scheduled.duration - 1,
                     start_date: date }

      set_dates(scheduled, attributes)
    end
  end

  def update(date)
    unit_of_work = []
    errors = []

    results = set_attributes(date).compact

    if results.all?(&:success?)
      unit_of_work += results.map(&:result)

      reschedule_related(unit_of_work).tap do |reschedule_results|
        errors += reschedule_results.errors
        unit_of_work += reschedule_results.result
      end

      unit_of_work.uniq!

      unit_of_work.all?(&:save) if errors.all?(&:empty?)
    end

    ServiceResult.new(success: errors.all?(&:empty?),
                      errors: errors,
                      result: unit_of_work)
  end

  def reschedule_related(work_packages)
    WorkPackages::SetScheduleService
      .new(user: user,
           work_packages: work_packages)
      .call(%i(start_date due_date))
  end

  def set_attributes(date)
    if work_package.leaf?
      [reschedule(work_package, date)]
    else
      reschedule_leaves(date)
    end
  end

  def set_dates(scheduled, attributes)
    SetAttributesWorkPackageService
      .new(user: user,
           work_package: scheduled,
           contract: WorkPackages::UpdateContract)
      .call(attributes)
  end

  # TODO copied from Update service
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
