module Fluence
  # Storage directly on a git repository — normally a bare one — with no
  # checkout at all. Reads come from the HEAD commit via `git cat-file` and
  # `git ls-tree`; writes build a new commit with the plumbing commands
  # (`hash-object`, `read-tree` into a temporary index, `write-tree`,
  # `commit-tree`, `update-ref`). Since nothing is ever checked out, there
  # is no working copy to go stale: external contributions are simply
  # pushed into the repository and are visible on the next request.
  class Storage::GitRepo < Storage
    getter repo : String

    @lock = Mutex.new

    def initialize(repo : String)
      @repo = ::File.expand_path repo
    end

    # Creates a new bare repository at *repo*.
    def self.init(repo : String) : GitRepo
      ::Dir.mkdir_p repo
      storage = new repo
      storage.git! ["init", "--bare", storage.repo]
      storage
    end

    def git_directory : String
      @repo
    end

    def read(path : String) : String
      status, output = git ["cat-file", "blob", "HEAD:#{path}"]
      raise Error404.new "No such file: #{path}" unless status.success?
      output
    end

    def exists?(path : String) : Bool
      return false unless head
      status, _ = git ["cat-file", "-e", "HEAD:#{path}"]
      status.success?
    end

    def size(path : String) : Int64?
      status, output = git ["cat-file", "-s", "HEAD:#{path}"]
      status.success? ? output.strip.to_i64? : nil
    end

    def list(prefix : String) : Array(String)
      return [] of String unless head
      status, output = git ["ls-tree", "-r", "--name-only", "-z", "HEAD", "--", prefix]
      return [] of String unless status.success?
      output.split('\0', remove_empty: true).sort!
    end

    def write(path : String, content : String | IO, user : Fluence::User, message : String)
      @lock.synchronize do
        blob = hash_object content
        commit(user, message) do |index_env|
          git! ["update-index", "--add", "--cacheinfo", "100644,#{blob},#{path}"], env: index_env
        end
      end
    end

    def delete(path : String, user : Fluence::User, message : String)
      @lock.synchronize do
        raise Error404.new "No such file: #{path}" unless exists? path
        commit(user, message) do |index_env|
          index_remove path, index_env
        end
      end
    end

    def rename(old_path : String, new_path : String, user : Fluence::User, message : String)
      @lock.synchronize do
        status, blob = git ["rev-parse", "HEAD:#{old_path}"]
        raise Error404.new "No such file: #{old_path}" unless status.success?
        commit(user, message) do |index_env|
          index_remove old_path, index_env
          git! ["update-index", "--add", "--cacheinfo", "100644,#{blob.strip},#{new_path}"], env: index_env
        end
      end
    end

    def search(query : String, prefix : String) : Array(String)
      return [] of String unless head
      status, output = git ["grep", "-I", "-i", "-l", "-z", "--fixed-strings",
                            "-e", query, "HEAD", "--", prefix]
      return [] of String unless status.success?
      output.split('\0', remove_empty: true).map &.lchop("HEAD:")
    end

    def headings(prefix : String) : Hash(String, String)
      ret = {} of String => String
      return ret unless head
      status, output = git ["grep", "-I", "-m1", "-e", "^# ", "HEAD", "--", prefix]
      return ret unless status.success?
      output.each_line do |line|
        path, _, heading = line.lchop("HEAD:").partition(":# ")
        next if heading.empty?
        ret[path] = heading.strip
      end
      ret
    end

    # Runs git against the repository; returns the status and combined output.
    protected def git(args : Array(String), env : Hash(String, String)? = nil,
                      input : IO = IO::Memory.new) : {Process::Status, String}
      full_env = {"GIT_DIR" => @repo}
      full_env.merge! env if env
      output = IO::Memory.new
      status = Process.run("git", args, env: full_env, input: input,
        output: output, error: output)
      {status, output.to_s}
    end

    protected def git!(args : Array(String), env : Hash(String, String)? = nil,
                       input : IO = IO::Memory.new) : String
      status, output = git args, env: env, input: input
      raise Error.new "git #{args.first?} failed: #{output}" unless status.success?
      output
    end

    private def head : String?
      status, output = git ["rev-parse", "--verify", "--quiet", "HEAD"]
      status.success? ? output.strip : nil
    end

    # Removes *path* from the temporary index. `update-index --force-remove`
    # insists on a work tree, but the --index-info form with mode 0 works
    # in a bare repository too.
    private def index_remove(path : String, index_env : Hash(String, String))
      git! ["update-index", "--index-info"], env: index_env,
        input: IO::Memory.new("0 #{"0" * 40}\t#{path}\n")
    end

    private def hash_object(content : String | IO) : String
      input = content.is_a?(String) ? IO::Memory.new(content) : content
      git!(["hash-object", "-w", "--stdin"], input: input).strip
    end

    # Builds a commit on top of HEAD: loads the current tree into a temporary
    # index, yields so the caller can mutate it with update-index, then
    # writes the tree and advances HEAD. A mutation that leaves the tree
    # unchanged produces no commit. HEAD is advanced with compare-and-swap,
    # so a concurrent external push fails the update instead of being lost.
    private def commit(user : Fluence::User, message : String, &)
      base = head
      index_file = ::File.tempname("fluence-index")
      index_env = {"GIT_INDEX_FILE" => index_file}
      begin
        if base
          git! ["read-tree", base], env: index_env
        else
          git! ["read-tree", "--empty"], env: index_env
        end

        yield index_env

        tree = git!(["write-tree"], env: index_env).strip
        if base && tree == git!(["rev-parse", "HEAD^{tree}"]).strip
          return # nothing changed
        end

        args = ["commit-tree", tree, "-m", message]
        args += ["-p", base] if base
        new_commit = git!(args, env: git_env(user)).strip

        if base
          git! ["update-ref", "HEAD", new_commit, base]
        else
          git! ["update-ref", "HEAD", new_commit]
        end
      ensure
        ::File.delete? index_file
      end
    end
  end
end
