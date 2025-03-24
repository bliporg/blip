creations = {}

creations.createModalContent = function(_, config)
	local itemGrid = require("item_grid")
	local itemDetails = require("item_details")
	local worldDetails = require("world_details")
	local theme = require("uitheme").current
	local modal = require("modal")
	local bundle = require("bundle")
	local api = require("system_api", System)
	local gridNeedRefresh = false

	-- default config
	local defaultConfig = {
		uikit = require("uikit"), -- allows to provide specific instance of uikit
		onOpen = nil,
		authorId = Player.UserID,
		authorName = Player.Username,
		title = nil,
		categories = { "items", "wearables", "worlds" },
	}

	local ok, err = pcall(function()
		config = require("config"):merge(defaultConfig, config, {
			acceptTypes = {
				onOpen = { "function" },
				title = { "string" },
			},
		})
	end)
	if not ok then
		error("creations:createModalContent(config) - config error: " .. err, 2)
	end

	local ui = config.uikit

	local functions = {}

	-- if original isn't nil, it means we're duplicating an entity
	-- original: name of copied entity
	-- grid parameter is used to force content reload after item creation
	functions.createNewContent = function(what, original, grid, originalCategory)
		local newContent = modal:createContent()

		if what == "item" or what == "wearable" then
			if original then
				newContent.title = "Duplicate Item"
			else
				newContent.title = "New Item"
			end
		else
			newContent.title = "New World"
		end

		newContent.icon = "✨"

		local node = ui:createNode()

		local categories = { "null" }
		local categoryShapes = { "shapes/one_cube_template" }
		local buttonLabels = { "✨ Create Item ⚔️" }
		local inputLabel = "Item Name?"

		local textWithEmptyInput =
			"An Item needs a name, coders will use it as a reference within world scripts. Choose wisely, it cannot be changed!"

		if what == "wearable" and original == nil then
			categories = { "hair", "jacket", "pants", "boots" }
			categoryShapes = {
				"shapes/hair_template",
				"shapes/jacket_template",
				"shapes/pants_template",
				"shapes/shoes_template",
			}
			buttonLabels = {
				"✨ Create Hair 🙂",
				"✨ Create Jacket 👕",
				"✨ Create Pants 👖",
				"✨ Create Shoes 👞",
			}
		elseif what == "world" then
			categories = { "null" }
			categoryShapes = { "shapes/world_icon" }
			buttonLabels = { "✨ Create World 🌎" }
			inputLabel = "World Name?"
			textWithEmptyInput = "A World needs a name! No pressure, this can be changed later on."
		end

		local currentCategory = 1

		local btnCreate
		if original == nil then
			btnCreate = ui:buttonPositive({ content = buttonLabels[1], padding = theme.padding })
		else
			btnCreate = ui:buttonPositive({ content = "✨ Duplicate 📑", padding = theme.padding })
		end
		newContent.bottomCenter = { btnCreate }

		local templatePreview = ui:createShape(bundle:Shape(categoryShapes[currentCategory]), { spherized = true })
		templatePreview:setParent(node)

		templatePreview.pivot.LocalRotation = { -0.1, 0, -0.2 }
		templatePreview.object.dt = 0
		templatePreview.object.Tick = function(o, dt)
			o.dt = o.dt + dt
			if templatePreview.pivot ~= nil then
				templatePreview.pivot.LocalRotation = { -0.1, o.dt, -0.2 }
			end
		end

		if original then
			Object:Load(original, function(shape)
				if shape and templatePreview.setShape then
					templatePreview:setShape(shape)
				end
			end)
		end

		local nextTemplateBtn
		local previousTemplateBtn

		local input = ui:createTextInput("", inputLabel)
		input:setParent(node)

		local text = ui:createText(textWithEmptyInput, theme.textColor)
		text:setParent(node)

		if #categories > 1 then
			nextTemplateBtn = ui:buttonNeutral({ content = "➡️" })
			nextTemplateBtn:setParent(node)
			nextTemplateBtn.onRelease = function()
				currentCategory = currentCategory + 1
				if currentCategory > #categories then
					currentCategory = 1
				end
				local label = buttonLabels[currentCategory]
				btnCreate.Text = label

				text.Text = textWithEmptyInput
				text.Color = theme.textColor
				text.pos = { node.Width * 0.5 - text.Width * 0.5, input.pos.Y - text.Height - theme.paddingBig, 0 }

				templatePreview:setShape(bundle:Shape(categoryShapes[currentCategory]))
			end

			previousTemplateBtn = ui:buttonNeutral({ content = "⬅️" })
			previousTemplateBtn:setParent(node)
			previousTemplateBtn.onRelease = function()
				currentCategory = currentCategory - 1
				if currentCategory < 1 then
					currentCategory = #categories
				end
				local label = buttonLabels[currentCategory]
				btnCreate.Text = label

				text.Text = textWithEmptyInput
				text.Color = theme.textColor
				text.pos = { node.Width * 0.5 - text.Width * 0.5, input.pos.Y - text.Height - theme.paddingBig, 0 }

				templatePreview:setShape(bundle:Shape(categoryShapes[currentCategory]))
			end
		end

		btnCreate.onRelease = function()
			local sanitized
			local err

			if what == "world" then
				sanitized, err = api.checkWorldName(input.Text)
				if err ~= nil then
					text.Text = "❌ " .. err
					text.Color = theme.colorNegative
					text.pos = { node.Width * 0.5 - text.Width * 0.5, input.pos.Y - text.Height - theme.paddingBig, 0 }
					return
				end
			else
				sanitized, err = api.checkItemName(input.Text)
				if err ~= nil then
					text.Text = "❌ " .. err
					text.Color = theme.colorNegative
					text.pos = { node.Width * 0.5 - text.Width * 0.5, input.pos.Y - text.Height - theme.paddingBig, 0 }
					return
				end
			end

			btnCreate:disable()
			input:disable()

			text.Text = "Creating..."
			text.Color = theme.textColor
			text.pos = { node.Width * 0.5 - text.Width * 0.5, input.pos.Y - text.Height - theme.paddingBig, 0 }

			local newCategory = categories[currentCategory]
			if originalCategory then
				newCategory = originalCategory
			end
			if newCategory == "null" then
				newCategory = nil
			end

			if what == "world" then
				api:createWorld({ title = sanitized, category = newCategory, original = original }, function(err, world)
					if err ~= nil then
						text.Text = "❌ Sorry, there's been an error."
						text.Color = theme.colorNegative
						text.pos =
							{ node.Width * 0.5 - text.Width * 0.5, input.pos.Y - text.Height - theme.paddingBig, 0 }

						btnCreate:enable()
						input:enable()
					else
						System:DebugEvent("User creates a world", { ["world-id"] = world.id, title = world.title })

						-- forces grid to refresh when coming back
						if grid ~= nil then
							grid.needsToRefreshEntries = true
						end

						local worldDetailsContent = worldDetails:createModalContent({
							mode = "create",
							world = world,
							uikit = ui,
						})

						local btnEditCode = ui:buttonNeutral({ content = "🤓 Code", textSize = "default" })
						btnEditCode.onRelease = function()
							System.EditWorldCode(world.id)
						end

						local btnEdit = ui:buttonNeutral({ content = "✏️ Edit", textSize = "big" })
						btnEdit.onRelease = function()
							System.EditWorld(world.id)
						end

						worldDetailsContent.bottomRight = { btnEdit, btnEditCode }

						worldDetailsContent.idealReducedContentSize = function(content, width, height)
							content.Width = width
							content.Height = height
							return Number2(content.Width, content.Height)
						end

						newContent:pushAndRemoveSelf(worldDetailsContent)
					end
				end)
			else
				api:createItem({ name = sanitized, category = newCategory, original = original }, function(err, item)
					if err ~= nil then
						if err.statusCode == 409 then
							text.Text = "❌ You already have an item with that name!"
						else
							-- print(err.message, err.statusCode)
							text.Text = "❌ Sorry, there's been an error."
						end
						text.Color = theme.colorNegative
						text.pos =
							{ node.Width * 0.5 - text.Width * 0.5, input.pos.Y - text.Height - theme.paddingBig, 0 }

						btnCreate:enable()
						input:enable()
					else
						System:DebugEvent(
							"User creates an item",
							{ ["item-id"] = item.id, repo = item.repo, name = item.name }
						)

						-- forces grid to refresh when coming back
						if grid ~= nil then
							grid.needsToRefreshEntries = true
						end

						local itemFullName = item.repo .. "." .. item.name
						-- local category = cell.category

						local cell = {}
						cell.id = item.id
						cell.name = item.name
						cell.repo = item.repo
						cell.description = ""
						cell.fullName = itemFullName
						cell.created = item.created

						local itemDetailsContent =
							itemDetails:createModalContent({ mode = "create", uikit = ui, item = cell })

						local btnEdit = ui:button({ content="✏️ Edit", textSize = "big" })
						btnEdit.onRelease = function()
							System.LaunchItemEditor(itemFullName, newCategory)
						end

						local btnDuplicate = ui:button({ content="📑 Duplicate", textSize = "default" })
						btnDuplicate.onRelease = function()
							-- no need to pass grid, it's already marked
							-- for refresh at this point
							local m = itemDetailsContent:getModalIfContentIsActive()
							if m ~= nil then
								local what
								if newCategory == nil then
									what = "item"
								else
									what = "wearable"
								end
								m:push(functions.createNewContent(what, itemFullName, nil, newCategory))
							end
						end

						-- itemDetailsContent.bottomCenter = {btnDuplicate, btnEdit}
						itemDetailsContent.bottomRight = { btnEdit }
						itemDetailsContent.bottomLeft = { btnDuplicate }

						itemDetailsContent.idealReducedContentSize = function(content, width, height)
							content.Width = width
							content.Height = height
							return Number2(content.Width, content.Height)
						end

						newContent:pushAndRemoveSelf(itemDetailsContent)
					end
				end) -- api:createItem
			end -- end if world/item
		end

		input.onTextChange = function(self)
			local name = self.Text

			if name == "" then
				text.Text = textWithEmptyInput
				text.Color = theme.textColor
			else
				if what == "world" then
					local sanitized, err = api.checkWorldName(name)
					if err ~= nil then
						text.Text = "❌ " .. err
						text.Color = theme.colorNegative
					else
						text.Text = "✅ " .. sanitized
						text.Color = theme.colorPositive
					end
				else
					local slug, err = api.checkItemName(name, Player.Username)
					if err ~= nil then
						text.Text = "❌ " .. err
						text.Color = theme.colorNegative
					else
						text.Text = "✅ " .. slug
						text.Color = theme.colorPositive
					end
				end
			end
			text.pos = { node.Width * 0.5 - text.Width * 0.5, input.pos.Y - text.Height - theme.paddingBig, 0 }
		end

		node._w = 300
		node._h = 300
		node._width = function(self)
			return self._w
		end
		node._height = function(self)
			return self._h
		end

		node._setWidth = function(self, v)
			self._w = v
		end
		node._setHeight = function(self, v)
			self._h = v
		end

		newContent.node = node

		node.refresh = function(self)
			local extraBottomPadding = input.Height
			text.object.MaxWidth = (self.Width - theme.padding * 2)
			input.Width = self.Width

			local availableHeightForPreview = self.Height
				- text.Height
				- input.Height
				- theme.padding * 2
				- extraBottomPadding
			local availableWidthForPreview = self.Width
			if #categories > 1 then
				availableWidthForPreview = availableWidthForPreview
					- previousTemplateBtn.Width
					- nextTemplateBtn.Width
					- theme.padding * 2
			end

			local availableSizeForPreview = math.min(200, availableHeightForPreview, availableWidthForPreview)

			self.Height = availableSizeForPreview + input.Height + text.Height + theme.padding * 2 + extraBottomPadding

			templatePreview.Height = availableSizeForPreview
			templatePreview.pos =
				{ self.Width * 0.5 - templatePreview.Width * 0.5, self.Height - templatePreview.Height, 0 }
			if #categories > 1 then
				previousTemplateBtn.Height = templatePreview.Height
				nextTemplateBtn.Height = templatePreview.Height

				previousTemplateBtn.pos = { 0, self.Height - templatePreview.Height, 0 }
				nextTemplateBtn.pos =
					{ self.Width - previousTemplateBtn.Width, self.Height - templatePreview.Height, 0 }
			end

			input.pos =
				{ self.Width * 0.5 - input.Width * 0.5, templatePreview.pos.Y - input.Height - theme.padding, 0 }
			text.pos = { self.Width * 0.5 - text.Width * 0.5, input.pos.Y - text.Height - theme.paddingBig, 0 }
		end

		newContent.idealReducedContentSize = function(content, width, height)
			content.Width = math.min(600, width)
			content.Height = math.min(500, height)
			content:refresh()
			return Number2(content.Width, content.Height)
		end

		input:focus()

		return newContent
	end

	local createCreationsContent = function()
		local creationsContent = modal:createContent()
		if config.title ~= nil then
			creationsContent.title = config.title
		elseif config.authorId == Player.UserID then
			creationsContent.title = "Creations"
		else
			creationsContent.title = config.authorName .. "'s Creations"
		end
		creationsContent.icon = "🏗️"

		local node = ui:frame()

		local grid = itemGrid:create({
			minBlocks = 1,
			type = "items",
			displayLikes = true,
			repo = config.authorName,
			authorId = config.authorId,
			categories = { "null" },
			sort = "updatedAt:desc",
			uikit = ui,
		})
		grid:setParent(node)

		local btnNew
		if config.authorId == Player.UserID then
			btnNew = ui:buttonPositive({ content = "✨ Create item ⚔️", padding = theme.padding })
			btnNew:setParent(node)
		end

		node.parentDidResize = function(self)
			if btnNew then
				grid.Width = self.Width
				grid.Height = self.Height - btnNew.Height - theme.padding
				grid.pos.Y = btnNew.Height + theme.padding
				btnNew.pos = { self.Width * 0.5 - btnNew.Width * 0.5, 0 }
			else
				grid.Width = self.Width
				grid.Height = self.Height
				grid.pos.Y = 0
			end
		end

		creationsContent.willResignActive = function(_)
			grid:cancelRequestsAndTimers()
		end

		creationsContent.didBecomeActive = function(_)
			if gridNeedRefresh then
				-- re-download grid content
				if grid.getItems then
					grid:getItems()
				end
				gridNeedRefresh = false
			else
				-- simply display the grid (same content)
				if grid.refresh then
					grid:refresh()
				end
			end
		end

		local newItem = function()
			local m = creationsContent:getModalIfContentIsActive()
			if m ~= nil then
				m:push(functions.createNewContent("item", nil, grid))
			end
		end

		local newWearable = function()
			local m = creationsContent:getModalIfContentIsActive()
			if m ~= nil then
				m:push(functions.createNewContent("wearable", nil, grid))
			end
		end

		local newWorld = function()
			local m = creationsContent:getModalIfContentIsActive()
			if m ~= nil then
				m:push(functions.createNewContent("world", nil, grid))
			end
		end

		if btnNew then
			btnNew.onRelease = newItem
		end

		creationsContent.tabs = {}

		for _, category in ipairs(config.categories) do
			if category == "items" then
				table.insert(creationsContent.tabs, {
					label = "⚔️ Items",
					short = "⚔️",
					action = function()
						grid:setCategories({ "null" }, "items")
						if btnNew then
							btnNew.Text = "✨ Create item ⚔️"
							btnNew.pos.X = btnNew.parent.Width * 0.5 - btnNew.Width * 0.5
							btnNew.onRelease = newItem
						end
					end,
				})
			elseif category == "wearables" then
				table.insert(creationsContent.tabs, {
					label = "👕 Wearables",
					short = "👕",
					action = function()
						grid:setCategories({ "hair", "jacket", "pants", "boots" }, "items")
						if btnNew then
							btnNew.Text = "✨ Create wearable 👕"
							btnNew.pos.X = btnNew.parent.Width * 0.5 - btnNew.Width * 0.5
							btnNew.onRelease = newWearable
						end
					end,
				})
			elseif category == "worlds" then
				table.insert(creationsContent.tabs, {
					label = "🌎 Worlds",
					short = "🌎",
					action = function()
						grid:setCategories({ "null" }, "worlds")
						if btnNew then
							btnNew.Text = "✨ Create world 🌎"
							btnNew.pos.X = btnNew.parent.Width * 0.5 - btnNew.Width * 0.5
							btnNew.onRelease = newWorld
						end
					end,
				})
			end
		end

		if #creationsContent.tabs > 0 then
			creationsContent.tabs[1].action()
		end

		if  #creationsContent.tabs == 1 then
			creationsContent.tabs = {}
		end

		creationsContent.node = node

		grid.onOpen = function(entity)
			if config.onOpen then
				config.onOpen(creationsContent, entity)
				return
			end

			if entity.type == "item" then
				local itemFullName = entity.repo .. "." .. entity.name
				local category = entity.category

				local mode = config.authorId == Player.UserID and "create" or "explore"

				local itemDetailsContent = itemDetails:createModalContent({ item = entity, mode = mode, uikit = ui })

				if mode == "create" then
					local btnEdit = ui:buttonNeutral({ content = "✏️ Edit", textSize = "default" })
					btnEdit.onRelease = function()
						System.LaunchItemEditor(itemFullName, category)
					end

					local btnDuplicate = ui:buttonSecondary({ content = "📑 Duplicate", textSize = "default" })
					btnDuplicate.onRelease = function()
						local m = itemDetailsContent:getModalIfContentIsActive()
						if m ~= nil then
							local what
							if category == nil then
								what = "item"
							else
								what = "wearable"
							end
							m:push(functions.createNewContent(what, itemFullName, grid, category))
						end
					end

					local btnExport = ui:buttonSecondary({ content = "📤", textSize = "default" })
					btnExport.onRelease = function()
						File:ExportItem(entity.repo, entity.name, "vox", function(err, message)
							if err then
								print("Error: " .. message)
								return
							end
						end)
					end

					local btnArchive = ui:buttonSecondary({ content = "🗑️", textSize = "default" })
					btnArchive.onRelease = function()
						local str = "Are you sure you want to archive this item?"
						local positive = function()
							local data = { archived = true }
							api:patchItem(entity.id, data, function(err, itm)
								if err or not itm.archived then
									Menu:ShowAlert({ message = "Could not archive item" }, System)
									return
								end
								itemDetailsContent:pop()
								grid:getItems()
							end)
						end
						local negative = function() end
						local alertConfig = {
							message = str,
							positiveLabel = "Yes",
							positiveCallback = positive,
							negativeLabel = "No",
							negativeCallback = negative,
						}

						Menu:ShowAlert(alertConfig, System)
					end

					itemDetailsContent.bottomLeft = { btnDuplicate, btnExport, btnArchive }
					itemDetailsContent.bottomRight = { btnEdit }
				end

				itemDetailsContent.idealReducedContentSize = function(content, width, height)
					content.Width = width
					content.Height = height
					return Number2(content.Width, content.Height)
				end

				local m = creationsContent:getModalIfContentIsActive()
				if m ~= nil then
					m:push(itemDetailsContent)
				end
			elseif entity.type == "world" then
				local mode = config.authorId == Player.UserID and "create" or "explore"

				local worldDetailsContent = worldDetails:createModalContent({ mode = mode, world = entity, uikit = ui })
				worldDetailsContent.onContentUpdate = function(updatedWorld)
					gridNeedRefresh = true
					worldDetailsContent.title = updatedWorld.title
					if worldDetailsContent.refreshModal then
						worldDetailsContent:refreshModal()
					end
				end

				if mode == "create" then
					local btnEditCode = ui:buttonSecondary({ content = "🤓 Code", textSize = "default" })
					btnEditCode.onRelease = function()
						System.EditWorldCode(entity.id)
					end

					local btnEdit = ui:buttonNeutral({ content = "✏️ Edit", textSize = "default" })
					btnEdit.onRelease = function()
						System.EditWorld(entity.id)
					end

					worldDetailsContent.bottomRight = { btnEdit, btnEditCode }
				end

				worldDetailsContent.idealReducedContentSize = function(content, width, height)
					content.Width = width
					content.Height = height
					return Number2(content.Width, content.Height)
				end

				local m = creationsContent:getModalIfContentIsActive()
				if m ~= nil then
					m:push(worldDetailsContent)
				end
			end
		end

		return creationsContent
	end

	return createCreationsContent()
end

creations.createModal = function(_, config)
	local modal = require("modal")
	local ui = config.ui or require("uikit")
	local ease = require("ease")
	local theme = require("uitheme").current
	local MODAL_MARGIN = theme.paddingBig -- space around modals

	-- TODO: handle this correctly
	local topBarHeight = 50

	local content = modal:createContent()

	local creationsContent = creations:createModalContent({
		uikit = ui,
		onOpen = config.onOpen,
		categories = config.categories,
		title = config.title,
	})

	creationsContent.idealReducedContentSize = function(content, width, height)
		local grid = content
		grid.Width = width
		grid.Height = height -- - content.pages.Height - theme.padding
		--grid:refresh() -- affects width and height (possibly reducing it)
		return Number2(grid.Width, grid.Height)
	end

	function maxModalWidth()
		local computed = Screen.Width - Screen.SafeArea.Left - Screen.SafeArea.Right - MODAL_MARGIN * 2
		local max = Screen.Width * 0.8
		local w = math.min(max, computed)
		return w
	end

	function maxModalHeight()
		return (Screen.Height - Screen.SafeArea.Bottom - topBarHeight - MODAL_MARGIN * 2) * 0.95
	end

	function updateModalPosition(modal, forceBounce)
		local vMin = Screen.SafeArea.Bottom + MODAL_MARGIN
		local vMax = Screen.Height - topBarHeight - MODAL_MARGIN

		local vCenter = vMin + (vMax - vMin) * 0.5

		local p = Number3(Screen.Width * 0.5 - modal.Width * 0.5, vCenter - modal.Height * 0.5, 0)

		if not modal.updatedPosition or forceBounce then
			modal.LocalPosition = p - { 0, 100, 0 }
			modal.updatedPosition = true
			ease:cancel(modal) -- cancel modal ease animations if any
			ease:outBack(modal, 0.22).LocalPosition = p
		else
			modal.LocalPosition = p
		end
	end

	local currentModal = modal:create(content, maxModalWidth, maxModalHeight, updateModalPosition, ui)

	content:pushAndRemoveSelf(creationsContent)

	return currentModal, creationsContent
end

return creations
