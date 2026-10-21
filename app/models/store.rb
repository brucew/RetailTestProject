class Store < ApplicationRecord
  has_many :inventory_checks, dependent: :restrict_with_error
  has_many :price_checks, dependent: :restrict_with_error
  has_many :inventory_alerts, dependent: :restrict_with_error

  validates :address, presence: true, uniqueness: true
end
