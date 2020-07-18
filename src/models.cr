require "json"
require "time"

class Fileman::FileCheckSum
    include JSON::Serializable

    property md5 : String = ""
    property sha1 : String = ""
    property sha256 : String = ""
    property sha512 : String = ""

    def initialize; end
end

class Fileman::Item

    include JSON::Serializable
    property size : UInt64 = 0_u64
    property content : String = ""
    property path : String = ""
    property name : String = ""
    property extension : String = ""
    property modified : String  = Time.utc.to_s("%Y-%m-%dT%H:%M:%S")
    property mode : UInt16 = 420

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

class Fileman::DirList

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

    property items : Array(Fileman::Item) = Array(Fileman::Item).new

    @[JSON::Field(key: "numDirs")]
    property num_dirs : UInt64 = 0_u64

    @[JSON::Field(key: "numFiles")]
    property num_files : UInt64 = 0_u64

    property sorting : Fileman::SortingPrefernces = Fileman::SortingPrefernces.new

    def initialize; end
end

class Fileman::SortingPrefernces

    include JSON::Serializable

    property by : String = "name"
    property asc : Bool = false

    def initialize; end
end

class Fileman::Permissions
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

class Fileman::User

    include JSON::Serializable

    property id : UInt64 = 0_u64
    property username : String = ""
    property password : String = ""
    property scope : String = ""
    property locale : String = ""
    property viewMode : String = ""
    property lockPassword : Bool = false
    property commands : Array(String) = Array(String).new
    property sorting : Fileman::SortingPrefernces = Fileman::SortingPrefernces.new
    property rules : Array(String) = Array(String).new
    property perm : Fileman::Permissions = Fileman::Permissions.new

    def initialize; end
end
