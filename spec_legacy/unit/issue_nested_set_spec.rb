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
require_relative '../legacy_spec_helper'

describe 'IssueNestedSet', type: :model do
  include MiniTest::Assertions # refute

  fixtures :all

  self.use_transactional_fixtures = false

  before do
    WorkPackage.delete_all
  end

  it 'moving to a descendant should not validate' do
    parent1 = create_issue!
    child =   create_issue!(parent: parent1)
    grandchild = create_issue!(parent: child)

    child.reload
    child.parent = grandchild
    assert !child.save
    refute_empty child.errors[:parent]
  end

  it 'should project copy should copy issue tree' do
    Project.delete_all # make sure unqiue identifiers
    p = Project.create!(name: 'Tree copy', identifier: 'tree-copy', type_ids: [1, 2])
    i1 = create_issue!(project_id: p.id, subject: 'i1')
    i2 = create_issue!(project_id: p.id, subject: 'i2', parent: i1)
    create_issue!(project_id: p.id, subject: 'i3', parent: i1)
    create_issue!(project_id: p.id, subject: 'i4', parent: i2)
    create_issue!(project_id: p.id, subject: 'i5')
    c = Project.new(name: 'Copy', identifier: 'copy', type_ids: [1, 2])
    c.copy(p, only: 'work_packages')
    c.reload

    assert_equal 5, c.work_packages.count
    ic1, ic2, ic3, ic4, ic5 = c.work_packages.reorder('subject')
    assert ic1.root?
    assert_equal ic1, ic2.parent
    assert_equal ic1, ic3.parent
    assert_equal ic2, ic4.parent
    assert ic5.root?
  end

  # Helper that creates an issue with default attributes
  def create_issue!(attributes = {})
    (i = WorkPackage.new.tap do |wp|
      attr = { project_id: 1, type_id: 1, author_id: 1, subject: 'test' }.merge(attributes)
      wp.attributes = attr
    end).save!
    i
  end
end
