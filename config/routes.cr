# No need to change defaults.

class Router
  {% for verb in {:get, :post, :delete, :patch, :put, :head} %}
    macro {{verb.id}}(route, controller, method)
      ::{{verb.id}}(\{{route}}) do |env|
        context = \{{controller}}.new(env)
        # puts "Before init"
        # pp env.request.cookies
        # pp env.response.cookies
        context.cookies.fill_from_client_headers(env.request.headers)
        # puts "After init"
        # pp env.request.cookies
        # pp env.response.cookies
        output = context.\{{method.id}}()
        # puts "After controller"
        # pp env.request.cookies
        # pp env.response.cookies
        #context.cookies.add_response_headers(env.response.headers)
        output
      end
    end
  {% end %}
end

# This will issue a redirect to the page configured as homepage.
Router.get "/", HomeController, :index

Router.get "/sitemap", PagesController, :sitemap
# Router.get "#{Fluence::OPTIONS.media_prefix}map", MediaController, :sitemap

Router.get "#{Fluence::OPTIONS.pages_prefix}/search", PagesController, :search

Router.get "#{Fluence::OPTIONS.pages_prefix}/*path", PagesController, :show
Router.post "#{Fluence::OPTIONS.pages_prefix}/*path", PagesController, :update

Router.get "#{Fluence::OPTIONS.media_prefix}/*path", MediaController, :show
Router.post "#{Fluence::OPTIONS.media_prefix}/*path", MediaController, :update
Router.post "#{Fluence::OPTIONS.media_prefix}/upload", MediaController, :upload

Router.get "#{Fluence::OPTIONS.users_prefix}/login", UsersController, :login
Router.post "#{Fluence::OPTIONS.users_prefix}/login", UsersController, :login_validates
Router.get "#{Fluence::OPTIONS.users_prefix}/register", UsersController, :register
Router.post "#{Fluence::OPTIONS.users_prefix}/register", UsersController, :register_validates
Router.get "#{Fluence::OPTIONS.users_prefix}/logout", UsersController, :logout

Router.get "#{Fluence::OPTIONS.admin_prefix}#{Fluence::OPTIONS.users_prefix}", AdminController, :users_show
Router.post "#{Fluence::OPTIONS.admin_prefix}#{Fluence::OPTIONS.users_prefix}/create", AdminController, :user_create
Router.post "#{Fluence::OPTIONS.admin_prefix}#{Fluence::OPTIONS.users_prefix}/delete", AdminController, :user_delete

Router.get "#{Fluence::OPTIONS.admin_prefix}/acls", AdminController, :acls_show
Router.post "#{Fluence::OPTIONS.admin_prefix}/acls/update", AdminController, :acl_update
Router.post "#{Fluence::OPTIONS.admin_prefix}/acls/create", AdminController, :acl_create
Router.post "#{Fluence::OPTIONS.admin_prefix}/acls/delete", AdminController, :acl_delete
