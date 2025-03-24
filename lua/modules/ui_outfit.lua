uiOutfit = {}

-- MODULES
modal = require("modal")
uiAvatar = require("ui_avatar")
theme = require("uitheme").current

-- CONSTANTS

-- Each menu has content + avatar
-- Here are a few constraint for responsive layout:

uiOutfit.createTryContent = function(_, config)
	local ui = config.uikit or require("uikit")

	local outfitNode = ui:createFrame()

	local content = modal:createContent()
	content.node = outfitNode

	local avatarSize = math.min(Screen.Width, 400) / 2
	local currentAvatar = uiAvatar:get(Player.Username, avatarSize, nil, ui)
	currentAvatar:setParent(outfitNode)

	local avatar = uiAvatar:get(Player.Username, avatarSize, nil, ui)
	avatar:setParent(outfitNode)

	local arrowText = ui:button({ content="➡️" })
	arrowText:disable()
	arrowText:setColorDisabled(Color.Black, Color.White)
	arrowText:setParent(outfitNode)

	local equipBtn = ui:button({ content="✅ Confirm the outfit change" })
	equipBtn:setParent(outfitNode)
	equipBtn.onRelease = function()
		require("equipments").load(config.slot, config.itemfullname, Player.Avatar, false, false, function(eq)
			if eq == nil then
				print("Error: invalid item.")
				return
			end

			-- send API request to update user avatar
			local data = {}
			data[config.slot] = config.itemfullname
			require("system_api", System):updateAvatar(data, function(err)
				if err then
					print("❌", err)
					return
				end
				LocalEvent:Send(LocalEvent.Name.LocalAvatarUpdate, System, { outfit = true })
			end)
		end)
		content:pop()
	end

	avatar.didLoad = function()
		require("equipments").load(config.slot, config.itemfullname, avatar.body.shape, false, false, function(obj)
			ui.setLayers(obj)
			for _, o in ipairs(obj.attachedParts) do
				ui.setLayers(o)
			end
		end)
	end

	outfitNode.parentDidResize = function()
		local avatarSize = outfitNode.Width * 0.5
		currentAvatar.Size = avatarSize
		avatar.Size = avatarSize

		currentAvatar.pos = {
			0,
			outfitNode.Height - currentAvatar.Height,
		}
		avatar.pos = {
			outfitNode.Width - avatar.Width,
			outfitNode.Height - avatar.Height,
		}
		arrowText.pos = {
			outfitNode.Width * 0.5 - arrowText.Width * 0.5,
			outfitNode.Height - avatar.Height * 0.5 - arrowText.Height * 0.5,
		}

		equipBtn.pos = {
			outfitNode.Width * 0.5 - equipBtn.Width * 0.5,
			0,
		}
	end
	outfitNode:parentDidResize()

	content.idealReducedContentSize = function(content)
		content.Width = math.min(Screen.Width, 350)
		content.Height = math.min(Screen.Width, 400) / 2 + equipBtn.Height + theme.padding
		return Number2(content.Width, content.Height)
	end

	return content
end

uiOutfit.create = function(_, config)
	local ui = config.uikit or require("uikit")
	local username = config.username

	local outfitNode = ui:createFrame()
	outfitNode.Width = 200
	outfitNode.Height = 200

	local content = modal:createContent()
	content.title = config.username .. "'s outfit"
	content.icon = "👕"
	content.node = outfitNode

	local avatar = uiAvatar:get(username, 200, nil, ui)
	avatar:setParent(outfitNode)

	local wearables = { "hair", "jacket", "pants", "boots" }

	local containers = {}
	for _, value in ipairs(wearables) do
		local container = ui:createFrame()
		container:hide()
		container:setParent(outfitNode)
		containers[value] = container
		local btn = ui:button({ content="" })
		btn:setParent(container)
		local textBtn = ui:createText("", Color.White, "small")
		textBtn:setParent(btn)
		btn.pos.Z = -500
		container.btn = btn
		container.textBtn = textBtn
	end

	local infoText = ui:createText("Click to try the outfit", Color.White, "small")
	infoText:setParent(outfitNode)

	outfitNode.parentDidResize = function()
		if Screen.Width < Screen.Height then
			avatar.Size = outfitNode.Height * 0.4
			avatar.pos = { outfitNode.Width * 0.5 - avatar.Width * 0.5, outfitNode.Height - avatar.Height }
			infoText.pos = { outfitNode.Width * 0.5 - infoText.Width * 0.5, 0 }
		else
			avatar.Size = outfitNode.Height - theme.padding * 2
			avatar.pos = { -avatar.Width * 0.05, theme.padding }
			infoText.pos = { outfitNode.Width * 0.66 - infoText.Width * 0.5, 0 }
		end

		local container
		container = containers.hair
		-- Items not yet loaded
		if not container.uiShape then
			return
		end

		local containerWidth
		local containerHeight
		local xOffset = 0
		if Screen.Width < Screen.Height then
			containerWidth = outfitNode.Width * 0.5
			containerHeight = (outfitNode.Height * 0.6 - infoText.Height) * 0.5
		else
			containerWidth = (outfitNode.Width - 0.85 * avatar.Width - theme.padding) * 0.5
			containerHeight = (outfitNode.Height - infoText.Height) * 0.5
			xOffset = outfitNode.Width * 0.33
		end

		local outfitContainersInfo = {
			hair = {
				pos = { xOffset, containerHeight + infoText.Height + theme.padding },
			},
			jacket = {
				pos = { xOffset + containerWidth, containerHeight + infoText.Height + theme.padding },
			},
			pants = {
				pos = { xOffset, theme.padding + infoText.Height },
			},
			boots = {
				pos = { xOffset + containerWidth, theme.padding + infoText.Height },
			},
		}

		local tmpUiText = ui:createText("")
		for key, config in pairs(outfitContainersInfo) do
			local container = containers[key]
			container.Width = containerWidth
			container.Height = containerHeight
			container.pos = config.pos

			-- Cut text
			container.btn.Width = container.Width

			local name = container.textBtn.textName
			local repo = "by @" .. container.textBtn.textRepo

			tmpUiText.Text = name
			local length = tmpUiText.Width
			if length + 2 * theme.padding >= container.btn.Width then
				local percentButtonLengthRatio = container.btn.Width / (length + theme.padding * 2)
				name = string.sub(name, 1, #repo - math.floor(#repo * (1 - percentButtonLengthRatio)) - 3) .. "…"
			end

			tmpUiText.Text = repo
			length = tmpUiText.Width
			if length + 2 * theme.padding >= container.btn.Width then
				local percentButtonLengthRatio = container.btn.Width / (length + theme.padding * 2)
				repo = string.sub(repo, 1, #repo - math.floor(#repo * (1 - percentButtonLengthRatio)) - 3) .. "…"
			end
			container.textBtn.Text = string.format("%s\n%s", name, repo)

			container.btn.Height = container.textBtn.Height + 2 * theme.padding
			container.textBtn.pos = { theme.padding * 2, theme.padding }

			container.uiShape.Width = container.Height - container.btn.Height
			container.uiShape.pos =
				{ container.Width * 0.5 - container.uiShape.Width * 0.5, container.Height - container.uiShape.Height }
		end
		tmpUiText:remove()
	end

	require("api").getAvatar(username, function(err, data)
		if err then
			return
		end

		local nbWearablesLoaded = 0
		local function nextWearableLoaded()
			nbWearablesLoaded = nbWearablesLoaded + 1
			if nbWearablesLoaded >= #wearables then
				for _, container in pairs(containers) do
					container:show()
				end
				outfitNode:parentDidResize()
			end
		end

		for _, wearableName in ipairs(wearables) do
			if data[wearableName] ~= nil then
				local container = containers[wearableName]
				local btn, textBtn = container.btn, container.textBtn
				Object:Load(data[wearableName], function(obj)
					local uiShape = ui:createShape(obj, { spherized = true })
					uiShape:setParent(container)
					container.uiShape = uiShape
					nextWearableLoaded()
				end)
				local repo, name = string.match(data[wearableName], "([^%.]+)%.([^%.]+)")
				textBtn.textName = name
				textBtn.textRepo = repo
				btn.onRelease = function()
					local activeModal = content:getModalIfContentIsActive()
					activeModal:push(uiOutfit:createTryContent({
						uikit = ui,
						slot = wearableName,
						itemfullname = data[wearableName],
					}))
				end
			end
		end
	end)

	content.idealReducedContentSize = function(content)
		if Screen.Width < Screen.Height then
			content.Width = math.min(Screen.Width * 0.7, 400)
			content.Height = Screen.Height * 0.45
		else
			content.Width = math.min(Screen.Width * 0.5, 600)
			content.Height = math.min(Screen.Height * 0.75, content.Width * 0.4)
		end
		return Number2(content.Width, content.Height)
	end

	return content
end

return uiOutfit
