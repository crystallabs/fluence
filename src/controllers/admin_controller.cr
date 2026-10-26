class AdminController < ApplicationController
  # get /admin/users
  def users_show
    acl_permit! :write
    users = Fluence::USERS.load!
    render "users_show.slang"
  end

  # post /admin/users/create
  def user_create
    acl_permit! :write
    username = params.body["username"]
    password = params.body["password"]
    groups = params.body["groups"].split(",").map(&.strip)
    begin
      user = Fluence::USERS.register! username, password, groups
      flash["success"] = "The user #{user.name} has been added."
    rescue err
      flash["danger"] = "Cannot register this account: #{err.message}."
    end
    redirect_to "#{Fluence::OPTIONS.admin_prefix}/users"
  end

  # post /admin/users/password
  def user_password
    acl_permit! :write
    attempt do
      username = params.body["username"]
      Fluence::USERS.transaction! { |users| users[username].change_password! params.body["password"] }
      flash["success"] = "The password of user #{username} has been reset."
    end
    redirect_to "#{Fluence::OPTIONS.admin_prefix}/users"
  end

  # post /admin/users/delete
  #
  # The last member of the "admin" group is never deleted: nobody could
  # reach the admin interface afterwards.
  def user_delete
    acl_permit! :write
    attempt do
      username = params.body["username"]
      deleted = false
      Fluence::USERS.transaction! do |users|
        user = users[username]
        next if user.group?("admin") && users.list.values.count(&.group?("admin")) <= 1
        users.delete username
        deleted = true
      end
      if deleted
        flash["success"] = "The user #{username} has been deleted."
      else
        flash["danger"] = "The user #{username} is the last administrator and cannot be deleted."
      end
    end
    redirect_to "#{Fluence::OPTIONS.admin_prefix}/users"
  end

  # get /admin/acls
  def acls_show
    acl_permit! :write
    acls = Fluence::ACL.load!
    render "acls_show.slang"
  end

  # post /admin/acls/create
  def acl_create
    acl_permit! :write
    attempt do
      group = params.body["group"]
      path = params.body["path"]
      perm = Acl::PERM_STR[params.body["perm"]]
      Fluence::ACL.transaction! do |acls|
        acls.add group unless acls[group]?
        acls[group][path] = perm
      end
      flash["success"] = "ACL #{group} :: #{path} :: #{perm} has been added."
    end
    redirect_to "#{Fluence::OPTIONS.admin_prefix}/acls"
  end

  # post /admin/acls/update
  def acl_update
    acl_permit! :write
    attempt do
      group = params.body["group"]
      path = params.body["path"]
      perm = Acl::PERM_STR[params.body["change"]]
      Fluence::ACL.transaction! do |acls|
        acls[group][path] = perm
      end
      flash["success"] = "ACL #{group} :: #{path} :: #{perm} has been updated."
    end
    redirect_to "#{Fluence::OPTIONS.admin_prefix}/acls"
  end

  # post /admin/acls/delete
  def acl_delete
    acl_permit! :write
    attempt do
      group = params.body["group"]
      path = params.body["path"]
      Fluence::ACL.transaction! do |acls|
        acls[group].delete path
      end
      flash["success"] = "ACL #{group} :: #{path} has been deleted."
    end
    redirect_to "#{Fluence::OPTIONS.admin_prefix}/acls"
  end

  # Runs the block; a failure (missing form field, unknown group or
  # user...) becomes a flash message instead of an error page.
  private def attempt(&)
    yield
  rescue err
    flash["danger"] = "Unable to process that: #{err.message}."
  end
end
