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
  class UpdateSingleService < ::BaseServices::Update
    def after_validate(*)
      set_duration

      super
    end

    def after_perform(*)
      reschedule_following_phases if model.range_set?

      super
    end

    private

    def default_contract_class = ProjectLifeCycleSteps::UpdateSingleContract

    def set_duration
      model.duration = calculate_duration
    end

    def calculate_duration
      return nil unless model.range_set?

      Day.working.from_range(from: model.start_date, to: model.finish_date).count
    end

    def reschedule_following_phases
      from = initial_reschedule_date

      following_phases.each do |phase|
        next unless phase.range_set?
        next unless phase.duration # not updated using service that sets duration

        date_range = calculate_date_range(from, duration: phase.duration)
        next unless date_range

        next unless phase.update(date_range:)

        from = date_range.end + 1
      end
    end

    def initial_reschedule_date
      model.active? ? model.finish_date + 1 : model.start_date
    end

    def following_phases
      model.project.available_phases.select { it.position > model.position }
    end

    def calculate_date_range(from, duration:)
      days = working_days_from(from, count: duration)

      days.first.date..days.last.date if days.length == duration
    end

    def working_days_from(from, count:)
      days = Day.working.from_range(from:, to: from.next_year).first(count)
      if days.length < count && !days.empty?
        years = count.ceildiv(days.length) + 1
        days = Day.working.from_range(from:, to: from.next_year(years)).first(count)
      end
      days
    end
  end
end
