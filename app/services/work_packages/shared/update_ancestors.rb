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

module WorkPackages
  module Shared
    module UpdateAncestors
      def update_ancestors(changed_work_packages)
        changes = changed_work_packages
                  .map { |wp| wp.previous_changes.keys }
                  .flatten
                  .uniq
                  .map(&:to_sym)

        update_each_ancestor(changed_work_packages, changes)
      end

      def update_ancestors_all_attributes(work_packages)
        changes = work_packages
                  .first
                  .attributes
                  .keys
                  .uniq
                  .map(&:to_sym)

        update_each_ancestor(work_package, changes)
      end

      def update_each_ancestor(work_package, changes)
        modified = []
        errors = []

        work_package.ancestors.each do |ancestor|
          result = inherit_to_ancestor(ancestor, changes)

          if result.success?
            modified << ancestor if ancestor.changed?
          else
            errors << result.errors
          end
        end

        [modified, errors]
      end

      def inherit_to_ancestor(ancestor, changes)
        WorkPackages::UpdateInheritedAttributesService
          .new(user: user,
               work_package: ancestor,
               contract: WorkPackages::UpdateContract)
          .call(changes)
      end
    end
  end
end
