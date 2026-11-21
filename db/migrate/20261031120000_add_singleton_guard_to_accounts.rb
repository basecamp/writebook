class AddSingletonGuardToAccounts < ActiveRecord::Migration[8.2]
  def change
    add_column :accounts, :singleton_guard, :integer, default: 0, null: false

    # An install may already hold more than one account, from a repeated first
    # run. Keep them all, but leave the guard on the first one only, the account
    # the app uses, so the unique index can be built.
    up_only do
      execute "UPDATE accounts SET singleton_guard = id WHERE id > (SELECT MIN(id) FROM accounts)"
    end

    add_index :accounts, :singleton_guard, unique: true
  end
end
