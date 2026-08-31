.container-fluid
  .row-no-gutters
    .container.col-6
      h1 User Management
      h3 Create a new User
      form#register-new-user method="post" action="#{Fluence::OPTIONS.admin_prefix}/users/create"
        fieldset
          legend
            | Admin
          .mb-3.row
            label.col-2.col-form-label for="input_username" Username
            .col-10
              input.form-control id="input_username" name="username" type="text"
          .mb-3.row.pt-2
            label.col-2.col-form-label for="input_password" Password
            .col-10
              input.form-control id="input_password" name="password" type="password"
          .mb-3.row.pt-2
            label.col-2.col-form-label for="input_group" Groups
            .col-10
              input.form-control id="input_group" name="groups" type="text"
          .mb-3.row.pt-2
            input.form-control.btn.btn-md.btn-success name="register" type="submit" value="Register"
  .row-no-gutters.pt-3
    .container
        h3 Manage existing users
        .row
          .col-4
            span style="font-weight:bold" Users
          .col-4
            label style="font-weight:bold" Groups
          .col-4
            label style="font-weight:bold" Action
        hr
        - users.each do |user|
          .row
            .col-4
              span=user.name
            .col-4
              span=user.groups.join(", ")
            .col-4
              form method="post" action="#{Fluence::OPTIONS.admin_prefix}/users/delete"
                input type="hidden" name="username" value=user.name
                input.form-control.btn.btn-md.btn-danger name="delete" type="submit" value="Delete"
          hr
