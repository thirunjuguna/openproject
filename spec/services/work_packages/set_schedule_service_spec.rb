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

describe WorkPackages::SetScheduleService do
  let(:work_package) do
    FactoryGirl.build_stubbed(:work_package,
                              due_date: Date.today)
  end
  let(:instance) do
    described_class.new(user: user, work_package: work_package)
  end
  let(:following) do
    { work_package => [] }
  end
  let(:user) { FactoryGirl.build_stubbed(:user) }
  let(:type) { FactoryGirl.build_stubbed(:type) }

  subject { instance.call(attributes) }

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
  let(:attributes) { [:start_date] }

  context 'without relation' do
    it 'is success' do
      expect(subject)
        .to be_success
    end
  end

  context 'with a single successor' do
    let(:follower_start_date) { Date.today + 1.day }
    let(:follower_due_date) { Date.today + 3.day }
    let(:follower_delay) { 0 }
    let!(:following_work_package) do
      following = FactoryGirl.build_stubbed(:work_package,
                                            type: type,
                                            start_date: follower_start_date,
                                            due_date: follower_due_date)

      relation = FactoryGirl.build(:follows_relation,
                                   delay: follower_delay,
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

    context 'moving forward' do
      before do
        work_package.due_date = Date.today + 5.days
      end

      it 'is success' do
        expect(subject)
          .to be_success
      end

      it 'reschedules the follower' do
        subject
        expect(following_work_package.start_date)
          .to eql Date.today + 6.day
        expect(following_work_package.due_date)
          .to eql Date.today + 8.day
      end
    end

    context 'moving forward with the follower having some space left' do
      let(:follower_start_date) { Date.today + 3.day }
      let(:follower_due_date) { Date.today + 5.day }

      before do
        work_package.due_date = Date.today + 5.days
      end

      it 'is success' do
        expect(subject)
          .to be_success
      end

      it 'reschedules the follower' do
        subject
        expect(following_work_package.start_date)
          .to eql Date.today + 6.day
        expect(following_work_package.due_date)
          .to eql Date.today + 8.day
      end
    end

    context 'moving forward with the follower having some space left and a delay' do
      let(:follower_start_date) { Date.today + 5.day }
      let(:follower_due_date) { Date.today + 7.day }
      let(:follower_delay) { 3 }

      before do
        work_package.due_date = Date.today + 5.days
      end

      it 'is success' do
        expect(subject)
          .to be_success
      end

      it 'reschedules the follower' do
        subject
        expect(following_work_package.start_date)
          .to eql Date.today + 9.day
        expect(following_work_package.due_date)
          .to eql Date.today + 11.day
      end
    end

    context 'moving forward with the follower not needing to be moved' do
      let(:follower_start_date) { Date.today + 6.day }
      let(:follower_due_date) { Date.today + 8.day }

      before do
        work_package.due_date = Date.today + 5.days
      end

      it 'is success' do
        expect(subject)
          .to be_success
      end

      it 'reschedules the follower' do
        subject
        expect(following_work_package.start_date)
          .to eql Date.today + 6.day
        expect(following_work_package.due_date)
          .to eql Date.today + 8.day
      end
    end

    context 'moving backwards' do
      before do
        work_package.due_date = Date.today - 5.days
      end

      it 'is success' do
        expect(subject)
          .to be_success
      end

      it 'reschedules the follower' do
        subject
        expect(following_work_package.start_date)
          .to eql Date.today - 4.day
        expect(following_work_package.due_date)
          .to eql Date.today - 2.day
      end
    end

    context 'moving backwards with space between' do
      let(:follower_start_date) { Date.today + 3.day }
      let(:follower_due_date) { Date.today + 5.day }

      before do
        work_package.due_date = Date.today - 5.days
      end

      it 'is success' do
        expect(subject)
          .to be_success
      end

      it 'reschedules the follower' do
        subject
        expect(following_work_package.start_date)
          .to eql Date.today - 2.days
        expect(following_work_package.due_date)
          .to eql Date.today
      end
    end
  end

  context 'with a chain of successors' do
    let(:follower1_start_date) { Date.today + 1.day }
    let(:follower1_due_date) { Date.today + 3.day }
    let(:follower2_start_date) { Date.today + 4.day }
    let(:follower2_due_date) { Date.today + 8.day }
    let(:follower3_start_date) { Date.today + 9.day }
    let(:follower3_due_date) { Date.today + 10.day }

    let!(:following_work_package1) do
      following = FactoryGirl.build_stubbed(:work_package,
                                            type: type,
                                            start_date: follower1_start_date,
                                            due_date: follower1_due_date)

      relation = FactoryGirl.build(:follows_relation,
                                   from: following,
                                   to: work_package)

      allow(following)
        .to receive(:follows_relations)
        .and_return [relation]

      following
    end
    let!(:following_work_package2) do
      following = FactoryGirl.build_stubbed(:work_package,
                                            type: type,
                                            start_date: follower2_start_date,
                                            due_date: follower2_due_date)

      relation = FactoryGirl.build(:follows_relation,
                                   from: following,
                                   to: following_work_package1)

      allow(following)
        .to receive(:follows_relations)
        .and_return [relation]

      following
    end
    let!(:following_work_package3) do
      following = FactoryGirl.build_stubbed(:work_package,
                                            type: type,
                                            start_date: follower3_start_date,
                                            due_date: follower3_due_date)

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
        work_package => [following_work_package1,
                         following_work_package2,
                         following_work_package3],
        [following_work_package1,
         following_work_package2,
         following_work_package3] => []
      }
    end

    context 'moving forward' do
      before do
        work_package.due_date = Date.today + 5.days
      end

      it 'is success' do
        expect(subject)
          .to be_success
      end

      it 'reschedules the follower' do
        subject
        expect(following_work_package1.start_date)
          .to eql Date.today + 6.day
        expect(following_work_package1.due_date)
          .to eql Date.today + 8.day
        expect(following_work_package2.start_date)
          .to eql Date.today + 9.day
        expect(following_work_package2.due_date)
          .to eql Date.today + 13.day
        expect(following_work_package3.start_date)
          .to eql Date.today + 14.day
        expect(following_work_package3.due_date)
          .to eql Date.today + 15.day
      end
    end

    context 'moving forward with some space between the followers' do
      let(:follower1_start_date) { Date.today + 1.day }
      let(:follower1_due_date) { Date.today + 3.day }
      let(:follower2_start_date) { Date.today + 7.day }
      let(:follower2_due_date) { Date.today + 10.day }
      let(:follower3_start_date) { Date.today + 17.day }
      let(:follower3_due_date) { Date.today + 18.day }

      before do
        work_package.due_date = Date.today + 5.days
      end

      it 'is success' do
        expect(subject)
          .to be_success
      end

      it 'reschedules the follower' do
        subject
        expect(following_work_package1.start_date)
          .to eql Date.today + 6.day
        expect(following_work_package1.due_date)
          .to eql Date.today + 8.day
        expect(following_work_package2.start_date)
          .to eql Date.today + 9.day
        expect(following_work_package2.due_date)
          .to eql Date.today + 12.day
        expect(following_work_package3.start_date)
          .to eql Date.today + 17.day
        expect(following_work_package3.due_date)
          .to eql Date.today + 18.day
      end
    end

    context 'moving backwards' do
      before do
        work_package.due_date = Date.today - 5.days
      end

      it 'is success' do
        expect(subject)
          .to be_success
      end

      it 'reschedules the follower' do
        subject
        expect(following_work_package1.start_date)
          .to eql Date.today - 4.day
        expect(following_work_package1.due_date)
          .to eql Date.today - 2.day
        expect(following_work_package2.start_date)
          .to eql Date.today - 1.day
        expect(following_work_package2.due_date)
          .to eql Date.today + 3.day
        expect(following_work_package3.start_date)
          .to eql Date.today + 4.day
        expect(following_work_package3.due_date)
          .to eql Date.today + 5.day
      end
    end
  end
#
#  context 'with a chain of successors with two paths leadig to the same work package in the end' do
#    let!(:following_work_package1) do
#      following = FactoryGirl.build_stubbed(:work_package)
#
#      relation = FactoryGirl.build(:follows_relation,
#                                   from: following,
#                                   to: work_package)
#
#      allow(following)
#        .to receive(:follows_relations)
#        .and_return [relation]
#
#      following
#    end
#    let!(:following_work_package2) do
#      following = FactoryGirl.build_stubbed(:work_package)
#
#      relation = FactoryGirl.build(:follows_relation,
#                                   from: following,
#                                   to: following_work_package1,
#                                   delay: 5)
#
#      allow(following)
#        .to receive(:follows_relations)
#        .and_return [relation]
#
#      following
#    end
#    let!(:following_work_package3) do
#      following = FactoryGirl.build_stubbed(:work_package)
#
#      relation = FactoryGirl.build(:follows_relation,
#                                   from: following,
#                                   to: work_package)
#
#      allow(following)
#        .to receive(:follows_relations)
#        .and_return [relation]
#
#      following
#    end
#    let!(:following_work_package4) do
#      following = FactoryGirl.build_stubbed(:work_package)
#
#      relation1 = FactoryGirl.build(:follows_relation,
#                                    from: following,
#                                    to: following_work_package2)
#
#      relation2 = FactoryGirl.build(:follows_relation,
#                                    from: following,
#                                    to: following_work_package3)
#
#      allow(following)
#        .to receive(:follows_relations)
#        .and_return [relation1, relation2]
#
#      following
#    end
#    let(:following) do
#      {
#        work_package => [following_work_package1, following_work_package3],
#        [following_work_package1, following_work_package3] => [following_work_package2, following_work_package4],
#        [following_work_package2, following_work_package4] => [following_work_package4],
#        [following_work_package4] => []
#      }
#    end
#
#    it_behaves_like 'yields the following work packages and the min date in the correct order' do
#      let(:expected) do
#        [[following_work_package1, Date.today + 1.day],
#         [following_work_package3, Date.today + 1.day],
#         [following_work_package2, Date.today + 7.days],
#         [following_work_package4, Date.today + 8.days]]
#      end
#    end
#  end
#
#  context 'with a successor having a parent and a sibling' do
#    let!(:following_work_package) do
#      following = FactoryGirl.build_stubbed(:work_package,
#                                            subject: 'following',
#                                            start_date: Date.today + 5.days,
#                                            due_date: Date.today + 10.days)
#
#      follows_relation = FactoryGirl.build(:follows_relation,
#                                           from: following,
#                                           to: work_package)
#
#      allow(following)
#        .to receive(:follows_relations)
#        .and_return [follows_relation]
#
#      parent_relation = FactoryGirl.build(:hierarchy_relation,
#                                          from: following_parent_work_package,
#                                          to: following)
#
#      allow(following)
#        .to receive(:parent_relation)
#        .and_return parent_relation
#
#      following
#    end
#    let!(:following_parent_work_package) do
#      FactoryGirl.build_stubbed(:work_package,
#                                subject: 'following_parent',
#                                start_date: Date.today + 5.days,
#                                due_date: Date.today + 14.days)
#    end
#    let!(:following_sibling_work_package) do
#      sibling = FactoryGirl.build_stubbed(:work_package,
#                                          subject: 'following_sibling',
#                                          start_date: Date.today + 8.days,
#                                          due_date: Date.today + 14.days)
#
#      parent_relation = FactoryGirl.build(:hierarchy_relation,
#                                          from: following_parent_work_package,
#                                          to: sibling)
#
#      allow(sibling)
#        .to receive(:parent_relation)
#        .and_return parent_relation
#
#      sibling
#    end
#    let(:following) do
#      {
#        work_package => [following_work_package, following_sibling_work_package, following_parent_work_package],
#        [following_work_package, following_parent_work_package] => []
#      }
#    end
#
#    it_behaves_like 'yields the following work packages and the min date in the correct order' do
#      let(:expected) do
#        [[following_work_package, [Date.today + 1.day, nil], [Date.today + 1.day, nil]],
#         [following_parent_work_package, [Date.today + 1.day, Date.today + 8.days], [Date.today + 6.days, Date.today + 14.days]]]
#      end
#    end
#  end
end
