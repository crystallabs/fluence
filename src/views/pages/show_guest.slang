/ Minimal page view for guests (not signed in): page content and the
/ language switcher only. Navigation (home, sitemap, search, login/
/ register) comes from the shared layout/_nav.slang, which already hides
/ what a guest can't use.
.container-fluid
  .row
    - if !Fluence::OPTIONS.languages.empty?
      .col-md-3
        section#page-languages
          h6.section-title Language
          ul.list-unstyled.mb-0
            - default_class = page.lang.nil? ? "fw-bold" : ""
            li
              a class=default_class href="#{page.url}" = Fluence::OPTIONS.default_lang
            - Fluence::OPTIONS.languages.each do |code|
              - has_translation = page.translations.includes? code
              - current_class = page.lang == code ? "fw-bold" : ""
              li
                a class=current_class href="#{page.url}?lang=#{code}" = has_translation ? code : "#{code} (untranslated)"
    .col
      - if page.exists?
        #page-body
          == body_html
      - else
        .small.text-body-secondary This page does not exist yet.
script
  | hljs.highlightAll();
