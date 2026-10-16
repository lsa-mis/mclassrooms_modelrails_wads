# frozen_string_literal: true

require "rails_helper"

# Lexxy 1.0 authors alt apart from the caption and Action Text exposes it as Attachment#alt.
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

  it "leaves an undescribed image to its caption, which names the file once" do
    figure = render_blob(alt: nil)

    expect(figure).to have_css("img[alt='']")
    expect(figure).to have_css("figcaption", text: "canoe.png", count: 1)
  end

  it "treats a blank description as no description" do
    expect(render_blob(alt: "  ")).to have_css("img[alt='']")
  end
end
