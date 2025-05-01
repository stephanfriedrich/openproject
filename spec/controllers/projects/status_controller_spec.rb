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

require "rails_helper"

RSpec.describe Projects::StatusController do
  shared_let(:user) { create(:admin) }
  current_user { user }

  let(:project) { build_stubbed(:project) }
  let(:service_result) { ServiceResult.success(result: project) }

  before do
    allow(Project)
      .to receive(:find)
            .with(project.identifier)
            .and_return(project)

    update_service = instance_double(Projects::UpdateService, call: service_result)

    allow(Projects::UpdateService)
      .to receive(:new)
            .with(user:, model: project)
            .and_return(update_service)
  end

  describe "PUT #update" do
    context "when service call succeeds" do
      context "with valid status_code param" do
        context "with a text/html request" do
          it "redirects back or to project show" do
            put :update, params: { project_id: project, status_code: :foo }

            expect(response).to redirect_to project_path(project)
            expect(flash[:notice]).to eq I18n.t(:notice_successful_update)
          end
        end

        context "with a turbo stream request" do
          it "renders turbo streams updating Projects::StatusButtonComponent and flash action" do
            put :update, params: { project_id: project, status_code: :foo }, format: :turbo_stream

            expect(response).to be_successful
            expect(assigns(:project)).to eq project
            expect(response).to have_turbo_stream action: "update", target: "projects-status-button-component"
            expect(response).to have_turbo_stream action: "flash", target: "op-primer-flash-component"
          end
        end
      end

      context "with valid empty status_code param" do
        context "when service call succeeds" do
          context "with a text/html request" do
            it "redirects back or to project show" do
              put :update, params: { project_id: project, status_code: "" }

              expect(response).to redirect_to project_path(project)
              expect(flash[:notice]).to eq I18n.t(:notice_successful_update)
            end
          end

          context "with a turbo stream request" do
            it "renders turbo streams updating Projects::StatusButtonComponent and flash action" do
              put :update, params: { project_id: project, status_code: "" }, format: :turbo_stream

              expect(response).to be_successful
              expect(assigns(:project)).to eq project
              expect(response).to have_turbo_stream action: "update", target: "projects-status-button-component"
              expect(response).to have_turbo_stream action: "flash", target: "op-primer-flash-component"
            end
          end
        end
      end
    end

    context "when service call fails" do
      let(:service_result) { ServiceResult.failure(result: project, message: "Custom Field 1 must not be blank") }

      context "with a text/html request" do
        it "redirects back or to project show" do
          put :update, params: { project_id: project, status_code: :foo }

          expect(response).to redirect_to project_path(project)
          expect(flash[:error]).to start_with I18n.t(:notice_unsuccessful_update_with_reason, reason: "")
        end
      end

      context "with a turbo stream request" do
        it "renders turbo stream flash action" do
          put :update, params: { project_id: project, status_code: :foo }, format: :turbo_stream

          expect(response).not_to be_successful
          expect(response).to have_http_status :unprocessable_entity
          expect(assigns(:project)).to eq project
          expect(response).to have_turbo_stream action: "flash", target: "op-primer-flash-component"
        end
      end
    end

    context "with invalid params" do
      it "invalid params" do
        put :update, params: { project_id: project, not_status_code: "something" }, format: :turbo_stream

        expect(response).not_to be_successful
        expect(response).to have_http_status :bad_request
      end
    end
  end

  describe "DELETE #destroy" do
    context "when service call succeeds" do
      context "with a text/html request" do
        it "redirects back or to project show" do
          delete :destroy, params: { project_id: project }

          expect(response).to redirect_to project_path(project)
          expect(flash[:notice]).to eq I18n.t(:notice_successful_update)
        end
      end

      context "with a turbo stream request" do
        it "renders turbo streams updating Projects::StatusButtonComponent and flash action" do
          delete :destroy, params: { project_id: project }, format: :turbo_stream

          expect(response).to be_successful
          expect(assigns(:project)).to eq project
          expect(response).to have_turbo_stream action: "update", target: "projects-status-button-component"
          expect(response).to have_turbo_stream action: "flash", target: "op-primer-flash-component"
        end
      end
    end

    context "when service call fails" do
      let(:service_result) { ServiceResult.failure(result: project, message: "Custom Field 1 must not be blank") }

      context "with a text/html request" do
        it "redirects back or to project show" do
          delete :destroy, params: { project_id: project }

          expect(response).to redirect_to project_path(project)
          expect(flash[:error]).to start_with I18n.t(:notice_unsuccessful_update_with_reason, reason: "")
        end
      end

      context "with a turbo stream request" do
        it "renders turbo stream flash action" do
          delete :destroy, params: { project_id: project }, format: :turbo_stream

          expect(response).not_to be_successful
          expect(response).to have_http_status :unprocessable_entity
          expect(assigns(:project)).to eq project
          expect(response).to have_turbo_stream action: "flash", target: "op-primer-flash-component"
        end
      end
    end
  end
end
