require "yaml"

require "./perm"
require "./group"
require "./entity"

# The Groups is used to handle a set of uniq `Group`, by *name*.
class Acl::Groups < Lockable
  include YAML::Serializable

  property file : String
  property groups : Hash(String, Acl::Group)

  # ```
  # acls = Acl::Groups.new
  # g1 = Acl::Group.new(name: "user", default: Acl::Perm::Read, permissions: {"/tmp/protected" => Acl::Perm::None})
  # g2 = Acl::Group.new(name: "admin", default: Acl::Perm::Write)
  # acls.add g1
  # acls.add g2
  # ```
  def initialize(@file)
    @groups = {} of String => Acl::Group
  end

  def save!
    File.write(@file, to_yaml)
    self
  end

  # Read the file and erase the content, skip if the file does not exists
  def load!
    if File.exists?(@file) && (new_groups = Acl::Groups.read(@file) rescue nil)
      @groups = new_groups.groups
      # @file = groups.file
    else
      @groups = {} of String => Acl::Group
    end
    self
  end

  def self.read(file : String)
    Acl::Groups.from_yaml(File.read file)
  end

  # Check if an `Entity` has a group with the required permissions to operate.
  #
  # ```
  # acls = Groups.new ...
  # user = User.new ...
  # acls.permitted?(user, "/my/path", Perm::Read)
  # ```
  def permitted?(entity : Acl::Entity, path : String, access : Acl::Perm)
    entity.groups.any? do |group|
      @groups[group]? ? @groups[group].permitted?(path, access) : false
    end
  end

  # def if_permitted(entity : Acl::Entity, path : String, access : Acl::Perm)
  #   yield block if permitted? entity, path, access
  # end

  def add(group : String)
    @groups[group] = Group.new(group)
    self
  end

  def add(group : Acl::Group)
    @groups[group.name] = group
    group
  end

  def delete(group : String)
    @groups.delete group
    self
  end

  def delete(group : Acl::Group)
    @groups.delete group.name
    self
  end

  def [](group : String) : Acl::Group
    @groups[group]
  end

  def [](group : Acl::Group) : Acl::Group
    @groups[group.name]
  end

  def []?(group : String) : Acl::Group?
    @groups[group]?
  end

  def []?(group : Acl::Group) : Acl::Group?
    @groups[group.name]?
  end

  def group_exists?(group : String) : Bool
    @groups.keys.includes? group
  end

  def group_exists?(group : Acl::Group) : Bool
    group_exists? group.name
  end

  # List the groups having at least the permission *acl_min* on a path
  def groups_having_direct_access_to(path : String, acl_min : Acl::Perm, not_more : Bool = false) : Array(String)
    @groups.select do |_, group|
      current_acl = (group[path]? || Acl::Perm::None).to_i
      if not_more
        current_acl == acl_min.to_i
      else
        current_acl >= acl_min.to_i
      end
    end.keys
  end

  def groups_having_any_access_to(path : String, acl_min : Acl::Perm, not_more : Bool = false) : Array(String)
    @groups.select do |_, group|
      current_acl = (group.matching?(path) || Acl::Perm::None).to_i
      if not_more
        current_acl == acl_min.to_i
      else
        current_acl >= acl_min.to_i
      end
    end.keys
  end

  def add_permissions_to(path : String, groups : Array(String), acl : Acl::Perm)
    groups.each do |group|
      self.add group unless group_exists? group
      old_acl = self[group][path]?
      self[group][path] = acl if old_acl.nil? || old_acl.to_i < acl.to_i
    end
    self
  end

  def clear_permissions_of(path : String)
    self.clear_permissions_of(path, Acl::Perm::Read)
    self.clear_permissions_of(path, Acl::Perm::Write)
  end

  def clear_permissions_of(path : String, acl : Acl::Perm)
    @groups.each do |_, group|
      group.delete(path) if group[path]? == acl
    end
    self
  end
end
