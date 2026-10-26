require "markd"

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

    # Builds the table of contents from markdown *content*: every heading
    # markd recognizes (ATX and setext, also inside lists and quotes, never
    # inside code), in document order, with the plain text its rendered id
    # is computed from (`Fluence::Markdown.plain_text`). So `anchors` of
    # the result are exactly the ids of the rendered headings.
    def self.toc(content : String) : Toc
      toc = Toc.new
      walker = Markd::Parser.parse(content, Fluence::Markdown::MARKD_OPTIONS).walker
      while event = walker.next
        node, entering = event
        next unless entering && node.type.heading?
        toc << {node.data["level"].as(Int32), Fluence::Markdown.plain_text(node)}
      end
      toc
    end

    # The page title a table of contents implies: its first level-1
    # heading, so a "# " line inside code never counts. Nil if none.
    def self.title(toc : Toc) : String?
      toc.find(&.[0].==(1)).try &.[1].strip.presence
    end
  end
end
