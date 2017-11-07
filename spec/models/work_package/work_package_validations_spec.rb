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

describe WorkPackage, type: :model do
  let(:project) { FactoryGirl.create(:project) }
  let(:user) { FactoryGirl.create(:user) }

  describe 'validations' do
    # validations
    %i(subject priority project type author status).each do |field|
      it { is_expected.to validate_presence_of field }
    end

    it { is_expected.to validate_length_of(:subject).is_at_most 255 }
    it { is_expected.to validate_inclusion_of(:done_ratio).in_range 0..100 }
    it { is_expected.to validate_numericality_of :estimated_hours }

    it 'validates, that start-date is before end-date' do
      wp = FactoryGirl.build(:work_package, start_date: 1.day.from_now, due_date: 1.day.ago)
      wp.valid?
      expect(wp.errors[:due_date].size).to eq(1)
    end

    it 'validates, that correct formats are properly parsed' do
      wp = FactoryGirl.build(:work_package, start_date: '01/01/13', due_date: '31/01/13')
      wp.valid?
      expect(wp.errors[:start_date].size).to eq(0)
      expect(wp.errors[:due_date].size).to eq(0)
    end
  end

  describe 'validations of versions' do
    let(:wp) { FactoryGirl.build(:work_package) }

    it 'validate, that versions of the project can be assigned to workpackages' do
      assignable_version = FactoryGirl.create(:version, project: wp.project)

      wp.fixed_version = assignable_version
      expect(wp).to be_valid
    end

    it 'validate, that the fixed_version belongs to the project the ticket lives in' do
      other_project = FactoryGirl.create(:project)
      non_assignable_version = FactoryGirl.create(:version, project: other_project)

      wp.fixed_version = non_assignable_version

      expect(wp).not_to be_valid
      expect(wp.errors[:fixed_version_id].size).to eq(1)
    end

    it 'validate, that closed or locked versions cannot be assigned' do
      non_assignable_version = FactoryGirl.create(:version, project: wp.project)

      %w{locked closed}.each do |status|
        non_assignable_version.update_attribute(:status, status)

        wp.fixed_version = non_assignable_version
        expect(wp).not_to be_valid
        expect(wp.errors[:fixed_version_id].size).to eq(1)
      end
    end

    it 'does not validate closed and locked versions if validation is skipped' do
      non_assignable_version = FactoryGirl.create(:version, project: wp.project)

      %w{locked closed}.each do |status|
        non_assignable_version.update_attribute(:status, status)

        wp.skip_fixed_version_validation = true
        wp.fixed_version = non_assignable_version
        expect(wp).to be_valid
      end
    end

    it 'validates, that inexistent ids are erroneous' do
      wp.fixed_version_id = 0
      expect(wp).not_to be_valid
    end

    describe 'validations of enabled types' do
      let (:old_type)     { FactoryGirl.create(:type, name: 'old') }

      let (:old_project)  { FactoryGirl.create(:project, types: [old_type]) }
      let (:work_package) do
        FactoryGirl.create(:work_package, project: old_project, type: old_type)
      end

      let (:new_type)     { FactoryGirl.create(:type, name: 'new') }
      let (:new_project)  { FactoryGirl.create(:project, types: [new_type]) }

      it 'validate, that the newly selected type is available for the project the wp lives in' do
        # change type to a type of another project

        work_package.type = new_type

        expect(work_package).not_to be_valid
        expect(work_package.errors[:type_id].size).to eq(1)
      end

      it 'validate, that the selected type is enabled for the project the wp was moved into' do
        work_package.project = new_project

        expect(work_package).not_to be_valid
        expect(work_package.errors[:type_id].size).to eq(1)
      end
    end

    describe 'validations of priority' do
      let (:active_priority) { FactoryGirl.create(:priority) }
      let (:inactive_priority) { FactoryGirl.create(:priority, active: false) }

      let (:wp) { FactoryGirl.create(:work_package) }

      it 'should validate on active priority' do
        wp.priority = active_priority
        expect(wp).to be_valid
      end

      it 'should validate an inactive priority that has been assigned before becoming inactive' do
        wp.priority = active_priority
        wp.save!

        active_priority.active = false
        active_priority.save!
        wp.reload

        expect(wp.priority.active).to be_falsey
        expect(wp).to be_valid
      end

      it 'should not validate on an inactive priority' do
        wp.priority = inactive_priority
        expect(wp).not_to be_valid
        expect(wp.errors[:priority_id].size).to eq(1)
      end
    end

    describe 'validations of category' do
      let (:valid_category) { FactoryGirl.create(:category, project: project1) }
      let (:invalid_category) { FactoryGirl.create(:category, project: project2) }
      let (:project1) { FactoryGirl.create(:project) }
      let (:project2) { FactoryGirl.create(:project) }

      let (:valid_work_package) do
        FactoryGirl.build(:work_package, category: valid_category, project: project1)
      end
      let (:invalid_work_package) do
        FactoryGirl.build(:work_package, category: invalid_category, project: project1)
      end

      it 'should not raise for empty category' do
        valid_work_package.category = nil
        expect(valid_work_package).to be_valid
      end

      let (:idless_category) { FactoryGirl.create(:category, id: nil) }

      it 'should not validate on a missing category_id' do
        wp = FactoryGirl.build(:work_package, category: idless_category, project: project1)
        expect(wp).not_to be_valid
        expect(wp.errors[:category].size).to eq(1)
      end

      it 'should validate on matching project.id' do
        expect(valid_work_package).to be_valid
      end

      it 'should be invalid for incorrect project.id' do
        expect(invalid_work_package).not_to be_valid
        expect(invalid_work_package.errors[:category].size).to eq(1)
      end
    end

    describe 'validations of estimated hours' do
      wp_regular = FactoryGirl.build(:work_package, estimated_hours: 1)
      wp_zero_hours = FactoryGirl.build(:work_package, estimated_hours: 0)
      wp_nil = FactoryGirl.build(:work_package, estimated_hours: nil)
      wp_invalid = FactoryGirl.build(:work_package, estimated_hours: -1)

      it 'should not raise for values > 0' do
        expect(wp_regular).to be_valid
      end

      it 'should not raise for zero hours' do
        expect(wp_zero_hours).to be_valid
      end

      it 'should not raise for nil' do
        expect(wp_nil).to be_valid
      end

      it 'should raise for values < 0' do
        expect(wp_invalid).not_to be_valid
      end
    end
  end
end
