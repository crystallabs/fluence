module Fluence
  class Error < Exception; end

  class Error404 < Error; end

  class Error403 < Error; end

  # Concurrent modification: the repository advanced (e.g. via a `git push`)
  # while a write was being prepared, and the retry lost the race again.
  class Error409 < Error
    def initialize(message = "the wiki repository changed while saving; please try again")
      super message
    end
  end
end
