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

class WorkPackages::DestroyService
  include Shared::UpdateAncestors

  attr_accessor :user, :work_package

  def initialize(user:, work_package:)
    self.user = user
    self.work_package = work_package
  end

  def call
    as_user do
      destroy
    end
  end

  private

  def destroy
    unit_of_work = [work_package]
    errors = []

    descendants = work_package.descendants.to_a

    if work_package.destroy
      errors << work_package.errors

      ancestors_updated, ancestors_errors = update_ancestors_all_attributes(unit_of_work)

      unit_of_work += ancestors_updated
      errors += ancestors_errors

      unit_of_work += descendants.each(&:destroy)
    end

    ServiceResult.new(success: work_package.destroyed?,
                      errors: errors.reject(&:empty?),
                      result: unit_of_work)
  end

  # TODO: copied from update service
  def as_user
    result = nil

    WorkPackage.transaction do
      User.execute_as user do
        result = yield

        if result.failure?
          raise ActiveRecord::Rollback
        end
      end
    end

    result
  end
end
