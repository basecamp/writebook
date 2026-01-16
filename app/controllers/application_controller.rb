class ApplicationController < ActionController::Base
  include Authentication, Authorization, VersionHeaders

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  private
    def set_active_storage_url_options
      ActiveStorage::Current.url_options = { protocol: request.protocol, host: request.host, port: request.port }
    end
end
