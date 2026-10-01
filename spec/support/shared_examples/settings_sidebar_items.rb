RSpec.shared_context "settings sidebar items" do
  def item(key)
    I18n.t("settings.sidebar.items.#{key}")
  end
end
