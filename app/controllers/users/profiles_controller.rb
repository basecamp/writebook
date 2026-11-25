class Users::ProfilesController < ApplicationController
  include UserScoped

  before_action :ensure_current_user, only: %i[ edit update ]
  before_action :ensure_current_password_confirms_sign_in_changes, only: :update, unless: -> { authenticated_by.session? }

  def show
  end

  def edit
  end

  def update
    respond_to do |format|
      format.html do
        @user.update!(user_params)
        redirect_to users_url
      end

      format.json do
        if @user.update(user_params)
          render :edit
        else
          render_errors @user.errors.full_messages
        end
      rescue ActiveRecord::RecordNotUnique
        render_errors [ "Name or email address is already taken" ]
      end
    end
  end

  private
    # A bearer token that could change the email address or password could
    # sign in as the user and keep the account after the token is revoked.
    def ensure_current_password_confirms_sign_in_changes
      if changes_sign_in? && !@user.authenticate(params.dig(:user, :current_password).to_s)
        render_errors [ "Current password is needed to change the email address or password, or it's wrong" ]
      end
    end

    def changes_sign_in?
      user_params[:password].present? || (user_params.key?(:email_address) && user_params[:email_address] != @user.email_address)
    end

    def render_errors(errors)
      respond_to do |format|
        format.html { head :unprocessable_entity }
        format.json { render json: { errors: errors }, status: :unprocessable_entity }
      end
    end

    def user_params
      params.require(:user).permit(:name, :email_address, :password)
    end
end
