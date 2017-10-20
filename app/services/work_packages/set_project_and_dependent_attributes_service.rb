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

class WorkPackages::SetProjectAndDependentAttributesService
  include Concerns::Contracted

  attr_accessor :user,
                :work_package,
                :contract

  def initialize(user:, work_package:, contract:)
    self.user = user
    self.work_package = work_package

    self.contract = contract.new(work_package, user)
  end

  def call(project)
    set_attributes(project)

    validate_and_result
  end

  private

  # TODO duplicated with setAttributesWorkPackageService
  def validate_and_result
    boolean, errors = validate(work_package)

    ServiceResult.new(success: boolean,
                      errors: errors)
  end

  def set_attributes(project)
    work_package.project = project

    set_fixed_version_to_nil
    reassign_category
    reassign_type
  end

  def set_fixed_version_to_nil
    unless work_package.fixed_version &&
           work_package.project.shared_versions.include?(work_package.fixed_version)
      work_package.fixed_version = nil
    end
  end

  def reassign_category
    # work_package is moved to another project
    # reassign to the category with same name if any
    if work_package.category.present?
      category = work_package.project.categories.find_by(name: work_package.category.name)

      work_package.category = category
    end
  end

  def reassign_type
    available_types = work_package.project.types

    if available_types.include? work_package.type
      return
    elsif available_types.any?(&:is_default)
      work_package.type = available_types.detect(&:is_default)
    else
      work_package.type = available_types.first
    end

    reassign_status
  end

  def reassign_status
    available_statuses = work_package.new_statuses_allowed_to(user, true)

    if available_statuses.include? work_package.status
      return
    elsif available_statuses.any?(&:is_default)
      work_package.status = available_statuses.detect(&:is_default)
    else
      work_package.status = available_statuses.first
    end
  end
end
