--- This module creates a modal that allows to manage friend relationships.

local friendsWindow = {}

local loc = require("localize")

local mt = {
	__index = {},
	__newindex = function()
		error("friends module is read-only", 2)
	end,
	__metatable = false,
}
setmetatable(friendsWindow, mt)

local uiAvatar = require("ui_avatar")
local theme = require("uitheme").current
local padding = theme.padding
local modal = require("modal")
local api = require("api", System)
local systemApi = require("system_api", System)
local CELL_PADDING = padding

-- list IDs
local LIST = {
	RECEIVED = 1,
	SENT = 2,
	FRIENDS = 3,
	SEARCH = 4,
}

local TITLES = {
	loc("Received (%d)"),
	loc("Sent (%d)"),
	loc("Friends (%d)"),
	loc("Search (%d)"),
}

local CELL_TYPE = {
	LOADING = 1,
	INVITE_FRIENDS = 2,
	FRIENDS = 3, -- there can be more than one friend on a row
	CATEGORY = 4,
}

-- uikit: optional, allows to provide specific instance of uikit
mt.__index.create = function(_, maxWidth, maxHeight, position, uikit)
	local ui = uikit or require("uikit")
	local content = modal:createContent()
	content.title = loc("Friends")
	content.icon = "👥"

	content.didBecomeActive = function()
		systemApi:readNotifications({
			category = "social",
			callback = function(err)
				if err == nil then
					LocalEvent:Send(LocalEvent.Name.NotificationCountDidChange)
					systemApi:getNotifications({ returnCount = true, read = false }, function(count, err)
						if err == nil then
							-- NOTE: on macOS, setting count to whatever value removes the badge
							System.NotificationCount = count
						end
					end)
				end
			end,
		})
	end

	local scroll
	local searchText
	local loading = true
	local showSent = false

	-- list of friends, requests (sent or received) or search
	local lists = {
		received = {},
		sent = {},
		friends = {},
		search = {},
	}

	local searchTimer
	local requests = {}
	local cachedAvatars = {}

	local cancelRequests = function()
		for _, r in ipairs(requests) do
			r:Cancel()
		end
		requests = {}
	end

	local cancelRequestsAndTimers = function()
		if searchTimer ~= nil then
			searchTimer:Cancel()
			searchTimer = nil
		end
		cancelRequests()
	end

	local idealReducedContentSize = function(_, width, height, minWidth)
		width = math.min(width, 500)
		width = math.max(minWidth, width)
		return Number2(width, height)
	end

	local node = ui:createFrame(Color(0, 0, 0, 0))

	node.onRemove = function()
		cancelRequestsAndTimers()
		-- this is necessary for lines to be unloaded
		--  and cells to cancel their requests
		scroll:flush()
		node.screenDidResizeListener:Remove()
		node.screenDidResizeListener = nil
		if helpPointer then
			helpPointer:remove()
			helpPointer = nil
		end
		for _, avatar in pairs(cachedAvatars) do
			avatar:remove()
		end
		cachedAvatars = {}
	end

	local retrieveFriendsLists = function(searchStr, keepScrollPosition)
		cancelRequestsAndTimers()

		searchText = searchStr
		loading = true
		local nbLists = 4
		local nbListsRetrieved = 0

		lists = {}
		lists[LIST.RECEIVED] = {}
		lists[LIST.SENT] = {}
		lists[LIST.FRIENDS] = {}
		lists[LIST.SEARCH] = {}

		listNumberOfEntries = {}
		listNumberOfEntries[LIST.RECEIVED] = 0
		listNumberOfEntries[LIST.SENT] = 0
		listNumberOfEntries[LIST.FRIENDS] = 0
		listNumberOfEntries[LIST.SEARCH] = 0

		node:resetList()
		keepScrollPosition = keepScrollPosition or false

		local function newListResponse(listID, list)
			lists[listID] = list or {}
			nbListsRetrieved = nbListsRetrieved + 1
			if nbListsRetrieved < nbLists then
				return
			end

			if searchText and #searchText > 0 then
				-- filter out search list
				-- remove this part once backend handles that
				for k = #lists[LIST.SEARCH], 1, -1 do
					local user = lists[LIST.SEARCH][k]
					local idFound = false
					for _, v in ipairs(lists[LIST.FRIENDS]) do
						if v.id == user.id then
							idFound = true
						end
					end
					for _, v in ipairs(lists[LIST.RECEIVED]) do
						if v.id == user.id then
							idFound = true
						end
					end
					for _, v in ipairs(lists[LIST.SENT]) do
						if v.id == user.id then
							idFound = true
						end
					end
					if idFound then
						table.remove(lists[LIST.SEARCH], k)
					end
				end
			end

			listNumberOfEntries[LIST.RECEIVED] = #lists[LIST.RECEIVED]
			listNumberOfEntries[LIST.SENT] = #lists[LIST.SENT]
			listNumberOfEntries[LIST.FRIENDS] = #lists[LIST.FRIENDS]
			listNumberOfEntries[LIST.SEARCH] = #lists[LIST.SEARCH]

			loading = false

			node:resetList(keepScrollPosition)
		end

		local function requestList(methodName, listID, searchText)
			local list = {}

			if listID == LIST.SEARCH then
				if searchText == nil or searchText == "" then
					newListResponse(listID, list)
					return
				end
				local req = api:searchUser(searchText, function(ok, users, err)
					if not ok then
						newListResponse(listID, list) -- set empty list
						error("request failed: " .. err)
					end
					if #users == 0 then
						newListResponse("search", {})
					end
					for _, usr in ipairs(users) do
						if usr and usr.username ~= "" then
							table.insert(list, usr)
						end
					end
					newListResponse(listID, list)
				end)
				table.insert(requests, req)
				return
			end

			local req = api[methodName](api, { fields = { "id", "username", "lastSeen" } }, function(users, err)
				if err ~= nil then
					newListResponse(listID, list) -- set empty list
					error("request failed: " .. err.message)
				end
				if #users == 0 then
					newListResponse(listID, {})
					return
				end
				for _, usr in ipairs(users) do
					-- if search, match the username
					if usr.username == "" then
						usr.username = Players.DefaultUsername
					end
					if not searchText or string.find(usr.username, searchText) then
						table.insert(list, usr)
					end
				end
				newListResponse(listID, list)
			end)
			table.insert(requests, req)
		end

		requestList("getFriends", LIST.FRIENDS, searchText)
		requestList("getReceivedFriendRequests", LIST.RECEIVED, searchText)
		requestList("getSentFriendRequests", LIST.SENT, searchText)
		requestList("searchUser", LIST.SEARCH, searchText)
	end

	local getSearchBar = function()
		local searchBarContainer = ui:createFrame()
		local textInput = ui:createTextInput("", "🔎 search...")
		textInput:setParent(searchBarContainer)

		searchBarContainer.parentDidResize = function()
			searchBarContainer.Width = searchBarContainer.parent.Width
			searchBarContainer.Height = textInput.Height
			textInput.Width = searchBarContainer.Width
		end

		textInput.onTextChange = function(_)
			cancelRequestsAndTimers()
			searchTimer = Timer(0.3, function()
				cancelRequests()
				searchTimer = nil
				retrieveFriendsLists(textInput.Text, false)
			end)
		end
		return searchBarContainer
	end

	local searchBar = getSearchBar()
	searchBar:setParent(node)

	node.parentDidResize = function(_)
		searchBar.Width = node.Width
		searchBar.pos = { 0, node.Height - searchBar.Height }

		if node.scroll then
			node.scroll.Width = node.Width
			node.scroll.Height = node.Height - searchBar.Height
		end
	end

	local computeCellSize = function()
		local w = 170
		local h = 100
		-- 2 buttons + 1 label stacked vertically
		local btn = ui:buttonSecondary({ content = "foo", textSize = "small" })
		local label = ui:createText("username1234567", Color.White, "small") -- usernames are 15 chars max
		-- 3 paddings between buttons & label +  padding around label within frame
		h = math.max(h, btn.Height * 2 + label.Height + padding * 5)
		w = math.max(w, label.Width + padding * 2)

		btn:remove()
		label:remove()
		return w, h
	end

	local cellWidth, cellHeight = computeCellSize()
	node.screenDidResizeListener = LocalEvent:Listen(LocalEvent.Name.ScreenDidResize, function()
		cellWidth, cellHeight = computeCellSize()
		node:resetList()
	end, { topPriority = true })

	local createFriendCell = function(config)
		local forceWidth = config.width
		local forceHeight = config.height

		local cell = ui:frameScrollCell()
		cell:setParent(nil)

		local textBg = ui:frame({ color = Color(0, 0, 0, 0.5) })
		textBg:setParent(cell)
		textBg:hide()
		cell.textBg = textBg

		local textName = ui:createText("", Color.White, "small")
		textName:setParent(textBg)
		textName.pos = { padding, padding }

		local textStatus = ui:createText("", Color.White, "small")
		textStatus:setParent(textBg)

		local btnPrimary = ui:buttonSecondary({ content = "", textSize = "small" })
		btnPrimary:setParent(cell)
		btnPrimary.pos = { padding, padding }

		local btnSecondary = ui:buttonSecondary({ content = "", textSize = "small" })
		btnSecondary:setParent(cell)
		btnSecondary.pos = { btnPrimary.pos.X, btnPrimary.pos.Y + btnPrimary.Height + padding }

		local avatar

		cell.parentDidResize = function()
			cell.Height = forceHeight or cellHeight
			cell.Width = forceWidth or cell.Height

			textBg.Width = textName.Width + padding * 2
			textBg.Height = textName.Height + padding * 2
			textBg.pos.Y = cell.Height - textBg.Height

			if avatar then
				avatar.Height = cell.Height -- avatars are spherized, so there's enough margin already
				avatar.pos = { cell.Width * 0.666 - avatar.Width * 0.5, cell.Height * 0.5 - avatar.Height * 0.5 }
			end

			btnPrimary.pos = { padding, padding }
			btnSecondary.pos = { btnPrimary.pos.X, btnPrimary.pos.Y + btnPrimary.Height + padding }

			-- display in front of shape
			textBg.LocalPosition.Z = -600
			btnPrimary.LocalPosition.Z = -600
			btnSecondary.LocalPosition.Z = -600
		end

		cell.setUser = function(self, user)
			if not user or not user.username then
				return
			end

			cell.username = user.username
			cell.userID = user.id
			textBg.LocalPosition.Z = -600

			textName.Text = user.username
			-- TODO: handle status
			textStatus.Text = ""

			self.textBg:show()

			cell.loadTimer = Timer(0.5, function()
				self.loadTimer = nil

				cell.onRelease = function()
					local profileContent = require("profile"):create({
						username = user.username,
						userID = user.id,
						uikit = ui,
					})
					content:push(profileContent)
				end
				cell.onPress = function()
					-- cell:setColor(Color(35, 35, 35))
				end
				cell.onCancel = function()
					-- cell:setColor(Color(63, 63, 63))
				end

				avatar = cachedAvatars[user.id]
				if avatar == nil then
					local requests
					avatar, requests = uiAvatar:get({ usernameOrId = user.id, size = cell.Height * 0.95, ui = ui })

					cell.avatarRequests = requests
					avatar.body.pivot.LocalRotation = Rotation(math.rad(-22), 0, 0) * Rotation(0, math.rad(145), 0)
					cachedAvatars[user.id] = avatar

					avatar.didLoad = function()
						avatar.loaded = true
						cell.avatarRequests = nil
					end
				end
				if not avatar.loaded and cell.avatarRequests == nil then
					local requests = avatar:load({ usernameOrId = user.username })
					cell.avatarRequests = requests
				end
				avatar:setParent(cell)

				cell.avatar = avatar

				if cell.parentDidResize then
					cell:parentDidResize()
				end
			end)
		end

		cell.setType = function(self, cellType)
			if cellType == LIST.RECEIVED then
				btnPrimary.Text = "✅ Accept"
				btnPrimary:show()
				btnPrimary.onRelease = function()
					System:DebugEvent("User presses Accept Friend button")
					local req = systemApi:replyToFriendRequest(cell.userID, true, function(ok, _)
						if not ok then
							return
						end
						LocalEvent:Send(LocalEvent.Name.NotificationCountDidChange)
						retrieveFriendsLists(nil, true)
					end)
					table.insert(requests, req)
				end
				btnSecondary.Text = "❌"
				btnSecondary:show()
				btnSecondary.onRelease = function()
					local req = systemApi:replyToFriendRequest(cell.userID, false, function(ok, _)
						if not ok then
							return
						end
						LocalEvent:Send(LocalEvent.Name.NotificationCountDidChange)
						retrieveFriendsLists(nil, true)
					end)
					table.insert(requests, req)
				end
			elseif cellType == LIST.SENT then
				btnPrimary.Text = "❌ Cancel"
				btnPrimary:show()
				btnPrimary.onRelease = function()
					local req = systemApi:cancelFriendRequest(cell.userID, function(ok, _)
						if not ok then
							return
						end
						retrieveFriendsLists(nil, true)
					end)
					table.insert(requests, req)
				end
				btnSecondary.Text = ""
				btnSecondary:hide()
				btnSecondary.onRelease = nil
			elseif cellType == LIST.FRIENDS then
				btnPrimary.Text = "🌎 Join"
				btnPrimary:show()
				btnPrimary.onRelease = function()
					Menu:ShowAlert({ message = "Coming soon!" }, System)
				end
				btnSecondary.Text = "💬"
				btnSecondary:show()
				btnSecondary.onRelease = function()
					Menu:ShowAlert({ message = "Coming soon!" }, System)
				end
			elseif cellType == LIST.SEARCH then
				btnPrimary.Text = "➕ Add friend"
				btnPrimary:show()
				btnPrimary.onRelease = function()
					System:DebugEvent("User presses Add Friend button")
					local req = systemApi:sendFriendRequest(cell.userID, function(ok, _)
						if not ok then
							return
						end
						retrieveFriendsLists(searchText, true)
					end)
					table.insert(requests, req)
				end
				btnSecondary.Text = ""
				btnSecondary:hide()
				btnSecondary.onRelease = nil
			end
			self:parentDidResize()
		end

		return cell
	end

	local getContentForLine = function(lineNumber, nbCellsPerLine)
		local l = 1
		while l <= #lists do
			if listNumberOfEntries[l] == 0 then
				l = l + 1 -- nothing in that list, look in next one
			elseif showSent == false and l == LIST.SENT and lineNumber > 1 then
				lineNumber = lineNumber - 1
				l = l + 1
			elseif lineNumber == 1 then
				return lists[l], l, true -- first line : title
			else
				local nbLinesForList = math.floor(listNumberOfEntries[l] / nbCellsPerLine)
					+ (listNumberOfEntries[l] % nbCellsPerLine > 0 and 1 or 0)

				if lineNumber - 1 <= nbLinesForList then
					local start = (lineNumber - 2) * nbCellsPerLine + 1
					local stop = math.min(start + nbCellsPerLine - 1, listNumberOfEntries[l])
					return lists[l], l, nil, { start, stop }
				else
					l = l + 1
					lineNumber = lineNumber - 1 - nbLinesForList
				end
			end
		end
	end

	local titleCells = {}
	local friendRows = {}
	local friendCells = {}

	local function recycleFriendRow(row)
		for _, cell in ipairs(row.cells) do
			if cell.loadTimer then
				cell.loadTimer:Cancel()
				cell.loadTimer = nil
			end

			if cell.avatarRequests then
				for _, r in ipairs(cell.avatarRequests) do
					r:Cancel()
				end
				cell.avatarRequests = nil
			end

			if cell.avatar then
				cell.avatar:setParent(nil)
				cell.avatar = nil
			end

			cell:setParent(nil)
			table.insert(friendCells, cell)
		end
		row.cells = {}
		row:setParent(nil)
		table.insert(friendRows, row)
	end

	local loadCell = function(cellId)
		if loading == true then
			if cellId == 1 then
				local cell = ui:frame()
				cell:setParent(nil)
				cell.type = CELL_TYPE.LOADING

				local text = ui:createText("Loading...", Color.White)
				text:setParent(cell)
				cell.Height = math.floor(cellHeight * 1.5)
				cell.parentDidResize = function(self)
					local parent = self.parent
					self.Width = parent.Width
					text.pos = { self.Width * 0.5 - text.Width * 0.5, self.Height * 0.5 - text.Height * 0.5 }
				end
				return cell
			end
			return
		end

		local nbResults = 0
		for _, n in ipairs(listNumberOfEntries) do
			nbResults = nbResults + n
		end

		if nbResults == 0 then
			if cellId == 1 then
				local cell = ui:frame()
				cell:setParent(nil)
				cell.type = CELL_TYPE.INVITE_FRIENDS

				local isSearch = searchText and #searchText > 0
				if not isSearch and searchBar then
					helpPointer = helpPointer or require("ui_pointer"):create({ uikit = ui })
					helpPointer:pointAt({ target = searchBar, from = "below" })
				end
				local str = isSearch and "No users found. 🤨" or "Invite your friends! 🙂"
				local text = ui:createText(str, Color.White)
				text:setParent(cell)
				cell.Height = math.floor(cellHeight * 1.5)
				cell.parentDidResize = function(self)
					local parent = self.parent
					self.Width = parent.Width
					text.pos = { self.Width * 0.5 - text.Width * 0.5, self.Height * 0.5 - text.Height * 0.5 }
				end
				return cell
			end
			return
		end

		local width = node.Width - CELL_PADDING * 2
		local nbCellsPerLine = math.floor(width / cellWidth)
		local adaptedCellWidth = math.floor((width + CELL_PADDING) / nbCellsPerLine) - CELL_PADDING

		local list, listID, title, range = getContentForLine(cellId, nbCellsPerLine)

		if title then
			local cell = table.remove(titleCells)
			if cell == nil then
				cell = ui:frame({ color = Color(0, 0, 0, 0.5) })
				cell:setParent(nil)
				cell.type = CELL_TYPE.CATEGORY

				local text = ui:createText("", Color.White)
				text:setParent(cell)
				text.pos = { padding, padding }
				cell.text = text

				local arrow = ui:buttonSecondary({ content = "⬆️", textColor = Color.White, textSize = "small" })
				arrow:setParent(cell)
				cell.arrow = arrow

				cell.Height = text.Height + padding * 2

				cell.parentDidResize = function(self)
					local parent = self.parent
					cell.Width = parent.Width
					cell.arrow.pos =
						{ cell.Width - cell.arrow.Width - padding, cell.Height * 0.5 - cell.arrow.Height * 0.5 }
				end
			end

			cell.Color = Color(0, 0, 0, 0.5)

			local titleStr = TITLES[listID]
			titleStr = string.format(titleStr, listNumberOfEntries[listID])
			cell.text.Text = titleStr

			if listID == LIST.SENT then
				cell.arrow:show()
				if showSent then
					cell.arrow.Text = "⬆️"
				else
					cell.arrow.Text = "⬇️"
				end

				cell.arrow.onRelease = function()
					cell.Color = Color(0, 0, 0, 0.5)
					showSent = not showSent
					node:resetList(true)
				end
			else
				cell.arrow:hide()
				cell.onRelease = function() end
			end

			return cell
		end

		if list and range then
			local row = table.remove(friendRows)
			if row == nil then
				row = ui:frame()
				row:setParent(nil)
				row.type = CELL_TYPE.FRIENDS

				row.cells = {}
				row.parentDidResize = function(self)
					local parent = self.parent
					self.Width = parent.Width
					for i, c in ipairs(self.cells) do
						c.pos.X = (adaptedCellWidth + padding) * (i - 1)
					end
				end
			end

			row.Height = cellHeight

			local start = range[1]
			for i = start, range[2] do
				local cell = table.remove(friendCells)
				if cell == nil then
					cell = createFriendCell({ width = adaptedCellWidth, height = cellHeight })
				end

				cell:setParent(row)
				table.insert(row.cells, cell)

				cell:setUser(list[i])
				cell:setType(listID)
			end

			return row
		end
	end

	local config = {
		backgroundColor = theme.buttonTextColor,
		padding = {
			top = CELL_PADDING,
			bottom = CELL_PADDING,
			left = CELL_PADDING,
			right = CELL_PADDING,
		},
		cellPadding = CELL_PADDING,
		loadCell = loadCell,
		unloadCell = function(_, cell)
			if cell.type == CELL_TYPE.LOADING then
				cell:remove()
			elseif cell.type == CELL_TYPE.INVITE_FRIENDS then
				cell:remove()
			elseif cell.type == CELL_TYPE.CATEGORY then
				cell:setParent(nil)
				table.insert(titleCells, cell)
			elseif cell.type == CELL_TYPE.FRIENDS then
				recycleFriendRow(cell)
			end
		end,
	}

	scroll = ui:scroll(config)

	scroll:setParent(node)
	node.scroll = scroll

	node.resetList = function(keepScrollPosition)
		local scrollPosition = keepScrollPosition and scroll.scrollPosition or 0
		scroll:flush()
		if helpPointer then
			helpPointer:remove()
			helpPointer = nil
		end
		scroll:setScrollPosition(scrollPosition)
		scroll:refresh()
	end

	node:resetList()
	retrieveFriendsLists()

	content.node = node
	content.idealReducedContentSize = idealReducedContentSize

	local _modal = require("modal"):create(content, maxWidth, maxHeight, position, ui)
	return _modal
end

return friendsWindow
