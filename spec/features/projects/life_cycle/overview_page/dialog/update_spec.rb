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

require "spec_helper"
require_relative "../shared_context"

RSpec.describe "Edit project phases on project overview page", :js, with_flag: { stages_and_gates: true } do
  include_context "with seeded projects and phases"

  shared_let(:overview) { create :overview, project: }

  let(:overview_page) { Pages::Projects::Show.new(project) }

  let(:activity_page) { Pages::Projects::Activity.new(project) }

  current_user { admin }

  before do
    overview_page.visit_page
  end

  def formatted_date_range(life_cycle)
    if life_cycle.range_set?
      [life_cycle.start_date, life_cycle.finish_date].map { I18n.l(it) }.join("\n-\n")
    else
      "-"
    end
  end

  describe "with the dialog open" do
    context "when all LifeCycleSteps are blank" do
      before do
        Project::Phase.update_all(start_date: nil, finish_date: nil)
      end

      it "shows all the Project::Phases without a value" do
        project_life_cycles.each do |life_cycle|
          dialog = overview_page.open_edit_dialog_for_life_cycle(life_cycle)
          dialog.expect_input(life_cycle.name, value: "")

          dialog.submit # Saving the dialog is successful
          dialog.expect_closed
        end

        project_life_cycles.each do |life_cycle|
          overview_page.within_life_cycle_container(life_cycle) do
            expect(page).to have_text "-"
          end
        end
      end
    end

    context "when all LifeCycleSteps have a value" do
      it "shows all the Project::Phases and updates them correctly" do
        life_cycle_initiating_was = life_cycle_initiating.dup
        life_cycle_planning_was = life_cycle_planning.dup
        life_cycle_executing_was = life_cycle_executing.dup
        life_cycle_closing_was = life_cycle_closing.dup

        # Set a value for life_cycle_initiating
        dialog = overview_page.open_edit_dialog_for_life_cycle(life_cycle_initiating, wait_angular: true)

        dialog.expect_input_for(life_cycle_initiating)

        retry_block do
          # Retrying due to a race condition between filling the input vs submitting the form preview.
          original_dates = [life_cycle_initiating.start_date, life_cycle_initiating.finish_date]
          dialog.set_date_for(values: original_dates)

          page.driver.clear_network_traffic
          dialog.set_date_for(values: [start_date - 1.week, start_date])

          dialog.expect_caption(text: "Duration: 8 working days")
          # Ensure that only 1 ajax request is triggered after setting the date range.
          expect(page.driver.browser.network.traffic.size).to eq(1)
        end

        # Saving the dialog is successful
        dialog.submit
        dialog.expect_closed

        # Sidebar is refreshed with the updated values
        project_life_cycles.each do |life_cycle|
          life_cycle.reload

          overview_page.within_life_cycle_container(life_cycle) do
            expect(page).to have_text formatted_date_range(life_cycle)
          end
        end

        # Clear the value of life_cycle_planning
        dialog = overview_page.open_edit_dialog_for_life_cycle(life_cycle_planning, wait_angular: true)

        dialog.expect_input_for(life_cycle_planning)
        dialog.clear_date

        # Saving the dialog is successful
        dialog.submit
        dialog.expect_closed

        # Sidebar is refreshed with the updated values
        project_life_cycles.each do |life_cycle|
          life_cycle.reload

          overview_page.within_life_cycle_container(life_cycle) do
            expect(page).to have_text formatted_date_range(life_cycle)
          end
        end

        activity_page.visit!

        activity_page.show_details

        activity_page.within_journal(number: 1) do
          activity_page.expect_activity("Initiating changed from " \
                                        "#{I18n.l life_cycle_initiating_was.start_date} - " \
                                        "#{I18n.l life_cycle_initiating_was.finish_date} to " \
                                        "#{I18n.l life_cycle_initiating.start_date} - " \
                                        "#{I18n.l life_cycle_initiating.finish_date}")

          activity_page.expect_activity("Planning date deleted " \
                                        "#{I18n.l life_cycle_planning_was.start_date} - " \
                                        "#{I18n.l life_cycle_planning_was.finish_date}")

          activity_page.expect_activity("Executing changed from " \
                                        "#{I18n.l life_cycle_executing_was.start_date} - " \
                                        "#{I18n.l life_cycle_executing_was.finish_date} to " \
                                        "#{I18n.l life_cycle_executing.start_date} - " \
                                        "#{I18n.l life_cycle_executing.finish_date}")

          activity_page.expect_activity("Closing changed from " \
                                        "#{I18n.l life_cycle_closing_was.start_date} - " \
                                        "#{I18n.l life_cycle_closing_was.finish_date} to " \
                                        "#{I18n.l life_cycle_closing.start_date} - " \
                                        "#{I18n.l life_cycle_closing.finish_date}")
        end
      end
    end

    context "when there is an invalid custom field on the project (Regression#60666)" do
      let(:custom_field) { create(:string_project_custom_field, is_required: true, is_for_all: true) }

      before do
        project.custom_field_values = { custom_field.id => nil }
        project.save(validate: false)
      end

      it "allows saving and closing the dialog without the custom field validation to interfere" do
        dialog = overview_page.open_edit_dialog_for_life_cycle(life_cycle_initiating, wait_angular: true)

        # Saving the dialog is successful
        dialog.submit
        dialog.expect_closed
      end
    end
  end
end
