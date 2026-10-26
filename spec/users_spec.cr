require "./spec_helper"

describe Fluence::Users do
  it "adds, finds, updates, and deletes users" do
    users = Fluence::Users.new File.tempname("fluence-spec-users")
    users.add Fluence::User.new("alice", "pw", %w[user])
    users["alice"].groups.should eq %w[user]
    expect_raises(Fluence::Users::AlreadyExists) { users.add Fluence::User.new("alice", "pw") }

    users.update "alice", Fluence::User.new("alice", "pw", %w[user admin])
    users["alice"].groups.should eq %w[user admin]

    users.update "alice", Fluence::User.new("alicia", "pw", %w[user])
    users["alice"]?.should be_nil
    users["alicia"].groups.should eq %w[user]
    expect_raises(Fluence::Users::NotExists) { users.update "nobody", Fluence::User.new("x", "pw") }

    users.delete "alicia"
    users["alicia"]?.should be_nil
    expect_raises(Fluence::Users::NotExists) { users.delete "alicia" }
  end

  it "loads an empty file as no users and refuses a malformed one" do
    file = File.tempname("fluence-spec-users")
    users = Fluence::Users.new file
    users.load!.list.should be_empty

    users.add Fluence::User.new("alice", "pw")
    users.save!
    Fluence::Users.new(file).load!["alice"]?.should_not be_nil

    File.write file, "list: [not a hash\n"
    expect_raises(YAML::ParseException) { Fluence::Users.new(file).load! }
  end

  it "does not save a transaction whose block raised" do
    file = File.tempname("fluence-spec-users")
    users = Fluence::Users.new file
    users.transaction! &.add(Fluence::User.new("alice", "pw"))
    expect_raises(Exception, "boom") do
      users.transaction! do |list|
        list.add Fluence::User.new("bob", "pw")
        raise "boom"
      end
    end
    reloaded = Fluence::Users.new(file).load!
    reloaded["alice"]?.should_not be_nil
    reloaded["bob"]?.should be_nil
  end

  it "reloads the file before every transaction" do
    file = File.tempname("fluence-spec-users")
    users = Fluence::Users.new file
    users.transaction! &.add(Fluence::User.new("alice", "pw"))

    # A hand edit made behind the back of the in-memory copy.
    other = Fluence::Users.new(file).load!
    other.add Fluence::User.new("bob", "pw")
    other.save!

    users.transaction! &.add(Fluence::User.new("carol", "pw"))
    reloaded = Fluence::Users.new(file).load!
    reloaded.list.keys.should eq %w[alice bob carol]
  end

  it "keeps the file readable by its owner only" do
    file = File.tempname("fluence-spec-users")
    File.write file, "", perm: 0o644
    users = Fluence::Users.new file
    (File.info(file).permissions.value & 0o777).should eq 0o600
    users.transaction! &.add(Fluence::User.new("alice", "pw"))
    (File.info(file).permissions.value & 0o777).should eq 0o600

    fresh = File.tempname("fluence-spec-users")
    Fluence::Users.new fresh
    (File.info(fresh).permissions.value & 0o777).should eq 0o600
  end
end

describe Fluence::User do
  it "rejects names with a trailing newline" do
    expect_raises(Exception, /Invalid name/) { Fluence::User.new "admin\n", "password" }
    Fluence::User.new("admin", "password").name.should eq "admin"
  end
end
