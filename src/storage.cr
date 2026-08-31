require "../config/options"
require "./errors"

module Fluence
  # Storage is the interface to the wiki content. All paths are repo-relative
  # POSIX paths such as "pages/foo/bar.md" or "media/foo/file.png"; there is
  # no other state — the git repository (or the working tree backed by one)
  # is the single source of truth, so external modifications are always
  # visible without any cache or index to rebuild.
  #
  # Two implementations exist:
  #
  # - `Storage::GitRepo` operates directly on a (usually bare) git repository:
  #   reads come from HEAD via `git cat-file`/`ls-tree`, and writes create
  #   commits with the plumbing commands, without any checkout. This is the
  #   default for new installations; external contributions arrive via
  #   `git push`.
  # - `Storage::WorkTree` operates on a checked-out working tree and commits
  #   through regular `git add`/`commit`. Used automatically for existing
  #   pre-0.7 data directories, where pages may also be edited directly on
  #   the filesystem.
  abstract class Storage
    COMMITTER = {name: "Fluence Wiki", email: "fluence@localhost"}

    @@current : Storage?

    # The storage instance in use. Auto-detected from the data directory on
    # first use; specs and tools may assign their own.
    def self.current : Storage
      @@current ||= detect
    end

    def self.current=(storage : Storage?)
      @@current = storage
    end

    # Picks the storage implementation for `Fluence::OPTIONS.datadir`:
    # an existing bare repository or working tree is used as-is; otherwise a
    # new bare repository is created (or a working tree, if the environment
    # variable FLUENCE_STORAGE is set to "worktree").
    def self.detect : Storage
      dir = Fluence::OPTIONS.datadir
      if ::File.exists?(::File.join(dir, "HEAD")) && ::Dir.exists?(::File.join(dir, "objects"))
        GitRepo.new dir
      elsif ::Dir.exists?(::File.join(dir, ".git"))
        WorkTree.new dir
      elsif ENV["FLUENCE_STORAGE"]? == "worktree"
        WorkTree.init dir
      else
        GitRepo.init dir
      end
    end

    # Returns the content of the file at *path*, or raises `Error404`.
    abstract def read(path : String) : String

    abstract def exists?(path : String) : Bool

    # Returns the size in bytes of the file at *path*, or nil if absent.
    abstract def size(path : String) : Int64?

    # Returns all file paths under *prefix* (e.g. "pages"), repo-relative.
    abstract def list(prefix : String) : Array(String)

    # Writes *content* to *path* and commits, attributing *user* as author.
    abstract def write(path : String, content : String | IO, user : Fluence::User, message : String)

    # Deletes the file at *path* and commits.
    abstract def delete(path : String, user : Fluence::User, message : String)

    # Renames *old_path* to *new_path* and commits.
    abstract def rename(old_path : String, new_path : String, user : Fluence::User, message : String)

    # Returns paths under *prefix* whose content matches *query*
    # (fixed string, case-insensitive).
    abstract def search(query : String, prefix : String) : Array(String)

    # Returns a map of path => first level-1 markdown heading ("# ..." line,
    # without the marker) for files under *prefix* that have one.
    abstract def headings(prefix : String) : Hash(String, String)

    # Environment for git commands: pins the committer identity so no host
    # or repository git configuration is required, and sets the author to
    # the acting wiki user.
    protected def git_env(user : Fluence::User? = nil) : Hash(String, String)
      env = {
        "GIT_COMMITTER_NAME"  => COMMITTER[:name],
        "GIT_COMMITTER_EMAIL" => COMMITTER[:email],
      }
      if user
        env["GIT_AUTHOR_NAME"] = user.name
        env["GIT_AUTHOR_EMAIL"] = "#{user.name}@localhost"
      end
      env
    end
  end
end

require "./users/user"
require "./storage/work_tree"
require "./storage/git_repo"
