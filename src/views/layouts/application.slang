doctype html
html lang="en"
  head
    title = title
    meta charset="utf-8"
    meta http-equiv="X-UA-Compatible" content="IE=edge"
    meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no"

    link rel="stylesheet" href="/assets/stylesheet/bootstrap.min.css"
    script src="/assets/javascript/jquery-3.7.1.slim.min.js"
    script src="/assets/javascript/bootstrap.bundle.min.js"
    link rel="stylesheet" href="/assets/stylesheet/fontawesome.min.css"
    link rel="stylesheet" href="/assets/stylesheet/highlight.min.css"
    script src="/assets/javascript/highlight.min.js"
    link rel="stylesheet" href="/assets/stylesheet/easymde.min.css"
    script src="/assets/javascript/easymde.min.js"
    link rel="stylesheet" href="/assets/stylesheet/base.css"
    script src="/assets/javascript/base.js"
    link rel="stylesheet" href="/assets/stylesheet/fine-uploader-new.min.css"
    script src="/assets/javascript/fine-uploader.min.js"

  body
    #navbar
      == render_template "layouts/_nav.slang"

    #main.mt-3.mb-3
      - if !flash.empty?
        #main-flash
          .row
            - flash.each do |key, value|
              .col class="alert alert-#{key} alert-dismissible fade show" role="alert"
                = flash[key]
                button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"
              .w-100
      #main-content
        == content
