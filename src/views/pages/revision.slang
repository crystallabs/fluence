.container-fluid
  .row
    .col
      == render_template "pages/_page_menu.slang"

    .col-sm-10
      - heading = page.title
      == render_template "pages/_history_header.slang"
      .alert.alert-warning#revision-info role="alert"
        | You are viewing the page as of revision
        code.mx-1 = commit.short_oid
        = "by #{commit.author} on #{commit.time.to_s("%Y-%m-%d %H:%M")}: #{commit.subject}"
        .mt-2
          a.btn.btn-sm.btn-outline-secondary href="#{page.url}?diff=#{commit.oid}" Show changes
          - if writable
            form.d-inline.ms-1 method="post" action="#{page.url}" onsubmit="return confirm('Replace the current content of `#{page.name}` with this revision?')"
              textarea.d-none name="body" = body
              input type="hidden" name="summary" value="Restore revision #{commit.short_oid}"
              button.btn.btn-sm.btn-warning type="submit" Restore this revision
      #page-body
        == body_html
script
  = "hljs.highlightAll();"
