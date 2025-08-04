mod = {}

mod.createBadge = function(_, config)
	local theme = require("uitheme").current
	local defaultConfig = {
		count = 42,
		ui = require("uikit"),
		height = 0, -- forces badge height if not 0
		padding = 6, -- left and right padding
		vPadding = 0,
		textSize = "small",
		type = "notifications", -- "notifications" or "logs"
	}

	ok, err = pcall(function()
		config = require("config"):merge(defaultConfig, config)
	end)
	if not ok then
		error("notifications:createBadge(config) - config error: " .. err, 2)
	end

	local ui = config.ui

	local badge
	local textColor
	if config.type == "logs" then
		badge = ui:frameLogsBadge()
		textColor = Color.Black
	else
		badge = ui:frameNotificationsBadge()
		textColor = Color.White
	end
	local badgeLabel = ui:createText("", { font = Font.Noto, size = config.textSize, color = textColor })
	badgeLabel:setParent(badge)
	badge.parentDidResize = function(self)
		local parent = self.parent
		if parent == nil then
			return
		end

		local textScale = 1
		badgeLabel.object.Scale = textScale
		if config.height > 0 then
			if badgeLabel.Height + config.vPadding * 2 > config.height then
				textScale = (config.height - config.vPadding * 2) / badgeLabel.Height
				badgeLabel.object.Scale = textScale
			end
		end

		local height = badgeLabel.Height + config.vPadding * 2
		self.Width =  math.max(height, badgeLabel.Width + config.padding * 2)
		self.Height = height
		badgeLabel.pos = {
			self.Width * 0.5 - badgeLabel.Width * 0.5,
			self.Height * 0.5 - badgeLabel.Height * 0.5,
		}
		badge.pos.X = -self.Width * 0.5
		badge.pos.Y = parent.Height * 0.9 - badge.Height * 0.5
		badge.LocalPosition.Z = -900
	end

	badge.setCount = function(self, count)
		config.count = count
		badgeLabel.Text = "" .. count
		if count == 0 then
			self:hide()
		else
			self:show()
			self:parentDidResize()
		end
	end

	badge:setCount(config.count)

	return badge
end

mod.createModalContent = function(_, config)
	local requests = {}
	local function cancelRequests()
		for _, r in ipairs(requests) do
			r:Cancel()
		end
		requests = {}
	end

	local theme = require("uitheme").current
	local modal = require("modal")
	local conf = require("config")
	local systemApi = require("system_api", System)
	local time = require("time")

	-- default config
	local defaultConfig = {
		uikit = require("uikit"), -- allows to provide specific instance of uikit
	}

	config = conf:merge(defaultConfig, config)

	local ui = config.uikit

	local content = modal:createContent()
	content.closeButton = true
	content.title = "Notifications"
	content.icon = Data:FromBundle("images/icon-bell.png")

	local node = ui:createFrame()
	content.node = node

	local frame = ui:frameTextBackground()
	frame:setParent(node)

	local loadedNotifications = {}
	local nbLoadedNotifications = 0
	local recycledCells = {}

	local function notificationCellParentDidResize(self)
		self.Width = self.parent.Width

		local infoHeight = self.when.Height
		if self.icon then
			infoHeight = infoHeight + self.icon.Height + theme.paddingTiny
		end
		local y = self.Height * 0.5 - infoHeight * 0.5
		self.when.pos = {
			theme.paddingBig,
			y,
		}
		if self.icon then
			y = y + self.when.Height + theme.paddingTiny
			self.icon.pos = {
				theme.paddingBig,
				y,
			}
		end
		self.description.pos = {
			self.Width - self.description.Width - theme.paddingBig,
			self.Height * 0.5 - self.description.Height * 0.5,
		}
	end

	local function getNotificationCell(notification, containerWidth)
		local c = table.remove(recycledCells)
		if c == nil then
			c = ui:frameScrollCell()
			c.when = ui:createText("", { color = Color(150, 150, 150), size = "small" })
			c.when.object.Scale = 0.8
			c.when:setParent(c)
			c.description = ui:createText("", { color = Color(240, 240, 240), size = "small" })
			c.description:setParent(c)
			c.icon = ui:createText("", { color = Color.White, size = "small "})
			c.icon.object.Scale = 0.8
			c.icon:setParent(c)
			c.parentDidResize = notificationCellParentDidResize
		end

		if notification.category == "money" then
			c.icon.Text = "💰"
		elseif notification.category == "social" then
			c.icon.Text = "👥"
		elseif notification.category == "like" then
			c.icon.Text = "❤️"
		else
			c.icon.Text = "❌"
		end

		local t, units = time.ago(notification.created, {
			years = false,
			months = false,
			seconds_label = "s",
			minutes_label = "m",
			hours_label = "h",
			days_label = "d",
		})
		c.when.Text = "" .. t .. units .. " ago"

		c.description.object.MaxWidth = containerWidth - c.when.Width - theme.paddingBig * 3
		c.description.Text = notification.message or ""

		c.Height = math.max(c.description.Height, c.icon.Height + theme.paddingTiny + c.when.Height) + theme.padding * 2

		return c
	end

	local function recycleNotificationCell(cell)
		cell:setParent(nil)
		table.insert(recycledCells, cell)
	end

	local scroll = ui:scroll({
		padding = {
			top = theme.padding,
			bottom = theme.padding,
			left = 0,
			right = 0,
		},
		cellPadding = theme.padding,
		loadCell = function(index, _, container) -- TODO: use container to create cell with right constraints
			if index <= nbLoadedNotifications then
				local c = getNotificationCell(loadedNotifications[index], container.Width)
				return c
			end
		end,
		unloadCell = function(_, cell)
			recycleNotificationCell(cell)
		end,
	})
	scroll:setParent(frame)

	local okBtn

	local functions = {}

	functions.layout = function(width, height)
		width = width or frame.parent.Width
		height = height or frame.parent.Height

		frame.Width = width
		local frameHeight = height

		if okBtn ~= nil then
			okBtn.Width = width - theme.padding * 2
			frameHeight = frameHeight - okBtn.Height - theme.padding - theme.paddingTiny
			okBtn.pos.X = width * 0.5 - okBtn.Width * 0.5
			okBtn.pos.Y = theme.paddingTiny
		end

		frame.Height = frameHeight

		frame.pos = { 0, height - frameHeight, 0 }

		scroll.Height = frame.Height
		scroll.Width = frame.Width - theme.padding * 2
		scroll.pos = { theme.padding, 0 }
	end

	functions.createOpenSettingsBtn = function()
		local padding = theme.padding
		local buttonContent = ui:frame()
		local line1 = ui:createText("⚙️ Open Settings", { font = Font.Pixel, size = "default" })
		line1:setParent(buttonContent)
		local line2 = ui:createText("➡️ Turn ON Notifications", { font = Font.Pixel, size = "default" })
		line2:setParent(buttonContent)
		buttonContent.parentDidResize = function(self)
			line1.object.MaxWidth = self.parent.Width - padding * 2
			line2.object.MaxWidth = self.parent.Width - padding * 2
			self.Width = math.max(line1.Width, line2.Width)
			self.Height = line1.Height + padding + line2.Height
			line2.pos = {
				self.Width * 0.5 - line2.Width * 0.5,
				0,
			}
			line1.pos = {
				self.Width * 0.5 - line1.Width * 0.5,
				line2.pos.Y + line2.Height + padding,
			}
		end

		local btn = ui:buttonNeutral({
			content = buttonContent,
			padding = 10,
		})

		btn.onRelease = function()
			System:DebugEvent("User presses OPEN SETTINGS button", { context = "notifications menu" })
			System:OpenAppSettings()
		end

		return btn
	end

	functions.createTurnOnPushNotificationsBtn = function()
		local padding = theme.padding
		local buttonContent = ui:frame()
		local line1 = ui:createText("Turn ON Push Notifications", { font = Font.Pixel, size = "default" })
		line1:setParent(buttonContent)
		local line2 = ui:createText("+100 🇵 reward!", { font = Font.Pixel, size = "default" })
		line2:setParent(buttonContent)
		buttonContent.parentDidResize = function(self)
			line1.object.MaxWidth = self.parent.Width - padding * 2
			line2.object.MaxWidth = self.parent.Width - padding * 2
			self.Width = math.max(line1.Width, line2.Width)
			self.Height = line1.Height + padding + line2.Height
			line2.pos = {
				self.Width * 0.5 - line2.Width * 0.5,
				0,
			}
			line1.pos = {
				self.Width * 0.5 - line1.Width * 0.5,
				line2.pos.Y + line2.Height + padding,
			}
		end

		local btn = ui:buttonPositive({
			content = buttonContent,
			padding = 10,
		})

		btn.onRelease = function()
			System:DebugEvent("User presses TURN ON notifications button", { context = "notifications menu" })
			System:NotificationRequestAuthorization(function(response)
				System:DebugEvent(
					"App receives notification authorization response",
					{ response = response, context = "notifications menu" }
				)
				functions.refreshNotificationBtn()
			end)
		end

		return btn
	end

	local previousNotificationStatus
	functions.refreshNotificationBtn = function()
		System:NotificationGetStatus(function(status)
			-- DEBUG:
			-- local statuses = { "underdetermined", "postponed", "denied", "authorized" }
			-- notificationStatus = statuses[math.random(1, #statuses)]

			if status == previousNotificationStatus then
				return
			end

			previousNotificationStatus = status
			if okBtn then
				okBtn:remove()
				okBtn = nil
			end

			if status == "underdetermined" or status == "postponed" then
				okBtn = functions.createTurnOnPushNotificationsBtn()
				okBtn:setParent(node)
			elseif status == "denied" then
				okBtn = functions.createOpenSettingsBtn()
				okBtn:setParent(node)
			end

			functions.layout()
		end)
	end
	functions.refreshNotificationBtn()

	content.idealReducedContentSize = function(_, width, height)
		width = math.min(width, 500)
		functions.layout(width, height)
		return Number2(width, height)
	end

	local appDidBecomeActiveListener
	content.willResignActive = function()
		if appDidBecomeActiveListener then
			appDidBecomeActiveListener:Remove()
			appDidBecomeActiveListener = nil
		end
		cancelRequests()
	end

	content.didBecomeActive = function()
		if appDidBecomeActiveListener == nil then
			appDidBecomeActiveListener = LocalEvent:Listen(LocalEvent.Name.AppDidBecomeActive, function()
				functions.refreshNotificationBtn()
			end)

			-- NOTE: didBecomeActive is called twice
			-- calling getNotifications within this block to avoid doing it twice.
			-- TODO: fix this `didBecomeActive` issue, could be an important optimization in other modals
			req = systemApi:getNotifications({}, function(notifications, err)
				if err then
					return
				end
				loadedNotifications = notifications
				nbLoadedNotifications = #notifications
				if type(scroll.flush) ~= "function" then
					return
				end
				scroll:flush()
				scroll:refresh()

				systemApi:readNotifications({
					callback = function(err)
						if err == nil then
							System.NotificationCount = 0 -- removes icon badge
							LocalEvent:Send(LocalEvent.Name.NotificationCountDidChange)
						end
					end,
				})
			end)

			table.insert(requests, req)
		end
	end

	return content
end

return mod
