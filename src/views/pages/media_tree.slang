ul.list-unstyled
  - nodes.each do |node|
    li
      - if node.page?
        a href="#{node.url}" = node.title
      - else
        span.text-body-secondary = node.title
      - if node.directory?
        == add_media node.children
