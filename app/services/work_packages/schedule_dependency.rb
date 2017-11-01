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

    self.dependencies = Hash.new do |hash, wp|
      hash[wp] = Dependency.new
    end

    build_dependencies
  end

  def each
    unhandled = dependencies.keys

    while unhandled.any?
      movement = false
      dependencies.each do |scheduled, dependency|
        next unless unhandled.include?(scheduled)
        next unless dependency.met?(unhandled)

        # TODO: handle descendant limitation
        yield scheduled, dependency.min_date

        unhandled.delete(scheduled)
        movement = true
      end

      raise "Circular dependency" unless movement
    end
  end

  private

  attr_accessor :work_package,
                :dependencies

  def build_dependencies
    all_following = load_all_following(work_package)

    all_following.each do |following|
      ancestors = ancestors_from_preloaded(following, all_following)
      descendants = descendants_from_preloaded(following, all_following)

      dependencies[following].ancestors += ancestors
      dependencies[following].descendants += descendants

      tree = ancestors + descendants

      dependencies[following].follows_moved += moved_predecessors_from_preloaded(following, [work_package] + all_following, tree)
      dependencies[following].follows_unmoved += unmoved_predecessors_from_preloaded(following, [work_package] + all_following, tree)
    end

    dependencies
  end

  def load_all_following(work_packages)
    following = load_following(work_packages)

    if following.any?
      following + load_all_following(following)
    else
      following
    end
  end

  def load_following(work_packages)
    WorkPackage
      .hierarchy_tree_following(work_packages)
      .includes(:parent_relation, follows_relations: :to)
  end

  def ancestors_from_preloaded(work_package, candidates)
    if work_package.parent_relation
      parent = candidates.detect { |c| work_package.parent_relation.from_id == c.id }

      if parent
        [parent] + ancestors_from_preloaded(parent, candidates)
      end
    else
      []
    end
  end

  def descendants_from_preloaded(work_package, candidates)
    children = candidates.select { |c| c.parent_relation && c.parent_relation.from_id == work_package.id }

    children + children.map { |child| descendants_from_preloaded(child, candidates) }.flatten
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

  class Dependency
    def initialize
      self.follows_moved = []
      self.follows_unmoved = []
      self.ancestors = []
      self.descendants = []
    end

    attr_accessor :follows_moved,
                  :follows_unmoved,
                  :ancestors,
                  :descendants

    def met?(unhandled_work_packages)
      (descendants & unhandled_work_packages).empty? &&
        (follows_moved.map(&:to) & unhandled_work_packages).empty?
    end

    def min_date
      (follows_moved + follows_unmoved)
        .map(&:successor_soonest_start)
        .max
    end
  end
end
