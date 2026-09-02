require "./spec_helper"

describe "ACL enforcement over HTTP" do
  it "serves guests a server-rendered page without an editor" do
    with_each_storage do |_, _|
      Fluence::Page.new("readable").update! SPEC_USER, "# Readable\n\nHello *world*.\n"

      response = SpecClient.new.get "/pages/readable"
      response.status_code.should eq 200
      response.body.should contain %(<h1 id="readable">Readable</h1>)
      response.body.should contain %(id="page-body")
      response.body.should_not contain "<textarea"
    end
  end

  it "rejects page writes from guests" do
    with_each_storage do |_, _|
      Fluence::Page.new("readable").update! SPEC_USER, "# Readable\n"

      response = SpecClient.new.post "/pages/readable", {"body" => "# Defaced\n"}
      response.status_code.should eq 302
      response.headers["Location"].should eq Fluence::OPTIONS.homepage
      Fluence::Page.new("readable").read.should eq "# Readable\n"
    end
  end

  it "lets a logged-in user create and update pages" do
    with_each_storage do |storage, _|
      client = SpecClient.login "editor", "sekrit123"

      response = client.post "/pages/new-page", {"body" => "# New Page\n"}
      response.status_code.should eq 302
      response.headers["Location"].should eq "/pages/new-page"
      Fluence::Page.new("new-page").read.should eq "# New Page\n"
      git_log(storage).should contain "editor <editor@localhost>"

      client.get("/pages/new-page").body.should contain "<textarea"
    end
  end

  it "auto-logs-in from the user.name/user.token cookies alone" do
    with_each_storage do |_, _|
      logged_in = SpecClient.login "editor", "sekrit123"

      client = SpecClient.new
      {"user.name", "user.token"}.each do |name|
        client.jar << HTTP::Cookie.new(name, logged_in.jar[name].value)
      end
      response = client.post "/pages/cookie-page", {"body" => "# Via Cookie\n"}
      response.status_code.should eq 302
      Fluence::Page.new("cookie-page").exists?.should be_true
    end
  end
end

describe "rename destination check over HTTP" do
  it "refuses renaming onto a write-protected destination" do
    with_each_storage do |_, _|
      client = SpecClient.login "editor", "sekrit123"
      client.post "/pages/movable", {"body" => "# Movable\n"}

      Fluence::ACL["user"]["#{Fluence::OPTIONS.pages_prefix}/locked/*"] = Acl::Perm::Read
      begin
        response = client.post "/pages/movable",
          {"rename" => "rename", "input-page-name" => "locked/movable"}
        response.status_code.should eq 302
        Fluence::Page.new("movable").exists?.should be_true
        Fluence::Page.new("locked/movable").exists?.should be_false
      ensure
        Fluence::ACL["user"].delete "#{Fluence::OPTIONS.pages_prefix}/locked/*"
      end

      response = client.post "/pages/movable",
        {"rename" => "rename", "input-page-name" => "moved"}
      response.status_code.should eq 302
      Fluence::Page.new("moved").exists?.should be_true
      Fluence::Page.new("movable").exists?.should be_false
    end
  end
end

describe "search filtering over HTTP" do
  it "omits results the requester may not read" do
    with_each_storage do |_, _|
      Fluence::Page.new("pub").update! SPEC_USER, "# Pub\nfindme-xyz\n"
      Fluence::Page.new("locked/priv").update! SPEC_USER, "# Priv\nfindme-xyz\n"

      Fluence::ACL["guest"]["#{Fluence::OPTIONS.pages_prefix}/locked/*"] = Acl::Perm::None
      begin
        response = SpecClient.new.get "/pages/search?q=findme-xyz"
        response.status_code.should eq 200
        response.body.should contain "/pages/pub"
        response.body.should_not contain "/pages/locked/priv"
      ensure
        Fluence::ACL["guest"].delete "#{Fluence::OPTIONS.pages_prefix}/locked/*"
      end

      response = SpecClient.new.get "/pages/search?q=findme-xyz"
      response.body.should contain "/pages/locked/priv"
    end
  end
end

describe "media upload over HTTP" do
  it "accepts uploads from writers, rejects guests" do
    with_each_storage do |_, _|
      headers, body = multipart_upload "home", "hello.txt", "hello world"

      response = SpecClient.new.post "/media/upload", headers, body
      response.body.should contain %("success":false)
      Fluence::Media.new("home/hello.txt").exists?.should be_false

      client = SpecClient.login "editor", "sekrit123"
      headers, body = multipart_upload "home", "hello.txt", "hello world"
      response = client.post "/media/upload", headers, body
      response.body.should contain %("success":true)
      Fluence::Media.new("home/hello.txt").read.should eq "hello world"
    end
  end
end

describe "registration and admin defaults" do
  it "makes the first registered user admin, later ones regular users" do
    with_each_storage do |_, _|
      backup = File.read(Fluence::USERS.file)
      begin
        Fluence::USERS.transaction!(&.list.clear)

        first = SpecClient.new
        first.post "/users/register", {"username" => "founder", "password" => "sekrit123"}
        Fluence::USERS.load!.find("founder").groups.should eq %w[user admin]

        second = SpecClient.new
        second.post "/users/register", {"username" => "regular", "password" => "sekrit123"}
        Fluence::USERS.load!.find("regular").groups.should eq %w[user]

        first.post "/users/login", {"username" => "founder", "password" => "sekrit123"}
        first.get("/admin/users").status_code.should eq 200

        second.post "/users/login", {"username" => "regular", "password" => "sekrit123"}
        response = second.get "/admin/users"
        response.status_code.should eq 302
        response.headers["Location"].should eq Fluence::OPTIONS.homepage
      ensure
        File.write(Fluence::USERS.file, backup)
        Fluence::USERS.load!
      end
    end
  end

  it "refuses self-registration when closed, and hides the nav link" do
    with_each_storage do |_, _|
      Fluence::OPTIONS.registration = "closed"
      begin
        response = SpecClient.new.get "/users/register"
        response.status_code.should eq 302
        response.headers["Location"].should eq "#{Fluence::OPTIONS.users_prefix}/login"

        client = SpecClient.new
        response = client.post "/users/register", {"username" => "sneaky", "password" => "sekrit123"}
        response.status_code.should eq 302
        Fluence::USERS.load!.find?("sneaky").should be_nil

        SpecClient.new.get("/users/login").body.should_not contain "/users/register"
      ensure
        Fluence::OPTIONS.registration = "open"
      end

      SpecClient.new.get("/users/login").body.should contain "/users/register"
    end
  end
end

describe "session and cookie hardening" do
  it "sets HttpOnly/SameSite login cookies" do
    client = SpecClient.new
    client.post "/users/register", {"username" => "cookieuser", "password" => "sekrit123"}
    response = client.post "/users/login", {"username" => "cookieuser", "password" => "sekrit123"}

    {"user.name", "user.token"}.each do |name|
      cookie = response.cookies[name]
      cookie.http_only.should be_true
      cookie.samesite.should eq HTTP::Cookie::SameSite::Lax
      cookie.path.should eq "/"
    end
  end

  it "does not echo arbitrary client cookies back into the response" do
    with_each_storage do |_, _|
      Fluence::Page.new("readable").update! SPEC_USER, "# Readable\n"

      headers = HTTP::Headers{"Cookie" => "tracker=42"}
      response = SpecClient.new.get "/pages/readable", headers
      response.headers.get?("Set-Cookie").to_s.should_not contain "tracker"
    end
  end

  it "persists the session secret under meta/" do
    path = File.join(Fluence::OPTIONS.metadir, "secret")
    File.exists?(path).should be_true
    File.read(path).strip.should eq Kemal::Session.config.secret
    (File.info(path).permissions.value & 0o077).should eq 0
  end
end

private def basic_auth(credentials : String) : HTTP::Headers
  HTTP::Headers{"Authorization" => "Basic #{Base64.strict_encode(credentials)}"}
end

describe "git smart-HTTP access" do
  it "authenticates with wiki credentials and authorizes via the ACL" do
    with_each_storage do |_, _|
      SpecClient.login "editor", "sekrit123" # ensures seed-admin and editor exist

      # Anonymous: no ACL matches /repo for guests, so ask for credentials.
      response = SpecClient.new.get "/repo/info/refs?service=git-upload-pack"
      response.status_code.should eq 401
      response.headers["WWW-Authenticate"].should contain "Basic"

      # Wrong password.
      response = SpecClient.new.get "/repo/info/refs?service=git-upload-pack",
        basic_auth("editor:wrong")
      response.status_code.should eq 401

      # A registered user may fetch (Read via the default "/*" rule)...
      response = SpecClient.new.get "/repo/info/refs?service=git-upload-pack",
        basic_auth("editor:sekrit123")
      response.status_code.should eq 200
      response.headers["Content-Type"].should eq "application/x-git-upload-pack-advertisement"
      response.body.should start_with "001e# service=git-upload-pack"

      # ...but not push.
      response = SpecClient.new.get "/repo/info/refs?service=git-receive-pack",
        basic_auth("editor:sekrit123")
      response.status_code.should eq 401

      # An admin may push.
      response = SpecClient.new.get "/repo/info/refs?service=git-receive-pack",
        basic_auth("seed-admin:seed-password")
      response.status_code.should eq 200
      response.body.should start_with "001f# service=git-receive-pack"

      # Requests without ?service= are the unsupported dumb protocol.
      response = SpecClient.new.get "/repo/info/refs", basic_auth("editor:sekrit123")
      response.status_code.should eq 403
    end
  end

  it "serves anonymous fetch when guests are granted Read on the repo" do
    with_each_storage do |_, _|
      Fluence::ACL["guest"]["#{Fluence::OPTIONS.repo_prefix}/*"] = Acl::Perm::Read
      begin
        response = SpecClient.new.get "/repo/info/refs?service=git-upload-pack"
        response.status_code.should eq 200
        response.body.should start_with "001e# service=git-upload-pack"
      ensure
        Fluence::ACL["guest"].delete "#{Fluence::OPTIONS.repo_prefix}/*"
      end
    end
  end
end

describe "page history over HTTP" do
  it "lists revisions, shows past content and diffs, and restores" do
    with_each_storage do |storage, _|
      client = SpecClient.login "editor", "sekrit123"
      client.post "/pages/hist", {"body" => "# Hist\nfirst\n", "summary" => "Initial version"}
      client.post "/pages/hist", {"body" => "# Hist\nsecond\n"}
      commits = storage.log "pages/hist.md"
      commits.map(&.subject).should eq ["Update page hist", "Create page hist"]
      commits[1].body.should eq "Initial version"

      response = SpecClient.new.get "/pages/hist?history"
      response.status_code.should eq 200
      response.body.should contain "Create page hist"
      response.body.should contain "Initial version"
      response.body.should contain "Update page hist"
      response.body.should contain "/pages/hist?rev=#{commits[1].oid}"
      response.body.should contain "/pages/hist?diff=#{commits[0].oid}"

      response = SpecClient.new.get "/pages/hist?rev=#{commits[1].oid}"
      response.status_code.should eq 200
      response.body.should contain "<p>first</p>"
      response.body.should_not contain "Restore this revision"
      client.get("/pages/hist?rev=#{commits[1].short_oid}").body.should contain "Restore this revision"

      response = SpecClient.new.get "/pages/hist?diff=#{commits[0].oid}"
      response.status_code.should eq 200
      response.body.should contain %(<span class="diff-del">-first</span>)
      response.body.should contain %(<span class="diff-add">+second</span>)

      {"--output=x", "0" * 40, "HEAD"}.each do |rev|
        response = SpecClient.new.get "/pages/hist?rev=#{rev}"
        response.status_code.should eq 302
        response.headers["Location"].should eq "/pages/hist?history"
      end

      response = client.post "/pages/hist",
        {"body" => "# Hist\nfirst\n", "summary" => "Restore revision #{commits[1].short_oid}"}
      response.status_code.should eq 302
      Fluence::Page.new("hist").read.should eq "# Hist\nfirst\n"
      storage.log("pages/hist.md")[0].body.should eq "Restore revision #{commits[1].short_oid}"

      client.get("/pages/hist").body.should contain "/pages/hist?history"
    end
  end

  it "keeps the history views behind the page's read permission" do
    with_each_storage do |storage, _|
      Fluence::Page.new("locked/secret").update! SPEC_USER, "# Secret\n"
      oid = storage.log("pages/locked/secret.md")[0].oid

      Fluence::ACL["guest"]["#{Fluence::OPTIONS.pages_prefix}/locked/*"] = Acl::Perm::None
      begin
        {"?history", "?rev=#{oid}", "?diff=#{oid}"}.each do |query|
          response = SpecClient.new.get "/pages/locked/secret#{query}"
          response.status_code.should eq 302
          response.headers["Location"].should eq Fluence::OPTIONS.homepage
        end
      ensure
        Fluence::ACL["guest"].delete "#{Fluence::OPTIONS.pages_prefix}/locked/*"
      end

      SpecClient.new.get("/pages/locked/secret?history").status_code.should eq 200
    end
  end
end

describe "attachments on rename over HTTP" do
  it "moves attachments with the page, unless the user cannot write at their destination" do
    with_each_storage do |_, _|
      client = SpecClient.login "editor", "sekrit123"
      client.post "/pages/withfile", {"body" => "# With File\n![a](/media/withfile/a.txt)\n"}
      Fluence::Media.new("withfile/a.txt").write SPEC_USER, "A"

      Fluence::ACL["user"]["#{Fluence::OPTIONS.media_prefix}/locked/*"] = Acl::Perm::Read
      begin
        client.post "/pages/withfile", {"rename" => "rename", "input-page-name" => "locked/withfile"}
        Fluence::Page.new("withfile").exists?.should be_true
        Fluence::Media.new("withfile/a.txt").exists?.should be_true
      ensure
        Fluence::ACL["user"].delete "#{Fluence::OPTIONS.media_prefix}/locked/*"
      end

      client.post "/pages/withfile", {"rename" => "rename", "input-page-name" => "moved/withfile"}
      Fluence::Media.new("withfile/a.txt").exists?.should be_false
      Fluence::Media.new("moved/withfile/a.txt").read.should eq "A"
      Fluence::Page.new("moved/withfile").read.should eq "# With File\n![a](/media/moved/withfile/a.txt)\n"
    end
  end
end

describe "static assets" do
  it "are served from the source tree's public/ regardless of the working directory" do
    Fluence::OPTIONS.publicdir.should eq File.expand_path("public", Dir.current)
    Dir.cd(Dir.tempdir) do
      response = SpecClient.new.get "/assets/stylesheet/base.css"
      response.status_code.should eq 200
      response.body.should contain "#pages-hierarchy"
    end
  end
end

describe "editor conveniences over HTTP" do
  it "prefills a new page with a heading and honours ?edit and ?view" do
    with_each_storage do |_, _|
      client = SpecClient.login "editor", "sekrit123"
      body = client.get("/pages/docs/my-new-page").body
      body.should contain "# My New Page"
      body.should contain "Fluence.editor.init(true);"

      client.post "/pages/docs/my-new-page", {"body" => "# Saved\n"}
      body = client.get("/pages/docs/my-new-page").body
      body.should_not contain "# My New Page"
      body.should contain "Fluence.editor.init(false);"
      client.get("/pages/docs/my-new-page?edit").body.should contain "Fluence.editor.init(true);"
      client.get("/pages/docs/other-page?view").body.should contain "Fluence.editor.init(false);"

      SpecClient.new.get("/pages/docs/other-page").body.should_not contain "# Other Page"
    end
  end

  it "marks the current section active in the navbar" do
    response = SpecClient.new.get "/sitemap"
    response.body.should contain %(<a class="nav-link active" href="/sitemap">Sitemap</a>)
    response.body.should contain %(<a class="nav-link" href="#{Fluence::OPTIONS.homepage}">Home</a>)
  end
end

describe "attachment deletion over HTTP" do
  it "answers JSON when asked, otherwise redirects back to the page" do
    with_each_storage do |_, _|
      client = SpecClient.login "editor", "sekrit123"
      client.post "/pages/att", {"body" => "# Att\n"}
      Fluence::Media.new("att/a.txt").write SPEC_USER, "A"
      Fluence::Media.new("att/b.txt").write SPEC_USER, "B"

      headers = HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded", "Accept" => "application/json"}
      response = client.request "POST", "/media/att/a.txt", headers,
        URI::Params.encode({"delete" => "Delete", "media-name" => "a.txt"})
      response.status_code.should eq 200
      response.body.should eq %({"success":true})
      Fluence::Media.new("att/a.txt").exists?.should be_false

      response = client.post "/media/att/b.txt", {"delete" => "Delete", "media-name" => "b.txt"}
      response.status_code.should eq 302
      response.headers["Location"].should eq "/pages/att"
      Fluence::Media.new("att/b.txt").exists?.should be_false

      Fluence::Media.new("att/c.txt").write SPEC_USER, "C"
      SpecClient.new.post("/media/att/c.txt", {"delete" => "Delete", "media-name" => "c.txt"}).status_code.should eq 302
      Fluence::Media.new("att/c.txt").exists?.should be_true
    end
  end
end

describe "page menu over HTTP" do
  it "shows a collapsible tree expanded along the current page, with prev/up/next links" do
    with_each_storage do |_, _|
      %w[alpha docs docs/guide docs/guide/install docs/zeta other/thing].each do |name|
        Fluence::Page.new(name).update! SPEC_USER, "# #{name.split('/').last.capitalize}\n"
      end

      body = SpecClient.new.get("/pages/docs/guide").body
      body.should contain %(<a class="tree-link active" href="/pages/docs/guide">Guide</a>)
      body.should contain %(<div class="collapse show" id="tree-docs">)
      body.should contain %(<div class="collapse show" id="tree-docs-guide">)
      body.should contain %(<div class="collapse" id="tree-other">)
      body.should contain %(<a class="tree-link text-body-secondary" href="/pages/other">other</a>)
      body.should contain %(href="/pages/docs" title="Previous: Docs">)
      body.should contain %(href="/pages/docs" title="Up: Docs">)
      body.should contain %(href="/pages/docs/guide/install" title="Next: Install">)

      body = SpecClient.new.get("/pages/alpha").body
      body.should contain %(<span class="btn btn-outline-secondary text-nowrap disabled">‹ Prev</span>)
      body.should contain %(href="/pages/docs" title="Next: Docs">)

      SpecClient.new.get("/sitemap").body.should contain %(<div class="collapse show" id="tree-other">)
    end
  end
end

describe "save and continue over HTTP" do
  it "answers JSON when asked, otherwise redirects back into the editor" do
    with_each_storage do |storage, _|
      client = SpecClient.login "editor", "sekrit123"

      headers = HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded", "Accept" => "application/json"}
      response = client.request "POST", "/pages/draft", headers,
        URI::Params.encode({"body" => "# Draft\nstep one\n", "summary" => "First step", "continue" => "1"})
      response.status_code.should eq 200
      response.body.should eq %({"success":true,"title":"Draft"})
      Fluence::Page.new("draft").read.should eq "# Draft\nstep one\n"
      storage.log("pages/draft.md")[0].body.should eq "First step"

      response = client.post "/pages/draft", {"body" => "# Draft\nstep two\n", "continue" => "1"}
      response.status_code.should eq 302
      response.headers["Location"].should eq "/pages/draft?edit"

      response = client.post "/pages/draft", {"body" => "# Draft\nstep three\n"}
      response.headers["Location"].should eq "/pages/draft"

      response = SpecClient.new.request "POST", "/pages/draft", headers, URI::Params.encode({"body" => "# Defaced\n"})
      response.status_code.should eq 302
      Fluence::Page.new("draft").read.should eq "# Draft\nstep three\n"
    end
  end
end
