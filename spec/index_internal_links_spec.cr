require "./spec_helper"

describe Fluence::Page::InternalLinks do
  it "lists standard markdown links to wiki pages" do
    str = "I [link](am-a-link) and [x](/pages/me-too), not [e](https://example.com) or ![img](pic.png)\n"
    links = Fluence::Page::InternalLinks.links_in_content str, "home"

    links.map(&.[1]).should eq ["am-a-link", "me-too"]
    links[0][0].should eq str.index("am-a-link")
  end

  it "resolves relative targets against the page directory" do
    str = "[s](sibling) [u](../up) [a](/pages/abs) [out](../../escape)"
    links = Fluence::Page::InternalLinks.links_in_content str, "dir/page"

    links.map(&.[1]).should eq ["dir/sibling", "up", "abs"]
  end

  it "skips code blocks, anchors, and non-page paths" do
    str = "```\n[x](y)\n```\n[a](#anchor)\n[m](/media/home/file.pdf)\n[b](real)\n"
    links = Fluence::Page::InternalLinks.links_in_content str, "home"

    links.map(&.[1]).should eq ["real"]
  end

  it "keeps fragments when rewriting links on rename" do
    content = "See [Old](/pages/old-page#part) and [rel](old-page), not [other](old-page-2)."
    updated = Fluence::Page::InternalLinks.rewrite_links content, "home", "old-page", "/pages/new-page"

    updated.should eq "See [Old](/pages/new-page#part) and [rel](/pages/new-page), not [other](old-page-2)."
  end
end

describe Fluence::Page::InternalLinks do
  it "rewrites link and image targets under a prefix" do
    content = "![i](/media/old/a.png) [d](/media/old/sub/b.pdf) [n](/media/older/c.png) [p](/pages/old)\n```\n![i](/media/old/a.png)\n```\n"
    updated = Fluence::Page::InternalLinks.rewrite_prefix content, "/media/old", "/media/new"

    updated.should eq "![i](/media/new/a.png) [d](/media/new/sub/b.pdf) [n](/media/older/c.png) [p](/pages/old)\n```\n![i](/media/old/a.png)\n```\n"
    Fluence::Page::InternalLinks.rewrite_prefix("plain", "/media/old", "/media/new").should eq "plain"
  end
end
