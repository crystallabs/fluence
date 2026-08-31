class Fluence::Page < Fluence::File
  module InternalLinks
    # {id, page-real-url}
    alias Link = {Int32, String}
    alias LinkList = Array(Link)

    # Lists the [[internal links]] found in markdown *content*.
    def self.links_in_content(content : String)
      links = LinkList.new
      link_begin = -1
      while link_begin = content.index("[[", link_begin + 1)
        link_end = content.index "]]", link_begin
        next if link_end.nil?
        end_of_line = content.index '\n', link_begin
        next if end_of_line && end_of_line < link_end
        links << {link_begin + 2, content[link_begin + 2..link_end - 1]}
      end
      links
    end
  end
end
