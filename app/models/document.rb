class Document < ApplicationRecord
  has_rich_text :body
  has_one :resource, as: :resourceable, dependent: :destroy
end
