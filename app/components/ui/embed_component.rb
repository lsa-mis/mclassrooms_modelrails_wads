# frozen_string_literal: true

module UI
  class EmbedComponent < ApplicationComponent
    # Embeds third-party content.
    # Usage, options and the accessibility contract: docs/components/embed.md in the
    # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.

    PROVIDERS = {
      youtube:     { aspect: "16/9", sandbox: "allow-scripts allow-same-origin allow-presentation allow-popups" },
      vimeo:       { aspect: "16/9", sandbox: "allow-scripts allow-same-origin allow-presentation allow-popups" },
      spotify:     { aspect: nil,    sandbox: "allow-scripts allow-same-origin allow-popups" },
      google_maps: { aspect: "16/9", sandbox: "allow-scripts allow-same-origin" },
      yandex_maps: { aspect: "16/9", sandbox: "allow-scripts allow-same-origin" },
      loom:        { aspect: "16/9", sandbox: "allow-scripts allow-same-origin allow-presentation allow-popups" },
      soundcloud:  { aspect: nil,    sandbox: "allow-scripts allow-same-origin allow-popups" },
      x:           { aspect: nil,    sandbox: nil },
      telegram:    { aspect: nil,    sandbox: nil },
      facebook:    { aspect: "16/9", sandbox: "allow-scripts allow-same-origin allow-popups allow-forms" }
    }.freeze

    WIDGET_PROVIDERS = %i[x telegram].freeze

    DOMAIN_MAP = {
      /youtube\.com|youtu\.be/i                         => :youtube,
      /vimeo\.com/i                                     => :vimeo,
      /open\.spotify\.com/i                             => :spotify,
      /loom\.com/i                                      => :loom,
      /soundcloud\.com/i                                => :soundcloud,
      /(?:twitter|x)\.com/i                             => :x,
      /t\.me|telegram\.org/i                            => :telegram,
      /facebook\.com|fb\.com/i                          => :facebook,
      /maps\.google|google\.com\/maps|maps\.app\.goo\.gl/i => :google_maps,
      /yandex\.(ru|com)\/maps/i                         => :yandex_maps
    }.freeze

    WRAPPER_CLS = "overflow-hidden rounded-md"
    # bg-black is an intentional letterbox backdrop for media iframes —
    # a media surface, not a text-contrast surface (so no semantic token applies).
    DARK_WRAPPER_CLS = "overflow-hidden rounded-md bg-black"

    def self.detect_provider(url)
      DOMAIN_MAP.each { |pattern, provider| return provider if url.to_s.match?(pattern) }
      nil
    end

    TITLES = {
      youtube:     "YouTube video",
      vimeo:       "Vimeo video",
      spotify:     "Spotify player",
      google_maps: "Google Maps",
      yandex_maps: "Yandex Maps",
      loom:        "Loom video",
      soundcloud:  "SoundCloud player",
      x:           "Post on X",
      telegram:    "Telegram post",
      facebook:    "Facebook video"
    }.freeze

    def initialize(url: nil, query: nil, aspect: nil, height: nil, title: nil, **html_attrs)
      @type   = query ? :google_maps : self.class.detect_provider(url)
      @url    = url
      @query  = query
      @aspect = aspect || PROVIDERS.dig(@type, :aspect)
      @height = height || default_height
      @title_override = title           # was: @title = title || default_title
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    # Resolve at render time (t needs the view context).
    def title
      @title_override || default_title
    end

    def call
      return unsupported_msg unless @type && PROVIDERS.key?(@type)

      if WIDGET_PROVIDERS.include?(@type)
        widget_markup
      else
        iframe_markup
      end
    end

    private

    # ── Widget-based providers (X, Telegram) ─────────────────────────────────

    def widget_markup
      case @type
      when :x        then x_widget
      when :telegram then telegram_widget
      end
    end

    def x_widget
      tweet_id = extract_tweet_id(@url.to_s)
      return unsupported_msg unless tweet_id

      content_tag(:div,
        class: cn(WRAPPER_CLS, @extra_class),
        data:  { controller: "embed", embed_provider_value: "x", embed_post_id_value: tweet_id },
        **@html_attrs) do
        content_tag(:blockquote, class: "twitter-tweet", "data-dnt": "true") do
          tag.a(href: "https://twitter.com/i/status/#{tweet_id}")
        end
      end
    end

    def telegram_widget
      return unsupported_msg unless @url

      post_id = @url.sub(%r{\Ahttps://t\.me/}, "").sub(%r{\A@}, "")

      content_tag(:div, "",
        class: cn(WRAPPER_CLS, @extra_class),
        data:  { controller: "embed", embed_provider_value: "telegram", embed_post_id_value: post_id },
        **@html_attrs)
    end

    # ── Iframe-based providers ────────────────────────────────────────────────

    def iframe_markup
      embed_url = build_embed_url
      return unsupported_msg unless embed_url

      sandbox = PROVIDERS.dig(@type, :sandbox)
      iframe_attrs = {
        src:  embed_url, title: title, loading: "lazy",
        class: "w-full h-full border-0 block",
        allowfullscreen: true,
        allow: "autoplay; fullscreen; picture-in-picture"
      }
      iframe_attrs[:sandbox] = sandbox if sandbox

      wrapper_style = @aspect ? "aspect-ratio: #{@aspect}" : "height: #{@height}px"
      content_tag(:div,
        class: cn(DARK_WRAPPER_CLS, @extra_class),
        style: wrapper_style,
        **@html_attrs) do
        tag.iframe(**iframe_attrs)
      end
    end

    def build_embed_url
      case @type
      when :youtube     then youtube_url
      when :vimeo       then vimeo_url
      when :spotify     then spotify_url
      when :google_maps then google_maps_url
      when :yandex_maps then yandex_maps_url
      when :loom        then loom_url
      when :soundcloud  then soundcloud_url
      when :facebook    then facebook_url
      end
    end

    def unsupported_msg
      content_tag(:p,
        t("ui.embed.unsupported", type: @type, default: "Unsupported embed type: %{type}"),
        class: "text-sm text-danger")
    end

    # ── Embed URL builders ────────────────────────────────────────────────────

    def youtube_url
      vid = extract_youtube_id(@url.to_s)
      "https://www.youtube.com/embed/#{vid}?rel=0" if vid
    end

    def vimeo_url
      vid = extract_vimeo_id(@url.to_s)
      "https://player.vimeo.com/video/#{vid}?dnt=1" if vid
    end

    def spotify_url
      path = extract_spotify_path(@url.to_s)
      "https://open.spotify.com/embed/#{path}" if path
    end

    def google_maps_url
      if @query
        "https://maps.google.com/maps?q=#{CGI.escape(@query)}&output=embed"
      elsif @url
        return @url if @url.include?("output=embed") || @url.match?(%r{/maps/embed})
        begin
          uri = URI.parse(@url)
          q = URI.decode_www_form(uri.query.to_s).to_h["q"]
          if q
            "https://maps.google.com/maps?q=#{CGI.escape(q)}&output=embed"
          else
            sep = @url.include?("?") ? "&" : "?"
            "#{@url}#{sep}output=embed"
          end
        rescue URI::InvalidURIError, ArgumentError
          nil
        end
      end
    end

    def yandex_maps_url
      return nil unless @url
      @url.sub(%r{yandex\.(ru|com)/maps}, 'yandex.\1/map-widget/v1')
    end

    def loom_url
      vid = extract_loom_id(@url.to_s)
      "https://www.loom.com/embed/#{vid}" if vid
    end

    def soundcloud_url
      return nil unless @url
      "https://w.soundcloud.com/player/?url=#{CGI.escape(@url)}&auto_play=false&hide_related=true&show_comments=false&visual=false"
    end

    def facebook_url
      return nil unless @url
      "https://www.facebook.com/plugins/video.php?href=#{CGI.escape(@url)}&show_text=false"
    end

    # ── ID extractors ─────────────────────────────────────────────────────────

    def extract_youtube_id(url)
      uri = URI.parse(url)
      if uri.host&.include?("youtu.be")
        uri.path.delete_prefix("/")
      elsif uri.host&.include?("youtube.com")
        URI.decode_www_form(uri.query.to_s).to_h["v"]
      end
    rescue URI::InvalidURIError, ArgumentError
      nil
    end

    def extract_vimeo_id(url)
      URI.parse(url).path.split("/").last
    rescue URI::InvalidURIError
      nil
    end

    def extract_spotify_path(url)
      m = url.match(%r{open\.spotify\.com/(track|album|playlist|episode|show)/([^?]+)})
      m ? "#{m[1]}/#{m[2]}" : nil
    end

    def extract_loom_id(url)
      URI.parse(url).path.split("/").last
    rescue URI::InvalidURIError
      nil
    end

    def extract_tweet_id(url)
      URI.parse(url).path.split("/").last
    rescue URI::InvalidURIError
      nil
    end

    def default_height
      case @type
      when :spotify    then 152
      when :soundcloud then 166
      else 400
      end
    end

    def default_title
      t("ui.embed.titles.#{@type}", default: TITLES.fetch(@type, "Embedded content"))
    end
  end
end
