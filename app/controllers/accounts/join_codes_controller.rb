class Accounts::JoinCodesController < ApplicationController
  before_action :ensure_can_administer

  def create
    Current.account.reset_join_code

    respond_to do |format|
      format.html { redirect_to users_url }
      format.json { render json: { join_url: join_url(Current.account.join_code) } }
    end
  end
end
