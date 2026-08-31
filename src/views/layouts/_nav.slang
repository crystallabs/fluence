/ - active = context.request.path == "/" ? "active" : ""
/ a class="nav-item #{active}" href="/" Home
nav.navbar.navbar-expand-lg.bg-body-tertiary
    a class="navbar-brand" href="#{Fluence::OPTIONS.homepage}"
      img.d-inline-block.align-top src="#{Fluence::OPTIONS.brand_logo}" alt="#{Fluence::OPTIONS.brand_info}"
      = Fluence::OPTIONS.brand
    button.navbar-toggler type="button" data-bs-toggle="collapse" data-bs-target="#navbarSupportedContent" aria-controls="navbarSupportedContent" aria-expanded="false" aria-label="Toggle navigation"
      span.navbar-toggler-icon

    #navbarSupportedContent.collapse.navbar-collapse
      ul.navbar-nav.me-auto
        li.nav-item.active
          a.nav-link href="#{Fluence::OPTIONS.homepage}" Home
            span.visually-hidden (current)
        li.nav-item.active
          a.nav-link href="/sitemap" Sitemap
        - if Fluence::ACL.permitted?(current_user, "#{Fluence::OPTIONS.admin_prefix}/users", Acl::Perm::Read)
          li.nav-item.active
            a.nav-link href="#{Fluence::OPTIONS.admin_prefix}/users" Users
        - if Fluence::ACL.permitted?(current_user, "#{Fluence::OPTIONS.admin_prefix}/acls", Acl::Perm::Read)
          li.nav-item.active
            a.nav-link href="#{Fluence::OPTIONS.admin_prefix}/acls" ACLs
      form#search-page.my-2.d-inline.w-50 action="#{Fluence::OPTIONS.pages_prefix}/search" method="get"
        .input-group
          input.form-control.me-sm-2 name="q" type="search" placeholder="Search" aria-label="Search" autocomplete="on"
          /      datalist#search-list
          /        - Fluence::PAGES.entries.values.each do |entry|
          /          option value=entry.url = entry.title
          button.btn.btn-outline-success.my-2.my-sm-0 type="submit" Search
      ul.navbar-nav.mx-auto
        - if user_signed_in?
          li.navbar-text
            span | Logged in as
              = current_user.name
          li.nav-item.active
            a.nav-link href="#{Fluence::OPTIONS.users_prefix}/logout" (Logout)
        - else
          li.nav-item.active
            a.nav-link href="#{Fluence::OPTIONS.users_prefix}/login" | Login
            li.navbar-text or
            a.nav-link.active href="#{Fluence::OPTIONS.users_prefix}/register" Register