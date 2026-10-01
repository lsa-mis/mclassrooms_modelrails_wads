class IconRegistry
  class NotFound < StandardError; end

  ICON_DIR = Rails.root.join("app/assets/icons")
  STYLES = %i[outline solid].freeze

  class << self
    def find(name, style: nil)
      keys_for(name, style).filter_map { |key| cache[key] }.first ||
        raise(NotFound, "Icon '#{name}' not found#{" in #{style} style" if style}")
    end

    def exists?(name, style: nil)
      keys_for(name, style).any? { |key| cache.key?(key) }
    end

    def available_icons
      cache.keys.map(&:first).uniq.sort
    end

    def reload!
      @cache = nil
    end

    def eager_load!
      cache
    end

    private

    def keys_for(name, style)
      styles = style ? [ style.to_sym ] : STYLES
      styles.map { |candidate| [ name.to_sym, candidate ] }
    end

    def cache
      @cache ||= load_all_icons
    end

    def load_all_icons
      icons = {}
      STYLES.each do |style|
        dir = ICON_DIR.join(style.to_s)
        next unless dir.exist?

        Dir.glob(dir.join("*.svg")).each do |path|
          name = File.basename(path, ".svg").to_sym
          icons[[ name, style ]] = parse_svg(path, style)
        end
      end
      icons
    end

    def parse_svg(path, style)
      doc = Nokogiri::XML(File.read(path))
      svg = doc.at_css("svg")
      {
        inner_html: svg.inner_html.strip,
        viewbox: svg["viewBox"],
        style: style
      }.freeze
    end
  end
end
