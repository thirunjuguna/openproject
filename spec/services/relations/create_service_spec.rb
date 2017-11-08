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

describe Relations::CreateService do
  let(:work_package1_start_date) { nil }
  let(:work_package1_due_date) { Date.today }
  let(:work_package2_start_date) { nil }
  let(:work_package2_due_date) { nil }

  let(:follows_relation) { false }
  let(:delay) { 3 }

  let(:work_package1) do
    FactoryGirl.build_stubbed(:work_package,
                              due_date: work_package1_due_date,
                              start_date: work_package1_start_date)
  end
  let(:work_package2) do
    FactoryGirl.build_stubbed(:work_package,
                              due_date: work_package2_due_date,
                              start_date: work_package2_start_date)
  end
  let(:instance) do
    described_class.new(user: user)
  end
  let(:relation) do
    relation = Relation.new attributes

    allow(relation)
      .to receive(:follows?)
      .and_return(follows_relation)

    relation
  end
  let(:attributes) do
    {
      to: work_package1,
      from: work_package2,
      delay: delay
    }
  end

  let(:user) { FactoryGirl.build_stubbed(:user) }
  let(:model_valid) { true }
  let(:contract_valid) { true }
  let(:contract) { double('contract') }

  subject do
    instance.call(relation)
  end

  before do
    allow(relation)
      .to receive(:save)
      .and_return(model_valid)

    allow(Relations::CreateContract)
      .to receive(:new)
      .with(relation, user)
      .and_return(contract)
    allow(contract)
      .to receive(:validate)
      .and_return(contract_valid)
  end

  context 'when all valid and it is a follows relation' do
    let(:set_schedule_service) { double('set schedule service') }
    let(:set_schedule_result) do
      double('set schedule result',
             success?: true,
             result: [work_package2],
             success: true,
             errors: [])
    end

    let(:follows_relation) { true }

    before do
      expect(WorkPackages::SetScheduleService)
        .to receive(:new)
        .with(user: user, work_packages: [work_package1])
        .and_return(set_schedule_service)

      expect(set_schedule_service)
        .to receive(:call)
        .and_return(set_schedule_result)

      set_schedule_result.result.each do |wp|
        expect(wp)
          .to receive(:save)
          .and_return(true)
      end

      allow(set_schedule_result)
        .to receive(:success=)
    end

    it 'is successful' do
      expect(subject)
        .to be_success
    end

    it 'returns the relation and the altered successor' do
      expect(subject.result)
        .to eql [relation, work_package2]
    end
  end

  context 'when all is valid and it is not a follows relation' do
    it 'is successful' do
      expect(subject)
        .to be_success
    end

    it 'returns the relation' do
      expect(subject.result)
        .to eql [relation]
    end
  end

  context 'when the contract is invalid' do
    let(:contract_valid) { false }
    let(:contract_errors) { double('contract_errors') }

    before do
      allow(contract)
        .to receive(:errors)
        .and_return(contract_errors)
    end

    it 'is unsuccessful' do
      expect(subject)
        .to be_failure
    end

    it "returns the contract's errors" do
      expect(subject.errors)
        .to eql [contract_errors]
    end
  end

  context 'when the model is invalid' do
    let(:model_valid) { false }
    let(:model_errors) { double('model_errors') }

    before do
      allow(relation)
        .to receive(:errors)
        .and_return(model_errors)
    end

    it 'is unsuccessful' do
      expect(subject)
        .to be_failure
    end

    it "returns the model's errors" do
      expect(subject.errors)
        .to eql [model_errors]
    end
  end
end
