module IconHelper
  SIZES = {
    xs: "w-3 h-3",
    sm: "w-4 h-4",
    md: "w-5 h-5",
    lg: "w-6 h-6",
    xl: "w-8 h-8"
  }.freeze

  def icon(name, size: :md, style: :outline, aria_label: nil, **attrs)
    data = IconRegistry.find(name, style: style)
    custom_class = attrs.delete(:class)

    size_classes = custom_sizing?(custom_class) ? "" : SIZES.fetch(size)
    css_class = [ size_classes, custom_class ].compact_blank.join(" ")

    svg_attrs = {
      viewBox: data[:viewbox],
      class: css_class,
      xmlns: "http://www.w3.org/2000/svg"
    }

    if data[:style] == :outline
      svg_attrs[:fill] = "none"
      svg_attrs[:stroke] = "currentColor"
    else
      svg_attrs[:fill] = "currentColor"
    end

    if aria_label
      svg_attrs[:role] = "img"
      svg_attrs[:"aria-label"] = aria_label
    else
      svg_attrs[:"aria-hidden"] = "true"
    end

    svg_attrs.merge!(attrs)

    tag.svg(**svg_attrs) { data[:inner_html].html_safe }
  end

  private

  def custom_sizing?(css_class)
    return false unless css_class

    css_class.match?(/\bw-\S+/) && css_class.match?(/\bh-\S+/)
  end
end
