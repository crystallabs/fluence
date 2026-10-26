module Fluence
  # The version from shard.yml, read at compile time so it is defined in
  # one place only.
  VERSION = {{ read_file("#{__DIR__}/../shard.yml").lines.find(&.starts_with?("version:")).split(":")[1].strip }}
end
