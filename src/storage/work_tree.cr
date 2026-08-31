module Fluence
  # Storage over a checked-out working tree whose history lives in `root/.git`.
  # Reads come straight from the filesystem, so pages edited directly on disk
  # are visible immediately; every write through the wiki is committed.
  class Storage::WorkTree < Storage
    getter root : String

    @lock = Mutex.new

    def initialize(root : String)
      @root = ::File.expand_path root
    end

    # Creates a new working tree repository at *root*.
    def self.init(root : String) : WorkTree
      ::Dir.mkdir_p root
      storage = new root
      storage.git ["init", "."]
      storage
    end

    def read(path : String) : String
      ::File.read abs(path)
    rescue ::File::NotFoundError
      raise Error404.new "No such file: #{path}"
    end

    def exists?(path : String) : Bool
      ::File.file? abs(path)
    end

    def size(path : String) : Int64?
      info = ::File.info? abs(path)
      info.try &.size.to_i64
    end

    def list(prefix : String) : Array(String)
      dir = abs(prefix)
      return [] of String unless ::Dir.exists? dir
      ::Dir.glob(::File.join(dir, "**", "*"))
        .select { |f| ::File.file? f }
        .map { |f| f.lchop(@root).lchop("/") }
        .sort!
    end

    def write(path : String, content : String | IO, user : Fluence::User, message : String)
      @lock.synchronize do
        file = abs(path)
        ::Dir.mkdir_p ::File.dirname(file)
        case content
        in String then ::File.write file, content
        in IO     then ::File.open(file, "w") { |f| IO.copy content, f }
        end
        commit [path], user, message
      end
    end

    def delete(path : String, user : Fluence::User, message : String)
      @lock.synchronize do
        ::File.delete abs(path)
        prune_empty_dirs ::File.dirname(abs(path))
        commit [path], user, message
      end
    end

    def rename(old_path : String, new_path : String, user : Fluence::User, message : String)
      @lock.synchronize do
        ::Dir.mkdir_p ::File.dirname(abs(new_path))
        ::File.rename abs(old_path), abs(new_path)
        prune_empty_dirs ::File.dirname(abs(old_path))
        commit [old_path, new_path], user, message
      end
    end

    def search(query : String, prefix : String) : Array(String)
      status, output = git ["grep", "-I", "-i", "-l", "-z", "--untracked", "--fixed-strings",
                            "-e", query, "--", prefix]
      return [] of String unless status.success?
      output.split('\0', remove_empty: true)
    end

    def headings(prefix : String) : Hash(String, String)
      ret = {} of String => String
      status, output = git ["grep", "-I", "-m1", "--untracked", "-e", "^# ", "--", prefix]
      return ret unless status.success?
      output.each_line do |line|
        path, _, heading = line.partition(":# ")
        next if heading.empty?
        ret[path] = heading.strip
      end
      ret
    end

    # Runs git in the working tree; returns the status and combined output.
    protected def git(args : Array(String), user : Fluence::User? = nil) : {Process::Status, String}
      output = IO::Memory.new
      status = Process.run("git", args, env: git_env(user), chdir: @root,
        output: output, error: output)
      {status, output.to_s}
    end

    private def commit(paths : Array(String), user : Fluence::User, message : String)
      status, output = git ["add", "--"] + paths
      raise Error.new "git add failed: #{output}" unless status.success?
      # A no-op edit produces nothing to commit; that is not an error.
      status, output = git ["commit", "--no-gpg-sign", "-m", message, "--"] + paths, user: user
      unless status.success? || output.includes?("nothing to commit") || output.includes?("nothing added")
        raise Error.new "git commit failed: #{output}"
      end
    end

    # Removes now-empty directories left behind under the data root.
    private def prune_empty_dirs(dir : String)
      while dir.starts_with?(@root) && dir != @root && ::Dir.exists?(dir) && ::Dir.empty?(dir)
        ::Dir.delete dir
        dir = ::File.dirname dir
      end
    end

    private def abs(path : String) : String
      ::File.join @root, path
    end
  end
end
