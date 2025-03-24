settings = {}

--- Creates modal content for app settings
--- config(table): contents "cache" and "logout" keys, set either of these to true to display associated buttons
--- returns: modal
settings.createModalContent = function(_, config)
	-- MODULES
	local modal = require("modal")
	local theme = require("uitheme")

	-- CONSTANTS
	local SENSITIVITY_STEP = 0.1
	local MIN_SENSITIVITY = 0.1
	local MAX_SENSITIVITY = 3.0
	local VOLUME_STEP = 0.05
	local MIN_VOLUME = 0.0
	local MAX_VOLUME = 1.0

	if config ~= nil and type(config) ~= "table" then
		error("setting:create(<config>): config should be a table", 2)
	end

	-- default config
	local _config = {
		account = true,
		clearCache = false,
		uikit = require("uikit"),
	}

	if config then
		for k, v in pairs(_config) do
			if type(config[k]) == type(v) then
				_config[k] = config[k]
			end
		end
	end

	config = _config

	local ui = config.uikit

	local settingsNode = ui:createFrame()

	local content = modal:createContent()
	content.title = "Settings"
	content.icon = Data:FromBundle("images/icon-settings.png")
	content.node = settingsNode

	local rows = {}

	-- VOLUME

	local volumeLabel = ui:createText("", {
		color = Color.White,
	})
	local function refreshVolumeLabel()
		volumeLabel.Text = string.format("Volume: %.2f ", System.MasterVolume)
	end
	refreshVolumeLabel()

	local volumeMinus = ui:buttonSecondary({ content = "➖" })
	volumeMinus.label = volumeLabel
	volumeMinus.onRelease = function(_)
		System.MasterVolume = math.max(System.MasterVolume - VOLUME_STEP, MIN_VOLUME)
		refreshVolumeLabel()
	end

	local volumePlus = ui:buttonSecondary({ content = "➕" })
	volumePlus.label = volumeLabel
	volumePlus.onRelease = function(_)
		System.MasterVolume = math.min(System.MasterVolume + VOLUME_STEP, MAX_VOLUME)
		refreshVolumeLabel()
	end

	table.insert(rows, { volumeLabel, volumeMinus, volumePlus })

	-- SENSITIVITY

	local sensitivityLabel = ui:createText("", {
		color = Color.White,
	})
	local function refreshSensitivityLabel()
		sensitivityLabel.Text = string.format("Sensitivity: %.1f ", System.Sensitivity)
	end
	refreshSensitivityLabel()

	local sensitivityMinus = ui:buttonSecondary({ content = "➖" })
	sensitivityMinus.label = sensitivityLabel
	sensitivityMinus.onRelease = function(_)
		System.Sensitivity = math.max(System.Sensitivity - SENSITIVITY_STEP, MIN_SENSITIVITY)
		refreshSensitivityLabel()
	end

	local sensitivityPlus = ui:buttonSecondary({ content = "➕" })
	sensitivityPlus.label = sensitivityLabel
	sensitivityPlus.onRelease = function(_)
		System.Sensitivity = math.min(System.Sensitivity + SENSITIVITY_STEP, MAX_SENSITIVITY)
		refreshSensitivityLabel()
	end

	table.insert(rows, { sensitivityLabel, sensitivityMinus, sensitivityPlus })

	-- ZOOM SENSITIVITY

	local zoomSensitivityLabel = ui:createText("", {
		color = Color.White,
	})
	local function refreshZoomSensitivityLabel()
		zoomSensitivityLabel.Text = string.format("Zoom sensitivity: %.1f ", System.ZoomSensitivity)
	end
	refreshZoomSensitivityLabel()

	local zoomSensitivityMinus = ui:buttonSecondary({ content = "➖" })
	zoomSensitivityMinus.label = zoomSensitivityLabel
	zoomSensitivityMinus.onRelease = function(_)
		System.ZoomSensitivity = math.max(System.ZoomSensitivity - SENSITIVITY_STEP, MIN_SENSITIVITY)
		refreshZoomSensitivityLabel()
	end

	local zoomSensitivityPlus = ui:buttonSecondary({ content = "➕" })
	zoomSensitivityPlus.label = zoomSensitivityLabel
	zoomSensitivityPlus.onRelease = function(_)
		System.ZoomSensitivity = math.min(System.ZoomSensitivity + SENSITIVITY_STEP, MAX_SENSITIVITY)
		refreshZoomSensitivityLabel()
	end

	table.insert(rows, { zoomSensitivityLabel, zoomSensitivityMinus, zoomSensitivityPlus })

	-- RENDER QUALITY

	local renderQualityLabel = ui:createText("", {
		color = Color.White,
	})
	local rqMinus = ui:buttonSecondary({ content = "➖" })
	local rqPlus = ui:buttonSecondary({ content = "➕" })

	local function refreshRenderQualityLabel()
		if System.RenderQualityTiersAvailable then
			renderQualityLabel.Text =
				string.format("Render Quality: %d/%d ", System.RenderQualityTier, System.MaxRenderQualityTier)
		else
			rqMinus:disable()
			rqPlus:disable()
			renderQualityLabel.Text = string.format("Render Quality: 1/%d ", System.MaxRenderQualityTier)
		end

		local modal = content:getModalIfContentIsActive()
		if modal then
			modal:refreshContent()
		end
	end

	rqMinus.label = sensitivityLabel
	rqMinus.onRelease = function(_)
		System.RenderQualityTier = math.max(System.RenderQualityTier - 1, System.MinRenderQualityTier)
		refreshRenderQualityLabel()
	end

	rqPlus.label = sensitivityLabel
	rqPlus.onRelease = function(_)
		System.RenderQualityTier = math.min(System.RenderQualityTier + 1, System.MaxRenderQualityTier)
		refreshRenderQualityLabel()
	end

	refreshRenderQualityLabel()

	table.insert(rows, { renderQualityLabel, rqMinus, rqPlus })

	-- HAPTIC FEEDBACK
	local hapticFeedbackToggle
	if Client.IsMobile then
		local hapticFeedbackLabel = ui:createText("Haptic Feedback:", Color.White)

		hapticFeedbackToggle = ui:buttonNeutral({ content = "ON" })
		if System.HapticFeedbackEnabled then
			hapticFeedbackToggle.Text = "ON"
			hapticFeedbackToggle:setColor(theme.colorPositive)
		else
			hapticFeedbackToggle.Text = "OFF"
			hapticFeedbackToggle:setColor(theme.colorNegative)
		end

		hapticFeedbackToggle.onRelease = function(_)
			System.HapticFeedbackEnabled = not System.HapticFeedbackEnabled

			if System.HapticFeedbackEnabled then
				hapticFeedbackToggle.Text = "ON"
				hapticFeedbackToggle:setColor(theme.colorPositive)
			else
				hapticFeedbackToggle.Text = "OFF"
				hapticFeedbackToggle:setColor(theme.colorNegative)
			end
		end

		table.insert(rows, { hapticFeedbackLabel, hapticFeedbackToggle })
	end

	-- FULLSCREEN
	local fullscreenToggle
	if Client.OSName == "Windows" then
		local fullscreenLabel = ui:createText("Fullscreen:", Color.White)

		fullscreenToggle = ui:buttonNeutral({ content = "ON" })
		if System.Fullscreen then
			fullscreenToggle.Text = "ON"
			fullscreenToggle:setColor(theme.colorPositive)
		else
			fullscreenToggle.Text = "OFF"
			fullscreenToggle:setColor(theme.colorNegative)
		end

		fullscreenToggle.onRelease = function(_)
			System.Fullscreen = not System.Fullscreen

			if System.Fullscreen then
				fullscreenToggle.Text = "ON"
				fullscreenToggle:setColor(theme.colorPositive)
			else
				fullscreenToggle.Text = "OFF"
				fullscreenToggle:setColor(theme.colorNegative)
			end
		end

		table.insert(rows, { fullscreenLabel, fullscreenToggle })
	end

	-- CACHE

	cacheAndLogoutRow = {}

	if _config.account == true then
		local accountButton = ui:buttonNeutral({ content = "Account settings", textSize = "small" })
		accountButton.onRelease = function(_)
			local accountContent = modal:createContent()
			accountContent.title = "Account"
			accountContent.icon = Data:FromBundle("images/icon-settings.png")

			local node = ui:createFrame()
			accountContent.node = node

			local logoutButton = ui:buttonNegative({ content = "Logout", textSize = "small", padding = theme.padding })
			logoutButton:setColor(theme.colorNegative)
			logoutButton:setParent(node)

			logoutButton.onRelease = function(_)
				local logoutContent = modal:createContent()
				logoutContent.title = "Logout"
				logoutContent.icon = "⚙️"

				local node = ui:createFrame()
				logoutContent.node = node

				local text = ui:createText("Are you sure you want to logout now?", Color.White)
				text:setParent(node)

				text.object.MaxWidth = 300

				logoutContent.idealReducedContentSize = function(_, _, _)
					local w, h = text.Width + theme.padding * 2, text.Height + theme.padding * 2
					return Number2(w, h)
				end

				node.parentDidResize = function(self)
					local w = text.Width
					text.pos.X = self.Width * 0.5 - w * 0.5
					text.pos.Y = self.Height - text.Height - theme.padding
				end

				local yes = ui:buttonNeutral({ content = "Yes! 🙂" })
				yes.onRelease = function()
					local modal = logoutContent:getModalIfContentIsActive()
					if modal then
						modal:close()
					end
					System:Logout()
				end
				logoutContent.bottomCenter = { yes }

				accountContent:push(logoutContent)
			end

			local deleteButton = ui:button({
				content = "Delete account",
				textSize = "small",
				underline = true,
				color = Color(0, 0, 0, 0),
				borders = false,
				padding = false,
				shadow = false,
			})
			deleteButton:setColor(Color(0, 0, 0, 0), theme.colorNegative)
			deleteButton:setParent(node)

			deleteButton.onRelease = function(_)
				local deleteContent = modal:createContent()
				deleteContent.title = "Account deletion"
				deleteContent.icon = "⚙️"

				local node = ui:createFrame()
				deleteContent.node = node

				local text =
					ui:createText("⚠️ Are you REALLY sure you want to delete your account now?", Color.White)
				text:setParent(node)

				local text2 = ui:createText("Type your username to confirm:", Color.White)
				text2:setParent(node)

				text.object.MaxWidth = 300
				text2.object.MaxWidth = 300

				local input = ui:createTextInput("", "username", { textSize = "default" })
				input:setParent(node)

				local req

				node.parentDidResize = function(self)
					local w = math.max(text.Width, text2.Width)

					text.pos.X = self.Width * 0.5 - w * 0.5
					text.pos.Y = self.Height - text.Height - theme.padding

					text2.pos.X = self.Width * 0.5 - w * 0.5
					text2.pos.Y = text.pos.Y - text2.Height - theme.padding

					input.Width = w
					input.pos.X = self.Width * 0.5 - w * 0.5
					input.pos.Y = text2.pos.Y - input.Height - theme.padding
				end

				deleteContent.idealReducedContentSize = function(_, _, _, _)
					local w = math.max(text.Width, text2.Width) + theme.padding * 2
					local h = text.Height + text2.Height + input.Height + theme.padding * 4
					return Number2(w, h)
				end

				local yes = ui:button({ content="🗑️ Delete account" })
				yes:disable()
				yes.onRelease = function()
					yes:disable()
					req = require("system_api", System):deleteUser(function(success)
						req = nil
						if success == true then
							local modal = deleteContent:getModalIfContentIsActive()
							if modal then
								modal:close()
							end
							System:Logout()
						else
							if string.lower(input.Text) == string.lower(Player.Username) then
								yes:enable()
							end
						end
					end)
				end

				input.onTextChange = function()
					if req ~= nil then
						req:Cancel()
						req = nil
					end
					if string.lower(input.Text) == string.lower(Player.Username) then
						yes:enable()
					else
						yes:disable()
					end
				end

				deleteContent.bottomCenter = { yes }

				accountContent:push(deleteContent)
			end

			node.parentDidResize = function(self)
				logoutButton.pos.X = self.Width * 0.5 - logoutButton.Width * 0.5
				logoutButton.pos.Y = self.Height - logoutButton.Height - theme.padding

				deleteButton.pos.X = self.Width * 0.5 - deleteButton.Width * 0.5
				deleteButton.pos.Y = logoutButton.pos.Y - deleteButton.Height - theme.padding
			end

			accountContent.idealReducedContentSize = function(_, _, _, minWidth)
				local w = math.max(logoutButton.Width, deleteButton.Width, 250)
				local h = logoutButton.Height + deleteButton.Height + theme.padding * 3
				w = math.max(minWidth, w)
				return Number2(w, h)
			end

			content:push(accountContent)
		end
		table.insert(cacheAndLogoutRow, accountButton)
	end

	if _config.clearCache == true then
		local cacheButton = ui:buttonNeutral({ content = "Clear cache", textSize = "small" })
		cacheButton.onRelease = function(_)
			local clearCacheContent = modal:createContent()
			clearCacheContent.title = "Settings"
			clearCacheContent.icon = Data:FromBundle("images/icon-settings.png")

			local node = ui:createFrame()
			clearCacheContent.node = node

			local text = ui:createText(
				"⚠️ Clearing all cached data from visited experiences, are you sure about this?",
				Color.White,
				"default"
			)
			text.pos.X = theme.padding
			text.pos.Y = theme.padding
			text:setParent(node)

			text.object.MaxWidth = 300

			clearCacheContent.idealReducedContentSize = function(_, _, _, minWidth)
				local w = text.Width + theme.padding * 2
				local h = text.Height + theme.padding * 2
				w = math.max(minWidth, w)
				return Number2(w, h)
			end

			local yes = ui:buttonNeutral({ content = "Yes, delete cache! 💀" })
			yes.onRelease = function()
				System.ClearCache()
				local done = ui:createText("✅ Done!", Color.White)
				clearCacheContent.bottomCenter = { done }
			end
			clearCacheContent.bottomCenter = { yes }

			content:push(clearCacheContent)
		end
		table.insert(cacheAndLogoutRow, cacheButton)
	end

	if #cacheAndLogoutRow > 0 then
		table.insert(rows, cacheAndLogoutRow)
	end

	-- UI setup

	for _, row in ipairs(rows) do
		for _, element in ipairs(row) do
			element:setParent(settingsNode)
		end
	end

	local refresh = function()
		-- button only used as a min width reference for some buttons
		local btn = ui:button({ content="OFF" })
		local toggleWidth = btn.Width + theme.padding * 2
		btn.Text = "➕"
		local oneEmojiWidth = btn.Width + theme.padding
		btn:remove()

		if hapticFeedbackToggle ~= nil then
			hapticFeedbackToggle.Width = toggleWidth
		end
		if fullscreenToggle ~= nil then
			fullscreenToggle.Width = toggleWidth
		end
		sensitivityMinus.Width = oneEmojiWidth
		sensitivityPlus.Width = oneEmojiWidth
		zoomSensitivityMinus.Width = oneEmojiWidth
		zoomSensitivityPlus.Width = oneEmojiWidth
		rqMinus.Width = oneEmojiWidth
		rqPlus.Width = oneEmojiWidth

		local totalHeight = 0
		local totalWidth = 0
		local rowHeight
		local rowWidth

		for i, row in ipairs(rows) do
			if row.hidden == true then
				for _, element in ipairs(row) do
					element:hide()
				end
			else
				rowHeight = 0
				rowWidth = 0

				for j, element in ipairs(row) do
					element:show()
					rowHeight = math.max(rowHeight, element.Height)
					rowWidth = rowWidth + element.Width + (j > 1 and theme.padding or 0)
				end

				totalHeight = totalHeight + rowHeight + (i > 1 and theme.padding or 0)
				totalWidth = math.max(totalWidth, rowWidth)

				row.height = rowHeight
				row.width = rowWidth
			end
		end

		totalWidth = totalWidth + theme.padding * 2
		totalHeight = totalHeight + theme.padding * 2

		local vCursor = totalHeight - theme.padding
		local hCursor

		for _, row in ipairs(rows) do
			if not row.hidden then
				hCursor = (totalWidth - row.width) * 0.5
				for _, element in ipairs(row) do
					element.pos.X = hCursor
					element.pos.Y = vCursor - row.height * 0.5 - element.Height * 0.5
					hCursor = hCursor + element.Width + theme.padding
				end
				vCursor = vCursor - row.height - theme.padding
			end
		end

		return totalWidth, totalHeight
	end

	content.idealReducedContentSize = function(_, _, _)
		local w, h = refresh()
		return Number2(w, h)
	end

	return content
end

return settings
