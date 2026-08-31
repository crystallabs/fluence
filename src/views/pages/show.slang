- writable = Fluence::ACL.permitted? current_user, page.url, Acl::Perm::Write
- if writable
  script type="text/template" id="qq-template"
          div class="qq-uploader-selector qq-uploader" qq-drop-area-text="Drop files here"
              div class="qq-total-progress-bar-container-selector qq-total-progress-bar-container"
                  div role="progressbar" aria-valuenow="0" aria-valuemin="0" aria-valuemax="100" class="qq-total-progress-bar-selector qq-progress-bar qq-total-progress-bar"
              div class="qq-upload-drop-area-selector qq-upload-drop-area" qq-hide-dropzone=""
                  span class="qq-upload-drop-area-text-selector"
              div class="buttons"
                  div class="qq-upload-button-selector btn btn-primary"
                      div Select files
                  button type="button" id="trigger-upload" class="btn btn-primary"
                      i class="icon-upload icon-white"
                      | Upload
              span class="qq-drop-processing-selector qq-drop-processing"
                  span Processing dropped files...
                  span class="qq-drop-processing-spinner-selector qq-drop-processing-spinner"
              ul class="qq-upload-list-selector qq-upload-list" aria-live="polite" aria-relevant="additions removals"
                  li
                      div class="qq-progress-bar-container-selector"
                          div role="progressbar" aria-valuenow="0" aria-valuemin="0" aria-valuemax="100" class="qq-progress-bar-selector qq-progress-bar"
                      span class="qq-upload-spinner-selector qq-upload-spinner"
                      img class="qq-thumbnail-selector" qq-max-size="100" qq-server-scale=""
                      span class="qq-upload-file-selector qq-upload-file"
                      span class="qq-edit-filename-icon-selector qq-edit-filename-icon" aria-label="Edit filename"
                      input class="qq-edit-filename-selector qq-edit-filename" tabindex="0" type="text"
                      span class="qq-upload-size-selector qq-upload-size"
                      button type="button" class="qq-btn qq-upload-cancel-selector qq-upload-cancel" Cancel
                      button type="button" class="qq-btn qq-upload-retry-selector qq-upload-retry" Retry
                      button type="button" class="qq-btn qq-upload-delete-selector qq-upload-delete" Delete
                      span role="status" class="qq-upload-status-text-selector qq-upload-status-text"

              dialog class="qq-alert-dialog-selector"
                  div class="qq-dialog-message-selector"
                  div class="qq-dialog-buttons"
                      button type="button" class="qq-cancel-button-selector" Close

              dialog class="qq-confirm-dialog-selector"
                  div class="qq-dialog-message-selector"
                  div class="qq-dialog-buttons"
                      button type="button" class="qq-cancel-button-selector" No
                      button type="button" class="qq-ok-button-selector" Yes

              dialog class="qq-prompt-dialog-selector"
                  div class="qq-dialog-message-selector"
                  input type="text"
                  div class="qq-dialog-buttons"
                      button type="button" class="qq-cancel-button-selector" Cancel
                      button type="button" class="qq-ok-button-selector" Ok
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
              div id="uploader"
              javascript:
                var uploader = new qq.FineUploader({
                    element: document.getElementById("uploader"),
                    request: {
                        endpoint: '#{Fluence::OPTIONS.media_prefix}/upload',
                        params: {
                            qqpagename: '#{page.name}'
                        }
                    },
                    debug: true,
                    deleteFile: {
                        enabled: true,
                        endpoint: 'Fluence::OPTIONS.media_prefix/upload',
                        params: {
                            qqpagename: '#{page.name}'
                        }
                    },
                    thumbnails: {
                        placeholders: {
                            waitingPath: '/assets/stylesheet/waiting-generic.png',
                            notAvailablePath: '/assets/stylesheet/not_available-generic.png'
                        }
                    },
                    autoUpload: false,
                    callbacks: {
                      onComplete: function(id, name, responseJSON){
                        /*TODO:
                          - 2 files with same name
                          - paused files (this callback will return nothing if ALL files are not successfully uploaded, paused file will block it)
                          - add if statements for succeeded array */
                        var hook = '#{Fluence::OPTIONS.media_prefix}/#{page.name}/'
                        var tag = new String()
                        if (responseJSON.success){
                          tag = new String(
                          `<div class='row border-bottom'>
                            <div class='col-9'>
                              <a class='list-group-item' href='${hook + name}'>  ${name}  </a>
                            </div>
                              <div class='col-3'>
                                <input class='form-control' name='media-name' value='${name}' type='hidden'>
                                <button class='btn btn-sm btn-danger my-1' name='delete' value='Delete'   type='submit' formaction=${hook+name} onclick=\"return confirm('Really delete attachment ${name}?')\">
                                  Delete
                                </button>
                              </div>
                          </div>`)
                      }
                        else {
                          tag = new String(
                          `<div class='row border-bottom'  data-bs-toggle='tooltip' data-bs-placement='top' title='${responseJSON.error}'>
                            <div class='col-9'>
                              <a class='list-group-item' href='#'>  ${name}  </a>
                            </div>
                              <div class='col-3'>
                                <p class='text-danger'>FAILED</p>
                              </div>
                          </div>`)
                        }
                        $('#attachments').append(tag);
                      },
                      onError: function(id,name,reason){
                        console.log(reason);
                      },
                      onAllComplete: function(){
                        this.clearStoredFiles();
                      }
                    }
                });
                qq(document.getElementById("trigger-upload")).attach("click", function() {
                    uploader.uploadStoredFiles();
                });
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
                        button.btn.btn-sm.btn-danger.my-1 name="delete" value="Delete" type="submit" formaction="#{Fluence::OPTIONS.media_prefix}/#{page.name}/#{m.title || m.name}" onclick="return confirm('Really delete attachment `#{m.title || m.name}`?')" Delete
    .col
      .row.g-0
        - if Fluence::ACL.permitted? current_user, page.url, Acl::Perm::Write
          #page-content.col-12
            span Page Content
            .row
              .col
                a.btn.btn-sm.w-100.btn-success href="#" onclick="Fluence.editor.togglePreview()" id="button_toggle" white-space="normal" Preview
              .col
                button.btn.btn-sm.w-100.btn-success name="save" id="button_save" type="submit" value="save" form="edit-page" visibility="hidden" Save
            hr
        - if page.exists?
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
    - if (!page.exists? && Fluence::OPTIONS.open_new_in_edit) || (page.exists? && (page.size==0) && Fluence::OPTIONS.open_empty_in_edit) || Fluence::OPTIONS.open_in_edit
      = "editor.codemirror.focus();"
    - else
      = "Fluence.editor.togglePreview();"
  - else
    = "hljs.highlightAll();"
