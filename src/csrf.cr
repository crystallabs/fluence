# Cross-site request forgery protection: every request other than
# GET/HEAD/OPTIONS must carry the session's CSRF token, either in the
# `authenticity_token` field of a form (urlencoded body) or in the
# `X-CSRF-Token` header (the fetch calls of base.js, which read it from
# the `csrf-token` meta tag of the layout). Missing or wrong tokens are
# answered with 403 before the request reaches any action.
#
# The token lives in the session only (no cookie of its own) and is
# issued once per session, when a page renders a form, so several tabs
# and "Save and continue" keep working with the token of their page.
# Logging in starts a new session, and with it a new token.
#
# The git smart-HTTP routes under `Fluence::Options#repo_prefix` are
# exempt: git clients authenticate with HTTP Basic on every request and
# send no cookies, so there is no session a forged request could ride on.
class Fluence::CSRF < Kemal::Handler
  SESSION_KEY  = "csrf"
  HEADER       = "X-CSRF-Token"
  PARAMETER    = "authenticity_token"
  SAFE_METHODS = %w[GET HEAD OPTIONS TRACE]
  ERROR        = "The request did not carry a valid security token (the session may have expired). Reload the page and try again."

  # The session's token, issued on first use. The flash is read before
  # the session is written: writing re-serializes the stored flash, which
  # would drop the messages this request is about to show.
  def self.token(context : HTTP::Server::Context) : String
    context.session.string?(SESSION_KEY) || Random::Secure.urlsafe_base64(32).tap do |token|
      context.flash
      context.session.string SESSION_KEY, token
    end
  end

  def call(context)
    request = context.request
    return call_next(context) if SAFE_METHODS.includes?(request.method) || exempt?(request.path)
    return call_next(context) if valid?(context)

    Log.debug { "CSRF token missing or wrong: #{request.method} #{request.path}" }
    context.response.status_code = 403
    if ApplicationController.wants_json? request
      context.response.content_type = "application/json"
      context.response.print({success: false, error: ERROR}.to_json)
    else
      context.response.content_type = "text/plain; charset=utf-8"
      context.response.print ERROR
    end
  end

  private def exempt?(path : String) : Bool
    prefix = Fluence::OPTIONS.repo_prefix
    path == prefix || path.starts_with?("#{prefix}/")
  end

  private def valid?(context) : Bool
    return false unless expected = context.session.string?(SESSION_KEY)
    return false unless submitted = context.request.headers[HEADER]? || form_token(context)
    Crypto::Subtle.constant_time_compare expected, submitted
  end

  # The token field of a urlencoded form. Multipart bodies are not read
  # here: MediaController#upload streams them itself, and its fetch call
  # sends the header.
  private def form_token(context) : String?
    type = context.request.headers["Content-Type"]?
    return unless type && type.starts_with?(Kemal::ParamParser::URL_ENCODED_FORM)
    context.params.body[PARAMETER]?
  end
end
