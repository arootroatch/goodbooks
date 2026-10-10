require "rails_helper"

RSpec.describe "Design tokens" do
  let(:tokens) do
    File.read(Rails.root.join("app/assets/stylesheets/tokens.css"))
      .scan(/--([\w-]+):\s*light-dark\((#\h{6}),\s*(#\h{6})\)/)
      .to_h { |name, light, dark| [ name, { light:, dark: } ] }
  end

  def luminance(hex)
    hex.delete("#").scan(/../).map { _1.to_i(16) / 255.0 }
      .map { _1 <= 0.03928 ? _1 / 12.92 : ((_1 + 0.055) / 1.055)**2.4 }
      .then { |r, g, b| 0.2126 * r + 0.7152 * g + 0.0722 * b }
  end

  def contrast(a, b)
    hi, lo = [ luminance(a), luminance(b) ].sort.reverse
    (hi + 0.05) / (lo + 0.05)
  end

  %w[fg muted accent neg pos warn].each do |text|
    %w[bg surface].each do |background|
      %i[light dark].each do |mode|
        it "#{text} on #{background} meets WCAG AA in #{mode} mode" do
          expect(contrast(tokens.dig(text, mode), tokens.dig(background, mode))).to be >= 4.5
        end
      end
    end
  end

  it "keeps text on accent-soft and on-accent readable" do
    %i[light dark].each do |mode|
      expect(contrast(tokens.dig("accent-fg", mode), tokens.dig("accent-soft", mode))).to be >= 4.5
      expect(contrast(tokens.dig("on-accent", mode), tokens.dig("accent", mode))).to be >= 4.5
    end
  end
end
