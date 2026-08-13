class Users::BearerKeysController < ApplicationController
  include UserScoped

  before_action :ensure_current_user

  def create
    @user.regenerate_bearer_key
    redirect_to edit_user_profile_url(@user)
  end
end
