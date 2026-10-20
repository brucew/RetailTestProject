class Brand < ApplicationRecord
  has_many :products, dependent: :restrict_with_error
  has_many :inventory_alerts, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
end
