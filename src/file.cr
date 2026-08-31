require "./errors"
require "./storage"

# `File` is a representation of anything that can be accessed
# via some sort of an URL and has ACLs applying to it.

# It is used to associate storage path, url and data.
#
# Pages and Media are two primary uses.
#
# Content lives in `Fluence::Storage` under a repo-relative path such as
# "pages/foo.md"; `jail!` ensures the path cannot escape the class' subtree.
abstract class Fluence::File
  class AlreadyExists < Exception
  end

  # Repo-relative storage path, e.g. "pages/foo/bar.md"
  property path : String

  # Name of the entry, e.g. "foo/bar"
  property name : String

  # Complete URL of the entry
  property url : String

  # Title of the entry
  property title : String

  def initialize(@path, @name, @url, @title)
  end

  abstract def url_prefix : String

  # Storage subtree this class lives under, e.g. "pages".
  abstract def storage_prefix : String

  # Re-derives metadata (title etc.) from the current content.
  abstract def process!

  protected def storage : Fluence::Storage
    Fluence::Storage.current
  end

  # Verifies that the storage path is normalized and stays within this
  # class' subtree (no "..", absolute paths, etc.), raising `Error403`
  # otherwise.
  def jail!
    prefix = "#{storage_prefix}/"
    normalized = Path.posix(@path).normalize.to_s
    unless normalized == @path && @path.starts_with?(prefix) && @path.size > prefix.size
      raise Error403.new "Out of chroot (#{@path} on #{prefix})"
    end
    self
  end

  # Reads the content.
  def read
    jail!
    storage.read @path
  end

  def update!(user : Fluence::User, body)
    write user, body
    process!
    self
  end

  # Writes *body* as the new content, committing to git.
  def write(user : Fluence::User, body)
    jail!
    action = exists? ? "update" : "create"
    storage.write @path, body, user, "#{action} #{@name}"
  end

  # Deletes the content, committing to git.
  def delete(user : Fluence::User)
    jail!
    storage.delete @path, user, "delete #{@name}"
    self
  end

  def exists?
    jail!
    storage.exists? @path
  end

  # Content size in bytes; 0 if absent.
  def size : Int64
    storage.size(@path) || 0_i64
  end

  # Renames this entry's content to *new_page*'s location, committing to
  # git. Neither object is mutated; use the subclasses' `rename!` for that.
  protected def rename_to(new_page : Fluence::File, user : Fluence::User, overwrite = false)
    jail!
    if name == new_page.name
      raise AlreadyExists.new "Old and new name are the same, renaming not possible."
    end
    new_page.jail!
    if new_page.exists? && !overwrite
      raise AlreadyExists.new %Q(Destination exists and overwriting was not requested. Do you want to visit the page #{new_page.name} instead?)
    end
    storage.rename @path, new_page.path, user, "rename #{@name} -> #{new_page.name}"
    new_page
  end

  def self.sanitize(text : String)
    self.title_to_slug URI.decode(text)
  end

  def self.title_to_slug(title : String) : String
    title.gsub(/[^[:alnum:]^\/]+/, "-").downcase
  end
end
