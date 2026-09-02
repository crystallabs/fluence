.container-fluid
  .row
    .col
      == render_template "pages/_page_menu.slang"

    .col-sm-10
      - heading = "History"
      == render_template "pages/_history_header.slang"
      - if commits.empty?
        p This page has no recorded history.
      - else
        table.table.table-sm.table-hover#page-history
          thead
            tr
              th Date
              th Author
              th Change
              th
          tbody
            - commits.each do |commit|
              tr
                td.text-nowrap
                  time datetime="#{commit.time.to_rfc3339}" = commit.time.to_s("%Y-%m-%d %H:%M")
                td = commit.author
                td
                  = commit.subject
                  - unless commit.body.empty?
                    .small.text-body-secondary.text-break style="white-space: pre-line" = commit.body
                td.text-nowrap.text-end
                  code.me-2 = commit.short_oid
                  a.btn.btn-sm.btn-outline-primary href="#{page.url}?rev=#{commit.oid}" View
                  a.btn.btn-sm.btn-outline-secondary.ms-1 href="#{page.url}?diff=#{commit.oid}" Changes
        - if truncated
          p.text-body-secondary
            = "Showing the latest #{commits.size} changes. "
            a href="#{page.url}?history&all" Show all
