require "test_helper"

class FirstRunsConcurrencyTest < ActionDispatch::IntegrationTest
  # Give each request its own connection, so the database settles the race as it
  # does in production, not a test transaction they would all share.
  self.use_transactional_tests = false

  setup do
    Book.destroy_all
    User.destroy_all
    Account.destroy_all
  end

  teardown do
    Book.destroy_all
    User.destroy_all
    Account.destroy_all
  end

  test "concurrent first runs create one account and one administrator" do
    requests = 5
    barrier = Concurrent::CyclicBarrier.new(requests)
    path = first_run_path

    requests.times.map do |i|
      Thread.new do
        session = open_session
        barrier.wait

        session.post path, params: \
          { user: { name: "Person #{i}", email_address: "person#{i}@example.com", password: "secret123456" } }
      rescue ActiveRecord::StatementTimeout
        # A request can give up waiting on the winner's write lock. That's fine:
        # what matters is what got written, not how each loser was answered.
      end
    end.each(&:join)

    assert_equal 1, Account.count
    assert_equal 1, User.administrator.count
  end
end
