class Store < ApplicationRecord
  has_many :inventory_checks, dependent: :restrict_with_error

  validates :address, presence: true, uniqueness: true
end
