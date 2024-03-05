module HeadHelper
  def direct_uploads_meta_tag
    tag.meta name: "direct-uploads-url", content: rails_direct_uploads_url
  end
end
