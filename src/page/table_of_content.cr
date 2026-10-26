class Fluence::Page < Fluence::File
  module TableOfContent
    alias TocLine = {Int32, String}
    alias Toc = Array(TocLine)

    # Hands out heading ids for one document, in document order: the
    # heading text made URL-safe (`Page.sanitize`), deduplicated
    # GitHub-style ("notes", "notes-1", "notes-2"). Both the rendered
    # headings (`Fluence::Markdown::Renderer`) and the TOC links use it,
    # so each link lands on its own section.
    class Anchors
      @used = Set(String).new
      @counts = Hash(String, Int32).new(0)

      # The id for the next heading, whose text is *text*.
      def next(text : String) : String
        base = Page.sanitize text
        loop do
          n = @counts[base]
          @counts[base] = n + 1
          id = n == 0 ? base : "#{base}-#{n}"
          return id if @used.add? id
        end
      end
    end

    # The ids of the headings in *toc*, in order (see `Anchors`).
    def self.anchors(toc : Toc) : Array(String)
      anchors = Anchors.new
      toc.map { |_, text| anchors.next text }
    end

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
