class PagesController < ApplicationController

  # get /pages/*path
  def show
    acl_permit! :read
    flash["danger"] = params.query["flash.danger"] if params.query["flash.danger"]?
    if page = Fluence::PAGES[params.url["path"]]?
      # Page exists in the index
    else
      page = Fluence::Page.new params.url["path"]
      # If page exists but was not found, this is a page someone added from cmdline. Incorporate it.
      if page.exists?
        Fluence::PAGES.transaction! { |index|
          page.process!
          index.add! page
          flash["warning warning-created-externally"] = "Page exists on disk but was not created through the wiki. Processed and added it to the index"
        }
      end
    end
    media = Fluence::MEDIA[page.name]? || Fluence::Media.new page.name

    show_show(page, media)
  end

  private def show_show(page, media)
    if page.exists? && ( ::File.info(page.path).modification_time > page.modification_time)
      Fluence::PAGES.transaction! { |_|
        page.process!
        flash["warning warning-re-process"] = "External modification to page detected. Processing any changes and showing the updated page"
      }
    end

    body = page.read rescue ""
    body_html = body ? Fluence::Markdown.to_html body, page, Fluence::PAGES.load! : ""
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
    page = Fluence::PAGES[params.url["path"]]? || (Fluence::Page.new params.url["path"])
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
    unless params.body["input-page-name"]?.to_s.strip.empty?
      pages = [main_page]
      if params.body["input-page-subtree"]?
        pages += main_page.children.values.map{|v| v[1]}
      end
      # TODO: verify if the user can write on input-page-name
      # TODO: if input-page-name does not begin with /, do relative rename to the current path

      old_main_page_name = main_page.name
      pages.each do |page|
        old_url = page.url
        begin
          old_name = page.name
          Fluence::PAGES.transaction! { |index|
            new_name = page.name.sub /^#{old_main_page_name}/, params.body["input-page-name"]
            old_path = page.path

            page.rename! current_user, new_name, !!params.body["input-page-overwrite"]?, subtree: false, intlinks: !!params.body["input-page-intlinks"]?
            index.rename old_name, page
            Fluence::Page.remove_empty_directories old_path
          }
          flash["success success-#{old_name}"] = "Page '#{old_name}' has been renamed to '#{page.name}'"
        rescue e : Fluence::Page::AlreadyExists
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
        pages += main_page.children.values.map{|v| v[1]}
      end

      pages.each do |page|
        begin
          Fluence::PAGES.transaction! { |index|
            index.delete page
            page.delete current_user if page.exists?
            Fluence::Page.remove_empty_directories page.path
          }
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
    Fluence::PAGES.transaction! { |index|
      page.update! current_user, params.body["body"]
      unless Fluence::PAGES[page]?
        index.add! page
      end
    }
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
    #if query = params.query["q"]
    # page = Fluence::Page.new(query.not_nil!)
    # # TODO: a real search
    #end
    #page = nil
    #title = "Search Results - #{title()}"
    #redirect_to (query.empty? || !page) ? "#{Fluence::OPTIONS.homepage}" : page.url
    redirect_to "#{Fluence::OPTIONS.homepage}"
  end
end
