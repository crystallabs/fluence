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

      # Visible part of URL through which pages are accessed, e.g. /pages/my_page
      @pages_prefix = "/pages"
      # Start page - homepage. Defaults to /pages/home
      @homepage = "#{@pages_prefix}/home"

      # Visible part of URL through which media is accessed, e.g. /media/my_page/my_file1.pdf
      @media_prefix = "/media"

      # Location of users and admin interfaces
      @users_prefix = "/users"
      @admin_prefix = "/admin"

      # Recursion limit for any recursive functions
      @recursion_limit = 1000

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
    getter homepage : String
    getter pages_prefix : String
    getter media_prefix : String
    getter users_prefix : String
    getter admin_prefix : String
    getter recursion_limit : Int32
    getter open_in_edit : Bool
    getter open_new_in_edit : Bool
    getter open_empty_in_edit : Bool
  end

  OPTIONS = Fluence::Options.new
end
