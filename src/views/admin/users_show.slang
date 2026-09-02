.container-fluid
  .row.g-0
    .container.col-md-8.col-lg-6
      h1 User Management
      h3 Create a new user
      form#register-new-user method="post" action="#{Fluence::OPTIONS.admin_prefix}/users/create"
        fieldset
          .mb-3.row
            label.col-3.col-form-label for="input_username" Username
            .col-9
              input.form-control id="input_username" name="username" type="text" required="required" autocomplete="off"
          .mb-3.row
            label.col-3.col-form-label for="input_password" Password
            .col-9
              input.form-control id="input_password" name="password" type="password" required="required" autocomplete="new-password"
          .mb-3.row
            label.col-3.col-form-label for="input_group" Groups
            .col-9
              input.form-control id="input_group" name="groups" type="text" value="user" placeholder="user, admin"
              .form-text Comma-separated list of groups the user belongs to.
          .mb-3.row
            .col-9.offset-3
              button.btn.btn-success name="register" type="submit" Create user
  .row.g-0.pt-3
    .container
      h3 Existing users
      table.table.table-sm.table-hover.align-middle#users
        thead
          tr
            th Username
            th Groups
            th.text-end Action
        tbody
          - users.each do |user|
            tr
              td = user.name
              td = user.groups.join(", ")
              td.text-end
                form.d-inline method="post" action="#{Fluence::OPTIONS.admin_prefix}/users/delete" onsubmit="return confirm('Really delete user `#{user.name}`?')"
                  input type="hidden" name="username" value=user.name
                  button.btn.btn-sm.btn-danger name="delete" type="submit" Delete
