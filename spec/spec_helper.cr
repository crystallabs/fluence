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

SPEC_USER = Fluence::User.new "spec", "password", %w[user]

# Password hashing dominates the suite's run time at the default cost.
Fluence::User.bcrypt_cost = Crypto::Bcrypt::COST_RANGE.begin

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

  # The client's address as the server sees it (nil by default).
  property remote_address : Socket::Address?

  # The CSRF token last seen in a page (see `Fluence::CSRF`), and the
  # session cookie it belongs to: logging in or out starts a new session,
  # whose token is fetched afresh.
  @csrf_token : String?
  @csrf_session : String?

  # Sends a request. POSTs carry the session's CSRF token in the header
  # the fetch calls of base.js use, unless *csrf* is false (or the request
  # goes to the git routes, which take none).
  def request(method : String, path : String, headers = HTTP::Headers.new, body : String? = nil, csrf = true) : HTTP::Client::Response
    if csrf && method == "POST" && !path.starts_with?(Fluence::OPTIONS.repo_prefix) && !headers.has_key?(Fluence::CSRF::HEADER)
      headers = headers.dup
      headers[Fluence::CSRF::HEADER] = csrf_token
    end
    request = HTTP::Request.new(method, path, headers, body)
    request.remote_address = remote_address
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
    remember_csrf_token client_response.body
    client_response
  end

  def get(path : String, headers = HTTP::Headers.new) : HTTP::Client::Response
    request "GET", path, headers
  end

  # Posts a form like a browser does, with the CSRF token in its hidden
  # `authenticity_token` field (left out when *csrf* is false).
  def post(path : String, form : Hash(String, String), csrf = true) : HTTP::Client::Response
    headers = HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
    form = form.merge({Fluence::CSRF::PARAMETER => csrf_token}) if csrf
    request "POST", path, headers, URI::Params.encode(form), csrf: false
  end

  def post(path : String, headers : HTTP::Headers, body : String, csrf = true) : HTTP::Client::Response
    request "POST", path, headers, body, csrf: csrf
  end

  # The token of the current session: the one last seen in a page, else
  # one read from a page with forms — the settings page when logged in,
  # the login page otherwise.
  def csrf_token : String
    if (token = @csrf_token) && @csrf_session == session_cookie
      return token
    end
    @csrf_token = nil
    if get("#{Fluence::OPTIONS.users_prefix}/settings").status_code != 200
      get "#{Fluence::OPTIONS.users_prefix}/login"
    end
    @csrf_token || raise "no CSRF token found in the settings or login page"
  end

  private def session_cookie : String?
    jar[Kemal::Session.config.cookie_name]?.try &.value
  end

  private def remember_csrf_token(body : String)
    if match = body.match(/<meta name="csrf-token" content="([^"]+)"/)
      @csrf_token = match[1]
      @csrf_session = session_cookie
    end
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

# Headers and body of a multipart upload request as sent by the
# attachment form on a page (see MediaController#upload).
def multipart_upload(page : String, filename : String, content : String) : {HTTP::Headers, String}
  io = IO::Memory.new
  boundary = MIME::Multipart.generate_boundary
  HTTP::FormData.build(io, boundary) do |form|
    form.field "pagename", page
    form.file "file", IO::Memory.new(content), HTTP::FormData::FileMetadata.new(filename: filename)
  end
  {HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}"}, io.to_s}
end
