require "markd"
require "./page"

# Renders page content — GitHub Flavored Markdown — to HTML via markd.
# Internal links are plain markdown links ([title](/pages/name) or a
# relative target), so no preprocessing pass is needed; see
# `Page::InternalLinks` for how they are recognized and tracked.
#
# Rendering is `safe`: link/image targets with script-capable schemes
# (javascript:, vbscript:, data: other than images) are dropped, and raw
# HTML in the content goes through `Sanitize` (only `Sanitize::ALLOWED_TAGS`,
# each with a plain class="..." at most, survive; everything else is
# escaped to literal text). Anyone allowed to edit a page would otherwise
# be able to run script in every reader's browser.
struct Fluence::Markdown
  MARKD_OPTIONS = Markd::Options.new(gfm: true, autolink: true, tagfilter: true, emoji: true, safe: true)

  # Allowlist sanitizer for the raw HTML markd's `html_block`/`html_inline`
  # nodes carry verbatim (`safe: true` would otherwise drop it entirely).
  # Lets page content use icon fonts (`<i class="fas fa-running">`), lay
  # out custom structure (headings, lists, article/div sections), and
  # apply theme CSS classes to any of it, without opening the door to
  # `<script>`, event-handler attributes, or any other tag.
  module Sanitize
    ALLOWED_TAGS = %w[i span h1 h2 h3 h4 h5 ol ul li article div]
    TAG = /<\/?[a-zA-Z][^<>]*>/
    SAFE_TAG = /\A<(\/?)(#{ALLOWED_TAGS.join('|')})(?:\s+class="[A-Za-z0-9_ -]*")?\s*>\z/i

    # *html* with every tag not matching `SAFE_TAG` escaped to literal text.
    def self.call(html : String) : String
      html.gsub(TAG) { |tag| tag.matches?(SAFE_TAG) ? tag : escape(tag) }
    end

    private def self.escape(text : String) : String
      text.gsub('&', "&amp;").gsub('<', "&lt;").gsub('>', "&gt;")
    end
  end

  # HTMLRenderer whose headings carry an id matching the anchors the
  # table-of-contents helper generates (`Fluence::Page.sanitize` of the
  # heading text), so TOC links actually land on their sections; and
  # whose raw-HTML nodes are sanitized (see `Sanitize`) rather than
  # dropped outright.
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

    def html_block(node : Markd::Node, entering : Bool) : Nil
      newline
      literal(Sanitize.call(node.text))
      newline
    end

    def html_inline(node : Markd::Node, entering : Bool) : Nil
      literal(Sanitize.call(node.text))
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
