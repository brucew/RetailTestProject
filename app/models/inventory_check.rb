class InventoryCheck < ApplicationRecord
  belongs_to :product
  belongs_to :store

  validates :inventory_present, inclusion: { in: [true, false] }
  validates :inventory_present, uniqueness: { scope: %i[store_id product_id event_time],
                                              message: "is already recorded for this store, product and time" }
  validates :event_time, presence: true

  # Every copy of a repeated check except the earliest (lowest id) one.
  def self.exact_duplicates
    ranked = select(:id, <<~SQL.squish)
      ROW_NUMBER() OVER (PARTITION BY store_id, product_id, event_time, inventory_present ORDER BY id) AS occurrence
    SQL
    where(id: from(ranked, :ranked_checks).where("ranked_checks.occurrence > 1").select("ranked_checks.id"))
  end
end
