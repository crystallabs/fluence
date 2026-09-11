class MediaController < ApplicationController
  # get /media/*path
  def show
    page = Fluence::Media.new params.url["path"]
    acl_permit! :read, page.url
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
    page = Fluence::Media.new params.url["path"]
    acl_permit! :write, page.url
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
      rescue e : Fluence::Media::AlreadyExists | Fluence::Error409
        flash["danger danger-#{main_page.name}"] = e.to_s
        redirect_to old_url
        return
      end
    end
    redirect_to main_page.url
  end

  # Deletes the attachment. Answers JSON ({success} or {success, error})
  # when the client asks for it (Accept: application/json), as the
  # attachment list on a page does; otherwise redirects back to the page
  # the attachment belongs to.
  private def update_delete(media)
    error = nil
    unless params.body["media-name"]?.to_s.strip.empty?
      begin
        media.delete current_user if media.exists?
      rescue e
        error = e.to_s
      end
    end

    if request.headers["Accept"]?.try &.includes?("application/json")
      @env.response.content_type = "application/json"
      return (error ? {success: false, error: error} : {success: true}).to_json
    end
    if error
      flash["danger danger-#{media.name}"] = error
    else
      flash["success success-#{media.name}"] = "Media #{media.name} has been deleted"
    end
    redirect_to owner_page_url(media)
  end

  # URL of the page an attachment ("<page name>/<file name>") belongs to.
  private def owner_page_url(media) : String
    dir = ::File.dirname media.name
    dir == "." ? Fluence::OPTIONS.homepage : "#{Fluence::OPTIONS.pages_prefix}/#{dir}"
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
  #
  # Multipart body with a "pagename" field (the page the attachment belongs
  # to) followed by a "file" part. Returns JSON: {success, name, url} or
  # {success, error}.
  def upload
    @env.response.content_type = "application/json"
    pagename = ""
    saved = nil
    error = nil

    uses_login_cookies
    HTTP::FormData.parse(@env.request) do |part|
      case part.name
      when "pagename"
        # The page's canonical name and URL are what the permission and
        # the storage location are based on, not the name as typed.
        begin
          page = Fluence::Page.new part.body.gets_to_end
        rescue Fluence::Error403
          error = "Invalid page name."
          next
        end
        pagename = page.name
        unless Fluence::ACL.permitted?(current_user, page.url, Acl::Perm::Write)
          error = "You are not permitted to access this resource (#{page.url}, write)."
        end
      when "file"
        next if error
        filename = Fluence::Media.sanitize(part.filename.to_s).strip "/"
        if pagename.empty? || filename.empty?
          error = "Upload is missing the page name or file name."
          next
        end
        begin
          media = Fluence::Media.new "#{pagename}/#{filename}"
          media.write current_user, part.body
          saved = media
        rescue e : Fluence::Error403 | Fluence::Error409
          error = e.message
        end
      end
    end

    if error
      {success: false, error: error}.to_json
    elsif media = saved
      {success: true, name: media.title || media.name, url: media.url}.to_json
    else
      {success: false, error: "No file was uploaded."}.to_json
    end
  end
end
