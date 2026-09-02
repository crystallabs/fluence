.container-fluid
  .row.g-0
    .container.col-md-8.col-lg-6
      h1 ACL Management
      h3 Create a new ACL
      form#acl-create method="post" action="#{Fluence::OPTIONS.admin_prefix}/acls/create"
        fieldset
          .mb-3.row
            label.col-3.col-form-label for="input_group_acl" Group
            .col-9
              input.form-control id="input_group_acl" name="group" type="text" required="required" placeholder="user"
              .form-text A group that does not exist yet is created.
          .mb-3.row
            label.col-3.col-form-label for="input_path_acl" Path pattern
            .col-9
              input.form-control id="input_path_acl" name="path" type="text" required="required" placeholder="#{Fluence::OPTIONS.pages_prefix}/*"
          .mb-3.row
            label.col-3.col-form-label for="input_permission_acl" Permission
            .col-9
              select.form-select id="input_permission_acl" name="perm"
                option value="none" None
                option value="read" Read
                option value="write" Write
          .mb-3.row
            .col-9.offset-3
              button.btn.btn-success name="create" type="submit" Create ACL
  .row.g-0.pt-3
    .container
      h3 Existing ACLs
      table.table.table-sm.table-hover.align-middle#acls
        thead
          tr
            th Group
            th Path pattern
            th Permission
            th.text-end Change to
        tbody
          - acls.groups.each do |_, group|
            - group.permissions.each do |path, perm|
              - badge_class = {"Write" => "text-bg-success", "Read" => "text-bg-info", "None" => "text-bg-warning"}[perm.to_s]? || "text-bg-secondary"
              tr
                td = group.name
                td
                  code = path.to_s
                td
                  span class="badge #{badge_class}" = perm.to_s
                td.text-end
                  form.d-inline method="post" action="#{Fluence::OPTIONS.admin_prefix}/acls/update"
                    input type="hidden" name="group" value=group.name
                    input type="hidden" name="path" value=path.to_s
                    .btn-group.btn-group-sm role="group" aria-label="Change permission"
                      button.btn.btn-outline-success type="submit" name="change" value="write" Write
                      button.btn.btn-outline-info type="submit" name="change" value="read" Read
                      button.btn.btn-outline-warning type="submit" name="change" value="none" None
                  form.d-inline.ms-2 method="post" action="#{Fluence::OPTIONS.admin_prefix}/acls/delete" onsubmit="return confirm('Really delete the ACL `#{group.name} :: #{path}`?')"
                    input type="hidden" name="group" value=group.name
                    input type="hidden" name="path" value=path.to_s
                    button.btn.btn-sm.btn-danger type="submit" name="change" value="delete" Delete
