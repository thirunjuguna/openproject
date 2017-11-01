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

require 'spec_helper'

describe WorkPackages::ScheduleDependency do
  let(:work_package) do
    FactoryGirl.build_stubbed(:work_package,
                              due_date: Date.today)
  end
  let(:instance) do
    described_class.new(work_package)
  end
  let(:following) do
    { work_package => [] }
  end

  before do
    following.each do |wp, results|
      allow(WorkPackage)
        .to receive(:hierarchy_tree_following)
        .with(wp)
        .and_return(results)

      allow(results)
        .to receive(:includes)
        .and_return(results)
    end
  end

  context 'without relation' do
    it 'does not yield' do
      expect { |b| instance.each(&b) }.not_to yield_control
    end
  end

  shared_examples_for 'yields the following work packages and the min date in the correct order' do
    it do
      yielded = []

      instance.each do |work_package, min_date|
        yielded << [work_package, min_date]
        work_package.due_date = min_date
      end

      expect(yielded)
        .to match_array(expected)
    end
  end

  context 'with a single successor' do
    let!(:following_work_package) do
      following = FactoryGirl.build_stubbed(:work_package)

      relation = FactoryGirl.build(:follows_relation,
                                   from: following,
                                   to: work_package)

      allow(following)
        .to receive(:follows_relations)
        .and_return [relation]

      following
    end
    let(:following) do
      {
        work_package => [following_work_package],
        [following_work_package] => []
      }
    end

    it_behaves_like 'yields the following work packages and the min date in the correct order' do
      let(:expected) do
        [[following_work_package, Date.today + 1.day]]
      end
    end
  end

  context 'with a chain of successors' do
    let!(:following_work_package1) do
      following = FactoryGirl.build_stubbed(:work_package)

      relation = FactoryGirl.build(:follows_relation,
                                   from: following,
                                   to: work_package)

      allow(following)
        .to receive(:follows_relations)
        .and_return [relation]

      following
    end
    let!(:following_work_package2) do
      following = FactoryGirl.build_stubbed(:work_package)

      relation = FactoryGirl.build(:follows_relation,
                                   from: following,
                                   to: following_work_package1)

      allow(following)
        .to receive(:follows_relations)
        .and_return [relation]

      following
    end
    let!(:following_work_package3) do
      following = FactoryGirl.build_stubbed(:work_package)

      relation = FactoryGirl.build(:follows_relation,
                                   from: following,
                                   to: following_work_package2)

      allow(following)
        .to receive(:follows_relations)
        .and_return [relation]

      following
    end
    let(:following) do
      {
        work_package => [following_work_package1],
        [following_work_package1] => [following_work_package2],
        [following_work_package2] => [following_work_package3],
        [following_work_package3] => []
      }
    end

    it_behaves_like 'yields the following work packages and the min date in the correct order' do
      let(:expected) do
        [[following_work_package1, Date.today + 1.day],
         [following_work_package2, Date.today + 2.day],
         [following_work_package3, Date.today + 3.day]]
      end
    end
  end

  context 'with a chain of successors with two paths leadig to the same work package in the end' do
    let!(:following_work_package1) do
      following = FactoryGirl.build_stubbed(:work_package)

      relation = FactoryGirl.build(:follows_relation,
                                   from: following,
                                   to: work_package)

      allow(following)
        .to receive(:follows_relations)
        .and_return [relation]

      following
    end
    let!(:following_work_package2) do
      following = FactoryGirl.build_stubbed(:work_package)

      relation = FactoryGirl.build(:follows_relation,
                                   from: following,
                                   to: following_work_package1,
                                   delay: 5)

      allow(following)
        .to receive(:follows_relations)
        .and_return [relation]

      following
    end
    let!(:following_work_package3) do
      following = FactoryGirl.build_stubbed(:work_package)

      relation = FactoryGirl.build(:follows_relation,
                                   from: following,
                                   to: work_package)

      allow(following)
        .to receive(:follows_relations)
        .and_return [relation]

      following
    end
    let!(:following_work_package4) do
      following = FactoryGirl.build_stubbed(:work_package)

      relation1 = FactoryGirl.build(:follows_relation,
                                    from: following,
                                    to: following_work_package2)

      relation2 = FactoryGirl.build(:follows_relation,
                                    from: following,
                                    to: following_work_package3)

      allow(following)
        .to receive(:follows_relations)
        .and_return [relation1, relation2]

      following
    end
    let(:following) do
      {
        work_package => [following_work_package1, following_work_package3],
        [following_work_package1, following_work_package3] => [following_work_package2, following_work_package4],
        [following_work_package2, following_work_package4] => [following_work_package4],
        [following_work_package4] => []
      }
    end

    it_behaves_like 'yields the following work packages and the min date in the correct order' do
      let(:expected) do
        [[following_work_package1, Date.today + 1.day],
         [following_work_package3, Date.today + 1.day],
         [following_work_package2, Date.today + 7.days],
         [following_work_package4, Date.today + 8.days]]
      end
    end
  end
end
