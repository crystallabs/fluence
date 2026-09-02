.container-fluid
  .row
    .col
      h6.section-title Wiki Pages
      #pages-hierarchy
        == add_page_tree tree, nil
    .col-sm-10
      h1
        = "Pages titled '#{slug}'"
        small.text-body-secondary.ms-2 = "#{sections.size} pages"
      - if sections.empty?
        p No readable page has this title.
      - sections.each do |page, body_html|
        section.page-section.mb-4
          .small.text-body-secondary.border-bottom.pb-1
            | From page
            a.ms-1 href="#{page.url}" = page.name
          .page-body
            == body_html
script
  = "hljs.highlightAll();"
