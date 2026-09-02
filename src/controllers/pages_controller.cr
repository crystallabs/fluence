class PagesController < ApplicationController

  # get /pages/*path
  #
  # Query parameters select the page's history views, which share the
  # page URL so the page's ACL applies to them:
  #   ?history    list of commits that touched the page
  #   ?rev=<oid>  page content as of that commit
  #   ?diff=<oid> what that commit changed in the page
  def show
    acl_permit! :read
    flash["danger"] = params.query["flash.danger"] if params.query["flash.danger"]?
    page = Fluence::Page.new params.url["path"]
    page.process! if page.exists?

    if params.query.has_key? "history"
      show_history page
    elsif rev = params.query["rev"]?
      show_revision page, rev
    elsif rev = params.query["diff"]?
      show_diff page, rev
    else
      show_show page, Fluence::Media.new(page.name)
    end
  end

  # Commits that touched the page; the newest HISTORY_LIMIT unless ?all.
  HISTORY_LIMIT = 100

  private def show_history(page)
    limit = params.query.has_key?("all") ? 0 : HISTORY_LIMIT
    commits = page.history limit
    truncated = limit > 0 && commits.size == limit
    tree = page_tree
    title = "History of #{page.title} - #{title()}"
    render "history.slang"
  end

  private def show_revision(page, rev)
    commit = commit_or_redirect(page, rev) || return
    body = page.read_at commit.oid
    body_html = Fluence::Markdown.to_html body
    writable = Fluence::ACL.permitted? current_user, page.url, Acl::Perm::Write
    tree = page_tree
    title = "#{page.title} @ #{commit.short_oid} - #{title()}"
    render "revision.slang"
  rescue Fluence::Error404
    flash["danger"] = "The page did not exist in revision #{rev}."
    redirect_to "#{page.url}?history"
  end

  private def show_diff(page, rev)
    commit = commit_or_redirect(page, rev) || return
    diff = page.diff commit.oid
    tree = page_tree
    title = "Changes to #{page.title} @ #{commit.short_oid} - #{title()}"
    render "diff.slang"
  end

  # The commit *rev* from the page's history, or nil after redirecting to
  # the history when it is not one of them.
  private def commit_or_redirect(page, rev) : Fluence::Storage::Commit?
    if rev.matches? Fluence::Storage::REV
      commit = page.history.find &.oid.starts_with?(rev)
    end
    return commit if commit
    flash["danger"] = "Revision '#{rev}' is not part of the history of page '#{page.name}'."
    redirect_to "#{page.url}?history"
    nil
  end

  private def show_show(page, media)
    body = page.exists? ? (page.read rescue "") : ""
    body_html = Fluence::Markdown.to_html body
    last_commit = page.exists? ? page.history(1).first? : nil
    Fluence::ACL.load!
    writable = Fluence::ACL.permitted? current_user, page.url, Acl::Perm::Write
    body = page.default_content if writable && !page.exists?
    open_in_edit = open_in_edit? page

    if !page.exists?
      flash["info"] = "The page '#{page.name}' does not exist yet."
      if Fluence::ACL.permitted?(current_user, request.path, Acl::Perm::Write)
        flash["info"] += " You could create it by typing and saving new content."
      else
        flash["info"] += " Register or login to be able to create it."
      end
    end

    groups_read = Fluence::ACL.groups_having_any_access_to page.url, Acl::Perm::Read
    groups_write = Fluence::ACL.groups_having_any_access_to page.url, Acl::Perm::Write, true
    title = "#{page.title} - #{title()}"

    tree = page_tree

    render "show.slang"
  end

  # Whether the editor opens in edit mode (as opposed to preview) for
  # *page*: the ?edit and ?view query parameters decide, otherwise the
  # open_*_in_edit options do.
  private def open_in_edit?(page) : Bool
    return true if params.query.has_key? "edit"
    return false if params.query.has_key? "view"
    options = Fluence::OPTIONS
    options.open_in_edit ||
      (!page.exists? && options.open_new_in_edit) ||
      (page.exists? && page.size == 0 && options.open_empty_in_edit)
  end

  # post /pages/*path
  def update
    acl_permit! :write
    page = Fluence::Page.new params.url["path"]
    page.process! if page.exists?
    if params.body["rename"]?
      update_rename(page)
    elsif params.body["delete"]?
      update_delete(page)
    # We do not want empty body to mean page deletion.
    #elsif (params.body["body"]?.to_s.empty?)
    #  update_delete(page)
    else
      update_edit(page)
    end
  end

  private def update_rename(main_page)
    new_main_name = params.body["input-page-name"]?.to_s.strip
    unless new_main_name.empty?
      pages = [main_page]
      if params.body["input-page-subtree"]?
        pages += subtree_of main_page
      end
      # TODO: if input-page-name does not begin with /, do relative rename to the current path

      old_main_page_name = main_page.name
      pages.each do |page|
        old_url = page.url
        begin
          old_name = page.name
          new_name = page.name.sub /^#{Regex.escape old_main_page_name}/, new_main_name

          # The user must be permitted to write at the destination too,
          # including where the page's attachments move to.
          new_page = Fluence::Page.new new_name
          destinations = [new_page.url]
          destinations << Fluence::Media.new(new_page.name).url unless page.attachment_paths.empty?
          destinations.each do |new_url|
            unless Fluence::ACL.permitted?(current_user, new_url, Acl::Perm::Write)
              flash["danger"] = "You are not permitted to write to '#{new_url}'."
              redirect_to old_url
              return
            end
          end

          page.rename! current_user, new_name, !!params.body["input-page-overwrite"]?, subtree: false, intlinks: !!params.body["input-page-intlinks"]?
          flash["success success-#{old_name}"] = "Page '#{old_name}' has been renamed to '#{page.name}'"
        rescue e : Fluence::Page::AlreadyExists | Fluence::Error409
          flash["danger danger-#{page.name}"] = e.to_s
          redirect_to old_url
          return
        end
      end
    end
    redirect_to main_page.url
  end

  private def update_delete(main_page)
    unless params.body["input-page-name"]?.to_s.strip.empty?
      pages = [main_page]
      if params.body["input-page-subtree"]?
        pages += subtree_of main_page
      end

      pages.each do |page|
        begin
          page.delete current_user if page.exists?
          flash["success success-#{page.name}"] = "Page '#{page.name}' has been deleted"
        rescue e
          flash["danger danger-#{page.name}"] = e.to_s
          redirect_to page.url
          return
        end
      end
    end
    redirect_to "#{Fluence::OPTIONS.homepage}"
  end

  # Saves the page body. Answers JSON ({success} or {success, error}) when
  # the client asks for it (Accept: application/json), as "Save & continue"
  # does; otherwise redirects to the page, reopening the editor when the
  # form was submitted with "continue".
  private def update_edit(page)
    action = page.exists? ? "updated" : "created"
    error = nil
    begin
      page.update! current_user, params.body["body"], params.body["summary"]?
    rescue err
      error = "Error: cannot update #{page.name}, #{err.message}"
    end

    if request.headers["Accept"]?.try &.includes?("application/json")
      @env.response.content_type = "application/json"
      return (error ? {success: false, error: error} : {success: true, title: page.title}).to_json
    end
    if error
      flash["danger"] = error
    else
      flash["success"] = %Q(Page '#{page.name}' has been #{action})
    end
    redirect_to params.body["continue"]? ? "#{page.url}?edit" : page.url
  end

  # get /sitemap
  def sitemap
    acl_permit! :read
    tree = page_tree
    media = Fluence::MEDIA.children1
    title = "Sitemap - #{title()}"
    render "sitemap.slang"
  end

  # get /pages/search?q=
  def search
    acl_permit! :read
    query = params.query["q"]?.to_s.strip
    results = [] of Fluence::Page
    unless query.empty?
      results = Fluence::PAGES.search(query).compact_map do |name|
        page = Fluence::Page.new name
        next unless Fluence::ACL.permitted?(current_user, page.url, Acl::Perm::Read)
        page.process!
      end
    end
    title = "Search - #{title()}"
    render "search.slang"
  end

  private def subtree_of(page)
    prefix = page.name + "/"
    Fluence::PAGES.names.select(&.starts_with?(prefix)).map { |name| Fluence::Page.new(name).process! }
  end
end
