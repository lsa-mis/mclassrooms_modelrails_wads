# frozen_string_literal: true

require "rails_helper"

# Ids that come from a constant, or from a runtime prefix that restarts per controller,
# collide as soon as a page renders two of the component — and the ARIA pointing AT them
# (`aria-controls`, `aria-activedescendant`) silently resolves to whichever rendered
# first, so assistive tech describes the wrong node.
#
# Both previews render TWO instances deliberately. An earlier version of this check ran
# against a single-instance preview, where "all ids are unique" is trivially true of a
# one-element list — it passed while the shared-constant bug was still present.
RSpec.describe "Duplicate element ids", type: :system do
  def ids_for(selector)
    JSON.parse(page.evaluate_script(
      %{JSON.stringify([...document.querySelectorAll("#{selector}")].map(e => e.id))}
    ))
  end

  shared_examples "unique ids across instances" do |component, listbox|
    before { visit "/rails/view_components/ui/#{component}_component/two_on_a_page" }

    it "renders two instances, so the check is not vacuous" do
      expect(ids_for(listbox).length).to eq(2)
    end

    it "gives each instance a distinct listbox id" do
      ids = ids_for(listbox)

      expect(ids.uniq.length).to eq(ids.length)
      expect(ids).to all(be_present)
    end

    it "points each control at its own listbox" do
      pairs = page.evaluate_script(<<~JS)
        (() => {
          const owners = [...document.querySelectorAll("[aria-controls]")];
          return JSON.stringify(owners.map((o) => {
            const target = document.getElementById(o.getAttribute("aria-controls"));
            const box = o.closest("[data-controller]");
            return !!target && !!box && box.contains(target);
          }));
        })()
      JS

      expect(JSON.parse(pairs)).to all(be(true))
    end
  end

  describe "combobox" do
    include_examples "unique ids across instances", "combobox", "[role=listbox]"

    # Option ids are minted by the controller at runtime; a fixed prefix restarts its
    # counter per instance, so both comboboxes produce `-option-0`.
    it "gives every option across both instances a distinct id" do
      visit "/rails/view_components/ui/combobox_component/two_on_a_page"
      page.all("[data-combobox-target=input]").each(&:click)
      expect(page).to have_css("[role=option]", minimum: 4, visible: :all)

      ids = ids_for("[role=option]")

      expect(ids.uniq.length).to eq(ids.length)
    end
  end

  describe "command" do
    include_examples "unique ids across instances", "command", "[role=listbox]"
  end
end
