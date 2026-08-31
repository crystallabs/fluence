class UsersController < ApplicationController
  # get /users/login
  def login
    acl_permit! :read
    render "login.slang"
  end

  # post /users/login
  def login_validates
    acl_permit! :write
    user = Fluence::USERS.auth! params.body["username"].to_s, params.body["password"].to_s
    # TODO: make a notification
    if user.nil?
      flash["danger"] = "User or password doesn't match."
      redirect_to "#{Fluence::OPTIONS.users_prefix}/login"
    else
      flash["success"] = "You are now logged in as user '#{user.name}'."
      session.string("user.name", user.name)
      set_login_cookies_for(user.name)
      redirect_to Fluence::OPTIONS.homepage
    end
  end

  # get /users/logout
  def logout
    acl_permit! :read
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

  # False, with a flash and a redirect queued, when self-registration
  # is closed (FLUENCE_REGISTRATION=closed).
  private def registration_open!
    return true if Fluence::OPTIONS.registration_open?
    flash["info"] = "Registration is closed on this wiki. Ask an administrator for an account."
    redirect_to "#{Fluence::OPTIONS.users_prefix}/login"
    false
  end
end
