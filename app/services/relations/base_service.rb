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

class Relations::BaseService
  include Concerns::Contracted

  attr_accessor :user

  def initialize(user:)
    self.user = user
  end

  private

  def update_relation(relation, attributes)
    relation.attributes = relation.attributes.merge attributes

    success, errors = validate_and_save relation

    result = ServiceResult.new success: success, errors: [errors], result: [relation]

    if success && relation.follows?
      reschedule_result = reschedule(relation)
      result.merge!(reschedule_result)
    end

    result
  end

  def initialize_contract!(relation)
    self.contract = self.class.contract.new relation, user
  end

  def reschedule(relation)
    schedule_result = WorkPackages::SetScheduleService
                      .new(user: user, work_packages: [relation.to])
                      .call

    save_result = if schedule_result.success?
                    schedule_result.result.each(&:save)
                  else
                    schedule_result.success?
                  end

    schedule_result.success = save_result

    schedule_result
  end

  # TODO: copied from wp update service
  def as_user_and_sending(send_notifications)
    result = nil

    Relation.transaction do
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
