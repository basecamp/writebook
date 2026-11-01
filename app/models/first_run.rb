class FirstRun
  ACCOUNT_NAME = "Writebook"

  def self.create!(user_params)
    # Build the administrator, hashing its password, before taking the write lock
    # that a concurrent first run waits on.
    administrator = User.new(user_params.merge(role: :administrator))

    ApplicationRecord.transaction do
      Account.create!(name: ACCOUNT_NAME, embed_providers: EmbedProvider::DEFAULTS)
      administrator.save!
    end

    administrator.tap do |user|
      DemoContent.create_manual(user)
    end
  end
end
