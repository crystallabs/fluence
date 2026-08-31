# No need to change defaults.

# The secret signing session cookies. WIKI_SECRET in the environment
# overrides; otherwise a secret is generated on first boot and persisted
# under meta/, so sessions survive restarts.
private def fluence_session_secret : String
  if secret = ENV["WIKI_SECRET"]?.presence
    return secret
  end
  path = File.join(Fluence::OPTIONS.metadir, "secret")
  if File.exists?(path) && (secret = File.read(path).strip.presence)
    return secret
  end
  secret = Random::Secure.base64(64)
  File.write(path, secret, perm: 0o600)
  secret
end

Kemal::Session.config do |config|
  config.cookie_name = "session_id"
  config.secret = fluence_session_secret
  config.secure = Fluence::OPTIONS.secure_cookies

  # Used by kemal-session
  config.gc_interval = 2.minutes # 2 minutes
end
