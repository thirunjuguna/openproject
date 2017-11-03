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

class WorkPackages::ScheduleDependency
  def initialize(work_package)
    self.work_package = work_package
    self.dependencies = {}

    build_dependencies
  end

  def each
    unhandled = dependencies.keys

    while unhandled.any?
      movement = false
      dependencies.each do |scheduled, dependency|
        next unless unhandled.include?(scheduled)
        next unless dependency.met?(unhandled)

        yield scheduled, dependency

        unhandled.delete(scheduled)
        movement = true
      end

      raise "Circular dependency" unless movement
    end
  end

  attr_accessor :work_package,
                :dependencies

  private

  def build_dependencies
    load_all_following(work_package)
  end

  def load_all_following(work_packages)
    following = load_following(work_packages)

    new_dependencies = add_dependencies(following)

    if new_dependencies.any?
      load_all_following(new_dependencies.keys)
    end
  end

  def load_following(work_packages)
    WorkPackage
      .hierarchy_tree_following(work_packages)
      .includes(:parent_relation,
                follows_relations: :to)
  end

  def find_unmoved(candidates)
    moved = dependencies.slice(*candidates.keys).select do |following, dependency|
      dependency.ancestors.any? { |ancestor| included_in_follows(ancestor) } ||
        dependency.descendants.any? { |descendant| included_in_follows(descendant) } ||
        included_in_follows(following)
    end

    candidates.keys - moved.keys
  end

  def included_in_follows(wp)
    tos = wp.follows_relations.map(&:to)

    dependencies.slice(*tos).any? ||
      tos.include?(work_package)
  end

  def add_dependencies(dependent_work_packages)
    added = dependent_work_packages.inject({}) do |new_dependencies, dependent_work_package|
      dependency = Dependency.new dependent_work_package, self

      new_dependencies[dependent_work_package] = dependency

      new_dependencies
    end

    dependencies.merge!(added)
    unmoved = find_unmoved(added)

    unmoved.each do |to_delete|
      dependencies.delete(to_delete)
    end

    added.delete(unmoved)

    added
  end

  class Dependency
    def initialize(work_package, schedule_dependency)
      self.schedule_dependency = schedule_dependency
      self.work_package = work_package
    end

    def ancestors
      @ancestors ||= ancestors_from_preloaded(work_package)
    end

    def descendants
      @descendants ||= descendants_from_preloaded(work_package)
    end

    def follows_moved
      tree = ancestors + descendants

      @follows_moved ||= moved_predecessors_from_preloaded(work_package, known_work_packages, tree)
    end

    def follows_unmoved
      tree = ancestors + descendants

      @follows_unmoved ||= unmoved_predecessors_from_preloaded(work_package, known_work_packages, tree)
    end

    attr_accessor :work_package,
                  :schedule_dependency

    def met?(unhandled_work_packages)
      (descendants & unhandled_work_packages).empty? &&
        (follows_moved.map(&:to) & unhandled_work_packages).empty?
    end

    def max_date_of_followed
      (follows_moved + follows_unmoved)
        .map(&:successor_soonest_start)
        .max
    end

    def start_date
      descendants_dates.min
    end

    def due_date
      descendants_dates.max
    end

    private

    def descendants_dates
      descendants.map(&:due_date) + descendants.map(&:start_date)
    end

    def ancestors_from_preloaded(work_package)
      if work_package.parent_relation
        parent = known_work_packages.detect { |c| work_package.parent_relation.from_id == c.id }

        if parent
          [parent] + ancestors_from_preloaded(parent)
        end
      else
        []
      end
    end

    def descendants_from_preloaded(work_package)
      children = known_work_packages.select { |c| c.parent_relation && c.parent_relation.from_id == work_package.id }

      children + children.map { |child| descendants_from_preloaded(child) }.flatten
    end

    def known_work_packages
      [schedule_dependency.work_package] + schedule_dependency.dependencies.keys
    end

    def moved_predecessors_from_preloaded(work_package, moved, tree)
      moved_predecessors = ([work_package] + tree)
                           .map(&:follows_relations)
                           .flatten
                           .select do |relation|
                             moved.detect { |c| relation.to_id == c.id }
                           end

      moved_predecessors.each do |relation|
        relation.to = moved.detect { |c| relation.to_id == c.id }
      end

      moved_predecessors
    end

    def unmoved_predecessors_from_preloaded(work_package, moved, tree)
      ([work_package] + tree)
        .map(&:follows_relations)
        .flatten
        .reject do |relation|
          moved.any? { |m| relation.to_id == m.id }
        end
    end
  end
end
