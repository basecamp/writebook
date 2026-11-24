class Section < ApplicationRecord
  include Leafable

  def searchable_content
    body
  end

  def markable
    body
  end

  def fingerprintable_content
    "#{body}\0#{theme}"
  end
end
