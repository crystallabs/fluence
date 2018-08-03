class HomeController < ApplicationController
  # get /
  def index
    if Fluence::ACL.permitted?(current_user, "/pages/home", Acl::Perm::Read)
      redirect_to "/pages/home"
    else
      "Not authorized"
    end
  end
end
