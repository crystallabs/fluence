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
  #   through regular `git add`/`commit`. Used automatically when the data
  #   directory is a checkout (contains `.git`); pages there may also be
  #   edited directly on the filesystem.
  abstract class Storage
    COMMITTER = {name: "Fluence Wiki", email: "fluence@localhost"}

    # One commit in the history of a file, as returned by `#log`.
    record Commit, oid : String, author : String, time : Time, subject : String, body : String do
      def short_oid : String
        oid[0, 8]
      end
    end

    # Shape of a revision accepted by `#read_at` and `#diff`: an abbreviated
    # or full commit hash. Symbolic names are deliberately rejected so a
    # revision coming from a URL can never be mistaken for a git option.
    REV = /\A[0-9a-f]{4,40}\z/

    # Field and record separators of the `git log` format parsed by `#parse_log`.
    LOG_FORMAT = "%H%x1f%an%x1f%at%x1f%s%x1f%b"

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

    # Renames every `{old_path, new_path}` pair in *moves* in one commit.
    abstract def rename(moves : Array({String, String}), user : Fluence::User, message : String)

    # Renames *old_path* to *new_path* and commits.
    def rename(old_path : String, new_path : String, user : Fluence::User, message : String)
      rename [{old_path, new_path}], user, message
    end

    # Returns the commits that touched *path*, newest first, following the
    # file across renames. At most *limit* commits when *limit* is positive.
    abstract def log(path : String, limit : Int32 = 0) : Array(Commit)

    # Returns the content of *path* as of commit *rev*, or raises `Error404`
    # when the revision is unknown or did not contain the file.
    abstract def read_at(path : String, rev : String) : String

    # Returns the unified diff of what commit *rev* did to *path* (empty when
    # the commit did not touch it), or raises `Error404` for an unknown revision.
    abstract def diff(path : String, rev : String) : String

    # Returns paths under *prefix* whose content matches *query*
    # (fixed string, case-insensitive).
    abstract def search(query : String, prefix : String) : Array(String)

    # Returns a map of path => first level-1 markdown heading ("# ..." line,
    # without the marker) for files under *prefix* that have one.
    abstract def headings(prefix : String) : Hash(String, String)

    # The directory to hand to git commands that take a repository argument
    # (`git upload-pack <dir>`, `git receive-pack <dir>`): the bare
    # repository itself, or the root of the working tree.
    abstract def git_directory : String

    protected def log_args(path : String, limit : Int32) : Array(String)
      args = ["log", "-z", "--follow", "--format=#{LOG_FORMAT}"]
      args << "--max-count=#{limit}" if limit > 0
      args + ["--", path]
    end

    protected def parse_log(output : String) : Array(Commit)
      output.split('\0', remove_empty: true).map do |record|
        oid, author, time, subject, body = record.split('\u001f', 5)
        Commit.new oid, author, Time.unix(time.to_i64), subject, body.to_s.strip
      end
    end

    # Arguments showing the diff commit *rev* made to *path*; a root commit
    # is compared against the empty tree, a merge against its first parent.
    protected def diff_args(path : String, rev : String) : Array(String)
      ["show", "--format=", "--no-color", "--diff-merges=first-parent", rev, "--", path]
    end

    protected def check_rev!(rev : String)
      raise Error404.new "No such revision: #{rev}" unless rev.matches? REV
    end

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
