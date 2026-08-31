require "uri"

require "./file"
require "./errors"
require "./page/*"

# `Page` is a representation of something that can be accessed
# from a URL /pages/*path.
#
# It associates a name (and URL) with content stored under "pages/" in the
# wiki storage. Title, table of contents, and internal links are derived
# from the content on demand via `process!`; nothing is cached.
class Fluence::Page < Fluence::File
	property slug : String  # URL-friendly title
	property toc : Page::TableOfContent::Toc
	property intlinks : Page::InternalLinks::LinkList

	def initialize(name : String)
		name = Page.sanitize(name).strip "/"
		title = ::File.basename name
		super("pages/#{name}.md", name, "#{Fluence::OPTIONS.pages_prefix}/#{name}", title)

		@slug = Page.title_to_slug @title
		@intlinks = Page::InternalLinks::LinkList.new
		@toc = Page::TableOfContent::Toc.new

		jail!
	end

	def storage_prefix : String
		"pages"
	end

	# Beginning of the URL
	def url_prefix : String
		Fluence::OPTIONS.pages_prefix
	end

	# Translates a storage path ("pages/test/title.md") into a page name
	# ("test/title"); nil for paths that are not wiki pages.
	def self.storage_path_to_name(path : String) : String?
		return nil unless path.starts_with?("pages/") && path.ends_with?(".md")
		path.lchop("pages/").chomp(".md")
	end

	# Pages take their display title from their first markdown heading.
	def self.titled?
		true
	end

	# Re-derives title, table of contents, and internal links from content.
	def process!
		content = exists? ? read : ""
		heading = content.each_line.find(&.starts_with?("# "))
		@title = heading ? heading.lchop("# ").strip : ::File.basename(@name)
		@slug = Page.title_to_slug @title
		@toc = Page::TableOfContent.toc content
		@intlinks = Page::InternalLinks.links_in_content content
		self
	end

	def children1
		Fluence::PAGES.children1 self
	end

	def children
		Fluence::PAGES.children self
	end

	# Does any page exist below this one?
	def directory?
		prefix = @name + "/"
		Fluence::PAGES.names.any? &.starts_with?(prefix)
	end

	# Renames the page without modifying the current Page object.
	# Returns the new Page object.
	def rename(user : Fluence::User, new_name, overwrite = false, subtree = false, intlinks = false)
		rename_to Page.new(new_name), user, overwrite
	end

	# Renames the page, updates self, and returns self. With *intlinks*,
	# [[internal links]] pointing at the old name are rewritten in all
	# other pages.
	def rename!(user : Fluence::User, new_name, overwrite = false, subtree = false, intlinks : Bool? = nil)
		old_name = @name
		new_page = rename user, new_name, overwrite
		@path = new_page.path
		@name = new_page.name
		@url = new_page.url
		process!

		update_links user, old_name if intlinks

		self
	end

	# Rewrites [[old_name]] and [[old_name|...]] links in all other pages to
	# point at this page's current name.
	private def update_links(user : Fluence::User, old_name : String)
		pattern = /(?<!\\)\[\[#{Regex.escape old_name}(?=\]\]|\|)/
		Fluence::PAGES.names.each do |name|
			next if name == @name
			page = Fluence::Page.new name
			content = page.read rescue next
			updated = content.gsub pattern, "[[#{@name}"
			page.write user, updated if updated != content
		end
	end
end
