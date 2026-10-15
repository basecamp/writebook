class Accounts::CustomStylesController < ApplicationController
  allow_unauthenticated_access only: :show
  before_action :ensure_can_administer, :set_account, except: :show

  def show
    if stale? Current.account
      expires_in 1.hour, public: true
      render plain: Current.account&.custom_styles.to_s, content_type: "text/css"
    end
  end

  def edit
  end

  def update
    @account.update!(account_params)
    redirect_to edit_account_custom_styles_url
  end

  private
    def set_account
      @account = Current.account
    end

    def account_params
      params.require(:account).permit(:custom_styles)
    end
end
