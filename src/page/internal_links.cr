require "uri"

class Fluence::Page < Fluence::File
  module InternalLinks
    # {offset-of-link-target, page-name}
    alias Link = {Int32, String}
    alias LinkList = Array(Link)

    # Inline markdown link whose target is captured: [text](target "title").
    # A preceding '!' is an image (media, not a page link).
    LINK = /(?<![\\!])\[(?:[^\[\]\\]|\\.)*\]\(\s*([^)\s]+)(?:\s+"[^"]*")?\s*\)/

    # Like `LINK`, but also matching images: ![alt](target "title").
    LINK_OR_IMAGE = /(?<!\\)\[(?:[^\[\]\\]|\\.)*\]\(\s*([^)\s]+)(?:\s+"[^"]*")?\s*\)/

    # Lists the internal page links found in markdown *content*.
    # *context_name* is the name of the page holding the content; relative
    # link targets resolve against its directory, like URLs in a browser.
    def self.links_in_content(content : String, context_name : String = "") : LinkList
      links = LinkList.new
      each_link(content, context_name) do |target_start, _target_end, name|
        links << {target_start, name}
      end
      links
    end

    # Rewrites links resolving to *old_name* to point at *new_url* instead,
    # preserving any #fragment. Returns the updated content.
    def self.rewrite_links(content : String, context_name : String, old_name : String, new_url : String) : String
      result = String::Builder.new content.bytesize
      pos = 0
      each_link(content, context_name) do |target_start, target_end, name|
        next unless name == old_name
        target = content[target_start...target_end]
        fragment = (i = target.index '#') ? target[i..] : ""
        result << content[pos...target_start] << new_url << fragment
        pos = target_end
      end
      return content if pos == 0
      result << content[pos..]
      result.to_s
    end

    # Rewrites link and image targets starting with *old_prefix* followed
    # by "/" (e.g. the URL of a page's attachments, "/media/old-name") to
    # start with *new_prefix* instead. Returns the updated content.
    def self.rewrite_prefix(content : String, old_prefix : String, new_prefix : String) : String
      result = String::Builder.new content.bytesize
      pos = 0
      each_target(content, LINK_OR_IMAGE) do |target_start, target_end, target|
        next unless target.starts_with? "#{old_prefix}/"
        result << content[pos...target_start] << new_prefix << target.lchop(old_prefix)
        pos = target_end
      end
      return content if pos == 0
      result << content[pos..]
      result.to_s
    end

    # Yields {target_start, target_end, page_name} for every link to a wiki
    # page, skipping fenced and indented code blocks.
    private def self.each_link(content : String, context_name : String, &)
      each_target(content, LINK) do |target_start, target_end, target|
        if name = resolve target, context_name
          yield target_start, target_end, name
        end
      end
    end

    # Yields {target_start, target_end, target} for every match of *pattern*
    # (whose first group is the target), skipping fenced and indented code blocks.
    private def self.each_target(content : String, pattern : Regex, &)
      offset = 0
      code_block = false
      content.each_line(chomp: false) do |line|
        if line.starts_with? "```"
          code_block = !code_block
        elsif !code_block && !line.starts_with?("    ")
          line.scan(pattern) do |match|
            yield offset + match.begin(1), offset + match.end(1), match[1]
          end
        end
        offset += line.size
      end
    end

    # Resolves a link *target* to a page name; nil when the target is not a
    # wiki page (external URL, media, pure anchor, escape from the pages tree).
    def self.resolve(target : String, context_name : String) : String?
      target = target.split('#', 2)[0].split('?', 2)[0]
      return if target.empty?
      return if target.starts_with?("//") || target.matches?(/\A[A-Za-z][A-Za-z0-9+.-]*:/)
      target = URI.decode target
      if target.starts_with? '/'
        prefix = "#{Fluence::OPTIONS.pages_prefix}/"
        return unless target.starts_with? prefix
        name = target.lchop prefix
      else
        dir = ::File.dirname context_name
        name = dir == "." ? target : "#{dir}/#{target}"
      end
      name = Path.posix(name).normalize.to_s
      return if name.in?(".", "..") || name.starts_with?("../") || name.starts_with?('/')
      name.strip("/").presence
    end
  end
end
