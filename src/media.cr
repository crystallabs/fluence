require "uri"

require "./file"
require "./errors"

# `Media` is a representation of something that can be accessed
# from a URL /media/*path.
#
# It associates a name (and URL) with content stored under "media/" in the
# wiki storage — typically attachments uploaded to a page, stored as
# "media/<page name>/<file name>".
class Fluence::Media < Fluence::File
	property slug : String # URL-friendly title

	def initialize(name : String)
		name = Media.sanitize(name).strip "/"
		title = ::File.basename name
		super("media/#{name}", name, "#{Fluence::OPTIONS.media_prefix}/#{name}", title)

		@slug = Media.title_to_slug @title

		jail!
	end

	def storage_prefix : String
		"media"
	end

	# Beginning of the URL
	def url_prefix : String
		Fluence::OPTIONS.media_prefix
	end

	# Translates a storage path ("media/test/file.png") into a media name
	# ("test/file.png"); nil for paths outside the media subtree.
	def self.storage_path_to_name(path : String) : String?
		return nil unless path.starts_with?("media/")
		path.lchop("media/")
	end

	# Media have no content-derived titles; names are used instead.
	def self.titled?
		false
	end

	def process!
		@slug = Media.title_to_slug @name
		self
	end

	def children1
		Fluence::MEDIA.children1 self
	end

	def children
		Fluence::MEDIA.children self
	end

	# Does any media entry exist below this one?
	def directory?
		prefix = @name + "/"
		Fluence::MEDIA.names.any? &.starts_with?(prefix)
	end

	# Renames the media without modifying the current Media object.
	# Returns the new Media object.
	def rename(user : Fluence::User, new_name, overwrite = false)
		rename_to Media.new(new_name), user, overwrite
	end

	# Renames the media, updates self, and returns self
	def rename!(user : Fluence::User, new_name, overwrite = false)
		new_page = rename user, new_name, overwrite
		@path = new_page.path
		@name = new_page.name
		@url = new_page.url
		process!

		self
	end

	def self.title_to_slug(title : String) : String
		title.gsub(/[^[:alnum:]^\/\.]+/, "-")
	end
end
