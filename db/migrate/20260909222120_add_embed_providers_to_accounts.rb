class AddEmbedProvidersToAccounts < ActiveRecord::Migration[8.2]
  def change
    add_column :accounts, :embed_providers, :text
  end
end
