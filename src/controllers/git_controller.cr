require "base64"
require "compress/gzip"

# Serves the wiki repository over the git smart HTTP protocol, so the wiki
# URL itself can be cloned, fetched from, and pushed to:
#
#   git clone http://user@wiki.host:3000/repo
#
# Authentication is HTTP Basic against the wiki users; authorization is the
# regular ACL, checked against the request path (under
# `Fluence::OPTIONS.repo_prefix`): fetching requires Read, pushing Write.
# The protocol exchange itself is delegated to `git upload-pack` /
# `git receive-pack --stateless-rpc`, streaming between the HTTP request
# and response.
class GitController < ApplicationController
  # get /repo/info/refs?service=git-upload-pack|git-receive-pack
  def info_refs
    case params.query["service"]?
    when "git-upload-pack"  then advertise "upload-pack", Acl::Perm::Read
    when "git-receive-pack" then advertise "receive-pack", Acl::Perm::Write
    else
      # No service parameter means the pre-1.6.6 "dumb" protocol.
      @env.response.status_code = 403
      "The dumb git HTTP protocol is not supported; please use git >= 1.6.6."
    end
  end

  # post /repo/git-upload-pack — serves fetch/clone
  def upload_pack
    exchange "upload-pack", Acl::Perm::Read
  end

  # post /repo/git-receive-pack — serves push
  def receive_pack
    exchange "receive-pack", Acl::Perm::Write
  end

  # The ref advertisement phase: the service banner pkt-line, a flush-pkt,
  # then the refs as printed by the service in --advertise-refs mode.
  private def advertise(service : String, perm : Acl::Perm)
    return unless authorized? perm
    respond_headers "application/x-git-#{service}-advertisement"
    banner = "# service=git-#{service}\n"
    @env.response.print "%04x" % (banner.bytesize + 4)
    @env.response.print banner
    @env.response.print "0000"
    run service, ["--advertise-refs"], IO::Memory.new
    nil
  end

  # The stateless-rpc phase: the request body is the client's protocol
  # stream, the response body is the service's answer.
  private def exchange(service : String, perm : Acl::Perm)
    return unless authorized? perm
    respond_headers "application/x-git-#{service}-result"
    body = request.body || IO::Memory.new
    body = Compress::Gzip::Reader.new(body) if request.headers["Content-Encoding"]? == "gzip"
    run service, [] of String, body
    nil
  end

  private def run(service : String, extra_args : Array(String), input : IO)
    args = [] of String
    # Working-tree storages have the target branch checked out;
    # updateInstead makes a push update the checkout too (or refuses
    # cleanly if it has uncommitted changes). Irrelevant for bare repos.
    args += ["-c", "receive.denyCurrentBranch=updateInstead"] if service == "receive-pack"
    args += [service, "--stateless-rpc"] + extra_args
    args << Fluence::Storage.current.git_directory

    env = {} of String => String
    # Let the client negotiate git protocol v2.
    if protocol = request.headers["Git-Protocol"]?
      env["GIT_PROTOCOL"] = protocol
    end

    error = IO::Memory.new
    status = Process.run("git", args, env: env, input: input,
      output: @env.response, error: error)
    Log.warn { "git #{service} failed: #{error}" } unless status.success?
  end

  private def respond_headers(content_type : String)
    @env.response.content_type = content_type
    @env.response.headers["Cache-Control"] = "no-cache, max-age=0, must-revalidate"
    @env.response.headers["Pragma"] = "no-cache"
    @env.response.headers["Expires"] = "Fri, 01 Jan 1980 00:00:00 GMT"
  end

  # The wiki user of this request: the Basic auth credentials when present
  # (nil if invalid), the guest user otherwise.
  private def git_user : Fluence::User?
    authorization = request.headers["Authorization"]?
    return Fluence::USERS.default unless authorization
    return unless authorization.starts_with? "Basic "
    name, _, password = Base64.decode_string(authorization.lchop("Basic ")).partition(':')
    Fluence::USERS.auth? name, password
  rescue Base64::Error
    nil
  end

  # On denial answers 401 with a Basic challenge — git clients react by
  # prompting for credentials and retrying, so this is the whole login flow.
  private def authorized?(perm : Acl::Perm) : Bool
    user = git_user
    if user && Fluence::ACL.permitted?(user, request.path, perm)
      Log.debug { "GIT PERMITTED #{user.name} #{request.path} #{perm}" }
      return true
    end
    Log.debug { "GIT NOT PERMITTED #{user.try(&.name) || "(bad credentials)"} #{request.path} #{perm}" }
    @env.response.status_code = 401
    @env.response.headers["WWW-Authenticate"] = %(Basic realm="#{Fluence::OPTIONS.brand}")
    false
  end
end
