mod = {}

local TEXT_COLOR = Color(200, 200, 200)

mod.createModalContent = function(_, config)
	local api = require("api")
	local badgeModal = require("badge_modal")
	local loc = require("localize")
	local modal = require("modal")
	local theme = require("uitheme").current
	local time = require("time")
	local systemApi = require("system_api", System)

	local defaultConfig = {
		world = {
			id = "",
			title = "…",
			description = "",
			thumbnail = nil,
			likes = nil,
			liked = nil,
		},
		mode = "explore", -- "explore" / "create"
		uikit = require("uikit"),
	}

	local ok, err = pcall(function()
		config = require("config"):merge(defaultConfig, config, {
			acceptTypes = {
				-- TODO: config module should allow checking deeper levels
				-- world = {
				-- 	thumbnail = { "Data" },
				-- 	likes = { "number" },
				-- 	liked = { "boolean" },
				-- },
			},
		})
	end)
	if not ok then
		error("worldDetails:createModalContent(config) - config error: " .. err, 2)
	end

	local ui = config.uikit
	local world = config.world
	local content = modal:createContent() -- world details content

	-- whether the world is displayed in create mode (the user must be the author)
	local createMode = config.mode == "create"

	local worldDetails = ui:createNode()

	local requests = {}
	local likeRequest
	local refreshTimer
	local listeners = {}
	-- array of badges fetched from the server
	local badgesFetched = {}

	badges = {
		cells = {},
	}

	local function removeAllCells()
		for _, cell in ipairs(badges.cells) do
			cell:remove()
		end
		badges.cells = {}
	end

	local t = 0
	local r = Rotation()
	local l = LocalEvent:Listen(LocalEvent.Name.Tick, function(dt)
		t += dt * 1.5
		r.Y = math.pi + math.sin(t) * 0.4
		r.X = math.cos(t * 1.1) * 0.3
		for _, cell in ipairs(badges.cells) do
			if cell.badge ~= nil then
				cell.badge.LocalRotation:Set(r)
			end
		end
	end)
	table.insert(listeners, l)

	local PADDING = theme.padding

	-- Constants for badges list
	-- (similar to friends list in cubzh.lua)
	local CONFIG = {
		BADGE_CELL_WIDTH = 90,
		BADGE_CELL_HEIGHT = 140,
		BADGES_CELL_PADDING = PADDING,
	}

	local function badgeCellResizeFn(self)
		if self.parent.Height == nil then
			return
		end
		self.Height = self.parent.Height
	end

	local function badgesScrollLoadCell(index)
		local firstIndexOfContent = 1
		if createMode then
			firstIndexOfContent = 2
		end

		if index >= firstIndexOfContent + #badgesFetched then
			return nil
		end

		local cell = badges.cells[index]

		-- index of the "Create badge" cell
		if index < firstIndexOfContent then
			if cell == nil then
				cell = ui:frameScrollCellWithBevel()
				cell.Width = CONFIG.BADGE_CELL_WIDTH
				cell.parentDidResize = badgeCellResizeFn

				local image = ui:frame({
					image = {
						data = Data:FromBundle("images/icon-plus.png"),
						alpha = true,
						filtering = true,
					},
				})
				image.object.Color = Color(180, 180, 180)
				image.Width = CONFIG.BADGE_CELL_WIDTH * 0.6
				image.Height = image.Width
				cell.image = image
				image:setParent(cell)

				local label = ui:createText(loc("New\nBadge"), {
					color = Color(180, 180, 180),
					size = "small",
					outline = 0.4,
					outlineColor = Color(10, 10, 10),
					alignment = "center",
				})
				cell.label = label
				label:setParent(cell)

				cell.onPress = function(_)
					Client:HapticFeedback()
				end

				cell.onRelease = function(_)
					-- show badge creation form in the world details modal
					badgeModalContent = badgeModal:createModalContent({
						uikit = ui,
						mode = "create",
						worldId = world.id,
					})
					local m = content:getModalIfContentIsActive()
					if m ~= nil then
						m:push(badgeModalContent)
					else
						print("❌ no modal found")
					end
				end

				badges.cells[index] = cell
			end

			local label = cell.label
			local image = cell.image

			label.pos = {
				CONFIG.BADGE_CELL_WIDTH * 0.5 - label.Width * 0.5,
				CONFIG.BADGE_CELL_HEIGHT * 0.5 * 0.5 - label.Height * 0.5,
			}

			local vSpaceForImage = CONFIG.BADGE_CELL_HEIGHT - (label.pos.Y + label.Height)
			image.pos = {
				CONFIG.BADGE_CELL_WIDTH * 0.5 - image.Width * 0.5,
				CONFIG.BADGE_CELL_HEIGHT - vSpaceForImage * 0.5 - image.Height * 0.5,
			}

			return cell
		else -- display a badge cell
			local fetchedBadgeIndex = index + 1 - firstIndexOfContent
			if fetchedBadgeIndex <= #badgesFetched then
				local badge = badgesFetched[fetchedBadgeIndex]

				if cell == nil then
					cell = ui:frame({ color = Color(255, 255, 255, 0) })
					cell.Width = CONFIG.BADGE_CELL_WIDTH
					cell.parentDidResize = badgeCellResizeFn

					local badgeShape = ui:frame()
					cell.badgeShape = badgeShape
					badgeShape.Width = CONFIG.BADGE_CELL_WIDTH
					badgeShape.Height = CONFIG.BADGE_CELL_WIDTH
					badgeShape:setParent(cell)

					local showBadgeUnlocked = createMode or badge.userDidUnlock

					local reqs = require("badge"):createBadgeObject({
						badgeId = badge.badgeID,
						locked = not showBadgeUnlocked,
						frontOnly = true,
						callback = function(badgeObject)
							cell.badge = badgeObject

							local s = ui:createShape(badgeObject, { spherized = false })
							s.Width = badgeShape.Width
							s.Height = badgeShape.Height
							s:setParent(cell)

							s.pos = badgeShape.pos
							badgeShape:remove()
							badgeShape = s
							cell.badgeShape = s
						end,
					})
					-- TODO: cancel reqs when cell is destroyed

					local nameLabel = ui:createText(badge.name, {
						color = Color.White,
						size = "small",
						outline = 0.4,
						outlineColor = Color(10, 10, 10),
						alignment = "center",
					})
					cell.nameLabel = nameLabel
					nameLabel:setParent(cell)

					local rarity = badge.rarity
					if rarity == nil then
						rarity = 0
					end
					local rarityLabel = ui:createText(string.format("rarity: %.1f%%", rarity * 100), {
						color = Color.White,
						size = "small",
						alignment = "center",
					})
					cell.rarityLabel = rarityLabel
					rarityLabel:setParent(cell)

					cell.onRemove = function()
						for _, req in ipairs(reqs) do
							req:Cancel()
						end
						reqs = {}
					end

					cell.onRelease = function(_)
						if createMode then -- edit badge
							-- show badge creation form in the world details modal
							badgeModalContent = badgeModal:createModalContent({
								uikit = ui,
								mode = "edit",
								badgeObj = badge,
							})
							local m = content:getModalIfContentIsActive()
							if m ~= nil then
								m:push(badgeModalContent)
							else
								print("❌ no modal found")
							end
						else -- display badge
							-- show badge creation form in the world details modal
							badgeModalContent = badgeModal:createModalContent({
								uikit = ui,
								mode = "display",
								badgeObj = badge,
								locked = not showBadgeUnlocked,
							})
							local m = content:getModalIfContentIsActive()
							if m ~= nil then
								m:push(badgeModalContent)
							else
								print("❌ no modal found")
							end
						end
					end

					badges.cells[index] = cell
				end

				local rarityLabel = cell.rarityLabel
				local nameLabel = cell.nameLabel
				local badgeShape = cell.badgeShape

				local y = CONFIG.BADGE_CELL_HEIGHT

				nameLabel.object.Scale = 1
				if nameLabel.Width > cell.Width then
					nameLabel.object.Scale = cell.Width / nameLabel.Width
				end

				rarityLabel.object.Scale = 0.8
				if rarityLabel.Width > cell.Width then
					rarityLabel.object.Scale = cell.Width / rarityLabel.Width
				end

				local vSpace = y - badgeShape.Height - PADDING * 2
				local textHeight = nameLabel.Height + rarityLabel.Height
				if textHeight > vSpace then
					local scale = vSpace / textHeight
					nameLabel.object.Scale *= scale
					rarityLabel.object.Scale *= scale
				end

				y = y - badgeShape.Height

				cell.badgeShape.pos = {
					CONFIG.BADGE_CELL_WIDTH * 0.5 - cell.badgeShape.Width * 0.5,
					y,
				}

				y = y - PADDING - nameLabel.Height
				nameLabel.pos = {
					CONFIG.BADGE_CELL_WIDTH * 0.5 - nameLabel.Width * 0.5,
					y,
				}

				y = y - rarityLabel.Height
				rarityLabel.pos = {
					CONFIG.BADGE_CELL_WIDTH * 0.5 - rarityLabel.Width * 0.5,
					y,
				}

				if badge.userDidUnlock == true then
					nameLabel.Color = Color.Green
				end

				return cell
			end
		end
		return nil -- no cell for index (this line may not be needed)
	end

	local badgesScrollUnloadCell = function(_, cell)
		cell:setParent(nil)
	end

	local privateFields = {}

	local cancelRequestsTimersAndListeners = function()
		for _, req in ipairs(requests) do
			req:Cancel()
		end
		requests = {}

		for _, listener in ipairs(listeners) do
			listener:Remove()
		end
		listeners = {}

		if refreshTimer ~= nil then
			refreshTimer:Cancel()
			refreshTimer = nil
		end
	end

	local badgesNeedRefresh = true
	local badgesNeedRefreshListener = LocalEvent:Listen("badgesNeedRefresh", function()
		badgesNeedRefresh = true
		-- badges will be refreshed when content becomes active
	end)

	worldDetails.onRemove = function(_)
		cancelRequestsTimersAndListeners()
		badgesNeedRefreshListener:Remove()
	end

	content.title = ""
	content.icon = "🌎"
	content.node = worldDetails

	content.didBecomeActive = function()
		for _, listener in ipairs(listeners) do
			listener:Resume()
		end
		fetchBadgesAndUpdateUI()
	end

	content.willResignActive = function()
		for _, listener in ipairs(listeners) do
			listener:Pause()
		end
	end

	local btnLaunch
	local btnServers

	if not createMode then
		local playIcon = ui:frame({
			image = {
				data = Data:FromBundle("images/icon-play-white.png"),
				alpha = true,
			},
		})
		playIcon.Width = 36
		playIcon.Height = 36

		btnLaunch = ui:buttonPositive({ content = playIcon })
		btnLaunch.onRelease = function()
			System:DebugEvent("User presses Start button to launch world", { ["world-id"] = world.id })
			URL:Open("https://app.cu.bzh?worldID=" .. world.id)
		end
		btnLaunch:setParent(worldDetails)

		if world.maxPlayers ~= nil and world.maxPlayers > 1 then
			btnServers = ui:buttonSecondary({ content = "Servers", textSize = "small" })
			btnServers.onRelease = function()
				local config = { worldID = world.id, title = world.title, uikit = ui }
				local list = require("server_list"):create(config)
				content:push(list)
			end
			btnServers:setParent(worldDetails)
		end
	end

	local cell = ui:frame() -- { color = Color(100, 100, 100) }
	cell.Height = 100
	cell:setParent(nil)

	local title
	local by
	local authorBtn
	local author
	local likeBtn
	local reportBtn
	local editDescriptionBtn
	local editIconBtn
	local description
	local views
	local serverSize
	local creationDate
	local updateDate
	local serverSizeText
	local serverSizeSlider

	local iconMask = ui:frame({
		image = {
			data = Data:FromBundle("images/round-corner-mask.png"),
			slice9 = { 0.5, 0.5 },
			slice9Scale = 1.0,
			slice9Width = 20,
			-- alpha = true,
			cutout = true, -- mask only seem to work with cutout, not alpha
		},
		mask = true,
	})
	-- iconMask.IsMask = true
	iconMask:setParent(cell)

	local iconArea = ui:frame({ color = Color(20, 20, 22) })
	iconArea:setParent(iconMask)

	if createMode then
		title = ui:createTextInput(config.world.title, "World Name")
		editTitleBtn = ui:buttonSecondary({ content = "✏️" })

		local function focus()
			title:focus()
		end

		local function submit()
			local sanitized, err = api.checkWorldName(title.Text)
			if err == nil then
				local req = systemApi:patchWorld(world.id, { title = sanitized }, function(err, world)
					if err == nil then
						-- World update succeeded.
						-- Notify that the content has changed.
						if content.onContentUpdate then
							content.onContentUpdate(world)
						end
					end
				end)
				table.insert(requests, req)
			end

			editTitleBtn.Text = "✏️"
			editTitleBtn.onRelease = focus
		end

		title.onFocus = function(_)
			editTitleBtn.Text = "✅"
			editTitleBtn.onRelease = submit
		end

		title.onTextChange = function(self)
			local _, err = api.checkWorldName(self.Text)
			if err ~= nil then
				editTitleBtn:disable()
			else
				editTitleBtn:enable()
			end
		end

		editTitleBtn.onRelease = focus
		editTitleBtn:setParent(cell)
	else
		title = ui:createText(config.world.title, { color = Color.White, size = "big", outline = 0.5 })
	end
	title:setParent(cell)

	local badgesTitle = ui:createText("🏅 Badges", { color = Color.White, size = "default" })
	badgesTitle:setParent(cell)

	-- create scroll to display badges
	local badgesScroll = ui:scroll({
		backgroundColor = theme.buttonTextColor,
		-- backgroundColor = Color(26, 26, 30),
		padding = {
			top = CONFIG.BADGES_CELL_PADDING,
			bottom = CONFIG.BADGES_CELL_PADDING,
			left = CONFIG.BADGES_CELL_PADDING,
			right = CONFIG.BADGES_CELL_PADDING,
		},
		cellPadding = CONFIG.BADGES_CELL_PADDING,
		direction = "right",
		loadCell = badgesScrollLoadCell,
		unloadCell = badgesScrollUnloadCell,
	})
	badgesScroll:setParent(cell)

	if config.mode ~= "create" then
		badgesTitle:hide()
		badgesScroll:hide()
	end

	function fetchBadgesAndUpdateUI()
		if not badgesNeedRefresh then
			return
		end
		api:listBadgesForWorld(world.id, function(err, badges)
			if err ~= nil or badges == nil then
				-- print("🐞 [badges] could not list badges for world", world.id, err)
				return
			end
			badgesNeedRefresh = false

			table.sort(badges, function(a, b)
				-- unlocked first
				if a.userDidUnlock and not b.userDidUnlock then
					return true
				elseif not a.userDidUnlock and b.userDidUnlock then
					return false
				end
				-- both same unlock status, sort by rarity (most common first, i.e. higher rarity value first)
				local ar = a.rarity or 0
				local br = b.rarity or 0
				return ar > br
			end)
			badgesFetched = badges

			badgesScroll:flush()
			removeAllCells()

			if config.mode == "create" then
				badgesScroll:refresh()

			elseif badgesFetched and #badgesFetched > 0 then
				badgesTitle:show()
				badgesScroll:show()

				worldDetails:refresh()
				badgesScroll:refresh()
			else
				badgesTitle:hide()
				badgesScroll:hide()
			end
		end)
	end

	-- TODO: gaetan: should this be done this way?
	badgesScroll.parentDidResize = function(self)
		self.Width = self.parent.Width - theme.padding * 2
		self.Height = CONFIG.BADGE_CELL_HEIGHT + CONFIG.BADGES_CELL_PADDING * 2
	end

	if createMode then
		editIconBtn = ui:buttonSecondary({ content = "✏️ Edit icon", textSize = "small" })
		editIconBtn:setParent(cell)
		editIconBtn.onRelease = function()
			File:OpenAndReadAll(function(success, data)
				if not success then
					print("could not read file")
					return
				end

				if data == nil then
					return
				end

				systemApi:setWorldIcon(world.id, data, function(err)
					if err ~= nil then
						print("could not set world icon")
						return
					end

					-- refresh the world's thumbnail in the UI
					local req = api:getWorldThumbnail({
						worldID = world.id,
						width = 250,
						callback = function(thumbnail, err)
							if err == nil then
								world.thumbnail = thumbnail
								refreshWorld()
							end
						end,
					})
					table.insert(requests, req)
				end)
			end)
		end

		serverSizeText = ui:createText("Server Size: …", { color = Color.White, size = "small" })
		serverSizeText:setParent(cell)

		serverSizeSlider = ui:slider({
			min = 1,
			max = 32,
			defaultValue = 1,
			hapticFeedback = true,
			onValueChange = function(value)
				if world.maxPlayers ~= nil then
					world.maxPlayers = value
					serverSizeText.Text = "Server Size: " .. world.maxPlayers
				end
			end,
		})

		serverSizeSlider.onRelease = function()
			if world.maxPlayers ~= nil then
				local req = systemApi:patchWorld(world.id, { maxPlayers = world.maxPlayers }, function(_, _)
					-- not handling response yet
				end)
				table.insert(requests, req)
			end
		end

		serverSizeSlider:setParent(cell)
	end

	local secondaryTextColor = Color(150, 150, 150)

	if config.mode ~= "create" then
		serverSize = ui:createText("👤 …", { color = secondaryTextColor, size = "small" })
		serverSize:setParent(cell)
	end

	creationDate = ui:createText("🌎 published … ago", secondaryTextColor, "small")
	creationDate:setParent(cell)

	updateDate = ui:createText("✨ updated … ago", secondaryTextColor, "small")
	updateDate:setParent(cell)

	by = ui:createText("🛠️ by ", secondaryTextColor, "small")
	by:setParent(cell)

	if createMode then
		local str = " @" .. Player.Username
		author = ui:createText(str, Color.Green, "small")
		author:setParent(cell)
	else
		authorBtn = ui:buttonLink({ content = "@…", textSize = "small" })
		authorBtn:setParent(cell)
	end

	views = ui:createText("👁 …", secondaryTextColor, "small")
	views:setParent(cell)

	description = ui:createText("description", { color = TEXT_COLOR, size = "small" })
	description:setParent(cell)

	likeBtn = ui:buttonSecondary({ content = "🤍 …", textSize = "small" })
	likeBtn:setParent(cell)

	reportBtn = ui:button({
		content = "Report",
		textSize = "small",
		borders = false,
		padding = false,
		textColor = theme.errorTextColor,
		color = Color(0, 0, 0, 0),
	})
	reportBtn.onRelease = function(self)
		local config = {
			world = world,
			uikit = ui,
		}
		local reportContent = require("report"):createModalContent(config)
		content:push(reportContent)
	end
	reportBtn:setParent(cell)

	if createMode then
		editDescriptionBtn = ui:buttonSecondary({ content = "✏️ Edit description", textSize = "small" })
		editDescriptionBtn:setParent(cell)
		editDescriptionBtn.onRelease = function()
			if System.MultilineInput ~= nil then
				if description.empty == true then
					description.Text = ""
				end
				System.MultilineInput(
					description.Text,
					"Description",
					"How would you describe that World?",
					"", -- regex
					10000, -- max chars
					function(text) -- done
						ui:turnOn()
						if text == "" then
							description.empty = true
							description.Text = "Worlds are easier to find with a description!"
							description.Color = theme.textColorSecondary
							local req = systemApi:patchWorld(world.id, { description = "" }, function(_, _)
								-- not handling response yet
							end)
							table.insert(requests, req)
						else
							description.empty = false
							description.Text = text
							description.Color = TEXT_COLOR
							local req = systemApi:patchWorld(world.id, { description = text }, function(_, _)
								-- not handling response yet
							end)
							table.insert(requests, req)
						end
					end,
					function() -- cancel
						ui:turnOn()
					end
				)
				ui:turnOff()
			end
		end
		-- else -- explore mode
	end

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
		loadCell = function(index)
			if index == 1 then
				return cell
			end
		end,
		unloadCell = function(_, _) end,
	})
	scroll:setParent(worldDetails)

	-- refreshes UI with what's in local config.world / world
	local function refreshWorld()
		if world.thumbnail ~= nil then
			iconArea:setImage(world.thumbnail)
		end

		if config.mode == "create" then
			if world.description == nil or world.description == "" then
				description.empty = true
				description.Text = "Worlds are easier to find with a description!"
				description.Color = theme.textColorSecondary
			else
				description.empty = false
				description.Text = world.description
				description.Color = TEXT_COLOR
			end

			if world.maxPlayers then
				serverSizeText.Text = "Server Size: " .. world.maxPlayers
				serverSizeSlider:setValue(world.maxPlayers)
			end
		else
			description.Text = world.description or ""
			description.Color = TEXT_COLOR
		end

		if likeBtn then
			likeBtn.Text = (world.liked == true and "❤️ " or "🤍 ")
				.. (world.likes and math.floor(world.likes) or 0)

			likeBtn.onRelease = function()
				world.liked = not world.liked

				if world.liked == true then
					world.likes = world.likes ~= nil and world.likes + 1 or 1
				else
					world.likes = world.likes ~= nil and world.likes - 1 or 0
				end

				if likeRequest then
					likeRequest:Cancel()
				end
				likeRequest = systemApi:likeWorld(world.id, world.liked, function(_)
					-- TODO: this request should return the refreshed number of likes
				end)
				table.insert(requests, likeRequest)

				local nbLikes = (world.likes and math.floor(world.likes) or 0)
				likeBtn.Text = (world.liked == true and "❤️ " or "🤍 ") .. nbLikes

				privateFields.alignViewsAndLikes()
			end
		end

		views.Text = "👁 " .. (world.views and math.floor(world.views) or 0)

		if world.maxPlayers and serverSize then
			if world.maxPlayers == 1 then
				serverSize.Text = "👤 solo game (no server)"
			else
				serverSize.Text = "👥 " .. world.maxPlayers .. " players per server"
			end
		end

		if world.created then
			local n, unitType = time.ago(world.created)
			if n == 1 then
				unitType = unitType:sub(1, #unitType - 1)
			end
			if math.floor(n) == n then
				creationDate.Text = string.format("🌎 published %d %s ago", math.floor(n), unitType)
			else
				creationDate.Text = string.format("🌎 published %.1f %s ago", n, unitType)
			end
		end

		if world.updated then
			local n, unitType = time.ago(world.updated)
			if n == 1 then
				unitType = unitType:sub(1, #unitType - 1)
			end
			if math.floor(n) == n then
				updateDate.Text = string.format("✨ updated %d %s ago", math.floor(n), unitType)
			else
				updateDate.Text = string.format("✨ updated %.1f %s ago", n, unitType)
			end
		end

		-- update author text/button
		if author then
			author.Text = " @" .. (world.authorName or "…")
		elseif authorBtn and world.authorName then
			authorBtn.Text = "@" .. world.authorName
			authorBtn.onRelease = function(_)
				local profileConfig = {
					username = world.authorName,
					userID = world.authorId,
					uikit = ui,
				}
				local profileContent = require("profile"):create(profileConfig)
				content:push(profileContent)
			end
		end

		content.title = ""

		-- update description text
		if description ~= nil then
			description.Text = world.description or ""
		end

		local modal = content:getModalIfContentIsActive()
		if modal ~= nil then
			modal:refreshContent()
		end

		worldDetails:refresh()
	end

	-- send request to gather world information
	local function loadWorld()
		local req = api:getWorld(world.id, {
			"authorName",
			"authorId",
			"description",
			"liked",
			"likes",
			"views",
			"title",
			"created",
			"updated",
			"maxPlayers",
		}, function(worldInfo, err)
			if err ~= nil then
				-- TODO: handle error (retry button?)
				return
			end

			world.authorName = worldInfo.authorName
			world.authorId = worldInfo.authorId
			world.description = worldInfo.description
			world.title = worldInfo.title
			world.liked = worldInfo.liked
			world.likes = worldInfo.likes
			world.views = worldInfo.views
			world.created = worldInfo.created
			world.updated = worldInfo.updated
			world.maxPlayers = worldInfo.maxPlayers

			refreshWorld()
		end)
		table.insert(requests, req)

		if world.thumbnail == nil then
			local req = api:getWorldThumbnail({
				worldID = world.id,
				width = 250,
				callback = function(thumbnail, err)
					if err == nil then
						world.thumbnail = thumbnail
						refreshWorld()
					end
				end,
			})
			table.insert(requests, req)
		end
	end

	local w = 400
	local h = 400

	privateFields.scheduleRefresh = function()
		if refreshTimer ~= nil then
			return
		end
		refreshTimer = Timer(0.01, function()
			refreshTimer = nil
			worldDetails:refresh()
		end)
	end

	privateFields.alignViewsAndLikes = function()
		local parent = likeBtn.parent
		if parent == nil then
			return
		end
		local viewAndLikesWidth = views.Width + theme.padding + likeBtn.Width
		views.pos.X = parent.Width - viewAndLikesWidth - theme.padding
		likeBtn.pos.X = views.pos.X + views.Width + theme.padding
	end

	worldDetails._width = function(_)
		return w
	end

	worldDetails._height = function(_)
		return h
	end

	worldDetails._setWidth = function(_, v)
		w = v
		privateFields:scheduleRefresh()
	end

	worldDetails._setHeight = function(_, v)
		h = v
		privateFields:scheduleRefresh()
	end

	worldDetails.refresh = function(self)
		if world.thumbnail ~= nil then
			iconArea:setImage(world.thumbnail)
		end

		local padding = theme.padding
		local width = self.Width - theme.padding * 2 -- remove scroll padding
		local iconSize = math.min(100, self.Width * 0.3)

		iconArea.Width = iconSize
		iconArea.Height = iconSize
		iconMask.Width = iconSize
		iconMask.Height = iconSize

		description.object.MaxWidth = width - padding * 2

		local viewAndLikesHeight = math.max(views.Height, likeBtn.Height)

		local author = author or authorBtn
		local singleLineHeight = math.max(by.Height, author.Height)

		local widthAsideIcon = width - iconSize - theme.paddingBig

		if createMode then
			title.Width = widthAsideIcon - editTitleBtn.Width - theme.paddingTiny
		else
			title.object.MaxWidth = widthAsideIcon
		end

		by.object.Scale = 1
		author.object.Scale = 1
		local w = by.Width + author.Width
		if w > widthAsideIcon then
			local scale = widthAsideIcon / w
			by.object.Scale = scale
			author.object.Scale = scale
		end
		local authorLineHeight = math.max(by.Height, author.Height)

		-- header contains the icon, the title and the author
		-- + edit icon button in create mode
		local headerHeight = title.Height + authorLineHeight + padding
		if editIconBtn then
			headerHeight = headerHeight + editIconBtn.Height + padding
		end
		headerHeight = math.max(headerHeight, iconArea.Height)

		local contentHeight = headerHeight
			+ padding
			+ viewAndLikesHeight -- views and likes
			+ padding
			+ description.Height
			+ theme.paddingBig
			+ singleLineHeight -- server size
			+ padding
			+ singleLineHeight -- publication date
			+ padding
			+ singleLineHeight -- update date
			+ theme.paddingBig

		if badgesTitle:isVisible() then
			contentHeight += badgesTitle.Height + padding
		end

		if badgesScroll:isVisible() then
			contentHeight += badgesScroll.Height + padding
		end

		if serverSizeText then
			local h = math.max(serverSizeText.Height, serverSizeSlider.Height)
			contentHeight = contentHeight + h + padding
		end

		if editDescriptionBtn then
			contentHeight = contentHeight + editDescriptionBtn.Height + padding
		end

		cell.Height = contentHeight
		cell.Width = width

		local y = contentHeight - iconArea.Height

		-- icon
		-- iconArea.pos.X = 0
		-- iconArea.pos.Y = y
		iconMask.pos.X = 0
		iconMask.pos.Y = y

		-- title
		y = contentHeight - title.Height
		title.pos = { iconSize + theme.paddingBig, y }

		if editTitleBtn then
			local h = title.Height
			editTitleBtn.Height = h
			editTitleBtn.Width = h
			editTitleBtn.pos = { title.pos.X + title.Width + theme.paddingTiny, y }
		end

		-- author
		y = y - padding
		by.pos = { iconSize + theme.paddingBig, y - authorLineHeight * 0.5 - by.Height * 0.5 }
		author.pos = { by.pos.X + by.Width, y - authorLineHeight * 0.5 - author.Height * 0.5 }
		y = y - authorLineHeight

		-- edit icon
		if editIconBtn then
			y = y - padding - editIconBtn.Height
			editIconBtn.pos = { iconSize + theme.paddingBig, y }
		end

		y = math.min(iconMask.pos.Y, y)

		-- view and likes
		y = y - padding - viewAndLikesHeight * 0.5
		views.pos.Y = y - views.Height * 0.5
		likeBtn.pos.Y = y - likeBtn.Height * 0.5

		reportBtn.pos = {
			padding,
			likeBtn.pos.Y + likeBtn.Height * 0.5 - reportBtn.Height * 0.5,
		}

		privateFields.alignViewsAndLikes()
		y = y - viewAndLikesHeight * 0.5

		-- server size
		if serverSizeText then
			local h = math.max(serverSizeText.Height, serverSizeSlider.Height)
			y = y - h * 0.5 - padding
			serverSizeText.pos = { padding, y - serverSizeText.Height * 0.5 }
			serverSizeSlider.Width = math.min(width - serverSizeText.Width - theme.paddingBig, 200)
			serverSizeSlider.pos = { width - serverSizeSlider.Width - padding, y - serverSizeSlider.Height * 0.5 }
			y = y - h * 0.5
		end

		-- description
		y = y - padding - description.Height
		description.pos = { padding, y }

		if editDescriptionBtn ~= nil then
			y = y - padding - editDescriptionBtn.Height
			editDescriptionBtn.pos = { width * 0.5 - editDescriptionBtn.Width * 0.5, y }
		end

		-- badges
		if badgesTitle:isVisible() then
			y = y - theme.paddingBig - badgesTitle.Height
			badgesTitle.pos = { padding, y }
		end
		if badgesScroll:isVisible() then
			y = y - padding - badgesScroll.Height
			badgesScroll.pos = { padding, y }
		end

		-- info
		if serverSize then
			y = y - theme.paddingBig - singleLineHeight * 0.5
			serverSize.pos = { padding, y - serverSize.Height * 0.5 }
			y = y - singleLineHeight * 0.5
		end

		y = y - theme.paddingBig - singleLineHeight * 0.5
		creationDate.pos = { padding, y - creationDate.Height * 0.5 }
		y = y - singleLineHeight * 0.5

		y = y - padding - singleLineHeight * 0.5
		updateDate.pos = { padding, y - updateDate.Height * 0.5 }
		y = y - singleLineHeight * 0.5

		scroll.Width = self.Width

		if btnLaunch then
			scroll.Height = self.Height - btnLaunch.Height - padding * 2

			if btnServers then
				btnLaunch.Width = self.Width - btnServers.Width - padding * 3
				btnServers.Height = btnLaunch.Height

				btnServers.pos = {
					padding,
					padding,
				}
				btnLaunch.pos = { btnServers.pos.X + btnServers.Width + padding, padding }
			else
				btnLaunch.Width = self.Width - padding * 2
				btnLaunch.pos = { self.Width * 0.5 - btnLaunch.Width * 0.5, padding }
			end
			scroll.pos.Y = btnLaunch.pos.Y + btnLaunch.Height + padding
		else
			scroll.Height = self.Height
			scroll.pos.Y = 0
		end

		-- TODO: gaetan: check if this is really needed
		scroll:flush()
		scroll:refresh()
	end

	refreshWorld()
	loadWorld()

	return content
end

return mod
