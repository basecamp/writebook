class Section < ApplicationRecord
  include Leafable

  def searchable_content
    body
  end

  def to_markdown(title:, url_options: ActiveStorage::Current.url_options)
    [ "## #{title}", body.to_s ].join("\n\n")
  end
end
