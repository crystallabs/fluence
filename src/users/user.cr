require "crypto/bcrypt/password"
require "../acl/entity"

# A `User` consists of name/password/groups/token.
# The *name* and *groups* is public, the *password* and the *token* are private.
# The password is used to recognize an user when login in with a form for example.
# The token is used to recognize an user by a cookie for example.
class Fluence::User
  class Invalid < Exception
  end

  include YAML::Serializable

  property name : String
  property password : String
  property groups : Array(String)
  property token : String?

  # ```
  # User.new "admin", "password", %w(admin user)
  # User.new "regular", "password", %w(user guest)
  # ```
  def initialize(@name, @password, @groups = [] of String, @token : String? = nil)
    raise "Invalid name #{@name}" if @name !~ /^[A-Za-z0-9 _.-]+$/ # Security: Avoid escaping and injection of code
  end

  # Encrypts the password using `Crypto::Bcrypt`.
  #
  # ```
  # Fluence::User.new("admin", "password", %w(admin)).encrypt!.password # => "$2a$11$G2i2.Km1DRbJtqDBFRhKXuSn8IwNVt7AypAP328T1OYq0wBugkgCm"
  # ```
  def encrypt!
    @password = Crypto::Bcrypt::Password.create(@password).to_s
    self
  end

  # Reads the password using `Crypto::Bcrypt`
  def password_encrypted
    Crypto::Bcrypt::Password.new @password
  end

  def generate_new_token!
    @token = Random::Secure.base64 64
  end

  #########################
  # Implement Acl::Entity #
  #########################
  include Acl::Entity

  def group?(group : String) : Bool
    @groups.includes? group
  end
end
