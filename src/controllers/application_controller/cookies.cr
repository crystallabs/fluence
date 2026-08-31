class ApplicationController
  module Cookies
    # Cookies sent by the client with the request. Cookies set by the
    # controller go to the response via `set_cookie` and are not readable
    # here — reading back a just-set value is not needed anywhere.
    def cookies
      @env.request.cookies
    end

    # Sets a response cookie, hardened by default: HttpOnly (no script
    # access), SameSite=Lax (not sent on cross-site POSTs), and Secure
    # when the instance is served over HTTPS (see
    # `Fluence::Options#secure_cookies`).
    def set_cookie(name : String, value : String, expires : Time? = nil)
      @env.response.cookies << HTTP::Cookie.new(
        name: name,
        value: value,
        expires: expires,
        path: "/",
        http_only: true,
        samesite: :lax,
        secure: Fluence::OPTIONS.secure_cookies,
      )
    end

    def delete_cookie(name : String)
      set_cookie name, "", expires: Time::UNIX_EPOCH
    end
  end
end
