class FirstRunsController < ApplicationController
  allow_unauthenticated_access

  before_action :prevent_running_after_setup

  def show
    @user = User.new
  end

  def create
    user = FirstRun.create!(user_params)
    start_new_session_for user

    redirect_to root_url
  rescue ActiveRecord::RecordNotUnique
    redirect_to root_url
  end

  private
    def prevent_running_after_setup
      redirect_to root_url if User.any?
    end

    def user_params
      params.require(:user).permit(:name, :email_address, :password)
    end
end
