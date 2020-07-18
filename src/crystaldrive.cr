require "uri"
require "kemal"
require "zip"
require "./backend"
require "crystalstore"

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
  gsub(%(`[{[ .Json ]}]`), %(`{
    "BaseURL": "",
    "CSS": false,
    "DisableExternal": false,
    "LoginPage": false,
    "Name": "",
    "NoAuth": true,
    "ReCaptcha": false,
    "Signup": false,
    "StaticURL": "/static",
    "Version": "(untracked)"}`))

TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjp7ImlkIjoxLCJsb2NhbGUiOiJlbiIsInZpZXdNb2RlIjoibW9zYWljIiwicGVybSI6eyJhZG1pbiI6dHJ1ZSwiZXhlY3V0ZSI6dHJ1ZSwiY3JlYXRlIjp0cnVlLCJyZW5hbWUiOnRydWUsIm1vZGlmeSI6dHJ1ZSwiZGVsZXRlIjp0cnVlLCJzaGFyZSI6ZmFsc2UsImRvd25sb2FkIjp0cnVlfSwiY29tbWFuZHMiOltdLCJsb2NrUGFzc3dvcmQiOmZhbHNlfSwiZXhwIjoxNTY2OTEyNzc2MzMsImlhdCI6MTU2NjkwNTU3NiwiaXNzIjoiRmlsZSBCcm93c2VyIn0.GaBiL_MeqDev0695MRqE3RhmGatouIT4BtlvpTI4P1A"

private def zip_files(files : Array(String))
  path = ""
  File.tempfile("zipfile") do |file|
      path = file.path
    Zip::Writer.open(file) do |zip|
      files.each do |file|
        stats = Fileman::Backend.file_stats(file)
        f = Fileman::Backend.file_open(file, 755)
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
private def list_files(files : Array(String), all_files : Array(String) = Array(String).new)
  files.each do |path|
      path = URI.decode(path)
      begin
        list = Fileman::Backend.list(path)
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
        list_files(dirs, all_files)
      rescue CrystalStore::FileNotFoundError
        all_files.push(path)
    end
  end
    all_files
end

# Home
get "/" do |env|
  env.response.content_type = "text/html"
  HOME  
end

# Home
get "/files/*" do |env|
  env.response.content_type = "text/html"
  HOME
end

# Login
post "/api/login" do |env|
  env.response.content_type = "cty"
  TOKEN
end

# Renew
post "/api/renew" do |env|
  env.response.content_type = "cty"
  env.response.headers["X-Renew-Token"] = "true"
  TOKEN
end

# list or stats
get "/api/resources/*" do |env|
  path = URI.decode(env.request.path.gsub("/api/resources", ""))
  list = false

  if env.request.path.ends_with?('/')
    list = true
  end

  
  env.response.content_type = "application/json; charset=utf-8"
  env.response.headers["X-Renew-Token"] =  "true"

  if list 
    Fileman::Backend.list(path).to_json
  else
    stats = Fileman::Backend.file_stats(path)
    if stats.itemType == "text"
      f = Fileman::Backend.file_open(path, 755)
      s = Bytes.new(stats.size)
      f.read s
      stats.content = String.new s
    end
    stats.to_json
  end
end

# Create dir / file
post "/api/resources/*" do |env|
  dir = env.request.path.gsub("/api/resources", "")
  dir = URI.decode(dir)
  override = ! env.get?("override").nil?

  if dir.ends_with?("/")
    begin
      pp! "here"
      Fileman::Backend.dir_create(dir, 755, create_parents=true)
    rescue CrystalStore::FileExistsError; 
      if ! override
        halt env, status_code: 409, response: "Already exists"
      else
        env.response.content_type = "text/plain; charset=utf-8"
        env.response.headers["X-Renew-Token"] = "true"
        env.response.headers["X-Content-Type-Options"] ="nosniff"
      end
    end
  else    
    file = env.request.path.gsub("/api/resources", "")
    file = URI.decode(file)
    override = env.params.query.has_key?("override") ? true : false
    env.response.content_type = "text/plain; charset=utf-8"
    env.response.headers["X-Renew-Token"] = "true"
    env.response.headers["X-Content-Type-Options"] ="nosniff"
    
    content_type = "application/octet-stream"
    if env.request.headers.has_key?("Content-Type")
      content_type = env.request.headers["Content-Type"]
    end

    begin
      Fileman::Backend.file_create(file, 755, content_type, create_parents=true)
    rescue CrystalStore::FileExistsError
      if !override
        halt env, status_code: 409, response: "Already exists"
      end
    end
    
    f = Fileman::Backend.file_open file, 755
    f.set_conten_type content_type
    IO.copy(env.request.body.not_nil!, f)
    f.close
    env.response.headers["Etag"] = "15bed3cb4c34f4360"
  end
end


# Delete Dir / file
delete "/api/resources/*" do |env|
  path = URI.decode(env.request.path.gsub("/api/resources", ""))
  env.response.content_type = "text/plain; charset=utf-8"
  env.response.headers["X-Renew-Token"] = "true"
  env.response.headers["X-Content-Type-Options"] ="nosniff"
  if path.ends_with?("/")
    begin
      Fileman::Backend.dir_delete(path)
    rescue CrystalStore::FileNotFoundError
      halt env, status_code: 409, response: "Dir not found"
    end
  else
    begin
      Fileman::Backend.file_delete(path)
    rescue CrystalStore::FileNotFoundError
      halt env, status_code: 409, response: "File not found"
    end
  end
end

# Copy,  rename, move Dir / file
patch "/api/resources/*" do |env|
  src = URI.decode(env.request.path.gsub("/api/resources", ""))
  dest = URI.decode(env.params.query["destination"])
  action = env.params.query["action"]
  env.response.content_type = "text/plain; charset=utf-8"
  env.response.headers["X-Renew-Token"] = "true"
  env.response.headers["X-Content-Type-Options"] ="nosniff"
  
  if src.ends_with?("/")
    begin
      if action == "copy"
        Fileman::Backend.dir_copy(src, dest)
      elsif action == "rename" || action == "move"
        Fileman::Backend.dir_move(src, dest)
      end
    rescue ex1: CrystalStore::FileNotFoundError
      halt env, status_code: 409, response: "Not found"
    rescue ex2:  CrystalStore::FileExistsError
      halt env, status_code: 409, response: "Already exists"
    end
  else
    begin
      if action == "copy"
        Fileman::Backend.file_copy(src, dest)
      elsif action == "rename" || action == "move"
        Fileman::Backend.file_move(src, dest)
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
  env.response.content_type = "text/plain; charset=utf-8"
  env.response.headers.add("X-Renew-Token", "true")
  env.response.headers.add("X-Content-Type-Options", "nosniff")

  exists = Fileman::Backend.file_exists? file

  if ! exists
    halt env, status_code: 409, response: "not found"
  end

  Fileman::Backend.file_delete(file)
  Fileman::Backend.file_create(file, 755, "text/html")
  f = Fileman::Backend.file_open file, 755
  puts env.request.body.to_s
  IO.copy(env.request.body.not_nil!, f)
  f.close
end

# download files
get "/api/raw/" do |env|
  algorithm = "zip"
  
  files = env.params.query["files"]
  files = files.split(',')
  all_files = list_files(files)
  
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
  path = URI.decode(env.request.path.gsub("/api/raw", ""))
  if path.ends_with?('/')
      env.response.status_code = 302
      env.response.headers.add("Location", "/api/raw/?files=" + path)
  else
      inline = env.params.query.has_key?("inline") == true
      stats = Fileman::Backend.file_stats(path)
      if inline
          env.response.headers["Content-Disposition"] = "inline"
          env.response.headers["Accept-Ranges"] = "bytes"
      else
        env.response.headers["Content-Disposition"] = "attachment; filename*=utf-8 " + stats.name
      end
      env.response.content_type = ""
      env.response.headers["X-Renew-Token"] = "true"
      
      f = Fileman::Backend.file_open(path, 755)
      s = Bytes.new(stats.size)
      f.read s
      f.close
      send_file  env, s, filename: f.filename, disposition: "attachment"
  end
end

get "/api/preview/thumb/*" do |env|
  path = URI.decode(env.request.path.gsub("/api/preview/thumb", ""))
  f = Fileman::Backend.file_open(path, 755)
  s = Bytes.new(f.file.meta.not_nil!.size)
  f.read s
  f.close
  env.response.headers["Content-Type"] = f.content_type
  env.response.headers["Content-Disposition"] = "inline"
  env.response.content_length = f.file.meta.not_nil!.size
  
  send_file  env, s, filename: f.filename, disposition: "inline"
end

get "/api/preview/big/*" do |env|
  path = URI.decode(env.request.path.gsub("/api/preview/big", ""))
  f = Fileman::Backend.file_open(path, 755)
  s = Bytes.new(f.file.meta.not_nil!.size)
  f.read s
  f.close
  env.response.headers["Content-Type"] = f.content_type
  env.response.headers["Content-Disposition"] = "inline"
  env.response.content_length = f.file.meta.not_nil!.size
  
  send_file  env, s, filename: f.filename, disposition: "inline"
end

# workaround until kemal really supports 0.35
class HTTP::Server::Response
  class Output
    # original definition since Crystal 0.35.0
    def close
      return if closed?

      unless response.wrote_headers?
        response.content_length = @out_count
      end

      ensure_headers_written

      super

      if @chunked
        @io << "0\r\n\r\n"
        @io.flush
      end
    end

    # patch from https://github.com/kemalcr/kemal/pull/576
    def close
      # ameba:disable Style/NegatedConditionsInUnless
      unless response.wrote_headers? && !response.headers.has_key?("Content-Range")
        response.content_length = @out_count
      end

      ensure_headers_written

      previous_def
    end
  end
end

Kemal.run
