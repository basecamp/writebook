ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include SessionTestHelper

    # Tests assert against the shipped provider table, so a per-install
    # WRITEBOOK_EMBED_PROVIDERS in the shell must not leak in — nor out.
    setup { @embed_providers_before = ENV.delete("WRITEBOOK_EMBED_PROVIDERS") }
    teardown { ENV["WRITEBOOK_EMBED_PROVIDERS"] = @embed_providers_before }
  end
end
