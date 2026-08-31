# Lockable is an abstract class that provides a function `#transaction!` that
# allows the class to execute some code that requires to do not conflict with
# other operations. It is usually linked with an IO (a file).
require "yaml"

abstract class Lockable
  abstract def load!
  abstract def save!

  @[YAML::Field(ignore: true)]
  @lock : Mutex = Mutex.new

  # Execute some operation on the object, and then save it.
  # The content can be loaded before executing the operations optionally.
  #
  # ```
  # someLockableObject.transaction(read: true) { |obj| obj.update_operation(...) }
  # ```
  def transaction!(read = false)
    @lock.synchronize do
      begin
        self.load! if read == true
        yield self
      ensure
        self.save!
        self
      end
    end
  end
end
