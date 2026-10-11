require "rails_helper"

# Operators retry or start the sync; a workspace admin or editor reads history under /admin instead.
RSpec.describe Operations::SyncRunPolicy do
  let(:operator) { create(:user).tap { |u| Operatorship.grant!(user: u) } }
  let(:member) { create(:user) }
  let(:sync_run) { create(:sync_run) }

  {
    index?: [ true, false ],
    show?: [ true, false ],
    create?: [ true, false ],
    resume?: [ true, false ],
    update?: [ false, false ],
    destroy?: [ false, false ]
  }.each do |verb, (operator_expected, non_operator_expected)|
    it "answers #{verb.inspect} #{operator_expected} for an operator and #{non_operator_expected} for a non-operator" do
      expect(described_class.new(operator, sync_run).public_send(verb)).to be(operator_expected)
      expect(described_class.new(member, sync_run).public_send(verb)).to be(non_operator_expected)
    end
  end
end
