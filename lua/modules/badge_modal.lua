--
-- Modal content for badge creation and editing
--

local mod = {}

local ICON_SIZE = 100

mod.createModalContent = function(_, config)
	local modal = require("modal")
	local badge = require("badge")
	local theme = require("uitheme")
	local loc = require("localize")
	local system_api = require("system_api", System)

	-- default config
	local defaultConfig = {
		uikit = require("uikit"), -- allows to provide specific instance of uikit
		onOpen = nil,
		mode = nil, -- "display" or "create" or "edit"
		badgeInfo = nil, -- must be provided if mode is "edit"
		worldId = nil, -- must be provided if mode is "create"
		locked = true,
	}

	-- merge provided config with default config
	local ok, err = pcall(function()
		config = require("config"):merge(defaultConfig, config, {
			acceptTypes = {
				onOpen = { "function" },
				mode = { "string" },
				badgeInfo = { "table" },
				worldId = { "string" },
				locked = { "boolean" },
			},
		})
	end)
	if not ok then
		error("badge_modal:createModalContent(config) - config error: " .. err, 2)
	end

	local badgeAnimationListener = nil
	local badgeObject = nil

	local function animateBadge()
		if badgeObject == nil then
			return
		end
		if badgeAnimationListener ~= nil then
			return
		end

		local t = 0
		local r = Rotation()
		badgeAnimationListener = LocalEvent:Listen(LocalEvent.Name.Tick, function(dt)
			t += dt * 1.5
			r.Y = math.sin(t) * 0.4
			r.X = math.cos(t * 1.1) * 0.3
			badgeObject.LocalRotation:Set(r)
		end)
	end

	local function removeBadgeAnimation()
		if badgeAnimationListener ~= nil then
			badgeAnimationListener:Remove()
			badgeAnimationListener = nil
		end
	end

	-- use uikit from the config
	local ui = config.uikit

	-- modal content variables
	local refreshTimer

	-- create content
	local content = modal:createContent()

	-- define some functions
	local functions = {
		constructNode = function()
			local node = ui:frame()

			-- badge creation form fields
			-- local iconData
			local tag
			local name
			local description

			-- unique cell of the scroll
			local cell = ui:frame()
			cell:setParent(nil)

			-- scroll (root element of the modal content)
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
			scroll:setParent(node)

			-- define UI elements

			local badgeShape = ui:frame()
			badgeShape.Width = ICON_SIZE
			badgeShape.Height = ICON_SIZE
			badgeShape:setParent(cell)

			local badgeId = nil
			if config.badgeInfo ~= nil then
				badgeId = config.badgeInfo.badgeID
			end
			local req = badge:createBadgeObject({
				badgeId = badgeId,
				locked = config.locked and config.mode == "display",
				frontOnly = true,
				callback = function(o)
					badgeObject = o

					local s = ui:createShape(badgeObject, { spherized = false, doNotFlip = true })
					s.Width = ICON_SIZE
					s.Height = ICON_SIZE
					s:setParent(cell)

					badgeShape:remove()
					badgeShape = s

					local y = cell.Height - theme.padding - badgeShape.Height
					badgeShape.pos = { theme.padding, y }

					node:refreshCreateButton()

					animateBadge()
				end,
			})

			local editIconBtn = ui:buttonSecondary({ content = "✏️ Set Image", textSize = "small" })
			editIconBtn:setParent(cell)
			if config.mode == "display" then
				editIconBtn.IsHidden = true
			end

			-- Tag
			local identifierLabel = nil
			if config.mode == "create" then
				identifierLabel = ui:createText(
					"The identifier is used in code to unlock the badge. (a-z & 0-9 characters only, players don't see it)",
					{
						size = "small",
						color = Color(150, 150, 150),
					}
				)
				identifierLabel:setParent(cell)
			end

			local tagTextOrEdit = nil
			if config.mode == "create" then
				tagTextOrEdit = ui:createTextInput("", "identifier")
			elseif config.mode == "edit" then
				-- config.badgeInfo.tag must exist in this case
				tag = config.badgeInfo.tag
				tagTextOrEdit = ui:createText("Badge Identifier: " .. tag, {
					size = "small",
					color = Color.White,
				})
			elseif config.mode == "display" then
				-- display the badge unlock status and date
				-- local text = "not unlocked yet"
				-- if not config.locked then
				-- 	text = "unlocked on " .. config.badgeInfo.userUnlockedAt -- this field doesn't exist yet
				-- end
				-- tagTextOrEdit = ui:createText(text, {
				-- 	size = "small",
				-- 	color = Color.White,
				-- })
			end
			if tagTextOrEdit ~= nil then
				tagTextOrEdit:setParent(cell)
			end

			-- Name
			local nameTextOrEdit = nil
			if config.mode == "create" or config.mode == "edit" then
				nameTextOrEdit = ui:createTextInput(config.badgeInfo.name or "", "Badge Name")
			elseif config.mode == "display" then
				name = config.badgeInfo.name
				nameTextOrEdit = ui:createText(name, {
					size = "default",
					color = Color.White,
				})
			end
			nameTextOrEdit:setParent(cell)

			-- Description
			local descriptionTextOrEdit = nil
			if config.mode == "create" or config.mode == "edit" then
				descriptionTextOrEdit = ui:createTextInput(config.badgeInfo.description or "", "Description")
			elseif config.mode == "display" then
				description = config.badgeInfo.description
				descriptionTextOrEdit = ui:createText(description, {
					size = "small",
					color = Color.White,
				})
			end
			descriptionTextOrEdit:setParent(cell)

			-- Create Badge Button
			local submitBtnText = nil
			if config.mode == "create" then
				submitBtnText = loc("Create")
			elseif config.mode == "edit" then
				submitBtnText = loc("Update")
			elseif config.mode == "display" then
				submitBtnText = loc("Close")
			else
				error("badge_modal:createModalContent(config): invalid mode: " .. config.mode)
			end
			local submitFormBtn = ui:buttonPositive({
				content = submitBtnText,
				padding = {
					top = theme.padding,
					bottom = theme.padding,
					left = theme.padding * 2,
					right = theme.padding * 2,
				},
			})
			submitFormBtn:disable()
			submitFormBtn:setParent(cell)

			-- Tag value has changed
			if config.mode == "create" then
				tagTextOrEdit.onTextChange = function(self)
					-- allow only alphanumeric characters and underscores
					if not self.Text:match("^%w+$") then
						self.onTextChangeSave = self.onTextChange
						self.onTextChange = nil
						self.Text = self.Text:gsub("[^%w]", "")
						self.onTextChange = self.onTextChangeSave
					end

					-- store new value
					tag = self.Text

					-- update create button
					node:refreshCreateButton()
				end
			end

			-- Name value has changed
			if config.mode == "create" or config.mode == "edit" then
				nameTextOrEdit.onTextChange = function(self)
					name = self.Text
					node:refreshCreateButton()
				end
			end

			-- Description value has changed
			if config.mode == "create" or config.mode == "edit" then
				descriptionTextOrEdit.onTextChange = function(self)
					description = self.Text
					node:refreshCreateButton()
				end
			end

			node.refreshCreateButton = function()
				if config.mode == "display" then
					submitFormBtn:enable()
				else
					if badgeObject ~= nil and badgeObject:getBadgeImageData() ~= nil and tag ~= nil and tag ~= "" then
						submitFormBtn:enable()
					else
						submitFormBtn:disable()
					end
				end
			end

			node.refresh = function(self)
				scroll.Width = self.Width

				local contentWidth = self.Width - theme.padding * 2
				if identifierLabel ~= nil then
					identifierLabel.object.MaxWidth = contentWidth
				end

				-- compute content height
				local contentHeight = theme.padding
					+ badgeShape.Height
					+ theme.padding
					+ (tagTextOrEdit.Height or 0)
					+ theme.padding
					+ nameTextOrEdit.Height
					+ theme.padding
					+ descriptionTextOrEdit.Height
					+ theme.padding
					+ submitFormBtn.Height
					+ theme.padding

				if identifierLabel ~= nil then
					contentHeight += identifierLabel.Height
					contentHeight += theme.padding
				end

				cell.Width = contentWidth
				cell.Height = contentHeight

				-- shrink to fit content if possible
				self.Height = math.min(contentHeight + theme.padding * 2, self.Height)
				scroll.Height = self.Height

				-- compute width values
				local formFieldWidth = cell.Width - theme.padding * 2
				if tagTextOrEdit ~= nil then
					tagTextOrEdit.Width = formFieldWidth
				end
				nameTextOrEdit.Width = formFieldWidth
				descriptionTextOrEdit.Width = formFieldWidth

				local y = contentHeight

				-- badge preview
				y = y - theme.padding - badgeShape.Height
				badgeShape.pos = { theme.padding, y }
				editIconBtn.pos = { badgeShape.pos.X + badgeShape.Width + theme.padding, y }

				-- tag edit + button
				if tagTextOrEdit ~= nil then
					y = y - theme.padding - tagTextOrEdit.Height
					tagTextOrEdit.pos = { theme.padding, y }
				end

				-- identifier label
				if identifierLabel ~= nil then
					y = y - theme.padding - identifierLabel.Height
					identifierLabel.pos = { theme.padding, y }
				end

				-- name edit + button
				y = y - theme.padding - nameTextOrEdit.Height
				nameTextOrEdit.pos = { theme.padding, y }

				-- description edit
				y = y - theme.padding - descriptionTextOrEdit.Height
				descriptionTextOrEdit.pos = { theme.padding, y }

				-- create badge button
				y = y - theme.padding - submitFormBtn.Height
				submitFormBtn.pos = { (cell.Width - submitFormBtn.Width) / 2, y }

				-- Update create button state
				self:refreshCreateButton()

				-- TODO: gaetan: is this really necessary?
				scroll:flush()
				scroll:refresh()
			end

			-- Import icon button callback
			if config.mode == "create" or config.mode == "edit" then
				editIconBtn.onRelease = function()
					File:OpenAndReadAll(function(success, data)
						if not success then -- TODO: handle error
							-- iconData = nil -- reset icon data
							return
						end

						if data == nil then -- TODO: handle error
							-- iconData = nil -- reset icon data
							return
						end

						-- store icon data in a variable
						-- iconData = data
						if badgeObject ~= nil then
							badgeObject:setBadgeImage(data)
						end

						node:refreshCreateButton()
					end)
				end
			end

			-- Create badge button callback
			submitFormBtn.onRelease = function()
				if config.mode == "create" then
					system_api:createBadge({
						worldID = config.worldId,
						icon = badgeObject:getBadgeImageData(),
						tag = tag,
						name = name,
						description = description,
					}, function(err)
						if err then
							Menu:ShowAlert({
								message = loc("Sorry, something went wrong. 😕"),
								neutralLabel = loc("OK"),
								neutralCallback = function() end,
							}, System)
						else
							-- badge created successfully, going back to world details
							LocalEvent:Send("badgesNeedRefresh")
							Menu:ShowAlert({
								message = loc("Badge Created! ✅"),
								neutralLabel = loc("OK"),
								neutralCallback = function()
									content:pop()
								end,
							}, System)
						end
					end)
				elseif config.mode == "edit" then
					system_api:updateBadge({
						badgeID = config.badgeInfo.badgeID,
						icon = badgeObject:getBadgeImageData(),
						name = name,
						description = description,
					}, function(err)
						if err then
							Menu:ShowAlert({
								message = loc("Sorry, something went wrong. 😕"),
								neutralLabel = loc("OK"),
								neutralCallback = function() end,
							}, System)
							return
						end
						LocalEvent:Send("badgesNeedRefresh")
						content:pop()
					end)
				elseif config.mode == "display" then
					content:pop()
				end
			end

			node:refresh()
			return node
		end,
	}

	content.idealReducedContentSize = function(node, width, height)
		node.Width = width
		node.Height = height
		node:refresh()
		return Number2(node.Width, node.Height)
	end

	content.node = functions.constructNode()
	if config.mode == "create" then
		content.title = "New Badge"
	elseif config.mode == "edit" then
		content.title = "Edit Badge"
	elseif config.mode == "display" then
		content.title = "Badge details"
	end
	content.icon = "🏅"

	content.didBecomeActive = function()
		animateBadge()
	end

	content.willResignActive = function()
		removeBadgeAnimation()
	end

	return content
end

return mod
