.container-fluid
  .row.g-0
    .container.col-md-6.col-lg-4
      h2.page-header Settings
      p.text-body-secondary = "Preferences of user '#{current_user.name}'. They apply in every browser you log in from."
      form#settings method="post"
        fieldset
          .mb-3.row
            label.col-5.col-form-label for="input_editor_mode" Open pages in
            .col-7
              select.form-select id="input_editor_mode" name="editor_mode"
                - {"default" => "Site default", "edit" => "Edit mode", "view" => "View mode"}.each do |value, label|
                  - chosen = settings.editor_mode == value
                  option value=value selected=chosen = label
          .mb-3.row
            .col-5.col-form-label Editor layout
            .col-7
              .form-check
                input.form-check-input type="checkbox" id="input_side_by_side" name="side_by_side" checked=settings.side_by_side?
                label.form-check-label for="input_side_by_side" Side-by-side preview
              .form-check
                input.form-check-input type="checkbox" id="input_fullscreen" name="fullscreen" checked=settings.fullscreen?
                label.form-check-label for="input_fullscreen" Fullscreen
          .mb-3.row
            label.col-5.col-form-label for="input_autosave_delay" Draft autosave delay
            .col-7
              .input-group
                input.form-control type="number" id="input_autosave_delay" name="autosave_delay" min="0" max="600" value=settings.autosave_delay
                span.input-group-text seconds
              .form-text 0 disables drafts.
          .mb-3.row
            label.col-5.col-form-label for="input_theme" Color scheme
            .col-7
              select.form-select id="input_theme" name="theme"
                - {"auto" => "Follow the browser", "light" => "Light", "dark" => "Dark"}.each do |value, label|
                  - chosen = settings.theme == value
                  option value=value selected=chosen = label
          .mb-3.pt-2
            input.form-control.btn.btn-md.btn-success name="save" type="submit" value="Save"
