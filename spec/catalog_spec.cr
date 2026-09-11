require "./spec_helper"

describe Fluence::Catalog do
  it "lists names, titles, and hierarchy from storage" do
    with_each_storage do |storage, kind|
      Fluence::Page.new("home").update! SPEC_USER, "# Welcome Home\nHello."
      Fluence::Page.new("other").update! SPEC_USER, "no heading here"
      Fluence::Page.new("dir/sub").update! SPEC_USER, "# Subpage\n"

      Fluence::PAGES.names.should eq ["dir/sub", "home", "other"]

      titles = Fluence::PAGES.titles
      titles["home"].should eq "Welcome Home"
      titles["other"].should eq "other"
      titles["dir/sub"].should eq "Subpage"

      top = Fluence::PAGES.children1
      top.keys.sort.should eq ["dir", "home", "other"]
      top["dir"][1].should be_nil
      top["home"][1].not_nil!.title.should eq "Welcome Home"

      Fluence::PAGES.children1("dir").keys.should eq ["dir/sub"]

      page = Fluence::PAGES["home"]?.not_nil!
      page.toc.should eq [{1, "Welcome Home"}]
      Fluence::PAGES["missing"]?.should be_nil

      Fluence::Page.new("dir/sub").directory?.should be_false
      dir_holder = Fluence::Page.new("dir")
      dir_holder.directory?.should be_true
    end
  end

  it "resolves internal links by title and searches content" do
    with_each_storage do |storage, kind|
      Fluence::Page.new("home").update! SPEC_USER, "# Welcome Home\nsecretword here"
      context = Fluence::Page.new("context")

      title, url = Fluence::PAGES.find("Welcome Home", context)
      title.should eq "Welcome Home"
      url.should eq "/pages/home"

      _, missing_url = Fluence::PAGES.find("No Such Page", context)
      missing_url.should eq "/pages/no-such-page"

      Fluence::PAGES.search("secretword").should eq ["home"] # content match
      Fluence::PAGES.search("welcome").should eq ["home"]    # title match
      Fluence::PAGES.search("hom").should eq ["home"]        # name match
      Fluence::PAGES.search("zzz-nothing").should be_empty
    end
  end

  it "renames pages and rewrites internal links" do
    with_each_storage do |storage, kind|
      Fluence::Page.new("a").update! SPEC_USER, "# A\nSee [b](b) and [Custom](/pages/b). Not [bb](bb)."
      b = Fluence::Page.new("b").update! SPEC_USER, "# B\n"

      b.rename! SPEC_USER, "c", intlinks: true
      b.name.should eq "c"
      b.exists?.should be_true

      Fluence::Page.new("b").exists?.should be_false
      Fluence::Page.new("a").read.should eq "# A\nSee [b](/pages/c) and [Custom](/pages/c). Not [bb](bb)."
    end
  end

  it "refuses renaming onto an existing page unless overwriting" do
    with_each_storage do |storage, kind|
      a = Fluence::Page.new("a").update! SPEC_USER, "# A\n"
      Fluence::Page.new("b").update! SPEC_USER, "# B\n"

      expect_raises(Fluence::Page::AlreadyExists) { a.rename! SPEC_USER, "b" }
      a.rename! SPEC_USER, "b", overwrite: true
      Fluence::Page.new("b").read.should eq "# A\n"
    end
  end

  it "jails paths that try to escape the storage subtree" do
    expect_raises(Fluence::Error403) { Fluence::Media.new "../../etc/passwd" }
  end
end

describe Fluence::Catalog do
  it "breaks title ties by URL closeness even when a candidate URL is shorter" do
    with_each_storage do |storage, kind|
      Fluence::Page.new("docs").update! SPEC_USER, "# Docs\n"
      Fluence::Page.new("other/docs").update! SPEC_USER, "# Docs\n"

      _, url = Fluence::PAGES.find("Docs", Fluence::Page.new("docs/guide"))
      url.should eq "/pages/docs"
    end
  end

  it "lists only names that are reachable by URL" do
    with_each_storage do |storage, kind|
      storage.write "pages/README.md", "# Read Me\n", SPEC_USER, "pushed"
      storage.write "pages/My Notes.md", "# My Notes\n", SPEC_USER, "pushed"
      storage.write "pages/docs/user-guide.md", "# Guide\n", SPEC_USER, "pushed"
      storage.write "media/docs/user-guide/Shot 1.png", "x", SPEC_USER, "pushed"
      storage.write "media/docs/user-guide/shot-2.PNG", "x", SPEC_USER, "pushed"

      Fluence::PAGES.names.should eq ["docs/user-guide"]
      Fluence::PAGES.titles.should eq({"docs/user-guide" => "Guide"})
      Fluence::MEDIA.names.should eq ["docs/user-guide/shot-2.PNG"]
    end
  end
end
