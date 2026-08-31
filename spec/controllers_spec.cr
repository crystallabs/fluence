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
