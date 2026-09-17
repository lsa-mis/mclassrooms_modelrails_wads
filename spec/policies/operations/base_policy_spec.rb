require "rails_helper"

RSpec.describe "Operations policies" do
  let(:operator) { create(:user).tap { |u| Operatorship.grant!(user: u) } }
  let(:member) { create(:user) }
  let(:workspace) { create(:workspace) }

  describe Operations::WorkspacePolicy do
    # verb => [answer for an operator, answer for a non-operator]. Values are
    # read off app/policies/operations/workspace_policy.rb, not derived from
    # calling it, so a changed override shows up as a mismatch here.
    {
      index?: [ true, false ],
      show?: [ true, false ],
      new?: [ true, false ],
      create?: [ true, false ],
      update?: [ false, false ],
      edit?: [ false, false ],
      destroy?: [ false, false ],
      suspend?: [ true, false ],
      unsuspend?: [ true, false ]
    }.each do |verb, (operator_expected, non_operator_expected)|
      it "answers #{verb.inspect} #{operator_expected} for an operator and #{non_operator_expected} for a non-operator" do
        expect(described_class.new(operator, workspace).public_send(verb)).to be(operator_expected)
        expect(described_class.new(member, workspace).public_send(verb)).to be(non_operator_expected)
      end
    end

    it "denies a nil user" do
      expect(described_class.new(nil, workspace).index?).to be false
    end

    it "does not read Current.workspace" do
      # A spy on the reader, not a value assertion (spec/requests/operations/
      # area_spec.rb's "never establishes a workspace context" is the
      # symmetric fix on the setter side): Current.workspace already reads
      # nil in this non-request example whether or not the policy touches
      # it, so only observing the call itself can fail.
      allow(Current).to receive(:workspace).and_call_original
      described_class.new(operator, workspace).show?
      expect(Current).not_to have_received(:workspace)
    end

    it "does not descend from ApplicationPolicy" do
      expect(described_class.ancestors).not_to include(ApplicationPolicy)
    end
  end

  describe Operations::UserPolicy do
    # Record is `member` throughout, including the non-operator actor rows
    # (actor == record there, same as the original hand-written example) —
    # values read off app/policies/operations/user_policy.rb.
    {
      index?: [ true, false ],
      show?: [ true, false ],
      new?: [ false, false ],
      create?: [ false, false ],
      update?: [ false, false ],
      edit?: [ false, false ],
      destroy?: [ false, false ],
      unlock?: [ true, false ],
      suspend?: [ true, false ],
      unsuspend?: [ true, false ]
    }.each do |verb, (operator_expected, non_operator_expected)|
      it "answers #{verb.inspect} #{operator_expected} for an operator and #{non_operator_expected} for a non-operator" do
        expect(described_class.new(operator, member).public_send(verb)).to be(operator_expected)
        expect(described_class.new(member, member).public_send(verb)).to be(non_operator_expected)
      end
    end

    it "refuses to suspend an operator record, the operator themself included" do
      other_operator = create(:user).tap { |u| Operatorship.grant!(user: u) }

      expect(described_class.new(operator, other_operator).suspend?).to be false
      expect(described_class.new(operator, operator).suspend?).to be false
    end
  end

  describe Operations::ActivityLogPolicy do
    # The feed is read-only: index? is the one predicate that opens, the
    # rest are refused for everyone (app/policies/operations/activity_log_policy.rb).
    {
      index?: [ true, false ],
      show?: [ false, false ],
      create?: [ false, false ],
      new?: [ false, false ],
      update?: [ false, false ],
      edit?: [ false, false ],
      destroy?: [ false, false ]
    }.each do |verb, (operator_expected, non_operator_expected)|
      it "answers #{verb.inspect} #{operator_expected} for an operator and #{non_operator_expected} for a non-operator" do
        expect(described_class.new(operator, ActivityLog).public_send(verb)).to be(operator_expected)
        expect(described_class.new(member, ActivityLog).public_send(verb)).to be(non_operator_expected)
      end
    end
  end

  describe Operations::OperatorshipPolicy do
    # Record is a plain unsaved Operatorship — every predicate here answers
    # from the actor's operator? status alone (app/policies/operations/
    # operatorship_policy.rb), never the record's attributes.
    {
      index?: [ true, false ],
      show?: [ false, false ],
      new?: [ true, false ],
      create?: [ true, false ],
      update?: [ false, false ],
      edit?: [ false, false ],
      destroy?: [ true, false ]
    }.each do |verb, (operator_expected, non_operator_expected)|
      it "answers #{verb.inspect} #{operator_expected} for an operator and #{non_operator_expected} for a non-operator" do
        expect(described_class.new(operator, Operatorship.new).public_send(verb)).to be(operator_expected)
        expect(described_class.new(member, Operatorship.new).public_send(verb)).to be(non_operator_expected)
      end
    end
  end
end
