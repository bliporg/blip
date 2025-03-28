--[[

API module

]]
--

local time = require("time")
local url = require("url")

-- TODO create url type

local mod = {
	kApiAddr = "https://api.cu.bzh", -- prod server
	-- kApiAddr = "http://192.168.1.16:10083", -- dev server
	maxWorldTitleLength = 32,
}

local errorMT = {
	__tostring = function(t)
		return t.message or ""
	end,
}

mod.error = function(_, statusCode, message)
	local err = { statusCode = statusCode, message = message }
	setmetatable(err, errorMT)
	return err
end

local function urlGetFields(url, fields)
	if fields == nil then
		return url
	end
	local firstParams = string.find(url, "?") == nil
	for i, field in ipairs(fields) do
		if i == 1 and firstParams then
			url = url .. "?f=" .. field
		else
			url = url .. "&f=" .. field
		end
	end
	return url
end

-- search Users by username substring
-- callback(ok, users, errMsg)
-- ok: boolean
-- users: []User
-- errMsg: string
mod.searchUser = function(_, searchText, callback)
	-- validate arguments
	if type(searchText) ~= "string" then
		error("api:searchUser(searchText, callback) - searchText must be a string", 2)
	end
	if type(callback) ~= "function" then
		error("api:searchUser(searchText, callback) - callback must be a function", 2)
	end

	local req = HTTP:Get(mod.kApiAddr .. "/user-search-others/" .. searchText, function(resp)
		if resp.StatusCode ~= 200 then
			callback(false, nil, "could not search users (" .. resp.StatusCode .. ")")
			return
		end
		local users, err = JSON:Decode(resp.Body)
		if err ~= nil then
			callback(false, nil, "search users decode error: " .. err)
			return
		end
		callback(true, users, nil) -- success
	end)
	return req
end

-- getFriends
-- callback(friends, err)
mod.getFriends = function(self, config, callback)
	if self ~= mod then
		error("api:getFriends(config, callback): use `:`", 2)
	end
	if type(callback) ~= "function" then
		error("api:getFriends(config, callback) - callback must be a function", 2)
	end

	local defaultConfig = {
		userID = "self",
		fields = { "id" },
	}

	ok, err = pcall(function()
		config = require("config"):merge(defaultConfig, config)
	end)

	if not ok then
		error("api:getFriends(config, callback): config error (" .. err .. ")", 2)
	end

	local u = url:parse(mod.kApiAddr .. "/users/" .. config.userID .. "/friends")

	for _, field in ipairs(config.fields) do
		u:addQueryParameter("f", field)
	end

	local req = HTTP:Get(u:toString(), function(res)
		if res.StatusCode ~= 200 then
			callback(nil, mod:error(res.StatusCode, "status code: " .. res.StatusCode))
			return
		end

		local friends, err = JSON:Decode(res.Body)

		for _, friend in ipairs(friends) do
			if friend.created then
				friend.created = time.iso8601_to_os_time(friend.created)
			end
			if friend.updated then
				friend.updated = time.iso8601_to_os_time(friend.updated)
			end
		end

		if err ~= nil then
			callback(nil, mod:error(res.StatusCode, "getFriends JSON decode error: " .. err))
			return
		end
		callback(friends) -- success
	end)
	return req
end

-- getFriendCount ...
-- callback(ok, count, errMsg)
mod.getFriendCount = function(self, callback, config)
	if type(callback) ~= "function" then
		error("api:getFriendCount(callback) - callback must be a function", 2)
	end

	local req = self:getFriends(function(ok, friends, err)
		local count = 0
		if friends ~= nil then
			count = #friends
		end
		callback(ok, count, err)
	end, { "username" }, config)
	return req
end

-- getSentFriendRequests ...
-- callback(requests, err)
mod.getSentFriendRequests = function(self, config, callback)
	if self ~= mod then
		error("api:getSentFriendRequests(config, callback): use `:`", 2)
	end
	if type(callback) ~= "function" then
		error("api:getSentFriendRequests(config, callback) - callback must be a function", 2)
	end

	local defaultConfig = {
		fields = { "id" },
	}

	ok, err = pcall(function()
		config = require("config"):merge(defaultConfig, config)
	end)

	if not ok then
		error("api:getSentFriendRequests(config, callback): config error (" .. err .. ")", 2)
	end

	local u = url:parse(mod.kApiAddr .. "/users/self/friend-requests")

	u:addQueryParameter("status", "sent")

	for _, field in ipairs(config.fields) do
		u:addQueryParameter("f", field)
	end

	local req = HTTP:Get(u:toString(), function(resp)
		if resp.StatusCode ~= 200 then
			callback(nil, mod:error(resp.StatusCode, "could not get sent friend requests (" .. resp.StatusCode .. ")"))
			return
		end
		local requests, err = JSON:Decode(resp.Body)
		if err ~= nil then
			callback(nil, mod:error(resp.StatusCode, "getSentFriendRequests JSON decode error: " .. err))
			return
		end
		callback(requests) -- success
	end)

	return req
end

-- getReceivedFriendRequests ...
-- callback(ok, reqs, errMsg)
mod.getReceivedFriendRequests = function(self, config, callback)
	if self ~= mod then
		error("api:getReceivedFriendRequests(config, callback): use `:`", 2)
	end
	if type(callback) ~= "function" then
		error("api:getReceivedFriendRequests(config, callback) - callback must be a function", 2)
	end

	local defaultConfig = {
		fields = { "id" },
	}

	ok, err = pcall(function()
		config = require("config"):merge(defaultConfig, config)
	end)

	if not ok then
		error("api:getReceivedFriendRequests(config, callback): config error (" .. err .. ")", 2)
	end

	local u = url:parse(mod.kApiAddr .. "/users/self/friend-requests")

	u:addQueryParameter("status", "received")

	for _, field in ipairs(config.fields) do
		u:addQueryParameter("f", field)
	end

	local req = HTTP:Get(u:toString(), function(resp)
		if resp.StatusCode ~= 200 then
			callback(
				nil,
				mod:error(resp.StatusCode, "could not get received friend requests (" .. resp.StatusCode .. ")")
			)
			return
		end
		local requests, err = JSON:Decode(resp.Body)
		if err ~= nil then
			callback(nil, mod:error(resp.StatusCode, "getReceivedFriendRequests JSON decode error: " .. err))
			return
		end
		callback(requests) -- success
	end)

	return req
end

-- getUserInfo gets a user by its ID
-- callback(userInfo, err)
-- success: err == nil
-- fields parameter is optional, it can be a table-- containing extra expected user fields:
-- {"created", "nbFriends"}
-- TODO: caller should have a way to check error code -> 401 means bad credentials for signup.lua (removing installed credentials)
mod.getUserInfo = function(_, id, callback, fields)
	if type(id) ~= "string" then
		error("api:getUserInfo(userID, callback, [fields]) - userID must be a string", 2)
	end
	if type(callback) ~= "function" then
		error("api:getUserInfo(userID, callback, [fields]) - callback must be a function", 2)
	end
	if fields ~= nil and type(fields) ~= "table" then
		error("api:getUserInfo(callback, [fields]) - fields must be a table or nil", 2)
	end

	local url = mod.kApiAddr .. "/users/" .. id

	url = urlGetFields(url, fields)

	local req = HTTP:Get(url, function(resp)
		if resp.StatusCode ~= 200 then
			callback(nil, mod:error(resp.StatusCode, "could not get user info (" .. resp.StatusCode .. ")"))
			return
		end
		local usr, err = JSON:Decode(resp.Body)
		if err ~= nil then
			callback(nil, mod:error(resp.StatusCode, "getUserInfo JSON decode error: " .. err))
			return
		end
		if usr.nbFriends ~= nil then
			usr.nbFriends = math.floor(usr.nbFriends)
		end
		callback(usr, nil) -- success
	end)
	return req
end

-- getMinAppVersion gets minimum app version
-- callback(error string or nil, minVersion string)
mod.getMinAppVersion = function(_, callback)
	if type(callback) ~= "function" then
		error("api:getMinAppVersion(callback) - callback must be a function", 2)
	end

	local url = mod.kApiAddr .. "/min-version"

	local req = HTTP:Get(url, function(resp)
		if resp.StatusCode ~= 200 then
			callback("could not get min app version (" .. resp.StatusCode .. ")", nil)
			return
		end
		local r, err = JSON:Decode(resp.Body)
		if err ~= nil then
			callback("get min app version decode error: " .. err, nil)
			return
		end
		if not r.version or type(r.version) ~= "string" then
			callback("get min app version error: version field missing", nil)
			return
		end
		callback(nil, r.version) -- success
	end)
	return req
end

-- --------------------------------------------------
-- BLUEPRINTS
-- --------------------------------------------------

--- Lists items using filter.
---
--- Config ---
--- search: string (not empty)
--- category: string
--- repo: string
--- sortBy: string? (nil, "", "updatedAt:desc", "likes:desc", "views:desc", ...)
---
--- Callback ---
---
--- error: string (can be nil)
--- items: []Item (can be nil)
---

-- /itemdrafts?search=banana,gdevillele&page=1&perPage=100
mod.getItems = function(self, config, callback)
	if self ~= mod then
		error("api:getItems(config, callback): use `:`", 2)
	end
	if type(config) ~= "table" then
		error("api:getItems(config, callback): config must be a table", 2)
	end
	if type(callback) ~= "function" then
		error("api:getItems(config, callback): callback must be a function", 2)
	end

	local defaultConfig = {
		category = "",
		search = "",
		sortBy = "updatedAt:desc", -- likes:desc
		page = 1,
		perPage = 50,
		repo = "",
		minBlock = nil,
		fields = { "title", "created", "updated", "views", "likes" },
	}

	ok, err = pcall(function()
		config = require("config"):merge(defaultConfig, config, {
			acceptTypes = {
				minBlock = { "number" },
				category = { "string", "table" },
			},
		})
	end)

	if not ok then
		error("api:getItems(config, callback): config error (" .. err .. ")", 2)
	end

	local u = url:parse(mod.kApiAddr .. "/itemdrafts")

	if type(config.category) == "string" then
		u:addQueryParameter("category", config.category)
	elseif type(config.category) == "table" then
		for _, category in ipairs(config.category) do
			u:addQueryParameter("category", category)
		end
	end
	u:addQueryParameter("repo", config.repo)
	u:addQueryParameter("search", config.search)
	u:addQueryParameter("sortBy", config.sortBy)
	u:addQueryParameter("perPage", math.floor(config.perPage))
	u:addQueryParameter("page", math.floor(config.page))
	if config.minBlock ~= nil then
		u:addQueryParameter("minBlock", math.floor(config.minBlock))
	end

	for _, field in ipairs(config.fields) do
		u:addQueryParameter("f", field)
	end

	local req = HTTP:Get(u:toString(), function(res)
		-- check status code
		if res.StatusCode ~= 200 then
			callback(nil, mod:error(res.StatusCode, "status code: " .. res.StatusCode))
			return
		end

		-- decode body
		local items, err = JSON:Decode(res.Body)
		if err ~= nil then
			callback(nil, mod:error(res.StatusCode, "getItems JSON decode error: " .. err))
			return
		end

		for _, v in ipairs(items.results) do
			v.created = time.iso8601_to_os_time(v.created)
			v.updated = time.iso8601_to_os_time(v.updated)
			if v.likes == nil then
				v.likes = 0
			end
		end

		callback(items.results) -- success
	end)
	return req
end

--- returns worlds considering provided filters
-- TODO: add filter for user world drafts
-- callback(worlds, err)
mod.getWorlds = function(self, config, callback)
	if self ~= mod then
		error("api:getWorlds(config, callback): use `:`", 2)
	end
	if type(callback) ~= "function" then
		error("api:getWorlds(config, callback): callback should be a function", 2)
	end

	local defaultConfig = {
		authorId = "",
		category = "",
		search = "",
		sortBy = "updatedAt:desc", -- likes:desc
		page = 1,
		perPage = 50,
		fields = { "title", "created", "updated", "views", "likes" },
	}

	ok, err = pcall(function()
		config = require("config"):merge(defaultConfig, config)
	end)

	if not ok then
		error("api:getWorlds(config, callback): config error (" .. err .. ")", 2)
	end

	local u = url:parse(mod.kApiAddr .. "/worlds")

	u:addQueryParameter("authorid", config.authorId)
	u:addQueryParameter("category", config.category)
	u:addQueryParameter("search", config.search)
	u:addQueryParameter("sortBy", config.sortBy)
	u:addQueryParameter("perPage", math.floor(config.perPage))
	u:addQueryParameter("page", math.floor(config.page))

	for _, field in ipairs(config.fields) do
		u:addQueryParameter("f", field)
	end

	local req = HTTP:Get(u:toString(), function(res)
		if res.StatusCode ~= 200 then
			callback(nil, mod:error(res.StatusCode, "status code: " .. res.StatusCode))
			return
		end

		local data, err = JSON:Decode(res.Body)
		if err ~= nil then
			callback(nil, mod:error(res.StatusCode, "getWorlds JSON decode error: " .. err))
			return
		end

		for _, v in ipairs(data.results) do
			if v.created then
				v.created = time.iso8601_to_os_time(v.created)
			end
			if v.updated then
				v.updated = time.iso8601_to_os_time(v.updated)
			end
			if v.likes ~= nil then
				v.likes = math.floor(v.likes)
			else
				v.likes = 0
			end
			if v.views ~= nil then
				v.views = math.floor(v.views)
			else
				v.views = 0
			end
		end
		callback(data.results)
	end)
	return req
end

-- callback(error string or nil, World or nil)
-- field=authorName
mod.getWorld = function(self, worldID, fields, callback)
	if self ~= mod then
		error("api:getWorld(config, callback): use `:`", 2)
	end
	if type(fields) ~= "table" then
		error("api:getWorld(worldID, fields, callback) - fields must be a table", 2)
	end
	if #fields < 1 then
		error("api:getWorld(worldID, fields, callback) - fields must contain at least one entry", 2)
	end
	if type(callback) ~= "function" then
		error("api:getWorld(worldID, fields, callback) - callback must be a function", 2)
	end

	local u = url:parse(mod.kApiAddr .. "/worlds/" .. worldID)

	for _, field in ipairs(fields) do
		u:addQueryParameter("f", field)
	end

	-- send request
	local req = HTTP:Get(u:toString(), function(res)
		-- check status code
		if res.StatusCode ~= 200 then
			callback(nil, mod:error(res.StatusCode, "status code: " .. res.StatusCode))
			return
		end

		-- decode body
		local world, err = JSON:Decode(res.Body)
		if err ~= nil then
			callback(nil, mod:error(res.StatusCode, "getWorld JSON decode error: " .. err))
			return
		end

		if world.created then
			world.created = time.iso8601_to_os_time(world.created)
		end
		if world.updated then
			world.updated = time.iso8601_to_os_time(world.updated)
		end
		if world.likes ~= nil then
			world.likes = math.floor(world.likes)
		else
			world.likes = 0
		end
		if world.views ~= nil then
			world.views = math.floor(world.views)
		else
			world.views = 0
		end
		-- `liked` field is omitted if value is false
		if world.liked == nil then
			world.liked = false
		end

		callback(world) -- success
	end)
	return req
end

mod.getWorldThumbnail = function(self, config)
	if self ~= mod then
		error("api:getWorldThumbnail(config): use `:`", 2)
	end

	local defaultConfig = {
		worldID = "",
		width = nil,
		callback = nil,
	}

	ok, err = pcall(function()
		config = require("config"):merge(defaultConfig, config, {
			acceptTypes = {
				width = { "number" },
				callback = { "function" },
			},
		})
	end)

	if not ok then
		error("api:getWorldThumbnail(config): config error (" .. err .. ")", 2)
	end

	if config.worldID == "" then
		error("api:getWorldThumbnail(config): config.worldID should not be empty", 2)
	end
	if config.callback == nil then
		error("api:getWorldThumbnail(config): config.callback should be a function", 2)
	end

	local u
	if config.width ~= nil then
		u = url:parse(mod.kApiAddr .. "/worlds/" .. config.worldID .. "/thumbnail-" .. config.width .. ".png")
	else
		u = url:parse(mod.kApiAddr .. "/worlds/" .. config.worldID .. "/thumbnail.png")
	end

	local req = HTTP:Get(u:toString(), function(res)
		if res.StatusCode == 200 then
			config.callback(res.Body)
		elseif res.StatusCode == 400 then
			config.callback(nil, mod:error(res.StatusCode, "status code: " .. res.StatusCode))
		else
			config.callback(nil, mod:error(res.StatusCode, "status code: " .. res.StatusCode))
		end
	end)

	return req
end

mod.getServers = function(self, worldID, callback)
	local url = self.kApiAddr .. "/servers?worldID=" .. worldID .. "&tag=" .. Private.ServerTag

	local req = HTTP:Get(url, function(res)
		if res.StatusCode ~= 200 then
			callback(self.error(res.StatusCode, "could not get servers"), nil)
			return
		end

		local t = JSON:Decode(res.Body)
		if t.servers == nil then
			t = {}
			callback(nil, t)
			return
		end
		-- take care of omitempty fields
		local hasPlayers
		local hasMaxPlayers
		local hasDevMode
		for _, s in pairs(t.servers) do
			hasPlayers = false
			hasMaxPlayers = false
			hasDevMode = false
			for k, _ in pairs(s) do
				if k == "players" then
					hasPlayers = true
				end
				if k == "max-players" then
					hasMaxPlayers = true
				end
				if k == "dev-mode" then
					hasDevMode = true
				end
			end
			if not hasPlayers then
				s.players = 0
			end
			if not hasMaxPlayers then
				s["max-players"] = 0
			end
			if not hasDevMode then
				s["dev-mode"] = 0
			end
		end
		callback(nil, t.servers)
	end)
	return req
end

mod.getUserId = function(username, cb)
	if not username then
		return cb("Error: first parameter of getUserId must be a username.")
	end
	local url = mod.kApiAddr .. "/users?username=" .. username
	local req = HTTP:Get(url, function(res)
		if res.StatusCode ~= 200 then
			return cb("Error (" .. res.StatusCode .. "): can't find user " .. username .. ".")
		end
		cb(nil, JSON:Decode(res.Body).id)
	end)
	return req
end

mod.getAvatar = function(usernameOrId, cb)
	if type(usernameOrId) ~= "string" then
		error("getAvatar(usernameOrId) - usernameOrId should be a string", 2)
	end
	local url = mod.kApiAddr .. "/users/" .. usernameOrId .. "/avatar"
	local req = HTTP:Get(url, function(res)
		if res.StatusCode ~= 200 then
			cb("Error (" .. res.StatusCode .. "): can't get avatar.")
			return
		end
		local data = JSON:Decode(res.Body)
		data.hair = #data.hair > 0 and data.hair or nil
		data.jacket = #data.jacket > 0 and data.jacket or "official.jacket"
		data.pants = #data.pants > 0 and data.pants or "official.pants"
		data.boots = #data.boots > 0 and data.boots or "official.boots"
		cb(nil, data)
	end)
	return req
end

-- callback(error string or nil, balance object or nil)
--
-- balance object:
-- {
-- 	"userID": "000000000-0000-0000-0000-000000000000",
-- 	"grantedCoins": 0,
-- 	"purchasedCoins": 0,
-- 	"earnedCoins": 0,
-- 	"totalCoins": 0,
-- }
mod.getBalance = function(_, cb)
	local cbType = type(cb)
	if cbType ~= "function" and cbType ~= "nil" then
		error("getBalance(cb) - cb must be a function or nil", 2)
	end

	local url = mod.kApiAddr .. "/users/self/balance"
	local req = HTTP:Get(url, function(res)
		if res.StatusCode ~= 200 then
			cb("Error (" .. res.StatusCode .. "): can't get balance.")
			return
		end
		cb(nil, JSON:Decode(res.Body))
	end)
	return req
end

mod.getTransactions = function(self, config)
	if self ~= mod then
		error("api:getTransactions(config): use `:`", 2)
	end
	local defaultConfig = {
		limit = 100,
		callback = function() end, -- callback(transactions, error)
	}

	local ok, err = pcall(function()
		config = require("config"):merge(defaultConfig, config)
	end)

	if not ok then
		error("api:getTransactions(config): config error (" .. err .. ")", 2)
	end

	local url = mod.kApiAddr .. "/users/self/transactions?limit=" .. math.floor(config.limit)

	local req = HTTP:Get(url, function(res)
		if res.StatusCode ~= 200 then
			config.callback(nil, mod:error(res.StatusCode, "status code: " .. res.StatusCode))
			return
		end
		local transactions, err = JSON:Decode(res.Body)
		if err ~= nil then
			config.callback(nil, mod:error(res.StatusCode, "getTransactions JSON decode error: " .. err))
			return
		end
		config.callback(transactions)
	end)
	return req
end

mod.getItem = function(self, itemId, fields, callback)
	if self ~= mod then
		error("api:getItem(config, callback): use `:`", 2)
	end
	if type(fields) ~= "table" then
		error("api:getItem(itemId, fields, callback) - fields must be a table", 2)
	end
	if #fields < 1 then
		error("api:getItem(itemId, fields, callback) - fields must contain at least one entry", 2)
	end
	if type(callback) ~= "function" then
		error("api:getItem(itemId, fields, callback) - callback must be a function", 2)
	end

	local u = url:parse(mod.kApiAddr .. "/items/" .. itemId)

	for _, field in ipairs(fields) do
		u:addQueryParameter("f", field)
	end

	local req = HTTP:Get(u:toString(), function(res)
		if res.StatusCode ~= 200 then
			callback(nil, mod:error(res.StatusCode, "status code: " .. res.StatusCode))
			return
		end

		local item, err = JSON:Decode(res.Body)
		if err ~= nil then
			callback(nil, mod:error(res.StatusCode, "getItem JSON decode error: " .. err))
			return
		end

		if item.created then
			item.created = time.iso8601_to_os_time(item.created)
		end
		if item.updated then
			item.updated = time.iso8601_to_os_time(item.updated)
		end
		if item.likes ~= nil then
			item.likes = math.floor(item.likes)
		else
			item.likes = 0
		end
		if item.views ~= nil then
			item.views = math.floor(item.views)
		else
			item.views = 0
		end
		-- `liked` field is omitted if value is false
		if item.liked == nil then
			item.liked = false
		end

		callback(item) -- success
	end)
	return req
end

mod.getQuests = function() -- self
	-- nothing for now
end

-- Receives "natural" name, returns slug and string error (nil if there's none)
-- No request is sent, this is local validation.
mod.checkItemName = function(itemName, username)
	if type(itemName) ~= "string" then
		return nil, "Item name must be a string."
	elseif itemName == "" then
		return nil, "Item name can't be empty."
	elseif itemName:match("^[a-zA-Z].*$") == nil then
		return nil, "Item must start with a letter (A-Z)."
	elseif itemName:match("^[a-zA-Z][a-zA-Z0-9_ ]*$") == nil then
		return nil, "Item name must contain only letters (A-Z), numbers, spaces and underscores."
	elseif #itemName > 20 then
		return nil, "Item name must be 20 characters or shorter."
	end

	local lowered = string.lower(itemName)
	local slug = lowered:gsub(" ", "_")

	if username ~= nil then
		slug = username .. "." .. slug
	end

	return slug, nil
end

mod.checkWorldName = function(worldName)
	if type(worldName) ~= "string" then
		return nil, "World name must be a string."
	elseif worldName == "" then
		return nil, "World name can't be empty."
	elseif #worldName > mod.maxWorldTitleLength then
		local str = "Item name must be " .. mod.maxWorldTitleLength .. " characters or shorter."
		return nil, str
	end

	local sanitized = worldName

	return sanitized, nil
end

mod.aiChatCompletions = function(messages, temperatureOrCb, cb)
	if not messages then
		cb("Error: api.aiChatCompletions takes messages as a first parameter.")
		return
	end
	if type(temperatureOrCb) == "function" then
		cb = temperatureOrCb
	end
	local temperature = type(temperatureOrCb) == "number" and temperatureOrCb or 0.7

	local url = mod.kApiAddr .. "/ai/chatcompletions"
	local headers = {}
	headers["Content-Type"] = "application/json"

	local body = {}
	body.model = "gpt-4o-mini"
	body.messages = messages
	body.temperature = temperature
	HTTP:Post(url, headers, body, function(res)
		if res.StatusCode ~= 200 then
			return cb("Error (" .. tostring(res.StatusCode) .. "): " .. res.Body:ToString())
		end
		local body = JSON:Decode(res.Body:ToString())
		if body.error.type then
			return cb("Error (" .. body.error.type .. ")")
		end
		local message = body.choices[1].message
		cb(nil, message)
	end)
end

mod.aiImageGenerations = function(prompt, optionsOrCallback, callback)
	local options = type(optionsOrCallback) == "table" and optionsOrCallback or {}
	local cb = type(optionsOrCallback) == "function" and optionsOrCallback or callback

	local url = mod.kApiAddr .. "/ai/imagegenerations"
	local headers = {}
	headers["Content-Type"] = "application/json"

	local body = {
		prompt = prompt,
		size = options.size or 256,
		output = options.output or "Quad",
		pixelart = options.pixelart or false,
		asURL = options.asURL or false,
	}
	if body.output ~= "Shape" and body.output ~= "Quad" then
		return cb('Error: output can only be "Shape" or "Quad".')
	end
	local req = HTTP:Post(url, headers, body, function(res)
		if res.StatusCode ~= 200 then
			return cb("Error (" .. tostring(res.StatusCode) .. "): " .. res.Body:ToString())
		end
		local outputObj
		if body.output == "Quad" and not body.asURL then
			outputObj = Quad()
			outputObj.Width = 50
			outputObj.Height = 50
			outputObj.Image = res.Body
		elseif body.output == "Shape" and not body.asURL then
			outputObj = Shape(res.Body)
			local collisionBoxMin = outputObj.CollisionBox.Min
			local center = outputObj.CollisionBox.Center:Copy()
			center.Y = outputObj.CollisionBox.Min.Y
			outputObj.Pivot = { outputObj.Width * 0.5, collisionBoxMin.Y, outputObj.Depth * 0.5 }
			outputObj.CollisionBox = Box(center - { 0.5, 0, 0.5 }, center + { 0.5, 1, 0.5 })
		elseif body.asURL then
			outputObj = JSON:Decode(res.Body).url
		end
		cb(nil, outputObj)
	end)
	return req
end

return mod
