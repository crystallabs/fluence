# A read-only view of an IO that raises `TooLarge` once more than *limit*
# bytes have been read through it — for request bodies whose size is not
# known in advance (chunked) or whose Content-Length is not trusted.
class Fluence::LimitedIO < IO
  class TooLarge < Exception
  end

  @read = 0_i64

  def initialize(@io : IO, @limit : Int64)
  end

  def read(slice : Bytes) : Int32
    count = @io.read slice
    @read += count
    raise TooLarge.new "More than #{@limit} bytes" if @read > @limit
    count
  end

  def write(slice : Bytes) : NoReturn
    raise IO::Error.new "Can't write to a LimitedIO"
  end
end
