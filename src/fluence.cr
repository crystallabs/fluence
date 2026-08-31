require "markd"
require "yaml"
require "json"
require "kemal"
require "kemal-session"
require "kilt/slang"

require "./flash"

require "./version"
require "./controllers/application_controller"
require "../config/routes"
require "../config/application"
require "../config/options"
require "./lockable"
require "./errors"
require "./git"
require "./**"

Kemal.config.host_binding = Fluence::OPTIONS.host
Kemal.config.port = Fluence::OPTIONS.port

module Fluence
  Dir.mkdir_p Fluence::OPTIONS.metadir
	Dir.mkdir_p Fluence::Page.subdirectory
	Dir.mkdir_p Fluence::Media.subdirectory

  DEFAULT_USER = Fluence::User.new *Fluence::OPTIONS.guest

  # The list of users is stored in *meta/users*. This file is updated when
  # a user is created/modified/deleted, but data is stored in RAM for
  # efficiency.
  USERS = Fluence::Users.new("#{Fluence::OPTIONS.metadir}/users", DEFAULT_USER).load!

  # The list of permissions (group => path+permission) is stored in
  # file *meta/acl*. Similar behavior like `USERS`.
  ACL = Acl::Groups.new("#{Fluence::OPTIONS.metadir}/acl").load!

  # If there is no "guest" ACL, we assume that the ACL have not been initialized yet
  # and we create a group "guest" and "user".
  # TODO: a proper "installation" procedure should be made to avoid these kind
  # of operation in a scope
  if ACL["guest"]?.nil?
    ACL.add("guest")
    ACL["guest"]["#{Fluence::OPTIONS.users_prefix}/*"] = Acl::Perm::Write
    ACL["guest"]["/sitemap"] = Acl::Perm::Read
    ACL["guest"]["#{Fluence::OPTIONS.pages_prefix}/*"] = Acl::Perm::Read
    ACL["guest"]["#{Fluence::OPTIONS.media_prefix}/*"] = Acl::Perm::Read
    ACL["guest"]["/"] = Acl::Perm::Read
    ACL.add("user")
    ACL["user"]["/*"] = Acl::Perm::Read
    ACL["user"]["#{Fluence::OPTIONS.users_prefix}/login"] = Acl::Perm::None
    ACL["user"]["#{Fluence::OPTIONS.users_prefix}/register"] = Acl::Perm::None
    ACL["user"]["#{Fluence::OPTIONS.pages_prefix}/*"] = Acl::Perm::Write
    ACL["user"]["#{Fluence::OPTIONS.media_prefix}/*"] = Acl::Perm::Write
    ACL["user"]["#{Fluence::OPTIONS.admin_prefix}/*"] = Acl::Perm::Write
    ACL.save!
  end

  # The list of pages with a lot of meta-data. Same behavior like
  # `USERS` and `ACL`.
	# An existing but empty index is rebuilt from disk contents: index files
	# written by Fluence <= 0.6 were always empty due to a bug, and rebuilding
	# also heals a manually truncated index.
	PAGES = begin
		idx = if ::File.exists? "#{Fluence::OPTIONS.metadir}/pages"
			Fluence::Index(Fluence::Page).new("pages").load!
		else
			Fluence::Index(Fluence::Page).build("pages")
		end
		idx.entries.empty? ? Fluence::Index(Fluence::Page).build("pages") : idx
	end

  # The list of media with a lot of meta-data. Same behavior like
  # `USERS` and `ACL`.
	MEDIA = begin
		idx = if ::File.exists? "#{Fluence::OPTIONS.metadir}/media"
			Fluence::Index(Fluence::Media).new("media").load!
		else
			Fluence::Index(Fluence::Media).build("media")
		end
		idx.entries.empty? ? Fluence::Index(Fluence::Media).build("media") : idx
	end

#	# Install file watcher on data files.
#	# Exact use of the triggers is to be determined later.
#	# (It could be used to catch file modifications which happen
#	# outside of the wiki, and to automatically update the wiki
#	# index. This could be made to work live and report live stream
#	# of page and media changes to some admin page)
#	watch "data/**/*" do |e|
#		"Detected #{e.status} for file #{e.name}"
#	end
end

Kemal.run
