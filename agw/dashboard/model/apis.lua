local DB = require("agw.store.mysql_db")

return function(config)
	local api_url_model = {}
	local mysql_config = config.store_mysql
	local db = DB:new(mysql_config)

	function api_url_model:new(name, url, enable)
        return db:query("insert into apis(name, request_path, enable) values(?,?,?)",
                {name, url, enable})
    end
	
	return api_url_model
end