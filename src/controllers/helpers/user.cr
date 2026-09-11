module Fluence::Helpers::User
  # The username+token are set into the cookies in order to allow future auto-login
  def set_login_cookies_for(username)
    Fluence::USERS.transaction!(read: true) { |users| users[username].generate_new_token! }
    token = Fluence::USERS[username].token.to_s
    set_cookie name: "user.name", value: username, expires: 14.days.from_now
    set_cookie name: "user.token", value: token, expires: 14.days.from_now
  end

  # If a cookie is set but the user is not signed in, try to use it and renew the cookie
  def uses_login_cookies
    unless user_signed_in?
      if (name = cookies["user.name"]?) && (token = cookies["user.token"]?)
        if (user = Fluence::USERS.auth_token?(name.value, token.value))
          session.string("user.name", user.name)
          set_login_cookies_for(user.name)
        else
          Log.debug { "Invalid cookies credentials" }
          delete_cookie "user.name"
          delete_cookie "user.token"
        end
      end
    end
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
      flash["danger"] = "You are not permitted to access this resource (#{{{path}}}, #{{{perm}}})."
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
