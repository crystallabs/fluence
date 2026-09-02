.container-fluid
  .row
    .col
      == render_template "pages/_page_menu.slang"

    .col-sm-10
      - heading = "Changes"
      == render_template "pages/_history_header.slang"
      .alert.alert-secondary#diff-info role="alert"
        | Revision
        code.mx-1 = commit.short_oid
        = "by #{commit.author} on #{commit.time.to_s("%Y-%m-%d %H:%M")}: #{commit.subject}"
        - unless commit.body.empty?
          .small.text-break.mt-1 style="white-space: pre-line" = commit.body
        .mt-2
          a.btn.btn-sm.btn-outline-secondary href="#{page.url}?rev=#{commit.oid}" View page at this revision
      - if diff.empty?
        p This revision did not change the page content.
      - else
        pre.diff
          == diff_html diff
