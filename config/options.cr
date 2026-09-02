# Please configure the defaults to your needs.

module Fluence

  # Application config. Feel free to tune the instance variables.
  class Options
    def initialize

      # Host/port to listen on.
      @host = "0.0.0.0"
      @port = 3000

      # Brand name, full name (including optional credit to Fluence Wiki), and logo.
      @brand = "Fluence"
      @brand_info = "#{@brand} - Fluence Wiki"
      @brand_logo = "/logo.png"

      # The username, password, and default groups that the default/unauthenticated
      # user should have.
      @guest = { "guest", "guest", %w(guest) }

      # Location of data/ and meta/ directories. Defaults to $PWD/{data,meta}
      @datadir = ::File.expand_path ENV.fetch("FLUENCE_DATADIR", "data"), Dir.current
      @metadir = ::File.expand_path ENV.fetch("FLUENCE_METADIR", "meta"), Dir.current

      # Directory of static assets (stylesheets, scripts, logo), served at
      # the site root. Defaults to the public/ directory of the source tree
      # Fluence was compiled from, so the binary can be started from any
      # working directory. When that tree is not available at runtime (e.g.
      # a binary from a release tarball), the public/ directory next to the
      # executable is used, then public/ in the working directory. Override
      # with FLUENCE_PUBLICDIR.
      @publicdir = ::File.expand_path ENV.fetch("FLUENCE_PUBLICDIR") { default_publicdir }

      # Visible part of URL through which pages are accessed, e.g. /pages/my_page
      @pages_prefix = "/pages"
      # Start page - homepage. Defaults to /pages/home
      @homepage = "#{@pages_prefix}/home"

      # Visible part of URL through which media is accessed, e.g. /media/my_page/my_file1.pdf
      @media_prefix = "/media"

      # URL through which pages are looked up by title rather than by name,
      # e.g. /titles/calendar shows every page titled "Calendar" (or named
      # .../calendar), concatenated when there is more than one.
      @titles_prefix = "/titles"

      # Location of users and admin interfaces
      @users_prefix = "/users"
      @admin_prefix = "/admin"

      # URL through which the wiki repository is served over the git smart
      # HTTP protocol, e.g. `git clone http://wiki.host:3000/repo`.
      # Fetching requires Read and pushing requires Write permission on
      # this path (see README, "Git access over HTTP").
      @repo_prefix = "/repo"

      # Self-registration mode: "open" (anyone can register) or "closed"
      # (only admins can add users, through the admin interface).
      # Regardless of the mode, the first user to register becomes admin.
      @registration = ENV.fetch("FLUENCE_REGISTRATION", "open")

      # Send cookies with the Secure attribute, so browsers only transmit
      # them over HTTPS. Enable (set FLUENCE_SECURE_COOKIES to any value)
      # when serving Fluence over TLS or behind an HTTPS reverse proxy;
      # off by default because the default setup is plain HTTP.
      @secure_cookies = !ENV["FLUENCE_SECURE_COOKIES"]?.nil?

      # Do all, or only new, and/or only empty pages, open in edit mode by default?
      # By default, only new pages open in edit mode; existing and empty pages open in view mode.
      @open_in_edit = false
      @open_new_in_edit = true
      @open_empty_in_edit = false

      #
      # No need to configure anything below this point in the file.
      #

      Dir.mkdir_p @datadir
      Dir.mkdir_p @metadir
    end

    getter host : String
    getter port : Int32
    getter brand : String
    getter brand_info : String
    getter brand_logo : String
    getter guest
    getter datadir : String
    getter metadir : String
    getter publicdir : String
    getter homepage : String
    getter pages_prefix : String
    getter media_prefix : String
    getter titles_prefix : String
    getter users_prefix : String
    getter admin_prefix : String
    getter repo_prefix : String
    getter secure_cookies : Bool
    property registration : String

    def registration_open?
      @registration != "closed"
    end
    getter open_in_edit : Bool
    getter open_new_in_edit : Bool
    getter open_empty_in_edit : Bool

    # First existing candidate for the static assets directory, or the source
    # tree's public/ if none exists, so the error names the expected path.
    private def default_publicdir : String
      source = ::File.join(__DIR__, "..", "public")
      candidates = [source, "public"]
      if exe = Process.executable_path
        candidates.insert 1, ::File.join(::File.dirname(exe), "public")
      end
      candidates.find(source) { |dir| ::Dir.exists? dir }
    end
  end

  OPTIONS = Fluence::Options.new
end
