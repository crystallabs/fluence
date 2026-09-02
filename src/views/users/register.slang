.container-fluid
  .row.g-0
    .container.col-md-6.col-lg-4
      h2.page-header Register
      form#register method="post"
        fieldset
          .mb-3.row
            label.col-4.col-form-label for="input_username" Username
            .col-8
              input.form-control id="input_username" name="username" type="text" required="required" autocomplete="username" autofocus="autofocus" pattern="[A-Za-z0-9 _.\-]+" title="Letters, digits, spaces, underscores, dots, and dashes"
          .mb-3.row
            label.col-4.col-form-label for="input_password" Password
            .col-8
              input.form-control id="input_password" name="password" type="password" required="required" autocomplete="new-password"
          .mb-3.pt-2
            button.btn.btn-success.w-100 name="register" type="submit" Register
      p.text-body-secondary
        | Already have an account?
        a.ms-1 href="#{Fluence::OPTIONS.users_prefix}/login" Login
