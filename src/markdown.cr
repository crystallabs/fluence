require "markd"
require "./page"

# Renders page content — GitHub Flavored Markdown — to HTML via markd.
# Internal links are plain markdown links ([title](/pages/name) or a
# relative target), so no preprocessing pass is needed; see
# `Page::InternalLinks` for how they are recognized and tracked.
struct Fluence::Markdown
  MARKD_OPTIONS = Markd::Options.new(gfm: true, autolink: true, tagfilter: true, emoji: true)

  # HTMLRenderer whose headings carry an id matching the anchors the
  # table-of-contents helper generates (`Fluence::Page.sanitize` of the
  # heading text), so TOC links actually land on their sections.
  class Renderer < Markd::HTMLRenderer
    def heading(node : Markd::Node, entering : Bool) : Nil
      tag_name = HEADINGS[node.data["level"].as(Int32) - 1]
      if entering
        newline
        tag(tag_name, {"id" => Fluence::Page.sanitize(plain_text(node))})
      else
        tag(tag_name, end_tag: true)
        newline
      end
    end

    private def plain_text(node : Markd::Node) : String
      String.build do |io|
        walker = node.walker
        while event = walker.next
          child, entering = event
          io << child.text if entering
        end
      end
    end
  end

  # ```
  # Fluence::Markdown.to_html("**GFM** with [a link](/pages/home)")
  # ```
  def self.to_html(input : String) : String
    return "" if input.empty?
    document = Markd::Parser.parse(input, MARKD_OPTIONS)
    Renderer.new(MARKD_OPTIONS).render(document, nil)
  end
end
