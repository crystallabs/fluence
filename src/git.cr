require "../config/options"

module Fluence::Git
  extend self

  # Runs a git command in the data repository, without a shell, and returns
  # its combined output. Arguments are passed as-is and never interpolated
  # into a command line, so file names and user names cannot inject commands.
  def run(args : Array(String)) : String
    output = IO::Memory.new
    Process.run("git", args, chdir: Fluence::OPTIONS.datadir, output: output, error: output)
    output.to_s.tap { |o| puts o unless o.empty? }
  end

  # Initialize the data repository (where the pages are stored).
  def init!
    Dir.mkdir_p Fluence::OPTIONS.datadir
    run ["init", "."]
  end
end

Fluence::Git.init!
