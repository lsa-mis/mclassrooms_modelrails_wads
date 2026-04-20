# A Document is a rich-text content wrapper. The table has only id + timestamps —
# all content lives in Action Text's rich_text table (via has_rich_text :body).
# The model exists to satisfy the polymorphic resourceable association on Resource,
# giving documents a dedicated type in the resource hierarchy.
class Document < ApplicationRecord
  has_rich_text :body
  has_one :resource, as: :resourceable, dependent: :destroy
end
