module User::Role
  extend ActiveSupport::Concern

  included do
    enum role: %i[ member administrator ]
  end

  def can_administer?
    administrator?
  end
end
