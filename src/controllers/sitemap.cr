def add_page(page, stack = [] of String)
  String.build do |str|
    Slang.embed("src/views/sitemap.directory.html.slang", "str")
  end
end

get "/sitemap" do |env|
  locals = {title: "sitemap", pages: Wikicr::Page.list}
  render "src/views/sitemap.html.slang", "src/views/layout.html.slang"
end