require "./spec_helper"

# Simulates a concurrent `git push`: for the first *stale_reads* calls,
# `head` reports a stale commit, so the final compare-and-swap in commit
# loses against the repository's real HEAD.
private class StaleHeadRepo < Fluence::Storage::GitRepo
  property stale : String?
  property stale_reads = 0

  private def head : String?
    if (stale = @stale) && @stale_reads > 0
      @stale_reads -= 1
      return stale
    end
    super
  end
end

private def rev_parse_head(repo : String) : String
  output = IO::Memory.new
  Process.run("git", ["rev-parse", "HEAD"], env: {"GIT_DIR" => repo}, output: output)
  output.to_s.strip
end

describe Fluence::Storage do
  it "performs the full content lifecycle on each backend" do
    with_each_storage do |storage, _|
      storage.exists?("pages/home.md").should be_false
      storage.list("pages").should be_empty
      storage.size("pages/home.md").should be_nil

      storage.write "pages/home.md", "# Home\nBody text.", SPEC_USER, "create home"
      storage.exists?("pages/home.md").should be_true
      storage.read("pages/home.md").should eq "# Home\nBody text."
      storage.size("pages/home.md").should eq "# Home\nBody text.".bytesize
      storage.list("pages").should eq ["pages/home.md"]

      storage.write "pages/dir/sub.md", "# Sub\n", SPEC_USER, "create sub"
      storage.list("pages").should eq ["pages/dir/sub.md", "pages/home.md"]

      storage.headings("pages").should eq({
        "pages/home.md"    => "Home",
        "pages/dir/sub.md" => "Sub",
      })

      storage.search("body", "pages").should eq ["pages/home.md"]
      storage.search("nosuchtoken", "pages").should be_empty

      storage.rename "pages/home.md", "pages/start.md", SPEC_USER, "rename home"
      storage.exists?("pages/home.md").should be_false
      storage.read("pages/start.md").should eq "# Home\nBody text."

      storage.delete "pages/dir/sub.md", SPEC_USER, "delete sub"
      storage.exists?("pages/dir/sub.md").should be_false
      storage.list("pages").should eq ["pages/start.md"]

      expect_raises(Fluence::Error404) { storage.read "pages/none.md" }
    end
  end

  it "records commits attributed to the acting user" do
    with_each_storage do |storage, _|
      storage.write "pages/a.md", "# A\n", SPEC_USER, "create a"
      storage.write "pages/a.md", "# A, edited\n", SPEC_USER, "update a"
      log = git_log(storage)
      log.should contain "create a"
      log.should contain "update a"
      log.should contain "spec <spec@localhost>"
    end
  end

  it "stores binary content byte-for-byte" do
    with_each_storage do |storage, _|
      bytes = Bytes.new(256, &.to_u8)
      storage.write "media/p/file.bin", IO::Memory.new(bytes), SPEC_USER, "upload file.bin"
      storage.read("media/p/file.bin").to_slice.should eq bytes
      storage.size("media/p/file.bin").should eq 256
    end
  end

  it "does not create a commit for a no-op write" do
    with_each_storage do |storage, _|
      storage.write "pages/a.md", "same\n", SPEC_USER, "create a"
      storage.write "pages/a.md", "same\n", SPEC_USER, "identical write"
      git_log(storage).lines.size.should eq 1
    end
  end

  it "retries once when HEAD moves concurrently, and raises Error409 when it keeps moving" do
    dir = File.tempname("fluence-spec-cas")
    begin
      Fluence::Storage::GitRepo.init(dir)
      storage = StaleHeadRepo.new(dir)
      storage.write "pages/a.md", "# A\n", SPEC_USER, "create a"
      stale = rev_parse_head(storage.repo)

      # An external push lands after the wiki last saw HEAD...
      Fluence::Storage::GitRepo.new(dir).write "pages/b.md", "# B\n", SPEC_USER, "external push"

      # ...so the first commit attempt CAS-fails; the retry succeeds and
      # neither the pushed change nor the wiki write is lost.
      storage.stale = stale
      storage.stale_reads = 1
      storage.write "pages/c.md", "# C\n", SPEC_USER, "create c"
      storage.stale_reads.should eq 0
      storage.read("pages/b.md").should eq "# B\n"
      storage.read("pages/c.md").should eq "# C\n"

      # If HEAD is stale on the retry too, the conflict surfaces as Error409.
      storage.stale = stale
      storage.stale_reads = 99
      expect_raises(Fluence::Error409) do
        storage.write "pages/d.md", "# D\n", SPEC_USER, "create d"
      end
    ensure
      FileUtils.rm_rf dir
    end
  end
end

describe Fluence::Storage do
  it "reports history, past content, and diffs on each backend" do
    with_each_storage do |storage, _|
      storage.log("pages/h.md").should be_empty
      storage.write "pages/h.md", "# H\nfirst\n", SPEC_USER, "Create page h\n\nInitial text"
      storage.write "pages/h.md", "# H\nsecond\n", SPEC_USER, "Update page h"
      storage.rename "pages/h.md", "pages/moved.md", SPEC_USER, "Rename page h -> moved"

      log = storage.log("pages/moved.md")
      log.map(&.subject).should eq ["Rename page h -> moved", "Update page h", "Create page h"]
      log[2].body.should eq "Initial text"
      log[1].body.should eq ""
      log.each do |commit|
        commit.author.should eq "spec"
        commit.oid.size.should eq 40
        commit.short_oid.should eq commit.oid[0, 8]
        (Time.utc - commit.time).should be < 1.minute
      end
      storage.log("pages/moved.md", 2).map(&.subject).should eq ["Rename page h -> moved", "Update page h"]

      storage.read_at("pages/h.md", log[2].oid).should eq "# H\nfirst\n"
      storage.read_at("pages/h.md", log[1].short_oid).should eq "# H\nsecond\n"
      storage.read_at("pages/moved.md", log[0].oid).should eq "# H\nsecond\n"
      expect_raises(Fluence::Error404) { storage.read_at "pages/moved.md", log[1].oid }
      expect_raises(Fluence::Error404) { storage.read_at "pages/h.md", "HEAD" }

      diff = storage.diff("pages/h.md", log[1].oid)
      diff.should contain "-first"
      diff.should contain "+second"
      storage.diff("pages/h.md", log[2].oid).should contain "+first"
      storage.diff("pages/moved.md", log[1].oid).should eq ""
      expect_raises(Fluence::Error404) { storage.diff "pages/h.md", "--output=x" }
    end
  end

  it "renames several paths in one commit" do
    with_each_storage do |storage, _|
      storage.write "pages/p.md", "# P\n", SPEC_USER, "Create page p"
      storage.write "media/p/a.png", "A", SPEC_USER, "Upload media p/a.png"
      storage.write "media/p/sub/b.txt", "B", SPEC_USER, "Upload media p/sub/b.txt"

      storage.rename [{"pages/p.md", "pages/q.md"}, {"media/p/a.png", "media/q/a.png"},
                      {"media/p/sub/b.txt", "media/q/sub/b.txt"}], SPEC_USER, "Rename page p -> q"

      storage.list("pages").should eq ["pages/q.md"]
      storage.list("media").should eq ["media/q/a.png", "media/q/sub/b.txt"]
      storage.read("media/q/sub/b.txt").should eq "B"
      git_log(storage).lines.size.should eq 4
      storage.log("media/q/a.png").map(&.subject).should eq ["Rename page p -> q", "Upload media p/a.png"]
    end
  end
end

describe Fluence::Storage do
  it "reports the path a file had at each commit" do
    with_each_storage do |storage, _|
      storage.write "pages/h.md", "# H\nfirst\n", SPEC_USER, "Create page h"
      storage.rename "pages/h.md", "pages/moved.md", SPEC_USER, "Rename page h -> moved"

      log = storage.log("pages/moved.md")
      log.map(&.path).should eq ["pages/moved.md", "pages/h.md"]
      storage.read_at(log[1].path, log[1].oid).should eq "# H\nfirst\n"
    end
  end

  it "finds headings of files with non-ASCII names" do
    with_each_storage do |storage, _|
      storage.write "pages/straße-日本.md", "# Unicode Title\n", SPEC_USER, "create"
      storage.headings("pages").should eq({"pages/straße-日本.md" => "Unicode Title"})
    end
  end

  it "raises Error404 when renaming or deleting a missing path" do
    with_each_storage do |storage, _|
      expect_raises(Fluence::Error404) { storage.rename "pages/nope.md", "pages/x.md", SPEC_USER, "m" }
      expect_raises(Fluence::Error404) { storage.delete "pages/nope.md", SPEC_USER, "m" }
    end
  end
end

# Runs git plumbing *args* against the bare repository *repo* (with index
# file *index*), returning the stripped output.
private def plumbing(repo : String, index : String, args : Array(String), input : String? = nil) : String
  env = {"GIT_DIR" => repo, "GIT_INDEX_FILE" => index,
         "GIT_AUTHOR_NAME" => "ext", "GIT_AUTHOR_EMAIL" => "ext@localhost",
         "GIT_COMMITTER_NAME" => "ext", "GIT_COMMITTER_EMAIL" => "ext@localhost"}
  output = IO::Memory.new
  status = Process.run("git", args, env: env, output: output, error: Process::Redirect::Inherit,
    input: IO::Memory.new(input || ""))
  raise "git #{args.first} failed" unless status.success?
  output.to_s.strip
end

# Commits *content* at *path* straight into the bare repository *repo* with
# git plumbing, bypassing Fluence like a `git push` would.
private def external_commit(repo : String, path : String, content : String)
  index = File.tempname("fluence-spec-index")
  begin
    blob = plumbing repo, index, ["hash-object", "-w", "--stdin"], content
    plumbing repo, index, ["read-tree", "HEAD"]
    plumbing repo, index, ["update-index", "--add", "--cacheinfo", "100644,#{blob},#{path}"]
    tree = plumbing repo, index, ["write-tree"]
    commit = plumbing repo, index, ["commit-tree", tree, "-p", "HEAD", "-m", "external"]
    plumbing repo, index, ["update-ref", "HEAD", commit]
  ensure
    File.delete? index
  end
end

describe "Fluence::Storage#snapshot" do
  it "returns the block's value on each backend" do
    with_each_storage do |storage, _|
      storage.snapshot { 42 }.should eq 42
    end
  end

  it "keeps reads on the pinned commit while the repository moves on" do
    with_each_storage do |storage, _|
      next unless storage.is_a? Fluence::Storage::GitRepo
      storage.write "pages/a.md", "# Old\n", SPEC_USER, "create a"

      storage.snapshot do
        external_commit storage.repo, "pages/a.md", "# New\nfresh\n"
        external_commit storage.repo, "pages/b.md", "# B\n"

        storage.read("pages/a.md").should eq "# Old\n"
        storage.size("pages/a.md").should eq "# Old\n".bytesize
        storage.exists?("pages/b.md").should be_false
        storage.list("pages").should eq ["pages/a.md"]
        storage.headings("pages").should eq({"pages/a.md" => "Old"})
        storage.search("fresh", "pages").should be_empty
        storage.log("pages/a.md").map(&.subject).should eq ["create a"]

        # Another fiber (another request) is not pinned.
        channel = Channel(String).new
        spawn { channel.send storage.read("pages/a.md") }
        channel.receive.should eq "# New\nfresh\n"

        # A nested snapshot keeps the outer pin.
        storage.snapshot { storage.read("pages/a.md") }.should eq "# Old\n"
        storage.read("pages/a.md").should eq "# Old\n"
      end

      # Outside, and in a later snapshot, reads see the new HEAD.
      storage.read("pages/a.md").should eq "# New\nfresh\n"
      storage.snapshot { storage.list("pages") }.should eq ["pages/a.md", "pages/b.md"]
    end
  end

  it "sees its own writes, built on the live HEAD" do
    with_each_storage do |storage, _|
      next unless storage.is_a? Fluence::Storage::GitRepo
      storage.snapshot do
        # Pinned while HEAD is still unborn.
        storage.exists?("pages/a.md").should be_false
        storage.list("pages").should be_empty
        storage.write "pages/a.md", "# A\n", SPEC_USER, "create a"
        storage.read("pages/a.md").should eq "# A\n"

        external_commit storage.repo, "pages/b.md", "# B\n"
        storage.exists?("pages/b.md").should be_false
        storage.write "pages/c.md", "# C\n", SPEC_USER, "create c"
        # The write builds on, and so reveals, the external commit.
        storage.list("pages").should eq ["pages/a.md", "pages/b.md", "pages/c.md"]

        external_commit storage.repo, "pages/d.md", "# D\n"
        storage.delete "pages/b.md", SPEC_USER, "delete b"
        storage.list("pages").should eq ["pages/a.md", "pages/c.md", "pages/d.md"]
      end
      storage.read("pages/c.md").should eq "# C\n"
      git_log(storage).lines.size.should eq 5
    end
  end

  it "lets a request see its own write, as Save and continue does" do
    with_each_storage do |storage, _|
      next unless storage.is_a? Fluence::Storage::GitRepo
      client = SpecClient.login "editor", "sekrit123"
      headers = HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded", "Accept" => "application/json"}
      response = client.post "/pages/snap", headers, URI::Params.encode({"body" => "# Snap Title\n"})
      # The title is read back inside the request's snapshot, which was
      # pinned before the page existed.
      JSON.parse(response.body)["title"].should eq "Snap Title"
    end
  end
end
