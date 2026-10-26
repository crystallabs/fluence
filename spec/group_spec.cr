describe Acl::Group do
  it "test initialize" do
    # First initializer, simple
    g1 = Acl::Group.new("name1",
      {Acl::Path.new("/") => Acl::Perm::Read},
      Acl::Perm::None
    )
    # First initializer, named arguments
    g2 = Acl::Group.new(
      name: "name2",
      permissions: {Acl::Path.new("/o") => Acl::Perm::Write},
      default: Acl::Perm::Read
    )
    # Sec initializer, simple
    g3 = Acl::Group.new("name3",
      {"/" => Acl::Perm::Read},
      Acl::Perm::None
    )
    # Sec initializer, named arguments
    g4 = Acl::Group.new(
      name: "name4",
      permissions: {"/o" => Acl::Perm::Write},
      default: Acl::Perm::Read
    )
    g1.name.should eq "name1"
    g2.name.should eq "name2"
    g3.name.should eq "name3"
    g4.name.should eq "name4"
    g1.default.should eq Acl::Perm::None
    g2.default.should eq Acl::Perm::Read
    g3.default.should eq Acl::Perm::None
    g4.default.should eq Acl::Perm::Read
  end

  it "test permitted?" do
    g = Acl::Group.new(
      name: "guest",
      permissions: {
        Acl::Path.new("/public*")           => Acl::Perm::Write,
        Acl::Path.new("/restricted*")       => Acl::Perm::Read,
        Acl::Path.new("/users*")            => Acl::Perm::Read,
        Acl::Path.new("/users/guest")       => Acl::Perm::Write,
        Acl::Path.new("/users/protected/*") => Acl::Perm::None,
      },
      default: Acl::Perm::None
    )
    g.permitted?("/", Acl::Perm::Read).should be_false
    g.permitted?("/users", Acl::Perm::Read).should be_true
    g.permitted?("/users/guest", Acl::Perm::Read).should be_true
    g.permitted?("/users/admin", Acl::Perm::Read).should be_true
    g.permitted?("/users/guest", Acl::Perm::Write).should be_true
    g.permitted?("/users/admin", Acl::Perm::Write).should be_false
    g.permitted?("/users/protected/any", Acl::Perm::Read).should be_false
    g.permitted?("/public", Acl::Perm::Read).should be_true
    g.permitted?("/public", Acl::Perm::Write).should be_true
    g.permitted?("/public/some", Acl::Perm::Write).should be_true
    g.permitted?("/public/some", Acl::Perm::Write).should be_true
    g.permitted?("/publicXXX/some", Acl::Perm::Write).should be_true
  end

  it "advanced test permitted?" do
    g = Acl::Group.new(
      name: "guest",
      permissions: {
        Acl::Path.new("/write/*")        => Acl::Perm::Write,
        Acl::Path.new("/read/*")         => Acl::Perm::Read,
        Acl::Path.new("/none/*")         => Acl::Perm::None,
        Acl::Path.new("/read/none")      => Acl::Perm::None,
        Acl::Path.new("/write/none")     => Acl::Perm::None,
        Acl::Path.new("/none/readonly")  => Acl::Perm::Read,
        Acl::Path.new("/write/readonly") => Acl::Perm::Read,
        Acl::Path.new("/read/writeonly") => Acl::Perm::Write,
        Acl::Path.new("/none/writeonly") => Acl::Perm::Write,
      },
      default: Acl::Perm::Read
    )
    g.permitted?("/", Acl::Perm::Read).should be_true
    g.permitted?("/", Acl::Perm::Write).should be_false
    g.permitted?("/none/any", Acl::Perm::None).should be_true
    g.permitted?("/none/any", Acl::Perm::Read).should be_false
    g.permitted?("/read/any", Acl::Perm::Read).should be_true
    g.permitted?("/read/any", Acl::Perm::Write).should be_false
    g.permitted?("/write/any", Acl::Perm::Write).should be_true
    g.permitted?("/read/none", Acl::Perm::Read).should be_false
    g.permitted?("/write/none", Acl::Perm::Read).should be_false
    g.permitted?("/none/readonly", Acl::Perm::Read).should be_true
    g.permitted?("/write/readonly", Acl::Perm::Write).should be_false
    g.permitted?("/none/writeonly", Acl::Perm::Write).should be_true
    g.permitted?("/read/writeonly", Acl::Perm::Write).should be_true
  end

  it "test permissions access" do
    g = Acl::Group.new(
      name: "guest",
      permissions: {
        "/public*"     => Acl::Perm::Write,
        "/restricted*" => Acl::Perm::Read,
        "/users*"      => Acl::Perm::Read,
        "/users/guest" => Acl::Perm::Write,
      },
      default: Acl::Perm::None
    )
    g["/"]?.should eq nil
    g["/"].should eq g.default
    # TODO: enable this test after changing the design of operator [] to do not match path
    # g["/public"]?.should eq nil
    g["/public*"]?.should eq Acl::Perm::Write

    g["/"] = Acl::Perm::Read
    g["/"]?.should eq Acl::Perm::Read
    g.delete("/")
    g["/"]?.should eq nil
  end
end
