require "uri"
require "kemal"
require "kemal-session"
require "kemal-session-bcdb"
require "./init"
require "compress/zip"
require "./backend"
require "crystalstore"
require "./auth"
require "./errors"
require "./docserver"

include CrystalDrive::Init
include CrystalDrive::DocServer

HOME = File.read("public/static/index.html").
  gsub("[{[ .StaticURL ]}]", "/static").
  gsub(%([{[ if .ReCaptcha -]}]<script src="[{[ .ReCaptchaHost ]}]/recaptcha/api.js?render=explicit"></script>[{[ end ]}]), "").
  gsub(%([{[ if .Name -]}][{[ .Name ]}][{[ else ]}]File Browser[{[ end ]}]), "Threefold Filemanager").
  gsub(%([{[ if .Theme -]}]<link rel=stylesheet href="/static/themes/[{[ .Theme ]}].css">[{[ end ]}] [{[ if .CSS -]}]<link rel=stylesheet href="/static/custom.css">[{[ end ]}]), "").
  gsub(%(name=viewport), %(name="viewport")).
  gsub(%(<link rel=manifest id=manifestPlaceholder crossorigin=use-credentials>), %(<link rel="manifest" id="manifestPlaceholder" crossorigin="use-credentials">)).
  gsub(%(name=msapplication-TileImage), %(name="msapplication-TileImage")).
  gsub(%(fullStaticURL + ), "").
  gsub(%(name=msapplication-TileColor content=#2979ff), %(name="msapplication-TileColor" content="#2979ff")).
  gsub(%([{[ .ONLY_OFFICE_URL ]}]), ENV["ONLY_OFFICE_HOST"]).
  gsub(%(`[{[ .Json ]}]`), %(`{
    "AuthMethod": "json",
    "BaseURL": "",
    "CSS": false,
    "DisableExternal": false,
    "LoginPage": true,
    "Name": "",
    "NoAuth": false,
    "ReCaptcha": false,
    "Signup": false,
    "StaticURL": "/static",
    "Version": "0.1"}`))


private def zip_files(files : Array(String))
  path = ""
  File.tempfile("zipfile") do |file|
      path = file.path
      Compress::Zip::Writer.open(file) do |zip|
      files.each do |file|
        stats = CrystalDrive::Backend.file_stats("",file)
        f = CrystalDrive::Backend.file_open(file, 755)
        s = Bytes.new(stats.size)
        f.read s
        data = String.new s
        f.close
        zip.add file, data
      end
    end
  end
  return path
end

# recursively get all files in a path
private def list_files(env, files : Array(String), all_files : Array(String) = Array(String).new)
  files.each do |path|
      path = URI.decode(path)
      path = prefix_paths(env, path)
      begin
        list = CrystalDrive::Backend.list(path)
        files = [] of String
        dirs = [] of String
        
        list.items.each do |item|
          if item.is_dir
            dirs << Path.new(path, item.path).to_s
          else
            files << Path.new(path, item.path).to_s
          end
        end

        all_files += files
        list_files(env, dirs, all_files)
      rescue CrystalStore::FileNotFoundError
        all_files.push(path)
    end
  end
    all_files
end

# prefix all paths with user dir
private def prefix_paths(env, path)
  is_dir = path.ends_with?("/")
  parts = Path.new(path).parts
  shared = false

  if parts.size > 1 && parts[1] == "shared"
    shared = true
    parts[1] = CrystalDrive::Backend.get_shared_with_me_dirname
  end
  path = Path.new(parts).to_s
  if is_dir
    path = "#{path}/"
  end

  if shared && parts.size > 4
    return path.sub("/#{CrystalDrive::Backend.get_shared_with_me_dirname}", "")
  end

  %(/#{env.session.string("username")}#{path})
end

private def has_permissions?(username : String, path : String, permission : String)
  CrystalDrive::Backend.has_permission?(username, path, permission)
end

before_all "/api/*" do |env|
  if env.session.string?("username").nil?
    if !env.params.query.has_key?("auth")
      halt env, status_code: 403, response: "403 Forbidden"
    else
      begin
        username = CrystalDrive::Token.get_usermame(env.params.query["auth"])
        env.session.string("username", username.to_s)
      rescue exception
        halt env, status_code: 403, response: "403 Forbidden"
      end 
    end
  end
end

# Home
get "/" do |env|
  env.response.content_type = "text/html"
  HOME  
end

# Home
get "/files" do |env|
  env.response.content_type = "text/html"
  HOME  
end

# Home
get "/files/*" do |env|
  env.response.content_type = "text/html"
  HOME
end

# Home
get "/login/callback/*" do |env|
  env.response.content_type = "text/html"
  HOME
end

# Home
get "/login/" do |env|
  env.response.content_type = "text/html"
  HOME
end

# API Login (Dev only)
post "/api/login" do |env|
  env.response.content_type = "cty"
  begin
    env_mode = ENV["DEV_MODE"]
  rescue exception
    halt env, status_code: 403, response: "403 Forbidden"
  end

  username = "h4mdy"
  email = "kk@sd.com"
  token = CrystalDrive::Token.generate_token(username, email, "en", "mosaic", {"admin" => true, "execute" => true, "create" => true, "rename" => true, "modify" => true, "delete" => true,  "share" => true, "download"=> true}, false, Array(String).new)
  env.session.string("token", token)
  env.session.string("username", username)
  env.session.string("email", email)

  begin
      CrystalDrive::Backend.dir_create(username, 755)
  rescue CrystalStore::FileExistsError
  end

  begin
      CrystalDrive::Backend.create_shared_withme_dir(username)
  rescue CrystalStore::FileExistsError
  end
  token
end

# Renew
post "/api/renew" do |env|
  env.response.content_type = "cty"
  current_token = env.session.string?("token")
  current_user = env.session.string?("username")
  current_email = env.session.string?("email")

  if !env.request.headers.has_key?("X-Auth")
    halt env, status_code: 403, response: "403 Forbidden"
  end
  provided_token = env.request.headers["X-Auth"]
  
  if !CrystalDrive::Token.is_valid? provided_token.not_nil!, current_user, current_email
    halt env, status_code: 403, response: "403 Forbidden"
  end
  
  
  viewmode = env.session.string?("viewmode")
  if viewmode.nil?
    viewmode = "mosaic"
  end

  token = CrystalDrive::Token.generate_token(current_user, current_email, "en", viewmode, {"admin" => true, "execute" => true, "create" => true, "rename" => true, "modify" => true, "delete" => true,  "share" => true, "download"=> true}, false, Array(String).new)
  env.session.string("token", token)
  token
end

# list or stats
get "/api/resources/*" do |env|
  orig_path = URI.decode(env.request.path.gsub("/api/resources", ""))
  path = prefix_paths(env, orig_path)
  
  if !has_permissions?(env.session.string("username"), path, "r")
    halt env, status_code: 403, response: "Permission denied"
  end

  list = false

  if env.request.path.ends_with?('/')
    list = true
  end
  
  env.response.content_type = "application/json; charset=utf-8"
  env.response.headers["X-Renew-Token"] =  "true"

  if list
    begin
      CrystalDrive::Backend.list(path).to_json
    rescue CrystalStore::FileNotFoundError
      halt env, status_code: 404, response: "Not found"
    end
  else
    stats = CrystalDrive::Backend.file_stats(orig_path, path)
    if stats.itemType == "text"
      f = CrystalDrive::Backend.file_open(path, 755)
      s = Bytes.new(stats.size)
      f.read s
      stats.content = String.new s
    end
    stats.to_json
  end
end

# Create dir / file
post "/api/resources/*" do |env|
  path = env.request.path.gsub("/api/resources", "")
  item = URI.decode(path)
  item = prefix_paths(env, item)
  
  if !has_permissions?(env.session.string("username"), item, "w")
    halt env, status_code: 403, response: "Permission denied"
  end

  override = env.params.query.has_key?("override") ? true : false

  if item.ends_with?("/")
    begin
      CrystalDrive::Backend.dir_create(item, 755, create_parents=true)
    rescue CrystalStore::FileExistsError; 
      if ! override
        halt env, status_code: 409, response: "Already exists"
      else
        env.response.content_type = "text/plain; charset=utf-8"
        env.response.headers["X-Content-Type-Options"] ="nosniff"
      end
    end
  else    
    env.response.content_type = "text/plain; charset=utf-8"
    env.response.headers["X-Content-Type-Options"] ="nosniff"
    content_type = "application/octet-stream"
    if env.request.headers.has_key?("Content-Type")
      content_type = env.request.headers["Content-Type"]
    end

    begin
      CrystalDrive::Backend.file_create(item, 755, content_type, create_parents=true)
    rescue CrystalStore::FileExistsError
      if !override
        halt env, status_code: 409, response: "Already exists"
      end
    end
    
    f = CrystalDrive::Backend.file_open item, 755
    f.set_conten_type content_type
    IO.copy(env.request.body.not_nil!, f)
    f.close
    env.response.headers["Etag"] = "15bed3cb4c34f4360"
  end
end


# Delete Dir / file
delete "/api/resources/*" do |env|
  path = URI.decode(env.request.path.gsub("/api/resources", ""))
  path = prefix_paths(env, path)

  if !has_permissions?(env.session.string("username"), path, "d")
    halt env, status_code: 403, response: "Permission denied"
  end

  env.response.content_type = "text/plain; charset=utf-8"
  env.response.headers["X-Renew-Token"] = "true"
  env.response.headers["X-Content-Type-Options"] ="nosniff"
  
  parts = Path.new(path).parts

  if path.includes?(CrystalDrive::Backend.get_shared_with_me_dirname) && parts.size > 4
    begin
      CrystalDrive::Backend.link_delete(path)
    rescue CrystalStore::FileNotFoundError
      halt env, status_code: 409, response: "Link not found"
    end
  
  elsif path.ends_with?("/")
    begin
      CrystalDrive::Backend.dir_delete(path)
    rescue CrystalStore::FileNotFoundError
      halt env, status_code: 409, response: "Dir not found"
    end
  else
    begin
      CrystalDrive::Backend.file_delete(path)
    rescue CrystalStore::FileNotFoundError
      halt env, status_code: 409, response: "File not found"
    end
  end
end

# Copy,  rename, move Dir / file
patch "/api/resources/*" do |env|
  src = URI.decode(env.request.path.gsub("/api/resources", ""))
  src = prefix_paths(env, src)
  dest = URI.decode(env.params.query["destination"])
  dest = prefix_paths(env, dest)

  action = env.params.query["action"]
  env.response.content_type = "text/plain; charset=utf-8"
  env.response.headers["X-Renew-Token"] = "true"
  env.response.headers["X-Content-Type-Options"] ="nosniff"
  
  if src.ends_with?("/")
    begin
      if action == "copy"
        if !has_permissions?(env.session.string("username"), src, "r")
          halt env, status_code: 403, response: "Permission denied"
        end
      
        if !has_permissions?(env.session.string("username"), dest, "w")
          halt env, status_code: 403, response: "Permission denied"
        end

        CrystalDrive::Backend.dir_copy(src, dest)
      elsif action == "rename" || action == "move"
        if !has_permissions?(env.session.string("username"), src, "r")
          halt env, status_code: 403, response: "Permission denied"
        end
      
        if action == "rename"
          if !has_permissions?(env.session.string("username"), src, "rw")
            halt env, status_code: 403, response: "Permission denied"
          end
        end

        if action == "move"
          if !has_permissions?(env.session.string("username"), src, "rd")
            halt env, status_code: 403, response: "Permission denied"
          end
          if !has_permissions?(env.session.string("username"), dest, "w")
            halt env, status_code: 403, response: "Permission denied"
          end
        end
        CrystalDrive::Backend.dir_move(src, dest)
      end
    rescue ex1: CrystalStore::FileNotFoundError
      halt env, status_code: 409, response: "Not found"
    rescue ex2:  CrystalStore::FileExistsError
      halt env, status_code: 409, response: "Already exists"
    end
  else
    begin
      if action == "copy"
        CrystalDrive::Backend.file_copy(src, dest)
      elsif action == "rename" || action == "move"
        CrystalDrive::Backend.file_move(src, dest)
      end
    rescue ex1: CrystalStore::FileNotFoundError
      halt env, status_code: 409, response: "Not found"
    rescue ex2:  CrystalStore::FileExistsError
      halt env, status_code: 409, response: "Already exists"
    end
  end 
end

# update file
put "/api/resources/*" do |env|
  file = URI.decode(env.request.path.sub("/api/resources", ""))
  file = prefix_paths(env, file)
  if !has_permissions?(env.session.string("username"), file, "w")
    halt env, status_code: 403, response: "Permission denied"
  end

  env.response.content_type = "text/plain; charset=utf-8"
  env.response.headers.add("X-Renew-Token", "true")
  env.response.headers.add("X-Content-Type-Options", "nosniff")

  exists = CrystalDrive::Backend.file_exists? file

  if ! exists
    halt env, status_code: 409, response: "not found"
  end

  CrystalDrive::Backend.file_delete(file)
  CrystalDrive::Backend.file_create(file, 755, "text/html")
  f = CrystalDrive::Backend.file_open file, 755
  IO.copy(env.request.body.not_nil!, f)
  f.close
end

# download files
get "/api/raw/" do |env|
  algorithm = "zip"
  
  files = env.params.query["files"]
  files = files.split(',')
  all_files = list_files(env, files)
  
  filename = ""
  content_type = ""

  if algorithm == "zip"
      zipped = zip_files(all_files)
      filename = "filemanager.zip"
      content_type = "application/zip"
      #TODO: uncomment for frontend
      # context.response.headers.add("Transfer-Encoding", "chunked")
      env.response.headers["Content-Disposition"] = "attachment; filename*=utf-8 " + filename
      env.response.headers["X-Renew-Token"] = "true"
      env.response.headers["Content-Type"] = content_type
      file = File.read(zipped)
      
  end
end

# Download_file
get "/api/raw/*" do |env|
  orig_path = URI.decode(env.request.path.gsub("/api/raw", ""))
  path = prefix_paths(env, orig_path)

  if !has_permissions?(env.session.string("username"), path, "r")
    halt env, status_code: 403, response: "Permission denied"
  end

  if path.ends_with?('/')
      env.response.status_code = 302
      env.response.headers.add("Location", "/api/raw/?files=" + path)
  else
      inline = env.params.query.has_key?("inline") == true
      stats = CrystalDrive::Backend.file_stats(orig_path, path)
      if inline
          env.response.headers["Content-Disposition"] = "inline"
          env.response.headers["Accept-Ranges"] = "bytes"
      else
        env.response.headers["Content-Disposition"] = "attachment; filename*=utf-8 " + stats.name
      end
      env.response.content_type = ""
      env.response.headers["X-Renew-Token"] = "true"
      
      f = CrystalDrive::Backend.file_open(path, 755)
      s = Bytes.new(stats.size)
      f.read s
      f.close
      send_file  env, s, filename: f.filename, disposition: "attachment"
  end
end

get "/api/preview/thumb/*" do |env|
  path = URI.decode(env.request.path.gsub("/api/preview/thumb", ""))
  path = prefix_paths(env, path)

  if !has_permissions?(env.session.string("username"), path, "r")
    halt env, status_code: 403, response: "Permission denied"
  end

  f = CrystalDrive::Backend.file_open(path, 755)
  s = Bytes.new(f.file.meta.not_nil!.size)
  f.read s
  f.close
  env.response.headers["Content-Disposition"] = "inline"
  env.response.content_length = f.file.meta.not_nil!.size
  send_file  env, s, filename: f.filename, disposition: "inline", mime_type:  f.content_type
end

get "/api/preview/big/*" do |env|
  path = URI.decode(env.request.path.gsub("/api/preview/big", ""))
  path = prefix_paths(env, path)
  
  if !has_permissions?(env.session.string("username"), path, "r")
    halt env, status_code: 403, response: "Permission denied"
  end

  f = CrystalDrive::Backend.file_open(path, 755)
  s = Bytes.new(f.file.meta.not_nil!.size)
  f.read s
  f.close
  env.response.headers["Content-Disposition"] = "inline"
  env.response.content_length = f.file.meta.not_nil!.size
  
  send_file  env, s, filename: f.filename, disposition: "inline", mime_type: f.content_type
end

put "/api/users/:username" do |env|
  if env.session.string?("username") != env.params.url["username"]
    halt env, status_code: 403, response: "403 Forbidden"
  end
  
  begin
    vm =  env.session.string?("viewmode")
    
    if vm == "mosaic"
      vm = "list"
    else
      vm = "mosaic"
    end
    env.session.string("viewmode", vm)

  rescue exception
    halt env, status_code: 409, response: "ca not update user settings"
  end
  env.response.headers.add("X-Content-Type-Options", "nosniff")
end

# add/update permissions
post "/api/share/*" do |env|
  file = URI.decode(env.request.path.sub("/api/share", ""))
  file = prefix_paths(env, file)
  env.response.content_type = "text/plain; charset=utf-8"
  env.response.headers.add("X-Renew-Token", "true")
  env.response.headers.add("X-Content-Type-Options", "nosniff")

  is_file = CrystalDrive::Backend.file_exists? file
  is_dir = CrystalDrive::Backend.dir_exists? file

  if ! is_file && ! is_dir
    halt env, status_code: 409, response: "not found"
  end

  shares = Hash(String, Hash(String, String)).new
  env.params.json["_json"].as(Array).each do |item|
    v = Hash(String, String).new
    v["user"] = item["permission"].to_s
    shares[item["name"].to_s] = v 
  end
  # only return user share info in this case
  res = Hash(String, String).new
  share_info = CrystalDrive::Backend.share(file, env.session.string("username"), shares)
  share_info.each do |name, v|
    if v.has_key?("user")
      res[name] = v["user"]
    end
  end
  res.to_json
end

get "/api/share/*" do |env|
  file = URI.decode(env.request.path.sub("/api/share", ""))
  file = prefix_paths(env, file)
  env.response.content_type = "text/plain; charset=utf-8"
  env.response.headers.add("X-Renew-Token", "true")
  env.response.headers.add("X-Content-Type-Options", "nosniff")

  is_file = CrystalDrive::Backend.file_exists? file
  is_dir = CrystalDrive::Backend.dir_exists? file

  if ! is_file && ! is_dir
    halt env, status_code: 409, response: "not found"
  end

  begin
    share = CrystalDrive::Backend.share_get(file)
    result = Array(Hash(String, String)).new
    share.permissions.each do |k, v|
      if v.has_key?("user")
        result << {"name" => k, "permission" => v["user"]}
      end
    end
    result.to_json
  rescue CrystalDrive::UserNotFoundError
    halt env, status_code: 409, response: "not found"
  end
end

delete "/api/share/*" do |env|
  file = URI.decode(env.request.path.sub("/api/share", ""))
  file = prefix_paths(env, file)
  env.response.content_type = "text/plain; charset=utf-8"
  env.response.headers.add("X-Renew-Token", "true")
  env.response.headers.add("X-Content-Type-Options", "nosniff")

  is_file = CrystalDrive::Backend.file_exists? file
  is_dir = CrystalDrive::Backend.dir_exists? file

  if ! is_file && ! is_dir
    halt env, status_code: 409, response: "not found"
  end
    CrystalDrive::Backend.share_delete(file, env.session.string("username"), "user")
end

# Create a sharing link
get "/api/share/link/*" do |env|
  path = URI.decode(env.request.path.sub("/api/share/link", ""))
  file = prefix_paths(env, path)
  env.response.content_type = "application/json"
  env.response.headers.add("X-Renew-Token", "true")
  env.response.headers.add("X-Content-Type-Options", "nosniff")

  is_file = CrystalDrive::Backend.file_exists? file
  is_dir = CrystalDrive::Backend.dir_exists? file
  
  if !env.params.query.has_key?("permission")
    halt env, status_code: 409, response: "Permission missing"
  end

  if ! is_file && ! is_dir
    halt env, status_code: 409, response: "not found"
  end

  begin
    res = CrystalDrive::Backend.share_link_get(file, env.params.query["permission"].as(String), env.session.string("username"))
    res["path"] = path
    res.to_json
  rescue CrystalDrive::NotFoundError
    halt env, status_code: 409, response: "not found"
  end
end

# list sharing links
get "/api/share/links/*" do |env|
  path = URI.decode(env.request.path.sub("/api/share/links", ""))
  file = prefix_paths(env, path)
  env.response.content_type = "application/json"
  env.response.headers.add("X-Renew-Token", "true")
  env.response.headers.add("X-Content-Type-Options", "nosniff")

  is_file = CrystalDrive::Backend.file_exists? file
  is_dir = CrystalDrive::Backend.dir_exists? file

  if ! is_file && ! is_dir
    halt env, status_code: 409, response: "not found"
  end

  begin
    res = CrystalDrive::Backend.share_links_get(file)
    # put again original path, remove prefix;
    res.each do |item|
      item["path"] = path
    end
    res.to_json
  rescue CrystalDrive::NotFoundError
    halt env, status_code: 409, response: "not found"
  end
end

# delete sharing link
delete "/api/share/link/*" do |env|
  file = URI.decode(env.request.path.sub("/api/share/link", ""))
  file = prefix_paths(env, file)
  env.response.content_type = "text/plain; charset=utf-8"
  env.response.headers.add("X-Renew-Token", "true")
  env.response.headers.add("X-Content-Type-Options", "nosniff")

  is_file = CrystalDrive::Backend.file_exists? file
  is_dir = CrystalDrive::Backend.dir_exists? file

  # empty means delete all
  permission = ""
  if env.params.query.has_key?("permission")
    permission =  env.params.query["permission"]
  end

  if ! is_file && ! is_dir
    halt env, status_code: 409, response: "not found"
  end

  begin
    CrystalDrive::Backend.share_link_delete(file,  permission, env.session.string("username"))
  rescue CrystalDrive::NotFoundError
    halt env, status_code: 409, response: "not found"
  end
end

get "/shared/:hash" do |env|
  env.response.content_type = "text/plain; charset=utf-8"
  env.response.headers.add("X-Renew-Token", "true")
  env.response.headers.add("X-Content-Type-Options", "nosniff")

  begin
    o = CrystalDrive::Backend.share_link_create(env.params.url["hash"], env.session.string("username"))
    # rediect to user shared dir
    env.response.status_code = 302
    env.response.headers.add("Location", "/files/shared/#{o["owner"]}/")
  rescue CrystalDrive::NotFoundError
    halt env, status_code: 404, response: "not found"
  end
end

Kemal.run
