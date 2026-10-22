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

  it "escapes disallowed raw HTML and drops script-capable link targets" do
    html = Fluence::Markdown.to_html("<img src=x onerror=alert(1)>\n\ntext <b onclick=alert(2)>bold</b>\n")
    html.should_not contain "<img"
    html.should_not contain "<b "
    html.should contain "&lt;img src=x onerror=alert(1)&gt;"
    html.should contain "text"

    html = Fluence::Markdown.to_html("[x](javascript:alert(1)) ![i](data:text/html,x) ![ok](data:image/png;base64,AA==)\n")
    html.should_not contain "javascript:"
    html.should_not contain "data:text/html"
    html.should contain %(src="data:image/png;base64,AA==")
  end

  it "lets <i>/<span class=\"...\"> through for icons and custom styling" do
    html = Fluence::Markdown.to_html(%(An icon <i class="fas fa-running l4"></i> and <span class="highlight">text</span>.))
    html.should contain %(<i class="fas fa-running l4"></i>)
    html.should contain %(<span class="highlight">text</span>)
  end

  it "lets headings, lists, and layout containers through as raw HTML" do
    html = Fluence::Markdown.to_html(<<-HTML
      <div class="callout">
      <article>
      <h3 class="title">Heading</h3>
      <ul><li>one</li><li>two</li></ul>
      <ol><li>first</li></ol>
      </article>
      </div>
      HTML
    )
    html.should contain %(<div class="callout">)
    html.should contain "<article>"
    html.should contain %(<h3 class="title">Heading</h3>)
    html.should contain "<ul><li>one</li><li>two</li></ul>"
    html.should contain "<ol><li>first</li></ol>"
    html.should contain "</div>"
  end

  it "still escapes an unsafe tag disguised with a class attribute" do
    html = Fluence::Markdown.to_html(%(<img class="x" src=y onerror=alert(1)>))
    html.should_not contain "<img"
    html.should contain "&lt;img"
  end

  it "escapes an opening tag carrying an extra attribute besides class" do
    html = Fluence::Markdown.to_html(%(<span class="x" onclick="alert(1)">text</span>))
    html.should_not contain %(<span class="x" onclick)
    html.should contain %(&lt;span class="x" onclick="alert(1)"&gt;)
  end

  it "leaves links alone when no user is given to check them against" do
    Fluence::Markdown.to_html("[Secret](/pages/hidden/secret)")
      .should contain %(<a href="/pages/hidden/secret">Secret</a>)
  end

  it "replaces a link to an unreadable page or attachment with the inaccessible label, dropping its text" do
    with_each_storage do |_, _|
      Fluence::ACL["guest"]["#{Fluence::OPTIONS.pages_prefix}/hidden/*"] = Acl::Perm::None
      Fluence::ACL["guest"]["#{Fluence::OPTIONS.media_prefix}/hidden/*"] = Acl::Perm::None
      begin
        html = Fluence::Markdown.to_html(
          "[Secret Plans](/pages/hidden/secret) and [a file](/media/hidden/secret/plans.pdf) and [Visible](/pages/visible)",
          Fluence::USERS.default.not_nil!
        )
        html.should_not contain "Secret Plans"
        html.should_not contain "hidden/secret"
        html.should contain "#{Fluence::OPTIONS.inaccessible_label}</span>"
        html.should contain %(<a href="/pages/visible">Visible</a>)
      ensure
        Fluence::ACL["guest"].delete "#{Fluence::OPTIONS.pages_prefix}/hidden/*"
        Fluence::ACL["guest"].delete "#{Fluence::OPTIONS.media_prefix}/hidden/*"
      end
    end
  end

  it "resolves a relative link the same way the page menu and intlinks do, before checking access" do
    with_each_storage do |_, _|
      Fluence::ACL["guest"]["#{Fluence::OPTIONS.pages_prefix}/hidden/*"] = Acl::Perm::None
      begin
        # Written on page "new-page" (context_name ""), "hidden/test2" is a
        # sibling target and resolves to /pages/hidden/test2 — same as the
        # browser resolving the href against the page's own URL.
        html = Fluence::Markdown.to_html(
          "[test](hidden/test2)", Fluence::USERS.default.not_nil!, ""
        )
        html.should_not contain "hidden/test2"
        html.should contain "#{Fluence::OPTIONS.inaccessible_label}</span>"
      ensure
        Fluence::ACL["guest"].delete "#{Fluence::OPTIONS.pages_prefix}/hidden/*"
      end
    end
  end

  it "replaces an embedded image the reader can't read with the image-inaccessible label, dropping its src" do
    with_each_storage do |_, _|
      Fluence::ACL["guest"]["#{Fluence::OPTIONS.media_prefix}/hidden/*"] = Acl::Perm::None
      begin
        html = Fluence::Markdown.to_html(
          "![Secret Diagram](/media/hidden/plans.png) and ![Visible](/media/visible.png)",
          Fluence::USERS.default.not_nil!
        )
        html.should_not contain "Secret Diagram"
        html.should_not contain "hidden/plans.png"
        html.should contain "#{Fluence::OPTIONS.image_inaccessible_label}</span>"
        html.should contain %(<img src="/media/visible.png" alt="Visible" />)
      ensure
        Fluence::ACL["guest"].delete "#{Fluence::OPTIONS.media_prefix}/hidden/*"
      end
    end
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
