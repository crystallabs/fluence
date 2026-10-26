module Fluence::Helpers::Page
  # A node of the tree of pages (page menu, sitemap) or of media (sitemap):
  # an entry, a directory level without an entry of its own, or both.
  class TreeNode
    getter name : String
    property title : String
    property? page : Bool
    getter children = [] of TreeNode

    def initialize(@name, @title, @page, @url_prefix : String = Fluence::OPTIONS.pages_prefix)
    end

    def directory? : Bool
      !@children.empty?
    end

    def url : String
      "#{@url_prefix}/#{@name}"
    end

    # Id of the collapsible element holding the children.
    def dom_id : String
      "tree-" + @name.gsub(/[^A-Za-z0-9]+/, "-")
    end
  end

  # Builds the tree of all pages from the catalog in one pass, siblings
  # ordered by name.
  def page_tree : Array(TreeNode)
    catalog_tree Fluence::PAGES, Fluence::OPTIONS.pages_prefix
  end

  # Likewise for all media.
  def media_tree : Array(TreeNode)
    catalog_tree Fluence::MEDIA, Fluence::OPTIONS.media_prefix
  end

  private def catalog_tree(catalog, url_prefix : String) : Array(TreeNode)
    roots = [] of TreeNode
    index = {} of String => TreeNode
    titles = catalog.titles
    titles.keys.sort!.each do |name|
      siblings = roots
      path = ""
      parts = name.split '/'
      parts.each_with_index do |part, i|
        path = i == 0 ? part : "#{path}/#{part}"
        node = index[path]? || begin
          new_node = TreeNode.new path, part, false, url_prefix
          index[path] = new_node
          siblings << new_node
          new_node
        end
        if i == parts.size - 1
          node.page = true
          node.title = titles[name]
        end
        siblings = node.children
      end
    end
    roots
  end

  # Pages of *nodes* in menu order (depth first).
  def flatten_tree(nodes : Array(TreeNode), into = [] of TreeNode) : Array(TreeNode)
    nodes.each do |node|
      into << node if node.page?
      flatten_tree node.children, into
    end
    into
  end

  # The previous page, parent page, and next page of *current* in menu
  # order; nil where there is none.
  def page_neighbours(tree : Array(TreeNode), current : String) : {TreeNode?, TreeNode?, TreeNode?}
    pages = flatten_tree tree
    i = pages.index &.name.==(current)
    prev_page = i && i > 0 ? pages[i - 1] : nil
    next_page = i && i < pages.size - 1 ? pages[i + 1] : nil
    parent = ::File.dirname current
    up_page = parent == "." ? nil : pages.find &.name.==(parent)
    {prev_page, up_page, next_page}
  end

  # Renders *nodes* as a collapsible tree. Branches containing *current*
  # start expanded; with *current* nil (the sitemap) every branch does.
  def add_page_tree(nodes : Array(TreeNode), current : String?)
    String.build do |str| # ameba:disable Lint/UnusedArgument
      Slang.embed("src/views/pages/page_tree.slang", "str")
    end
  end

  # Renders *nodes* (from `media_tree`) as a nested list.
  def add_media(nodes : Array(TreeNode))
    String.build do |str| # ameba:disable Lint/UnusedArgument
      Slang.embed("src/views/pages/media_tree.slang", "str")
    end
  end

  # One TOC entry linking to the heading's *anchor* (see
  # `Fluence::Page::TableOfContent::Anchors`). Heading text comes from
  # page content, so it is escaped.
  def create_toc_line(line, anchor : String, ends = true)
    "<li><a href=\"##{anchor}\">#{HTML.escape line}</a>#{ends ? "</li>" : nil}\n"
  end

  # *anchors* holds the id of each entry of *index_entry*.
  # TODO: move that
  def add_toc_level(b, index_entry, anchors : Array(String), current_id = 0, last_head = 0)
    return if index_entry.size == current_id
    current_entry = index_entry[current_id]
    current_head = current_entry[0]
    current_head_value = current_entry[1]
    next_entry = index_entry[current_id + 1]?
    next_head = next_entry ? next_entry[0] : 7
    close_li = next_head <= current_head
    if current_head > last_head
      b << "<ol>\n" << create_toc_line(current_head_value, anchors[current_id], close_li)
    elsif current_head < last_head
      b << "</ol></li>\n" << create_toc_line(current_head_value, anchors[current_id], close_li)
    else
      b << create_toc_line(current_head_value, anchors[current_id], close_li)
    end
    add_toc_level(b, index_entry, anchors, current_id + 1, current_head)
  end

  # Renders a unified diff as HTML lines classed by their role
  # (diff-add, diff-del, diff-hunk, diff-meta) for styling in base.css.
  def diff_html(diff : String) : String
    String.build do |b|
      diff.each_line do |line|
        css = case
              when line.starts_with?("+++"), line.starts_with?("---")      then "diff-meta"
              when line.starts_with?('+')                                  then "diff-add"
              when line.starts_with?('-')                                  then "diff-del"
              when line.starts_with?("@@")                                 then "diff-hunk"
              when line.starts_with?("diff "), line.starts_with?("index ") then "diff-meta"
              else                                                              ""
              end
        b << (css.empty? ? "<span>" : %(<span class="#{css}">))
        HTML.escape line, b
        b << "</span>\n"
      end
    end
  end

  def add_toc(index_entry)
    # (index_entry.values.map(&.size).sum + index_entry.size * 9)
    toc = String.build do |b|
      add_toc_level(b, index_entry, Fluence::Page::TableOfContent.anchors(index_entry))
    end
    String.build do |str| # ameba:disable Lint/UnusedArgument
      Slang.embed("src/views/pages/toc.slang", "str")
    end
  end
end
