local mod = {}

ui = require("uikit")
theme = require("uitheme").current
avatar = require("avatar")
itemGrid = require("item_grid")

local MAX_COLOR_SWATCH_SIZE = 100
local PADDING = 4.0
local CELL_PADDING = 4.0
local SCROLL_PADDING = 4.0
local ITEMS_PER_PAGE = 100

privateFields = setmetatable({}, { __mode = "k" })

function contentMaxHeight()
	return Screen.Height * 0.4
end

local avatarProperties = {
	skinColorIndex = nil,
	noseIndex = nil,
	eyesIndex = nil,
	eyesColorIndex = nil,
	hair = nil,
	jacket = nil,
	pants = nil,
	boots = nil,
}

local cache = {
	search = "",
	sort = "likes:desc",
}

function filterDidChange(search, sort)
	cache.search = search
	cache.sort = sort
end

local apiUpdateTimer = nil
local avatarDidChange = function(change)
	-- `change` argument is a table and can contain the following keys:
	-- - skinColorIndex
	-- - eyesColorIndex
	-- - eyesIndex
	-- - noseIndex
	-- - hair
	-- - jacket
	-- - pants
	-- - boots

	-- Update avatarProperties with content of `change` table
	for key, value in pairs(change) do
		avatarProperties[key] = value
	end

	if apiUpdateTimer == nil then
		apiUpdateTimer = Timer(1, false, function()
			-- send API request
			local api = require("system_api", System)

			local data = {
				skinColorIndex = avatarProperties.skinColorIndex,
				eyesColorIndex = avatarProperties.eyesColorIndex,
				eyesIndex = avatarProperties.eyesIndex,
				noseIndex = avatarProperties.noseIndex,
				hair = avatarProperties.hair,
				jacket = avatarProperties.jacket,
				pants = avatarProperties.pants,
				boots = avatarProperties.boots,
				-- Later, with premium account:
				-- skinColor1
				-- skinColor2
				-- skinColorNose
				-- skinColorMouth
				-- eyesColor
			}

			api:updateAvatar(data, function(_) -- err
				-- TODO: update animation & retry on error?
			end)

			-- destroy timer
			apiUpdateTimer = nil
		end)
	end
	-- else, timer is already running
end

mod.create = function(self, config)
	if self ~= mod then
		error("ui_avatar_editor:create(config) should be called with `:`", 2)
	end

	local defaultConfig = {
		ui = ui, -- can only be used by System to override UI instance
		margin = theme.padding,
		requestHeightCallback = function(_) end, -- height
		saveOnChangeIfLocalPlayer = false,
	}

	local ok, err = pcall(function()
		config = require("config"):merge(defaultConfig, config)
	end)
	if not ok then
		error("ui_avatar_editor:create(config) - config error: " .. err, 2)
	end

	local ui = config.ui
	local node = ui:createFrame(Color(0, 0, 0, 0))

	privateFields[node] = {}

	node.onRemove = function(self)
		privateFields[self] = nil
	end

	local refButton = ui:button({ content="dummy" })
	refButton:setParent(nil)

	local categoryNode
	local categories

	local function setSkin()
		if categoryNode then
			categoryNode:remove()
		end
		categoryNode = ui:createFrame()

		local btns = {}
		for skinColorIndex, color in pairs(avatar.skinColors) do
			local btn = ui:button({
				content = "",
				color = color.skin1,
			})
			btn.onRelease = function()
				avatarProperties.skinColorIndex = skinColorIndex
				local change = { skinColorIndex = skinColorIndex }
				avatarDidChange(change)
				LocalEvent:Send("avatar_editor_update", change)
			end
			btn:setParent(categoryNode)
			table.insert(btns, btn)
		end

		btns[1].parentDidResize = function(self)
			local parent = self.parent
			local half = math.floor(#btns / 2)
			local size = (parent.Width - theme.padding * (half - 1)) / half
			size = math.min(Screen.Height * 0.15, MAX_COLOR_SWATCH_SIZE, size)
			local totalSize = (size + theme.padding) * half - theme.padding
			local startX = parent.Width * 0.5 - totalSize * 0.5
			for i = 1, half do
				btn = btns[i]
				btn.Width = size
				btn.Height = size
				btn.pos = { startX + (i - 1) * (size + theme.padding), btn.Height + theme.padding }
			end
			for i = half + 1, #btns do
				btn = btns[i]
				btn.Width = size
				btn.Height = size
				btn.pos = { startX + (i - half - 1) * (size + theme.padding), 0 }
			end

			config.requestHeightCallback(size * 2 + theme.padding * 2 + categories.Height)
		end

		categoryNode:setParent(node)
		categories:parentDidResize()
		LocalEvent:Send("avatar_editor_should_focus_on_body")
	end

	local btns = {}

	local displayedCategoryIndex = 1

	local function refreshCategoryButtons()
		for _, b in pairs(btns) do
			if b.index == displayedCategoryIndex then
				b:select()
			else
				b:unselect()
			end
		end
	end

	categories = ui:scroll({
		backgroundColor = theme.buttonTextColor,
		direction = "right",
		cellPadding = CELL_PADDING,
		padding = SCROLL_PADDING,
		loadCell = function(index)
			if index == 1 then
				local btn = ui:buttonNeutral({ content = "🙂 Skin" })
				btn.index = index
				btns[btn.index] = btn
				btn.onRelease = function()
					if displayedCategoryIndex == index then
						return
					end
					displayedCategoryIndex = index
					refreshCategoryButtons()

					setSkin()
				end
				return btn
			elseif index == 2 then
				local btn = ui:buttonNeutral({ content = "✨ Hair" })
				btn.index = index
				btns[btn.index] = btn
				btn.onRelease = function()
					if displayedCategoryIndex == index then
						return
					end
					displayedCategoryIndex = index
					refreshCategoryButtons()

					if categoryNode then
						categoryNode:remove()
					end
					categoryNode = itemGrid:create({
						categories = { "hair", "featured" },
						perPage = ITEMS_PER_PAGE,
						uikit = ui,
						backgroundColor = theme.buttonTextColor,
						cellPadding = CELL_PADDING,
						padding = SCROLL_PADDING,
						search = cache.search,
						sort = cache.sort,
						filterDidChange = filterDidChange,
						onOpen = function(entity)
							local change = { hair = entity.fullName }
							avatarDidChange(change)
							LocalEvent:Send("avatar_editor_update", change)
						end,
					})
					categoryNode:setParent(node)
					categories:parentDidResize()

					config.requestHeightCallback(10000)
					LocalEvent:Send("avatar_editor_should_focus_on_head")
				end
				return btn
			elseif index == 3 then
				local btn = ui:buttonNeutral({ content = "🙂 Eyes" })
				btn.index = index
				btns[btn.index] = btn
				btn.onRelease = function()
					if displayedCategoryIndex == index then
						return
					end
					displayedCategoryIndex = index
					refreshCategoryButtons()

					if categoryNode then
						categoryNode:remove()
					end
					categoryNode = ui:createFrame()

					local uiAvatar = require("ui_avatar")
					local btnRatio = 130 / 90
					local headMaskRatio = 190 / 130
					local size = 130

					local btns = {}
					for eyesIndex, _ in pairs(avatar.eyes) do
						-- 13 x 9
						-- 19 x 9 with ears
						local mask = ui:createFrame(Color(0, 0, 0, 0))
						mask.IsMask = true
						mask.Width = size
						mask.Height = size / btnRatio
						mask:setParent(categoryNode)
						local head = uiAvatar:getHead("", size * headMaskRatio, ui, { spherized = false })
						head:setParent(mask)

						head:setEyes({
							index = eyesIndex,
							color = avatar.eyeColors[avatarProperties.eyesColorIndex],
						})

						head:setNose({ index = avatarProperties.noseIndex })

						local colors = avatar.skinColors[avatarProperties.skinColorIndex]
						if colors == nil then
							colors = Player.Avatar:getColors()
						end
						head:setColors({
							skin1 = colors.skin1,
							skin2 = colors.skin2,
							nose = colors.nose,
							mouth = colors.mouth,
						})

						head.pos.X = mask.Width * 0.5 - head.Width * 0.5
						mask.head = head

						local btn = ui:button({
							content = mask,
							color = Color(181, 186, 193),
							padding = false,
						})
						btn.head = head

						btn.onRelease = function()
							avatarProperties.eyesIndex = eyesIndex
							local change = { eyesIndex = eyesIndex }
							avatarDidChange(change)
							LocalEvent:Send("avatar_editor_update", change)
						end
						btn:setParent(categoryNode)
						table.insert(btns, btn)
					end

					local colorBtns = {}
					local lastIndex = #avatar.eyeColors
					for eyesColorIndex, color in ipairs(avatar.eyeColors) do
						local btn
						if eyesColorIndex == lastIndex then -- premium feature, not yet implemented
							btn = ui:button({
								content = "🎨",
								color = Color(0, 0, 0, 0.3),
							})
							local premiumBadge = ui:createText("👑", { size = "big" })
							premiumBadge.parentDidResize = function(self)
								local parent = self.parent
								self.pos.X = parent.Width - self.Width - 5
								self.pos.Y = 5
							end
							premiumBadge:setParent(btn)

							btn:disable()
						else
							btn = ui:button({
								content = "",
								color = color,
							})
							btn.onRelease = function()
								-- head:setColors({
								-- 	skin1 = colors.skin1,
								-- 	skin2 = colors.skin2,
								-- 	nose = colors.nose,
								-- 	mouth = colors.mouth,
								-- })
								avatarProperties.eyesColorIndex = eyesColorIndex
								local change = { eyesColorIndex = eyesColorIndex }
								avatarDidChange(change)
								LocalEvent:Send("avatar_editor_update", change)

								for _, b in ipairs(btns) do
									b.head:setEyes({
										color = avatar.eyeColors[avatarProperties.eyesColorIndex],
									})
								end
							end
						end

						btn:setParent(categoryNode)
						table.insert(colorBtns, btn)
					end

					btns[1].parentDidResize = function(self)
						local parent = self.parent
						local maxHeight = contentMaxHeight()

						-- one section for eye shapes, one for colors
						local maxEyeShapeSectionWidth = (parent.Width - theme.padding) * 0.5

						-- EYE SHAPES

						local columns = 2
						local rows = math.floor(#avatar.eyes / columns)
						local btnMaxHeight = ((maxHeight + theme.padding) / rows) - theme.padding

						local btnWidth = (maxEyeShapeSectionWidth - theme.padding * (columns - 1)) / columns
						local btnHeight = math.min(btnWidth * 1 / btnRatio, btnMaxHeight)
						btnWidth = btnHeight * btnRatio

						local maskWidth = btnWidth - 3 * 2 -- 3 = border
						local maskHeight = btnHeight - 3 * 2 -- 3 = border

						-- local totalSize = (btnWidth + theme.padding) * columns - theme.padding
						local startX = 0
						local startY = (rows - 1) * (btnHeight + theme.padding)

						local row, x
						for i = 1, #btns do
							row = math.floor((i - 1) / columns)
							x = ((i - 1) % columns) + 1
							btn = btns[i]
							btn.content.Width = maskWidth
							btn.content.Height = maskHeight
							btn.content.head.Width = maskWidth * headMaskRatio
							btn.content.head.pos.X = btn.content.Width * 0.5 - btn.content.head.Width * 0.5
							btn.pos = {
								startX + (x - 1) * (btnWidth + theme.padding),
								startY - (row * (btnHeight + theme.padding)),
							}
						end

						local eyesectionWidth = (btnWidth + theme.padding) * columns
						local eyesectionHeightPlusOnePadding = (btnHeight + theme.padding) * rows
						local remainingWidthForColorSection = parent.Width - eyesectionWidth

						-- COLORS

						columns = 2
						rows = math.floor(#colorBtns / columns)
						-- btnMaxHeight = ((maxHeight + theme.padding) / rows) - theme.padding

						btnWidth = (remainingWidthForColorSection - theme.padding * (columns - 1)) / columns
						btnHeight = (eyesectionHeightPlusOnePadding / rows) - theme.padding

						startX = eyesectionWidth
						startY = (rows - 1) * (btnHeight + theme.padding)

						for i = 1, #colorBtns do
							row = math.floor((i - 1) / columns)
							x = ((i - 1) % columns) + 1
							btn = colorBtns[i]
							btn.Width = btnWidth
							btn.Height = btnHeight
							btn.pos = {
								startX + (x - 1) * (btnWidth + theme.padding),
								startY - (row * (btnHeight + theme.padding)),
							}
						end

						config.requestHeightCallback(btnHeight * rows + theme.padding * rows + categories.Height)
					end

					categoryNode:setParent(node)
					categories:parentDidResize()
					LocalEvent:Send("avatar_editor_should_focus_on_eyes")
				end
				return btn
			-- elseif index == 4 then
			-- 	local btn = ui:button({ content="✨ Ears" })
			-- 	btn:disable()
			-- 	return btn
			elseif index == 4 then
				local btn = ui:buttonNeutral({ content = "👃 Nose" })
				btn.index = index
				btns[btn.index] = btn
				btn.onRelease = function()
					if displayedCategoryIndex == index then
						return
					end
					displayedCategoryIndex = index
					refreshCategoryButtons()

					if categoryNode then
						categoryNode:remove()
					end
					categoryNode = ui:createFrame()

					local uiAvatar = require("ui_avatar")
					local btnRatio = 130 / 90
					local headMaskRatio = 190 / 130
					local size = 130

					local columns = 4
					local rows = math.floor(#avatar.noses / columns)

					local btns = {}
					for noseIndex, _ in pairs(avatar.noses) do
						-- 13 x 9
						-- 19 x 9 with ears
						local mask = ui:createFrame(Color(0, 0, 0, 0))
						mask.IsMask = true
						mask.Width = size
						mask.Height = size / btnRatio
						mask:setParent(categoryNode)
						local head = uiAvatar:getHead("", size * headMaskRatio, ui, { spherized = false })
						head:setParent(mask)

						head:setEyes({
							index = avatarProperties.eyesIndex,
							color = avatar.eyeColors[avatarProperties.eyesColorIndex],
						})

						head:setNose({ index = noseIndex })

						local colors = avatar.skinColors[avatarProperties.skinColorIndex]
						if colors == nil then
							colors = Player.Avatar:getColors()
						end
						head:setColors({
							skin1 = colors.skin1,
							skin2 = colors.skin2,
							nose = colors.nose,
							mouth = colors.mouth,
						})

						head.pos.X = mask.Width * 0.5 - head.Width * 0.5
						mask.head = head

						local btn = ui:button({
							content = mask,
							color = Color(181, 186, 193),
							padding = false,
						})
						btn.onRelease = function()
							avatarProperties.noseIndex = noseIndex
							local change = { noseIndex = noseIndex }
							avatarDidChange(change)
							LocalEvent:Send("avatar_editor_update", change)
						end
						btn:setParent(categoryNode)
						table.insert(btns, btn)
					end

					btns[1].parentDidResize = function(self)
						local maxHeight = contentMaxHeight()
						local btnMaxHeight = ((maxHeight + theme.padding) / rows) - theme.padding
						local parent = self.parent

						local btnWidth = (parent.Width - theme.padding * (columns - 1)) / columns
						local btnHeight = math.min(btnWidth * 1 / btnRatio, btnMaxHeight)
						btnWidth = btnHeight * btnRatio

						local maskWidth = btnWidth - 3 * 2 -- 3 = border
						local maskHeight = btnHeight - 3 * 2 -- 3 = border

						local totalSize = (btnWidth + theme.padding) * columns - theme.padding
						local startX = parent.Width * 0.5 - totalSize * 0.5
						local startY = (rows - 1) * (btnHeight + theme.padding)

						local row, x
						for i = 1, #btns do
							row = math.floor((i - 1) / columns)
							x = ((i - 1) % columns) + 1
							btn = btns[i]
							btn.content.Width = maskWidth
							btn.content.Height = maskHeight
							btn.content.head.Width = maskWidth * headMaskRatio
							btn.content.head.pos.X = btn.content.Width * 0.5 - btn.content.head.Width * 0.5
							btn.pos = {
								startX + (x - 1) * (btnWidth + theme.padding),
								startY - (row * (btnHeight + theme.padding)),
							}
						end

						config.requestHeightCallback(btnHeight * rows + theme.padding * rows + categories.Height)
					end

					categoryNode:setParent(node)
					categories:parentDidResize()
					LocalEvent:Send("avatar_editor_should_focus_on_nose")
				end
				return btn
			-- elseif index == 6 then
			-- 	local btn = ui:button({ content="👕 Shirt" })
			-- 	btn:disable()
			-- 	return btn
			elseif index == 5 then
				local btn = ui:buttonNeutral({ content = "👕 Jacket" })
				btn.index = index
				btns[btn.index] = btn
				btn.onRelease = function()
					if displayedCategoryIndex == index then
						return
					end
					displayedCategoryIndex = index
					refreshCategoryButtons()

					if categoryNode then
						categoryNode:remove()
					end
					categoryNode = itemGrid:create({
						categories = { "jacket", "featured" },
						perPage = ITEMS_PER_PAGE,
						uikit = ui,
						search = cache.search,
						sort = cache.sort,
						filterDidChange = filterDidChange,
						onOpen = function(entity)
							local change = { jacket = entity.fullName }
							avatarDidChange(change)
							LocalEvent:Send("avatar_editor_update", change)
						end,
					})
					categoryNode:setParent(node)
					categories:parentDidResize()

					config.requestHeightCallback(10000)
					LocalEvent:Send("avatar_editor_should_focus_on_body")
				end
				return btn
			elseif index == 6 then
				local btn = ui:buttonNeutral({ content = "👖 Pants" })
				btn.index = index
				btns[btn.index] = btn
				btn.onRelease = function()
					if displayedCategoryIndex == index then
						return
					end
					displayedCategoryIndex = index
					refreshCategoryButtons()

					if categoryNode then
						categoryNode:remove()
					end
					categoryNode = itemGrid:create({
						categories = { "pants", "featured" },
						perPage = ITEMS_PER_PAGE,
						uikit = ui,
						search = cache.search,
						sort = cache.sort,
						filterDidChange = filterDidChange,
						onOpen = function(entity)
							local change = { pants = entity.fullName }
							avatarDidChange(change)
							LocalEvent:Send("avatar_editor_update", change)
						end,
					})
					categoryNode:setParent(node)
					categories:parentDidResize()

					config.requestHeightCallback(10000)
					LocalEvent:Send("avatar_editor_should_focus_on_body")
				end
				return btn
			elseif index == 7 then
				local btn = ui:buttonNeutral({ content = "👞 Shoes" })
				btn.index = index
				btns[btn.index] = btn
				btn.onRelease = function()
					if displayedCategoryIndex == index then
						return
					end
					displayedCategoryIndex = index
					refreshCategoryButtons()

					if categoryNode then
						categoryNode:remove()
					end
					categoryNode = itemGrid:create({
						categories = { "boots", "featured" },
						perPage = ITEMS_PER_PAGE,
						uikit = ui,
						search = cache.search,
						sort = cache.sort,
						filterDidChange = filterDidChange,
						onOpen = function(entity)
							local change = { boots = entity.fullName }
							avatarDidChange(change)
							LocalEvent:Send("avatar_editor_update", change)
						end,
					})
					categoryNode:setParent(node)
					categories:parentDidResize()

					config.requestHeightCallback(10000)
					LocalEvent:Send("avatar_editor_should_focus_on_feet")
				end
				return btn
				-- elseif index == 10 then
				-- 	local btn = ui:button({ content="✨ Gloves" })
				-- 	btn:disable()
				-- 	return btn
				-- elseif index == 11 then
				-- 	local btn = ui:button({ content="🎒 Backpack" })
				-- 	btn:disable()
				-- 	return btn
			end
			return nil
		end,
		unloadCell = function(_, cell) -- index, cell
			-- 'cell' is a button here
			-- Remove the button from the collection of buttons
			btns[cell.index] = nil
			-- Remove the button from the UI hierarchy
			cell:remove()
		end,
	})

	categories.parentDidResize = function(self)
		local parent = self.parent
		categories.Width = parent.Width
		categories.Height = refButton.Height + SCROLL_PADDING * 2
		categories.pos.Y = parent.Height - categories.Height

		if categoryNode then
			categoryNode.Width = parent.Width
			categoryNode.Height = parent.Height - categories.Height - PADDING
			categoryNode.pos = { 0, 0 }

			if categoryNode.getItems then
				categoryNode:getItems()
			end
		end
	end

	categories:setParent(node)
	refreshCategoryButtons()

	setSkin()

	return node
end

return mod
