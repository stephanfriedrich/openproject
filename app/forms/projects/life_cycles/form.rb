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
module Projects::LifeCycles
  class Form < ApplicationForm
    form do |f|
      multi_value_life_cycle_input(f)
    end

    private

    def qa_field_name
      "life-cycle-step-#{model.id}"
    end

    def base_input_attributes
      {
        label:,
        leading_visual: { icon: :calendar },
        datepicker_options: {
          inDialog: Overviews::ProjectPhases::EditDialogComponent::DIALOG_ID,
          data: { action: "change->overview--project-life-cycles-form#previewForm" }
        },
        wrapper_data_attributes: {
          "qa-field-name": qa_field_name
        }
      }
    end

    def multi_value_life_cycle_input(form)
      value = [model.start_date, model.finish_date].compact.join(" - ")

      input_attributes = { name: :date_range, value: }
      if model.duration
        input_attributes[:caption] =
          I18n.t("project_phase.duration", count: model.duration)
      end

      form.range_date_picker **base_input_attributes, **input_attributes
    end

    def label
      helpers.safe_join([icon, " ", model.name])
    end

    def icon
      render Primer::Beta::Octicon.new(icon: :"op-phase", classes: icon_color_class)
    end

    def icon_color_class
      helpers.hl_inline_class("project_phase_definition", model.definition)
    end
  end
end
