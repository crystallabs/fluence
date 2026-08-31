.container-fluid
  .row.g-0
    .container.col-3
      h2.page-header Login
      form#register method="post"
        fieldset
          .mb-3.row
            label.col-4.col-form-label for="input_username" Username
            .col-8
              input.form-control id="input_username" name="username" type="text"
          .mb-3.row.pt-2
            label.col-4.col-form-label for="input_password" Password
            .col-8
              input.form-control id="input_password" name="password" type="password"
          .mb-3.pt-2
            input.form-control.btn.btn-md.btn-success name="login" type="submit" value="Login"