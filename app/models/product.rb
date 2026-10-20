class Product < ApplicationRecord
  belongs_to :brand
  has_many :inventory_checks, dependent: :restrict_with_error
  has_many :price_checks, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
end
