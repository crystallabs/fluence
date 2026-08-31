.container-fluid
  .row
    .col
      - if query.empty?
        h1 Search
        p Enter a search term in the box above.
      - else
        h1 = "Search results for '#{query}'"
        - if results.empty?
          p No matching pages found.
        - else
          ul.list-unstyled
            - results.each do |result|
              li.mb-1
                a href="#{result.url}" = result.title
                - if result.title != result.name
                  span.ms-2.text-body-secondary = result.name
