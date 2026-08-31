require "uri"

require "./file"
require "./errors"
require "./page/*"

# `Page` is a representation of something that can be accessed
# from a URL /pages/*path.
#
# It is used to associate path, name (and URL), and data.
# Is is can also jails the path into the *OPTIONS.datadir* to be sure that
# there is no attack by writing files outside of the directory where the pages
# must be stored.
class Fluence::Page < Fluence::File

# Disabled for now due to:
# https://github.com/crystal-lang/crystal/issues/2827
#  include Fluence::Page::TableOfContent
#  include Fluence::Page::InternalLinks

	include YAML::Serializable

	property path : String  # absolute path of the file, e.g. /srv/wiki/data/pages/xxx
	property name : String  # name of the page, e.g. xxx or xxx/subpage1
	property url : String   # real url of the page /pages/xxx
	property title : String # Any title
	property slug : String  # URL-friendly title
	property toc : Page::TableOfContent::Toc
	property intlinks : Page::InternalLinks::LinkList
	property modification_time : Time
	property size : Int64

	def initialize(name : String)
    name = Page.sanitize(name).strip "/"
		url = url_prefix + "/" + name
    path = Page.name_to_directory(name)+ ".md"

		# Needed due to https://github.com/crystal-lang/crystal/issues/2827
		title = ::File.basename name
		super(path,name,url,title)

		@slug = Page.title_to_slug @title
		@intlinks = Page::InternalLinks::LinkList.new
		@toc = Page::TableOfContent::Toc.new

		# This data will be inaccurate (i.e. be current time) if an existing page
		# is created with Fluence::Page.new("existing_name") and #process! is not called.
		@modification_time = Time.local
		@size = 0_i64

    jail!
	end

  # translates a name ("/test/title" for example)
  # into a file path ("/srv/data/test/title.md)
  def self.name_to_path(name : String)
    name_to_directory(name) + ".md"
  end

	def process!
		# TODO read all this from one copy of contents
    title = ::File.read(@path).split("\n").find { |l| l.starts_with? "# " }
    @title = if title; title.strip("# ").strip else @name.sub /^.+\//, "" end
		@slug = Page.title_to_slug @title
		@toc = Page::TableOfContent.toc @path
		@intlinks = Page::InternalLinks.intlinks @path
		fi = ::File.info(@path)
		@modification_time = fi.modification_time
		@size = fi.size
		self
	end

  # Directory where the pages are stored
  def self.subdirectory
    ::File.join(Fluence::OPTIONS.datadir, "pages") + ::File::SEPARATOR
  end

  # Beginning of the URL
  def url_prefix : String
    Fluence::OPTIONS.pages_prefix
  end

	def children1
		Fluence::PAGES.children1 self
	end

	def children
		Fluence::PAGES.children self
	end

  # Renames the page without modifying the current Page object.
	# Returns the new Page object where only path, name, and url fields may be correct and/or initialized.
  def rename(user : Fluence::User, new_name, overwrite = false, subtree = false, git = true, intlinks = false)
    jail!
    Dir.mkdir_p ::File.dirname new_name
		if name == new_name
			raise AlreadyExists.new "Old and new name are the same, renaming not possible."
		end

		# Mostly disposable, here just to check jail.
		new_page = Page.new new_name
		new_page.jail!

		# TODO instead of raising, add flash message and skip
		# It would be sufficient to check the Index for existence of page,
		# but given that unintended deletions/overwrites of content can be
		# a problem, test in a more certain way by testing file existence.
		if ::File.exists?(new_page.path) && !overwrite
			raise AlreadyExists.new %Q(Destination exists and overwriting was not requested. Do you want to visit the page #{new_page.name} instead?)
		else
			Dir.mkdir_p ::File.dirname new_page.path
			::File.rename path, new_page.path
			files = [new_page.path]

			if git
				commit! user, "rename", other_files: files
			end
		end

		Fluence::Page.new new_name
  end

	# Renames the page, updates self, and returns self
	def rename!(user : Fluence::User, new_name, overwrite = false, subtree = false, git = true, intlinks : Bool? = nil)
		old_name = @name
		new_page = rename user, new_name, overwrite, subtree, git, intlinks
		@path = new_page.path
		@name = new_page.name
		@url = new_page.url
		jail!
		process!

		if intlinks
			Fluence::PAGES.entries.each do |_,p|
				p.intlinks.each_with_index do |l, i|
					p.intlinks[i] = { l[0], l[1].gsub /^#{old_name}(?=\/|$)/, @name }
					p.jail! # Just in case
					content = ::File.read p.path
					content = content .gsub /(?<!\\)\[\[#{old_name}\]\]/, "[[" + @name + "]]"
					::File.write p.path, content
				end
			end
		end

		self
	end

	def directory
		@path.chomp ".md"
	end

	def directory?
		::File.exists? directory
	end
end
