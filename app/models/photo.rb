class Photo < ApplicationRecord
  belongs_to :chat
  belongs_to :member
end
