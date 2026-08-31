require "./spec_helper"

# Fluence was originally written for Crystal < 1.0, whose YAML.mapping and
# enum serialization produced a specific on-disk format for the meta/ files.
# These specs make sure the current YAML::Serializable-based code both
# round-trips its own format and still reads meta files written by old builds.
describe "serialization" do
  it "round-trips a Group through YAML" do
    g1 = Acl::Group.new(
      name: "user",
      default: Acl::Perm::Read,
      permissions: {
        "/tmp/protected" => Acl::Perm::None,
        "/tmp/write/*"   => Acl::Perm::Write,
      })
    g2 = Acl::Group.from_yaml g1.to_yaml
    g2.name.should eq "user"
    g2.default.should eq Acl::Perm::Read
    g2.permitted?("/tmp/write/x", Acl::Perm::Write).should be_true
    g2.permitted?("/tmp/protected", Acl::Perm::Read).should be_false
    g2.permitted?("/elsewhere", Acl::Perm::Read).should be_true
  end

  it "reads Group YAML written by Crystal < 1.0 (numeric enum values)" do
    legacy = <<-YAML
      name: guest
      permissions:
        ? value: /pages/*
        : 1
        ? value: /users/*
        : 3
      default: 0
      YAML
    g = Acl::Group.from_yaml legacy
    g.permitted?("/pages/x", Acl::Perm::Read).should be_true
    g.permitted?("/pages/x", Acl::Perm::Write).should be_false
    g.permitted?("/users/x", Acl::Perm::Write).should be_true
    g.permitted?("/other", Acl::Perm::Read).should be_false
  end

  it "reads both old and new Perm scalar forms" do
    Acl::Perm.from_yaml("write").should eq Acl::Perm::Write
    Acl::Perm.from_yaml("Read").should eq Acl::Perm::Read
    Acl::Perm.from_yaml("3").should eq Acl::Perm::Write
    Acl::Perm.from_yaml("0").should eq Acl::Perm::None
  end

  it "round-trips a User through YAML" do
    u1 = Fluence::User.new "tester", "password", %w(user admin)
    u2 = Fluence::User.from_yaml u1.to_yaml
    u2.name.should eq "tester"
    u2.groups.should eq %w(user admin)
    u2.token.should be_nil
  end

  it "reads timestamps written by Crystal < 1.0" do
    t = Time.from_yaml("2020-05-17 10:20:30.000000000")
    t.year.should eq 2020
    t.month.should eq 5
  end
end
