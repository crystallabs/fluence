require "./spec_helper"

describe Fluence::LoginThrottle do
  it "blocks an address or a username after too many recent failures" do
    throttle = Fluence::LoginThrottle.new limit: 3, window: 100.milliseconds
    here = Socket::IPAddress.new("10.0.0.1", 1234)
    there = Socket::IPAddress.new("10.0.0.2", 1234)

    2.times { throttle.failure! here, "alice" }
    throttle.blocked?(here, "alice").should be_false
    throttle.failure! here, "alice"
    throttle.blocked?(here, "alice").should be_true
    throttle.blocked?(here, "bob").should be_true
    throttle.blocked?(there, "alice").should be_true
    throttle.blocked?(there, "bob").should be_false
    throttle.blocked?(nil, "bob").should be_false

    sleep 150.milliseconds
    throttle.blocked?(here, "alice").should be_false
    throttle.size.should eq 0
  end

  it "clears the keys of a successful login" do
    throttle = Fluence::LoginThrottle.new limit: 2, window: 1.minute
    here = Socket::IPAddress.new("10.0.0.1", 1234)
    2.times { throttle.failure! here, "alice" }
    throttle.blocked?(nil, "alice").should be_true
    throttle.success! here, "alice"
    throttle.blocked?(here, "alice").should be_false
    throttle.size.should eq 0
  end
end
