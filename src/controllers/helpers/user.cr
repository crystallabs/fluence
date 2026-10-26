module Fluence::Helpers::User
  # Issues a new remember-me token for the user and sets it, with the
  # username, into the cookies in order to allow future auto-login. The
  # token this browser presented, if any, is revoked: each browser holds
  # one token, and the user's other browsers keep theirs.
  def set_login_cookies_for(username : String, replacing : String? = presented_token)
    token = ""
    Fluence::USERS.transaction! do |users|
      user = users[username]
      replacing.try { |old| user.revoke_token old }
      token = user.issue_token!
    end
    write_login_cookies username, token
  end

  # Sets the remember-me cookies of this browser.
  def write_login_cookies(username : String, token : String)
    set_cookie name: "user.name", value: username, expires: 14.days.from_now
    set_cookie name: "user.token", value: token, expires: 14.days.from_now
  end

  # If a cookie is set but the user is not signed in, try to use it and
  # rotate the token: the presented one is replaced by a new one.
  def uses_login_cookies
    unless user_signed_in?
      if (name = cookies["user.name"]?) && (token = cookies["user.token"]?)
        if user = Fluence::USERS.auth_token?(name.value, token.value)
          start_session_for user.name
          set_login_cookies_for(user.name, replacing: token.value)
        else
          Log.debug { "Invalid cookies credentials" }
          delete_cookie "user.name"
          delete_cookie "user.token"
        end
      end
    end
  end

  # Logs the user in under a new session id, so that an id the browser
  # had before logging in (possibly planted by an attacker) is never
  # kept. The flash is read first so pending messages survive into the
  # new session (it is committed to it after the action).
  def start_session_for(username : String)
    flash
    session.reset
    session.string("user.name", username)
  end

  # The remember-me token of this browser: the one set by this response
  # (after a cookie auto-login rotated it), else the one in the request.
  def presented_token : String?
    @env.response.cookies["user.token"]?.try(&.value).presence ||
      cookies["user.token"]?.try(&.value).presence
  end

  # Revokes this browser's remember-me token, so it no longer logs in.
  def forget_login_token
    name = user_name? || cookies["user.name"]?.try(&.value)
    token = presented_token
    return unless name && token && Fluence::USERS.find?(name)
    Fluence::USERS.transaction! { |users| users[name]?.try &.revoke_token(token) }
  end

  def delete_login_cookies
    delete_cookie "user.name"
    delete_cookie "user.token"
  end

  # Nil if not signed in, else it returns the user name
  macro user_signed_in?
    session.string?("user.name")
  end

  # Nil if not signed in, else it returns the user name
  macro user_name?
    session.string?("user.name")
  end

  # The signed-in `Fluence::User`, else the default user (guest). A session
  # naming an account that no longer exists (deleted by an admin) is ended,
  # so the request proceeds as guest instead of failing.
  def current_user : Fluence::User
    if name = user_signed_in?
      if user = Fluence::USERS.find?(name)
        return user
      end
      session.destroy
      delete_login_cookies
    end
    Fluence::USERS.default || raise "No default user configured"
  end

  macro acl_permit!(perm, path = request.path)
    uses_login_cookies
    if Fluence::ACL.permitted?(current_user, {{path}}, Acl::PERM[{{perm}}])
      Log.debug { "PERMITTED #{current_user.name} #{{{path}}} #{Acl::PERM[{{perm}}]}" }
    else
      Log.debug { "NOT PERMITTED #{current_user.name} #{{{path}}} #{Acl::PERM[{{perm}}]}" }
      %message = "You are not permitted to access this resource (#{{{path}}}, #{{{perm}}})."
      # The fetch calls of base.js show the error of a JSON answer; a
      # redirect would reach them as an unparseable HTML page.
      if wants_json?
        @env.response.status_code = 403
        @env.response.content_type = "application/json"
        return {success: false, error: %message}.to_json
      end
      flash["danger"] = %message
      redirect_to case {{path}}
      when Fluence::OPTIONS.homepage
        "#{Fluence::OPTIONS.users_prefix}/register"
      else
        Fluence::OPTIONS.homepage
      end
      return # Stop the action
    end
  end
end
