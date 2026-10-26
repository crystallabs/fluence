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

describe "remember-me tokens over HTTP" do
  it "keeps one token per browser, rotating it on cookie login and revoking it on logout" do
    first = SpecClient.login "roamer", "sekrit123"
    second = SpecClient.new
    second.post "/users/login", {"username" => "roamer", "password" => "sekrit123"}
    Fluence::USERS.load!["roamer"].tokens.should eq [first.jar["user.token"].value, second.jar["user.token"].value]

    # The first browser, its session expired, logs in by cookie: only
    # its own token is rotated.
    presented = first.jar["user.token"].value
    first.jar.delete "session_id"
    first.get("/users/settings").status_code.should eq 200
    rotated = first.jar["user.token"].value
    rotated.should_not eq presented
    Fluence::USERS.load!["roamer"].tokens.should eq [second.jar["user.token"].value, rotated]

    stale = SpecClient.new
    stale.jar << HTTP::Cookie.new("user.name", "roamer")
    stale.jar << HTTP::Cookie.new("user.token", presented)
    stale.get("/users/settings").headers["Location"].should eq "/users/login"

    # Logging out revokes this browser's token only.
    kept = second.jar["user.token"].value
    first.post "/users/logout", {} of String => String
    Fluence::USERS.load!["roamer"].tokens.should eq [kept]
    second.jar.delete "session_id"
    second.get("/users/settings").status_code.should eq 200
  end
end

describe "password change" do
  it "requires the current password and keeps only this browser remembered" do
    client = SpecClient.login "changer", "sekrit123"
    client.post "/users/settings", {"theme" => "dark"}
    other = SpecClient.new
    other.post "/users/login", {"username" => "changer", "password" => "sekrit123"}
    client.get("/users/settings").body.should contain %(action="/users/password")

    client.post "/users/password", {"current_password" => "wrong", "new_password" => "fresh123", "password_confirmation" => "fresh123"}
    client.get("/users/settings").body.should contain "The current password is not correct."
    client.post "/users/password", {"current_password" => "sekrit123", "new_password" => "fresh123", "password_confirmation" => "fresh124"}
    client.get("/users/settings").body.should contain "do not match"
    Fluence::USERS.auth!("changer", "sekrit123").should_not be_nil

    response = client.post "/users/password", {"current_password" => "sekrit123", "new_password" => "fresh123", "password_confirmation" => "fresh123"}
    response.headers["Location"].should eq "/users/settings"
    client.get("/users/settings").body.should contain "Your password has been changed."

    user = Fluence::USERS.load!["changer"]
    Fluence::USERS.auth?("changer", "sekrit123").should be_nil
    Fluence::USERS.auth?("changer", "fresh123").should_not be_nil
    user.settings.theme.should eq "dark"
    user.groups.should eq %w[user]
    user.tokens.should eq [client.jar["user.token"].value]

    other.jar.delete "session_id"
    other.get("/users/settings").headers["Location"].should eq "/users/login"
  end

  it "can be reset by an admin" do
    Fluence::USERS.transaction! do |users|
      users.add Fluence::User.new("pw-admin", "sekrit123", %w[user admin]).encrypt! unless users["pw-admin"]?
    end
    target = SpecClient.login "pw-target", "sekrit123"
    admin = SpecClient.new
    admin.post "/users/login", {"username" => "pw-admin", "password" => "sekrit123"}
    admin.get("/admin/users").body.should contain %(action="/admin/users/password")

    response = admin.post "/admin/users/password", {"username" => "pw-target", "password" => "reset123"}
    response.headers["Location"].should eq "/admin/users"
    admin.get("/admin/users").body.should contain "The password of user pw-target has been reset."
    Fluence::USERS.load!.auth?("pw-target", "reset123").should_not be_nil
    Fluence::USERS["pw-target"].tokens.should be_empty
    target.jar.delete "session_id"
    target.get("/users/settings").headers["Location"].should eq "/users/login"

    # Regular users may not reset passwords.
    target.post "/users/login", {"username" => "pw-target", "password" => "reset123"}
    target.post "/admin/users/password", {"username" => "pw-admin", "password" => "x"}
    Fluence::USERS.load!.auth?("pw-admin", "sekrit123").should_not be_nil
  end
end

describe "login throttling" do
  it "rejects logins and git credentials after too many failures" do
    throttle = Fluence::LOGIN_THROTTLE
    limit, window = throttle.limit, throttle.window
    throttle.clear
    throttle.limit, throttle.window = 3, 3.seconds
    begin
      SpecClient.login "throttled", "sekrit123"
      SpecClient.login "bystander", "sekrit123"
      attacker = SpecClient.new
      attacker.remote_address = Socket::IPAddress.new("192.0.2.7", 40000)
      3.times do
        attacker.post("/users/login", {"username" => "throttled", "password" => "wrong"}).status_code.should eq 302
      end

      # Even the right password is refused now, for this username...
      response = attacker.post "/users/login", {"username" => "throttled", "password" => "sekrit123"}
      response.status_code.should eq 429
      response.body.should contain "Too many failed login attempts."
      attacker.jar["user.token"]?.should be_nil

      elsewhere = SpecClient.new
      elsewhere.remote_address = Socket::IPAddress.new("198.51.100.1", 40000)
      elsewhere.post("/users/login", {"username" => "throttled", "password" => "sekrit123"}).status_code.should eq 429
      git = SpecClient.new.get "/repo/info/refs?service=git-upload-pack", basic_auth("throttled:sekrit123")
      git.status_code.should eq 401

      # ...and for any username from this address.
      attacker.post("/users/login", {"username" => "bystander", "password" => "sekrit123"}).status_code.should eq 429
      elsewhere.post("/users/login", {"username" => "bystander", "password" => "sekrit123"}).status_code.should eq 302

      sleep 3100.milliseconds
      attacker.post("/users/login", {"username" => "throttled", "password" => "sekrit123"}).status_code.should eq 302
      attacker.jar["user.token"]?.should_not be_nil
    ensure
      throttle.limit, throttle.window = limit, window
      throttle.clear
    end
  end
end

describe "rename destination check over HTTP" do
  it "reports an invalid destination name instead of failing" do
    with_each_storage do |_, _|
      client = SpecClient.login "editor", "sekrit123"
      client.post "/pages/movable", {"body" => "# Movable\n"}

      response = client.post "/pages/movable", {"rename" => "rename", "input-page-name" => "a//b"}
      response.status_code.should eq 302
      response.headers["Location"].should eq "/pages/movable"
      Fluence::Page.new("movable").exists?.should be_true
    end
  end

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

  it "finds attachments by name and content, subject to the media ACL" do
    with_each_storage do |_, _|
      Fluence::Page.new("docs").update! SPEC_USER, "# Docs\n"
      Fluence::Media.new("docs/report-qwv.txt").update! SPEC_USER, "nothing here"
      Fluence::Media.new("docs/notes.txt").update! SPEC_USER, "contains findme-qwv inside"
      Fluence::Media.new("locked/secret-qwv.txt").update! SPEC_USER, "x"

      response = SpecClient.new.get "/pages/search?q=qwv"
      response.status_code.should eq 200
      response.body.should contain "/media/docs/report-qwv.txt"
      response.body.should contain "/media/docs/notes.txt"
      response.body.should contain %(href="/pages/docs")
      response.body.should contain "/media/locked/secret-qwv.txt"

      Fluence::ACL["guest"]["#{Fluence::OPTIONS.media_prefix}/locked/*"] = Acl::Perm::None
      begin
        response = SpecClient.new.get "/pages/search?q=qwv"
        response.body.should contain "/media/docs/report-qwv.txt"
        response.body.should_not contain "/media/locked/secret-qwv.txt"
      ensure
        Fluence::ACL["guest"].delete "#{Fluence::OPTIONS.media_prefix}/locked/*"
      end
    end
  end
end

describe "pages by title" do
  it "concatenates readable pages sharing a title, redirects a single match" do
    with_each_storage do |_, _|
      # Matched by title, by name, or both; "dave/other" by neither.
      Fluence::Page.new("alice/calendar").update! SPEC_USER, "# Calendar\nalice-cal-body\n"
      Fluence::Page.new("bob/calendar").update! SPEC_USER, "# Team Calendar\nbob-cal-body\n"
      Fluence::Page.new("carol/plans").update! SPEC_USER, "# Calendar\ncarol-cal-body\n"
      Fluence::Page.new("locked/calendar").update! SPEC_USER, "# Calendar\nlocked-cal-body\n"
      Fluence::Page.new("dave/other").update! SPEC_USER, "# Other\ndave-body\n"

      response = SpecClient.new.get "/titles/calendar"
      response.status_code.should eq 200
      response.body.should contain "alice-cal-body"
      response.body.should contain "bob-cal-body"
      response.body.should contain "carol-cal-body"
      response.body.should contain "locked-cal-body"
      response.body.should_not contain "dave-body"
      response.body.should contain %(href="/pages/alice/calendar")

      Fluence::ACL["guest"]["#{Fluence::OPTIONS.pages_prefix}/locked/*"] = Acl::Perm::None
      begin
        response = SpecClient.new.get "/titles/calendar"
        response.body.should contain "alice-cal-body"
        response.body.should_not contain "locked-cal-body"
      ensure
        Fluence::ACL["guest"].delete "#{Fluence::OPTIONS.pages_prefix}/locked/*"
      end

      response = SpecClient.new.get "/titles/Team%20Calendar"
      response.status_code.should eq 302
      response.headers["Location"].should eq "/pages/bob/calendar"

      SpecClient.new.get("/titles/nothing-here").status_code.should eq 404
    end
  end
end

describe "user settings" do
  it "are saved per user and change how pages open" do
    with_each_storage do |_, _|
      Fluence::Page.new("prefs").update! SPEC_USER, "# Prefs\n"

      response = SpecClient.new.get "/users/settings"
      response.status_code.should eq 302
      response.headers["Location"].should eq "/users/login"

      client = SpecClient.login "prefuser", "sekrit123"
      response = client.get "/users/settings"
      response.status_code.should eq 200
      response.body.should contain %(name="autosave_delay")

      response = client.get "/pages/prefs"
      response.body.should contain "Fluence.editor.init(false);"
      response.body.should contain %("autosave_delay":3)

      response = client.post "/users/settings", {"editor_mode" => "edit", "side_by_side" => "on", "autosave_delay" => "9999", "theme" => "dark"}
      response.status_code.should eq 302
      settings = Fluence::USERS.load!["prefuser"].settings
      settings.editor_mode.should eq "edit"
      settings.side_by_side?.should be_true
      settings.fullscreen?.should be_false
      settings.autosave_delay.should eq 600
      settings.theme.should eq "dark"

      response = client.get "/pages/prefs"
      response.body.should contain "Fluence.editor.init(true);"
      response.body.should contain %(data-bs-theme="dark")
      response.body.should contain %("side_by_side":true)

      client.post "/users/settings", {"editor_mode" => "bogus", "theme" => "neon", "autosave_delay" => "x"}
      settings = Fluence::USERS.load!["prefuser"].settings
      settings.editor_mode.should eq "default"
      settings.theme.should eq "auto"
      settings.autosave_delay.should eq 3
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

  it "rotates the session id at login and keeps the login flash" do
    client = SpecClient.new
    client.post "/users/register", {"username" => "rotator", "password" => "sekrit123"}
    client.get "/users/login"
    before = client.jar["session_id"].value

    response = client.post "/users/login", {"username" => "rotator", "password" => "sekrit123"}
    response.status_code.should eq 302
    after = client.jar["session_id"].value
    after.should_not eq before
    client.get("/users/settings").body.should contain "You are now logged in as user &#39;rotator&#39;."

    # The pre-login session id does not carry the login.
    stale = SpecClient.new
    stale.jar << HTTP::Cookie.new("session_id", before)
    stale.get("/users/settings").headers["Location"].should eq "/users/login"
  end

  it "logs out only with POST" do
    client = SpecClient.login "leaver", "sekrit123"
    body = client.get("/users/settings").body
    body.should contain %(<form id="logout" class="d-inline" method="post" action="/users/logout">)
    body.should_not contain %(href="/users/logout")

    client.get("/users/logout").status_code.should_not eq 302
    client.get("/users/settings").status_code.should eq 200

    response = client.post "/users/logout", {} of String => String
    response.headers["Location"].should eq "/users/login"
    client.jar["user.token"]?.should be_nil
    client.get("/users/settings").headers["Location"].should eq "/users/login"
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
    end
  end

  it "answers a guest's JSON request with 403 and the error instead of a redirect" do
    with_each_storage do |_, _|
      Fluence::Page.new("guarded").update! SPEC_USER, "# Guarded\n"

      headers = HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded", "Accept" => "application/json"}
      response = SpecClient.new.request "POST", "/pages/guarded", headers,
        URI::Params.encode({"body" => "# Defaced\n", "continue" => "1"})
      response.status_code.should eq 403
      response.headers["Content-Type"].should eq "application/json"
      response.body.should eq %({"success":false,"error":"You are not permitted to access this resource (/pages/guarded, write)."})
      Fluence::Page.new("guarded").read.should eq "# Guarded\n"
    end
  end
end

describe "canonical URLs and the ACL" do
  it "applies page rules regardless of case, encoding, or trailing slash in the URL" do
    with_each_storage do |_, _|
      Fluence::Page.new("secret").update! SPEC_USER, "# Secret\n\ntop-secret-body\n"
      client = SpecClient.login "editor", "sekrit123"

      Fluence::ACL["user"]["#{Fluence::OPTIONS.pages_prefix}/secret"] = Acl::Perm::None
      begin
        {"/pages/secret", "/pages/Secret", "/pages/secr%65t", "/pages/secret/"}.each do |url|
          response = client.get url
          response.status_code.should eq 302
          response.body.should_not contain "top-secret-body"
          client.post(url, {"body" => "# Defaced\n"}).status_code.should eq 302
        end
        Fluence::Page.new("secret").read.should eq "# Secret\n\ntop-secret-body\n"

        headers, body = multipart_upload "Secret", "evil.txt", "x"
        client.post("/media/upload", headers, body).body.should contain %("success":false)
        Fluence::Storage.current.list("media").should be_empty
      ensure
        Fluence::ACL["user"].delete "#{Fluence::OPTIONS.pages_prefix}/secret"
      end

      client.get("/pages/Secret").body.should contain "top-secret-body"
    end
  end

  it "applies media rules to the attachment's canonical URL" do
    with_each_storage do |_, _|
      Fluence::Media.new("locked/f.txt").update! SPEC_USER, "hidden-bytes"

      Fluence::ACL["guest"]["#{Fluence::OPTIONS.media_prefix}/locked/*"] = Acl::Perm::None
      begin
        {"/media/locked/f.txt", "/media/%6Cocked/f.txt"}.each do |url|
          response = SpecClient.new.get url
          response.status_code.should eq 302
          response.body.should_not contain "hidden-bytes"
        end
      ensure
        Fluence::ACL["guest"].delete "#{Fluence::OPTIONS.media_prefix}/locked/*"
      end

      SpecClient.new.get("/media/locked/f.txt").body.should eq "hidden-bytes"
    end
  end

  it "serves only harmless attachment types inline" do
    with_each_storage do |_, _|
      Fluence::Media.new("p/pic.png").update! SPEC_USER, "PNG"
      Fluence::Media.new("p/evil.html").update! SPEC_USER, "<script>alert(1)</script>"
      Fluence::Media.new("p/evil.svg").update! SPEC_USER, "<svg onload=alert(1)/>"

      response = SpecClient.new.get "/media/p/pic.png"
      response.headers["Content-Type"].should eq "image/png"
      response.headers["X-Content-Type-Options"].should eq "nosniff"
      response.headers["Content-Disposition"]?.should be_nil

      {"/media/p/evil.html", "/media/p/evil.svg"}.each do |url|
        response = SpecClient.new.get url
        response.status_code.should eq 200
        response.headers["X-Content-Type-Options"].should eq "nosniff"
        response.headers["Content-Disposition"].should start_with "attachment; filename="
      end
    end
  end

  it "stores uploads under the page's canonical name" do
    with_each_storage do |_, _|
      client = SpecClient.login "editor", "sekrit123"
      headers, body = multipart_upload "Docs/Notes", "a.txt", "A"
      client.post("/media/upload", headers, body).body.should contain %("url":"/media/docs/notes/a.txt")
      Fluence::Media.new("docs/notes/a.txt").read.should eq "A"
    end
  end
end

describe "attachment list on a page" do
  it "lists the page's own attachments even when subpages have some" do
    with_each_storage do |_, _|
      Fluence::Page.new("parent").update! SPEC_USER, "# Parent\n"
      Fluence::Page.new("parent/child").update! SPEC_USER, "# Child\n"
      Fluence::Media.new("parent/own.txt").update! SPEC_USER, "own"
      Fluence::Media.new("parent/child/pic.png").update! SPEC_USER, "png"

      response = SpecClient.new.get "/pages/parent"
      response.status_code.should eq 200
      response.body.should contain %(href="/media/parent/own.txt")
      response.body.should_not contain "/media/parent/child/pic.png"
    end
  end
end

describe "deleted accounts" do
  it "treats the session of a deleted user as guest instead of failing" do
    with_each_storage do |_, _|
      Fluence::Page.new("home").update! SPEC_USER, "# Home\n"
      client = SpecClient.login "doomed", "sekrit123"
      client.get("/pages/home").body.should contain "Logged in as"

      Fluence::USERS.transaction!(&.delete("doomed"))

      response = client.get "/pages/home"
      response.status_code.should eq 200
      response.body.should_not contain "Logged in as"
      response.body.should_not contain "<textarea"
      client.post("/users/logout", {} of String => String).status_code.should eq 302
    end
  end
end

describe "page history across renames" do
  it "shows revisions and diffs from before a rename" do
    with_each_storage do |_, _|
      client = SpecClient.login "editor", "sekrit123"
      client.post "/pages/before", {"body" => "# Before\nfirst\n"}
      client.post "/pages/before", {"body" => "# Before\nsecond\n"}
      client.post "/pages/before", {"rename" => "rename", "input-page-name" => "after"}

      commits = Fluence::Page.new("after").history
      commits.map(&.subject).should eq ["Rename page before -> after", "Update page before", "Create page before"]
      commits.map(&.path).should eq ["pages/after.md", "pages/before.md", "pages/before.md"]

      response = SpecClient.new.get "/pages/after?rev=#{commits[2].oid}"
      response.status_code.should eq 200
      response.body.should contain "<p>first</p>"

      response = SpecClient.new.get "/pages/after?diff=#{commits[1].oid}"
      response.status_code.should eq 200
      response.body.should contain %(<span class="diff-add">+second</span>)
    end
  end
end

describe "attachment list markup" do
  it "renders attachments as a plain list with a View toggle and Up/Prev/Next order" do
    with_each_storage do |_, _|
      Fluence::Page.new("att-list").update! SPEC_USER, "# Att List\n"
      Fluence::Media.new("att-list/a.txt").update! SPEC_USER, "A"
      client = SpecClient.login "editor", "sekrit123"

      body = client.get("/pages/att-list").body
      body.should contain %(<ul id="attachments" class="list-unstyled mb-0">)
      body.should contain %(<a class="me-auto text-break" href="/media/att-list/a.txt">a.txt</a>)
      body.should_not contain "list-group-item"
      body.should_not contain "border-bottom"
      body.should contain %(<div id="no-attachments" class="small text-body-secondary" hidden="hidden">None.</div>)
      body.should contain %(id="button_toggle" onclick="Fluence.editor.togglePreview()">View</button>)
      body.index!("↑ Up").should be < body.index!("‹ Prev")

      SpecClient.new.get("/pages/att-list").body.should_not contain %(name="delete")
      Fluence::Page.new("no-att").update! SPEC_USER, "# No Att\n"
      SpecClient.new.get("/pages/no-att").body.should contain %(<div id="no-attachments" class="small text-body-secondary">None.</div>)
    end
  end
end

describe "parent pages after renaming a leaf with attachments" do
  it "keep rendering" do
    with_each_storage do |_, _|
      Fluence::Page.new("1").update! SPEC_USER, "# One\n"
      Fluence::Page.new("1/2").update! SPEC_USER, "# Two\n"
      Fluence::Page.new("1/2/3").update! SPEC_USER, "# Three\n"
      Fluence::Media.new("1/2/3/f.txt").update! SPEC_USER, "F"
      client = SpecClient.login "editor", "sekrit123"

      client.post("/pages/1/2/3", {"rename" => "rename", "input-page-name" => "1/2/3x"}).status_code.should eq 302
      {"/pages/1", "/pages/1/2", "/pages/1/2/3x", "/sitemap"}.each do |url|
        client.get(url).status_code.should eq 200
      end
      client.get("/pages/1/2/3x").body.should contain %(href="/media/1/2/3x/f.txt")
    end
  end
end

describe "sidebar of a page that does not exist" do
  it "says so instead of showing the page sections" do
    with_each_storage do |_, _|
      body = SpecClient.login("editor", "sekrit123").get("/pages/not-yet").body
      body.should contain "This page does not exist yet. Click Save to create it."
      body.should_not contain %(id="page-toc")

      body = SpecClient.new.get("/pages/not-yet").body
      body.should contain "This page does not exist yet."
      body.should_not contain "Click Save"
    end
  end
end

describe "table of contents" do
  it "escapes heading text" do
    with_each_storage do |_, _|
      Fluence::Page.new("toc-esc").update! SPEC_USER, "# Toc Esc\n## A <b>bold</b> & \"quoted\" one\n"

      body = SpecClient.new.get("/pages/toc-esc").body
      entry = body.match!(/<li><a href="#([^"]*)">(A .*?)<\/a>/)
      entry[1].should eq "a-b-bold-/b-quoted-one"
      entry[2].should eq "A &lt;b&gt;bold&lt;/b&gt; &amp; &quot;quoted&quot; one"
      body.should contain %(<h2 id="#{entry[1]}">)
      body.should_not contain "<b>bold</b>"
    end
  end

  it "links each of several same-named headings to its own section" do
    with_each_storage do |_, _|
      Fluence::Page.new("toc-dup").update! SPEC_USER,
        "# Toc Dup\n## Notes\ntext\n```\n## Notes\n```\n## Notes\n### Notes\n## Notes 1\n"

      body = SpecClient.new.get("/pages/toc-dup").body
      anchors = body.scan(/<li><a href="#([^"]*)">Notes/).map(&.[1])
      anchors.should eq ["notes", "notes-1", "notes-2", "notes-1-1"]
      ids = body.scan(/<h[1-6] id="([^"]*)">Notes/).map(&.[1])
      ids.should eq anchors
    end
  end
end

describe "sitemap" do
  it "lists media as a tree of links" do
    with_each_storage do |_, _|
      Fluence::Media.new("docs/guide/shot.png").update! SPEC_USER, "PNG"
      Fluence::Media.new("docs/top.txt").update! SPEC_USER, "T"
      Fluence::Media.new("root.txt").update! SPEC_USER, "R"

      body = SpecClient.new.get("/sitemap").body
      body.should contain %(<a href="/media/docs/guide/shot.png">shot.png</a>)
      body.should contain %(<a href="/media/docs/top.txt">top.txt</a>)
      body.should contain %(<a href="/media/root.txt">root.txt</a>)
      body.should_not contain %(href="/media/docs")
      body.index!("<span class=\"text-body-secondary\">docs</span>").should be < body.index!("shot.png")
    end
  end
end

describe "admin forms" do
  it "report a failure as a flash message instead of an error page" do
    with_each_storage do |_, _|
      backup = File.read(Fluence::USERS.file)
      begin
        Fluence::USERS.transaction!(&.list.clear)
        admin = SpecClient.new
        admin.post "/users/register", {"username" => "founder", "password" => "sekrit123"}
        admin.post "/users/login", {"username" => "founder", "password" => "sekrit123"}

        response = admin.post "/admin/users/delete", {"username" => "nobody"}
        response.status_code.should eq 302
        response.headers["Location"].should eq "/admin/users"
        admin.get("/admin/users").body.should contain "Unable to process that: User nobody is not in the list."

        response = admin.post "/admin/acls/delete", {"group" => "no-such-group", "path" => "/x"}
        response.status_code.should eq 302
        admin.get("/admin/acls").body.should contain "Unable to process that"

        response = admin.post "/admin/acls/create", {"group" => "g", "path" => "/x", "perm" => "bogus"}
        response.status_code.should eq 302
        Fluence::ACL["g"]?.should be_nil
      ensure
        File.write(Fluence::USERS.file, backup)
        Fluence::USERS.load!
      end
    end
  end
end

describe "user deletion" do
  it "keeps at least one admin" do
    backup = File.read(Fluence::USERS.file)
    begin
      Fluence::USERS.transaction!(&.list.clear)
      admin = SpecClient.new
      admin.post "/users/register", {"username" => "founder", "password" => "sekrit123"}
      admin.post "/users/login", {"username" => "founder", "password" => "sekrit123"}

      admin.post "/admin/users/delete", {"username" => "founder"}
      admin.get("/admin/users").body.should contain "The user founder is the last administrator and cannot be deleted."
      Fluence::USERS.load!["founder"]?.should_not be_nil

      admin.post "/admin/users/create", {"username" => "deputy", "password" => "sekrit123", "groups" => "user, admin"}
      admin.post "/admin/users/create", {"username" => "plain", "password" => "sekrit123", "groups" => "user"}
      admin.post "/admin/users/delete", {"username" => "plain"}
      Fluence::USERS.load!["plain"]?.should be_nil

      admin.post "/admin/users/delete", {"username" => "deputy"}
      admin.get("/admin/users").body.should contain "The user deputy has been deleted."
      Fluence::USERS.load!["deputy"]?.should be_nil

      admin.post "/admin/users/delete", {"username" => "founder"}
      Fluence::USERS.load!["founder"]?.should_not be_nil
    ensure
      File.write(Fluence::USERS.file, backup)
      Fluence::USERS.load!
    end
  end
end

describe "response headers" do
  it "forbids framing" do
    with_each_storage do |_, _|
      response = SpecClient.new.get "/users/login"
      response.headers["X-Frame-Options"].should eq "DENY"
      response.headers["Content-Security-Policy"].should eq "frame-ancestors 'none'"
    end
  end
end

describe "CSRF protection" do
  it "refuses POSTs without the session's token and accepts them with it" do
    with_each_storage do |_, _|
      client = SpecClient.login "editor", "sekrit123"
      client.post "/pages/guarded", {"body" => "# Guarded\n"}

      response = client.post "/pages/guarded", {"body" => "# Forged\n"}, csrf: false
      response.status_code.should eq 403
      response.body.should contain "valid security token"
      response = client.post "/pages/guarded", {"body" => "# Forged\n", "authenticity_token" => "wrong"}, csrf: false
      response.status_code.should eq 403
      headers = HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded", "Accept" => "application/json"}
      response = client.post "/pages/guarded", headers, URI::Params.encode({"body" => "# Forged\n"}), csrf: false
      response.status_code.should eq 403
      response.headers["Content-Type"].should eq "application/json"
      JSON.parse(response.body)["success"].as_bool.should be_false
      headers, body = multipart_upload "guarded", "forged.txt", "x"
      client.post("/media/upload", headers, body, csrf: false).status_code.should eq 403
      Fluence::Page.new("guarded").read.should eq "# Guarded\n"
      Fluence::Storage.current.list("media").should be_empty

      # One token per session: it is not rotated, so pages opened earlier
      # (other tabs, "Save and continue") keep working.
      token = client.csrf_token
      client.post("/pages/guarded", {"body" => "# One\n"}).status_code.should eq 302
      client.post("/pages/guarded", {"body" => "# Two\n"}).status_code.should eq 302
      client.csrf_token.should eq token
      Fluence::Page.new("guarded").read.should eq "# Two\n"
    end
  end

  it "puts the token into every form and the meta tag read by base.js" do
    with_each_storage do |_, _|
      guest = SpecClient.new
      body = guest.get("/users/login").body
      token = body.match!(/name="authenticity_token" value="([^"]+)"/)[1]
      body.should contain %(<meta name="csrf-token" content="#{token}">)

      # Anonymous readers of a page without forms start no session.
      Fluence::Page.new("plain").update! SPEC_USER, "# Plain\n"
      reader = SpecClient.new
      reader.get("/pages/plain").body.should_not contain "csrf-token"

      client = SpecClient.login "editor", "sekrit123"
      body = client.get("/pages/plain").body
      token = client.csrf_token
      body.should contain %(<meta name="csrf-token" content="#{token}">)
      forms = body.scan(/<form [^>]*method="post"[^>]*>(\s*<[^>]+>)/)
      forms.size.should eq 5 # logout, edit, upload, attachments, page management
      forms.count(&.[1].includes?(%(name="authenticity_token" value="#{token}"))).should eq 4
    end
  end

  it "does not apply to the git smart-HTTP routes" do
    with_each_storage do |_, _|
      SpecClient.login "editor", "sekrit123"
      client = SpecClient.new
      client.get "/users/login" # a browser-like session, which git never has
      headers = HTTP::Headers{"Content-Type" => "application/x-git-receive-pack-request"}
      client.post("/repo/git-receive-pack", headers, "0000").status_code.should eq 401

      headers.merge! basic_auth("seed-admin:seed-password")
      response = client.post "/repo/git-receive-pack", headers, "0000"
      response.status_code.should eq 200
      response.headers["Content-Type"].should eq "application/x-git-receive-pack-result"
    end
  end
end
