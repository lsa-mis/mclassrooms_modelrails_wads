# frozen_string_literal: true

require "vips"   # ruby-vips is `require: false` in the Gemfile (see the comment there)

module Panorama
  # Reprojects an equirectangular panorama to the RECTILINEAR view a 360 viewer
  # shows at its default camera, so the room page's static image and the booted
  # Pannellum viewer are the same picture.
  #
  # Why this can be exact: the panoramas carry no GPano XMP metadata, so nothing
  # can override Pannellum's defaults — it always boots at yaw 0, pitch 0,
  # hfov 100, haov 360, vaov 180. See the design spec's "Established facts".
  #
  # Deliberately not a Result-struct service (CLAUDE.md deviation #3): a pure
  # transform renders or raises; a Result here would wrap a calculator in ceremony.
  #
  # SANITY CHECK when a render looks wrong: at HFOV 100 the output covers
  # longitude -50..+50 and latitude -30.8..+30.8 degrees, with the source's exact
  # centre at the render's exact centre. Anything wider, taller, or off-centre is
  # a bug HERE, not in the viewer. To look at one:
  #
  #   bin/rails panoramas:render_flat ROOM=<rmrecnbr> INLINE=1 FORCE=1
  #
  # FOUR CONVENTIONS, all silent-corruption magnets — do not "simplify" any:
  #
  #   1. Image y increases DOWNWARD; pitch increases UPWARD. That is the reason
  #      for the `* -1` on y_offset_px. It and the `/ -VAOV_DEG` below cancel each
  #      other — delete either alone and you get a vertically mirrored image that
  #      still looks like a room.
  #   2. Every angle is in DEGREES. libvips' `atan` answers in degrees; Ruby's
  #      `Math.atan` answers in radians. The `_deg` suffixes are load-bearing.
  #   3. A Vips::Image must be the RECEIVER of every operator. `Vips::Image` has
  #      no `#coerce`, so `0.5 - image` raises TypeError. That is why the `+ 0.5`
  #      terms trail rather than lead, and why the sign lives in `-VAOV_DEG`.
  #   4. `access: :random` is required. `mapim` samples out of order; :sequential
  #      makes vips buffer the whole 4000x2000 image or fail outright.
  #
  # Yaw and pitch are both zero, which collapses the general case: every angle
  # stays in one quadrant, so plain `atan` suffices and no `atan2` is needed.
  #
  # `mapim` returns BLACK outside the source, not wrapped. At haov 360 / hfov 100
  # / yaw 0 the sampled u stays within +/-555px of centre, so the +/-180 degree
  # seam is never reached. Any yaw parameter added here must `%` u into
  # [0, source_width) first or the render grows black wedges.
  module Rectilinear
    module_function

    HFOV_DEG = 100.0   # Pannellum's default horizontal field of view — a contract, not a taste
    HAOV_DEG = 360.0   # full-sphere source
    VAOV_DEG = 180.0
    ASPECT   = 2       # output w:h. Pannellum derives vfov from its CONTAINER's aspect, so this
    # same number must be the stage's aspect-ratio (_pano_pane.html.erb) or
    # the vertical framing silently disagrees.
    DEFAULT_WIDTH = 1024
    # ~+/-20px of height slop on a 4000px-wide export. Nowhere near loose enough
    # to admit a 3:2 phone photo (1.5) or 16:9 (1.78).
    ASPECT_TOLERANCE = 0.02

    NotEquirectangular = Class.new(StandardError)

    # The signature of the RECIPE, stamped into every render. Derived, so changing
    # HFOV_DEG or the default width automatically makes every existing render
    # stale and the next backfill re-renders it. Without this, changing a constant
    # here leaves 219 renders that agree with each other and with nothing else.
    def signature(width: DEFAULT_WIDTH)
      "hfov#{HFOV_DEG}-aspect#{ASPECT}-w#{width}"
    end

    # Geometry only, losslessly. Separate from #render because webp is lossy and
    # a geometry spec must not assert against compression artifacts.
    #
    # LAZY: the returned image reads source_path on demand. #render forces it.
    # Do not let a #project result escape a `blob.open` block — the tempfile is
    # unlinked at the end of it and you get intermittent corruption.
    def project(source_path, width: DEFAULT_WIDTH)
      source = Vips::Image.new_from_file(source_path.to_s, access: :random)
      assert_equirectangular!(source, source_path)

      source.mapim(index_map(width: width, height: width / ASPECT,
                             source_width: source.width, source_height: source.height))
    end

    def render(source_path, width: DEFAULT_WIDTH)
      StringIO.new(project(source_path, width: width).webpsave_buffer(Q: 82))
    end

    # A two-band image whose pixel values are the SOURCE coordinates to sample for
    # each output pixel — vips does the whole reprojection in one mapim call, with
    # no per-pixel Ruby. Keyword arguments on purpose: these are four
    # interchangeable-looking integers, and transposing two produces a
    # plausible-but-wrong image rather than an exception.
    def index_map(width:, height:, source_width:, source_height:)
      focal_px = (width / 2.0) / Math.tan(HFOV_DEG / 2.0 * Math::PI / 180.0)

      xy          = Vips::Image.xyz(width, height)
      x_offset_px = xy[0] + 0.5 - width / 2.0    # +0.5: pixel CENTRES, not indices
      y_offset_px = xy[1] + 0.5 - height / 2.0

      lambda_deg = (x_offset_px / focal_px).atan
      phi_deg    = ((y_offset_px * -1) / ((x_offset_px**2 + focal_px**2)**0.5)).atan

      # Absolute source PIXELS, not normalised uv — hence the _px suffix.
      source_x_px = (lambda_deg / HAOV_DEG + 0.5) * source_width
      source_y_px = (phi_deg / -VAOV_DEG + 0.5) * source_height

      source_x_px.bandjoin(source_y_px)
    end

    # Room validates content type and size only, so the admin edit form happily
    # accepts a 3:2 phone photo into the panorama slot. Projected, that renders
    # something PLAUSIBLE AND WRONG — the worst failure mode, because nobody
    # notices. Fail loudly, and say what to do about it.
    def assert_equirectangular!(source, source_path)
      ratio = source.width.to_f / source.height
      return if (ratio - 2.0).abs <= ASPECT_TOLERANCE

      raise NotEquirectangular,
            "#{source_path} is #{source.width}x#{source.height} (ratio #{ratio.round(3)}); " \
            "a rectilinear render needs a full-sphere 2:1 equirectangular source " \
            "(tolerance +/-#{ASPECT_TOLERANCE}). A ratio near 1.33/1.5/1.78 means an ordinary " \
            "camera photo was uploaded into the panorama slot."
    end
  end
end
