# Disable unfuzzed libvips operations.
#
# Reference the Active Storage transformer to ensure Vips is loaded before we block operations.
ActiveStorage::Transformers::Vips
Vips.block_untrusted(true)
Vips.block("VipsForeignLoadOpenslide", true) # prevent sqlite segfault in forked parallel workers
Rails.application.config.active_storage.variable_content_types -=
    %w[ image/bmp image/vnd.microsoft.icon image/vnd.adobe.photoshop ]
