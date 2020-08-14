require "json"
require "time"
require "msgpack"
require "bcdb"
require "./errors"
require "uuid"

class CrystalDrive::Model
    include MessagePack::Serializable

    def dumps
        io = IO::Memory.new
        self.to_msgpack(io)
        io.to_s
    end

    def self.loads(msgpack : String?)
        self.from_msgpack(msgpack.not_nil!.to_slice)
    end

    def self.get(db : Bcdb::Client, id : UInt64)
        begin
            self.loads(db.get(id.to_i32)["data"].as(String))
        rescue Bcdb::NotFoundError
            raise CrystalStore::FileNotFoundError.new "#{id.to_s} does not exist"
        end
    end

end

class CrystalDrive::AuthUser < CrystalDrive::Model

    property id : UInt64?
    property email : String
    property username : String

    def initialize(@username, @email); end

    def self.get(db : Bcdb::Client, username : String)
        ids = db.find({"username" => username})
        if ids.size == 0
           raise  CrystalDrive::UserNotFoundError.new
        end
        self.get(db, ids[0].to_u64)
    end

    def save(db : Bcdb::Client)
        begin
            CrystalDrive::AuthUser.get(db, @username)
        rescue exception
            id = db.put(self.dumps)
            db.update(id, self.dumps, {"userid" => id.to_s, "username" => @username})
        end
    end
end

class CrystalDrive::Share < CrystalDrive::Model
    include JSON::Serializable

    property permissions : Hash(String, String) # user_name => permission
    property path : String
    property id : UInt64? = nil

    def initialize(
        @path,
        @permissions,
    )
    end

    def self.get(db : Bcdb::Client, path : String)
        ids = db.find({"share" => path})
        if ids.size == 0
           p = Hash(String, String).new
           return self.new(path, p)
        end
        o = self.get(db, ids[0].to_u64)
        o.id = ids[0]
        o
    end

    def save(db : Bcdb::Client)
        if self.id.nil?
            db.put(self.dumps, {"share" => @path})
        else
            db.update(self.id.not_nil!, self.dumps, {"share" => @path})
        end
    end

    def self.delete(db : Bcdb::Client, path)
        ids = db.find({"share" => path})
        if ids.size > 0
            db.delete(ids[0])
        end
    end
end

class CrystalDrive::ShareLink < CrystalDrive::Model
    include JSON::Serializable
    property path : String
    property id : UInt64 = 0_u64
    property links : Hash(String, String) = Hash(String, String).new
    property owner : String = ""

    def initialize(@path, @owner); end

    def self.get(db : Bcdb::Client, path : String, permission : String, owner : String)
        ids = db.find({"share" => path, "shared_links" => "1"})
        if ids.size == 0
            o = self.new(path, owner)
            o.links[permission] = UUID.random.to_s
            key = db.put(o.dumps, {"share" => path, "shared_links" => "1", o.links[permission] => "1"})
            o.id = key
        else
            o = self.get(db, ids[0].to_u64)
            o.id = ids[0]
            if !o.links.has_key?(permission)
                o.links[permission] = UUID.random.to_s
                db.update(ids[0], o.dumps, {"share" => path, "shared_links" => "1", o.links[permission] => "1"})
            end
        end
        {
            "hash" => o.links[permission],
            "permission" => permission,
            "owner" => owner,
            "path" => path
        }
    end

    def self.get(db : Bcdb::Client, hash : String)
        ids = db.find({hash => "1"})
        res = Hash(String, String).new

        if ids.size >0
            o = self.get(db, ids[0].to_u64)
            o.links.each do |perm, h|
                if h == hash
                    res["hash"] = hash
                    res["permission"] = perm
                    res["owner"] = o.owner
                    res["path"] = o.path
                end
            end
        end
        res
    end


    def self.delete(db : Bcdb::Client, path : String, permission : String = "")
        ids = db.find({"share" => path, "shared_links" => "1"})
        if ids.size > 0
            # delete all
            if permission == ""
                db.delete(ids[0])
            else
                o = self.get(db, ids[0].to_u64)
                o.id = ids[0]
                if o.links.has_key?(permission)
                    o.links.delete(permission)
                end
                if o.links.size == 0
                    db.delete(ids[0])
                else
                    tags = {"share" => path, "shared_links" => "1"}
                    o.links.each do |perm, hash|
                        tags[hash] = "1"
                    end
                    db.update(ids[0], o.dumps, tags)
                end
            end
        end
    end

    def self.list(db : Bcdb::Client, path : String)
        ids = db.find({"share" => path, "shared_links" => "1"})
        res = Array(Hash(String, String)).new

        if ids.size >0
            o = self.get(db, ids[0].to_u64)
            o.links.each do |perm, hash|
                res << {
                    "hash" => hash,
                    "permission" => perm,
                }
            end
        end
        res
    end
end

class CrystalDrive::FileCheckSum
    include JSON::Serializable

    property md5 : String = ""
    property sha1 : String = ""
    property sha256 : String = ""
    property sha512 : String = ""

    def initialize; end
end

class CrystalDrive::Item

    include JSON::Serializable
    property size : UInt64 = 0_u64
    property content : String = ""
    property path : String = ""
    property name : String = ""
    property extension : String = ""
    property modified : String  = Time.utc.to_s("%Y-%m-%dT%H:%M:%S")
    property mode : UInt16 = 420
    property key : String = ""

    @[JSON::Field(key: "isDir")]
    property is_dir : Bool = false
    
    @[JSON::Field(key: "type")]
    property itemType : String = ""

    @[JSON::Field(key: "httpContentType")]
    property http_content_type : String = ""

    @[JSON::Field(key: "checkSum")]
    property checksum : String  = ""

    def initialize; end

end

class CrystalDrive::DirList

    include JSON::Serializable

    property size : UInt64 = 0_u64
    property path : String = ""
    property name : String = ""
    property extension : String = ""
    property modified : String  = Time.utc.to_s("%Y-%m-%dT%H:%M:%S")
    property mode : Int64 = 2147484141

    @[JSON::Field(key: "isDir")]
    property is_dir : Bool = true
    
    @[JSON::Field(key: "type")]
    property itemType : String = ""

    property items : Array(CrystalDrive::Item) = Array(CrystalDrive::Item).new

    @[JSON::Field(key: "numDirs")]
    property num_dirs : UInt64 = 0_u64

    @[JSON::Field(key: "numFiles")]
    property num_files : UInt64 = 0_u64

    property sorting : CrystalDrive::SortingPrefernces = CrystalDrive::SortingPrefernces.new

    def initialize; end
end

class CrystalDrive::SortingPrefernces

    include JSON::Serializable

    property by : String = "name"
    property asc : Bool = false

    def initialize; end
end

class CrystalDrive::Permissions
    include JSON::Serializable

    property admin : Bool = false
    property execute : Bool = false
    property create : Bool = false
    property rename : Bool = false
    property modify : Bool = false
    property delete : Bool = false
    property share : Bool = false
    property download : Bool = false

    def initialize; end
end

class CrystalDrive::User

    include JSON::Serializable

    property id : UInt64 = 0_u64
    property username : String = ""
    property password : String = ""
    property scope : String = ""
    property locale : String = ""
    property viewMode : String = ""
    property lockPassword : Bool = false
    property commands : Array(String) = Array(String).new
    property sorting : CrystalDrive::SortingPrefernces = CrystalDrive::SortingPrefernces.new
    property rules : Array(String) = Array(String).new
    property perm : CrystalDrive::Permissions = CrystalDrive::Permissions.new

    def initialize; end
end
