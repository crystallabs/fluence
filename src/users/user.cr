require "crypto/bcrypt/password"
require "../acl/entity"
require "./settings"

# A `User` consists of name/password/groups/tokens.
# The *name* and *groups* is public, the *password* and the *tokens* are private.
# The password is used to recognize an user when login in with a form for example.
# The tokens recognize an user by a remember-me cookie, one per browser.
class Fluence::User
  class Invalid < Exception
  end

  include YAML::Serializable

  property name : String
  property password : String
  property groups : Array(String)
  # Remember-me login tokens, one per browser, oldest first.
  property tokens : Array(String) = [] of String
  property settings : Settings = Settings.new

  # Files written before tokens were per browser hold a single scalar
  # `token:`; it is moved into `tokens` on load and not written back.
  @[YAML::Field(key: "token")]
  @legacy_token : String? = nil

  # Remember-me tokens kept per user; issuing one more drops the oldest.
  MAX_TOKENS = 10

  # ```
  # User.new "admin", "password", %w(admin user)
  # User.new "regular", "password", %w(user guest)
  # ```
  # Accepted user names. The anchors are \\A and \\z on purpose: ^ and $
  # would also accept a name followed by a newline.
  NAME = /\A[A-Za-z0-9 _.-]+\z/

  # Work factor of bcrypt password hashes. Specs lower it, since every
  # registration and login in the suite would otherwise cost ~0.5 s.
  class_property bcrypt_cost : Int32 = Crypto::Bcrypt::DEFAULT_COST

  def initialize(@name, @password, @groups = [] of String)
    raise "Invalid name #{@name}" unless @name.matches? NAME # Security: Avoid escaping and injection of code
  end

  protected def after_initialize
    if token = @legacy_token
      @tokens << token unless @tokens.includes? token
      @legacy_token = nil
    end
  end

  # Encrypts the password using `Crypto::Bcrypt`.
  #
  # ```
  # Fluence::User.new("admin", "password", %w(admin)).encrypt!.password # => "$2a$11$G2i2.Km1DRbJtqDBFRhKXuSn8IwNVt7AypAP328T1OYq0wBugkgCm"
  # ```
  def encrypt!
    @password = Crypto::Bcrypt::Password.create(@password, cost: User.bcrypt_cost).to_s
    self
  end

  # Reads the password using `Crypto::Bcrypt`
  def password_encrypted
    Crypto::Bcrypt::Password.new @password
  end

  # Adds a new remember-me token and returns it, dropping the oldest ones
  # beyond `MAX_TOKENS`.
  def issue_token! : String
    token = Random::Secure.base64 64
    @tokens << token
    @tokens.shift(@tokens.size - MAX_TOKENS) if @tokens.size > MAX_TOKENS
    token
  end

  # Removes a remember-me token (a no-op when it is not one of the user's).
  def revoke_token(token : String) : Nil
    @tokens.delete token
  end

  # Removes all remember-me tokens: no browser can log in by cookie anymore.
  def clear_tokens! : Nil
    @tokens.clear
  end

  # Sets a new (plain text) password, stored encrypted, and clears the
  # remember-me tokens, so cookies issued under the old one stop working.
  def change_password!(password : String) : self
    raise Invalid.new "The password cannot be empty" if password.empty?
    @password = password
    encrypt!
    clear_tokens!
    self
  end

  #########################
  # Implement Acl::Entity #
  #########################
  include Acl::Entity

  def group?(group : String) : Bool
    @groups.includes? group
  end
end
