require "rails_helper"
require "vips"

# The source is COORDINATE-ENCODED: each pixel's value IS its own position, so
# every assertion is arithmetic rather than eyeballing. PNG, because webp and
# jpeg would perturb the encoded values.
#
#   band 0 (R) = x index 0..255  ->  longitude = (x / 256.0) * 360 - 180
#   band 1 (G) = y index 0..127  ->  latitude  = 90 - (y / 128.0) * 180
#
# Expected values are for a 64x32 render at HFOV 100: f = 32 / tan(50 deg) =
# 26.851, using PIXEL CENTRES (px + 0.5 - W/2), which is why the extremes land
# just inside the theoretical +/-50 and +/-30.8 degree limits. Every value below
# was verified against a real run; they are exact, not approximate.
RSpec.describe Panorama::Rectilinear do
  # mktmpdir, not a fixed tmp/ path: bin/parallel-rspec runs workers that share
  # tmp/, and two workers in this file would race one another's cleanup.
  around do |example|
    Dir.mktmpdir("rectilinear") do |dir|
      @dir = dir
      example.run
    end
  end

  let(:source) do
    path = File.join(@dir, "coord_equirect.png")
    Vips::Image.xyz(256, 128).bandjoin(Vips::Image.black(256, 128)).cast(:uchar).pngsave(path)
    path
  end

  def sample(px, py, width: 64)
    described_class.project(source, width: width).getpoint(px, py).first(2)
  end

  describe ".project" do
    it "renders a 2:1 image at the requested width" do
      image = described_class.project(source, width: 64)

      expect([ image.width, image.height ]).to eq([ 64, 32 ])
    end

    it "puts the source's centre at the centre of the render" do
      u, v = sample(32, 16)

      expect(u).to be_within(2).of(129)
      expect(v).to be_within(2).of(65)
    end

    # Catches a YAW sign flip. Tolerance 1, not 2: the correct value is exactly
    # 163.0, and an hfov of 90 instead of 100 lands on 160 — only three units
    # away, so a loose tolerance here would let a wrong constant through.
    it "maps the horizontal extremes to +/-50 degrees of longitude" do
      right_u, = sample(63, 16)
      left_u,  = sample(0, 16)

      expect(right_u).to be_within(1).of(163),
        "right edge should sample east of centre. If left and right are swapped, " \
        "the sign on x_offset_px / focal_px is inverted."
      expect(left_u).to be_within(1).of(93)
    end

    # Catches a PITCH sign flip INDEPENDENTLY of yaw.
    it "maps the vertical extremes to +/-30 degrees of latitude" do
      top_v    = sample(32, 0).last
      bottom_v = sample(32, 31).last

      expect(top_v).to be_within(2).of(43),
        "the TOP of the render should sample ABOVE the source's equator (v < 64), got #{top_v}. " \
        "If it is ~85 the pitch sign is inverted — check the `* -1` on y_offset_px and the " \
        "`/ -VAOV_DEG` in index_map. Those two negations cancel, so deleting either alone " \
        "produces exactly this."
      expect(bottom_v).to be_within(2).of(85)
    end

    # THE discriminating assertion. On-axis samples pass for the WRONG formula
    # phi = atan(-y / f), which omits the hypot term. Only an off-axis sample
    # separates them: at the top-right corner the correct projection gives
    # +20.5 deg (v ~ 49), the wrong one +30.0 deg (v ~ 43).
    it "foreshortens off-axis latitude via the hypot term" do
      corner_v = sample(63, 0).last

      expect(corner_v).to be_within(2).of(49),
        "off-axis latitude is not foreshortened. phi must divide by hypot(x, f), not by f alone."
      expect(corner_v).not_to be_within(2).of(43)
    end

    # Guards the `+ 0.5` pixel-CENTRE offsets, which NOTHING else catches:
    # sampling at indices instead of centres shifts the render half a pixel up
    # and left, well inside every tolerance above. What it destroys is symmetry —
    # with centres the outermost columns mirror about the source's centre
    # (93 + 163 = 256) and the outermost rows about its middle (43 + 85 = 128).
    # Drop the offsets and both sums lose exactly one.
    it "samples pixel centres, so the render is symmetric about the source's centre" do
      left_u,  = sample(0, 16)
      right_u, = sample(63, 16)
      top_v    = sample(32, 0).last
      bottom_v = sample(32, 31).last

      expect(left_u + right_u).to be_within(0.5).of(256),
        "left+right must straddle the source centre exactly. Off by ~1 means the `+ 0.5` " \
        "pixel-centre terms in index_map were removed."
      expect(top_v + bottom_v).to be_within(0.5).of(128)
    end

    it "rejects a source that is not 2:1" do
      path = File.join(@dir, "not_equirect.png")
      Vips::Image.black(100, 100).pngsave(path)

      expect { described_class.project(path, width: 64) }
        .to raise_error(described_class::NotEquirectangular, /100x100.*ratio 1\.0/m)
    end

    # The square case above is only 1.0 — a full 1.0 away from the 2.0 target,
    # so it still fails with ASPECT_TOLERANCE widened all the way to 0.9. 3:2
    # is the ratio the guard actually exists for: an ordinary phone photo
    # dropped into the panorama slot, which projects to something PLAUSIBLE and
    # wrong rather than to anything obviously broken.
    it "rejects a 3:2 phone photo — the case the tolerance is sized for" do
      path = File.join(@dir, "phone_photo.png")
      Vips::Image.black(300, 200).pngsave(path)

      expect { described_class.project(path, width: 64) }
        .to raise_error(described_class::NotEquirectangular, /ratio 1\.5/)
    end

    # The other end of the same clamp: a real 4000x2000 export is not always
    # EXACTLY 2:1, and ASPECT_TOLERANCE = 0 (or a strict `==`) would reject
    # every one of them at ingest with a message blaming the photographer.
    it "accepts a source within the aspect tolerance rather than demanding exactly 2:1" do
      path = File.join(@dir, "nearly_equirect.png")
      Vips::Image.black(2000, 1001).pngsave(path)

      expect { described_class.project(path, width: 64) }.not_to raise_error
    end
  end

  # Not a tautology: this value is a CONTRACT with Pannellum's documented
  # default, and this is the cheapest place to record that it is not arbitrary.
  it "renders at Pannellum's default field of view" do
    expect(described_class::HFOV_DEG).to eq(100.0)
  end

  describe ".render" do
    # vips-loader, not just "it decoded": Vips::Image.new_from_buffer sniffs the
    # format and reads JPEG and PNG just as happily, so a size-only assertion
    # passes with webpsave_buffer swapped for jpegsave_buffer. The job's own
    # content_type assertion does not cover it either — the job HARD-CODES
    # "image/webp" on the attach regardless of what bytes it was handed, so
    # that swap would ship JPEGs labelled as WebP with nothing complaining.
    it "returns webp bytes readable back at the requested size" do
      io = described_class.render(source, width: 64)
      image = Vips::Image.new_from_buffer(io.string, "")

      expect([ image.width, image.height ]).to eq([ 64, 32 ])
      expect(image.get("vips-loader")).to eq("webpload_buffer")
    end
  end

  describe ".signature" do
    # Names every constant the signature must be derived from. Varying only the
    # ARGUMENT (the old assertion) is satisfied by `"w#{width}"` — which would
    # mean changing HFOV_DEG or ASPECT left every existing render stamped as
    # current, so no backfill would ever pick them up and the whole staleness
    # mechanism would quietly stop working.
    it "names the projection constants, so changing any of them invalidates every render" do
      expect(described_class.signature(width: 1024))
        .to eq("hfov#{described_class::HFOV_DEG}-aspect#{described_class::ASPECT}-w1024")
    end

    it "changes when the projection recipe changes" do
      expect(described_class.signature(width: 1024)).not_to eq(described_class.signature(width: 512))
    end
  end
end
