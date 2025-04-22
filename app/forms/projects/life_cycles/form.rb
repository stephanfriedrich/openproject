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
module Projects::LifeCycles
  class Form < ApplicationForm
    form do |f|
      f.group(layout: :horizontal) do |horizontal_form|
        start_date_input(horizontal_form)
        finish_date_input(horizontal_form)
        duration_input(horizontal_form)
      end
    end

    private

    def qa_field_name
      "life-cycle-step-#{model.id}"
    end

    def datepicker_attributes
      {
        inset: true,
        datepicker_options: {
          inDialog: Overviews::ProjectPhases::EditDialogComponent::DIALOG_ID,
          data: { action: "change->overview--project-life-cycles-form#previewForm" }
        },
        wrapper_data_attributes: {
          "qa-field-name": qa_field_name
        }
      }
    end

    def start_date_input(form)
      input_attributes = { name: :start_date, label: attribute_name(:start_date) }
      form.text_field **datepicker_attributes, **input_attributes
    end

    def finish_date_input(form)
      input_attributes = { name: :finish_date, label: attribute_name(:finish_date) }
      form.text_field **datepicker_attributes, **input_attributes
    end

    def duration_input(form)
      input_attributes = {
        name: :duration,
        label: attribute_name(:duration),
        type: :number,
        inset: true,
        value: model.duration,
        trailing_visual: { text: { text: I18n.t("datetime.units.day", count: model.duration) } }
      }
      # binding.pry
      form.text_field **input_attributes
    end
  end
end
