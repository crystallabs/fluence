require "json"

# Vendored port of kemal-flash (https://github.com/neovintage/kemal-flash),
# which is unmaintained and relied on JSON.mapping, removed in Crystal 1.0.
module Kemal::Flash
  class FlashHash
    include JSON::Serializable
    include Kemal::Session::StorableObject

    delegate each, empty?, keys, has_key?, delete, to_h, to: @values

    getter values : Hash(String, String)
    @discard : Set(String)

    def initialize
      @values = Hash(String, String).new
      @discard = Set(String).new
    end

    def self.from_json(string_or_io)
      flash_hash = new(JSON::PullParser.new(string_or_io))
      flash_hash.sweep
      flash_hash
    end

    def to_json(json : JSON::Builder)
      @values.reject!(@discard.to_a)
      @discard.clear
      super
    end

    def update(h : Hash(String, String))
      @discard.subtract h.keys
      @values.merge!(h)
    end

    def []=(k : String, val : String)
      @values[k] = val
      @discard.delete(k)
    end

    def [](k : String)
      @discard.add(k)
      @values[k]
    end

    def []?(k : String)
      @discard.add(k)
      @values[k]?
    end

    # Discards the key at the end of the current action
    def discard(key : String)
      @discard.add(key)
    end

    # Discards all keys at the end of the current action
    def discard
      @discard.concat(@values.keys)
    end

    # Removes any values that are in the discard set; keys that
    # remain are up for discard at the end of the current action.
    def sweep
      @values.reject!(@discard.to_a)
      @discard = Set(String).new(@values.keys)
    end
  end
end

class HTTP::Server::Context
  @flash : Kemal::Flash::FlashHash?

  def flash : Kemal::Flash::FlashHash
    @flash ||= begin
      objs = session.objects
      if objs.keys.includes?("flash")
        session.object("flash").as(Kemal::Flash::FlashHash)
      else
        Kemal::Flash::FlashHash.new
      end
    end
  end

  def commit_flash!
    session.object("flash", flash)
  end
end

# The flash has to be recommitted to the session or changes made
# during the request would be lost.
after_all do |context|
  context.commit_flash!
end
