require "http/client"

module CrystalDrive::DocServer
    private def save_file(url, filename)
        HTTP::Client.get(url) do |response|
          File.write(filename, response.body_io)
        end
      end
      
      post "/docserver/callback" do |env|
        if env.params.json.has_key? "status"
          if env.params.json["status"].to_s.to_i32 == 2
            save_file(env.params.json["url"].to_s, env.params.json["filename"].to_s)
          end
        end
        { "error" =>  0 }.to_json
      end      
end
