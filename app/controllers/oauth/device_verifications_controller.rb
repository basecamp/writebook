# RFC 8628 §3.3: the browser side of the device flow, where a signed-in user
# enters the code their CLI displayed and approves or denies it. Approval is
# update, denial is destroy — either way the CLI's next poll learns the answer.
class Oauth::DeviceVerificationsController < ApplicationController
  # The coarse limit on the device-facing endpoints doesn't cover this
  # controller, which would otherwise be an unthrottled brute-force surface
  # for guessing user codes.
  rate_limit to: 30, within: 1.minute, with: -> { render_rate_limit_exceeded }

  before_action :set_grant, except: :show

  def show
    if params[:user_code].present?
      if @grant = Oauth::DeviceGrant.find_pending_by_user_code(params[:user_code])
        render :confirm
      else
        reject_code
      end
    end
  end

  def create
    if @grant
      render :confirm
    else
      reject_code
    end
  end

  def update
    if @grant.nil?
      reject_code
    # RFC 8628 §5.4: a device code doesn't authenticate the program that
    # requested it — anyone can start a device flow and lure a signed-in user
    # to its verification link. Approval requires the user's explicit
    # affirmation that they initiated this sign-in. Denial stays
    # affirmation-free: declining is always safe.
    elsif params[:initiation_confirmed].blank?
      @error = "To connect, confirm that you requested this code."
      render :confirm
    elsif @grant.approve!(Current.user)
      render :approved
    else
      reject_code
    end
  end

  def destroy
    if @grant&.deny!
      render :denied
    else
      reject_code
    end
  end

  private
    def set_grant
      @grant = Oauth::DeviceGrant.find_pending_by_user_code(params[:user_code])
    end

    def reject_code
      @error = "That code is invalid or has expired. Check your terminal and try again."
      render :show, status: :unprocessable_entity
    end

    def render_rate_limit_exceeded
      response.headers["Retry-After"] = "60"
      @error = "Too many attempts. Please wait a minute and try again."
      render :show, status: :too_many_requests
    end
end
