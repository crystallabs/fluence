# In-memory limiter of failed logins, keyed by client IP address and by
# username: once a key has `limit` failures within `window`, login
# attempts involving it are rejected until the oldest failures age out.
# A successful login clears the keys it was made with.
#
# Only the address of the connecting peer is used; headers such as
# X-Forwarded-For are ignored, since any client can set them.
class Fluence::LoginThrottle
  property limit : Int32
  property window : Time::Span

  def initialize(@limit = 10, @window = 15.minutes)
    @failures = {} of String => Array(Time)
    @lock = Mutex.new
  end

  # True when the address or the username has too many recent failures.
  # Stale entries are pruned on every check.
  def blocked?(address : Socket::Address?, username : String) : Bool
    @lock.synchronize do
      prune
      keys(address, username).any? { |key| (@failures[key]?.try(&.size) || 0) >= @limit }
    end
  end

  def failure!(address : Socket::Address?, username : String) : Nil
    now = Time.utc
    @lock.synchronize do
      keys(address, username).each { |key| (@failures[key] ||= [] of Time) << now }
    end
  end

  def success!(address : Socket::Address?, username : String) : Nil
    @lock.synchronize do
      keys(address, username).each { |key| @failures.delete key }
    end
  end

  # Forgets all failures.
  def clear : Nil
    @lock.synchronize { @failures.clear }
  end

  # Number of keys with recorded failures.
  def size : Int32
    @lock.synchronize { @failures.size }
  end

  private def prune
    cutoff = Time.utc - @window
    @failures.reject! do |_, times|
      times.reject! { |time| time <= cutoff }
      times.empty?
    end
  end

  private def keys(address : Socket::Address?, username : String) : Array(String)
    keys = ["user:#{username}"]
    ip = address.is_a?(Socket::IPAddress) ? address.address : address.try(&.to_s)
    keys << "ip:#{ip}" if ip
    keys
  end
end

module Fluence
  # The limiter shared by the login form and git's HTTP Basic auth.
  LOGIN_THROTTLE = LoginThrottle.new
end
