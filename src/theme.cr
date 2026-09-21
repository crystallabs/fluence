# Site-level theming slots: raw HTML/CSS/JS overrides dropped in
# Fluence::OPTIONS.themedir, read fresh on every render so a site admin
# can restyle header, footer, nav, stylesheet, and behavior without
# rebuilding or restarting the binary. Missing files render as empty
# content — the built-in layout is the default theme.
module Fluence::Theme
  SLOTS = %w[header footer nav_extra]

  # Raw HTML for a named slot ("header", "footer", or "nav_extra"), or ""
  # if the site hasn't overridden it.
  def self.slot(name : String) : String
    read ::File.join(Fluence::OPTIONS.themedir, "#{name}.html")
  end

  # Contents of the site's custom stylesheet, or "" if it has none.
  def self.custom_css : String
    read ::File.join(Fluence::OPTIONS.themedir, "custom.css")
  end

  # Contents of the site's custom script, or "" if it has none.
  def self.custom_js : String
    read ::File.join(Fluence::OPTIONS.themedir, "custom.js")
  end

  private def self.read(path : String) : String
    ::File.exists?(path) ? ::File.read(path) : ""
  end
end
