# Active Storage mounts its direct-upload write endpoints
# (POST /rails/active_storage/direct_uploads and the disk-service PUT) on
# framework controllers that inherit from ActiveStorage::BaseController, so
# they never pass through ApplicationController's require_authentication.
# Writebook uploads attachments through ActionText::Markdown::UploadsController
# as an ordinary multipart POST and does not use direct uploads at all, leaving
# these endpoints reachable by anyone who can read a public page. Require a
# valid Writebook session before an anonymous caller can allocate a Blob or
# persist bytes to disk.
Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.include ActiveStorageAuthentication
  ActiveStorage::DirectUploadsController.before_action :require_active_storage_authentication

  ActiveStorage::DiskController.include ActiveStorageAuthentication
  ActiveStorage::DiskController.before_action :require_active_storage_authentication, only: :update
end
