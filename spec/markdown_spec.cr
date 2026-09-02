require "./spec_helper"

describe Fluence::Markdown do
  it "renders GFM tables and strikethrough" do
    html = Fluence::Markdown.to_html("A | B\n--- | ---\n1 | 2\n\n~~gone~~\n")
    html.should contain "<table"
    html.should contain "<del>gone</del>"
  end

  it "renders standard links as-is" do
    Fluence::Markdown.to_html("[title](/pages/test)")
      .should contain %(<a href="/pages/test">title</a>)
    Fluence::Markdown.to_html("[not](http://itisnot/not)")
      .should contain %(<a href="http://itisnot/not">not</a>)
  end

  it "leaves [[wikilinks]] as literal text" do
    Fluence::Markdown.to_html("[[test]]").should contain "[[test]]"
  end

  it "gives headings ids matching the TOC anchors" do
    html = Fluence::Markdown.to_html("# My Heading\n## Sub Part\n")
    html.should contain %(<h1 id="my-heading">My Heading</h1>)
    html.should contain %(<h2 id="sub-part">Sub Part</h2>)
  end

  it "does not treat code block content as headings" do
    Fluence::Markdown.to_html("```\n# not a heading\n```\n").should_not contain "<h1"
  end
end

describe Fluence::WikilinkMigration do
  it "converts wikilinks to standard links, resolving titles" do
    with_each_storage do |storage, kind|
      Fluence::Page.new("real-page").update! SPEC_USER, "# My Real Page\n"
      page = Fluence::Page.new("test")

      Fluence::WikilinkMigration.convert("See [[My Real Page]] and [[missing|Custom]].", page)
        .should eq "See [My Real Page](/pages/real-page) and [Custom](/pages/missing)."
      Fluence::WikilinkMigration.convert("[[test-empty|]]", page)
        .should eq "[test-empty](/pages/test-empty)"
    end
  end

  it "leaves code blocks and escaped brackets alone" do
    with_each_storage do |storage, kind|
      page = Fluence::Page.new("test")

      Fluence::WikilinkMigration.convert("```\n[[test]]\n```\n[[test]]", page)
        .should eq "```\n[[test]]\n```\n[test](/pages/test)"
      Fluence::WikilinkMigration.convert("    [[test]]", page)
        .should eq "    [[test]]"
      Fluence::WikilinkMigration.convert("[\\[page]]", page)
        .should eq "[\\[page]]"
    end
  end

  it "rewrites and commits affected pages" do
    with_each_storage do |storage, kind|
      Fluence::Page.new("target").update! SPEC_USER, "# Target\n"
      Fluence::Page.new("linker").update! SPEC_USER, "See [[Target]].\n"
      Fluence::Page.new("plain").update! SPEC_USER, "No links here.\n"

      Fluence::WikilinkMigration.run!(SPEC_USER).should eq 1
      Fluence::Page.new("linker").read.should eq "See [Target](/pages/target).\n"
    end
  end
end
