.container-fluid
  .row
    .col
      span Wiki Pages
      #pages-hierarchy
        == add_page pages

    .col-sm-8
      .row
        .col-12
          - if writable
            form#edit-page method="post"
              fieldset
                textarea.form-control name="body" = body
          - else
            #page-body
              == body_html
        .col-6
          span New Attachment
          - if writable
            form#upload action="#{Fluence::OPTIONS.media_prefix}/upload" method="post" enctype="multipart/form-data" data-pagename="#{page.name}" onsubmit="return Fluence.upload(this)"
              input.form-control.form-control-sm.my-1 type="file" name="file" multiple="multiple" required="required"
              button.btn.btn-sm.btn-primary type="submit" Upload
          - else
            p Insufficient permission to upload new attachments.
        .col-6
          span Attachments
            form#manage-attachments method="post"
              .list-group.list-group-flush id="attachments"
                - media.children1.each do |name, spec|
                  - m = spec[1].not_nil!
                  .row.border-bottom
                    .col-9
                      a.list-group-item href="#{m.url}" = m.title || m.name
                    .col-3
                      input.form-control type="hidden" name="media-name" value="#{m.title || m.name}"
                       - if writable
                        button.btn.btn-sm.btn-danger.my-1 name="delete" value="Delete" type="submit" formaction="#{Fluence::OPTIONS.media_prefix}/#{page.name}/#{m.title || m.name}" onclick="return Fluence.deleteAttachment(this, '#{m.title || m.name}')" Delete
    .col
      .row.g-0
        - if Fluence::ACL.permitted? current_user, page.url, Acl::Perm::Write
          #page-content.col-12
            span Page Content
            .row
              .col
                a.btn.btn-sm.w-100.btn-success href="#" onclick="Fluence.editor.togglePreview()" id="button_toggle" white-space="normal" Preview
              .col
                button.btn.btn-sm.w-100.btn-success name="save" id="button_save" type="submit" value="save" form="edit-page" Save
            input.form-control.form-control-sm.mt-2 type="text" name="summary" id="input-summary" form="edit-page" placeholder="Change summary (optional)" maxlength="500" autocomplete="off"
            hr
        - if page.exists?
          #page-history-link.col-12
            span History
            .small
              - if last_commit
                = "Last changed #{last_commit.time.to_s("%Y-%m-%d %H:%M")} by #{last_commit.author}."
              a.ms-1 href="#{page.url}?history" View history
            hr
          #page-toc.col-12
            span Table of Contents
            - if !page.toc.empty?
              == add_toc page.toc
            hr
          #page-intlinks.col-12
            span Internal Links
            ol
              - page.intlinks.each do |linkspec|
                - pg = Fluence::PAGES[linkspec[1]]? || Fluence::Page.new linkspec[1]
                li
                  a href="#{pg.url}" = pg.title || pg.name
            hr
          - if Fluence::ACL.permitted? current_user, page.url, Acl::Perm::Write
            #page-management.col-12
              span Page Management
                form#manage-page method="post"
                  .input-group
                    span.input-group-text id="label-page-name" Page name
                    input type="text" class="form-control" id="input-page-name" name="input-page-name" aria-describedby="label-page-name" value="#{page.name}"
                  .row.mt-2
                  .row
                    .col
                      .mb-3.form-check
                       input type="checkbox" class="form-check-input" id="input-page-subtree" name="input-page-subtree"
                       label class="form-check-label" for="input-page-subtree" With subpages
                    .col
                      .mb-3.form-check
                       input type="checkbox" class="form-check-input" id="input-page-intlinks" name="input-page-intlinks"
                       label class="form-check-label" for="input-page-intlinks" Update links
                    .col
                      .mb-3.form-check
                       input type="checkbox" class="form-check-input" id="input-page-overwrite" name="input-page-overwrite"
                       label class="form-check-label" for="input-page-overwrite" Overwrite
                    .col
                      button.btn.btn-sm.w-100.btn-warning name="rename" type="submit" value="rename" form="manage-page" Rename
                  .row
                    .col
                    .col
                      button.btn.btn-sm.w-100.btn-danger name="delete" type="submit" value="delete" form="manage-page" onclick="return confirm('Really delete page `#{page.name}`?')" Delete
              hr
            #page-permissions.col-12
              span Page Permissions
              .row
                .col-auto
                  | Read:
                .col
                  = groups_read.join ", "
                .w-100
                .col-auto
                  | Write:
                .col
                  = groups_write.join ", "
script
  - if writable
    = "var editor = new EasyMDE(Fluence.mde_options(true));"
    - if open_in_edit
      = "editor.codemirror.focus();"
    - else
      = "Fluence.editor.togglePreview();"
  - else
    = "hljs.highlightAll();"
