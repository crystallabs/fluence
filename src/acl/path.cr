require "yaml"

class Acl::Path
  include YAML::Serializable

  getter value : String

  @[YAML::Field(ignore: true)]
  getter regex : Regex?

  def self.value_to_regex(value : String)
    value_regex = value.gsub "*", ".*"
    Regex.new "^#{value_regex}$"
  end

  def initialize(@value : String)
    @regex = Acl::Path.value_to_regex @value
  end

  def acl_match?(other_path : String) : Bool
    @regex ||= Acl::Path.value_to_regex @value
    !!@regex.as(Regex).match other_path
  end

  def to_s
    @value
  end

  def size
    # +3 = ".md".size
    @value.includes?("*") ? @value.size : @value.size + 3
  end

  def ==(rhs)
    self.to_s == rhs.to_s
  end

  {% for op in [">", "<", ">=", "<="] %}
  def {{op.id}}(rhs : Path)
    self.size {{op.id}} rhs.size
  end
  {% end %}
end
