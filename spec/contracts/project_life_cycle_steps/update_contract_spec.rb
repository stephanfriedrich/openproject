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
require "contracts/shared/model_contract_shared_context"

RSpec.describe ProjectLifeCycleSteps::UpdateContract do
  include_context "ModelContract shared context"

  let(:user) { build_stubbed(:user) }

  subject(:contract) { described_class.new(phase, user) }

  context "with authorized user" do
    let(:phase) { build_stubbed(:project_phase) }
    let(:project) { phase.project }
    let(:date) { Date.current }

    before do
      mock_permissions_for(user) do |mock|
        mock.allow_in_project(:edit_project_phases, project:)
      end
    end

    it_behaves_like "contract is valid"
    it_behaves_like "contract reuses the model errors"

    context "when phase is invalid" do
      let(:phase) do
        build_stubbed(:project_phase, start_date: date + 1, finish_date: date - 1)
      end

      it_behaves_like "contract is invalid", date_range: :start_date_must_be_before_finish_date
    end

    context "when trying to change extra attributes" do
      before do
        phase.duration = 42
      end

      it_behaves_like "contract is invalid", duration: :error_readonly
    end

    describe "#validate_start_after_preceeding_phases" do
      def build_phase(**) = build_stubbed(:project_phase, project:, **)

      let(:project) { build_stubbed(:project) }
      let(:phases) { [preceding, phase, following] }
      let(:phase) { build_phase(date_range:, active:) }
      let(:preceding) { build_phase(date_range: preceding_date_range) }
      let(:following) { build_phase(date_range: following_date_range) }
      let(:active) { true }
      let(:date_range) { date - 1..date + 1 }
      let(:preceding_date_range) { date - 6..date - 5 }
      let(:following_date_range) { date + 5..date + 6 }

      before do
        allow(project).to receive(:available_phases).and_return(phases)
      end

      context "with successive non overlapping dates" do
        it_behaves_like "contract is valid"
      end

      context "without dates" do
        let(:date_range) { nil }

        it_behaves_like "contract is valid"
      end

      context "with preceding phase overlapping with start" do
        let(:preceding_date_range) { date - 6..date - 1 }

        it_behaves_like "contract is invalid", date_range: :non_continuous_dates

        context "when inactive" do
          let(:active) { false }

          it_behaves_like "contract is valid"
        end
      end

      context "with preceding phase following this" do
        let(:preceding_date_range) { date + 2..date + 4 }

        it_behaves_like "contract is invalid", date_range: :non_continuous_dates

        context "when inactive" do
          let(:active) { false }

          it_behaves_like "contract is valid"
        end
      end

      context "with preceding phase without dates" do
        let(:preceding_date_range) { nil }

        it_behaves_like "contract is valid"
      end

      context "with following phase overlapping with start" do
        let(:following_date_range) { date - 1..date + 6 }

        it_behaves_like "contract is valid"
      end

      context "with following phase preceding this" do
        let(:following_date_range) { date - 4..date - 2 }

        it_behaves_like "contract is valid"
      end
    end
  end

  context "with unauthorized user" do
    let(:phase) { build_stubbed(:project_phase) }

    it_behaves_like "contract user is unauthorized"
  end
end
