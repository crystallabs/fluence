require "./spec_helper"

describe Fluence::Storage do
  it "performs the full content lifecycle on each backend" do
    with_each_storage do |storage, kind|
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
    with_each_storage do |storage, kind|
      storage.write "pages/a.md", "# A\n", SPEC_USER, "create a"
      storage.write "pages/a.md", "# A, edited\n", SPEC_USER, "update a"
      log = git_log(storage)
      log.should contain "create a"
      log.should contain "update a"
      log.should contain "spec <spec@localhost>"
    end
  end

  it "stores binary content byte-for-byte" do
    with_each_storage do |storage, kind|
      bytes = Bytes.new(256) { |i| i.to_u8 }
      storage.write "media/p/file.bin", IO::Memory.new(bytes), SPEC_USER, "upload file.bin"
      storage.read("media/p/file.bin").to_slice.should eq bytes
      storage.size("media/p/file.bin").should eq 256
    end
  end

  it "does not create a commit for a no-op write" do
    with_each_storage do |storage, kind|
      storage.write "pages/a.md", "same\n", SPEC_USER, "create a"
      storage.write "pages/a.md", "same\n", SPEC_USER, "identical write"
      git_log(storage).lines.size.should eq 1
    end
  end
end
