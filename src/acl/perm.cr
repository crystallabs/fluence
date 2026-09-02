require "yaml"

# Permission levels of the Acl system
enum Acl::Perm
  # level 0. Cannot read, cannot write.
  None = 0

  # level 1. Can read, cannot write.
  Read = 1

  # level 3. Can read, can write.
  Write = 3

  # Accepts the YAML value either as a number or as a member name.
  def self.new(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : self
    unless node.is_a?(YAML::Nodes::Scalar)
      node.raise "Expected scalar, not #{node.kind}"
    end
    if number = node.value.to_i64?
      from_value(number)
    else
      parse(node.value)
    end
  end
end
