describe Acl do
  it "test the users permissions" do
    acls = Acl::Groups.new File.tempfile("spec").to_s
    g1 = Acl::Group.new(
      name: "user",
      default: Acl::Perm::Read,
      permissions: {
        "/tmp/protected" => Acl::Perm::None,
        "/tmp/write/*"   => Acl::Perm::Write,
        "/match/*" => Acl::Perm::Write,
        "/match/not-file" => Acl::Perm::None,
        "/match/not-dir/*" => Acl::Perm::None,
      })
    g2 = Acl::Group.new(
      name: "admin",
      permissions: {
        "/match/*" => Acl::Perm::Read,
      },
      default: Acl::Perm::Write)
    acls.add g1
    acls.add g2
    u1 = Fluence::User.new "u1", "", %w(user)
    u2 = Fluence::User.new "u2", "", %w(user admin)

    # simple
    acls.permitted?(u1, "/", Acl::Perm::Read).should be_true
    acls.permitted?(u1, "/tmp", Acl::Perm::Read).should be_true
    acls.permitted?(u1, "/tmp", Acl::Perm::Write).should be_false
    acls.permitted?(u1, "/tmp/protected", Acl::Perm::Read).should be_false
    acls.permitted?(u2, "/tmp/protected", Acl::Perm::Read).should be_true

    # matching
    acls.permitted?(u1, "/tmp/write/test", Acl::Perm::Read).should be_true
    acls.permitted?(u1, "/tmp/write/test", Acl::Perm::Write).should be_true
    acls.permitted?(u1, "/match/write-ok", Acl::Perm::Read).should be_true
    acls.permitted?(u1, "/match/write-ok", Acl::Perm::Write).should be_true
    # TODO: enable those tests
    acls.permitted?(u1, "/match/not-file", Acl::Perm::Write).should be_false
    acls.permitted?(u1, "/match/not-dir/any", Acl::Perm::Write).should be_false
    acls.permitted?(u1, "/match/not-file", Acl::Perm::Read).should be_false
    acls.permitted?(u1, "/match/not-dir/any", Acl::Perm::Read).should be_false
  end

  it "test the paths matching" do
    Acl::Path.new("/*").acl_match?("/a/test").should eq(true)
    Acl::Path.new("/a*").acl_match?("/a/test").should eq(true)
    Acl::Path.new("/a/test*").acl_match?("/a/test").should eq(true)
    Acl::Path.new("/a/test*").acl_match?("/a/test/").should eq(true)
    Acl::Path.new("/a/test*").acl_match?("/b/test").should eq(false)
    Acl::Path.new("/a/test*").acl_match?("/a/other").should eq(false)
    # Only "*" is special; regex metacharacters are literal.
    Acl::Path.new("/pages/a.b").acl_match?("/pages/a.b").should eq(true)
    Acl::Path.new("/pages/a.b").acl_match?("/pages/aXb").should eq(false)
    Acl::Path.new("/pages/(x)+").acl_match?("/pages/(x)+").should eq(true)
    Acl::Path.new("/pages/(x)+").acl_match?("/pages/x").should eq(false)
    Acl::Path.new("/pages/*").acl_match?("/pages/a\nb").should eq(false)
  end

  it "groups having" do
    acls = Acl::Groups.new File.tempfile("spec").to_s
    acls.add "guest"
    acls.add "admin"
    acls["guest"]["/*"] = Acl::Perm::Read
    acls["guest"]["/write/*"] = Acl::Perm::Write
    acls["guest"]["/write/admin"] = Acl::Perm::Read
    acls["admin"]["/*"] = Acl::Perm::Write
    acls.groups_having_any_access_to("/", Acl::Perm::Read).should eq(["guest", "admin"])
    acls.groups_having_any_access_to("/", Acl::Perm::Write).should eq(["admin"])
    acls.groups_having_any_access_to("/write", Acl::Perm::Write).should eq(["admin"])
    acls.groups_having_any_access_to("/write/anypage", Acl::Perm::Write).should eq(["guest", "admin"])
    acls.groups_having_any_access_to("/write/admin", Acl::Perm::Write).should eq(["admin"])
    acls.groups_having_direct_access_to("/*", Acl::Perm::Read).should eq(["guest", "admin"])
    acls.groups_having_direct_access_to("/*", Acl::Perm::Write).should eq(["admin"])
  end

  it "loads an empty file as no groups and refuses a malformed one" do
    file = File.tempname("fluence-spec-acl")
    acls = Acl::Groups.new file
    acls.load!.groups.should be_empty

    acls.add "guest"
    acls["guest"]["/*"] = Acl::Perm::Read
    acls.save!
    Acl::Groups.new(file).load!["guest"]["/*"].should eq Acl::Perm::Read

    File.write file, "groups: [not a hash\n"
    expect_raises(YAML::ParseException) { Acl::Groups.new(file).load! }
  end
end
