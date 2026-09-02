.container-fluid
  .row
    .col
      == render_template "pages/_page_menu.slang"

    .col-sm-8
      .row
        .col-12
          - if writable
            form#edit-page.invisible method="post"
              fieldset
                textarea.form-control name="body" = body
          - else
            #page-body
              == body_html
        .col-6
          h6.section-title.mt-3 New Attachment
          - if writable
            form#upload action="#{Fluence::OPTIONS.media_prefix}/upload" method="post" enctype="multipart/form-data" data-pagename="#{page.name}" onsubmit="return Fluence.upload(this)"
              input.form-control.form-control-sm.my-1 type="file" name="file" multiple="multiple" required="required"
              button.btn.btn-sm.btn-primary type="submit" Upload
          - else
            p.small.text-body-secondary Insufficient permission to upload new attachments.
        .col-6
          h6.section-title.mt-3 Attachments
          form#manage-attachments method="post"
            #attachments.list-group.list-group-flush
              - media.children1.each do |name, spec|
                - m = spec[1].not_nil!
                .row.border-bottom
                  .col-9
                    a.list-group-item href="#{m.url}" = m.title || m.name
                  .col-3
                    input type="hidden" name="media-name" value="#{m.title || m.name}"
                    - if writable
                      button.btn.btn-sm.btn-danger.my-1 name="delete" value="Delete" type="submit" formaction="#{Fluence::OPTIONS.media_prefix}/#{page.name}/#{m.title || m.name}" onclick="return Fluence.deleteAttachment(this, '#{m.title || m.name}')" Delete
    #sidebar.col
      - if writable
        section#page-content
          h6.section-title Page Content
          .d-flex.gap-2
            button.btn.btn-sm.btn-outline-success.flex-fill type="button" id="button_toggle" onclick="Fluence.editor.togglePreview()" Preview
            button.btn.btn-sm.btn-success.flex-fill name="save" id="button_save" type="submit" value="save" form="edit-page" Save
          input.form-control.form-control-sm.mt-2 type="text" name="summary" id="input-summary" form="edit-page" placeholder="Change summary (optional)" maxlength="500" autocomplete="off"
      - if page.exists?
        section#page-history-link
          h6.section-title History
          .small
            - if last_commit
              = "Last changed #{last_commit.time.to_s("%Y-%m-%d %H:%M")} by #{last_commit.author}."
            a.ms-1 href="#{page.url}?history" View history
        section#page-toc
          h6.section-title Table of Contents
          - if page.toc.empty?
            .small.text-body-secondary No headings.
          - else
            == add_toc page.toc
        section#page-intlinks
          h6.section-title Internal Links
          - if page.intlinks.empty?
            .small.text-body-secondary None.
          - else
            ol
              - page.intlinks.each do |linkspec|
                - pg = Fluence::PAGES[linkspec[1]]? || Fluence::Page.new linkspec[1]
                li
                  a href="#{pg.url}" = pg.title || pg.name
        - if writable
          section#page-management
            h6.section-title
              a.section-toggle.collapsed data-bs-toggle="collapse" href="#page-management-body" role="button" aria-expanded="false" aria-controls="page-management-body" Page Management
            #page-management-body.collapse
              form#manage-page method="post"
                .input-group.input-group-sm
                  span.input-group-text id="label-page-name" Page name
                  input.form-control type="text" id="input-page-name" name="input-page-name" aria-describedby="label-page-name" value="#{page.name}"
                .form-check.mt-2
                  input.form-check-input type="checkbox" id="input-page-subtree" name="input-page-subtree"
                  label.form-check-label for="input-page-subtree" With subpages
                .form-check
                  input.form-check-input type="checkbox" id="input-page-intlinks" name="input-page-intlinks"
                  label.form-check-label for="input-page-intlinks" Update links in other pages
                .form-check
                  input.form-check-input type="checkbox" id="input-page-overwrite" name="input-page-overwrite"
                  label.form-check-label for="input-page-overwrite" Overwrite existing page
                .d-flex.gap-2.mt-2
                  button.btn.btn-sm.btn-warning.flex-fill name="rename" type="submit" value="rename" Rename
                  button.btn.btn-sm.btn-danger.flex-fill name="delete" type="submit" value="delete" onclick="return confirm('Really delete page `#{page.name}`?')" Delete
        section#page-permissions
          h6.section-title Page Permissions
          table.table.table-sm.small.mb-0
            tr
              th.fw-normal.text-body-secondary Read
              td = groups_read.join ", "
            tr
              th.fw-normal.text-body-secondary Write
              td = groups_write.join ", "
script
  - if writable
    = "Fluence.editor.init(#{open_in_edit});"
  - else
    = "hljs.highlightAll();"
