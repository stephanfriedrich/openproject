#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
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
# See COPYRIGHT and LICENSE files for more details.
#++

FactoryBot.define do
  factory :project_phase_definition, class: "Project::PhaseDefinition" do
    sequence(:name) { |n| "Phase definition #{n}" }
    sequence(:position)

    color

    trait :with_start_gate do
      start_gate { true }
      sequence(:start_gate_name) { |n| "Phase definition Start Gate #{n}" }
    end

    trait :with_finish_gate do
      finish_gate { true }
      sequence(:finish_gate_name) { |n| "Phase definition Finish Gate #{n}" }
    end

    trait :with_gates do
      start_gate { true }
      finish_gate { true }
      sequence(:start_gate_name) { |n| "Phase definition Start Gate #{n}" }
      sequence(:finish_gate_name) { |n| "Phase definition Finish Gate #{n}" }
    end
  end
end
