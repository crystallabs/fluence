class Fluence::Page < Fluence::File
  module TableOfContent
    alias TocLine = {Int32, String}
    alias Toc = Array(TocLine)

    # Builds the table of contents from markdown *content*, skipping
    # fenced code blocks.
    def self.toc(content : String) : Toc
      toc = Toc.new
      code_block = false

      content.each_line do |line|
        if line =~ /^```/
          code_block = !code_block
        end

        next if code_block

        toc_line = get_toc_line line
        toc << toc_line.as(TocLine) unless toc_line.nil?
      end
      toc
    end

    # Parse a markdown line, and return a TocLine if it is a title
    def self.get_toc_line(line : String) : TocLine?
      if match = line.match /^(\#{1,6})\s(.+)/
        title_num = match[1].size
        title = match[2]
        {title_num, title}
      end
    end
  end
end
