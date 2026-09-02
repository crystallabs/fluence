require "yaml"
require "json"

class Fluence::User
end

# Per-user preferences, stored with the user in meta/users and applied
# wherever the page editor or the layout is rendered. Every field has a
# default, so users created before a setting existed get the default.
class Fluence::User::Settings
  include YAML::Serializable
  include JSON::Serializable

  # Mode pages open in: "default" (the site's open_*_in_edit options),
  # "edit", or "view".
  property editor_mode : String = "default"

  # Start the editor in side-by-side preview and/or fullscreen.
  property? side_by_side : Bool = false
  property? fullscreen : Bool = false

  # Seconds of inactivity before the editor stores a draft in the
  # browser; 0 disables drafts.
  property autosave_delay : Int32 = 3

  # Color scheme: "auto" (follow the browser), "light", or "dark".
  property theme : String = "auto"

  EDITOR_MODES   = %w[default edit view]
  THEMES         = %w[auto light dark]
  AUTOSAVE_RANGE = 0..600

  def initialize
  end

  # Replaces the settings with the submitted form fields; values outside
  # the accepted sets fall back to the defaults.
  def update!(fields : HTTP::Params) : self
    @editor_mode = pick fields["editor_mode"]?, EDITOR_MODES
    @theme = pick fields["theme"]?, THEMES
    @side_by_side = fields.has_key? "side_by_side"
    @fullscreen = fields.has_key? "fullscreen"
    @autosave_delay = fields["autosave_delay"]?.try(&.to_i?).try(&.clamp(AUTOSAVE_RANGE)) || 3
    self
  end

  private def pick(value : String?, allowed : Array(String)) : String
    value && allowed.includes?(value) ? value : allowed.first
  end
end
