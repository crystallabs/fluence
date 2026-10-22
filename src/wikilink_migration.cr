require "./page"

# One-shot conversion of the [[wikilink]] syntax to standard markdown
# links, resolving names against the catalog. Run with
# FLUENCE_MIGRATE_WIKILINKS=1; each modified page is committed to the
# wiki repository.
module Fluence::WikilinkMigration
  WIKILINK = /(?<!\\)\[\[([^\[\]\|\n]+)(?:\|([^\[\]\n]*))?\]\]/

  # Converts [[link]] and [[link|title]] in *content* to [title](url).
  # Code (see `Page::Lines`) is left untouched.
  def self.convert(content : String, context : Fluence::Page) : String
    String.build(content.bytesize) do |b|
      Page::Lines.each(content) do |line, code|
        if code
          b << line
        else
          b << line.gsub(WIKILINK) do
            title, url = resolve $1, $2?, context
            "[#{title}](#{url})"
          end
        end
      end
    end
  end

  # Rewrites all pages in place, committing each change as *user*.
  # Returns the number of pages modified.
  def self.run!(user : Fluence::User) : Int32
    changed = 0
    Fluence::PAGES.names.each do |name|
      page = Fluence::Page.new name
      content = page.read rescue next
      updated = convert content, page
      if updated != content
        page.write user, updated
        changed += 1
      end
    end
    changed
  end

  private def self.resolve(link, title, context)
    found_title, url = Fluence::PAGES.find link, context
    title = found_title if title.nil? || title.empty?
    {title, url}
  end
end
