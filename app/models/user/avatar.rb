module User::Avatar
  extend ActiveSupport::Concern

  included do
    has_one_attached :avatar
  end

  class_methods do
    def from_avatar_token(sid)
      find_signed!(sid, purpose: :avatar)
    end
  end

  def avatar_token
    signed_id(purpose: :avatar)
  end
end
