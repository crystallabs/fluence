# Lockable is an abstract class that provides a function `#transaction!` that
# allows the class to execute some code that requires to do not conflict with
# other operations. It is usually linked with an IO (a file).
require "yaml"

abstract class Lockable
  abstract def load!
  abstract def save!

  @[YAML::Field(ignore: true)]
  @lock : Mutex = Mutex.new

  # Executes some operation on the object under the lock, then saves it.
  # The content can optionally be (re)loaded first. Nothing is saved when
  # the block raises, so a failed operation leaves the file as it was.
  #
  # ```
  # someLockableObject.transaction!(read: true) { |obj| obj.update_operation(...) }
  # ```
  def transaction!(read = false, &)
    @lock.synchronize do
      load! if read
      yield self
      save!
    end
    self
  end
end
