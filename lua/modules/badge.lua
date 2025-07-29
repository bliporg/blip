--
-- Module for world badges
--

local mod = {}

local loc = require("localize")
local conf = require("config")
local system_api = require("system_api", System)
local api = require("api", System)

-- Unlock a badge for the current user and world
-- callback(err)
mod.unlock = function(_, badgeTag, callback)
	local worldId = Environment.worldId
	if worldId == nil or worldId == "" then
		error("unlockBadge must be called from a world")
	end

	-- unlocked, badgeId
	system_api:unlockBadge(worldId, badgeTag, function(err, response)
		-- err is nil on success
		-- unlocked is true if the badge was just unlocked for the 1st time
		if response.unlocked == true then
			-- TODO: gaetan: display badge title instead of tag
			LocalEvent:Send(LocalEvent.Name.BadgeUnlocked, {
				worldId = worldId,
				badgeTag = badgeTag,
				badgeId = response.badgeId,
				badgeName = response.badgeName,
			})
		end
		if callback ~= nil then
			callback(err, response)
		end
	end)
end
mod.unlockBadge = mod.unlock -- legacy

-- returns a Badge Object
-- thumbnail can be loaded on creation or later with badgeObject:setThumbnail(imageData)
-- returns table with underlying requests in case they need to be cancelled
local badgeUnlockedData = nil
local badgeLockedData = nil
local maskQuadData = nil

local function _setBadgeImage(self, imageData)
	if typeof(self) ~= "Mesh" then
		error("badgeObject:setBadgeImage(imageData) should be called with `:`")
	end

	self.badgeImageData = imageData

	local iconQuad = self.iconQuad
	local iconQuadBack = self.iconQuadBack

	if iconQuad ~= nil then
		iconQuad.Color = Color(255, 255, 255)
		iconQuad.Image = {
			data = imageData,
			filtering = false,
		}
	end

	if iconQuadBack ~= nil then
		iconQuadBack.Color = Color(255, 255, 255)
		iconQuadBack.Image = {
			data = imageData,
			filtering = false,
		}
	end
end

local function _getBadgeImageData(self)
	if typeof(self) ~= "Mesh" then
		error("badgeObject:getBadgeImageData() should be called with `:`")
	end
	return self.badgeImageData
end

local function _setBadgeId(self, badgeId, callback)
	if typeof(self) ~= "Mesh" then
		error("badgeObject:setBadgeId(badgeId) should be called with `:`")
	end
	if self.iconQuad == nil then
		-- badge has no quad to render thumbnail on
		return
	end
	if type(badgeId) ~= "string" then
		error("badgeObject:setBadgeId(badgeId) - badgeId must be a string")
	end
	if callback ~= nil and type(callback) ~= "function" then
		error("badgeObject:setBadgeId(badgeId, callback) - callback must be a function or nil")
	end

	self.badgeId = badgeId
	local iconQuad = self.iconQuad
	local iconQuadBack = self.iconQuadBack

	-- make quad transparent while loading thumbnail
	iconQuad.Color = Color(255, 255, 255, 0)
	if iconQuadBack ~= nil then
		iconQuadBack.Color = Color(255, 255, 255, 0)
	end

	local req = api:getBadgeThumbnail({
		badgeID = badgeId,
		callback = function(icon, err)
			if err ~= nil then
				if callback ~= nil then
					callback() -- thumbnail not loaded, but trigger callback anyway
				end
				return
			end

			self:setBadgeImage(icon)

			if callback ~= nil then
				callback()
			end
		end,
	})

	return req
end

mod.createBadgeObject = function(self, config)
	local reqs = {}
	local defaultConfig = {
		frontOnly = false, -- displays thumbnail on front side only
		badgeId = nil,
		locked = false, -- if true, returns design for locked badge
		callback = nil, -- function(badgeObject)
	}

	local ok, err = pcall(function()
		config = conf:merge(defaultConfig, config, {
			acceptTypes = {
				frontOnly = { "boolean" },
				locked = { "boolean" },
				badgeId = { "string" },
				callback = { "function" },
			},
		})
	end)
	if not ok then
		error("badge:createBadgeObject(config) - config error: " .. err)
	end

	local badgeData

	if config.locked then
		if badgeLockedData == nil then
			badgeLockedData = Data:FromBundle("shapes/badge-dark.glb")
		end
		badgeData = badgeLockedData
	else
		if badgeUnlockedData == nil then
			badgeUnlockedData = Data:FromBundle("shapes/badge.glb")
		end
		badgeData = badgeUnlockedData
	end

	if maskQuadData == nil then
		maskQuadData = Data:FromBundle("images/mask-round.png")
	end

	if badgeData == nil then
		error("badge:createBadgeObject(config) - badge data not found")
	end

	local req = Object:Load(badgeData, function(o)
		if o == nil then
			error("badge:createBadgeObject(config) - failed to load badge data")
		end

		o.setBadgeId = _setBadgeId
		o.setBadgeImage = _setBadgeImage
		o.getBadgeImageData = _getBadgeImageData

		local maskQuad
		local iconQuad

		local maskQuadBack
		local iconQuadBack

		if not config.locked then
			maskQuad = Quad()
			-- maskQuad.IsDoubleSided = false
			maskQuad.Color = Color(255, 255, 255, 0)
			maskQuad.Image = {
				data = maskQuadData,
				cutout = true,
			}
			maskQuad.Anchor = { 0.5, 0.5 }
			maskQuad.IsMask = true

			iconQuad = Quad()
			iconQuad.IsDoubleSided = false
			iconQuad.Color = Color(255, 255, 255, 0)
			iconQuad.Anchor = { 0.5, 0.5 }

			maskQuad:SetParent(o)
			maskQuad.Width = o.Width * 0.88 * 80
			maskQuad.Height = o.Height * 0.88 * 80
			maskQuad.Scale = 1 / 80
			maskQuad.LocalPosition.Z = -o.Depth * 0.28

			iconQuad:SetParent(maskQuad)
			iconQuad.Width = maskQuad.Width
			iconQuad.Height = maskQuad.Height

			o.iconQuad = iconQuad

			if config.frontOnly == false then
				maskQuadBack = Quad()
				-- maskQuadBack.IsDoubleSided = false
				maskQuadBack.Color = Color(255, 255, 255, 0)
				maskQuadBack.Image = {
					data = maskQuadData,
					cutout = true,
				}
				maskQuadBack.Anchor = { 0.5, 0.5 }
				maskQuadBack.IsMask = true

				iconQuadBack = Quad()
				iconQuadBack.IsDoubleSided = false
				iconQuadBack.Color = Color(255, 255, 255, 0)
				iconQuadBack.Anchor = { 0.5, 0.5 }

				maskQuadBack:SetParent(o)
				maskQuadBack.Width = o.Width * 0.88 * 80
				maskQuadBack.Height = o.Height * 0.88 * 80
				maskQuadBack.Scale = 1 / 80
				maskQuadBack.LocalPosition.Z = o.Depth * 0.28
				maskQuadBack.LocalRotation.Y = math.rad(180)

				iconQuadBack:SetParent(maskQuadBack)
				iconQuadBack.Width = maskQuadBack.Width
				iconQuadBack.Height = maskQuadBack.Height

				o.iconQuadBack = iconQuadBack
			end
		end

		if config.badgeId ~= nil and iconQuad ~= nil then
			local req = o:setBadgeId(config.badgeId, function()
				if config.callback ~= nil then
					config.callback(o) -- badge ready!
				end
			end)
			table.insert(reqs, req)
		else
			if config.callback ~= nil then
				config.callback(o)
			end
		end
	end)

	table.insert(reqs, req)
	return reqs
end

-- UIKIT SCROLL

mod.createScroll = function(self, config)
	local cellWidth = 90
	local cellHeight = 140
	local badgeHeight = cellWidth

	local theme = require("uitheme").current
	local padding = theme.padding
	local ui = require("uikit")

	local defaultConfig = {
		-- badges unlocked in this world
		-- when nil, shows all unlocked badges for userID or local player
		worldID = nil,
		userID = nil, -- badges unlocked by this user (local user if not provided)
		backgroundColor = theme.buttonTextColor,
		padding = {
			top = theme.padding,
			bottom = theme.padding,
			left = theme.padding,
			right = theme.padding,
		},
		cellPadding = theme.padding,
		direction = "right",
		createBadgeButton = false,
		showBadgesUnlocked = false,
		centerContent = true,
		ui = ui
	}

	local ok, err = pcall(function()
		config = require("config"):merge(defaultConfig, config, {
			acceptTypes = {
				worldID = { "string" },
				userID = { "string" },
				padding = { "table", "number" },
				loaded = { "function" }, -- callback(numberOfBadges)
				onOpen = { "function" }, -- callback(badgeInfo)
				onCreate = { "function" }, -- callback()
			},
		})
	end)
	if not ok then
		error("badge:createScroll(config) - config error: " .. err)
	end

	local ui = config.ui

	local createBadgeIndex = 0
	if config.createBadgeButton then
		createBadgeIndex = 1
	end

	local badgeObjectPools = {
		locked = {},
		unlocked = {},
	}
	local cellPool = {}

	local activeCells = {}
	local fetchedBadges = {}
	local createBadgeCell = nil

	local function scrollLoadCell(index)
		if index == createBadgeIndex then
			if createBadgeCell ~= nil then
				return createBadgeCell
			end

			createBadgeCell = ui:frameScrollCellWithBevel()
			createBadgeCell.Width = cellWidth
			createBadgeCell.Height = cellHeight

			local image = ui:frame({
				image = {
					data = Data:FromBundle("images/icon-plus.png"),
					alpha = true,
					filtering = true,
				},
			})
			image.object.Color = Color(180, 180, 180)
			image.Width = cellWidth * 0.6
			image.Height = image.Width
			image:setParent(createBadgeCell)

			local label = ui:createText(loc("New\nBadge"), {
				color = Color(180, 180, 180),
				size = "small",
				outline = 0.4,
				outlineColor = Color(10, 10, 10),
				alignment = "center",
			})
			label:setParent(createBadgeCell)

			createBadgeCell.onPress = function(_)
				Client:HapticFeedback()
			end

			createBadgeCell.onRelease = function(_)
				if config.onCreate ~= nil then
					config.onCreate()
				end
			end

			label.pos = {
				cellWidth * 0.5 - label.Width * 0.5,
				cellHeight * 0.5 * 0.5 - label.Height * 0.5,
			}

			local vSpaceForImage = cellHeight - (label.pos.Y + label.Height)
			image.pos = {
				cellWidth * 0.5 - image.Width * 0.5,
				cellHeight - vSpaceForImage * 0.5 - image.Height * 0.5,
			}

			return createBadgeCell
		end

		index = index - createBadgeIndex

		local badgeInfo = fetchedBadges[index]
		if badgeInfo == nil then
			return nil
		end

		local cell = table.remove(cellPool)
		if cell == nil then
			cell = ui:frame({ color = Color(255, 255, 255, 0) })
			cell.Width = cellWidth
			cell.Height = cellHeight

			local nameLabel = ui:createText("-", {
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
			local rarityLabel = ui:createText(string.format("-", rarity * 100), {
				color = Color.White,
				size = "small",
				alignment = "center",
			})
			cell.rarityLabel = rarityLabel
			rarityLabel:setParent(cell)

			cell.onRelease = function()
				local badgeInfo
				if cell.badgeIndex ~= nil then
					badgeInfo = fetchedBadges[cell.badgeIndex]
				end
				if badgeInfo ~= nil and config.onOpen ~= nil then
					config.onOpen(badgeInfo)
				end
			end
		end

		cell.badgeIndex = index
		cell.requests = {}

		local showBadgeUnlocked = config.showBadgesUnlocked or badgeInfo.unlocked
		cell.showsUnlocked = showBadgeUnlocked

		local badgeShape
		if showBadgeUnlocked then
			badgeShape = table.remove(badgeObjectPools.unlocked)
		else
			badgeShape = table.remove(badgeObjectPools.locked)
		end

		if badgeShape ~= nil and badgeShape.badgeObject ~= nil then
			local req = badgeShape.badgeObject:setBadgeId(badgeInfo.badgeID)
			table.insert(cell.requests, req)
			cell.badgeShape = badgeShape
			badgeShape:setParent(cell)
		else
			-- NOTE: add short timer to avoid sending requests when scrolling too fast
			local reqs = mod:createBadgeObject({
				badgeId = badgeInfo.badgeID,
				locked = not showBadgeUnlocked,
				frontOnly = true,
				callback = function(badgeObject)
					local badgeShape = ui:createShape(badgeObject, { spherized = false })
					badgeShape.Width = cellWidth
					badgeShape.Height = cellWidth
					badgeShape:setParent(cell)
					cell.badgeShape = badgeShape
					badgeShape.badgeObject = badgeObject

					badgeShape.pos = {
						cellWidth * 0.5 - badgeShape.Width * 0.5,
						cellHeight - badgeHeight,
					}
				end,
			})
			for _, r in reqs do
				table.insert(cell.requests, r)
			end
		end

		activeCells[cell] = true

		local rarityLabel = cell.rarityLabel
		local nameLabel = cell.nameLabel
		local badgeShape = cell.badgeShape

		nameLabel.Text = badgeInfo.name
		if badgeInfo.unlocked == true then
			nameLabel.Color = Color.Green
		else
			nameLabel.Color = Color.White
		end
		rarityLabel.Text = string.format("rarity: %.1f%%", badgeInfo.rarity * 100)

		local y = cellHeight

		nameLabel.object.Scale = 1
		if nameLabel.Width > cell.Width then
			nameLabel.object.Scale = cell.Width / nameLabel.Width
		end

		rarityLabel.object.Scale = 0.8
		if rarityLabel.Width > cell.Width then
			rarityLabel.object.Scale = cell.Width / rarityLabel.Width
		end

		local vSpace = y - badgeHeight - padding * 2
		local textHeight = nameLabel.Height + rarityLabel.Height
		if textHeight > vSpace then
			local scale = vSpace / textHeight
			nameLabel.object.Scale *= scale
			rarityLabel.object.Scale *= scale
		end

		y = y - badgeHeight

		if badgeShape ~= nil then
			badgeShape.pos = {
				cellWidth * 0.5 - badgeShape.Width * 0.5,
				y,
			}
		end

		y = y - padding - nameLabel.Height
		nameLabel.pos = {
			cellWidth * 0.5 - nameLabel.Width * 0.5,
			y,
		}

		y = y - rarityLabel.Height
		rarityLabel.pos = {
			cellWidth * 0.5 - rarityLabel.Width * 0.5,
			y,
		}

		return cell
	end
	
	local function scrollUnloadCell(index, cell)
		cell:setParent(nil)

		activeCells[cell] = true

		if cell.requests ~= nil then
			for _, req in cell.requests do
				req:Cancel()
			end
			cell.requests = {}
		end

		if index > createBadgeIndex then
			local badgeShape = cell.badgeShape
			if badgeShape ~= nil then
				cell.badgeShape = nil
				badgeShape:setParent(nil)
				if cell.showsUnlocked then
					table.insert(badgeObjectPools.unlocked, badgeShape)
				else
					table.insert(badgeObjectPools.locked, badgeShape)
				end
			end
			table.insert(cellPool, cell)
		end
	end

	local scroll = ui:scroll({
		backgroundColor = config.backgroundColor,
		padding = config.padding,
		cellPadding = config.cellPadding,
		direction = config.direction,
		loadCell = scrollLoadCell,
		unloadCell = scrollUnloadCell,
		centerContent = config.centerContent,
	})

	scroll.Height = cellHeight + config.padding.top + config.padding.bottom

	local fetchRequest = nil
	local function fetch()
		if config.worldID ~= nil and config.userID ~= nil then
			error("badge scroll can't load badges unlocked by user for a specific world yet")
		end

		if fetchRequest ~= nil then
			fetchRequest:Cancel()
		end

		local fetchFunc = function(callback)
			if config.worldID ~= nil then
				return api:listBadgesForWorld(config.worldID, callback)
			end
			local userID = config.userID or Player.UserID
			return api:listBadgesForUser(userID, callback)
		end

		fetchRequest = fetchFunc(function(err, badges)
			if err ~= nil or badges == nil then
				return
			end

			table.sort(badges, function(a, b)
				-- unlocked first
				if a.unlocked and not b.unlocked then
					return true
				elseif not a.unlocked and b.unlocked then
					return false
				end
				-- both same unlock status, sort by rarity (most common first, i.e. higher rarity value first)
				local ar = a.rarity or 0
				local br = b.rarity or 0
				return ar > br
			end)
			fetchedBadges = badges

			scroll:flush()
			scroll:refresh()

			if config.loaded ~= nil then
				config.loaded(scroll, #badges)
			end
		end)
	end

	local t = 0
	local r = Rotation()
	local tickListener = LocalEvent:Listen(LocalEvent.Name.Tick, function(dt)
		t += dt * 1.5
		r.Y = math.pi + math.sin(t) * 0.4
		r.X = math.cos(t * 1.1) * 0.3
		for cell, _ in activeCells do
			if cell.badgeShape ~= nil then
				cell.badgeShape.badgeObject.LocalRotation:Set(r)
			end
		end
	end)

	scroll.onRemove = function()
		if fetchRequest ~= nil then
			fetchRequest:Cancel()
			fetchRequest = nil
		end
		tickListener:Remove()
	end

	fetch() -- fetch once on creation

	scroll.fetch = fetch

	return scroll
end

return mod
