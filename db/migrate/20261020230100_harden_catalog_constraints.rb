class HardenCatalogConstraints < ActiveRecord::Migration[7.1]
  # The CSV importers identify stores by address and products by name, so
  # those values must be present and unique for a lookup to be unambiguous.
  def change
    change_column_null :brands, :name, false
    change_column_null :products, :name, false
    change_column_null :stores, :address, false

    add_index :brands, :name, unique: true
    add_index :products, :name, unique: true
    add_index :stores, :address, unique: true
  end
end
