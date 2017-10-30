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

# Currently this is only a stub.
# The intend for this service is for it to include all the vast scheduling rules that make up the work package scheduling.

class WorkPackages::SetScheduleService
  include Concerns::Contracted

  attr_accessor :user, :work_package

  self.contract = WorkPackages::UpdateContract

  def initialize(user:, work_package:)
    self.user = user
    self.work_package = work_package

    self.contract = self.class.contract.new(work_package, user)
  end

  def call(attributes)
    altered = schedule_following if (%i(start_date due_date) & attributes).any?

    ServiceResult.new(success: altered.all?(&:valid?),
                      errors: altered.map(&:errors),
                      result: altered)
  end

  private

  delegate :due_date,
           :due_date_was,
           :start_date,
           :start_date_was,
           to: :work_package

  def schedule_following
    delta = date_rescheduling_delta

    altered = []

    load_all_following(work_package)
      .each do |following|
        # TODO: handle case where another follows relation
        # prevents moving following to a sooner date
        following.start_date += delta
        following.due_date += delta

        altered << following
      end

    altered.uniq
  end

  def load_all_following(work_packages)
    load_following(work_packages)
      .map do |following|
        ret = [following]

        if following.descendants.any?
          ret += following.descendants
          ret += load_all_following(following.descendants)
        end

        ret
      end
      .flatten
      .uniq
  end

  def load_following(work_packages)
    work_packages = Array(work_packages)
    Relation
      .where(from: work_packages)
      .or(Relation.where(to: work_packages))
      .follows_with_hierarchy_accepted
      .includes({ from: :descendants }, to: :descendants)
      .map do |following_relation|
        if work_packages.include?(following_relation.from)
          following_relation.to
        else
          following_relation.from
        end
      end
  end

  def date_rescheduling_delta
    if due_date.present?
      due_date - (due_date_was || due_date)
    elsif start_date.present?
      start_date - (start_date_was || start_date)
    else
      0
    end
  end
end
