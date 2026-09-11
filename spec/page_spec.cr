require "./spec_helper"

describe Fluence::Page do
  it "test basic" do
    page = Fluence::Page.new("home")
    page.name.should eq "home"
    page.url.should eq "/pages/home"
    page.path.should eq "pages/home.md"
  end

  it "derives title, toc, and intlinks from content" do
    with_each_storage do |storage, kind|
      page = Fluence::Page.new("guide")
      page.update! SPEC_USER, "# The Guide\n## Part One\nSee [other](other).\n"
      page.title.should eq "The Guide"
      page.toc.should eq [{1, "The Guide"}, {2, "Part One"}]
      page.intlinks.size.should eq 1
      page.intlinks[0][1].should eq "other"
      page.size.should be > 0
    end
  end
end

describe Fluence::Page do
  it "moves attachments along on rename and rewrites links to them" do
    with_each_storage do |storage, kind|
      page = Fluence::Page.new("docs/guide")
      page.update! SPEC_USER, "# Guide\n![Shot](/media/docs/guide/shot.png) [pdf](/media/docs/guide/manual.pdf) [other](/media/docs/guidebook/x.png)\n"
      Fluence::Media.new("docs/guide/shot.png").write SPEC_USER, "PNG"
      Fluence::Media.new("docs/guide/manual.pdf").write SPEC_USER, "PDF"
      Fluence::Page.new("linker").update! SPEC_USER, "[g](/pages/docs/guide) ![s](/media/docs/guide/shot.png)\n"

      page.rename! SPEC_USER, "docs/handbook", intlinks: true

      Fluence::Media.new("docs/guide/shot.png").exists?.should be_false
      Fluence::Media.new("docs/handbook/shot.png").read.should eq "PNG"
      Fluence::Media.new("docs/handbook/manual.pdf").read.should eq "PDF"
      page.read.should eq "# Guide\n![Shot](/media/docs/handbook/shot.png) [pdf](/media/docs/handbook/manual.pdf) [other](/media/docs/guidebook/x.png)\n"
      Fluence::Page.new("linker").read.should eq "[g](/pages/docs/handbook) ![s](/media/docs/handbook/shot.png)\n"

      log = storage.log("pages/docs/handbook.md")
      log.map(&.subject).should eq ["Update page docs/handbook", "Rename page docs/guide -> docs/handbook", "Create page docs/guide"]
      log[0].body.should eq "Rewrite attachment links after renaming page docs/guide -> docs/handbook"
      log[1].body.should contain "media/docs/guide/shot.png -> media/docs/handbook/shot.png"
      storage.log("media/docs/handbook/shot.png")[0].subject.should eq "Rename page docs/guide -> docs/handbook"
      storage.log("pages/linker.md")[0].body.should eq "Update links after renaming page docs/guide -> docs/handbook"
    end
  end

  it "describes each write in the commit message" do
    with_each_storage do |storage, kind|
      page = Fluence::Page.new("notes")
      page.update! SPEC_USER, "# Notes\n", "  Started the notes page  "
      page.update! SPEC_USER, "# Notes\nmore\n"
      page.delete SPEC_USER
      Fluence::Media.new("notes/f.txt").write SPEC_USER, "x"

      log = storage.log("pages/notes.md")
      log.map(&.subject).should eq ["Delete page notes", "Update page notes", "Create page notes"]
      log[2].body.should eq "Started the notes page"
      storage.log("media/notes/f.txt")[0].subject.should eq "Upload media notes/f.txt"
    end
  end
end

describe Fluence::Page do
  it "leaves subpages' attachments and the links to them alone when the parent is renamed" do
    with_each_storage do |storage, kind|
      Fluence::Page.new("a").update! SPEC_USER, "# A\n![own](/media/a/own.png) ![sub](/media/a/b/pic.png)\n"
      Fluence::Page.new("a/b").update! SPEC_USER, "# B\n![pic](/media/a/b/pic.png) ![up](/media/a/own.png)\n"
      Fluence::Media.new("a/own.png").write SPEC_USER, "OWN"
      Fluence::Media.new("a/b/pic.png").write SPEC_USER, "PIC"
      Fluence::Media.new("a/nested/deep.txt").write SPEC_USER, "DEEP"

      Fluence::Page.new("a").attachment_paths.should eq ["media/a/nested/deep.txt", "media/a/own.png"]

      Fluence::Page.new("a").process!.rename! SPEC_USER, "c", intlinks: true

      storage.list("media").should eq ["media/a/b/pic.png", "media/c/nested/deep.txt", "media/c/own.png"]
      Fluence::Page.new("c").read.should eq "# A\n![own](/media/c/own.png) ![sub](/media/a/b/pic.png)\n"
      Fluence::Page.new("a/b").read.should eq "# B\n![pic](/media/a/b/pic.png) ![up](/media/c/own.png)\n"
    end
  end
end
