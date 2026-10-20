# An out-of-stock streak, addressed to the product's brand: two or more
# consecutive "no inventory" checks for a product at a store, in event_time
# order (D5). Rows are written by InventoryAlerts::Reconciler, which keeps them
# consistent with the checks as late or out-of-order data arrives (D7).
class InventoryAlert < ApplicationRecord
  belongs_to :brand
  belongs_to :store
  belongs_to :product
  belongs_to :streak_start_check, class_name: "InventoryCheck"
  belongs_to :triggering_check, class_name: "InventoryCheck"
  belongs_to :resolving_check, class_name: "InventoryCheck", optional: true

  validates :streak_start_check_id, uniqueness: true
  validates :miss_count, numericality: { only_integer: true, greater_than_or_equal_to: 2 }
  validates :started_at, presence: true
  validates :triggered_at, presence: true
  validates :resolved_at, presence: true, if: :resolving_check
  validates :resolved_at, absence: true, unless: :resolving_check

  scope :open, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }
  scope :newest_first, -> { order(triggered_at: :desc, id: :desc) }

  # Optional filters for the alerts index; a blank value leaves the scope as is.
  scope :for_brand, ->(brand_id) { where(brand_id:) if brand_id.present? }
  scope :with_status, ->(status) { public_send(status) if status.in?(%w[open resolved]) }

  # Open until inventory is seen again after the streak.
  def open?
    resolved_at.nil?
  end

  # The checks from the streak's first miss through the check that resolved
  # it (or the latest check, while open), in timeline order. Same-day checks
  # are ordered by id, so bounds compare (event_time, id) pairs.
  def streak_checks
    checks = store.inventory_checks.where(product_id:)
                  .where("(event_time, id) >= (:time, :id)", time: started_at, id: streak_start_check_id)
    checks = checks.where("(event_time, id) <= (:time, :id)", time: resolved_at, id: resolving_check_id) unless open?
    checks.order(:event_time, :id)
  end
end
