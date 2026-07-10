require "rails_helper"

# MiClassrooms Phase 5 Task 4 (Brief §14.1): AnnouncementPolicy — the
# home/find-a-room/about page banners are an admin-only console end to end,
# no editor carve-out (unlike Note, there's no per-unit claim that could
# plausibly extend to a workspace-wide announcement slot).
RSpec.describe AnnouncementPolicy do
  include_context "role matrix"

  let(:announcement) { create(:announcement) }

  # Brief §14.1 (Task 4 table): "all CRUD actions" collapse to one row —
  # every action here is the same `grant.admin?` one-liner, so the matrix
  # spans every action name §14.1 asks for.
  MATRIX = [
    [ :index?,   :announcement, true, false, false, false ],
    [ :show?,    :announcement, true, false, false, false ],
    [ :new?,     :announcement, true, false, false, false ],
    [ :create?,  :announcement, true, false, false, false ],
    [ :edit?,    :announcement, true, false, false, false ],
    [ :update?,  :announcement, true, false, false, false ],
    [ :destroy?, :announcement, true, false, false, false ]
  ].freeze

  USERS = %i[admin_user editor_user other_editor_user viewer_user].freeze

  MATRIX.each do |action, record_name, *expected|
    USERS.each_with_index do |user_name, i|
      it "#{action} on #{record_name} is #{expected[i]} for #{user_name}" do
        policy = described_class.new(send(user_name), send(record_name))
        expect(policy.public_send(action)).to be expected[i]
      end
    end
  end
end
