require "application_system_test_case"

class DeviceSignInTest < ApplicationSystemTestCase
  setup do
    @grant = Oauth::DeviceGrant.generate!
    sign_in "kevin@example.com"
  end

  test "approving a device shows the approval code, but only once the box is ticked" do
    visit oauth_device_verification_url(user_code: @grant.formatted_user_code)

    click_button "Connect"
    assert_text "confirm that you requested this code"
    assert @grant.reload.pending?

    check "initiation_confirmed"
    assert_checked_field "initiation_confirmed"
    click_button "Connect"

    assert_text "Device connected"
    assert @grant.reload.approved?

    # Read the code by script rather than through an element handle: the
    # page swap after a plain form submit can detach a handle mid-call.
    assert_match(/\A[A-Z2-9]{4}-[A-Z2-9]{4}\z/, evaluate_script("document.getElementById('approval_code').textContent.trim()"))
  end

  test "entering a code by hand, then denying it" do
    visit oauth_device_verification_url

    fill_in "user_code", with: @grant.formatted_user_code
    click_button "Continue"
    assert_text "Connect this device?"

    click_button "Deny"
    assert_text "Device denied"
    assert @grant.reload.denied?
  end
end
