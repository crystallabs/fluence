class MediaController < ApplicationController
  # get /sitemap
  def sitemap
    acl_permit! :read
    # See PagesController#sitemap, which covers media as well.
  end

  # get /media/search?q=
  def search
    redirect_to "#{Fluence::OPTIONS.homepage}"
  end

  # get /media/*path
  def show
    acl_permit! :read
    page = Fluence::Media.new params.url["path"]
    show_show(page)
  end

  private def show_show(page)
    Fluence::ACL.load!

    unless page.exists?
      @env.response.status_code = 404
      return "Not found: #{page.name}"
    end

    content = page.read
    @env.response.content_type = MIME.from_filename?(page.name) || "application/octet-stream"
    @env.response.write content.to_slice
  end

  # post /media/*path
  def update
    acl_permit! :write
    page = Fluence::Media.new params.url["path"]
    if params.body["rename"]?
      update_rename(page)
    elsif params.body["delete"]?
      update_delete(page)
    else
      update_edit(page)
    end
  end

  private def update_rename(main_page)
    new_main_name = params.body["input-page-name"]?.to_s.strip
    unless new_main_name.empty?
      old_name = main_page.name
      old_url = main_page.url
      begin
        # The user must be permitted to write at the destination too.
        new_url = "#{Fluence::OPTIONS.media_prefix}/#{Fluence::Media.sanitize(new_main_name).strip "/"}"
        unless Fluence::ACL.permitted?(current_user, new_url, Acl::Perm::Write)
          flash["danger"] = "You are not permitted to write to '#{new_url}'."
          redirect_to old_url
          return
        end

        main_page.rename! current_user, new_main_name, !!params.body["input-page-overwrite"]?
        flash["success success-#{old_name}"] = "Media #{old_name} has been renamed to #{main_page.name}"
      rescue e : Fluence::Media::AlreadyExists
        flash["danger danger-#{main_page.name}"] = e.to_s
        redirect_to old_url
        return
      end
    end
    redirect_to main_page.url
  end

  private def update_delete(main_page)
    unless params.body["media-name"]?.to_s.strip.empty?
      begin
        main_page.delete current_user if main_page.exists?
        flash["success success-#{main_page.name}"] = "Media #{main_page.name} has been deleted"
      rescue e
        flash["danger danger-#{main_page.name}"] = e.to_s
        redirect_to main_page.url
        return
      end
    end
    redirect_to "#{Fluence::OPTIONS.homepage}"
  end

  private def update_edit(page)
    action = page.exists? ? "updated" : "created"
    page.update! current_user, params.body["body"]
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
            media.write current_user, part.body
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
