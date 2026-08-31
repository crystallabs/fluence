require "./spec_helper"

describe Fluence::Markdown do
  it "test internal links" do
    with_each_storage do |storage, kind|
      page = Fluence::Page.new("test")
      index = Fluence::PAGES

      Fluence::Markdown.to_markdown("[[test]]", page, index).should eq("[test](/pages/test)")
      Fluence::Markdown.to_markdown("[not](http://itisnot/not)", page, index).should eq("[not](http://itisnot/not)")
      Fluence::Markdown.to_markdown("[\\[page]]", page, index).should eq("[\\[page]]")
    end
  end

  it "test special internal links cases" do
    with_each_storage do |storage, kind|
      page = Fluence::Page.new("test")
      index = Fluence::PAGES

      Fluence::Markdown.to_markdown("    [[test]]", page, index).should eq("    [[test]]")
      Fluence::Markdown.to_markdown("```\n[[test]]\n```\n[[test]]", page, index).should eq("```\n[[test]]\n```\n[test](/pages/test)")
    end
  end

  it "test internal link with fixed title" do
    with_each_storage do |storage, kind|
      page = Fluence::Page.new("test")
      index = Fluence::PAGES

      Fluence::Markdown.to_markdown("[[test|title]]", page, index).should eq("[title](/pages/test)")
      Fluence::Markdown.to_markdown("[[test-longer|title a bit longer]]", page, index).should eq("[title a bit longer](/pages/test-longer)")
      Fluence::Markdown.to_markdown("[[test-empty|]]", page, index).should eq("[test-empty](/pages/test-empty)")
    end
  end

  it "resolves links to existing pages by title" do
    with_each_storage do |storage, kind|
      Fluence::Page.new("real-page").update! SPEC_USER, "# My Real Page\n"
      page = Fluence::Page.new("test")

      Fluence::Markdown.to_markdown("[[My Real Page]]", page, Fluence::PAGES)
        .should eq("[My Real Page](/pages/real-page)")
    end
  end
end
