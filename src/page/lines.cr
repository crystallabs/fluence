class Fluence::Page < Fluence::File
  # Walks markdown content line by line, telling code from prose.
  module Lines
    # Yields every line of *content* (with its line terminator, so the
    # lines joined reproduce the content) and whether it is code: a line
    # inside a fenced (```) block, the fences themselves, and indented
    # code (four leading spaces). Markdown constructs are only recognized
    # in prose lines.
    def self.each(content : String, &)
      fenced = false
      content.each_line(chomp: false) do |line|
        if line.starts_with? "```"
          fenced = !fenced
          yield line, true
        else
          yield line, fenced || line.starts_with?("    ")
        end
      end
    end
  end
end
