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
