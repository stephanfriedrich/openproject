# frozen_string_literal: true

class DisallowNullInProjectPhasesReferences < ActiveRecord::Migration[8.0]
  def change
    reversible do |direction|
      direction.up do
        execute <<-SQL.squish
          DELETE FROM project_phases WHERE project_id IS NULL OR definition_id IS NULL
        SQL
      end
    end

    change_table(:project_phases, bulk: true) do |t|
      t.change_null :project_id, false
      t.change_null :definition_id, false
    end
  end
end
