require "uri"

require "./errors"
require "./page/*"

# `Media` is a representation of something that can be accessed
# from a URL /media/*path.
#
# As much as possible here should come from Fluence::File.
class Fluence::Media < Fluence::File

	include YAML::Serializable

	# path, name, url, and title are declared in Fluence::File and
	# serialized here through YAML::Serializable's inherited-ivar walk.
	property slug : String # URL-friendly title
	property modification_time : Time
	property size : Int64

	def initialize(name : String)
    name = Media.sanitize(name).strip "/"
		url = url_prefix + "/" + name
    path = Media.name_to_directory(name)

		# Needed due to https://github.com/crystal-lang/crystal/issues/2827
		title = ::File.basename name
		super(path,name,url,title)

		@slug = Media.title_to_slug @title

		# This data will be inaccurate (i.e. be current time) if an existing page
		# is created with Fluence::Media.new("existing_name") and #process! is not called.
		@modification_time = Time.local
		@size = 0_i64

    jail!
	end

  # Directory where media is stored
  def self.subdirectory
		::File.join(Fluence::OPTIONS.datadir, "media") + ::File::SEPARATOR
	end

  # Beginning of the URL
	def url_prefix : String
		Fluence::OPTIONS.media_prefix
	end

  # Renames the page without modifying the current Media object.
  # Returns the new Media object where only path, name, and url fields may be correct and/or initialized.
  def rename(user : Fluence::User, new_name, overwrite = false, git = true)
    jail!
    Dir.mkdir_p ::File.dirname new_name
    if name == new_name
      raise AlreadyExists.new "Old and new name are the same, renaming not possible."
    end

    # Mostly disposable, here just to check jail.
    new_page = Media.new new_name
    new_page.jail!

    # TODO instead of raising, add flash message and skip
    # It would be sufficient to check the Index for existence of page,
    # but given that unintended deletions/overwrites of content can be
    # a problem, test in a more certain way by testing file existence.
    if ::File.exists?(new_page.path) && !overwrite
      raise AlreadyExists.new %Q(Destination exists and overwriting was not requested. Do you want to open #{new_page.name} instead?)
    else
      Dir.mkdir_p ::File.dirname new_page.path
      ::File.rename path, new_page.path
      files = [new_page.path]

      if git
        commit! user, "rename", other_files: files
      end
    end

    Fluence::Media.new new_name
  end

  # Renames the page, updates self, and returns self
  def rename!(user : Fluence::User, new_name, overwrite = false, git = true)
    new_page = rename user, new_name, overwrite, git
    @path = new_page.path
    @name = new_page.name
    @url = new_page.url
    jail!
    process!

    self
  end

  def process!
    #@title = # Can we read it out from media files?
    @slug = Media.title_to_slug @name
    fi = ::File.info(@path)
    @modification_time = fi.modification_time
    @size = fi.size
    self
  end

  # translates a name ("/test/title" for example)
  # into a file path ("/srv/data/test/title)
  def self.name_to_path(name : String)
    name_to_directory(name)
  end


	# These are here but should just return [] since we don't use sub-content with media
	def children1
		Fluence::MEDIA.children1 self
	end
	def children
		Fluence::MEDIA.children self
	end

	def directory
		@path.sub /\/[^\/]+?$/, ""
	end

	def directory?
		Dir.exists? self.class.name_to_path(@name)
	end

	def self.title_to_slug(title : String) : String
		title.gsub(/[^[:alnum:]^\/\.]+/, "-")
	end
end
