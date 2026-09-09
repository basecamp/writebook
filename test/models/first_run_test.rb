require "test_helper"

class FirstRunTest < ActiveSupport::TestCase
  setup do
    Book.destroy_all
    User.destroy_all
    Account.destroy_all
  end

  test "creating makes first user an administrator" do
    user = create_first_run_user
    assert user.administrator?
  end

  test "creates an account" do
    assert_changes -> { Account.count }, +1 do
      create_first_run_user
    end
  end

  test "starts a new install on the curated embed providers" do
    create_first_run_user

    assert_equal EmbedProvider::DEFAULTS, Account.sole.embed_providers
    assert EmbedProvider.configured?
    assert EmbedProvider.allows?("https://www.youtube.com/embed/abc")
    assert_not EmbedProvider.allows?("https://anything.example/embed/abc")
  end

  test "an install upgraded from before the setting stays permissive" do
    Account.create!(name: "Upgraded")

    assert_nil Account.sole.embed_providers
    assert_not EmbedProvider.configured?
  end

  test "creates a demo book" do
    assert_changes -> { Book.count }, to: 1 do
      create_first_run_user
    end

    book = Book.first

    assert book.editable?(user: User.first)
    assert book.cover.attached?
    assert book.leaves.any?
  end

  private
    def create_first_run_user
      FirstRun.create!({ name: "User", email_address: "user@example.com", password: "secret123456" })
    end
end
