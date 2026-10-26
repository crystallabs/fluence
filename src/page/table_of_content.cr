class Fluence::Page < Fluence::File
  module TableOfContent
    alias TocLine = {Int32, String}
    alias Toc = Array(TocLine)

    # Builds the table of contents from markdown *content*, skipping
    # code (see `Page::Lines`).
    def self.toc(content : String) : Toc
      toc = Toc.new
      Page::Lines.each(content) do |line, code|
        next if code
        if toc_line = get_toc_line line.chomp
          toc << toc_line
        end
      end
      toc
    end

    # The page title a table of contents implies: its first level-1
    # heading, so a "# " line inside code never counts. Nil if none.
    def self.title(toc : Toc) : String?
      toc.find(&.[0].==(1)).try &.[1].strip.presence
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
