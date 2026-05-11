# Helper for the native <select> timezone picker on the preferences page.
# Zero JS — uses grouped_options_for_select with optgroups for region
# grouping. Browser provides type-to-jump; SR users get optgroup
# announcements.
module TimezonesHelper
  # 10 zones covering the US population. Surfaced unlabeled at the top
  # of the picker so 90% of users see their zone without scrolling.
  COMMON_US_ZONES = %w[
    America/New_York
    America/Chicago
    America/Denver
    America/Phoenix
    America/Los_Angeles
    America/Anchorage
    Pacific/Honolulu
    America/Indiana/Indianapolis
    America/Detroit
    America/Kentucky/Louisville
  ].freeze

  REGIONAL_PREFIXES = {
    "Americas" => "America/",
    "Europe"   => "Europe/",
    "Asia"     => "Asia/",
    "Pacific"  => "Pacific/",
    "Africa"   => "Africa/",
    "Atlantic" => "Atlantic/",
    "Indian"   => "Indian/"
  }.freeze

  def timezone_options_for_select
    all_zones = TZInfo::Timezone.all_identifiers.sort
    common_set = COMMON_US_ZONES.to_set

    grouped = REGIONAL_PREFIXES.map do |label, prefix|
      [ label, all_zones.select { |z| z.start_with?(prefix) }.reject { |z| common_set.include?(z) } ]
    end

    [ [ "", COMMON_US_ZONES ] ] + grouped
  end
end
