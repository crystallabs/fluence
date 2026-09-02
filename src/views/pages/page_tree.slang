ul.list-unstyled.page-tree
  - nodes.each do |node|
    - active = node.name == current
    - open = current.nil? || active || current.starts_with?(node.name + "/")
    - link_class = active ? "tree-link active" : "tree-link"
    - link_class += " text-body-secondary" unless node.page?
    li
      .d-flex.align-items-baseline
        - if node.directory?
          - toggle_class = open ? "tree-toggle" : "tree-toggle collapsed"
          a class=toggle_class href="##{node.dom_id}" data-bs-toggle="collapse" role="button" aria-expanded="#{open}" aria-controls="#{node.dom_id}" aria-label="Toggle #{node.title}"
        - else
          span.tree-toggle.tree-leaf
        a class=link_class href="#{node.url}" = node.title
      - if node.directory?
        - children_class = open ? "collapse show" : "collapse"
        div id=node.dom_id class=children_class
          == add_page_tree node.children, current
