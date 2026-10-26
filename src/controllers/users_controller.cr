class UsersController < ApplicationController
  # get /users/login
  def login
    acl_permit! :read
    render "login.slang"
  end

  # post /users/login
  def login_validates
    acl_permit! :write
    name = params.body["username"].to_s
    address = request.remote_address
    if Fluence::LOGIN_THROTTLE.blocked?(address, name)
      flash["danger"] = "Too many failed login attempts. Please try again later."
      @env.response.status_code = 429
      @env.response.headers["Retry-After"] = Fluence::LOGIN_THROTTLE.window.total_seconds.ceil.to_i.to_s
      return render "login.slang"
    end
    user = Fluence::USERS.auth! name, params.body["password"].to_s
    if user
      Fluence::LOGIN_THROTTLE.success!(address, name)
    else
      Fluence::LOGIN_THROTTLE.failure!(address, name)
    end
    # TODO: make a notification
    if user.nil?
      flash["danger"] = "User or password doesn't match."
      redirect_to "#{Fluence::OPTIONS.users_prefix}/login"
    else
      flash["success"] = "You are now logged in as user '#{user.name}'."
      start_session_for user.name
      set_login_cookies_for(user.name)
      redirect_to Fluence::OPTIONS.homepage
    end
  end

  # post /users/logout
  def logout
    acl_permit! :read
    forget_login_token
    session.destroy
    delete_login_cookies
    redirect_to "#{Fluence::OPTIONS.users_prefix}/login"
  end

  # get /users/register
  def register
    return unless registration_open!
    acl_permit! :read
    render "register.slang"
  end

  # post /users/register
  def register_validates
    return unless registration_open!
    acl_permit! :write
    # TODO: make a notification
    begin
      # The first user to register becomes admin; without that, a fresh
      # install would have no way to ever reach the admin interface.
      first_user = Fluence::USERS.load!.list.empty?
      groups = first_user ? %w[user admin] : %w[user]
      user = Fluence::USERS.register! params.body["username"].to_s, params.body["password"].to_s, groups
      flash["success"] = "You have now registered a new username '#{user.name}'. Please log in."
      flash["info"] = "As the first registered user, you have administrator rights." if first_user
      redirect_to "#{Fluence::OPTIONS.users_prefix}/login"
    rescue err
      flash["danger"] = "Cannot register this account: #{err.message}."
      redirect_to "#{Fluence::OPTIONS.users_prefix}/register"
    end
  end

  # get /users/settings
  def settings
    return unless signed_in!
    acl_permit! :read
    settings = current_user.settings
    title = "Settings - #{title()}"
    render "settings.slang"
  end

  # post /users/settings
  def settings_update
    return unless signed_in!
    acl_permit! :read
    name = current_user.name
    Fluence::USERS.transaction! { |users| users[name].settings.update! params.body }
    flash["success"] = "Your settings have been saved."
    redirect_to "#{Fluence::OPTIONS.users_prefix}/settings"
  end

  # post /users/password
  def password_update
    return unless signed_in!
    acl_permit! :read
    name = current_user.name
    password = params.body["new_password"]?.to_s
    if Fluence::USERS.auth!(name, params.body["current_password"]?.to_s).nil?
      flash["danger"] = "The current password is not correct."
    elsif password.empty?
      flash["danger"] = "The new password cannot be empty."
    elsif password != params.body["password_confirmation"]?
      flash["danger"] = "The new password and its confirmation do not match."
    else
      # Cookies issued under the old password stop working everywhere;
      # this browser gets a fresh one.
      token = ""
      Fluence::USERS.transaction! { |users| token = users[name].change_password!(password).issue_token! }
      write_login_cookies name, token
      flash["success"] = "Your password has been changed. Other browsers will have to log in again."
    end
    redirect_to "#{Fluence::OPTIONS.users_prefix}/settings"
  end

  # False, with a redirect to the login page queued, unless a user is
  # logged in.
  private def signed_in!
    uses_login_cookies
    return true if user_signed_in?
    flash["info"] = "Please log in to change your settings."
    redirect_to "#{Fluence::OPTIONS.users_prefix}/login"
    false
  end

  # False, with a flash and a redirect queued, when self-registration
  # is closed (FLUENCE_REGISTRATION=closed).
  private def registration_open!
    return true if Fluence::OPTIONS.registration_open?
    flash["info"] = "Registration is closed on this wiki. Ask an administrator for an account."
    redirect_to "#{Fluence::OPTIONS.users_prefix}/login"
    false
  end
end
