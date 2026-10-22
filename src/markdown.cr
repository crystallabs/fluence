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

    # HTML-escapes *text* for use as literal content (`&`/`<`/`>`).
    def self.escape(text : String) : String
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

  # Link to a page or attachment *user* can't read, with its text (title,
  # image alt text, or whatever markup it carried), replaced by
  # `Fluence::OPTIONS.inaccessible_label` — so a page linking to a hidden
  # one doesn't disclose its location or title. Markdown link text can't
  # itself contain a link, so `.*?</a>` always closes the same tag it
  # opened, never a nested one.
  HIDDEN_LINK = /<a href="([^"]*)"[^>]*>.*?<\/a>/m

  # An `![alt](src)` image markd rendered self-closed, whose `src` is what
  # would disclose an unreadable attachment's path (there's no link text
  # to drop, unlike `HIDDEN_LINK` — just the tag itself).
  HIDDEN_IMAGE = /<img src="([^"]*)"[^>]*\/>/

  # ```
  # Fluence::Markdown.to_html("**GFM** with [a link](/pages/home)", current_user, page.name)
  # ```
  # *user* is who the result is shown to, so links and images they can't
  # read get hidden (see `HIDDEN_LINK`, `HIDDEN_IMAGE`); omit it to skip
  # both passes entirely (there is no one to hide anything from).
  # *context_name* is the page the content belongs to, needed to resolve
  # relative link targets exactly like `Page::InternalLinks` does (a link
  # written as "sub/page" on page "a/b" targets "a/sub/page", not
  # "/pages/sub/page").
  def self.to_html(input : String, user : Fluence::User? = nil, context_name : String = "") : String
    return "" if input.empty?
    document = Markd::Parser.parse(input, MARKD_OPTIONS)
    html = Renderer.new(MARKD_OPTIONS).render(document, nil)
    return html unless user
    html = hide_inaccessible_images html, user
    hide_inaccessible_links html, user, context_name
  end

  private def self.hide_inaccessible_links(html : String, user : Fluence::User, context_name : String) : String
    html.gsub(HIDDEN_LINK) do |tag, match|
      href = match[1]
      path = if name = Fluence::Page::InternalLinks.resolve(href, context_name)
               "#{Fluence::OPTIONS.pages_prefix}/#{name}"
             elsif href.starts_with?("#{Fluence::OPTIONS.media_prefix}/")
               href.split(/[?#]/, 2).first
             end
      if path && !Fluence::ACL.permitted?(user, path, Acl::Perm::Read)
        %(<span class="text-body-secondary fst-italic">#{Sanitize.escape(Fluence::OPTIONS.inaccessible_label)}</span>)
      else
        tag
      end
    end
  end

  private def self.hide_inaccessible_images(html : String, user : Fluence::User) : String
    html.gsub(HIDDEN_IMAGE) do |tag, match|
      src = match[1]
      if src.starts_with?("#{Fluence::OPTIONS.media_prefix}/") && !Fluence::ACL.permitted?(user, src.split(/[?#]/, 2).first, Acl::Perm::Read)
        %(<span class="text-body-secondary fst-italic">#{Sanitize.escape(Fluence::OPTIONS.image_inaccessible_label)}</span>)
      else
        tag
      end
    end
  end
end
