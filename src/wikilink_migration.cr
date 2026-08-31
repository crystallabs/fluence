require "./page"

# One-shot conversion of the legacy [[wikilink]] syntax to standard
# markdown links, resolving names against the catalog the way the old
# renderer did. Run with FLUENCE_MIGRATE_WIKILINKS=1; each modified page
# is committed to the wiki repository.
module Fluence::WikilinkMigration
  WIKILINK = /(?<!\\)\[\[([^\[\]\|\n]+)(?:\|([^\[\]\n]*))?\]\]/

  # Converts [[link]] and [[link|title]] in *content* to [title](url).
  # Fenced and indented code blocks are left untouched.
  def self.convert(content : String, context : Fluence::Page) : String
    code_block = false
    String.build(content.bytesize) do |b|
      content.each_line(chomp: false) do |line|
        code_block = !code_block if line.starts_with? "```"
        if code_block || line.starts_with?("    ")
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
