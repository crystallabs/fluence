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

	def kind : String
		"page"
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
		@intlinks = Page::InternalLinks.links_in_content content, @name
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

	# Storage paths of this page's attachments ("media/<name>/...").
	def attachment_paths : Array(String)
		storage.list "media/#{@name}/"
	end

	# Renames the page without modifying the current Page object. The
	# page's attachments move with it, in the same commit.
	# Returns the new Page object.
	def rename(user : Fluence::User, new_name, overwrite = false, subtree = false, intlinks = false)
		new_page = Page.new(new_name)
		old_prefix = "media/#{@name}/"
		moves = attachment_paths.map { |path| {path, "media/#{new_page.name}/#{path.lchop old_prefix}"} }
		rename_to new_page, user, overwrite, moves
	end

	# Renames the page (with its attachments), updates self, and returns
	# self. Links to the moved attachments are rewritten in the page itself;
	# with *intlinks*, links pointing at the old page name (and at its
	# attachments) are rewritten in all other pages too.
	def rename!(user : Fluence::User, new_name, overwrite = false, subtree = false, intlinks : Bool? = nil)
		old_name = @name
		new_page = rename user, new_name, overwrite
		@path = new_page.path
		@name = new_page.name
		@url = new_page.url

		rewrite_attachment_links user, old_name, self
		update_links user, old_name if intlinks
		process!

		self
	end

	# URL under which the attachments of the page named *name* live.
	private def media_url_for(name : String) : String
		"#{Fluence::OPTIONS.media_prefix}/#{name}"
	end

	# Rewrites links to attachments of the page formerly named *old_name*
	# in *page* to their new location. No-op when nothing changes.
	private def rewrite_attachment_links(user : Fluence::User, old_name : String, page : Page)
		content = page.read rescue return
		updated = Page::InternalLinks.rewrite_prefix content, media_url_for(old_name), media_url_for(@name)
		return if updated == content
		page.write user, updated, nil, "Rewrite attachment links after renaming page #{old_name} -> #{@name}"
	end

	# Rewrites markdown links resolving to *old_name*, and links to its
	# attachments, in all other pages to point at this page's current name.
	private def update_links(user : Fluence::User, old_name : String)
		Fluence::PAGES.names.each do |name|
			next if name == @name
			page = Fluence::Page.new name
			content = page.read rescue next
			updated = Page::InternalLinks.rewrite_links content, name, old_name, @url
			updated = Page::InternalLinks.rewrite_prefix updated, media_url_for(old_name), media_url_for(@name)
			next if updated == content
			page.write user, updated, nil, "Update links after renaming page #{old_name} -> #{@name}"
		end
	end
end
