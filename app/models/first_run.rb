class FirstRun
  def self.create!(user_params)
    User.create! user_params.merge(role: :administrator)
  end
end
