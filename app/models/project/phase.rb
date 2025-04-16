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

class Project::Phase < ApplicationRecord
  belongs_to :project, optional: false, inverse_of: :available_phases
  belongs_to :definition,
             optional: false,
             class_name: "Project::PhaseDefinition"
  has_many :work_packages, inverse_of: :project_phase, dependent: :nullify

  validate :validate_date_range

  delegate :name,
           :position,
           :start_gate_name,
           :finish_gate_name,
           :start_gate?,
           :finish_gate?,
           to: :definition

  attr_readonly :definition_id

  scope :active, -> { where(active: true) }

  class << self
    def visible(user = User.current)
      allowed_projects = Project.allowed_to(user, :view_project_phases)
      active.where(project: allowed_projects)
    end
  end

  def date_range=(range)
    case range
    when String
      self.start_date, self.finish_date = range.split(" - ")
      self.finish_date ||= start_date # Allow single dates as range
    when Range
      fail ArgumentError, "Only inclusive ranges expected" if range.exclude_end?

      self.start_date = range.begin
      self.finish_date = range.end
    when nil
      self.start_date = self.finish_date = nil
    else
      fail ArgumentError, "Expected String, Range or nil"
    end
  end

  def range_set?
    start_date? && finish_date?
  end

  def not_set?
    !range_set?
  end

  def range_incomplete?
    start_date? ^ finish_date?
  end

  def validate_date_range
    errors.add(:date_range, :start_date_must_be_before_finish_date) if range_set? && (start_date > finish_date)
  end
end
