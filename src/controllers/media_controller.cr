class MediaController < ApplicationController
  # get /sitemap
  def sitemap
    acl_permit! :read
    # pages = Fluence::FileTree.build Fluence::Page.subdirectory
    # media = Fluence::FileTree.build Fluence::Media.subdirectory
    #title = "Sitemap - #{title()}"
    # render "sitemap.slang"
  end

  # get /pages/search?q=
  def search
    # if query = params.query["q"]
    # page = Fluence::Media.new(query.not_nil!)
    # # TODO: a real search
    # end
    #page = nil
    #title = "Search Results - #{title()}"
    # redirect_to (query.empty? || !page) ? "#{Fluence::OPTIONS.homepage}" : page.url
    redirect_to "#{Fluence::OPTIONS.homepage}"
  end

  # get /pages/*path
  def show
    acl_permit! :read
    flash["danger"] = params.query["flash.danger"] if params.query["flash.danger"]?
    if page = Fluence::MEDIA[params.url["path"]]?
      # Page exists in the index
    else
      page = Fluence::Media.new params.url["path"]
      # If page exists but was not found, this is a page someone added from cmdline. Incorporate it.
      if page.exists?
        Fluence::MEDIA.transaction! { |index|
          page.process!
          index.add! page
          flash["warning warning-created-externally"] = "Page exists on disk but was not created through the wiki. Processed and added it to the index"
        }
      end
    end
    show_show(page)
  end

  private def show_show(page)
    if page.exists? && (::File.info(page.path).modification_time > page.modification_time)
      Fluence::MEDIA.transaction! { |_|
        page.process!
        STDERR.puts "External modification to #{page.path} detected. Processing any changes"
      }
    end

    #body = page.read rescue ""
    Fluence::ACL.load!

    if !page.exists?
      # 404
    end

    send_file @env, page.path
  end

  # post /pages/*path
  def update
    acl_permit! :write
    page = Fluence::MEDIA[params.url["path"]]? || (Fluence::Media.new params.url["path"])
    if params.body["rename"]?
      update_rename(page)
    elsif params.body["delete"]?
      update_delete(page)
      # We do not want empty body to mean page deletion.
      # elsif (params.body["body"]?.to_s.empty?)
      #  update_delete(page)
    else
      update_edit(page)
    end
  end

  private def update_rename(main_page)
    unless params.body["input-page-name"]?.to_s.strip.empty?
      pages = [main_page]
      if params.body["input-page-subtree"]?
        pages += main_page.children.values.map { |v| v[1] }
      end
      # TODO: verify if the user can write on input-page-name
      # TODO: if input-page-name does not begin with /, do relative rename to the current path

      old_main_page_name = main_page.name
      pages.each do |page|
        old_url = page.url
        begin
          old_name = page.name
          Fluence::MEDIA.transaction! { |index|
            new_name = page.name.sub /^#{old_main_page_name}/, params.body["input-page-name"]
            old_path = page.path

            page.rename! current_user, new_name, !!params.body["input-page-overwrite"]?
            index.rename old_name, page
            Fluence::Media.remove_empty_directories old_path
          }
          flash["success success-#{old_name}"] = "Media #{old_name} has been renamed to #{page.name}"
        rescue e : Fluence::Media::AlreadyExists
          flash["danger danger-#{page.name}"] = e.to_s
          redirect_to old_url
          return
        end
      end
    end
    redirect_to main_page.url
  end

  private def update_delete(main_page)
    unless params.body["media-name"]?.to_s.strip.empty?
      pages = [main_page]
      if params.body["input-page-subtree"]?
        pages += main_page.children.values.map { |v| v[1] }
      end

      pages.each do |page|
        begin
          Fluence::MEDIA.transaction! { |index|
            index.delete page
            page.delete current_user if page.exists?
            Fluence::Media.remove_empty_directories page.path
          }
          flash["success success-#{page.name}"] = "Media #{page.name} has been deleted"
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
    Fluence::MEDIA.transaction! { |index|
      page.update! current_user, params.body["body"]
      unless Fluence::MEDIA[page]?
        index.add! page
      end
    }
    flash["success"] = %Q(Media #{page.name} has been #{action})
    redirect_to page.url
  rescue err
    flash["danger"] = "Error: cannot update #{page.name}, #{err.message}"
    redirect_to page.url
  end

  # post /media/upload
  def upload
    data = {} of String => String

    @env.response.content_type = "application/json"
    ret = {success: true}

    HTTP::FormData.parse(@env.request) do |part|
      case part.name
      when "qqpagename"
        data["qqpagename"] = part.body.gets_to_end
        page_path = File.join Fluence::OPTIONS.pages_prefix, data["qqpagename"]
        if !Fluence::ACL.permitted?(current_user, page_path, Acl::Perm::Write)
          ret = {success: false, error: "You are not permitted to access this resource (#{page_path}, write)."}
        end
      when "qqfilename"
        if ret[:success]
          data[part.name] = Fluence::Media.sanitize(part.body.gets_to_end).strip "/"
        end
      when "qqfile"
        if ret[:success]
          if !data["qqpagename"]
            flash["danger"] = %Q(No data["qqpagename"] included in upload, please try again)
            redirect_to Fluence::Page.new(data["qqpagename"]).url
            return
          else
            media = Fluence::Media.new %Q(#{data["qqpagename"]}/#{data["qqfilename"]})
            media.jail!

            #action = "added"
            Fluence::MEDIA.transaction! { |index|
              #Dir.mkdir_p ::File.dirname media.path
              #File.open(media.path, "w") do |f|
              #  IO.copy(part.body, f)
              #end
              media.write current_user, part.body

              media.process!

              unless Fluence::MEDIA[media]?
                index.add! media
              end
            }
          end
        end
      else
        if ret[:success]
          data[part.name] = part.body.gets_to_end
        end
      end
    end

    ret.to_json
  end
end
