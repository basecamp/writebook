class Users::ApiTokensController < ApplicationController
  include UserScoped

  before_action :ensure_current_user

  def create
    @api_token = @user.api_tokens.generate!(name: api_token_name)
    response.headers["Cache-Control"] = "no-store"
  end

  def destroy
    @user.api_tokens.find(params[:id]).destroy
    redirect_to edit_user_profile_url(@user)
  end

  private
    def api_token_name
      params.dig(:api_token, :name).to_s.strip.presence || "API token"
    end
end
