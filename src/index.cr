require "yaml"

module Fluence

	# Index is an index of all files in a chosen subdirectory and their saved or generated metadata.
	# The indexed subdirectories are usually `pages/` containing all Fluence Wiki pages, and `media/` containing all media/attachments associated with the individual pages.
  class Index(T) < Lockable
    include YAML::Serializable

    property file : String
    property directory : String
    property entries : Hash(String, T) # path, entry

		# Creates an empty index.
		# `@subdir` is name of the subdirectory within `datadir` that needs to be indexed, and will almost always be "pages" or "media".
    def initialize(subdir : String)
			@file = ::File.expand_path subdir, Fluence::OPTIONS.metadir
			@directory = ::File.expand_path subdir, Fluence::OPTIONS.datadir
      @entries = {} of String => T
    end

		# Creates an empty index, populates it with contents from desired subdir based on file search, and saves index contents to YAML file for persistence.
		# If you want to load an existing YAML dump of an index instead of create an index anew, see `load!`.
		def self.build(subdir : String, max_depth : Int = Fluence::OPTIONS.recursion_limit) : Index
			idx = Index(T).new subdir
			file_list(idx.directory, max_depth).each do |f|
				# 'f' is name from subdir onwards, e.g. 'home', 'home/test', etc.
				page = T.new(f).process!
				idx.add page
			end
			idx.save!
		end

		# Recursively finds files in the chosen starting directory.
		# Default limit is a maximum of Fluence::OPTIONS.recursion_limit directories to enter and scan.
		def self.file_list(subdir : String, max_depth : Int = Fluence::OPTIONS.recursion_limit) : Array
			# Stop the recursion
			raise Exception.new "Max recursion depth reached (#{max_depth})" if max_depth < 1

			# Save the current directory before getting in
			dir_current = Dir.current
			Dir.cd subdir

			# List the files and filter them
			all_files = Dir.glob "*"

			# Separate files and directory
			files = all_files.select { |file| !::File.directory? file }.map{ |f| f.chomp(".md")}

			# For directories, call this function recursively
			all_files
				.select { |file| ::File.directory? file }
				.map { |dir| Fluence::Index.file_list(dir, max_depth - 1).as(Array(String)).map { |f| ::File.join dir, f } }
				.each do |file_list|
					files += file_list
			end

			# Get out of the parent and return to current directory
			Dir.cd dir_current

			files
		end

    # Loads index contents from file, replacing any existing index content.
		# This method is faster than `build`, but it will contain stale data if the indexed directories are modified manually.
		# In such cases, just re-start Fluence with a command line option to rebuild the index, or delete the index in the `meta/` subdirectory and restart Fluence.
    def load!
      if ::File.exists?(@file) && (new_index = Index(T).read(@file) rescue nil)
        @entries = new_index.entries
        # @file = index.file
      else
        @entries = {} of String => T
      end
      self
    end

		# Creates index from contents of YAML file. This is a low level function and you should generally use `load!` instead.
    def self.read(file : String)
      self.from_yaml ::File.read(file)
    end

    # Saves current index to file, replacing any existing on-disk contents.
    def save!
      ::File.write @file, self.to_yaml
      self
    end

    def [](page : T) : T
      page = self[page]?
      page ? page : raise Exception.new "Missing: '#{page.path}'"
    end
    def []?(page : T) : T?
      ::File.exists?(page.path) ? page : nil
    end

    def []?(name : String) : T?
      page = T.new name
      self[page]?
    end
    def [](name : String) : T
      page = T.new name
      self[page]
    end

    # Writes page to disk. Does not commit to Git.
    def add(page : T)
      page.jail!
      page.content.try do |content| ::File.write page.path, content end
      self
    end
    # Adds a new `T` into the index. This operation syncs new index contents to disk.
		def add!(page : T)
			add page
			#commit! user, "update"
			self
		end

    # Removes a T from Index. This is a memory-only operation and does not sync new index contents to disk.
		# Recursive deletion is not handled here for now.
    def delete(page : T)
      page.jail!
      ::File.delete page.path
      self
    end
    # Deletes a page from index. This operation syncs new index contents to disk.
		# Recursive deletion is not handled here for now.
		def delete!(page : T)
			delete page
			#commit! user, "delete"
			self
		end

    # Renames `T` in index. This is a memory-only operation and does not sync new contents to disk.
		# Recursive renaming is not handled here for now.
    def rename(page : T, new_name : String)
      old = page
      new = T.new new_name
      old.jail!
      new.jail!
      ::File.rename old.path, new.path
      {old, new}
    end
    # Renames a page in index. This operation syncs new index contents to disk.
		# Recursive renaming is not handled here for now.
		def rename!(page : T)
			old, new = rename page
			#commit! user, new, other_files: old
			self
		end

		def children1(page : T)
			children1(page.name)
		end
		def children1(name : String)
			ret = {} of String => {String,T?}
			@entries.each do |k,v|
				if k =~ /^(#{name}\/(.+?))($|\/)/
					key = $2.to_s
					val = ($3 == "/") ? nil : v
					ret[$1] = {key,val} if !ret[$1]? || val
				end
			end
			ret
		end
		# Returns list of immediate children of the index, including subdirectories
		def children1
			ret = {} of String => {String,T?}
			@entries.each do |k,v|
				if k =~ /^(.+?)($|\/)/
					key = $1.to_s
					val = ($2.to_s == "/") ? nil : v
					ret[$1] = {key,val} if !ret[$1]? || val
				end
			end
			ret
		end
		# Returns list of all children pages for page
		def children(page : T)
			ret = {} of String => {String,T}
			@entries.each do |k,v|
				if k =~ /^#{page.name}\/.*?([^\/]+)$/
					key = $1.to_s
					val = v
					ret[k] = {key,val} if !ret[k]? || val
				end
			end
			ret
		end
		# Returns list of all pages in index
		def children
			ret = {} of String => {String,T}
			# Format here is a little unusual so it remains compatible with above
			@entries.each do |k,v|
				key = k.to_s
				val = v
				ret[k] = {key,val}
			end
			ret
		end

		#####
		# TODO review these functions below

    # Find a matching *text* in the Index.
    # If no matching content, return a default value.
    def find(text : String, context : T) : {String, String}
      found = find_by_title text, context
      return {found.title, found.url} unless found.nil?
      {text, "#{context.directory}/#{T.title_to_slug text}"}
    end

    # Find the closest `Index`' `T` to *text* based on the entries title
    # and searching for the closer url as possible to the context
    private def find_by_title(text : String, context : T) : T?
      # exact_matched = @entries.select{|_, entry| entry.title == text }.values
      # return choose_closer_url(exact_matched, context) unless exact_matched.empty?
      slug_matched = @entries.select { |_, entry| entry.slug == T.title_to_slug(text) }.values
      return choose_closer_url(slug_matched, context) unless slug_matched.empty?
      nil
    end

    # Find the url which is the closest as possible than the context url (start with the maximum common chars).
    private def choose_closer_url(entries : Array(T), context : T) : T
      raise "Cannot handle empty array" if entries.empty?
      entries.reduce { |lhs, rhs| Index.url_closeness(context.url, lhs.url) >= Index.url_closeness(context.url, rhs.url) ? lhs : rhs }
    end

    # Computes the amount of common chars at the beginning of each string
    def self.url_closeness(from : String, to : String)
      from.size.times do |i|
        return i if from[i] != to[i]
      end
      return from.size
    end
  end
end
