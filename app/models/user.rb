class User < ApplicationRecord
  include Avatar, Role

  has_many :sessions, dependent: :destroy

  scope :active, -> { where(active: true) }

  has_secure_password validations: false
end
