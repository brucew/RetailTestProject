class PriceCheck < ApplicationRecord
  belongs_to :product
  belongs_to :store

  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :price_cents, uniqueness: { scope: %i[store_id product_id event_time],
                                        message: "is already recorded for this store, product and time" }
  validates :event_time, presence: true

  # id breaks ties between same-day checks: the later CSV row is the newer check (A4).
  scope :newest_first, -> { order(event_time: :desc, id: :desc) }

  # The most recent price check for each store and product pair in the current
  # scope. Wrapped as a subquery so callers can filter, order and preload the
  # result freely without disturbing the DISTINCT ON ordering.
  def self.latest_per_store_and_product
    latest = select("DISTINCT ON (price_checks.store_id, price_checks.product_id) price_checks.*")
             .order(:store_id, :product_id, event_time: :desc, id: :desc)
    from(latest, :price_checks)
  end
end
