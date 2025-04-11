# frozen_string_literal: true

class AddDurationToProjectPhases < ActiveRecord::Migration[8.0]
  def change
    add_column :project_phases, :duration, :integer, null: true
    add_column :project_phase_journals, :duration, :integer, null: true
  end
end
