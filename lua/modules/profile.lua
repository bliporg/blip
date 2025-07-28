profile = {}

local loc = require("localize")

-- MODULES
api = require("api", System)
systemApi = require("system_api", System)
modal = require("modal")
theme = require("uitheme").current
uiAvatar = require("ui_avatar")
str = require("str")

-- CONSTANTS

local AVATAR_MAX_SIZE = 300
local AVATAR_MIN_SIZE = 200
local ACTIVE_NODE_MARGIN = theme.paddingBig

local AVATAR_NODE_RATIO = 1

--- Creates a profile modal content
--- positionCallback(function): position of the popup
--- config(table): isLocal, id, username
--- returns: modal content
profile.create = function(_, config)
	local defaultConfig = {
		userID = "",
		username = "",
		uikit = require("uikit"), -- allows to provide specific instance of uikit
		editAvatar = nil,
	}

	local ok, err = pcall(function()
		config = require("config"):merge(defaultConfig, config, {
			acceptTypes = {
				editAvatar = { "function" },
			},
		})
	end)
	if not ok then
		error("profile:create(config) - config error: " .. err, 2)
	end

	local username
	local userID
	local isLocal = config.userID == Player.UserID

	if isLocal then
		username = Player.Username
		userID = Player.UserID
	else
		username = config.username
		userID = config.userID
	end

	if userID == nil then
		error("profile.create called without a userID", 2)
	end

	local ui = config.uikit

	-- nodes beside avatar
	local activeNode = nil
	local infoNode

	local functions = {}

	local profileNode = ui:createFrame()
	profileNode.Width = 200
	profileNode.Height = 200

	local content = modal:createContent()

	local title = username
	content.title = title
	content.icon = "🙂"
	content.node = profileNode

	local cell = ui:frame() -- { color = Color(100, 100, 100) }
	cell.Height = 100
	cell:setParent(nil)

	local scroll = ui:scroll({
		-- backgroundColor = Color(255, 0, 0),
		backgroundColor = theme.buttonTextColor,
		-- backgroundColor = Color(0, 255, 0, 0.3),
		-- gradientColor = Color(37, 23, 59), -- Color(155, 97, 250),
		padding = {
			top = theme.padding,
			bottom = theme.padding,
			left = theme.padding,
			right = theme.padding,
		},
		cellPadding = theme.padding,
		centerContent = true,
		loadCell = function(index)
			if index == 1 then
				return cell
			end
		end,
		unloadCell = function(_, _) end,
	})
	scroll:setParent(profileNode)

	local requests = {}

	profileNode.onRemove = function()
		for _, req in ipairs(requests) do
			req:Cancel()
		end
		requests = {}
	end

	local avatarNode = uiAvatar:get({ usernameOrId = userID, ui = ui })
	avatarNode:setParent(cell)

	local avatarRot = Number3(0, math.pi, 0)
	avatarNode.onDrag = function(self, pointerEvent)
		if avatarNode.body.pivot ~= nil then
			avatarRot.Y = avatarRot.Y - pointerEvent.DX * 0.02
			avatarRot.X = avatarRot.X + pointerEvent.DY * 0.02

			if avatarRot.X > math.pi * 0.4 then
				avatarRot.X = math.pi * 0.4
			end
			if avatarRot.X < -math.pi * 0.4 then
				avatarRot.X = -math.pi * 0.4
			end

			self.body.pivot.LocalRotation = Rotation(avatarRot.X, 0, 0) * Rotation(0, avatarRot.Y, 0)
		end
	end

	local userInfo = {
		bio = "",
		discord = "",
		tiktok = "",
		x = "",
		github = "",
		nbFriends = 0,
		created = nil,
		verified = false,
		blocked = false,
	}

	for _, uID in ipairs(System.BlockedUsers) do
		if uID == userID then
			userInfo.blocked = true
			break
		end
	end

	local blockBtn
	local deleteAccountBtn
	if not isLocal then
		blockBtn = ui:button({ 
			content = "",
			textSize = "small",
			borders = false,
			padding = false,
			textColor = userInfo.blocked and Color(150, 150, 150) or theme.errorTextColor,
			color = Color(0, 0, 0, 0),
		})
		blockBtn.onRelease = function(self)
			local msg
			if userInfo.blocked then
				msg = "Are you sure you want to unblock " .. username .. "?"
			else
				msg = "Are you sure you want to block " .. username .. "?"
			end
			Menu:ShowAlert({
				message = msg,
				positiveCallback = function() 
					userInfo.blocked = not userInfo.blocked
					if userInfo.blocked then
						systemApi:blockUser(userID, function(success, blockedUsers)
							if success and blockedUsers ~= nil then
								System.BlockedUsers = blockedUsers
							end
						end)
					else
						systemApi:unblockUser(userID, function(success, blockedUsers)
							if success and blockedUsers ~= nil then
								System.BlockedUsers = blockedUsers
							end
						end)
					end
					infoNode:setUserInfo()
				end,
				negativeCallback = function() end,
			}, System)
		end
		blockBtn:setParent(cell)

		if Player.Username == "aduermael" or Player.Username == "gaetan" then
			deleteAccountBtn = ui:button({ 
				content = "💀 Delete Account", 
				textSize = "small", 
				borders = false,
				padding = false, 
				textColor = theme.errorTextColor,
				color = Color(0, 0, 0, 0),
			})
			deleteAccountBtn.onRelease = function()
				Menu:ShowAlert({
					message = "Are you sure you want to delete this account?",
					positiveCallback = function() 
						-- TODO: send request
						print("content:", content)
						local m = content:getModalIfContentIsActive()
						if m ~= nil then
							m:close()
						end
					end,
					negativeCallback = function() end,
				}, System)
			end
			deleteAccountBtn:setParent(cell)
		end
	end

	-- functions to create each node

	local creationsBtn
	local addFriendBtn
	local acceptFriendBtn
	local friendText
	local doneBtn

	local createInfoNode = function()
		local socialBtnsConfig = {
			{
				key = "discord",
				icon = "images/icon-discord.png",
				action = function(str)
					Dev:CopyToClipboard(str)
				end,
				prefix = "@",
			},
			{
				key = "tiktok",
				icon = "images/icon-tiktok.png",
				action = function(str)
					URL:Open("https://www.tiktok.com/@" .. str)
				end,
				prefix = "@",
			},
			{
				key = "x",
				icon = "images/icon-x.png",
				action = function(str)
					URL:Open("https://x.com/" .. str)
				end,
				prefix = "@",
			},
			{
				key = "github",
				icon = "images/icon-github.png",
				action = function(str)
					URL:Open("https://github.com/" .. str)
				end,
				prefix = "",
			},
		}

		local node = ui:frame()

		local editAvatarBtn
		local editBioBtn
		local editLinksBtn

		if isLocal then
			if config.editAvatar ~= nil then
				editAvatarBtn = ui:buttonSecondary({ content = loc("✏️ Edit avatar"), textSize = "small" })
				editAvatarBtn:setParent(node)

				editAvatarBtn.onRelease = function()
					config.editAvatar()
				end
			end

			editBioBtn = ui:buttonSecondary({ content = loc("✏️ Edit bio"), textSize = "small" })
			editBioBtn:setParent(node)

			editBioBtn.onRelease = function()
				System.MultilineInput(
					userInfo.bio,
					"Your bio",
					"Describe yourself with 140 characters",
					"",
					140,
					function(text) -- done
						userInfo.bio = text
						local data = { bio = userInfo.bio }
						-- TODO: we could use `api` instead of `require("system_api", System)`
						systemApi:patchUserInfo(data, function(err)
							if err then
								print("❌", err)
							end
						end)
						node:setUserInfo()
						ui:turnOn()
					end,
					function() -- cancel
						ui:turnOn()
					end
				)
				ui:turnOff()
			end

			editLinksBtn = ui:buttonSecondary({ content = loc("✏️ Edit links"), textSize = "small" })
			editLinksBtn:setParent(node)

			editLinksBtn.onRelease = function()
				functions.setActiveNode(functions.createEditInfoNode())
			end

			doneBtn = ui:buttonPositive({ content = "Done", textSize = "default" })
			doneBtn:setParent(nil)

			doneBtn.onRelease = function()
				functions.setActiveNode(infoNode)
				infoNode:setUserInfo()
			end
		end

		friendText = ui:createText("", { color = Color.White, size = "small" })
		friendText:setParent(node)
		friendText:hide()

		local friends = ui:createText("👥 0", Color.White)
		friends:setParent(node)

		local created = ui:createText("📰 ", Color.White)
		created:setParent(node)

		local bioText = ui:createText(userInfo.bio, { color = Color.White, size = "small" })
		bioText:setParent(node)

		local socialBtns = {}
		for _, config in ipairs(socialBtnsConfig) do
			local btn = ui:frame()
			local label = ui:createText("", { color = theme.urlColor, size = "small" })
			label:setParent(btn)
			local icon = ui:frame({
				image = {
					data = Data:FromBundle(config.icon),
					alpha = true,
				},
			})
			icon.Width = label.Height
			icon.Height = icon.Width
			icon:setParent(btn)
			icon.pos = { theme.paddingTiny, theme.paddingTiny + label.Height * 0.5 - icon.Height * 0.5 }
			label.pos = { icon.pos.X + icon.Width + theme.padding, theme.paddingTiny }
			btn.Height = label.Height + theme.paddingTiny * 2

			btn.label = label
			btn.icon = icon
			
			btn:setParent(node)
			btn:hide()
			socialBtns[config.key] = btn
		end

		node.parentDidResize = function(self)
			self:refresh()
		end

		node.refresh = function(self)
			local parent = self.parent
			local padding = theme.padding

			self.Width = parent.Width

			local totalHeight = created.Height

			if editAvatarBtn then
				totalHeight = totalHeight + editAvatarBtn.Height + padding
			end

			local listVisibleSocialButtons = {}
			for _, v in pairs(socialBtns) do
				if v:isVisible() then
					table.insert(listVisibleSocialButtons, v)
				end
			end

			if bioText.Text ~= "" then
				bioText.object.MaxWidth = self.Width - padding * 2
				totalHeight = totalHeight + bioText.Height + padding
			end

			if editBioBtn then
				totalHeight = totalHeight + editBioBtn.Height + padding
			end

			if #listVisibleSocialButtons > 0 then
				local btnListHeight = math.ceil(#listVisibleSocialButtons / 2) * (socialBtns.tiktok.Height + padding)
				totalHeight = totalHeight + btnListHeight + padding
			end

			if editLinksBtn then
				totalHeight = totalHeight + editLinksBtn.Height + padding
			end

			self.Height = totalHeight

			local cursorY = self.Height

			if editAvatarBtn then
				cursorY = cursorY - editAvatarBtn.Height - padding
				editAvatarBtn.pos = { self.Width * 0.5 - editAvatarBtn.Width * 0.5, cursorY }
			end

			-- stats
			cursorY = cursorY - created.Height - padding
			local bottomLineWidth = friends.Width
				+ theme.paddingBig
				+ created.Width

			friends.pos = { self.Width * 0.5 - bottomLineWidth * 0.5, cursorY }
			created.pos = { friends.pos.X + friends.Width + theme.paddingBig, cursorY }

			if bioText.Text ~= "" then
				bioText.pos = { self.Width * 0.5 - bioText.Width * 0.5, cursorY - bioText.Height - padding }
				cursorY = bioText.pos.Y
			end

			if editBioBtn then
				cursorY = cursorY - editBioBtn.Height - padding
				editBioBtn.pos = { self.Width * 0.5 - editBioBtn.Width * 0.5, cursorY }
			end

			-- Place middle block (socials)
			if #listVisibleSocialButtons > 0 then
				for i = 1, #listVisibleSocialButtons, 2 do -- iterate 2 by 2 to place 2 buttons on the same line
					local btn1 = listVisibleSocialButtons[i]
					local btn2 = listVisibleSocialButtons[i + 1]

					cursorY = cursorY - btn1.Height - padding

					if not btn2 then
						btn1.pos = { self.Width * 0.5 - btn1.Width * 0.5, cursorY }
					else
						local fullwidth = btn1.Width + btn2.Width + padding
						btn1.pos = { self.Width * 0.5 - fullwidth * 0.5, cursorY }
						btn2.pos = { self.Width * 0.5 + fullwidth * 0.5 - btn2.Width, cursorY }
					end
				end
			end

			if editLinksBtn then
				cursorY = cursorY - editLinksBtn.Height - padding
				editLinksBtn.pos = { self.Width * 0.5 - editLinksBtn.Width * 0.5, cursorY }
			end
		end

		node.setUserInfo = function(_)
			friends.Text = "👥 " .. tostring(userInfo.nbFriends)

			if userInfo.created ~= nil then
				local creationDateIso = userInfo.created
				local creationDateTable = require("time"):iso8601ToTable(creationDateIso)
				local creationYear = creationDateTable.year
				local creationMonth = require("time"):monthToString(math.floor(creationDateTable.month))
				local createdStr = creationMonth .. " " .. creationYear

				created.Text = "📰 " .. createdStr
			else
				created.Text = "📰"
			end

			if blockBtn ~= nil then
				blockBtn.textColor = userInfo.blocked and Color(150, 150, 150) or theme.errorTextColor
				blockBtn.Text = userInfo.blocked and "Unblock" or "Block"
			end

			bioText.Text = str:trimSpaces(userInfo.bio or "")

			local charWidth
			local emojiWidth
			do
				local aChar = ui:createText("a", nil, "small")
				charWidth = aChar.Width
				aChar:remove()

				local anEmoji = ui:createText("👾", nil, "small")
				emojiWidth = anEmoji.Width
				anEmoji:remove()
			end

			local availableWidth = activeNode.Width / 2
				- ACTIVE_NODE_MARGIN * 2
				- theme.padding * 2
				- emojiWidth
				- charWidth * 2
			local nbMaxChars = availableWidth // charWidth

			-- Loop through the config list and apply the logic
			local btn
			local displayStr
			for _, config in pairs(socialBtnsConfig) do
				local value = userInfo[config.key]
				btn = socialBtns[config.key]
				if value ~= nil and value ~= "" then
					if string.len(value) > nbMaxChars then
						-- config.icon
						displayStr = config.prefix
							.. string.sub(value, 1, nbMaxChars - 1)
							.. "…"
					else
						displayStr = config.prefix .. value
					end
					btn.label.Text = displayStr
					btn.Width = btn.label.Width + btn.icon.Width + theme.paddingTiny * 2 + theme.padding * 2
					btn.Height = btn.label.Height + theme.paddingTiny * 2
					btn:show()
					btn.onRelease = function()
						config.action(value)
					end
				else
					btn.Text = "" -- config.icon
					btn:hide()
				end
			end

			node:refresh()
			scroll:parentDidResize()
		end

		return node
	end

	functions.createEditInfoNode = function()
		local node = ui:createFrame(Color(0, 0, 0, 0))
		node.type = "EditInfoNode"

		local removeURL = function(value)
			local slashIndex = 0
			for i = 1, #value do
				if string.sub(value, i, i) == "/" then
					slashIndex = i
				end
			end
			if slashIndex ~= 0 then
				value = string.sub(value, slashIndex + 1, #value)
			end

			return value
		end

		local trimPrefix = function(str, prefix)
			if str:sub(1, #prefix) == prefix then
				-- Trim the prefix
				local trimmedStr = str:sub(#prefix + 1)
				return trimmedStr
			end
			return str -- return the string, unchanged
		end

		local discordLogo = ui:frame({
			image = {
				data = Data:FromBundle("images/icon-discord.png"),
				alpha = true,
			},
		})
		discordLogo:setParent(node)
		local discordLink = ui:createTextInput(userInfo.discord or "", "Discord username", { textSize = "small" })
		discordLink:setParent(node)
		discordLink.onFocusLost = function(self)
			local previous = userInfo.discord
			userInfo.discord = self.text
			-- send API request to update user info
			systemApi:patchUserInfo({ discord = userInfo.discord }, function(err)
				if err then
					print("❌", err)
					userInfo.discord = previous
				end
			end)
			-- background request, not updating profile UI
			-- table.insert(requests, req)
		end

		local tiktokLogo = ui:frame({
			image = {
				data = Data:FromBundle("images/icon-tiktok.png"),
				alpha = true,
			},
		})
		tiktokLogo:setParent(node)
		local tiktokLink = ui:createTextInput(userInfo.tiktok or "", "TikTok username", { textSize = "small" })
		tiktokLink:setParent(node)
		tiktokLink.onFocusLost = function(self)
			local previous = userInfo.tiktok
			userInfo.tiktok = self.text
			userInfo.tiktok = removeURL(userInfo.tiktok)
			userInfo.tiktok = trimPrefix(userInfo.tiktok, "@")
			-- send API request to update user info
			systemApi:patchUserInfo({ tiktok = userInfo.tiktok }, function(err)
				if err then
					print("❌", err)
					userInfo.tiktok = previous
				end
			end)
			-- background request, not updating profile UI
			-- table.insert(requests, req)
		end

		local xLogo = ui:frame({
			image = {
				data = Data:FromBundle("images/icon-x.png"),
				alpha = true,
			},
		})
		xLogo:setParent(node)
		local xLink = ui:createTextInput(userInfo.x or "", "X username", { textSize = "small" })
		xLink.onTextChange = function()
			if xLink.Text ~= "" then
				if xLink.Text == "@" then
					xLink.Text = ""
				elseif xLink.Text:sub(1, 1) ~= "@" then
					xLink.Text = "@" .. xLink.Text
				end
			end
		end
		xLink:onTextChange()
		xLink:setParent(node)
		xLink.onFocusLost = function(self)
			local value = self.text
			-- trim "@" prefix if found
			if value:sub(1, 1) == "@" then
				value = value:sub(2)
			end
			value = removeURL(value)
			local previous = userInfo.x
			userInfo.x = value
			-- send API request to update user info
			systemApi:patchUserInfo({ x = userInfo.x }, function(err)
				if err then
					print("❌", err)
					userInfo.x = previous
				end
			end)
			-- background request, not updating UI
			-- table.insert(requests, req)
		end

		local githubLogo = ui:frame({
			image = {
				data = Data:FromBundle("images/icon-github.png"),
				alpha = true,
			},
		})
		githubLogo:setParent(node)
		local githubUsername = ui:createTextInput(userInfo.github or "", "GitHub username", { textSize = "small" })
		githubUsername:setParent(node)
		githubUsername.onFocusLost = function(self)
			local previous = userInfo.github
			userInfo.github = self.text
			userInfo.github = removeURL(userInfo.github)
			-- send API request to update user info
			systemApi:patchUserInfo({ github = userInfo.github }, function(err)
				if err then
					print("❌", err)
					userInfo.github = previous
				end
			end)
			-- background request, not updating UI
			-- table.insert(requests, req)
		end

		node.refresh = function(self)
			local padding = theme.padding
			local textInputHeight = discordLink.Height

			self.Height = textInputHeight
				+ padding -- discord
				+ textInputHeight
				+ padding -- tiktok
				+ textInputHeight
				+ padding -- X
				+ textInputHeight -- Github
				+ padding

			local y = self.Height

			local logoSize = textInputHeight * 0.6
			local inputWidth = self.Width - logoSize - padding * 3

			y -= padding + textInputHeight
			discordLogo.Width = logoSize
			discordLogo.Height = logoSize
			discordLogo.pos.X = padding
			discordLogo.pos.Y = y + textInputHeight * 0.5 - discordLogo.Height * 0.5
			discordLink.pos.X = discordLogo.pos.X + discordLogo.Width + padding
			discordLink.pos.Y = y
			discordLink.Width = inputWidth

			y -= padding + textInputHeight
			tiktokLogo.Width = logoSize
			tiktokLogo.Height = logoSize
			tiktokLogo.pos.X = padding
			tiktokLogo.pos.Y = y + textInputHeight * 0.5 - tiktokLogo.Height * 0.5
			tiktokLink.pos.X = tiktokLogo.pos.X + tiktokLogo.Width + padding
			tiktokLink.pos.Y = y
			tiktokLink.Width = inputWidth

			y -= padding + textInputHeight
			xLogo.Width = logoSize
			xLogo.Height = logoSize
			xLogo.pos.X = padding
			xLogo.pos.Y = y + textInputHeight * 0.5 - xLogo.Height * 0.5
			xLink.pos.X = xLogo.pos.X + xLogo.Width + padding
			xLink.pos.Y = y
			xLink.Width = inputWidth

			y -= padding + textInputHeight
			githubLogo.Width = logoSize
			githubLogo.Height = logoSize
			githubLogo.pos.X = padding
			githubLogo.pos.Y = y + textInputHeight * 0.5 - githubLogo.Height * 0.5
			githubUsername.pos.X = githubLogo.pos.X + githubLogo.Width + padding
			githubUsername.pos.Y = y
			githubUsername.Width = inputWidth
		end

		return node
	end

	infoNode = createInfoNode()
	infoNode:setParent(nil)

	local avatarLoadedListener = nil

	-- isLocal
	creationsBtn = ui:buttonSecondary({ content = loc("🛠️ Creations"), textSize = "small" })
	creationsBtn.onRelease = function()
		Menu:ShowCreations()

		local creationsContent = require("creations"):createModalContent({
			uikit = ui,
			authorId = userID,
			authorName = username,
		})
		content:push(creationsContent)

		-- Menu:ShowAlert({ message = "Coming soon!" }, System)
	end

	local alreadyFriends = nil
	local requestSent = nil
	local requestReceived = nil

	functions.updateFriendInfo = function()
		-- wait for both responses
		if alreadyFriends == nil or requestSent == nil or requestReceived == nil then
			return
		end

		friendText:hide()
		if addFriendBtn then
			addFriendBtn:hide()
		end
		if acceptFriendBtn then
			acceptFriendBtn:hide()
		end

		if alreadyFriends then
			friendText.Text = "Friends ❤️"
			friendText:show()
		elseif requestSent then
			friendText.Text = "Friend request sent! ✉️"
			friendText:show()
		elseif requestReceived then
			if not acceptFriendBtn then
				acceptFriendBtn = ui:buttonNeutral({ content = "Accept Friend! ✅", textSize = "small" })
				acceptFriendBtn:setParent(nil)
			end
			acceptFriendBtn:show()

			acceptFriendBtn.onRelease = function(btn)
				btn:disable()
				systemApi:replyToFriendRequest(userID, true, function(ok, err)
					if ok == true and err == nil then
						functions.checkFriendRelationShip()
					else
						btn:enable()
					end
				end)
			end
		else
			if not addFriendBtn and not isLocal then
				addFriendBtn = ui:buttonNeutral({ content = "Add Friend 👥", textSize = "small" })
				addFriendBtn:setParent(nil)
			end
			if addFriendBtn then
				addFriendBtn:show()
				addFriendBtn.onRelease = function(btn)
					btn:disable()
					systemApi:sendFriendRequest(userID, function(ok, err)
						if ok == true and err == nil then
							functions.checkFriendRelationShip()
						else
							btn:enable()
						end
					end)
				end
			end			
		end

		functions.refreshBottomButtons()
	end

	functions.checkFriendRelationShip = function()
		-- check if the User is already a friend
		local req = api:getFriends({ fields = { "id" } }, function(friends, err)
			if err ~= nil then
				return
			end

			alreadyFriends = false
			for _, friend in pairs(friends) do
				if friend.id == userID then
					alreadyFriends = true
					break
				end
			end
			functions.updateFriendInfo()
		end)
		table.insert(requests, req)

		-- check if a request was already sent
		req = api:getSentFriendRequests({ fields = { "id" } }, function(requests, err)
			if err ~= nil then
				return
			end

			requestSent = false
			for _, req in pairs(requests) do
				if req.id == userID then
					requestSent = true
					break
				end
			end
			functions.updateFriendInfo()
		end)
		table.insert(requests, req)

		-- check if a request has been received
		req = api:getReceivedFriendRequests({ fields = { "id" } }, function(requests, err)
			if err ~= nil then
				return
			end

			requestReceived = false
			for _, req in pairs(requests) do
				if req.id == userID then
					requestReceived = true
					break
				end
			end
			functions.updateFriendInfo()
		end)
		table.insert(requests, req)
	end

	functions.checkFriendRelationShip()
	

	functions.refresh = function()
		if activeNode == nil then
			return
		end

		local totalWidth = profileNode.Width
		local totalHeight = profileNode.Height

		activeNode.Width = totalWidth - ACTIVE_NODE_MARGIN * 2
		activeNode.Height = totalHeight - ACTIVE_NODE_MARGIN * 2

		if activeNode.refresh then
			activeNode:refresh()
		end -- refresh may shrink content

		local activeNodeWidthWithMargin = activeNode.Width + ACTIVE_NODE_MARGIN * 2
		local activeNodeHeightWithMargin = activeNode.Height + ACTIVE_NODE_MARGIN * 2

		totalHeight = activeNodeHeightWithMargin
		totalWidth = math.max(activeNodeWidthWithMargin)

		return totalWidth, totalHeight
	end

	-- returns height occupied
	functions.refreshBottomButtons = function()
		local padding = theme.padding

		local friend = friendText
		if addFriendBtn and addFriendBtn:isVisible() then
			friend = addFriendBtn
		elseif acceptFriendBtn and acceptFriendBtn:isVisible() then
			friend = acceptFriendBtn
		end

		if creationsBtn then
			creationsBtn:setParent(nil)
		end
		if friend then
			friend:setParent(nil)
		end
		if coinsBtn then
			coinsBtn:setParent(nil)
		end
		if doneBtn then
			doneBtn:setParent(nil)
		end

		local h = 0

		if activeNode == infoNode then
			creationsBtn:setParent(profileNode)
			friend:setParent(profileNode)
			h = math.max(friend.Height, creationsBtn.Height) + padding * 2
			local w = friend.Width + padding + creationsBtn.Width
			friend.pos = { profileNode.Width * 0.5 - w * 0.5, h * 0.5 - friend.Height * 0.5 }
			creationsBtn.pos = { friend.pos.X + friend.Width + padding, h * 0.5 - creationsBtn.Height * 0.5 }
		else -- edit node
			if isLocal then
				doneBtn:setParent(profileNode)
				h = doneBtn.Height + padding * 2
				local w = doneBtn.Width
				doneBtn.pos = { profileNode.Width * 0.5 - w * 0.5, h * 0.5 - doneBtn.Height * 0.5 }
			end
		end

		scroll.Height = profileNode.Height - h
		scroll.pos = { 0, h }
	end

	scroll.parentDidResize = function(self)
		local parent = self.parent
		local padding = theme.padding

		cell.Width = parent.Width - padding * 2
		scroll.Width = parent.Width

		functions.refreshBottomButtons()

		local width = self.Width - padding * 2

		local avatarNodeHeight = math.min(AVATAR_MAX_SIZE, math.max(self.Height * 0.3, AVATAR_MIN_SIZE))
		local avatarNodeWidth = avatarNodeHeight * AVATAR_NODE_RATIO
		if avatarNodeWidth > width then
			avatarNodeWidth = width
			avatarNodeHeight = avatarNodeWidth * 1.0 / AVATAR_NODE_RATIO
		end

		avatarNode.Width = avatarNodeWidth
		avatarNode.Height = avatarNodeHeight

		local cellContentHeight = avatarNodeHeight
		local availableHeight = self.Height

		if activeNode.parent ~= nil then
			cellContentHeight = cellContentHeight + activeNode.Height + padding
		end

		cell.Height = math.max(availableHeight, cellContentHeight)

		local y = cell.Height
		if blockBtn ~= nil then
			blockBtn.pos = { 
				0, 
				y - blockBtn.Height,
			}
			if deleteAccountBtn ~= nil then
				deleteAccountBtn.pos = { 
					blockBtn.pos.X + blockBtn.Width + padding * 2,
					y - deleteAccountBtn.Height,
				}
			end
		end

		y = cellContentHeight
		if availableHeight > cellContentHeight then
			y += (availableHeight - cellContentHeight) * 0.7
		end

		y = y - avatarNode.Height
		avatarNode.pos = {
			self.Width * 0.5 - avatarNode.Width * 0.5,
			y,
		}

		if infoNode.parent ~= nil then
			y = y - infoNode.Height - padding
			infoNode.pos = { 0, y }
		end

		scroll:flush()
		scroll:refresh()
	end

	functions.setActiveNode = function(newNode)
		if newNode == nil then
			print("active mode can't be nil")
			return
		end

		-- remove previous node if any
		if activeNode ~= nil then
			if activeNode == infoNode then
				activeNode:setParent(nil)
			else
				activeNode:remove()
			end
		end

		activeNode = newNode
		activeNode:setParent(cell)

		-- force layout refresh
		functions.refresh()
		content:refreshModal()
		scroll:parentDidResize()
	end

	content.didBecomeActive = function()
		local fillUserInfo = function(usr, err)
			if err ~= nil then
				return
			end

			-- store user info
			userInfo.bio = usr.bio or ""
			userInfo.discord = usr.discord or ""
			userInfo.tiktok = usr.tiktok or ""
			userInfo.x = usr.x or ""
			userInfo.github = usr.github or ""
			userInfo.nbFriends = usr.nbFriends or 0
			userInfo.created = usr.created
			userInfo.verified = usr.HasVerifiedPhoneNumber == true or usr.hasEmail == true

			content.title = username

			if userInfo.verified then
				content.verified = true
			end

			infoNode:setUserInfo()
			content:refreshModal()
		end

		local req = api:getUserInfo(userID, {
			"created",
			"nbFriends",
			"bio",
			"discord",
			"x",
			"tiktok",
			"github",
			"hasVerifiedPhoneNumber",
			"hasEmail",
		}, fillUserInfo)
		table.insert(requests, req)

		-- listen for avatar load
		avatarLoadedListener = LocalEvent:Listen(LocalEvent.Name.AvatarLoaded, function(player)
			-- avatar of local player is loaded, let's refresh the avatarNode
			if player == Player then
				if avatarNode.refresh then
					avatarNode:refresh()
				end
			end
		end)
	end

	content.willResignActive = function()
		-- stop listening for AvatarLoaded events
		if avatarLoadedListener then
			avatarLoadedListener:Remove()
			avatarLoadedListener = nil
		end
	end

	functions.setActiveNode(infoNode)

	return content
end

return profile
