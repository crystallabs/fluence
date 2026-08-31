# Point the app at throwaway directories before any option is read.
ENV["FLUENCE_DATADIR"] ||= File.tempname("fluence-spec-data")
ENV["FLUENCE_METADIR"] ||= File.tempname("fluence-spec-meta")
# Keep Kemal from binding a real server when src/fluence.cr calls Kemal.run.
ENV["KEMAL_ENV"] = "test"

require "spec"
require "file_utils"
require "kemal"

Kemal.config.logging = false

# The full application — routes, controllers, session config, catalogs.
# In the test environment Kemal.run sets everything up without listening.
require "../src/fluence"

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

# Minimal HTTP harness: runs requests through the full Kemal handler chain
# (no listening socket), keeping cookies across requests like a browser.
class SpecClient
  @@handler : HTTP::Handler?

  # Kemal's handlers linked into a chain, as HTTP::Server does at listen.
  def self.handler : HTTP::Handler
    @@handler ||= begin
      handlers = Kemal.config.handlers
      handlers.each_cons_pair { |left, right| left.next = right }
      handlers.first
    end
  end

  getter jar = HTTP::Cookies.new

  def request(method : String, path : String, headers = HTTP::Headers.new, body : String? = nil) : HTTP::Client::Response
    request = HTTP::Request.new(method, path, headers, body)
    jar.add_request_headers request.headers
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    SpecClient.handler.call HTTP::Server::Context.new(request, response)
    response.close
    io.rewind
    client_response = HTTP::Client::Response.from_io(io, decompress: false)
    client_response.cookies.each do |cookie|
      if (expires = cookie.expires) && expires <= Time.utc
        jar.delete cookie.name
      else
        jar << cookie
      end
    end
    client_response
  end

  def get(path : String, headers = HTTP::Headers.new) : HTTP::Client::Response
    request "GET", path, headers
  end

  def post(path : String, form : Hash(String, String)) : HTTP::Client::Response
    headers = HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
    request "POST", path, headers, URI::Params.encode(form)
  end

  def post(path : String, headers : HTTP::Headers, body : String) : HTTP::Client::Response
    request "POST", path, headers, body
  end

  # A client registered (first time only) and logged in over HTTP. The
  # first registration on a wiki becomes admin, so a seed account absorbs
  # that role first — clients made here are always regular users.
  def self.login(username : String, password : String) : SpecClient
    client = new
    if Fluence::USERS.load!.list.empty?
      client.post "/users/register", {"username" => "seed-admin", "password" => "seed-password"}
    end
    client.post "/users/register", {"username" => username, "password" => password}
    client.post "/users/login", {"username" => username, "password" => password}
    raise "login failed for #{username}" unless client.jar["session_id"]?
    client
  end
end

# Headers and body of a fine-uploader-style multipart upload request.
def multipart_upload(page : String, filename : String, content : String) : {HTTP::Headers, String}
  io = IO::Memory.new
  boundary = MIME::Multipart.generate_boundary
  HTTP::FormData.build(io, boundary) do |form|
    form.field "qqpagename", page
    form.field "qqfilename", filename
    form.file "qqfile", IO::Memory.new(content), HTTP::FormData::FileMetadata.new(filename: filename)
  end
  {HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}"}, io.to_s}
end
