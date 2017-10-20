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

describe WorkPackages::UpdateService, 'integration tests', type: :model do
  let(:user) do
    FactoryGirl.create(:user,
                       member_in_project: project,
                       member_through_role: role)
  end
  let(:role) { FactoryGirl.create(:role, permissions: permissions) }
  let(:permissions) do
    %i(view_work_packages edit_work_packages add_work_packages move_work_packages)
  end

  let(:type) { FactoryGirl.create(:type_standard) }
  let(:project) { FactoryGirl.create(:project, types: [type]) }
  let(:status) { FactoryGirl.create(:status) }
  let(:priority) { FactoryGirl.create(:priority) }
  let(:work_package_attributes) do
    { project_id: project.id,
      type_id: type.id,
      author_id: user.id,
      status_id: status.id,
      priority: priority }
  end
  let(:work_package) do
    FactoryGirl.create(:work_package,
                       work_package_attributes)
  end
  let(:parent_work_package) do
    FactoryGirl.create(:work_package,
                       work_package_attributes).tap do |w|
      w.children << work_package
    end
  end
  let(:grandparent_work_package) do
    FactoryGirl.create(:work_package,
                       work_package_attributes).tap do |w|
      w.children << parent_work_package
    end
  end
  let(:sibling1_attributes) do
    work_package_attributes.merge(parent: parent_work_package)
  end
  let(:sibling2_attributes) do
    work_package_attributes.merge(parent: parent_work_package)
  end
  let(:sibling1_work_package) do
    FactoryGirl.create(:work_package,
                       sibling1_attributes)
  end
  let(:sibling2_work_package) do
    FactoryGirl.create(:work_package,
                       sibling2_attributes)
  end
  let(:child_attributes) do
    work_package_attributes.merge(parent: work_package)
  end
  let(:child_work_package) do
    FactoryGirl.create(:work_package,
                       child_attributes)
  end
  let(:grandchild_attributes) do
    work_package_attributes.merge(parent: child_work_package)
  end
  let(:grandchild_work_package) do
    FactoryGirl.create(:work_package,
                       grandchild_attributes)
  end
  let(:instance) do
    described_class.new(user: user,
                        work_package: work_package)
  end

  subject do
    instance.call(attributes: attributes,
                  send_notifications: false)
  end

  describe '#call' do
    describe 'updating subject' do
      let(:attributes) { { subject: 'New subject' } }

      it 'works' do
        expect(subject)
          .to be_success

        expect(work_package.subject)
          .to eql(attributes[:subject])
      end
    end

    describe 'inheriting dates' do
      let(:attributes) { { start_date: Date.today - 8.days, due_date: Date.today + 12.days } }
      let(:sibling1_attributes) do
        work_package_attributes.merge(start_date: Date.today - 5.days,
                                      due_date: Date.today + 10.days,
                                      parent: parent_work_package)
      end
      let(:sibling2_attributes) do
        work_package_attributes.merge(due_date: Date.today + 16.days,
                                      parent: parent_work_package)
      end

      before do
        parent_work_package
        grandparent_work_package
        sibling1_work_package
        sibling2_work_package
      end

      it 'works and inherits' do
        expect(subject)
          .to be_success

        # receives the provided start/due date
        expect(work_package.start_date)
          .to eql(attributes[:start_date])
        expect(work_package.due_date)
          .to eql(attributes[:due_date])

        # receives the min/max of the children's start/due date
        [parent_work_package,
         grandparent_work_package].each do |wp|
          wp.reload

          expect(wp.start_date)
            .to eql(attributes[:start_date])
          expect(wp.due_date)
            .to eql(sibling2_work_package.due_date)
        end

        # sibling dates are unchanged
        sibling1_work_package.reload
        expect(sibling1_work_package.start_date)
          .to eql(sibling1_attributes[:start_date])
        expect(sibling1_work_package.due_date)
          .to eql(sibling1_attributes[:due_date])

        sibling2_work_package.reload
        expect(sibling2_work_package.start_date)
          .to eql(sibling2_attributes[:start_date])
        expect(sibling2_work_package.due_date)
          .to eql(sibling2_attributes[:due_date])
      end
    end

    describe 'inheriting done_ratio' do
      let(:attributes) { { done_ratio: 50 } }
      let(:work_package_attributes) do
        { project_id: project.id,
          type_id: type.id,
          author_id: user.id,
          status_id: status.id,
          priority: priority,
          estimated_hours: 10 }
      end

      let(:sibling1_attributes) do
        work_package_attributes.merge(estimated_hours: nil,
                                      done_ratio: 20,
                                      parent: parent_work_package)
      end
      let(:sibling2_attributes) do
        work_package_attributes.merge(done_ratio: 0,
                                      estimated_hours: 100,
                                      parent: parent_work_package)
      end

      before do
        parent_work_package
        grandparent_work_package
        sibling1_work_package
        sibling2_work_package
      end

      it 'works and inherits average done ratio of leaves weighted by estimated times' do
        expect(subject)
          .to be_success

        # set to the provided values
        expect(work_package.done_ratio)
          .to eql(attributes[:done_ratio])

        # calculated
        # sibling1 not factored in as its estimated_hours are nil
        calculated_ratio = (work_package.done_ratio * work_package.estimated_hours +
                            sibling2_work_package.done_ratio * sibling2_work_package.estimated_hours) /
                           (work_package.done_ratio +
                            sibling2_work_package.done_ratio)

        [parent_work_package,
         grandparent_work_package].each do |wp|
          wp.reload

          expect(wp.done_ratio)
            .to eql(calculated_ratio.to_i)
        end

        # unchanged
        sibling1_work_package.reload
        expect(sibling1_work_package.done_ratio)
          .to eql(sibling1_attributes[:done_ratio])

        sibling2_work_package.reload
        expect(sibling2_work_package.done_ratio)
          .to eql(sibling2_attributes[:done_ratio])
      end
    end

    describe 'inheriting estimated_hours' do
      let(:attributes) { { estimated_hours: 7 } }
      let(:sibling1_attributes) do
        # no estimated hours
        work_package_attributes.merge(parent: parent_work_package)
      end
      let(:sibling2_attributes) do
        work_package_attributes.merge(estimated_hours: 5,
                                      parent: parent_work_package)
      end

      before do
        parent_work_package
        grandparent_work_package
        sibling1_work_package
        sibling2_work_package
      end

      it 'works and inherits' do
        expect(subject)
          .to be_success

        # receives the provided value
        expect(work_package.estimated_hours)
          .to eql(attributes[:estimated_hours].to_f)

        # receive the sum of the children's estimated hours
        [parent_work_package,
         grandparent_work_package].each do |wp|
          sum = sibling1_attributes[:estimated_hours].to_f +
                sibling2_attributes[:estimated_hours].to_f +
                attributes[:estimated_hours].to_f

          wp.reload

          expect(wp.estimated_hours)
            .to eql(sum)
        end

        # sibling hours are unchanged
        sibling1_work_package.reload
        expect(sibling1_work_package.estimated_hours)
          .to be_nil

        sibling2_work_package.reload
        expect(sibling2_work_package.estimated_hours)
          .to eql(sibling2_attributes[:estimated_hours].to_f)
      end
    end

    describe 'closing duplicates on closing status' do
      let(:status_closed) do
        FactoryGirl.create(:status,
                           is_closed: true).tap do |status_closed|
          FactoryGirl.create(:workflow,
                             old_status: status,
                             new_status: status_closed,
                             type: type,
                             role: role)
        end
      end
      let(:duplicate_work_package) do
        FactoryGirl.create(:work_package,
                           work_package_attributes).tap do |wp|
          wp.duplicated << work_package
        end
      end

      let(:attributes) { { status: status_closed } }

      before do
        duplicate_work_package
      end

      it 'works and closes duplicates' do
        expect(subject)
          .to be_success

        duplicate_work_package.reload

        expect(work_package.status)
          .to eql(attributes[:status])
        expect(duplicate_work_package.status)
          .to eql(attributes[:status])
      end
    end

    describe 'moving descendants on project_id changes' do
      let(:other_project) do
        FactoryGirl.create(:project).tap do |p|
          p.add_member! user, role
        end
      end
      let(:attributes) { { project: other_project } }

      before do
        parent_work_package
        child_work_package
        grandchild_work_package
      end

      it 'moves the work_package along with its descendants' do
        expect(subject)
          .to be_success

        expect(subject.result)
          .to match_array([work_package, child_work_package, grandchild_work_package])

        expect(work_package.project)
          .to eql(attributes[:project])

        child_work_package.reload
        expect(child_work_package.project)
          .to eql(attributes[:project])

        grandchild_work_package.reload
        expect(grandchild_work_package.project)
          .to eql(attributes[:project])

        # is unchanged
        parent_work_package.reload
        expect(parent_work_package.project)
          .to eql(project)
      end
    end
  end
end
