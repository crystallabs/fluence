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

  # Kind of entry as named in commit messages: "page" or "media".
  abstract def kind : String

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

  # Writes *body*, re-derives metadata, and returns self. *summary* is an
  # optional user-supplied description of the change for the commit message.
  def update!(user : Fluence::User, body, summary : String? = nil)
    write user, body, summary
    process!
    self
  end

  # Writes *body* as the new content, committing to git. The commit subject
  # names the action, kind, and entry ("Update page foo"); *summary* and
  # *details* go into the commit body.
  def write(user : Fluence::User, body, summary : String? = nil, details : String? = nil)
    jail!
    verb = exists? ? "Update" : create_verb
    storage.write @path, body, user, commit_message("#{verb} #{kind} #{@name}", summary, details)
  end

  # Deletes the content, committing to git.
  def delete(user : Fluence::User)
    jail!
    storage.delete @path, user, commit_message("Delete #{kind} #{@name}")
    self
  end

  # Verb used in the commit subject when the entry is first written.
  protected def create_verb : String
    "Create"
  end

  # Longest accepted user-supplied change summary, in characters.
  SUMMARY_LIMIT = 500

  # Assembles a git commit message: *subject* line, then the user's
  # *summary* (trimmed to `SUMMARY_LIMIT`) and *details* as paragraphs,
  # each omitted when empty.
  protected def commit_message(subject : String, summary : String? = nil, details : String? = nil) : String
    paragraphs = [subject]
    if summary = summary.try &.strip.presence
      paragraphs << summary[0, SUMMARY_LIMIT]
    end
    if details = details.try &.strip.presence
      paragraphs << details
    end
    paragraphs.join "\n\n"
  end

  def exists?
    jail!
    storage.exists? @path
  end

  # Commits that touched the entry, newest first (see `Storage#log`).
  def history(limit : Int32 = 0) : Array(Fluence::Storage::Commit)
    jail!
    storage.log @path, limit
  end

  # Content as of commit *rev* (see `Storage#read_at`).
  def read_at(rev : String) : String
    jail!
    storage.read_at @path, rev
  end

  # Unified diff of what commit *rev* did to the entry (see `Storage#diff`).
  def diff(rev : String) : String
    jail!
    storage.diff @path, rev
  end

  # Content size in bytes; 0 if absent.
  def size : Int64
    storage.size(@path) || 0_i64
  end

  # Renames this entry's content to *new_page*'s location, committing to
  # git together with any *extra_moves* (`{old_path, new_path}` pairs of
  # storage paths, e.g. a page's attachments). Neither object is mutated;
  # use the subclasses' `rename!` for that.
  protected def rename_to(new_page : Fluence::File, user : Fluence::User, overwrite = false,
                          extra_moves = [] of {String, String})
    jail!
    if name == new_page.name
      raise AlreadyExists.new "Old and new name are the same, renaming not possible."
    end
    new_page.jail!
    if new_page.exists? && !overwrite
      raise AlreadyExists.new %Q(Destination exists and overwriting was not requested. Do you want to visit the page #{new_page.name} instead?)
    end
    details = extra_moves.empty? ? nil : "Moved along:\n" + extra_moves.join("\n") { |old_path, new_path| "  #{old_path} -> #{new_path}" }
    storage.rename [{@path, new_page.path}] + extra_moves, user,
      commit_message("Rename #{kind} #{@name} -> #{new_page.name}", nil, details)
    new_page
  end

  def self.sanitize(text : String)
    self.title_to_slug URI.decode(text)
  end

  def self.title_to_slug(title : String) : String
    title.gsub(/[^[:alnum:]^\/]+/, "-").downcase
  end
end
