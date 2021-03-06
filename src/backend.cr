require "crystalstore"
require "./models"

class CrystalDrive::Backend
    STORE = CrystalStore::Store.new
    
    @@shared_with_me_dirname = "1eba81a9-6086-4489-a176-b99abb27aecf"

    def self.get_shared_with_me_dirname
        @@shared_with_me_dirname
    end

    private def self.is_file(path : String)
        return false
    end

    private def self.get_sorting_pref_for_user(id : String)
        return CrystalDrive::SortingPrefernces.new
    end

    private def self.get_content_type (http_content_type : String)
        if http_content_type.includes?("image")
            return "image"
        elsif http_content_type.includes?("text")
            return "text"
        elsif http_content_type.includes?("video")
            return "video"
        else
            return "blob"
        end
    end

    def self.shared(path : String)
        self.dir_list("#{path}/#{@@shared_with_me_dirname}")
    end

    def self.create_shared_withme_dir(user)
        self.dir_create("#{user}/#{@@shared_with_me_dirname}", 777)
    end

    def self.dir_create(path : String, mode : Int16, create_parents : Bool = false)
        STORE.dir_create path: path, mode: mode, create_parents: create_parents
    end

    def self.dir_delete(path : String)
        STORE.dir_delete path: path
    end

    def self.dir_copy(src : String, dest : String)
        STORE.dir_copy src: src, dest: dest
    end

    def self.dir_move(src : String, dest : String)
        STORE.dir_move src: src, dest: dest
    end

    def self.dir_exists?(path : String)
        STORE.dir_exists? path: path
    end

    def self.file_create(path : String, mode : Int16, content_type : String, create_parents : Bool = false)
        STORE.file_create path: path, mode: mode, flags: 0_i16, content_type: content_type, create_parents: create_parents
    end

    def self.file_open(path : String, mode : Int16)
        STORE.file_open path: path, mode: mode, flags: 0_i16
    end

    def self.file_delete(path : String)
        STORE.file_delete path: path
    end

    def self.file_exists?(path : String)
        STORE.file_exists? path: path
    end

    def self.file_copy(src : String, dest : String)
        STORE.file_copy src: src, dest: dest
    end

    def self.file_move(src : String, dest : String)
        STORE.file_move src: src, dest: dest
    end

    def self.link_delete(path : String)
        STORE.unlink path
    end

    def self.file_stats(orig_path : String, path : String)
        file_meta = STORE.file_stats path: path
        file_meta = file_meta.not_nil!
        
        item = CrystalDrive::Item.new
        item.key = file_meta.not_nil!.id.not_nil!.to_s
        item.name = file_meta.not_nil!.name.not_nil!
        item.size = file_meta.not_nil!.size
        item.path = orig_path
        item.extension = File.extname(item.name)
        item.modified = Time.unix(file_meta.not_nil!.last_modified).to_s("%Y-%m-%dT%H:%M:%S")
        item.mode = 493 #file_meta.not_nil!.mode.to_u16
        item.is_dir = false
        item.itemType = self.get_content_type file_meta.not_nil!.content_type
        return item
    end 

    def self.list(path : String = "/")
        is_root = (path == "/")
        path = Path.new("/", path)
        parts = path.parts
        basename = path.basename
        list  = STORE.dir_list(path.to_s)
        files = list.files
        dirs = list.dirs
        # resolve links (files or dirs)

        list.links.each do |link|
            if link.is_dir
                meta = STORE.dir_stats(link.src)
                pointer = CrystalStore::DirPointer.new id: 0_u64, name: link.name, meta: meta
                dirs << pointer
            else
                file_meta = STORE.file_stats(link.src)
                file = CrystalStore::File.new basename, meta: file_meta
                file.id = file_meta.not_nil!.id
                files << file
            end
        end

        parts.delete_at(1)
        
        if parts.size > 1 && parts[1] == @@shared_with_me_dirname
            parts[1] = "shared"
            basename = "Shared"
        end

        path = Path.new parts
        
        if path.to_s == "/"
            basename = ""
        end
        
        result = CrystalDrive::DirList.new
        result.size = list.size
        result.modified = Time.unix(list.last_modified).to_s("%Y-%m-%dT%H:%M:%S")
        result.mode = list.mode.to_i64
        result.path = path.to_s
        result.name = basename
        result.num_dirs = list.dirs.size.to_u64
        result.num_files = list.files.size.to_u64
        result.sorting = get_sorting_pref_for_user ""

        files.each do |file|
            item = CrystalDrive::Item.new
            item.key = file.id.not_nil!.to_s
            item.name = file.meta.not_nil!.name.not_nil!
            item.size = file.meta.not_nil!.size
            item.path = Path.new("/", item.name).to_s
            item.extension = File.extname(file.name)
            item.modified = Time.unix(file.meta.not_nil!.last_modified).to_s("%Y-%m-%dT%H:%M:%S")
            item.mode = file.meta.not_nil!.mode.to_u16
            item.is_dir = false
            item.itemType = self.get_content_type file.meta.not_nil!.content_type
            result.items << item
        end

        dirs.each do |dir|
            # skip shared with me directory
            if dir.name == @@shared_with_me_dirname
                result.num_dirs -= 1_u64 # skip shared with me 
                next
            end
            item = CrystalDrive::Item.new
            item.name = dir.meta.not_nil!.name.not_nil!
            item.size = dir.meta.not_nil!.size
            item.path = Path.new("/", item.name).to_s
            item.extension = ""
            item.modified = Time.unix(dir.meta.not_nil!.last_modified).to_s("%Y-%m-%dT%H:%M:%S")
            item.mode = dir.meta.not_nil!.mode.to_u16
            item.is_dir = true
            item.itemType = ""
            result.items << item
        end
        result

    end

    def self.stats(path : String)
        self.is_file(path) ? STORE.file_stats(path) : STORE.dir_stats(path)
    end

    def self.share(path : String, current_user : String, shares : Hash(String, Hash(String, String)))
        updated_users = [] of String
        deleted_users = [] of String

        begin
            share = CrystalDrive::Share.get(STORE.db, path)
        rescue CrystalDrive::UserNotFoundError
            share = CrystalDrive::Share.new path: path, permissions: Hash(String, Hash(String, String)).new
        end
        shares.each do |name, v|
            share_by_user_permission = ""
            share_by_link_permission = ""

            user_share = false
            link_share = false

            if v.has_key?("user")
                share_by_user_permission = v["user"]
                user_share = true
            end

            if v.has_key?("link")
                share_by_link_permission = v["link"]
                link_share = true
            end
            delete = false
            if user_share && share.permissions.has_key?(name) && share_by_user_permission == ""
                share.permissions[name].delete("user")
                delete = true
            end
            
            if link_share && share.permissions.has_key?(name) && share_by_link_permission == ""
                share.permissions[name].delete("link")
                delete = true
            end
            # deleted
            if share.permissions.has_key?(name) && !share.permissions[name].has_key?("user") && !share.permissions[name].has_key?("link")
                deleted_users << name
                share.permissions.delete(name)
            # updated / newly created
            else
                if !delete
                    if !share.permissions.has_key?(name)
                        share.permissions[name] = Hash(String, String).new
                    end
                    updated_users << name
                    if user_share
                        share.permissions[name]["user"] = v["user"]
                    elsif link_share
                        share.permissions[name]["link"] = v["link"]
                    end
                end
            end
        end
        
        if share.permissions.size > 0
            share.save(STORE.db)
        else
            CrystalDrive::Share.delete(STORE.db, path)
        end

        basename = Path.new(path).basename
        updated_users.each do |user|
            begin
                STORE.dir_create("/#{user}/#{@@shared_with_me_dirname}/#{current_user}", 755)
            rescue CrystalStore::FileExistsError
            end
            # try to add the symlink if not exists
            begin
                STORE.symlink src: path, dest: "/#{user}/#{@@shared_with_me_dirname}/#{current_user}/#{basename}"
            rescue CrystalStore::FileExistsError
            end
        end

        deleted_users.each do |user|
            begin
                STORE.unlink "/#{user}/#{@@shared_with_me_dirname}/#{current_user}/#{basename}"
            rescue CrystalStore::FileNotFoundError
            end
        end
        share.permissions
    end

    def self.share_get(path : String)
        CrystalDrive::Share.get(STORE.db, path)
    end

    def self.share_delete(path : String, current_user : String, type : String)
        basename = Path.new(path).basename
        share = CrystalDrive::Share.get(STORE.db, path)
        deleted_users = [] of String
        share.permissions.each do |user, perm|
            if share.permissions[user].has_key?(type)
                share.permissions[user].delete(type)
            end

            if !share.permissions[user].has_key?("user") && !share.permissions[user].has_key?("link")
                deleted_users << user
                STORE.unlink "/#{user}/#{@@shared_with_me_dirname}/#{current_user}/#{basename}"
            end
        end

        deleted_users.each do |u|
            share.permissions.delete(u)
        end

        if share.permissions.size == 0
            CrystalDrive::Share.delete(STORE.db, path)
        else
            share.save(STORE.db)
        end
    end

    def self.share_link_get(path : String, permission : String, owner : String)
        share_info = CrystalDrive::ShareLink.get(STORE.db, path, permission, owner)
    end

    def self.share_links_get(path : String)
        CrystalDrive::ShareLink.list(STORE.db, path)
    end

    def self.share_link_create(hash : String, current_user : String)
        share_info = CrystalDrive::ShareLink.get(STORE.db, hash)
        
        if share_info.size == 0
            raise CrystalDrive::NotFoundError.new
        end
        perm = {current_user =>  {"link" => share_info["permission"]} } 
        self.share(share_info["path"], share_info["owner"], perm)
        share_info
    end

    def self.share_link_delete(path : String, permission : String, current_user : String)
        CrystalDrive::ShareLink.delete(STORE.db, path, permission)
        self.share_delete(path, current_user, "link")
    end

    def self.has_permission?(username : String, path : String, permission : String )
        path = path.gsub("/#{username}/#{self.get_shared_with_me_dirname}", "")

        if path.starts_with?("/#{username}")
            return true
        end

        # Arrange permissions to be as in "rwd"
        
        p = ""
        
        if permission.includes?("r")
            p += "r"
        end

        if permission.includes?("w")
            p += "w"
        end

        if permission.includes?("d")
            p += "d"
        end

        permission = p

        paths = Array(String){path}
        parts = Path.new(path).parts
        
        parts.pop
        
        while parts.size > 2
            paths << "#{Path.new(parts).to_s}/"
            parts.pop
        end

        paths.each do |path|
            perm_obj = CrystalDrive::Share.get(STORE.db, path)
            found = perm_obj.permissions.size > 0
            # check parent permissions if this specific path has no sharing for this user
            if !found || !perm_obj.permissions.has_key? username
                next
            end

            if perm_obj.permissions[username].has_key?("user") && perm_obj.permissions[username]["user"].includes?(permission)
                return true
            elsif perm_obj.permissions[username].has_key?("link") && perm_obj.permissions[username]["link"].includes?(permission)
                return true
            else
                # user exists in permission set of parent, but does not have this permission
                return false
            end
        end
        return false
    end

    def self.user_add(username : String, email : String)
        u = CrystalDrive::AuthUser.new username: username, email: email
        u.save(STORE.db)
    end
end
