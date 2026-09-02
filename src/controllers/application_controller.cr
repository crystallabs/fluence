# This files creates the main controller which is inherited by any other controller.
# It also loads the controller and helpers.

require "./application_controller/**"
require "./helpers/**"

# The ApplicationController is the class that handles the environment:
# it handles the session, request, response, params, flash notices, cookies, redirections, and rendering.
class ApplicationController
  LAYOUT = "application.slang"
  include ApplicationController::Render
  include ApplicationController::Session
  include ApplicationController::Request
  include ApplicationController::Response
  include ApplicationController::Params
  include ApplicationController::Flash
  include ApplicationController::Cookies
  include ApplicationController::Redirect

  include Fluence::Helpers::User
  include Fluence::Helpers::Page

  getter env : HTTP::Server::Context

  def initialize(@env)
  end

  def title
    Fluence::OPTIONS.brand_info
  end

  # CSS classes of a navbar link: the link to the current page is active.
  def nav_link_class(href : String) : String
    request.path == href ? "nav-link active" : "nav-link"
  end
end

require "./**"
