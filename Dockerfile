# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.4.7
FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim as base

# Rails app lives here
WORKDIR /rails

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"

# Install the distribution's current trusted roots rather than the ones frozen into the base image
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y ca-certificates && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Fail the build if either of these withdrawn roots is still where Ruby's OpenSSL looks for
# trusted certificates
RUN ruby -ropenssl -e ' \
    file = ENV[OpenSSL::X509::DEFAULT_CERT_FILE_ENV] || OpenSSL::X509::DEFAULT_CERT_FILE; \
    dir = ENV[OpenSSL::X509::DEFAULT_CERT_DIR_ENV] || OpenSSL::X509::DEFAULT_CERT_DIR; \
    pems = [file, *Dir.glob(File.join(dir, "*"))].select { |path| File.file?(path) } \
      .flat_map { |path| File.read(path).scan(/-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----/m) }; \
    subjects = pems.map { |pem| OpenSSL::X509::Certificate.new(pem).subject.to_s }.uniq; \
    abort "Only #{subjects.size} roots in #{file} and #{dir}" if subjects.size < 100; \
    withdrawn = subjects.grep(%r{/CN=(emSign ECC Root CA - G3|AAA Certificate Services)\z}); \
    abort "Withdrawn roots still trusted: #{withdrawn}" if withdrawn.any?'


# Throw-away build stage to reduce size of final image
FROM --platform=$TARGETPLATFORM base as build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev libvips pkg-config

# Install application gems
COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Copy application code
COPY . .

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile


# Final stage for app image
FROM base

# Install packages needed for deployment
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libsqlite3-0 libvips redis && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

# Set version and revision
ARG APP_VERSION
ENV APP_VERSION=$APP_VERSION
ARG GIT_REVISION
ENV GIT_REVISION=$GIT_REVISION

# Entrypoint prepares the application.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 80 443
CMD ["bin/boot"]
