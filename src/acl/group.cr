require "yaml"

require "./perm"

# The Group is identified by a *name* and has *permissions* on a set of paths.
# It is used by `Groups`.
# NOTE: I did not use Hash().new(default) because it is annoying with passing the permissions in the constructor
class Acl::Group
  include YAML::Serializable

  property name : String
  property permissions : Hash(Acl::Path, Acl::Perm)
  property default : Acl::Perm

  # Create a new named Group with optional parameters.
  #
  # - *name* is the name of the group (arbitrary `String`).
  # - *permissions* is a hash of ``{Acl::Path.new("path") => `Perm`}``.
  # - *default* is the value used for every path not defined in the *permissions*.
  #
  # ```
  # guest = Acl::Group.new(name: "guest", default: Acl::Perm::None, permissions: {Acl::Path.new "/public" => Acl::Perm::Read})
  # user = Acl::Group.new(name: "user", default: Acl::Perm::Read, permissions: {Acl::Path.new "/protected" => Acl::Perm::None})
  # admin = Acl::Group.new(name: "admin", default: Acl::Perm::Write)
  # ```
  def initialize(@name,
                 @permissions : Hash(Acl::Path, Acl::Perm) = Hash(Acl::Path, Acl::Perm).new,
                 @default : Acl::Perm = Acl::Perm::None)
  end

  # ```
  # guest = Acl::Group.new(name: "guest", default: Acl::Perm::None, permissions: {"/public" => Acl::Perm::Read})
  # user = Acl::Group.new(name: "user", default: Acl::Perm::Read, permissions: {"/protected" => Acl::Perm::None})
  # admin = Acl::Group.new(name: "admin", default: Acl::Perm::Write)
  # ```
  def initialize(@name,
                 permissions : Hash(String, Acl::Perm),
                 @default : Acl::Perm = Acl::Perm::None)
    @permissions = permissions.map { |k, v| {Acl::Path.new(k), v} }.to_h
  end

  # Check if the group has the `Acl::Perm` required to have access to a given path.
  #
  # - *path* is the path that must be checked
  # - *access* is the minimal `Acl::Perm` required for a given operation
  # ```
  # guest = Acl::Group.new(name: "guest", default: Acl::Perm::None, permissions: {"/public" => Acl::Perm::Read})
  # guest.permitted "/public", Acl::Perm::Read  # => true
  # guest.permitted "/public", Acl::Perm::Write # => false
  # guest.permitted "/other", Acl::Perm::Read   # => false
  # ```
  def permitted?(path : String, access : Acl::Perm) : Bool
    matched_permissions = @permissions.select { |pe, _| pe.acl_match?(path) }
    if matched_permissions.empty?
      default.to_i >= access.to_i
    else
      # keep the longest path
      match = matched_permissions.reduce { |l, r| l[0] >= r[0] ? l : r }
      match[1].to_i >= access.to_i
    end
  end

  # Tries to match the *path* with the permissions of this group.
  # If select every matching path and get the maximum permission among them.
  def matching?(path : String) : Acl::Perm?
    founds = @permissions.select { |ppath, _| ppath.acl_match?(path) }
    return nil if founds.empty?
    found_min_size = founds.reduce { |left, right| left[0].size >= right[0].size ? left : right }
    found_min_size[1]
  end

  # Same as Path[String]? but returns the default value if not found
  def matching(path : String) : Acl::Perm
    acl = self.matching?(path)
    return @default if acl.nil?
    acl
  end

  # Tries to find the exact *path* with the permissions of this group.
  def []?(path : String) : Acl::Perm?
    found = @permissions.find { |ppath, _| ppath == path }
    found && found[1]
  end

  # Same as Path[String]? but returns the default value if not found
  def [](path : String) : Acl::Perm
    acl = self[path]?
    return @default if acl.nil?
    acl
  end

  # If a path exists, replace it with the given permission *acl*, else create it.
  def []=(path : String, acl : Acl::Perm)
    replace = @permissions.find { |ppath, _| ppath == path }
    if replace
      @permissions[replace[0]] = acl
    else
      @permissions[Acl::Path.new(path)] = acl
    end
  end

  # Remove the permissions associated to the path
  def delete(path : String)
    @permissions.reject! { |current_path, _| current_path.to_s == path }
    self
  end
end
