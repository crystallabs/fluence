require "yaml"
require "./errors"

# `File` is a representation of anything that can be accessed
# via some sort of an URL and has ACLs applying to it.

# It is used to associate path, url and data.
#
# Pages and Media are two primary uses. Originally, all of this was
# in the Page class directly. Now file is separate `File` to serve
# as basis for both Page and Media.
#
# It can also jail! the path into the *OPTIONS.datadir*.
abstract class Fluence::File

  class AlreadyExists < Exception
  end

  # Path of the file that contains the page
  getter path : String

  # Url of the page (without any prefix)
  getter name : String

  # Complete Url of the page
  getter url : String

  # Title of the page
  getter title : String

  @[YAML::Field(ignore: true)]
  getter content : String?

  # Pointless initialize needed due to https://github.com/crystal-lang/crystal/issues/2827
  def initialize(@path,@name,@url,@title)
  end

  abstract def url_prefix : String

  # translate a name ("/test/title" for example)
  # into a directory path ("/srv/data/test/title)
  def self.name_to_directory(name : String)
    ::File.expand_path self.sanitize(name), subdirectory
  end

  # verify if the *file* is in the current dir (avoid ../ etc.)
  # it will raise a `Error403` if the file is out of the datadir
  def jail!
    # TODO: consider security of ".git/"

    # The @fpath is already expanded (::File.expand_path) in the constructor
    if self.class.subdirectory != @path[0..(self.class.subdirectory.size - 1)]
      raise Error403.new "Out of chroot (#{@path} on #{self.class.subdirectory})"
    end
    self
  end

  # Reads the *file* and returns the content.
  def read
    jail!
    ::File.read @path
  end

  def update!(user : Fluence::User, body)
    write user, body
    process!
    self
  end

  # Writes into the *file*, and commit.
  def write(user : Fluence::User, body)
    jail!
    Dir.mkdir_p self.directory
    ::File.write @path, body
    commit! user, exists? ? "update" : "create"
  end

  # Deletes the *file*, and commits
  def delete(user : Fluence::User)
    jail!
    ::File.delete @path
    commit! user, "delete"
    self
  end

  # Checks if the *file* exists
  def exists?
    jail!
    ::File.exists? @path
  end

  def parent_directory
    ::File.dirname @path
  end

  # Save the modifications on the *file* into the git repository
  # TODO: lock before commit
  # TODO: security of jail!ed_file and self.name ?
  def commit!(user : Fluence::User, message, other_files : Array(String) = [] of String)
    dir = Dir.current
    begin
      Dir.cd Fluence::OPTIONS.datadir
      all_files = @path + " " + other_files.join(" ")
      puts `git add -- #{all_files}`
      puts `git commit --no-gpg-sign --author \"#{user.name} <#{user.name}@localhost>\" -m \"#{message} #{@name}\" -- #{all_files}`
    ensure
      Dir.cd dir
    end
  end

  def exists?
    ::File.exists? @path
  end

  def self.sanitize(text : String)
    self.title_to_slug URI.decode(text)
  end

  def self.title_to_slug(title : String) : String
    title.gsub(/[^[:alnum:]^\/]+/, "-").downcase
  end

  def self.remove_empty_directories(path)
    page_dir_elements = ::File.dirname(path).split ::File::SEPARATOR
    base_dir_elements = Fluence::Page.subdirectory.split ::File::SEPARATOR
    while page_dir_elements.size != base_dir_elements.size
      dir_path = page_dir_elements.join(::File::SEPARATOR)
      if Dir.empty? dir_path
        Dir.delete dir_path
        page_dir_elements.pop
      else
        break
      end
    end
  end
end
