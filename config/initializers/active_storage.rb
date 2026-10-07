# Disk URLs are stable (see the public flag in config/storage.yml), so browsers can
# keep what they've fetched. Only browsers, though: each request is authorized
# against the book the file belongs to, and a shared cache would keep serving a
# book's images to everyone after it was unpublished.
ActiveSupport.on_load(:active_storage_blob) do
  ActiveStorage::DiskController.after_action only: :show do
    expires_in 1.year, public: false
  end
end
