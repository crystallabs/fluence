class ApplicationController
  module Request
    delegate :request, to: @env

    # Whether the client asked for a JSON answer (Accept:
    # application/json), as the fetch calls of base.js do.
    def wants_json? : Bool
      ApplicationController.wants_json? request
    end
  end

  def self.wants_json?(request : HTTP::Request) : Bool
    !!request.headers["Accept"]?.try &.includes?("application/json")
  end
end
