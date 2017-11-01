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
    altered = if (%i(start_date due_date) & attributes).any?
                schedule_following
              else
                []
              end

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

    dependencies = build_dependencies

    while dependencies.any?
      dependencies.each do |work_package, dependency|
        next unless dependency.met?(dependencies.keys) # (dependencies.keys & dependency.moved).any?

        altered << reschedule(work_package, dependency, delta)

        dependencies.delete(work_package)
      end
    end

    altered.uniq
  end

  def build_dependencies
    dependencies = Hash.new do |hash, wp|
      hash[wp] = Dependency.new
    end

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
    following = Relation
                .where(to: work_packages)
                .follows_with_hierarchy_accepted
                .where(follows: 1)
                .select(:from_id)

    WorkPackage
      .where(id: Relation.hierarchy.where(from_id: following).select(:to_id))
      .or(WorkPackage.where(id: following))
      .includes(:parent_relation, follows_relations: :to)
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

  def reschedule(following, dependency, delta)
    following.start_date += delta
    following.due_date += delta

    # TODO: handle descendant limitation
    min_date = calculate_min_date(dependency) # all_following + [work_package])

    if min_date && following.start_date < min_date
      min_delta = min_date - following.start_date

      following.start_date += min_delta
      following.due_date += min_delta
    end

    following
  end

  def calculate_min_date(dependency)
    #  all_following_ids = all_work_packages.map(&:id)

    #ancestors = ancestors_from_preloaded(following, all_work_packages)
    #descendants = descendants_from_preloaded(following, all_work_packages)

    #subtree = ancestors + descendants + [following]
    #unmoved = subtree
    #          .map(&:follows_relations)
    #          .flatten
    #           .reject { |r| all_following_ids.include?(r.to_id) }
    #    binding.pry if following.subject == 'following'
    (dependency.follows_moved + dependency.follows_unmoved)
      .map(&:successor_soonest_start)
      .max
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

    #  .map do |relation|
    #  candidates.detect { |c| relation.to_id == c.id }
    #end
  end

  def unmoved_predecessors_from_preloaded(work_package, moved, tree)
    ([work_package] + tree)
      .map(&:follows_relations)
      .flatten
      .reject do |relation|
        moved.any? { |m| relation.to_id == m.id }
      end
  end


  # TODO: move into own class and add tests
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
  end
end
