.container-fluid
  .row
    .col
      - if query.empty?
        h1 Search
        p Enter a search term in the box above.
      - else
        h1 = "Search results for '#{query}'"
        - if results.empty? && media_results.empty?
          p No matching pages or attachments found.
        - unless results.empty?
          h6.section-title Pages
          ul.list-unstyled
            - results.each do |result|
              li.mb-1
                a href="#{result.url}" = result.title
                - if result.title != result.name
                  span.ms-2.text-body-secondary = result.name
        - unless media_results.empty?
          h6.section-title Attachments
          ul.list-unstyled
            - media_results.each do |result|
              li.mb-1
                a href="#{result.url}" = result.title
                - if page = owner_page result
                  span.ms-2.text-body-secondary
                    | on page
                    a.ms-1 href="#{page.url}" = page.name
