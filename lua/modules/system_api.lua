--[[

[System] API module

]]
--

local time = require("time")
local api = require("api")
local conf = require("config")
local url = require("url")

-- define the module table
local mod = {
	kApiAddr = api.kApiAddr,
}
local moduleMT = {}
moduleMT.__tostring = function(_)
	return "system api module"
end
moduleMT.__index = function(_, key)
	-- try to find the key in `api` module first, and then in `system_api`
	return api[key] or moduleMT[key]
end
setmetatable(mod, moduleMT)

-- define the error function
mod.error = function(_, statusCode, message)
	local err = { statusCode = statusCode, message = message }
	setmetatable(err, {
		__tostring = function(t)
			return t.message or ""
		end,
	})
	return err
end

mod.deleteUser = function(_, callback)
	if type(callback) ~= "function" then
		callback(false, "1st arg must be a function")
		return
	end
	local url = mod.kApiAddr .. "/privileged/users/self"
	local req = System:HttpDelete(url, {}, function(resp)
		if resp.StatusCode ~= 200 then
			callback(false, "http status not 200")
			return
		end
		callback(true, nil) -- success
	end)
	return req
end

mod.checkUsername = function(_, username, callback)
	if type(username) ~= "string" then
		error("system_api:checkUsername(username, callback) - username must be a string", 2)
		return
	end
	if type(callback) ~= "function" then
		error("system_api:checkUsername(username, callback) - callback must be a function", 2)
		return
	end
	local url = mod.kApiAddr .. "/checks/username"
	local body = {
		username = username,
	}
	local req = System:HttpPost(url, body, function(resp)
		if resp.StatusCode ~= 200 then
			callback(false, "http status not 200")
			return
		end
		local response, err = JSON:Decode(resp.Body)
		if err ~= nil then
			callback(false, "json decode error:" .. err)
			return
		end
		-- response: {format = true, appropriate = true, available = true, key = "hash"}
		callback(true, response) -- success
	end)
	return req
end

-- callback(response, err) - response{ isValid = true, formattedNumber = "+12345678901" }
mod.checkPhoneNumber = function(_, phoneNumber, callback)
	if type(phoneNumber) ~= "string" then
		error("system_api:checkPhoneNumber(phoneNumber, callback) - phoneNumber must be a string", 2)
		return
	end
	if type(callback) ~= "function" then
		error("system_api:checkPhoneNumber(phoneNumber, callback) - callback must be a function", 2)
		return
	end
	local url = mod.kApiAddr .. "/checks/phonenumber"
	local body = {
		phoneNumber = phoneNumber,
	}
	local req = System:HttpPost(url, body, function(res)
		if res.StatusCode ~= 200 then
			callback(nil, api:error(res.StatusCode, "could not check phone number"))
			return
		end
		local response, err = JSON:Decode(res.Body)
		if err ~= nil then
			callback(nil, api:error(res.StatusCode, "checkPhoneNumber JSON decode error: " .. err))
			return
		end
		callback(response)
	end)
	return req
end

-- callback(err, res) err is nil on success
mod.getLoginOptions = function(self, usernameOrEmail, callback)
	if self ~= mod then
		error("system_api:getLoginOptions(usernameOrEmail, callback): use `:`", 2)
	end

	-- validate arguments
	if type(usernameOrEmail) ~= "string" then
		callback("1st arg must be a string", nil)
		return
	end
	if type(callback) ~= "function" then
		callback("2nd arg must be a function", nil)
		return
	end
	if usernameOrEmail == "" then
		callback("username is empy", nil)
		return
	end
	if callback == nil then
		callback("callback is nil", nil)
		return
	end

	-- get login options from API server
	local url = mod.kApiAddr .. "/get-login-options"
	local body = { usernameOrEmail = usernameOrEmail }
	local req = System:HttpPost(url, body, function(resp)
		if resp.StatusCode ~= 200 then
			if resp.StatusCode >= 500 then
				callback("internal server error", nil)
			elseif resp.StatusCode >= 400 then
				callback("bad request", nil)
			else
				callback("something went wrong", nil)
			end
			return
		end

		local res, err = JSON:Decode(resp.Body)
		if err ~= nil then
			callback("something went wrong", nil)
			return
		end

		callback(nil, res) -- success
	end)

	return req
end

-- callback(err) err == nil on success
mod.getMagicKey = function(_, usernameOrEmail, callback)
	if type(usernameOrEmail) ~= "string" then
		callback("1st arg must be a string")
		return
	end
	if type(callback) ~= "function" then
		callback("2nd arg must be a function")
		return
	end

	local url = mod.kApiAddr .. "/get-magic-key"
	local body = {
		["username-or-email"] = usernameOrEmail,
	}

	local req = System:HttpPost(url, body, function(resp)
		if resp.StatusCode ~= 200 then
			if resp.StatusCode >= 500 then
				callback("internal server error", nil)
			elseif resp.StatusCode >= 400 then
				callback("bad request", nil)
			else
				callback("something went wrong", nil)
			end
			return
		end

		callback(nil) -- success
	end)

	return req
end

-- callback(err, accountInfo)
mod.login = function(_, config, callback)
	local defaultConfig = {
		usernameOrEmail = "",
		magickey = "",
		password = "",
		passkeyCredentialIDBase64 = "",
		passkeyAuthenticatorDataBase64 = "",
		passkeyRawClientDataJSONString = "",
		passkeySignatureBase64 = "",
		passkeyUserIDString = "",
	}
	config = conf:merge(defaultConfig, config)

	local url = mod.kApiAddr .. "/login"
	local body = {
		["username-or-email"] = config.usernameOrEmail,
		["magic-key"] = config.magickey,
		password = config.password,
		passkeyCredentialIDBase64 = config.passkeyCredentialIDBase64,
		passkeyAuthenticatorDataBase64 = config.passkeyAuthenticatorDataBase64,
		passkeyRawClientDataJSONString = config.passkeyRawClientDataJSONString,
		passkeySignatureBase64 = config.passkeySignatureBase64,
		passkeyUserIDString = config.passkeyUserIDString,
	}

	local _ = System:HttpPost(url, body, function(resp)
		if resp.StatusCode ~= 200 then
			if resp.StatusCode >= 500 then
				callback("internal server error", nil)
			elseif resp.StatusCode >= 400 then
				callback("bad request", nil)
			else
				callback("something went wrong", nil)
			end
			return
		end

		-- print(resp.Body:ToString())
		local res, err = JSON:Decode(resp.Body)
		if err ~= nil then
			callback("json decode error:" .. err, nil)
			return
		end

		callback(nil, res) -- success
	end)
end

-- callback(err, credentials)
mod.signUp = function(_, username, key, dob, callback)
	if username == nil then
		username = ""
	end
	if key == nil then
		key = ""
	end
	if dob == nil then
		dob = ""
	end
	if type(username) ~= "string" then
		callback("1st arg must be a string")
		return
	end
	if type(key) ~= "string" then
		callback("2nd arg must be a string")
		return
	end
	if type(dob) ~= "string" then
		callback("3rd arg must be a string")
		return
	end
	if type(callback) ~= "function" then
		callback("4th arg must be a function")
		return
	end

	local url = mod.kApiAddr .. "/users"
	local body = {
		username = username,
		key = key,
		dob = dob,
	}

	local req = System:HttpPost(url, body, function(resp)
		if resp.StatusCode ~= 200 then
			callback("http status not 200")
			return
		end
		local res, err = JSON:Decode(resp.Body)
		if err ~= nil then
			callback("json decode error:" .. err)
			return
		end

		callback(nil, res.credentials) -- success
	end)

	return req
end

-- postSecret ...
-- callback(ok, errMsg)
moduleMT.postSecret = function(_, secret, callback)
	if type(secret) ~= "string" then
		callback(false, "1st arg must be a string")
		return
	end
	if type(callback) ~= "function" then
		callback(false, "2nd arg must be a function")
		return
	end
	local url = mod.kApiAddr .. "/secret"
	local body = {
		secret = secret,
	}
	local req = System:HttpPost(url, body, function(resp)
		if resp.StatusCode ~= 200 then
			callback(false, "http status not 200")
			return
		end
		local response, _ = JSON:Decode(resp.Body)
		callback(true, response.message) -- success
	end)
	return req
end

moduleMT.blockUser = function(_, userID, callback)
	if type(userID) ~= "string" then
		callback(false, "systemApi:blockUser(userID, callback) - userID must be a string")
		return
	end
	if callback ~= nil and type(callback) ~= "function" then
		callback(false, "systemApi:blockUser(userID, callback) - callback must be a function")
		return
	end
	local url = mod.kApiAddr .. "/users/self/block"
	local body = {
		id = userID,
	}
	local req = System:HttpPost(url, body, function(resp)
		if resp.StatusCode ~= 200 then
			if callback ~= nil then
				callback(false)
			end
			return
		end
		if callback ~= nil then
			local blockedUsers, err = JSON:Decode(resp.Body)
			if err ~= nil then
				callback(true, nil)
				return
			end
			callback(true, blockedUsers)
		end
	end)
	return req
end

moduleMT.unblockUser = function(_, userID, callback)
	if type(userID) ~= "string" then
		callback(false, "systemApi:unblockUser(userID, callback) - userID must be a string")
		return
	end
	if callback ~= nil and type(callback) ~= "function" then
		callback(false, "systemApi:unblockUser(userID, callback) - callback must be a function")
		return
	end
	local url = mod.kApiAddr .. "/users/self/unblock"
	local body = {
		id = userID,
	}
	local req = System:HttpPost(url, body, function(resp)
		if resp.StatusCode ~= 200 then
			if callback ~= nil then
				callback(false)
			end
			return
		end
		if callback ~= nil then
			local blockedUsers, err = JSON:Decode(resp.Body)
			if err ~= nil then
				callback(true, nil)
				return
			end
			callback(true, blockedUsers)
		end
	end)
	return req
end

-- search Users by username substring
-- callback(ok, users, errMsg)
-- ok: boolean
-- users: []User
-- errMsg: string
moduleMT.searchUser = function(_, searchText, callback)
	-- validate arguments
	if type(searchText) ~= "string" then
		error("system_api:searchUser(searchText, callback) - searchText must be a string", 2)
		return
	end
	if type(callback) ~= "function" then
		error("system_api:searchUser(searchText, callback) - callback must be a function", 2)
		return
	end
	local req = System:HttpGet(mod.kApiAddr .. "/user-search-others/" .. searchText, function(resp)
		if resp.StatusCode ~= 200 then
			callback(false, nil, "http status not 200")
			return
		end
		local users, err = JSON:Decode(resp.Body)
		if err ~= nil then
			callback(false, nil, "json decode error:" .. err)
			return
		end
		callback(true, users, nil) -- success
	end)
	return req
end

-- getFriends ...
-- callback(ok, friends, errMsg)
moduleMT.getFriends = function(_, callback)
	if type(callback) ~= "function" then
		error("api:getFriends(callback) - callback must be a function", 2)
		return
	end
	local req = System:HttpGet(mod.kApiAddr .. "/friend-relations", function(resp)
		if resp.StatusCode ~= 200 then
			callback(false, nil, "http status not 200: " .. resp.StatusCode)
			return
		end
		local friends, err = JSON:Decode(resp.Body)
		if err ~= nil then
			callback(false, nil, "json decode error:" .. err)
			return
		end
		callback(true, friends, nil) -- success
	end)
	return req
end

-- getFriendCount ...
-- callback(ok, count, errMsg)
moduleMT.getFriendCount = function(self, callback)
	if type(callback) ~= "function" then
		error("api:getFriendCount(callback) - callback must be a function", 2)
		return
	end
	local req = self:getFriends(function(ok, friends)
		local count = 0
		if friends ~= nil then
			count = #friends
		end
		callback(ok, count, nil)
	end)
	return req
end

-- sendFriendRequest ...
-- callback(ok, errMsg)
moduleMT.sendFriendRequest = function(_, userID, callback)
	if type(userID) ~= "string" then
		callback(false, "1st arg must be a string")
		error("api:sendFriendRequest(userID, callback) - userID must be a string", 2)
		return
	end
	if type(callback) ~= "function" then
		error("api:sendFriendRequest(userID, callback) - callback must be a function", 2)
		return
	end
	local url = mod.kApiAddr .. "/friend-request"
	local body = {
		senderID = Player.UserID,
		recipientID = userID,
	}
	local req = System:HttpPost(url, body, function(resp)
		if resp.StatusCode ~= 200 then
			callback(false, "http status not 200")
			return
		end
		callback(true, nil) -- success
	end)
	return req
end

-- cancelFriendRequest ...
-- callback(ok, errMsg)
moduleMT.cancelFriendRequest = function(_, recipientID, callback)
	if type(recipientID) ~= "string" then
		callback(false, "1st arg must be a string")
		return
	end
	if type(callback) ~= "function" then
		callback(false, "2nd arg must be a function")
		return
	end
	local url = mod.kApiAddr .. "/friend-request-cancel"
	local body = {
		senderID = Player.UserID,
		recipientID = recipientID,
	}
	local req = System:HttpPost(url, body, function(resp)
		if resp.StatusCode ~= 200 then
			callback(false, "http status not 200")
			return
		end
		callback(true, nil) -- success
	end)
	return req
end

-- replyToFriendRequest accepts or rejects a received friend request
-- callback(ok, errMsg)
moduleMT.replyToFriendRequest = function(_, usrID, accept, callback)
	-- validate arguments
	if type(usrID) ~= "string" then
		callback(false, "1st arg must be a string")
		return
	end
	if type(accept) ~= "boolean" then
		callback(false, "2nd arg must be a boolean")
		return
	end
	if type(callback) ~= "function" then
		callback(false, "3rd arg must be a function")
		return
	end
	local url = mod.kApiAddr .. "/friend-request-reply"
	local body = {
		senderID = usrID,
		accept = accept,
	}
	local req = System:HttpPost(url, body, function(resp)
		if resp.StatusCode ~= 200 then
			callback(false, "http status not 200")
			return
		end
		callback(true, nil) -- success
	end)
	return req
end

-- api:createWorld({title = "banana", category = nil, original = nil}, function(err, world))
moduleMT.createWorld = function(self, data, callback)
	local url = self.kApiAddr .. "/worlddrafts"
	local req = System:HttpPost(url, data, function(res)
		if res.StatusCode ~= 200 then
			callback(api:error(res.StatusCode, "could not create world"), nil)
			return
		end

		local world, err = JSON:Decode(res.Body)
		if err ~= nil then
			callback(api:error(res.StatusCode, "could not decode response"), nil)
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
		if world.maxPlayers ~= nil then
			world.maxPlayers = math.floor(world.maxPlayers)
		end

		callback(nil, world)
	end)
	return req
end

-- api:patchWorld("world-id", {title = "something", description = "banana"}, function(err, world))
moduleMT.patchWorld = function(self, worldID, data, callback)
	local url = self.kApiAddr .. "/worlds/" .. worldID
	local req = System:HttpPatch(url, data, function(res)
		if res.StatusCode ~= 200 then
			callback(api:error(res.StatusCode, "could not modify world"), nil)
			return
		end

		local world, err = JSON:Decode(res.Body)
		if err ~= nil then
			callback(api:error(res.StatusCode, "could not decode response"), nil)
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
		if world.maxPlayers ~= nil then
			world.maxPlayers = math.floor(world.maxPlayers)
		end

		callback(nil, world)
	end)
	return req
end

-- callback(err) (nil err on success)
moduleMT.setWorldIcon = function(self, worldID, data, callback)
	local urlStr = self:getWorldThumbnailUrl(worldID, nil)
	local urlStr250 = self:getWorldThumbnailUrl(worldID, 250) -- resized thumbnail

	-- upload new World's thumbnail
	local req = System:HttpPost(urlStr, data, function(res)
		if res.StatusCode ~= 200 then
			callback(api:error(res.StatusCode, "could not set world icon"))
			return
		end

		-- clear HTTP cache for the world's thumbnail
		-- no need to clear the original URL, the cache is automatically invalidated when the POST request is successful
		-- System:ClearHttpCacheForUrl(urlStr)
		-- Explicitly clear cache for resized thumbnail URL
		System:ClearHttpCacheForUrl(urlStr250)

		-- call callback
		callback(nil) -- success
	end)
	return req
end

moduleMT.likeWorld = function(self, worldID, addLike, callback)
	local url = self.kApiAddr .. "/worlds/" .. worldID .. "/likes"
	local t = { value = addLike }
	local body = JSON:Encode(t)
	local req = System:HttpPatch(url, body, function(res)
		if res.StatusCode ~= 200 then
			callback(api:error(res.StatusCode, "could not modify world's likes"), nil)
			return
		end
		callback(nil, nil)
	end)
	return req
end

moduleMT.likeItem = function(self, itemID, addLike, callback)
	local url = self.kApiAddr .. "/items/" .. itemID .. "/likes"
	local t = { value = addLike }
	local body = JSON:Encode(t)
	local req = System:HttpPatch(url, body, function(res)
		if res.StatusCode ~= 200 then
			callback(api:error(res.StatusCode, "could not modify item's likes"))
			return
		end
		callback(nil) -- success
	end)
	return req
end

-- api:createItem({name = "banana", category = nil, original = nil}, function(err, item))
-- to create a mesh: { name = "foo", type = "mesh", data = Data, offsetRotation = Rotation, scale = 10.0 }
moduleMT.createItem = function(self, data, callback)
	local url = self.kApiAddr .. "/itemdrafts"
	local req = System:HttpPost(url, data, function(res)
		if res.StatusCode ~= 200 then
			callback(api:error(res.StatusCode, "could not create item"), nil)
			return
		end

		local item, err = JSON:Decode(res.Body)
		if err ~= nil then
			callback(api:error(res.StatusCode, "could not decode response"), nil)
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

		callback(nil, item)
	end)
	return req
end

-- moduleMT.uploadItemFile = function(self, fileType, fileData, callback)
-- 	local url = self.kApiAddr .. "/items/file/" .. fileType
-- 	-- print("UPLOADING FILE TO:", url)
-- 	local req = System:HttpPost(url, fileData, function(res)
-- 		if res.StatusCode ~= 200 then
-- 			callback(api:error(res.StatusCode, "could not upload item file"))
-- 			return
-- 		end
-- 		local response, err = JSON:Decode(res.Body)
-- 		if err ~= nil then
-- 			callback(api:error(res.StatusCode, "could not decode response"), nil)
-- 			return
-- 		end
-- 		callback(nil, response) -- success
-- 	end)
-- end

-- api:patchItem("item-id", {description = "banana"}, function(err, item))
moduleMT.patchItem = function(self, itemID, data, callback)
	local url = self.kApiAddr .. "/itemdrafts/" .. itemID
	local req = System:HttpPatch(url, data, function(res)
		if res.StatusCode ~= 200 then
			callback(api:error(res.StatusCode, "could not modify item"), nil)
			return
		end

		local item, err = JSON:Decode(res.Body)
		if err ~= nil then
			callback(api:error(res.StatusCode, "could not decode response"), nil)
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

		callback(nil, item)
	end)
	return req
end

-- callback(err)
-- err is nil on success and a string error message on failure
moduleMT.updateAvatar = function(_, data, cb) -- data = { jacket="caillef.jacket", eyescolor={r=255, g=0, b=30} }
	local url = mod.kApiAddr .. "/users/self/avatar"
	local req = System:HttpPatch(url, {}, data, function(res)
		if res.StatusCode ~= 200 then
			cb("Error (" .. res.StatusCode .. "): can't update avatar.")
			return
		end
		cb(nil) -- success
	end)
	return req
end

-- info: table ({bio = "...", ...})
-- callback: function(err)
moduleMT.patchUserInfo = function(_, info, callback)
	local url = mod.kApiAddr .. "/users/self"

	if type(info) ~= "table" then
		error("system_api:patchUserInfo(info, callback): info should be a table", 2)
	end
	if type(callback) ~= "function" then
		error("system_api:patchUserInfo(info, callback): callback should be a function", 2)
	end

	local filterIsValid = function(k, v)
		-- key must be a string
		if type(k) ~= "string" then
			return false
		end
		-- supported value types
		local fieldExpectedType = {
			age = "number",
			bio = "string",
			discord = "string",
			dob = "string",
			github = "string",
			parentPhone = "string",
			parentPhoneVerifCode = "string",
			phone = "string",
			phoneVerifCode = "string",
			tiktok = "string",
			username = "string",
			usernameKey = "string",
			website = "string",
			x = "string",
		}
		local expectedType = fieldExpectedType[k]
		if expectedType ~= nil then
			return type(v) == expectedType
		end
		-- update this:
		return k == "bio" or k == "discord" or k == "x" or k == "tiktok" or k == "website"
	end

	for k, v in pairs(info) do
		if not filterIsValid(k, v) then
			System:Log("INVALID FILTER: " .. k .. " " .. v)
			error("system_api:patchUserInfo(info, callback): key or value is not valid: " .. k .. " " .. v, 2)
		end
	end

	local req = System:HttpPatch(url, info, function(res)
		if res.StatusCode ~= 200 then
			callback("Error (" .. res.StatusCode .. "): can't update user info")
			return
		end
		callback(nil)
	end)
	return req
end

-- callback(notifications or { count = 42 }, err)
mod.getNotifications = function(self, config, callback)
	if self ~= mod then
		error("api:getNotifications(config, callback): use `:`", 2)
	end
	if type(callback) ~= "function" then
		error("api:getNotifications(config, callback) - callback must be a function", 2)
	end

	local defaultConfig = {
		category = nil, -- string
		read = nil, -- boolean
		returnCount = nil, -- only returns count if `true` { count = 42}
	}

	local ok, err = pcall(function()
		config = require("config"):merge(defaultConfig, config, {
			acceptTypes = {
				category = { "string" },
				read = { "boolean" },
				returnCount = { "boolean" },
			},
		})
	end)

	if not ok then
		error("api:getNotifications(config, callback): config error (" .. err .. ")", 2)
	end

	local u = url:parse(mod.kApiAddr .. "/privileged/users/self/notifications")

	if config.category ~= nil then
		u:addQueryParameter("category", config.category)
	end
	if config.read ~= nil then
		u:addQueryParameter("read", config.read == true and "true" or "false")
	end
	if config.returnCount ~= nil then
		u:addQueryParameter("returnCount", config.returnCount == true and "true" or "false")
	end

	local req = System:HttpGet(u:toString(), function(res)
		if res.StatusCode ~= 200 then
			callback(nil, api:error(res.StatusCode, "status code: " .. res.StatusCode))
			return
		end

		local data, err = JSON:Decode(res.Body)
		if err ~= nil then
			callback(nil, api:error(res.StatusCode, "getNotifications JSON decode error: " .. err))
			return
		end

		if config.returnCount == true then
			if data.count ~= nil then
				callback(math.floor(data.count))
			else
				callback(nil, api:error(res.StatusCode, "returned count is nil"))
			end
			return
		end

		for _, v in ipairs(data) do
			if v.created then
				v.created = time.iso8601_to_os_time(v.created)
			end
		end
		callback(data)
	end)
	return req
end

mod.getWorldHistory = function(self, config, callback)
	if self ~= mod then
		error("api:getWorldHistory(config, callback): use `:`", 2)
	end
	if type(callback) ~= "function" then
		error("api:getWorldHistory(config, callback) - callback must be a function", 2)
	end

	local defaultConfig = {
		worldID = nil, -- string
	}

	local ok, err = pcall(function()
		config = require("config"):merge(defaultConfig, config, {
			acceptTypes = {
				worldID = { "string" },
			},
		})
	end)

	if not ok then
		error("api:getWorldHistory(config, callback): config error (" .. err .. ")", 2)
	end

	local u = url:parse(mod.kApiAddr .. "/worlds/" .. config.worldID .. "/history")

	local req = System:HttpGet(u:toString(), function(res)
		if res.StatusCode ~= 200 then
			callback(nil, api:error(res.StatusCode, "status code: " .. res.StatusCode))
			return
		end

		local data, err = JSON:Decode(res.Body)
		if err ~= nil then
			callback(nil, api:error(res.StatusCode, "getWorldHistory JSON decode error: " .. err))
			return
		end

		for _, v in data do
			if v.created then
				v.created = time.iso8601_to_os_time(v.created)
			end
		end
		callback(data)
	end)
	return req
end

mod.readNotifications = function(self, config)
	if self ~= mod then
		error("api:readNotifications(config): use `:`", 2)
	end

	local defaultConfig = {
		category = nil, -- string
		callback = nil, -- function(err)
	}

	local ok, err = pcall(function()
		config = require("config"):merge(defaultConfig, config, {
			acceptTypes = {
				category = { "string" },
				callback = { "function" },
			},
		})
	end)

	if not ok then
		error("api:readNotifications(config): config error (" .. err .. ")", 2)
	end

	local u = url:parse(mod.kApiAddr .. "/privileged/users/self/notifications")

	if config.category ~= nil then
		u:addQueryParameter("category", config.category)
	end
	u:addQueryParameter("read", "false")

	local body = {
		read = true,
	}

	local req = System:HttpPatch(u:toString(), body, function(res)
		if res.StatusCode ~= 200 then
			if config.callback ~= nil then
				config.callback(api:error(res.StatusCode, "status code: " .. res.StatusCode))
			end
			return
		end
		if config.callback ~= nil then
			config.callback(nil)
		end
	end)
	return req
end

-- getPasskeyChallenge obtains a challenge from the API server.
-- This is needed for Passkey creation and authentication.
--
-- Callback signature: request func(challenge, err)
-- request: http request object
-- challenge: string
-- err: nil on success, error message (string) on failure
mod.getPasskeyChallenge = function(self, callback)
	if self ~= mod then
		error("system_api:getPasskeyChallenge(callback): use `:`", 2)
	end
	if type(callback) ~= "function" then
		error("system_api:getPasskeyChallenge(callback) - callback must be a function", 2)
	end

	local u = url:parse(mod.kApiAddr .. "/users/self/passkey-challenge")

	local req = HTTP:Get(u:toString(), function(resp)
		if resp.StatusCode ~= 200 then
			callback(nil, "could not get passkey challenge (" .. resp.StatusCode .. ")")
			return
		end

		local responseObject, err = JSON:Decode(resp.Body)
		if err ~= nil then
			callback(nil, "JSON decode error: " .. err)
			return
		end
		-- success
		callback(responseObject.challenge, nil)
	end)
end

mod.report = function(self, config)
	if self ~= mod then
		error("api:report(config): use `:`", 2)
	end

	local defaultConfig = {
		worldID = nil,
		itemID = nil,
		message = nil,
		callback = nil,
	}

	local ok, err = pcall(function()
		config = require("config"):merge(defaultConfig, config, {
			acceptTypes = {
				worldID = { "string" },
				itemID = { "string" },
				message = { "string" },
				callback = { "function" },
			},
		})
	end)

	if not ok then
		error("api:report(config): config error (" .. err .. ")", 2)
	end

	local u = url:parse(mod.kApiAddr .. "/reports")

	local body = {
		worldID = config.worldID,
		itemID = config.itemID,
		message = config.message,
	}

	print("worldID:", config.worldID)
	print("itemID:", config.itemID)

	local req = System:HttpPost(u:toString(), body, function(res)
		if res.StatusCode ~= 200 then
			if config.callback ~= nil then
				config.callback(api:error(res.StatusCode, "status code: " .. res.StatusCode))
			end
			return
		end
		if config.callback ~= nil then
			config.callback(nil)
		end
	end)
	return req
end

-- ----------------------------------------------
-- Badges
-- ----------------------------------------------

-- badgeInfo: {
-- 	worldID = "",
-- 	icon = Data(),
-- 	tag = "",
-- 	name = "",        -- optional
-- 	description = "", -- optional
-- }
-- callback(err)
mod.createBadge = function(self, badgeInfo, callback)
	if self ~= mod then
		error("api:createBadge(config): use `:`", 2)
	end

	if badgeInfo == nil or type(badgeInfo) ~= "table" then
		error("api:createBadge(badgeInfo, callback): badgeInfo must be a table", 2)
	end
	if callback == nil or type(callback) ~= "function" then
		error("api:createBadge(badgeInfo, callback): callback must be a function", 2)
	end

	-- validate badgeInfo
	if badgeInfo.worldID == nil or type(badgeInfo.worldID) ~= "string" then
		error("api:createBadge(badgeInfo, callback): worldID must be a string", 2)
	end
	-- ...

	-- construct JSON payload
	local payloadJson = JSON:Encode({
		worldID = badgeInfo.worldID,
		imageBase64 = badgeInfo.icon:ToString({ format = "base64" }),
		tag = badgeInfo.tag,
		name = badgeInfo.name,
		description = badgeInfo.description,
	})

	-- send request
	local u = url:parse(mod.kApiAddr .. "/badges")
	local req = System:HttpPost(u:toString(), payloadJson, function(res)
		if res.StatusCode ~= 200 then
			if callback ~= nil then
				callback(api:error(res.StatusCode, res.Body))
			end
			return
		end

		callback(nil) -- success
	end)
	return req
end

-- badgeInfo argument:
-- {
-- 	badgeID = config.badgeObj.badgeID,
-- 	icon = badgeObject:getBadgeImageData(),
-- 	tag = tag,
-- 	name = name,
-- 	description = description,
-- }
mod.updateBadge = function(self, badgeInfo, callback)
	if self ~= mod then
		error("api:updateBadge(badgeInfo, callback): use `:`", 2)
	end

	if badgeInfo == nil or type(badgeInfo) ~= "table" then
		error("api:updateBadge(badgeInfo, callback): badgeInfo must be a table", 2)
	end
	if callback == nil or type(callback) ~= "function" then
		error("api:updateBadge(badgeInfo, callback): callback must be a function", 2)
	end

	-- validate badgeInfo
	if badgeInfo.badgeID == nil or type(badgeInfo.badgeID) ~= "string" then
		error("api:updateBadge(badgeInfo, callback): badgeInfo.badgeID must be a string", 2)
	end
	if badgeInfo.icon ~= nil and type(badgeInfo.icon) ~= "userdata" then -- TODO: gaetan: why not "Data"? Is this correct?
		error("api:updateBadge(badgeInfo, callback): badgeInfo.icon must be a Data object (or nil)", 2)
	end
	if badgeInfo.name ~= nil and type(badgeInfo.name) ~= "string" then
		error("api:updateBadge(badgeInfo, callback): badgeInfo.name must be a string (or nil)", 2)
	end
	if badgeInfo.description ~= nil and type(badgeInfo.description) ~= "string" then
		error("api:updateBadge(badgeInfo, callback): badgeInfo.description must be a string (or nil)", 2)
	end

	-- construct JSON payload
	local payload = {
		badgeID = badgeInfo.badgeID,
	}
	if badgeInfo.icon ~= nil then
		payload.imageBase64 = badgeInfo.icon:ToString({ format = "base64" })
	end
	if badgeInfo.name ~= nil then
		payload.name = badgeInfo.name
	end
	if badgeInfo.description ~= nil then
		payload.description = badgeInfo.description
	end

	local payloadJson = JSON:Encode(payload)

	-- send request
	local u = url:parse(mod.kApiAddr .. "/badges/" .. badgeInfo.badgeID)
	local req = System:HttpPatch(u:toString(), payloadJson, function(res)
		if res.StatusCode ~= 200 then
			if callback ~= nil then
				callback(api:error(res.StatusCode, "status code: " .. res.StatusCode))
			end
			return
		end

		-- if icon has been update, we clear the HTTP cache for the badge image
		if badgeInfo.icon ~= nil then
			-- https://api.cu.bzh/badges/5eee2343-51b3-49d1-be97-73af468aff49/thumbnail.png
			local urlBadgeThumbnail = mod.kApiAddr .. "/badges/" .. badgeInfo.badgeID .. "/thumbnail.png"
			System:ClearHttpCacheForUrl(urlBadgeThumbnail)
		end

		callback(nil) -- success
	end)
	return req
end

-- callback(err, unlocked: boolean)
mod.unlockBadge = function(self, worldId, badgeTag, callback)
	if self ~= mod then
		error("api:unlockBadge(worldId, badgeTag): use `:`", 2)
	end

	-- compute signature
	local signature = System:ComputeBadgeSignature(worldId, badgeTag)

	-- send request
	local u = url:parse(mod.kApiAddr .. "/users/self/badges")
	local body = {
		worldId = worldId,
		badgeTag = badgeTag,
		signature = signature,
	}
	local req = System:HttpPost(u:toString(), body, function(res)
		if res.StatusCode ~= 200 then
			if callback ~= nil then
				callback(api:error(res.StatusCode, res.Body))
			end
			return
		end

		-- read response body
		-- {"unlocked":true|false, "badgeId": "badge-id", "badgeName": "Badge Name"}

		local response, err = JSON:Decode(res.Body)
		if err ~= nil then
			callback(api:error(res.StatusCode, "JSON decode error: " .. err))
			return
		end

		callback(nil, response) -- success
	end)

	return req
end

-- callback(err)
mod.moderationDeleteAccount = function(self, userID, callback)
	if self ~= mod then
		error("api:moderationDeleteAccount(callback): use `:`", 2)
	end

	local u = url:parse(mod.kApiAddr .. "/admin/banuseraccount/" .. userID)
	local req = System:HttpDelete(u:toString(), {}, function(res)
		if res.StatusCode ~= 200 then
			callback(api:error(res.StatusCode, res.Body))
			return
		end

		callback(nil) -- success
	end)
	return req
end

return mod
