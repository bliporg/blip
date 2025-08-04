creations = {}

local loc = require("localize")

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
	functions.createNewContent = function(config)
		local newContent = modal:createContent()

		local defaultConfig = {
			what = "item",
			grid = nil, -- grid to update when done
			original = nil,
			originalCategory = nil,
			preview = nil, -- Object to preview
			data = nil,
			offsetRotation = nil,
			scale = nil,
		}
	
		local ok, err = pcall(function()
			config = require("config"):merge(defaultConfig, config, {
				acceptTypes = {
					grid = { "table" },
					original = { "string" },
					originalCategory = { "string" },
					preview = { "Object", "MutableShape", "Shape", "Mesh", "Quad" },
					data = { "Data" },
					offsetRotation = { "Rotation" },
					scale = { "number" },
				},
			})
		end)
		if not ok then
			error("creations:createNewContent(config) - config error: " .. err)
		end

		local what = config.what
		local original = config.original
		local originalCategory = config.originalCategory
		local preview = config.preview
		local data = config.data
		local offsetRotation = config.offsetRotation
		local scale = config.scale

		if what == "item" then
			if original then
				newContent.title = "Duplicate Item"
			else
				newContent.title = "New Item"
			end
		elseif what == "model" then
			newContent.title = "New 3D Model"
			-- (can't be duplicated for now)
		elseif what == "wearable" then
			if original then
				newContent.title = "Duplicate Equipment"
			else
				newContent.title = "New Equipment"
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

		local textWithEmptyInput = "Each one of your Items needs a unique name. Choose wisely, it can't be changed!"

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
			categoryShapes = { "shapes/world_map_icon" }
			buttonLabels = { "✨ Create World 🌎" }
			inputLabel = "World Name?"
			textWithEmptyInput = "A World needs a name! No pressure, you can change it later."
		elseif what == "model" then
			categories = { "null" }
			buttonLabels = { "Save" }
		end

		local currentCategory = 1

		local btnCreate
		if original == nil then
			btnCreate = ui:buttonPositive({ content = buttonLabels[1], padding = theme.padding })
		else
			btnCreate = ui:buttonPositive({ content = "✨ Duplicate 📑", padding = theme.padding })
		end
		newContent.bottomCenter = { btnCreate }

		local templatePreview
		if preview ~= nil then
			templatePreview = ui:createShape(preview, { spherized = true })
		else
			templatePreview = ui:createShape(bundle:Shape(categoryShapes[currentCategory]), { spherized = true })
		end
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

		local text = ui:createText(textWithEmptyInput, { 
			size = "small", 
			color = theme.textColor, 
			alignment = "center",
		})
		text:setParent(node)

		local input = ui:createTextInput("", inputLabel, {
			-- add margin to see text and button below
			bottomMargin = btnCreate.Height + text.Height + theme.padding * 3,
		})
		input:setParent(node)

		if #categories > 1 then
			nextTemplateBtn = ui:buttonSecondary({ content = "➡️" })
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

			previousTemplateBtn = ui:buttonSecondary({ content = "⬅️" })
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
						worldDetailsContent.onContentUpdate = function(updatedWorld)
							gridNeedRefresh = true
							worldDetailsContent.title = updatedWorld.title
							if worldDetailsContent.refreshModal then
								worldDetailsContent:refreshModal()
							end
						end

						local btnEditCode = ui:buttonSecondary({ content = "🤓 Code", textSize = "default" })
						btnEditCode.onRelease = function()
							System.EditWorldCode(world.id)
						end

						local btnEdit = ui:buttonNeutral({ content = "✏️ Edit", textSize = "default" })
						btnEdit.onRelease = function()
							System.EditWorld(world.id)
						end

						worldDetailsContent.bottomCenter = { btnEditCode, btnEdit }

						worldDetailsContent.idealReducedContentSize = function(content, width, height)
							content.Width = width
							content.Height = height
							return Number2(content.Width, content.Height)
						end

						newContent:pushAndRemoveSelf(worldDetailsContent)
					end
				end)
			else
				local itemType = "voxels"
				if what == "model" then
					itemType = "mesh"
				end

				local b64
				if data ~= nil then
					b64 = data:ToString({ format = "base64" })
				end

				local r = nil
				if offsetRotation ~= nil then
					r = { offsetRotation.X, offsetRotation.Y, offsetRotation.Z }
				end

				api:createItem({ 
					name = sanitized, 
					category = newCategory, 
					original = original, 
					type = itemType,
					data = b64,
					offsetRotation = r,
					scale = scale,
				}, function(err, item)
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
						return
					end
					
					System:DebugEvent(
						"User creates an item",
						{ 
							["item-id"] = item.id, 
							repo = item.repo, 
							name = item.name,
							type = itemType,
						}
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

					local itemDetailsContent = itemDetails:createModalContent({ 
						mode = "create", 
						uikit = ui, 
						item = cell,
					})

					local btnEdit = ui:button({ content = "✏️ Edit", textSize = "big" })
					btnEdit.onRelease = function()
						System.LaunchItemEditor(itemFullName, newCategory)
					end

					local btnDuplicate = ui:button({ content = "📑 Duplicate", textSize = "default" })
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
							m:push(functions.createNewContent({
								what = what, 
								original = itemFullName, 
								originalCategory = newCategory
							}))
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
			text.object.MaxWidth = (self.Width - theme.padding * 2)
			input.Width = self.Width

			input:setBottomMargin(btnCreate.Height + text.Height + theme.padding * 3)

			local availableHeightForPreview = self.Height
				- text.Height
				- input.Height
				- theme.padding * 3
			local availableWidthForPreview = self.Width
			if #categories > 1 then
				availableWidthForPreview = availableWidthForPreview
					- previousTemplateBtn.Width
					- nextTemplateBtn.Width
					- theme.padding * 3
			end

			local availableSizeForPreview = math.min(200, availableHeightForPreview, availableWidthForPreview)

			self.Height = availableSizeForPreview + input.Height + text.Height + theme.padding * 2

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

		newContent.willResignActive = function(self)
			templatePreview.object.Tick = nil
			templatePreview:setShape(nil)
		end

		if not Client.IsMobile then
			input:focus()
		end

		return newContent
	end

	-- step that's used to adjust scale and rotation of imported model
	functions.setupModelContent = function(what, model, data, grid)
		local content = modal:createContent()
		content.title = "New 3D Model"
		content.icon = "✨"

		local node = ui:frame()
		content.node = node

		local btnNext = ui:buttonPositive({ content = "It looks good!", padding = theme.padding })
		content.bottomCenter = { btnNext }

		local modelAndAvatar = Object()

		local callbacks = {}

		local avatarObject = require("avatar"):get({ usernameOrId = Player.UserID, didLoad = function()
			if callbacks.refreshPreview ~= nil then
				callbacks.refreshPreview()
			end
		end })

		-- adding a delay to make sure model is loaded before refreshing preview
		Timer(0.3, function()
			if callbacks.refreshPreview ~= nil then
				callbacks.refreshPreview()
			end
		end)

		-- this is used to occupy the space that's going to be taken by the model when rotating,
		-- it's basically the same bounding box with a squarified base.
		local modelCubeContainer = MutableShape()
		modelCubeContainer:AddBlock(Color(255,255,255,0.3), 0, 0, 0)
		modelCubeContainer.Pivot:Set(0.5, 0.5, 0.5)
		modelCubeContainer.IsHidden = true

		-- not all Objects have a pivot
		-- using a container to offset the model to make it work in all cases
		local modelContainer = Object()

		avatarObject:SetParent(modelAndAvatar)
		modelCubeContainer:SetParent(modelAndAvatar)
		modelContainer:SetParent(modelAndAvatar)
		
		local modelOffsetRotation = Rotation(0, 0, 0)
		local modelScale = 10 -- default scale

		callbacks.setupModel = function()
			model:SetParent(modelContainer)
			model.LocalPosition:Set(0, 0, 0)
			model.LocalRotation:Set(0, 0, 0)
			if model.Pivot ~= nil then
				model.Pivot:Set(0, 0, 0)
			end
			model.Scale = 1
			local box = Box()
			box:Fit(model, { recurse = true, localBox = true })
			model.LocalPosition:Set(-box.Center)
			modelContainer.Scale = modelScale
		end
		callbacks.setupModel()

		local preview = ui:createShape(modelAndAvatar, { spherized = false, enforceRatio = true })
		preview:setParent(node)

		callbacks.updatePositions = function()
			local box = Box()
			box:Fit(modelContainer, { recurse = true, localBox = true })
			local modelDiameter = math.sqrt(box.Size.X * box.Size.X + box.Size.Z * box.Size.Z)
			local modelRadius = modelDiameter * 0.5
			local modelHeight = box.Size.Y

			modelCubeContainer.Scale = {
				math.max(box.Size.X, box.Size.Z),
				box.Size.Y,
				math.max(box.Size.X, box.Size.Z),
			}

			box:Fit(avatarObject, { recurse = true, localBox = true})
			local avatarDiameter = math.sqrt(box.Size.X * box.Size.X + box.Size.Z * box.Size.Z)
			local avatarRadius = avatarDiameter * 0.5

			local totalWidth = modelDiameter + avatarDiameter
			
			avatarObject.LocalPosition:Set(totalWidth * 0.5 - avatarRadius, 0, 0)
			modelContainer.LocalPosition:Set(-totalWidth * 0.5 + modelRadius, modelHeight * 0.5, 0)
			modelCubeContainer.LocalPosition:Set(modelContainer.LocalPosition)
		end
		callbacks.updatePositions()

		callbacks.refreshPreview = function()
			local r = modelContainer.LocalRotation:Copy()
			modelContainer.LocalRotation:Set(modelOffsetRotation)
			callbacks.updatePositions()
			preview:refresh()
			modelContainer.LocalRotation = r
			node:refresh()
		end

		local scaleInput = ui:createTextInput(
			string.format("%.1f", modelScale),
			"", { textSize = "small", }
		)
		scaleInput:setParent(node)
		scaleInput.Width = 70

		local scaleInputLabel = ui:createText("Adjust scale for model to look as it should next to the avatar:", {
			size = "small",
			color = theme.textColor,
			alignment = "center",
		})
		scaleInputLabel:setParent(node)

		local scaleMin = 0.1
		local scaleMax = 100
		local scaleSlider = ui:slider({
			min = scaleMin,
			max = scaleMax,
			step = 0.1,
			defaultValue = modelScale,
			hapticFeedback = false,
			button = ui:buttonNeutral({ content = "  ", padding = theme.padding }),
			onValueChange = function(v)
				modelScale = v
				modelContainer.Scale = modelScale
				scaleInput.Text = string.format("%.1f", v)
				callbacks.refreshPreview()
			end,
		})
		scaleSlider:setParent(node)

		scaleInput.onSubmit = function(self)
			local oldScale = modelScale
			local newScale
			local ok = pcall(function()
				newScale = tonumber(self.Text)
			end)
			if ok and type(newScale) == "number" then
				newScale = math.max(0, newScale)
				scaleSlider:setValue(math.min(scaleMax, math.max(scaleMin, newScale)))
				modelScale = newScale
				modelContainer.Scale = modelScale
				self.Text = string.format("%.1f", modelScale)
			else
				self.Text = string.format("%.1f", oldScale)
			end
			callbacks.refreshPreview()
		end

		local rotationInputLabel = ui:createText("Adjust rotation for model to face same direction as avatar:", {
			size = "small",
			color = theme.textColor,
			alignment = "center",
		})
		rotationInputLabel:setParent(node)

		local rXSlider = ui:slider({ min = 0, max = 270, step = 90, defaultValue = 0, hapticFeedback = true,
			button = ui:buttonNeutral({ content = "X", padding = theme.padding }),
			onValueChange = function(v)
				modelOffsetRotation.X = math.rad(v)
				callbacks.refreshPreview()
			end,
		})
		rXSlider:setParent(node)

		local rYSlider = ui:slider({ min = 0, max = 270, step = 90, defaultValue = 0, hapticFeedback = true,
			button = ui:buttonNeutral({ content = "Y", padding = theme.padding }),
			onValueChange = function(v)
				modelOffsetRotation.Y = math.rad(v)
				callbacks.refreshPreview()
			end,
		})
		rYSlider:setParent(node)

		local rZSlider = ui:slider({ min = 0, max = 270, step = 90, defaultValue = 0, hapticFeedback = true,
			button = ui:buttonNeutral({ content = "Z", padding = theme.padding }),
			onValueChange = function(v)
				modelOffsetRotation.Z = math.rad(v)
				callbacks.refreshPreview()
			end,
		})
		rZSlider:setParent(node)

		node.refresh = function(self)
			local previewHeight = 200
			scaleInputLabel.object.MaxWidth = (self.Width - theme.padding * 2)
			rotationInputLabel.object.MaxWidth = (self.Width - theme.padding * 2)

			local scaleControlsHeight = math.max(scaleSlider.Height, scaleInput.Height)

			local modalPadding = theme.paddingBig
			
			self.Height = previewHeight 
			+ scaleInputLabel.Height 
			+ scaleSlider.Height 
			+ rotationInputLabel.Height 
			+ rXSlider.Height 
			+ theme.padding * 4
			+ modalPadding * 3

			local w = self.Width - modalPadding * 2

			scaleSlider.Width = w - scaleInput.Width - modalPadding

			preview.Height = previewHeight
			if preview.Width > w  then
				preview.Width = w 
			end

			rXSlider.Width = w * 0.3
			rYSlider.Width = w * 0.3
			rZSlider.Width = w * 0.3

			local y = theme.padding
			
			rXSlider.pos = { modalPadding, y }
			rYSlider.pos = { self.Width * 0.5 - rYSlider.Width * 0.5, y }
			rZSlider.pos = { self.Width - modalPadding - rZSlider.Width, y }
			y += rXSlider.Height + theme.padding

			rotationInputLabel.pos = { modalPadding, y } 
			y += rotationInputLabel.Height + theme.padding

			scaleSlider.pos = { modalPadding, y + scaleControlsHeight * 0.5 - scaleSlider.Height * 0.5 }
			scaleInput.pos = { scaleSlider.pos.X + scaleSlider.Width + theme.padding, y + scaleControlsHeight * 0.5 - scaleInput.Height * 0.5 }
			y += scaleControlsHeight + theme.padding

			scaleInputLabel.pos = { modalPadding, y }
			y += scaleInputLabel.Height + modalPadding

			preview.pos = { self.Width * 0.5 - preview.Width * 0.5, y + previewHeight * 0.5 - preview.Height * 0.5 }
		end

		content.idealReducedContentSize = function(content, width, height)
			content.Width = math.min(600, width)
			content.Height = math.min(500, height)
			content:refresh()
			return Number2(content.Width, content.Height)
		end

		content.didBecomeActive = function(self)
			callbacks.setupModel()
			callbacks.updatePositions()
			callbacks.refreshPreview()

			local r = Rotation(0, 0, 0)
			modelContainer.Tick = function(self, dt)
				r = r * Rotation(0, dt, 0)
				modelContainer.LocalRotation =  r * modelOffsetRotation
				avatarObject.LocalRotation = r
			end
		end

		content.willResignActive = function(self)
			modelContainer.Tick = nil
		end

		btnNext.onRelease = function()
			local m = content:getModalIfContentIsActive()
			if m ~= nil then
				m:push(functions.createNewContent({ 
					what = "model", 
					preview = model, 
					data = data, 
					grid = grid,
					offsetRotation = modelOffsetRotation,
					scale = modelScale,
				}))
			end
		end

		return content
	end

	functions.uploadFileForNewContent = function(what, grid)
		local newContent = modal:createContent()

		local maxFileSizeInMB = 10

		local btnUploadText = "Upload"
		local primaryText = ""
		local secondaryText = ""

		if what == "model" then
			newContent.title = "New 3D Model"
			primaryText = "Upload a .glb file to create a 3D model."
			secondaryText = "⚠️ Please ensure you have the rights to use the model you upload. Do not upload copyrighted content without permission. Content may be removed upon claim received from rightful owner of file or IP."
		else
			error("unknown file upload content type")
		end

		newContent.icon = "✨"

		local node = ui:createNode()

		local btnUpload = ui:buttonNeutral({ content = btnUploadText, padding = theme.padding })
		newContent.bottomCenter = { btnUpload }

		local loadingAnimation = require("ui_loading_animation"):create({ ui = ui })
		loadingAnimation:setParent(node)
		loadingAnimation:hide()

		local errMessage = ui:createText("Sample error message that's using\nthree\nlines.", {
			color = theme.colorNegative,
			alignment = "center",
			size = "small",
		})
		errMessage:setParent(node)
		errMessage:hide()

		local primary
		if primaryText ~= "" then
			primary = ui:createText(primaryText, {
				color = theme.textColor,
				alignment = "center",
			})
			primary:setParent(node)
		end

		local secondary
		if secondaryText ~= "" then
			secondary = ui:createText(secondaryText, {
				color = theme.textColor,
				alignment = "center",
				size = "small",
			})
			secondary:setParent(node)
		end

		local function showError(errMsg)
			errMessage.Text = errMsg
			errMessage:show()
			if primary ~= nil then primary:hide() end
			if secondary ~= nil then secondary:hide() end
			loadingAnimation:hide()
			btnUpload:enable()
			node:refresh()
		end

		local function showLoading()
			errMessage:hide()
			if primary ~= nil then primary:hide() end
			if secondary ~= nil then secondary:hide() end
			loadingAnimation:show()
			btnUpload:disable()
			node:refresh()
		end

		local function showTexts()
			if primary ~= nil then primary:show() end
			if secondary ~= nil then secondary:show() end
			errMessage:hide()
			loadingAnimation:hide()
			btnUpload:enable()
			node:refresh()
		end

		btnUpload.onRelease = function()
			btnUpload:disable()
			File:OpenAndReadAll(function(success, fileData)
				local errMsg = ""
				if success and fileData ~= nil then
					local mb = fileData.Length / 1000000
					if mb > maxFileSizeInMB then
						errMsg = string.format("File size is too large (%.2fMB).\n(max size is %dMB)", mb, maxFileSizeInMB)
					end
				end

				if errMsg ~= "" then
					showError(errMsg)
					return
				end

				if fileData == nil then
					-- no error, user cancelled file selection
					showTexts()
					return
				end
				showLoading()

				if what == "model" then
					Object:Load(fileData, function(o)
						if o == nil then
							showError("can't load model file")
							return
						end

						if typeof(o) ~= "Mesh" and typeof(o) ~= "Object" then
							showError("can't load Mesh from file")
							return
						end
						
						local m = newContent:getModalIfContentIsActive()
						if m ~= nil then
							newContent:pushAndRemoveSelf(functions.setupModelContent(what, o, fileData, grid))
						end
					end)
				else
					showError("item type not supported")
					return
				end
			end)
		end

		node._w = 300
		node._h = 300
		node._width = function(self) return self._w end
		node._height = function(self) return self._h end
		node._setWidth = function(self, v) self._w = v end
		node._setHeight = function(self, v) self._h = v end
		newContent.node = node

		node.refresh = function(self)
			self.Height = theme.padding
			errMessage.object.MaxWidth = (self.Width - theme.padding * 2)
			
			if primary ~= nil then
				primary.object.MaxWidth = (self.Width - theme.padding * 2)
				self.Height = self.Height + primary.Height + theme.padding
			end

			if secondary ~= nil then
				secondary.object.MaxWidth = (self.Width - theme.padding * 2)
				self.Height = self.Height + secondary.Height + theme.padding
			end

			self.Height = math.max(self.Height, errMessage.Height + theme.padding * 2, loadingAnimation.Height + theme.padding * 2)

			errMessage.pos = { 
				self.Width * 0.5 - errMessage.Width * 0.5,
				self.Height * 0.5 - errMessage.Height * 0.5
			}

			loadingAnimation.pos = { 
				self.Width * 0.5 - loadingAnimation.Width * 0.5,
				self.Height * 0.5 - loadingAnimation.Height * 0.5
			}
			
			local y = self.Height
			if primary ~= nil then
				y -= primary.Height + theme.padding
				primary.pos = {  self.Width * 0.5 - primary.Width * 0.5, y }
			end

			if secondary ~= nil then
				y -= secondary.Height + theme.padding
				secondary.pos = {  self.Width * 0.5 - secondary.Width * 0.5, y }
			end
		end

		newContent.idealReducedContentSize = function(content, width, height)
			content.Width = math.min(600, width)
			content.Height = math.min(500, height)
			content:refresh()
			return Number2(content.Width, content.Height)
		end

		return newContent
	end

	functions.createPickCreationTypeContent = function()
		local content = modal:createContent()
		content.title = loc("Creations")
		content.icon = "🛠️"

		local requests = {}
		local listeners = {}

		local node = ui:frame()
		content.node = node

		local label = ui:createText(loc("What do you want to create?"), { 
			alignment = "center",
			size = "default", 
			color = Color.White 
		})
		label:setParent(node)

		local texturesIcon = Object()

		local scale = 10
		local block = MutableShape()
		block.Scale = Number3( 4, 3, 0.5 ) * scale
		block.Pivot = { 0.5, 0.5, 0.5 }
		block:AddBlock(Color.White, 0, 0, 0)
		block:SetParent(texturesIcon)
		block.IsHidden = true

		local cover = 0.8

		local q1 = Quad() 
		q1.Image = Data:FromBundle("images/texture-sample-2.png")
		q1.Anchor = { 1, 0 } 
		q1.Color = Color.White
		q1.Width = block.Scale.X * cover
		q1.Height = block.Scale.Y * cover
		q1:SetParent(texturesIcon) 
		q1.LocalPosition = { 
			block.Scale.X * 0.5, 
			-block.Scale.Y * 0.5, 
			-block.Scale.Z * 0.6 
		}

		local q2 = Quad()
		q2.Image = Data:FromBundle("images/texture-sample-1.png")
		q2.Anchor = { 0, 1 } 
		q2.Color = Color.White
		q2.Width = block.Scale.X * cover
		q2.Height = block.Scale.Y * cover
		q2:SetParent(texturesIcon) 
		q2.LocalPosition = { 
			-block.Scale.X * 0.5, 
			block.Scale.Y * 0.5, 
			block.Scale.Z * 0.6 
		}

		local worldIcon = Object()
		local worldIconShape = Shape(Data:FromBundle("shapes/world_map_icon.3zh"))
		worldIconShape:SetParent(worldIcon)

		local options = {
			{
				type = "voxel-item",
				previewItem = "shapes/turnip.3zh",
				title = loc("Voxel Item"),
				description = loc("A Voxel Item is a 3D object made out of cubes."),
				callback = function()
					local m = content:getModalIfContentIsActive()
					if m ~= nil then
						m:push(functions.createNewContent( { what = "item", grid = grid }))
					end
				end,
			},
			{
				title = loc("Textured 3D Model"),
				previewItem = "shapes/small-tree.glb",
				description = loc("A 3D object with a texture applied to it. Blip only supports .glb file uploads for this category, for now."),
				comingSoon = true,
				callback = function()
					local m = content:getModalIfContentIsActive()
					if m ~= nil then
						m:push(functions.uploadFileForNewContent("model", grid))
					end
				end
			},
			{
				title = loc("Voxel Avatar Equipment"),
				previewItem = "shapes/mantle.3zh",
				description = loc("An Avatar Equipment made out of cubes (haircut, jacket, pants, boots, etc.)"),
				callback = function()
					local m = content:getModalIfContentIsActive()
					if m ~= nil then
						m:push(functions.createNewContent({ what = "wearable", grid = grid }))
					end
				end,
			},
			{
				title = loc("World"),
				previewItem = worldIcon,
				description = loc("A World is a 3D scene with logic. That's what you need to pick if you want to create a game. Templates and AI will help you get started, wether you're a coder or not."),
				callback = function()
					local m = content:getModalIfContentIsActive()
					if m ~= nil then
						m:push(functions.createNewContent({ what = "world", grid = grid}))
					end
				end,
			},
			{
				title = loc("Image"),
				description = loc("Upload an image (PNG or JPG) that can be used as a texture."),
				comingSoon = true,
				previewItem = texturesIcon,
				callback = function()
					Menu:ShowAlert({ message = "Coming soon!" }, System)
				end
			},
		}
		local nbOptions = #options

		local cells = {}

		local scroll = ui:scroll({
			direction = "down",
			backgroundColor = Color.Black,
			cellPadding = theme.padding,
			padding = theme.padding,
			loadCell = function(index, _, container)
				if index > nbOptions then
					return nil
				end
				local c = cells[index]
				if c == nil then
					c = ui:frameScrollCell()

					if options[index].callback ~= nil then
						c.onRelease = options[index].callback
					end

					cells[index] = c
					
					c.title = ui:createText(options[index].title, { 
						size = "default", 
						color = Color.White 
					})
					c.title:setParent(c)
					c.description = ui:createText(options[index].description, { 
						size = "small", 
						color = Color(200, 200, 200) 
					})
					c.description:setParent(c)

					c.iconFrame = ui:frame()
					c.iconFrame.Width = 100
					c.iconFrame.Height = 100
					c.iconFrame:setParent(c)

					if options[index].previewItem ~= nil then
						local previewItem = options[index].previewItem
						if typeof(previewItem) == "Object" then
							local s = ui:createShape(previewItem, { spherized = true })
							s:setParent(c.iconFrame)
							s.pivot.LocalRotation = { -0.1, 0, -0.2 }
							-- setting Width sets Height & Depth as well when spherized
							s.Width = c.iconFrame.Width * 1.1
							s.pos = { -c.iconFrame.Width * 0.05, -c.iconFrame.Height * 0.05 }
							c.rotatingIcon = s
						else
							local req = Object:Load(Data:FromBundle(previewItem), function(o)
								local s = ui:createShape(o, { spherized = true })
								s:setParent(c.iconFrame)
								s.pivot.LocalRotation = { -0.1, 0, -0.2 }
								-- setting Width sets Height & Depth as well when spherized
								s.Width = c.iconFrame.Width * 1.1
								s.pos = { -c.iconFrame.Width * 0.05, -c.iconFrame.Height * 0.05 }
								c.rotatingIcon = s
							end)
							table.insert(requests, req)
						end
					end
				end

				local padding = theme.paddingBig

				c.Width = container.Width
				c.description.object.MaxWidth = c.Width - c.iconFrame.Width - padding * 3
				c.title.object.MaxWidth = c.Width - c.iconFrame.Width - padding * 3
				c.Height = math.max(c.iconFrame.Height, c.title.Height + c.description.Height + padding) + padding * 2

				c.iconFrame.pos = { padding, c.Height - c.iconFrame.Height - padding }
				c.title.pos = { c.iconFrame.pos.X + c.iconFrame.Width + padding, c.Height - c.title.Height - padding }
				c.description.pos = { c.iconFrame.pos.X + c.iconFrame.Width + padding, c.title.pos.Y - c.description.Height - padding }

				return c
			end,
			unloadCell = function(_, c)
				c:setParent(nil)
			end,
		})

		scroll:setParent(node)

		node.refresh = function(self)
			label.object.MaxWidth = self.Width - theme.padding * 2
			scroll.Width = self.Width
			scroll.Height = self.Height - label.Height - theme.padding
			label.pos = { self.Width * 0.5 - label.Width * 0.5, self.Height - label.Height }
			scroll:flush()
			scroll:refresh()
		end

		content.idealReducedContentSize = function(content, width, height)
			content.Width = width
			content.Height = height
			content:refresh()
			return Number2(content.Width, content.Height)
		end

		local l = LocalEvent:Listen(LocalEvent.Name.Tick, function(dt)
			for _, c in cells do
				if c.rotatingIcon then
					c.rotatingIcon.pivot.LocalRotation.Y += dt * 2
				end
			end
		end)
		table.insert(listeners, l)

		content.willResignActive = function()
			for _, l in listeners do
				l:pause()
			end
		end

		content.didBecomeActive = function()
			for _, l in listeners do
				l:resume()
			end
		end

		return content
	end

	local createCreationsContent = function()
		local creationsContent = modal:createContent()
		if config.title ~= nil then
			creationsContent.title = config.title
		elseif config.authorId == Player.UserID then
			creationsContent.title = loc("Creations")
		else
			creationsContent.title = config.authorName .. "'s Creations"
		end
		creationsContent.icon = "🛠️"

		local node = ui:frame()

		local grid = itemGrid:create({
			minBlocks = 1,
			type = "all",
			displayLikes = true,
			repo = config.authorName,
			authorId = config.authorId,
			categories = { "null" },
			sort = "updatedAt:desc",
			uikit = ui,
		})
		grid:setParent(node)

		local btnCreate

		if config.authorId == Player.UserID then
			btnCreate = ui:buttonPositive({ 
				content = loc("Create"), 
				textSize = "big", 
				padding = {
					top = theme.padding,
					bottom = theme.padding,
					left = theme.paddingBig,
					right = theme.paddingBig,
				}
			})
			btnCreate:setParent(node)
		end

		node.parentDidResize = function(self)
			if btnCreate then
				grid.Width = self.Width
				grid.Height = self.Height - btnCreate.Height - theme.padding
				grid.pos.Y = btnCreate.Height + theme.padding
				btnCreate.pos = { self.Width * 0.5 - btnCreate.Width * 0.5, 0 }
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

		local newPickCreationType = function()
			local m = creationsContent:getModalIfContentIsActive()
			if m ~= nil then
				m:push(functions.createPickCreationTypeContent())
			end
		end

		if btnCreate then btnCreate.onRelease = newPickCreationType end

		creationsContent.tabs = {}

		if #creationsContent.tabs > 0 then
			creationsContent.tabs[1].action()
		end

		if #creationsContent.tabs == 1 then
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
							m:push(functions.createNewContent({ 
								what = what, 
								original = itemFullName, 
								grid = grid, 
								originalCategory = category 
							}))
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
					-- archive button
					local btnArchive = ui:buttonSecondary({ content = "🗑️", textSize = "default" })
					btnArchive.onRelease = function()
						local str = "Are you sure you want to archive this world?"
						local positive = function()
							local data = { archived = true }
							api:patchWorld(entity.id, data, function(err, world)
								if err or not world.archived then
									Menu:ShowAlert({ message = "Could not archive world" }, System)
									return
								end
								worldDetailsContent:pop()
								grid:getItems()
							end)
							-- TODO: gaetan: add this to httpRequests and cancel it when changing scene
							-- table.insert(httpRequests, req)
						end
						local alertConfig = {
							message = str,
							positiveLabel = "Yes",
							positiveCallback = positive,
							negativeLabel = "No",
							negativeCallback = function() end,
						}
						Menu:ShowAlert(alertConfig, System)
					end

					local btnEditCode = ui:buttonSecondary({ content = "🤓 Code", textSize = "default" })
					btnEditCode.onRelease = function()
						System.EditWorldCode(entity.id)
					end

					local btnEdit = ui:buttonNeutral({ content = "✏️ Edit", textSize = "default" })
					btnEdit.onRelease = function()
						System.EditWorld(entity.id)
					end

					worldDetailsContent.bottomLeft = { btnArchive }
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
