# frozen_string_literal: true

require "rails_helper"

# Lexxy 1.0 authors alt text apart from the caption; Action Text exposes it as
# Attachment#alt from Rails 8.2. Until then try(:alt) is nil and the name holds.
RSpec.describe "active_storage/blobs/_blob.html.erb", type: :view do
  let(:image_attachment) do
    Struct.new(:alt, :caption, keyword_init: true) do
      def filename = ActiveStorage::Filename.new("canoe.png")
      def byte_size = 2048
      def representable? = true
      def representation(**) = "/uploads/canoe.png"
    end
  end

  def render_blob(alt:)
    render partial: "active_storage/blobs/blob", locals: { blob: image_attachment.new(alt: alt) }
    Capybara.string(rendered)
  end

  it "uses the author's alternative text when there is one" do
    expect(render_blob(alt: "A red canoe on a still lake")).to have_css("img[alt='A red canoe on a still lake']")
  end

  it "falls back to the filename when no alternative text was written" do
    expect(render_blob(alt: nil)).to have_css("img[alt='canoe']")
  end

  it "treats a blank description as no description" do
    expect(render_blob(alt: "  ")).to have_css("img[alt='canoe']")
  end
end
