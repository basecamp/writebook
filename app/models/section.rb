class Section < ApplicationRecord
  include Leafable

  def searchable_content
    body
  end

  def to_markdown
    "# #{body}"
  end
end
