# frozen_string_literal: true

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

module ProjectLifeCycleSteps
  class UpdateSingleContract < BaseContract
    validate :validate_start_after_preceeding_phases

    delegate :project, to: :model

    def writable_attributes = %w[start_date finish_date active]

    def validate_start_after_preceeding_phases
      return unless model.active?
      return unless model.range_set?
      return if start_after_preceding_phases?

      model.errors.add(:date_range, :non_continuous_dates)
    end

    private

    def start_after_preceding_phases?
      preceding_phases
        .select(&:range_set?)
        .all? { valid_dates?(current: model, previous: it) }
    end

    def valid_dates?(current:, previous:)
      current.start_date > previous.finish_date
    end

    def preceding_phases
      project.available_phases.select { it.position < model.position }
    end
  end
end
