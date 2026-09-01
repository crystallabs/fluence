class PagesController < ApplicationController

  # get /pages/*path
  def show
    acl_permit! :read
    flash["danger"] = params.query["flash.danger"] if params.query["flash.danger"]?
    page = Fluence::Page.new params.url["path"]
    page.process! if page.exists?
    media = Fluence::Media.new page.name

    show_show(page, media)
  end

  private def show_show(page, media)
    body = page.exists? ? (page.read rescue "") : ""
    body_html = Fluence::Markdown.to_html body
    Fluence::ACL.load!

    if !page.exists?
      flash["info"] = "The page '#{page.name}' does not exist yet."
      if Fluence::ACL.permitted?(current_user, request.path, Acl::Perm::Write)
        flash["info"] += " You could create it by typing and saving new content."
      else
        flash["info"] += " Register or login to be able to create it."
      end
    end

    groups_read = Fluence::ACL.groups_having_any_access_to page.url, Acl::Perm::Read, true
    groups_write = Fluence::ACL.groups_having_any_access_to page.url, Acl::Perm::Write, true
    title = "#{page.title} - #{title()}"

    # For menu on the left
    pages = Fluence::PAGES.children1

    render "show.slang"
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

          # The user must be permitted to write at the destination too.
          new_url = "#{Fluence::OPTIONS.pages_prefix}/#{Fluence::Page.sanitize(new_name).strip "/"}"
          unless Fluence::ACL.permitted?(current_user, new_url, Acl::Perm::Write)
            flash["danger"] = "You are not permitted to write to '#{new_url}'."
            redirect_to old_url
            return
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

  private def update_edit(page)
    action = page.exists? ? "updated" : "created"
    page.update! current_user, params.body["body"]
    flash["success"] = %Q(Page '#{page.name}' has been #{action})
    redirect_to page.url
  rescue err
    flash["danger"] = "Error: cannot update #{page.name}, #{err.message}"
    redirect_to page.url
  end

  # get /sitemap
  def sitemap
    acl_permit! :read
    pages = Fluence::PAGES.children1
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
