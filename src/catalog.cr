require "./storage"

module Fluence
  # Catalog answers collection-level questions about wiki content — listings,
  # hierarchy, titles, internal-link resolution, and search — by asking the
  # `Storage` directly. It holds no state of its own: there is no cache or
  # index to build, persist, or go stale.
  class Catalog(T)
    getter prefix : String

    def initialize(@prefix : String)
    end

    private def storage : Fluence::Storage
      Fluence::Storage.current
    end

    # All entry names under this catalog's prefix, e.g. ["home", "dir/sub"].
    def names : Array(String)
      storage.list(@prefix).compact_map { |p| T.storage_path_to_name p }
    end

    # Map of name => display title. For titled content (pages) the title is
    # the first level-1 heading, obtained from storage in one pass; content
    # without one falls back to the last component of its name.
    def titles : Hash(String, String)
      heads = T.titled? ? storage.headings(@prefix) : {} of String => String
      ret = {} of String => String
      names.each do |name|
        ret[name] = heads[T.new(name).path]? || ::File.basename(name)
      end
      ret
    end

    def [](name : String) : T
      self[name]? || raise Exception.new "Missing: '#{name}'"
    end

    def []?(name : String) : T?
      entry = T.new name
      entry.exists? ? entry.process! : nil
    end

    def [](entry : T) : T
      self[entry.name]
    end

    def []?(entry : T) : T?
      self[entry.name]?
    end

    def children1(page : T)
      children1 page.name
    end

    # Returns the immediate children of *name* ("" for the top level) as
    # `{key => {display_key, entry_or_nil}}`; nil marks a subdirectory level.
    def children1(name : String = "")
      ret = {} of String => {String, T?}
      titles_map = titles
      pattern = name.empty? ? /^(.+?)($|\/)/ : /^(#{Regex.escape(name)}\/(.+?))($|\/)/
      key_group = name.empty? ? 1 : 2
      last_group = name.empty? ? 2 : 3
      names.each do |n|
        if md = n.match pattern
          key = md[key_group].to_s
          val = md[last_group]? == "/" ? nil : entry_with_title(n, titles_map)
          ret[md[1]] = {key, val} if !ret[md[1]]? || val
        end
      end
      ret
    end

    # Returns all entries below *page* as `{name => {basename, entry}}`.
    def children(page : T)
      ret = {} of String => {String, T}
      titles_map = titles
      names.each do |n|
        if md = n.match /^#{Regex.escape(page.name)}\/.*?([^\/]+)$/
          ret[n] = {md[1].to_s, entry_with_title(n, titles_map)}
        end
      end
      ret
    end

    # Returns all entries as `{name => {name, entry}}`.
    def children
      ret = {} of String => {String, T}
      titles_map = titles
      names.each do |n|
        ret[n] = {n, entry_with_title(n, titles_map)}
      end
      ret
    end

    # Resolves an internal link *text* to `{title, url}`: prefers an entry
    # whose title slugifies to the same value, breaking ties by URL closeness
    # to *context*; otherwise links to the not-yet-existing top-level entry.
    def find(text : String, context : T) : {String, String}
      slug = T.title_to_slug text
      titles_map = titles
      matches = titles_map.keys.select { |n| T.title_to_slug(titles_map[n]) == slug }
      unless matches.empty?
        best = matches.map { |n| T.new n }.reduce do |lhs, rhs|
          Catalog.url_closeness(context.url, lhs.url) >= Catalog.url_closeness(context.url, rhs.url) ? lhs : rhs
        end
        return {titles_map[best.name], best.url}
      end
      {text, "#{context.url_prefix}/#{slug}"}
    end

    # Returns names matching *query* (case-insensitive) in their name,
    # title, or content.
    def search(query : String) : Array(String)
      q = query.downcase
      titles_map = titles
      name_hits = titles_map.keys.select do |n|
        n.downcase.includes?(q) || titles_map[n].downcase.includes?(q)
      end
      content_hits = storage.search(query, @prefix).compact_map { |p| T.storage_path_to_name p }
      (name_hits | content_hits).sort
    end

    # Computes the amount of common chars at the beginning of each string
    def self.url_closeness(from : String, to : String)
      from.size.times do |i|
        return i if from[i] != to[i]
      end
      from.size
    end

    private def entry_with_title(name : String, titles_map : Hash(String, String)) : T
      entry = T.new name
      entry.title = titles_map[name]? || entry.title
      entry
    end
  end
end
