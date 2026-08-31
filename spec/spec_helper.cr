# Point the app at throwaway directories before any option is read.
ENV["FLUENCE_DATADIR"] ||= File.tempname("fluence-spec-data")
ENV["FLUENCE_METADIR"] ||= File.tempname("fluence-spec-meta")

require "spec"
require "file_utils"

require "../src/lockable"
require "../config/options"
require "../src/errors"
require "../src/storage"
require "../src/catalog"
require "../src/acl"
require "../src/page"
require "../src/media"
require "../src/markdown"
require "../src/wikilink_migration"
require "../src/users/**"

# The catalogs normally defined by src/fluence.cr, which specs do not load.
module Fluence
  PAGES = Fluence::Catalog(Fluence::Page).new("pages")
  MEDIA = Fluence::Catalog(Fluence::Media).new("media")
end

SPEC_USER = Fluence::User.new "spec", "password", %w(user)

# Runs the block once per storage backend, each time on a fresh temporary
# repository assigned to `Fluence::Storage.current`.
def with_each_storage(&)
  {"bare git", "worktree"}.each do |kind|
    dir = File.tempname("fluence-spec-storage")
    Dir.mkdir_p dir
    storage = if kind == "bare git"
                Fluence::Storage::GitRepo.init(dir)
              else
                Fluence::Storage::WorkTree.init(dir)
              end
    Fluence::Storage.current = storage
    begin
      yield storage, kind
    ensure
      Fluence::Storage.current = nil
      FileUtils.rm_rf dir
    end
  end
end

# Full commit log of a spec storage, as "author <email> subject" lines.
def git_log(storage : Fluence::Storage) : String
  git_dir = case storage
            when Fluence::Storage::GitRepo  then storage.repo
            when Fluence::Storage::WorkTree then File.join(storage.root, ".git")
            else                                 raise "unknown storage"
            end
  output = IO::Memory.new
  Process.run("git", ["log", "--format=%an <%ae> %s"],
    env: {"GIT_DIR" => git_dir}, output: output, error: output)
  output.to_s
end
