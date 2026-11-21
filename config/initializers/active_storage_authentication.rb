# Active Storage mounts its endpoints on framework controllers that inherit from
# ActiveStorage::BaseController, so they never pass through ApplicationController's
# require_authentication.
#
# Writebook uploads attachments through ActionText::Markdown::UploadsController
# as an ordinary multipart POST and does not use direct uploads at all, leaving
# the direct-upload write endpoints reachable by anyone who can read a public
# page. Require a valid Writebook session before an anonymous caller can
# allocate a Blob or persist bytes to disk.
#
# Reads are authorized against the book a blob belongs to. Every byte Writebook
# serves passes through the disk service's show action, so that is where the
# check has to be; the redirect endpoints check too, so a revoked URL fails at
# its first hop. Writebook never links to the proxy endpoints, which mark every
# response publicly cacheable forever, so they are closed rather than authorized.
Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.include ActiveStorageAuthentication
  ActiveStorage::DirectUploadsController.before_action :require_active_storage_authentication

  ActiveStorage::DiskController.include ActiveStorageAuthentication
  ActiveStorage::DiskController.before_action :require_active_storage_authentication, only: :update

  ActiveStorage::DiskController.class_eval do
    include ActiveStorageAuthorization
    before_action :require_readable_blob, only: :show

    private
      def blob_for_authorization
        ActiveStorage::Blob.find_by(key: decode_verified_key&.dig(:key))
      end
  end

  [ ActiveStorage::Blobs::RedirectController, ActiveStorage::Representations::RedirectController ].each do |controller|
    controller.include ActiveStorageAuthorization
    controller.before_action :require_readable_blob
  end

  [ ActiveStorage::Blobs::ProxyController, ActiveStorage::Representations::ProxyController ].each do |controller|
    controller.prepend_before_action { head :not_found }
  end
end
