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
end
