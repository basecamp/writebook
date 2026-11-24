class AddApprovalCodeDigestToOauthDeviceGrants < ActiveRecord::Migration[8.0]
  def change
    add_column :oauth_device_grants, :approval_code_digest, :string
  end
end
