class BackfillPrimaryColorHueOnWorkspaces < ActiveRecord::Migration[8.1]
  def up
    Workspace.where.not(primary_color: [ nil, "" ]).find_each do |ws|
      hex = ws.read_attribute(:primary_color)
      next unless hex.match?(/\A#[0-9a-fA-F]{6}\z/)

      hue = hex_to_hue(hex)
      ws.update_column(:primary_color_hue, hue)
    end
  end

  def down
    # No-op: reverse conversion is lossy
  end

  private

  def hex_to_hue(hex)
    r, g, b = hex.delete("#").scan(/../).map { |c| c.to_i(16) / 255.0 }
    max = [ r, g, b ].max
    min = [ r, g, b ].min
    delta = max - min

    return 0 if delta.zero?

    hue = if max == r
            60 * (((g - b) / delta) % 6)
    elsif max == g
            60 * (((b - r) / delta) + 2)
    else
            60 * (((r - g) / delta) + 4)
    end

    hue.round.then { |h| h < 0 ? h + 360 : h }
  end
end
