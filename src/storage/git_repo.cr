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

    # Commits pinned by `#snapshot`, per fiber: requests interleave
    # whenever one waits for a git process, so a pin can never be shared.
    # A nil value pins an unborn HEAD (no commit yet).
    @pins = {} of Fiber => String?
    @pins_lock = Mutex.new

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

    # Pins the current HEAD commit for the duration of the block: reads in
    # the block made by the same fiber resolve against that commit instead
    # of each looking up HEAD anew, so they see one consistent state even
    # if a push lands meanwhile. Writes still build on the live HEAD and
    # then move the pin to their result, so the block sees its own changes.
    # A snapshot nested in another one keeps the outer pin.
    def snapshot(&)
      fiber = Fiber.current
      return yield if @pins_lock.synchronize { @pins.has_key? fiber }
      oid = head
      @pins_lock.synchronize { @pins[fiber] = oid }
      begin
        yield
      ensure
        @pins_lock.synchronize { @pins.delete fiber }
      end
    end

    def read(path : String) : String
      rev = read_rev || raise Error404.new "No such file: #{path}"
      status, output = git ["cat-file", "blob", "#{rev}:#{path}"]
      raise Error404.new "No such file: #{path}" unless status.success?
      output
    end

    def exists?(path : String) : Bool
      rev = read_rev || return false
      status, _ = git ["cat-file", "-e", "#{rev}:#{path}"]
      status.success?
    end

    def size(path : String) : Int64?
      rev = read_rev || return
      status, output = git ["cat-file", "-s", "#{rev}:#{path}"]
      status.success? ? output.strip.to_i64? : nil
    end

    def list(prefix : String) : Array(String)
      rev = read_rev || return [] of String
      status, output = git ["ls-tree", "-r", "--name-only", "-z", rev, "--", prefix]
      return [] of String unless status.success?
      output.split('\0', remove_empty: true).sort!
    end

    def write(path : String, content : String | IO, user : Fluence::User, message : String)
      @lock.synchronize do
        # Hash outside the retry: an IO body can only be read once, and the
        # blob is valid regardless of which commit it ends up in.
        blob = hash_object content
        retrying_conflict do
          commit(user, message) do |index_env|
            git! ["update-index", "--add", "--cacheinfo", "100644,#{blob},#{path}"], env: index_env
          end
        end
      end
    end

    def delete(paths : Array(String), user : Fluence::User, message : String)
      @lock.synchronize do
        retrying_conflict do
          # Checked against the live HEAD, which the commit builds on.
          paths.each do |path|
            status, _ = git ["cat-file", "-e", "HEAD:#{path}"]
            raise Error404.new "No such file: #{path}" unless status.success?
          end
          commit(user, message) do |index_env|
            paths.each { |path| index_remove path, index_env }
          end
        end
      end
    end

    def rename(moves : Array({String, String}), user : Fluence::User, message : String)
      @lock.synchronize do
        retrying_conflict do
          blobs = moves.map do |old_path, _|
            status, blob = git ["rev-parse", "HEAD:#{old_path}"]
            raise Error404.new "No such file: #{old_path}" unless status.success?
            blob.strip
          end
          commit(user, message) do |index_env|
            moves.each { |old_path, _| index_remove old_path, index_env }
            moves.each_with_index do |(_, new_path), i|
              git! ["update-index", "--add", "--cacheinfo", "100644,#{blobs[i]},#{new_path}"], env: index_env
            end
          end
        end
      end
    end

    def log(path : String, limit : Int32 = 0) : Array(Commit)
      rev = read_rev || return [] of Commit
      status, output = git log_args(path, limit, rev)
      status.success? ? parse_log(output, path) : [] of Commit
    end

    def read_at(path : String, rev : String) : String
      check_rev! rev
      status, output = git ["cat-file", "blob", "#{rev}:#{path}"]
      raise Error404.new "No such file: #{path} at #{rev}" unless status.success?
      output
    end

    def diff(path : String, rev : String) : String
      check_rev! rev
      status, output = git diff_args(path, rev)
      raise Error404.new "No such revision: #{rev}" unless status.success?
      output
    end

    def search(query : String, prefix : String) : Array(String)
      rev = read_rev || return [] of String
      status, output = git ["grep", "-I", "-i", "-l", "-z", "--fixed-strings",
                            "-e", query, rev, "--", prefix]
      return [] of String unless status.success?
      output.split('\0', remove_empty: true).map &.lchop("#{rev}:")
    end

    def headings(prefix : String) : Hash(String, String)
      ret = {} of String => String
      rev = read_rev || return ret
      # -z prints the path verbatim (non-ASCII names are not quoted), NUL-terminated.
      status, output = git ["grep", "-I", "-m1", "-z", "-e", "^# ", rev, "--", prefix]
      return ret unless status.success?
      output.each_line do |line|
        path, sep, text = line.lchop("#{rev}:").partition('\0')
        heading = text.lchop("# ").strip
        next if sep.empty? || heading.empty?
        ret[path] = heading
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

    # The live HEAD commit; nil while HEAD is unborn.
    private def head : String?
      status, output = git ["rev-parse", "--verify", "--quiet", "HEAD"]
      status.success? ? output.strip : nil
    end

    # The revision reads resolve against: the commit `#snapshot` pinned for
    # the current fiber, otherwise "HEAD" (left to git to resolve). nil when
    # the pinned HEAD was unborn, i.e. there is nothing to read.
    private def read_rev : String?
      fiber = Fiber.current
      @pins_lock.synchronize { @pins.has_key?(fiber) ? @pins[fiber] : "HEAD" }
    end

    # Moves the current fiber's pin, if it has one, to *oid*.
    private def repin(oid : String?)
      fiber = Fiber.current
      @pins_lock.synchronize { @pins[fiber] = oid if @pins.has_key? fiber }
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
    # so a concurrent external push raises `Error409` instead of being lost
    # (`retrying_conflict` then re-runs the whole build on the new HEAD).
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
        if base && tree == git!(["rev-parse", "#{base}^{tree}"]).strip
          repin base # nothing changed, but the live HEAD may be newer
          return
        end

        args = ["commit-tree", tree, "-m", message]
        args += ["-p", base] if base
        new_commit = git!(args, env: git_env(user)).strip

        # The zero oid as the expected old value asserts the ref must not
        # exist yet, so an unborn HEAD is a compare-and-swap too.
        status, _ = git ["update-ref", "HEAD", new_commit, base || ZERO_OID]
        raise Error409.new unless status.success?
        repin new_commit
      ensure
        ::File.delete? index_file
      end
    end

    ZERO_OID = "0" * 40

    # Runs the block, retrying it once if the final compare-and-swap in
    # `#commit` loses against a concurrent push; the second failure in a
    # row propagates `Error409` to the caller.
    private def retrying_conflict(&)
      yield
    rescue Error409
      yield
    end
  end
end
