doctype html
- theme = current_user.settings.theme
- theme_attr = theme == "auto" ? nil : theme
html lang="en" data-bs-theme=theme_attr
  head
    title = title
    - if theme == "auto"
      script
        | document.documentElement.setAttribute("data-bs-theme", matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    meta charset="utf-8"
    meta http-equiv="X-UA-Compatible" content="IE=edge"
    meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no"

    link rel="stylesheet" href="/assets/stylesheet/bootstrap.min.css"
    script src="/assets/javascript/bootstrap.bundle.min.js"
    link rel="stylesheet" href="/assets/stylesheet/fontawesome.min.css"
    link rel="stylesheet" href="/assets/stylesheet/highlight.min.css"
    script src="/assets/javascript/highlight.min.js"
    link rel="stylesheet" href="/assets/stylesheet/easymde.min.css"
    script src="/assets/javascript/easymde.min.js"
    link rel="stylesheet" href="/assets/stylesheet/base.css"
    script src="/assets/javascript/base.js"
    script == "Fluence.settings = #{current_user.settings.to_json};"

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
