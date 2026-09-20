Rails.application.config.app_version = ENV.fetch("APP_VERSION") do
  version_file = Rails.root.join("VERSION")
  if version_file.exist?
    version_file.read.strip
  else
    `git describe --tags --always 2>/dev/null`.strip.presence || "0"
  end
end
Rails.application.config.git_revision = ENV["GIT_REVISION"]
