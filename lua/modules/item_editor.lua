-- TODO:
-- [ ] fix wearable edition
-- [ ] fix palette display
-- [ ] fix orientation cube display

Config = {
	Items = { "%item_name%" },
	ChatAvailable = false,
}

-- --------------------------------------------------
-- Utilities for Player avatar
-- --------------------------------------------------

local debug = {}
debug.logSubshapes = function(_, shape, level)
	if level == nil then
		level = 0
	end
	local logIndent = ""
	for i = 1, level do
		logIndent = logIndent .. " |"
	end

	if shape == nil then
		print("[debug.logSubshapes]", "shape is nil")
		return
	end

	print("[debug.logSubshapes]", logIndent, shape)

	local count = shape.ChildrenCount
	for i = 1, count do
		local subshape = shape:GetChild(i)
		debug:logSubshapes(subshape, level + 1)
	end
end

blocksToRemove = {}

local utils = {}

bodyParts = {
	"Head",
	"Body",
	"RightArm",
	"LeftArm",
	"RightHand",
	"LeftHand",
	"RightLeg",
	"LeftLeg",
	"RightFoot",
	"LeftFoot",
}

bodyPartToWearablePart = {}
bodyPartsBasePositions = {}

utils.equipmentParents = function(_, player, itemCategory)
	local parts = {
		hair = player.Head,
		jacket = { player.Body, player.RightArm, player.LeftArm },
		pants = { player.RightLeg, player.LeftLeg },
		boots = { player.RightFoot, player.LeftFoot },
	}
	return parts[itemCategory]
end

-- returns an array of shapes
-- `testFunc` is a function(shape) -> boolean
utils.findSubshapes = function(rootShape, testFunc)
	if typeof(rootShape) ~= "Shape" and typeof(rootShape) ~= "MutableShape" and type(testFunc) ~= "function" then
		error("wrong arguments")
	end

	local matchingShapes = {}
	local shapesToProcess = { rootShape }

	while #shapesToProcess > 0 do
		local s = table.remove(shapesToProcess, #shapesToProcess)
		-- process shape
		if testFunc(s) == true then
			table.insert(matchingShapes, s)
		end

		-- explore subshapes
		local count = s.ChildrenCount
		for i = 1, count do
			local subshape = s:GetChild(i)
			table.insert(shapesToProcess, subshape)
		end
	end

	return matchingShapes
end

local disableObject = function(object, v)
	if object.IsHiddenSelf ~= nil then
		object.IsHiddenSelf = v
	end
	object.Physics = v and PhysicsMode.Disabled or PhysicsMode.TriggerPerBlock
end

local playerHideSubshapes = function(isHidden)
	local bodyParts = {
		Player.Avatar.Head,
		Player.Avatar.Body,
		Player.Avatar.LeftArm,
		Player.Avatar.LeftHand,
		Player.Avatar.RightArm,
		Player.Avatar.RightHand,
		Player.Avatar.LeftLeg,
		Player.Avatar.LeftFoot,
		Player.Avatar.RightLeg,
		Player.Avatar.RightFoot,
	}
	for _, bodyPart in ipairs(bodyParts) do
		bodyPart:Recurse(function(o)
			o.PrivateDrawMode = 0
			disableObject(o, isHidden)
		end, { includeRoot = true })
	end
end

local playerUpdateVisibility = function(p_isWearable, p_wearablePreviewMode)
	if type(p_isWearable) ~= "boolean" or type(p_wearablePreviewMode) ~= "number" then
		error("wrong arguments")
	end

	if not p_isWearable then
		-- item is not a wearable, so the player avatar should not be visible
		playerHideSubshapes(true)
		return
	end

	if p_wearablePreviewMode == wearablePreviewMode.fullBody then
		playerHideSubshapes(false)
		return
	end

	playerHideSubshapes(true)

	-- item is a wearable, we set the avatar visibility based on `p_wearablePreviewMode`
	if p_wearablePreviewMode == wearablePreviewMode.hide then
		local parents = utils:equipmentParents(Player, itemCategory)
		local parentsType = typeof(parents)
		if parentsType == "table" then
			for _, parent in ipairs(parents) do
				parent.PrivateDrawMode = 1
				disableObject(parent, false)
			end
		elseif parentsType == "MutableShape" then
			parents.PrivateDrawMode = 1
			disableObject(parents, false)
		else
			error("unexpected 'parents' type:", parentsType)
		end
	elseif p_wearablePreviewMode == wearablePreviewMode.bodyPart then
		-- show some of the avatar body parts based on the type of wearable being edited
		local parents = utils:equipmentParents(Player, itemCategory)
		local parentsType = typeof(parents)
		if parentsType == "table" then
			for _, parent in ipairs(parents) do
				disableObject(parent, false)
			end
		elseif parentsType == "MutableShape" then
			disableObject(parents, false)
		else
			error("unexpected 'parents' type:", parentsType)
		end
	end
end

Client.OnStart = function()
	gizmo = require("gizmo")
	gizmo:setLayer(4)
	gizmo:setScale(0.3)

	bundle = require("bundle")

	box_outline = require("box_outline")
	ui = require("uikit")
	theme = require("uitheme").current

	max_total_nb_shapes = 32

	colliderMinGizmo = gizmo:create({
		orientation = gizmo.Orientation.World,
		moveSnap = 0.5,
		onMove = function()
			local axis = { "X", "Y", "Z" }
			for _, a in ipairs(axis) do
				if colliderMinObject.Position[a] >= colliderMaxObject.Position[a] then
					colliderMinObject.Position[a] = colliderMaxObject.Position[a] - 0.5
				end
			end
			colliderMinGizmo:setObject(colliderMinObject)
			updateCollider()
		end,
	})

	colliderMaxGizmo = gizmo:create({
		orientation = gizmo.Orientation.World,
		moveSnap = 0.5,
		onMove = function()
			local axis = { "X", "Y", "Z" }
			for _, a in ipairs(axis) do
				if colliderMaxObject.Position[a] <= colliderMinObject.Position[a] then
					colliderMaxObject.Position[a] = colliderMinObject.Position[a] + 0.5
				end
			end
			colliderMaxGizmo:setObject(colliderMaxObject)
			updateCollider()
		end,
	})

	colorPickerModule = require("colorpicker")

	-- Displays the right tools based on state
	refreshToolsDisplay = function()
		local enablePaletteBtn = currentMode == mode.edit
			and (
				currentEditSubmode == editSubmode.add
				or currentEditSubmode == editSubmode.remove
				or currentEditSubmode == editSubmode.paint
			)

		local showPalette = currentMode == mode.edit
			and paletteDisplayed
			and (
				currentEditSubmode == editSubmode.add
				or currentEditSubmode == editSubmode.remove
				or currentEditSubmode == editSubmode.paint
			)

		local showColorPicker = showPalette and colorPickerDisplayed
		local showMirrorControls = currentMode == mode.edit and currentEditSubmode == editSubmode.mirror

		local showSelectControls = currentMode == mode.edit and currentEditSubmode == editSubmode.select

		if enablePaletteBtn then
			paletteBtn:enable()
		else
			paletteBtn:disable()
		end

		if showPalette then
			updatePalettePosition()
			palette:show()
		else
			palette:hide()
		end
		if showColorPicker then
			colorPicker:show()
		else
			colorPicker:hide()
		end
		if showSelectControls then
			selectControlsRefresh()
			selectControls:show()
		else
			selectControls:hide()
		end

		if showMirrorControls then
			mirrorControls:show()
			if not mirrorShape then
				mirrorGizmo:setObject(nil)
				placeMirrorText:show()
				rotateMirrorBtn:hide()
				removeMirrorBtn:hide()
				mirrorControls.Width = placeMirrorText.Width + ui_config.padding * 2
			else
				mirrorGizmo:setObject(mirrorAnchor)
				placeMirrorText:hide()
				rotateMirrorBtn:show()
				removeMirrorBtn:show()
				mirrorControls.Width = ui_config.padding + (rotateMirrorBtn.Width + ui_config.padding) * 2
			end
			mirrorControls.LocalPosition =
				{ Screen.Width - mirrorControls.Width - ui_config.padding, editMenu.Height + 2 * ui_config.padding, 0 }
		else
			mirrorControls:hide()
		end

		-- Pivot
		if isModeChangePivot then
			item:Recurse(function(s)
				disableObject(s, false)
			end, { includeRoot = true })

			selectGizmo:setObject(nil)
			changePivotBtn.Text = "Change Pivot"
			isModeChangePivot = false

			moveShapeBtn:enable()
			rotateShapeBtn:enable()
			removeShapeBtn:enable()
			addBlockChildBtn:enable()
			importChildBtn:enable()
			selectGizmo:setOnMove(nil)
		end
	end

	refreshDrawMode = function(forcedDrawMode)
		item:Recurse(function(s)
			if not s or typeof(s) == "Object" then
				return
			end
			if forcedDrawMode ~= nil then
				s.PrivateDrawMode = forcedDrawMode
			else
				if currentMode == mode.points then
					s.PrivateDrawMode = 0
				elseif currentMode == mode.edit then
					s.PrivateDrawMode = (s == focusShape and 2 or 0) + (gridEnabled and 8 or 0) + (dragging2 and 1 or 0)
				end
			end
		end, { includeRoot = true })
	end

	setSelfAndDescendantsHiddenSelf = function(shape, isHiddenSelf)
		shape:Recurse(function(s)
			disableObject(s, isHiddenSelf)
		end, { includeRoot = true })
	end

	undoShapesStack = {}
	redoShapesStack = {}

	----------------------------
	-- SETTINGS
	----------------------------

	local _settings = {
		cameraStartRotation = Number3(0.32, math.rad(225), 0.0),
		cameraStartPreviewRotationHand = Number3(0, math.rad(-130), 0),
		cameraStartPreviewRotationHat = Number3(math.rad(20), math.rad(180), 0),
		cameraStartPreviewRotationBackpack = Number3(0, 0, 0),
		cameraStartPreviewDistance = 15,
		cameraThumbnailRotation = Number3(0.32, 3.9, 0.0), --- other option for Y: 2.33
		zoomMin = 5, -- unit, minimum zoom distance allowed
	}
	settingsMT = {
		__index = function(_, k)
			local v = _settings[k]
			if v == nil then
				return nil
			end
			local ret
			pcall(function()
				ret = v:Copy()
			end)
			if ret ~= nil then
				return ret
			else
				return v
			end
		end,
		__newindex = function()
			error("settings are read-only")
		end,
	}
	settings = {}
	setmetatable(settings, settingsMT)

	Dev.DisplayBoxes = false
	cameraDistFactor = 0.05 -- additive factor per distance unit above threshold
	cameraDistThreshold = 15 -- distance under which scaling is 1

	saveTrigger = 60 -- seconds

	mirrorMargin = 1.0 -- the mirror is x block larger than the item
	mirrorThickness = 1.0 / 4.0

	----------------------------
	-- AMBIANCE
	----------------------------

	local gradientStart = 120
	local gradientStep = 40

	Sky.AbyssColor = Color(gradientStart, gradientStart, gradientStart)
	Sky.HorizonColor = Color(gradientStart + gradientStep, gradientStart + gradientStep, gradientStart + gradientStep)
	Sky.SkyColor =
		Color(gradientStart + gradientStep * 2, gradientStart + gradientStep * 2, gradientStart + gradientStep * 2)
	Clouds.On = false
	Fog.On = false

	----------------------------
	-- CURSOR / CROSSHAIR
	----------------------------

	Pointer:Show()
	require("crosshair"):hide()

	----------------------------
	-- STATE VALUES
	----------------------------

	-- item editor modes

	cameraModes = { FREE = 1, SATELLITE = 2 }
	mode = { edit = 1, points = 2, max = 2 }

	editSubmode = { add = 1, remove = 2, paint = 3, pick = 4, mirror = 5, select = 6, max = 6 }

	pointsSubmode = { move = 1, rotate = 2, max = 2 }

	focusMode = { othersVisible = 1, othersTransparent = 2, othersHidden = 3, max = 3 }
	focusModeName = { "Others Visible", "Others Transparent", "Others Hidden" }

	wearablePreviewMode = { hide = 1, bodyPart = 2, fullBody = 3 }
	currentWearablePreviewMode = wearablePreviewMode.bodyPart

	currentMode = nil
	currentEditSubmode = nil
	currentPointsSubmode = pointsSubmode.move -- points sub mode

	-- used to go back to previous submode and btn after pick
	prePickEditSubmode = nil
	prePickSelectedBtn = nil

	paletteDisplayed = true
	colorPickerDisplayed = false

	-- camera

	blockHighlightDirty = false

	cameraStates = {
		item = {
			target = nil,
			cameraDistance = 0,
			cameraMode = cameraModes.SATELLITE,
			cameraRotation = settings.cameraStartRotation,
			cameraPosition = Number3(0, 0, 0),
		},
		preview = {
			target = nil,
			cameraDistance = 0,
			cameraMode = cameraModes.SATELLITE,
			cameraRotation = settings.cameraStartPreviewRotationHand,
			cameraPosition = Number3(0, 0, 0),
		},
	}

	cameraRefresh = function()
		-- clamp rotation between 90° and -90° on X
		cameraCurrentState.cameraRotation.X =
			clamp(cameraCurrentState.cameraRotation.X, -math.pi * 0.4999, math.pi * 0.4999)

		Camera.Rotation = cameraCurrentState.cameraRotation

		if cameraCurrentState.cameraMode == cameraModes.FREE then
			Camera.Position = cameraCurrentState.cameraPosition
		elseif cameraCurrentState.cameraMode == cameraModes.SATELLITE then
			if cameraCurrentState.target == nil then
				return
			end
			Camera:SetModeSatellite(cameraCurrentState.target, cameraCurrentState.cameraDistance)
		end

		if orientationCube ~= nil then
			orientationCube:setRotation(Camera.Rotation)
		end
	end

	cameraAddRotation = function(r)
		cameraCurrentState.cameraRotation = cameraCurrentState.cameraRotation + r
		cameraRefresh()
	end

	-- input

	dragging2 = false -- drag2 motion active

	-- mirror mode

	mirrorShape = nil
	mirrorAnchor = nil
	mirrorAxes = { x = 1, y = 2, z = 3 }
	currentMirrorAxis = nil

	-- other variables

	item = nil
	standalonePalette = nil -- used for retro-compat w/ items created prior to 0.0.66

	gridEnabled = false
	currentFacemode = false
	changesSinceLastSave = false
	autoSaveDT = 0.0
	halfVoxel = Number3(0.5, 0.5, 0.5)
	poiNameHand = "ModelPoint_Hand_v2"
	poiNameHat = "ModelPoint_Hat"
	poiNameBackpack = "ModelPoint_Backpack"

	poiAvatarRightHandPalmDefaultValue = Number3(3.5, 1.5, 2.5)

	poiActiveName = poiNameHand

	itemCategory = Environment.itemCategory
	if itemCategory == "" then
		itemCategory = "generic"
	end
	isWearable = itemCategory ~= "generic"
	enableWearablePattern = true -- blue/red blocks to guide creation

	----------------------------
	-- OBJECTS & UI ELEMENTS
	----------------------------

	collisionGroup_item = 1

	local loadConfig = { useLocal = true, mutable = true }
	Assets:Load(Environment.itemFullname, function(assets)
		local shapesNotParented = {}

		local t
		for _, asset in ipairs(assets) do
			t = typeof(asset)
			if t == "Palette" then
				standalonePalette = asset
			elseif (t == "Object" or t == "Shape" or t == "MutableShape") and asset:GetParent() == nil then
				table.insert(shapesNotParented, asset)
			end
		end

		local finalObject
		if #shapesNotParented == 1 then
			finalObject = shapesNotParented[1]
		elseif #shapesNotParented > 1 then
			local root = Object()
			for _, v in ipairs(shapesNotParented) do
				root:AddChild(v)
			end
			finalObject = root
		end

		item = finalObject
		item:SetParent(World)

		if isWearable then
			if itemCategory == "pants" then
				item.Scale = 1.05
			end

			if enableWearablePattern then
				local str = "shapes/pattern" .. itemCategory
				pattern = bundle:Shape(str)
				pattern.Physics = PhysicsMode.Disabled
			end
		end

		-- set customCollisionBox if not equals to BoundingBox
		if item.BoundingBox.Min ~= item.CollisionBox.Min and item.BoundingBox.Max ~= item.CollisionBox.Max then
			customCollisionBox = Box(item.CollisionBox.Min, item.CollisionBox.Max)
		end

		ui_init()
		post_item_load()

		Menu:AddDidBecomeActiveCallback(menuDidBecomeActive)
		Client.Tick = tick
		Pointer.Zoom = zoom
		Pointer.Up = up
		Pointer.Click = click
		Pointer.LongPress = longPress
		Pointer.DragBegin = dragBegin
		Pointer.Drag = drag
		Pointer.DragEnd = dragEnd
		Pointer.Drag2Begin = drag2Begin
		Pointer.Drag2 = drag2
		Pointer.Drag2End = drag2End
		Screen.DidResize = didResize
		Screen.DidResize(Screen.Width, Screen.Height)
	end, AssetType.AnyObject, loadConfig)

	updateWearableShapesPosition = function()
		local parents = utils:equipmentParents(Player, itemCategory)
		local parentsType = typeof(parents)

		-- parents can be a Lua table (containing Shapes) or a Shape
		if parentsType == "table" then
			-- item root shape
			do
				local s = item
				local parentIndex = 1
				local coords = parents[parentIndex]:GetPoint("origin").Coords
				s.Position = parents[parentIndex]:BlockToWorld(coords)
				s.Rotation = parents[parentIndex].Rotation
			end

			-- 1st subshape of item
			local child = item:GetChild(1)
			local parent = parents[2]
			parent.LocalPosition = bodyPartsBasePositions[parent]
			if currentWearablePreviewMode == wearablePreviewMode.hide then
				if itemCategory == "pants" or itemCategory == "boots" then
					parent.LocalPosition = parent.LocalPosition + Number3(-5, 0, 0)
				elseif itemCategory == "jacket" then
					parent.LocalPosition = parent.LocalPosition + Number3(5, 0, 0)
				else
					local err = "Category not supported, category is" .. itemCategory
					error(err)
				end
			end
			local bodyPartCoords = parent:GetPoint("origin").Coords
			local pos = parent:BlockToWorld(bodyPartCoords)
			child.Position = pos
			child.Rotation = parent.Rotation

			if itemCategory ~= "jacket" then
				return
			end

			-- 1st subshape of 1st subshape of item
			child = child:GetChild(1)
			parent = parents[3]
			parent.LocalPosition = bodyPartsBasePositions[parent]
			if currentWearablePreviewMode == wearablePreviewMode.hide then
				parent.LocalPosition = parent.LocalPosition + Number3(-5, 0, 0)
			end
			bodyPartCoords = parent:GetPoint("origin").Coords
			pos = parent:BlockToWorld(bodyPartCoords)
			child.Position = pos
			child.Rotation = parent.Rotation
		elseif parentsType == "MutableShape" then
			local coords = parents:GetPoint("origin").Coords

			item.Position = parents:BlockToWorld(coords)
			item.Rotation = parents.Rotation
		end

		fitObjectToScreen(item, nil)
	end

	Player.Body:Recurse(function(bodyPart)
		bodyPartsBasePositions[bodyPart] = bodyPart.LocalPosition:Copy()
	end, { includeRoot = true })

	-- long press + drag
	continuousEdition = false
	blocksAddedWithDrag = {}

	-- a cube to show where the camera is looking at
	blockHighlight = bundle:MutableShape("shapes/cube_selector")
	blockHighlight.PrivateDrawMode = 2 + (gridEnabled and 8 or 0) -- highlight
	blockHighlight.Scale = 1 / (blockHighlight.Width - 1)
	blockHighlight:SetParent(World)
	blockHighlight.IsHidden = true
	blockHighlight.Physics = PhysicsMode.Disabled
end -- OnStart end

Client.Action1 = nil
Client.Action2 = nil
Client.Action1Release = nil
Client.Action2Release = nil
Client.Action3Release = nil

menuDidBecomeActive = function()
	if changesSinceLastSave then
		save()
	end
end

Client.Tick = function() end
tick = function(dt)
	if changesSinceLastSave then
		autoSaveDT = autoSaveDT + dt
		if autoSaveDT > saveTrigger then
			save()
		else
			local remaining = math.floor(saveTrigger - autoSaveDT)
			saveBtn.label.Text = (remaining < 10 and " " or "") .. remaining
		end
	end

	if blockHighlightDirty then
		refreshBlockHighlight()
	end

	if #blocksToRemove > 0 then
		for _, t in ipairs(blocksToRemove) do
			removeSingleBlock(t.block, t.shape)
		end
		updateMirror()
		blocksToRemove = {}
	end
end

Pointer.Zoom = function() end
zoom = function(zoomValue)
	local factor = 0.5

	if cameraCurrentState.cameraMode == cameraModes.FREE then
		cameraCurrentState.cameraPosition = cameraCurrentState.cameraPosition + (zoomValue * Camera.Backward * factor)
		cameraRefresh()
	elseif cameraCurrentState.cameraMode == cameraModes.SATELLITE then
		cameraCurrentState.cameraDistance = math.max(
			settings.zoomMin,
			cameraCurrentState.cameraDistance + zoomValue * factor * getCameraDistanceFactor()
		)
		cameraRefresh()
	end
end

Pointer.Click = function() end
click = function(e)
	if currentMode ~= mode.edit or continuousEdition then
		return
	end

	-- Raycast against all currently physics-enabled objects, we ensured that hidden objects are also physics-disabled
	-- note: if needed here, we could selectively use groups for item, player, and wearables ; for example if both body parts
	-- and wearable are shown but we want to raycast only against wearables e:CastRay(collisionGroup_wearable), or only
	-- against the item shapes e:CastRay(collisionGroup_item)
	local impact = e:CastRay()
	local shape = impact.Shape

	if impact == nil then
		return
	end

	if isWearable and not shape.isItem then
		if currentEditSubmode ~= editSubmode.add then
			return
		end
		local bodyPartName
		for _, part in pairs(bodyParts) do
			if Player[part] == shape then
				bodyPartName = part
				break
			end
		end
		shape = bodyPartToWearablePart[bodyPartName]
		if shape == nil then
			return
		end
	end

	if currentEditSubmode == editSubmode.pick then
		pickCubeColor(impact.Block)
	elseif currentEditSubmode == editSubmode.add then
		local impactPosition = Camera.Position + e.Direction * (impact.Distance - 0.1) -- epsilon to avoid number rounding errors
		local impactCoords = shape:WorldToBlock(impactPosition)
		addBlockWithImpact(impact, currentFacemode, shape, impactCoords)
		table.insert(undoShapesStack, shape)
		redoShapesStack = {}
	elseif currentEditSubmode == editSubmode.remove and shape ~= nil then
		removeBlockWithImpact(impact, currentFacemode, shape)
		table.insert(undoShapesStack, shape)
		redoShapesStack = {}
	elseif currentEditSubmode == editSubmode.paint then
		replaceBlockWithImpact(impact, currentFacemode, shape)
		table.insert(undoShapesStack, shape)
		redoShapesStack = {}
	elseif currentEditSubmode == editSubmode.mirror then
		placeMirror(impact, shape)
	elseif currentEditSubmode == editSubmode.select then
		selectFocusShape(shape)
	end

	if
		currentEditSubmode == editSubmode.add
		or currentEditSubmode == editSubmode.remove
		or currentEditSubmode == editSubmode.paint
	then
		checkAutoSave()
		refreshUndoRedoButtons()
	end
end

Pointer.Up = function() end
up = function(_)
	if blockerShape ~= nil then
		blockerShape:RemoveFromParent()
		blockerShape = nil
	end

	local shape = selectedShape or focusShape
	if shape and shape.isItem then
		shape.KeepHistoryTransactionPending = false
	end

	if continuousEdition then
		refreshUndoRedoButtons()
		continuousEdition = false
	end
end

Client.OnPlayerJoin = function(_)
	Player.Physics = false
end

Pointer.LongPress = function() end
longPress = function(e)
	if currentMode == mode.edit then
		local impact = e:CastRay()
		selectedShape = nil

		if impact.Block ~= nil then
			selectedShape = impact.Shape
			if not selectedShape.isItem then
				return
			end

			selectedShape.KeepHistoryTransactionPending = true

			continuousEdition = true

			-- add / remove / paint first block
			if currentEditSubmode == editSubmode.add then
				local addedBlock = addBlockWithImpact(impact, currentFacemode, selectedShape)
				table.insert(blocksAddedWithDrag, addedBlock)
				table.insert(undoShapesStack, selectedShape)
			elseif currentEditSubmode == editSubmode.remove then
				blockerShape = MutableShape()
				blockerShape.Palette:AddColor(Color(0, 0, 0, 0))
				World:AddChild(blockerShape)
				blockerShape.Scale = selectedShape.Scale
				blockerShape.Pivot = selectedShape.Pivot
				blockerShape.Position = selectedShape.Position
				blockerShape.Rotation = selectedShape.Rotation
				local coords = blockerShape:WorldToBlock(selectedShape:BlockToWorld(impact.Block) + { 0.5, 0.5, 0.5 })
				blockerShape:AddBlock(1, coords)

				local blockToRemove = { shape = selectedShape, block = impact.Block }
				table.insert(blocksToRemove, blockToRemove)
				table.insert(undoShapesStack, selectedShape)
			elseif currentEditSubmode == editSubmode.paint then
				replaceBlockWithImpact(impact, currentFacemode, selectedShape)
				table.insert(undoShapesStack, selectedShape)
			end
		end
	end
end

Pointer.DragBegin = function() end
dragBegin = function() end

Pointer.Drag = function() end
drag = function(e)
	if not continuousEdition then
		local angularSpeed = 0.01
		cameraAddRotation({ -e.DY * angularSpeed, e.DX * angularSpeed, 0 })
	end

	if continuousEdition and currentMode == mode.edit then
		local impact = e:CastRay(selectedShape, mirrorShape)

		if impact.Block == nil then
			return
		end

		if currentEditSubmode == editSubmode.add then
			local canBeAdded = true
			for _, b in pairs(blocksAddedWithDrag) do
				if impact.Block.Coords == b.Coords then
					-- do not add on top of added blocks
					canBeAdded = false
					break
				end
			end
			if canBeAdded then
				local addedBlock = addBlockWithImpact(impact, currentFacemode, selectedShape)
				table.insert(blocksAddedWithDrag, addedBlock)
			end
		elseif currentEditSubmode == editSubmode.remove then
			local impactOnBlocker = e:CastRay(blockerShape, mirrorShape)

			if impactOnBlocker.Block ~= nil and impact.Distance > impactOnBlocker.Distance then
				return
			end

			local coords = blockerShape:WorldToBlock(item:BlockToWorld(impact.Block) + { 0.5, 0.5, 0.5 })
			blockerShape:AddBlock(1, coords)
			local blockToRemove = { shape = selectedShape, block = impact.Block }
			table.insert(blocksToRemove, blockToRemove)
		elseif currentEditSubmode == editSubmode.paint then
			replaceBlockWithImpact(impact, currentFacemode, selectedShape)
		end
	end
end

Pointer.DragEnd = nil
dragEnd = function()
	blocksAddedWithDrag = {}
end

Pointer.Drag2Begin = function() end
drag2Begin = function()
	if currentMode == mode.edit then
		dragging2 = true
		setFreeCamera()
		require("crosshair"):show()
		refreshDrawMode()
	end
end

Pointer.Drag2 = function() end
drag2 = function(e)
	-- in edit mode, Drag2 performs camera pan
	if currentMode == mode.edit then
		local factor = 0.1
		local dx = e.DX * factor * getCameraDistanceFactor()
		local dy = e.DY * factor * getCameraDistanceFactor()

		cameraCurrentState.cameraPosition = cameraCurrentState.cameraPosition - Camera.Right * dx - Camera.Up * dy
		cameraRefresh()

		refreshBlockHighlight()
	end
end

Pointer.Drag2End = function() end
drag2End = function()
	-- snaps to nearby block center after drag2 (camera pan)
	if dragging2 then
		local impact = Camera:CastRay()
		if impact.Block ~= nil then
			local target = impact.Block.Position + halfVoxel
			cameraCurrentState.cameraMode = cameraModes.SATELLITE
			cameraCurrentState.target = target
			cameraCurrentState.cameraDistance = (target - Camera.Position).Length
			cameraRefresh()
		else
			cameraCurrentState.cameraMode = cameraModes.FREE
			cameraCurrentState.cameraPosition = Camera.Position
			-- cameraCurrentState.cameraRotation = Camera.Rotation
			cameraRefresh()
		end

		dragging2 = false
		require("crosshair"):hide()
		refreshDrawMode()
	end
end

Screen.DidResize = function() end
didResize = function(_, _)
	--
	-- Camera.FOV = (width / height) * 60.0
	if orientationCube ~= nil then
		local size = paletteBtn.Width * 2 + ui_config.padding
		orientationCube:setSize(size)
		orientationCube:setScreenPosition(
			editSubMenu.pos.X + editSubMenu.Width - size,
			editSubMenu.pos.Y - size - ui_config.padding
		)
	end

	if colorPicker ~= nil then
		local maxW = math.min(Screen.Width * 0.5 - theme.padding * 3, 400)
		local maxH = math.min(Screen.Height * 0.4 - theme.padding * 3, 300)
		colorPicker:setMaxSize(maxW, maxH)
	end

	updatePalettePosition()

	-- selectButtons.LocalPosition = Number3(5, Screen.Height / 2 - 25, 0)
end

--------------------------------------------------
-- Utilities
--------------------------------------------------

initClientFunctions = function()
	function setMode(newMode, newSubmode)
		local updatingMode = newMode ~= nil and newMode ~= currentMode
		local updatingSubMode = false

		-- going from one mode to another
		if updatingMode then
			if newMode < 1 or newMode > mode.max then
				error("setMode - invalid change:" .. newMode .. " " .. newSubmode)
				return
			end

			currentMode = newMode

			if currentMode == mode.edit then
				cameraCurrentState = cameraStates.item

				-- unequip Player
				if poiActiveName == poiNameHand then
					Player:EquipRightHand(nil)
				elseif poiActiveName == poiNameHat then
					Player:EquipHat(nil)
				elseif poiActiveName == poiNameBackpack then
					Player:EquipBackpack(nil)
				end

				-- remove avatar and arrows
				Player:RemoveFromParent()

				item:SetParent(World)
				item.LocalPosition = { 0, 0, 0 }
				item.LocalRotation = { 0, 0, 0 }

				Client.DirectionalPad = nil

				blockHighlight.IsHidden = false
				blockHighlightDirty = true
			else -- place item points / preview
				cameraCurrentState = cameraStates.preview
				-- make player appear in front of camera with item in hand

				Player.Head.IgnoreAnimations = true
				Player.Body.IgnoreAnimations = true
				Player.RightArm.IgnoreAnimations = true
				Player.RightHand.IgnoreAnimations = true
				Player.LeftArm.IgnoreAnimations = true
				Player.LeftHand.IgnoreAnimations = true
				Player.LeftLeg.IgnoreAnimations = true
				Player.LeftFoot.IgnoreAnimations = true
				Player.RightLeg.IgnoreAnimations = true
				Player.RightFoot.IgnoreAnimations = true

				Player:SetParent(World)
				Player.Physics = false

				if poiActiveName == poiNameHand then
					Player:EquipRightHand(item)
					cameraCurrentState.target = getEquipmentAttachPointWorldPosition("handheld")
					cameraCurrentState.cameraRotation = settings.cameraStartPreviewRotationHand
					cameraCurrentState.cameraDistance = 20
				elseif poiActiveName == poiNameHat then
					Player:EquipHat(item)
					cameraCurrentState.target = getEquipmentAttachPointWorldPosition("hat")
					cameraCurrentState.cameraRotation = settings.cameraStartPreviewRotationHat
					cameraCurrentState.cameraDistance = 20
				elseif poiActiveName == poiNameBackpack then
					Player:EquipBackpack(item)
					cameraCurrentState.target = getEquipmentAttachPointWorldPosition("backpack")
					cameraCurrentState.cameraRotation = settings.cameraStartPreviewRotationBackpack
					cameraCurrentState.cameraDistance = 20
				end

				Client.DirectionalPad = nil

				blockHighlight.IsHidden = true
				blockHighlightDirty = false
			end

			refreshUndoRedoButtons()
			cameraRefresh()
		end -- end updating node

		-- see if submode needs to be changed
		if newSubmode ~= nil then
			selectFocusShape()
			if newSubmode < 1 then
				error("setMode - invalid change:" .. newMode .. " " .. newSubmode)
				return
			end

			if currentMode == mode.edit then
				if newSubmode > editSubmode.max then
					error("setMode - invalid change:" .. newMode .. " " .. newSubmode)
					return
				end
				confirmColliderBtn:_onRelease()
				-- return if new submode is already active
				if newSubmode == currentEditSubmode then
					return
				end
				updatingSubMode = true
				currentEditSubmode = newSubmode
			elseif currentMode == mode.points then
				if newSubmode > pointsSubmode.max then
					error("setMode - invalid change:" .. newMode .. " " .. newSubmode)
					return
				end
				-- return if new submode is already active
				if newSubmode == currentPointsSubmode then
					return
				end
				updatingSubMode = true
				currentPointsSubmode = newSubmode
			end
		end

		if updatingMode then
			LocalEvent:Send("modeDidChange")
		end

		if updatingMode or updatingSubMode then
			LocalEvent:Send("modeOrSubmodeDidChange")
		end
	end

	function checkAutoSave()
		if changesSinceLastSave == false then
			changesSinceLastSave = true
			autoSaveDT = 0.0
		end
	end

	function save()
		--TODO: Remove customCollisionBox mechanic when adding and removing blocks, does not shrink collider by default
		if customCollisionBox then
			item.CollisionBox = customCollisionBox
		end

		if isModeChangePivot then
			item:Recurse(function(s)
				s.IsHiddenSelf = false
			end, { includeRoot = true })
		end

		item:Save(Environment.itemFullname, nil, itemCategory)

		if isModeChangePivot then
			item:Recurse(function(s)
				s.IsHiddenSelf = s ~= focusShape
			end, { includeRoot = true })
		end

		changesSinceLastSave = false

		saveBtn.label.Text = "✅"
	end

	addBlockWithImpact = function(impact, facemode, shape, overrideCoords)
		if shape == nil or impact == nil or facemode == nil or impact.Block == nil then
			return
		end
		if type(facemode) ~= "boolean" then
			return
		end

		-- always add the first block
		local addedBlock
		if overrideCoords then
			local block = shape:GetBlock(overrideCoords)
			addedBlock = addSingleBlock(block, nil, shape, overrideCoords)
		else
			addedBlock = addSingleBlock(impact.Block, impact.FaceTouched, shape)
		end

		-- if facemode is enable, test the neighbor blocks of impact.Block
		if addedBlock ~= nil and facemode then
			local faceTouched = impact.FaceTouched
			local oldColorPaletteIndex = impact.Block.PaletteIndex
			local queue = { impact.Block }
			-- neighbor finder (depending on the mirror orientation)
			local neighborFinder = {}
			if faceTouched == Face.Top or faceTouched == Face.Bottom then
				neighborFinder = { Number3(1, 0, 0), Number3(-1, 0, 0), Number3(0, 0, 1), Number3(0, 0, -1) }
			elseif faceTouched == Face.Left or faceTouched == Face.Right then
				neighborFinder = { Number3(0, 1, 0), Number3(0, -1, 0), Number3(0, 0, 1), Number3(0, 0, -1) }
			elseif faceTouched == Face.Front or faceTouched == Face.Back then
				neighborFinder = { Number3(1, 0, 0), Number3(-1, 0, 0), Number3(0, 1, 0), Number3(0, -1, 0) }
			end

			-- explore
			while true do
				local b = table.remove(queue)
				if b == nil then
					break
				end
				for _, f in ipairs(neighborFinder) do
					local neighborCoords = b.Coords + f
					-- check there is a block
					local neighborBlock = shape:GetBlock(neighborCoords)
					-- check it is the same color
					if neighborBlock ~= nil and neighborBlock.PaletteIndex == oldColorPaletteIndex then
						-- try to add new block on top of neighbor
						addedBlock = addSingleBlock(neighborBlock, faceTouched, shape)
						if addedBlock ~= nil then
							table.insert(queue, neighborBlock)
						end
					end
				end
			end
		end

		updateMirror()

		return addedBlock
	end

	addSingleBlock = function(block, faceTouched, shape, overrideCoords)
		local faces = {
			[Face.Top] = Number3(0, 1, 0),
			[Face.Bottom] = Number3(0, -1, 0),
			[Face.Left] = Number3(-1, 0, 0),
			[Face.Right] = Number3(1, 0, 0),
			[Face.Back] = Number3(0, 0, -1),
			[Face.Front] = Number3(0, 0, 1),
		}
		local newBlockCoords
		if faceTouched then
			newBlockCoords = block.Coordinates + faces[faceTouched]
		else
			newBlockCoords = overrideCoords
		end

		if enableWearablePattern and pattern then
			local targetPattern = pattern
			if item.ChildrenCount > 0 then
				local child = item:GetChild(1) -- Is first child (left part or right sleeve)
				if shape == child then
					targetPattern = pattern:GetChild(1)
				elseif child.ChildrenCount > 0 then
					if shape == child:GetChild(1) then -- Is first child of child (left sleeve)
						targetPattern = pattern:GetChild(1):GetChild(1)
					end
				end
			end
			local coords = newBlockCoords
			local relativeCoords = coords - shape:GetPoint("origin").Coords
			local pos = relativeCoords + targetPattern:GetPoint("origin").Coords
			local b = targetPattern:GetBlock(pos)
			if not b then
				pattern:SetParent(World)
				local nextShape = item
				pattern.Scale = item.Scale + Number3(1, 1, 1) * 0.001
				pattern:Recurse(function(s)
					s.PrivateDrawMode = 1
					s.Pivot = s:GetPoint("origin").Coords
					s.Position = nextShape.Position
					nextShape = nextShape:GetChild(1)
				end, { includeRoot = true })
				Timer(0.5, function()
					pattern:RemoveFromParent()
				end)
				return
			end
		end

		local added = shape:AddBlock(palette:getCurrentIndex(), newBlockCoords)
		if not added then
			return nil
		end

		local addedBlock = shape:GetBlock(newBlockCoords)
		-- add a block to the other side of the mirror
		if addedBlock ~= nil and shape == mirrorAnchor.selectedShape then
			local mirrorBlockCoords = mirrorAnchor.coords

			local posX = currentMirrorAxis == mirrorAxes.x
					and (mirrorBlockCoords.X - (addedBlock.Coordinates.X - mirrorBlockCoords.X))
				or addedBlock.Coordinates.X
			local posY = currentMirrorAxis == mirrorAxes.y
					and (mirrorBlockCoords.Y - (addedBlock.Coordinates.Y - mirrorBlockCoords.Y))
				or addedBlock.Coordinates.Y
			local posZ = currentMirrorAxis == mirrorAxes.z
					and (mirrorBlockCoords.Z - (addedBlock.Coordinates.Z - mirrorBlockCoords.Z))
				or addedBlock.Coordinates.Z
			local added = shape:AddBlock(palette:getCurrentIndex(), posX, posY, posZ)
			if added then
				local mirrorBlock = shape:GetBlock(posX, posY, posZ)
				if mirrorBlock and continuousEdition then
					table.insert(blocksAddedWithDrag, mirrorBlock)
				end
			end
		end

		return addedBlock
	end

	removeBlockWithImpact = function(impact, facemode, shape)
		if shape.BlocksCount == 1 then
			return
		end
		if shape == nil or impact == nil or facemode == nil or impact.Block == nil then
			return
		end
		if type(facemode) ~= "boolean" then
			return
		end

		-- always remove the first block
		removeSingleBlock(impact.Block, shape)

		-- if facemode is enable, test the neighbor blocks of impact.Block
		if facemode then
			local faceTouched = impact.FaceTouched
			local oldColorPaletteIndex = impact.Block.PaletteIndex
			local queue = { impact.Block }
			-- neighbor finder (depending on the mirror orientation)
			local neighborFinder = {}
			if faceTouched == Face.Top or faceTouched == Face.Bottom then
				neighborFinder = { Number3(1, 0, 0), Number3(-1, 0, 0), Number3(0, 0, 1), Number3(0, 0, -1) }
			elseif faceTouched == Face.Left or faceTouched == Face.Right then
				neighborFinder = { Number3(0, 1, 0), Number3(0, -1, 0), Number3(0, 0, 1), Number3(0, 0, -1) }
			elseif faceTouched == Face.Front or faceTouched == Face.Back then
				neighborFinder = { Number3(1, 0, 0), Number3(-1, 0, 0), Number3(0, 1, 0), Number3(0, -1, 0) }
			end

			-- relative coords from touched plan to block next to it
			-- (needed to check if there is a block next to the one we want to remove)
			local targetNeighbor = targetBlockDeltaFromTouchedFace(faceTouched)

			-- explore
			while true do
				local b = table.remove(queue)
				if b == nil then
					break
				end
				for _, f in ipairs(neighborFinder) do
					local neighborCoords = b.Coords + f
					-- check there is a block
					local neighborBlock = shape:GetBlock(neighborCoords)
					-- check block on top
					local blockOnTopPosition = neighborCoords + targetNeighbor
					local blockOnTop = shape:GetBlock(blockOnTopPosition)
					-- check it is the same color
					if
						neighborBlock ~= nil
						and neighborBlock.PaletteIndex == oldColorPaletteIndex
						and blockOnTop == nil
					then
						removeSingleBlock(neighborBlock, shape)
						table.insert(queue, neighborBlock)
					end
				end
				if shape.BlocksCount == 1 then
					return
				end
			end
		end

		updateMirror()
	end

	removeSingleBlock = function(block, shape)
		block:Remove()

		-- last block can't be removed via mirror mode
		if shape.BlocksCount > 2 and shape == mirrorAnchor.selectedShape then
			local mirrorBlockCoords = mirrorAnchor.coords
			local mirrorBlock

			local posX = currentMirrorAxis == mirrorAxes.x
					and (mirrorBlockCoords.X - (block.Coordinates.X - mirrorBlockCoords.X))
				or block.Coordinates.X
			local posY = currentMirrorAxis == mirrorAxes.y
					and (mirrorBlockCoords.Y - (block.Coordinates.Y - mirrorBlockCoords.Y))
				or block.Coordinates.Y
			local posZ = currentMirrorAxis == mirrorAxes.z
					and (mirrorBlockCoords.Z - (block.Coordinates.Z - mirrorBlockCoords.Z))
				or block.Coordinates.Z
			mirrorBlock = shape:GetBlock(posX, posY, posZ)

			if mirrorBlock ~= nil then
				mirrorBlock:Remove()
			end
		end
	end

	replaceBlockWithImpact = function(impact, facemode, shape)
		if impact == nil or facemode == nil or impact.Block == nil then
			return
		end
		if type(facemode) ~= "boolean" then
			return
		end

		local oldColorPaletteIndex = impact.Block.PaletteIndex

		-- return if trying to replace with same color index
		if oldColorPaletteIndex == palette:getCurrentIndex() then
			return
		end

		-- always paint the first block
		replaceSingleBlock(impact.Block, shape)

		if facemode then
			local faceTouched = impact.FaceTouched
			local queue = { impact.Block }
			-- neighbor finder (depending on the mirror orientation)
			local neighborFinder = {}
			if faceTouched == Face.Top or faceTouched == Face.Bottom then
				neighborFinder = { Number3(1, 0, 0), Number3(-1, 0, 0), Number3(0, 0, 1), Number3(0, 0, -1) }
			elseif faceTouched == Face.Left or faceTouched == Face.Right then
				neighborFinder = { Number3(0, 1, 0), Number3(0, -1, 0), Number3(0, 0, 1), Number3(0, 0, -1) }
			elseif faceTouched == Face.Front or faceTouched == Face.Back then
				neighborFinder = { Number3(1, 0, 0), Number3(-1, 0, 0), Number3(0, 1, 0), Number3(0, -1, 0) }
			end

			-- relative coords from touched plan to block next to it
			-- (needed to check if there is a block next to the one we want to remove)
			local targetNeighbor = targetBlockDeltaFromTouchedFace(faceTouched)

			-- explore
			while true do
				local b = table.remove(queue)
				if b == nil then
					break
				end
				for _, f in ipairs(neighborFinder) do
					local neighborCoords = b.Coords + f
					-- check there is a block
					local neighborBlock = shape:GetBlock(neighborCoords)
					-- check block on top
					local blockOnTopPosition = neighborCoords + targetNeighbor
					local blockOnTop = shape:GetBlock(blockOnTopPosition)
					-- check it is the same color
					if
						neighborBlock ~= nil
						and neighborBlock.PaletteIndex == oldColorPaletteIndex
						and blockOnTop == nil
					then
						replaceSingleBlock(neighborBlock, shape)
						table.insert(queue, neighborBlock)
					end
				end
			end
		end
	end

	replaceSingleBlock = function(block, shape)
		block:Replace(palette:getCurrentIndex())

		if shape == mirrorAnchor.selectedShape then
			local mirrorBlockCoords = mirrorAnchor.coords
			local mirrorBlock

			local posX = currentMirrorAxis == mirrorAxes.x
					and (mirrorBlockCoords.X - (block.Coordinates.X - mirrorBlockCoords.X))
				or block.Coordinates.X
			local posY = currentMirrorAxis == mirrorAxes.y
					and (mirrorBlockCoords.Y - (block.Coordinates.Y - mirrorBlockCoords.Y))
				or block.Coordinates.Y
			local posZ = currentMirrorAxis == mirrorAxes.z
					and (mirrorBlockCoords.Z - (block.Coordinates.Z - mirrorBlockCoords.Z))
				or block.Coordinates.Z
			mirrorBlock = shape:GetBlock(posX, posY, posZ)

			if mirrorBlock ~= nil then
				mirrorBlock:Replace(palette:getCurrentIndex())
			end
		end
	end

	pickCubeColor = function(block)
		if block ~= nil then
			palette:selectIndexOrAddColorIfMissing(block.PaletteIndex, block.Color)
		end

		if prePickEditSubmode then
			setMode(nil, prePickEditSubmode)
		end
		if prePickSelectedBtn then
			editMenuToggleSelect(prePickSelectedBtn)
		end

		LocalEvent:Send("selectedColorDidChange")
	end

	selectFocusShape = function(shape)
		focusShape = shape

		-- Do not show gizmo if root item or if shape is nil (unselect)
		local gizmoShape = (shape ~= nil and shape ~= item) and shape or nil
		selectGizmo:setObject(gizmoShape)

		refreshDrawMode()

		selectControlsRefresh()
	end

	refreshUndoRedoButtons = function()
		-- show these buttons only on edit mode
		if currentMode ~= mode.edit then
			return
		end

		local lastUndoableShape = undoShapesStack[#undoShapesStack]
		if lastUndoableShape.CanUndo then
			undoBtn:enable()
		else
			undoBtn:disable()
		end

		local lastRedoableShape = redoShapesStack[#redoShapesStack]
		if lastRedoableShape.CanRedo then
			redoBtn:enable()
		else
			redoBtn:disable()
		end
	end

	placeMirror = function(impact, shape)
		if not shape then
			return
		end
		-- place mirror if block has been hit
		-- and parent shape is equal to shape parameter
		if impact ~= nil and impact.Object == shape and impact.Block ~= nil then
			-- first time the mirror is placed since last removal
			if mirrorShape == nil then
				mirrorShape = bundle:Shape("shapes/cube_white")
				mirrorShape.Pivot = { 0.5, 0.5, 0.5 }
				mirrorShape.PrivateDrawMode = 1
				mirrorShape.Physics = PhysicsMode.Disabled

				-- Anchor at the shape position because the mirror is not attached to the shape
				mirrorAnchor = Object()
				mirrorAnchor:SetParent(World)
				mirrorShape:SetParent(mirrorAnchor)

				-- only set rotation creating the mirror
				-- moving it should not affect initial rotation
				local face = impact.FaceTouched

				if face == Face.Right then
					currentMirrorAxis = mirrorAxes.x
				elseif face == Face.Left then
					currentMirrorAxis = mirrorAxes.x
				elseif face == Face.Top then
					currentMirrorAxis = mirrorAxes.y
				elseif face == Face.Bottom then
					currentMirrorAxis = mirrorAxes.y
				elseif face == Face.Back then
					currentMirrorAxis = mirrorAxes.z
				elseif face == Face.Front then
					currentMirrorAxis = mirrorAxes.z
				else
					error("can't set mirror axis")
					currentMirrorAxis = nil
				end
			end

			mirrorAnchor.coords = impact.Block.Coords

			mirrorAnchor.selectedShape = shape

			mirrorControls:show()

			placeMirrorText:hide()
			rotateMirrorBtn:show()
			removeMirrorBtn:show()
			mirrorControls.Width = ui_config.padding + (rotateMirrorBtn.Width + ui_config.padding) * 2
			mirrorControls.LocalPosition =
				{ Screen.Width - mirrorControls.Width - ui_config.padding, editMenu.Height + 2 * ui_config.padding, 0 }
		end

		updateMirror()
	end

	removeMirror = function()
		if mirrorShape ~= nil then
			mirrorGizmo:setObject(nil)
			mirrorShape:RemoveFromParent()
			mirrorAnchor:RemoveFromParent()
		end
		mirrorShape = nil
		mirrorAnchor = nil
		currentMirrorAxis = nil
	end

	-- updates the dimension of the mirror when adding/removing cubes
	updateMirror = function()
		if mirrorShape ~= nil and mirrorAnchor ~= nil then
			local shape = mirrorAnchor.selectedShape
			if not shape then
				return
			end

			local width = shape.Width + mirrorMargin
			local height = shape.Height + mirrorMargin
			local depth = shape.Depth + mirrorMargin

			mirrorAnchor.Position = shape:BlockToWorld(mirrorAnchor.coords + { 0.5, 0.5, 0.5 })
			mirrorAnchor.Rotation = shape.Rotation

			local shapeCenter = shape:BlockToWorld(shape.Center)

			mirrorShape.Position = shapeCenter

			if currentMirrorAxis == mirrorAxes.x then
				mirrorShape.LocalScale = { mirrorThickness, height, depth }
				mirrorShape.LocalPosition.X = 0
				mirrorGizmo:setAxisVisibility(true, false, false)
			elseif currentMirrorAxis == mirrorAxes.y then
				mirrorShape.LocalScale = { width, mirrorThickness, depth }
				mirrorShape.LocalPosition.Y = 0
				mirrorGizmo:setAxisVisibility(false, true, false)
			elseif currentMirrorAxis == mirrorAxes.z then
				mirrorShape.LocalScale = { width, height, mirrorThickness }
				mirrorShape.LocalPosition.Z = 0
				mirrorGizmo:setAxisVisibility(false, false, true)
			end

			mirrorGizmo:setObject(mirrorAnchor)
		end
	end

	setFreeCamera = function()
		blockHighlight.IsHidden = true
		cameraCurrentState.cameraMode = cameraModes.FREE
		cameraCurrentState.cameraPosition = Camera.Position
		Camera:SetModeFree()
		cameraRefresh()
	end

	fitObjectToScreen = function(object, rotation)
		-- set camera positioning using FitToScreen
		local targetPoint = object:BlockToWorld(object.Center)
		Camera.Position = targetPoint

		if rotation ~= nil then
			Camera.Rotation = rotation
		end

		local box = Box()
		box:Fit(object, true)
		Camera:FitToScreen(box, 0.8, true) -- sets camera back

		-- maintain camera satellite mode
		local distance = (Camera.Position - targetPoint).Length

		cameraCurrentState.cameraMode = cameraModes.SATELLITE
		cameraCurrentState.target = targetPoint
		cameraCurrentState.cameraDistance = math.max(distance, settings.zoomMin)
		if rotation ~= nil then
			cameraCurrentState.rotation = rotation
		end
		cameraRefresh()
	end

	getCameraDistanceFactor = function()
		return 1 + math.max(0, cameraDistFactor * (cameraCurrentState.cameraDistance - cameraDistThreshold))
	end

	refreshBlockHighlight = function()
		local impact = Camera:CastRay()
		if impact.Block ~= nil then
			local halfVoxelVec = Number3(0.5, 0.5, 0.5)
			halfVoxelVec:Rotate(impact.Shape.Rotation)
			blockHighlight.Position = impact.Block.Position + halfVoxelVec
			blockHighlight.IsHidden = false
			blockHighlight.Rotation = impact.Shape.Rotation
		else
			blockHighlight.IsHidden = true
		end
		blockHighlightDirty = false
	end
end

setFacemode = function(newFacemode)
	if newFacemode ~= currentFacemode then
		currentFacemode = newFacemode
	end
end

targetBlockDeltaFromTouchedFace = function(faceTouched)
	-- relative coords from touched plan to block next to it
	-- (needed to check if there is a block next to the one we want to remove)
	local targetNeighbor = Number3(0, 0, 0)
	if faceTouched == Face.Top then
		targetNeighbor = Number3(0, 1, 0)
	elseif faceTouched == Face.Bottom then
		targetNeighbor = Number3(0, -1, 0)
	elseif faceTouched == Face.Left then
		targetNeighbor = Number3(-1, 0, 0)
	elseif faceTouched == Face.Right then
		targetNeighbor = Number3(1, 0, 0)
	elseif faceTouched == Face.Front then
		targetNeighbor = Number3(0, 0, 1)
	elseif faceTouched == Face.Back then
		targetNeighbor = Number3(0, 0, -1)
	end
	return targetNeighbor
end

function getEquipmentAttachPointWorldPosition(equipmentType)
	-- body parts have a point stored in model space (block coordinates), where item must be attached
	-- we can use it to find the corresponding item block
	local worldBodyPoint = Number3(0, 0, 0)

	if equipmentType == "handheld" then
		worldBodyPoint = Player.RightHand:BlockToWorld(poiAvatarRightHandPalmDefaultValue)
	elseif equipmentType == "hat" then
		-- TODO: review this
		worldBodyPoint = Player.Head:GetPoint(poiNameHat).Position
		if worldBodyPoint == nil then
			-- default value
			worldBodyPoint = Player.Head:PositionLocalToWorld({ -0.5, 8.5, -0.5 })
		end
	elseif equipmentType == "backpack" then
		-- TODO: review this
		worldBodyPoint = Player.Body:GetPoint(poiNameBackpack).Position
		if worldBodyPoint == nil then
			-- default value
			worldBodyPoint = Player.Body:PositionLocalToWorld({ 0.5, 2.5, -1.5 })
		end
	end

	return worldBodyPoint
end

function savePOI()
	if poiActiveName == nil or poiActiveName == "" then
		return
	end

	-- body parts have a point stored in model space (block coordinates), where item must be attached
	-- we can use it to find the corresponding item block
	local worldBodyPoint = Number3(0, 0, 0)

	if poiActiveName == poiNameHand then
		worldBodyPoint = getEquipmentAttachPointWorldPosition("handheld")
	elseif poiActiveName == poiNameHat then
		worldBodyPoint = getEquipmentAttachPointWorldPosition("hat")
	elseif poiActiveName == poiNameBackpack then
		worldBodyPoint = getEquipmentAttachPointWorldPosition("backpack")
	end

	-- item POI is stored in model space (block coordinates)
	local modelPoint = item:WorldToBlock(worldBodyPoint)

	-- Save new point coords/rotation
	item:AddPoint(poiActiveName, modelPoint, item.LocalRotation)

	checkAutoSave()
end

ui_config = {
	padding = 6,
	btnColor = Color(120, 120, 120),
	btnColorSelected = Color(97, 71, 206),
	btnColorDisabled = Color(120, 120, 120, 0.2),
	btnTextColorDisabled = Color(255, 255, 255, 0.2),
	btnColorMode = Color(38, 85, 128),
	btnColorModeSelected = Color(75, 128, 192),
}

function ui_init()
	local padding = ui_config.padding
	local btnColor = ui_config.btnColor
	local btnColorSelected = ui_config.btnColorSelected

	function createButton(text)
		local btn = ui:buttonNeutral({ content = text })
		return btn
	end

	LocalEvent:Listen("modeDidChange", function()
		-- update pivot when switching from one mode to the other
		if not item:GetPoint("origin") then -- if not an equipment, update Pivot
			item.Pivot = Number3(item.Width / 2, item.Height / 2, item.Depth / 2)
		end
		if currentMode == mode.edit then
			editModeBtn:select()
			placeModeBtn:unselect()
			if orientationCube ~= nil then
				orientationCube:show()
			end
			editMenu:show()
			editSubMenu:show()
			recenterBtn:show()
			placeMenu:hide()
			placeSubMenu:hide()
			placeGizmo:setObject(nil)

			palette:show()
			if currentEditSubmode ~= editSubmode.mirror then
				removeMirror()
				mirrorControls:hide()
			end
			if currentEditSubmode ~= editSubmode.select then
				selectControls:hide()
			end
		else
			editModeBtn:unselect()
			placeModeBtn:select()
			if orientationCube ~= nil then
				orientationCube:hide()
			end
			editMenu:hide()
			editSubMenu:hide()
			recenterBtn:hide()
			placeMenu:show()
			placeSubMenu:show()
			palette:hide()
			colorPicker:hide()
			mirrorControls:hide()
			selectControls:hide()
			mirrorGizmo:setObject(nil)
			selectGizmo:setObject(nil)

			placeGizmo:setObject(item)
		end
	end)

	LocalEvent:Listen("modeOrSubmodeDidChange", function()
		refreshToolsDisplay()
		-- NOTE: it may not always be necessary to call these too,
		-- playing it safe, could be improved.
		Screen.DidResize()
		refreshDrawMode()
	end)

	-- MODE MENU (+ settings)

	modeMenu = ui:frameTextBackground()

	editModeBtn = ui:buttonNeutral({ content = "✏️" })
	editModeBtn:setParent(modeMenu)
	editModeBtn.onRelease = function()
		setMode(mode.edit, nil)
	end
	editModeBtn:select()

	placeModeBtn = ui:buttonNeutral({ content = "👤" })
	placeModeBtn:setParent(modeMenu)
	placeModeBtn.onRelease = function()
		setMode(mode.points, nil)
	end

	importBtn = ui:buttonSecondary({ content = "📥" })
	importBtn:setParent(modeMenu)

	local confirmImportAlert
	importBtn.onRelease = function()
		if confirmImportAlert ~= nil then
			return
		end

		confirmImportAlert = require("alert"):create(
			"Importing a shape will replace the current item. If you want to keep this item, create a new one."
		)

		confirmImportAlert:setNegativeCallback("Cancel", function()
			confirmImportAlert:remove()
			confirmImportAlert = nil
		end)

		confirmImportAlert:setPositiveCallback("Import", function()
			confirmImportAlert:remove()
			confirmImportAlert = nil
			replaceShapeWithImportedShape()
		end)
	end

	replaceShapeWithImportedShape = function()
		if importBlocker then
			return
		end
		importBlocker = true

		File:OpenAndReadAll(function(success, fileData)
			importBlocker = false

			if not success or fileData == nil then
				return
			end

			if item ~= nil and item.Parent ~= nil then
				item:RemoveFromParent()
			end
			item = nil

			item = MutableShape(fileData) -- raises an error on failure
			item.History = true -- enable history for the edited item
			item:SetParent(World)

			customCollisionBox = nil
			if item.BoundingBox.Min ~= item.CollisionBox.Min and item.BoundingBox.Max ~= item.CollisionBox.Max then
				customCollisionBox = Box(item.CollisionBox.Min, item.CollisionBox.Max)
			end

			if currentEditSubmode == editSubmode.select then
				selectFocusShape(item)
			end

			-- dump previous standalone palette
			-- note: this function probably should have looked for a standalone palette in the imported file ; but now, after .66, it doesn't matter anymore
			standalonePalette = nil

			-- reset all colors in the palette widget
			palette:setColors(item)

			initShapes()

			fitObjectToScreen(item, nil)

			-- refresh UI
			gridEnabled = false
			refreshUndoRedoButtons()

			checkAutoSave()
		end)
	end

	screenshotBtn = ui:buttonSecondary({ content = "📷" })
	screenshotBtn:setParent(modeMenu)
	screenshotBtn.onRelease = function()
		if waitForScreenshot == true then
			return
		end
		waitForScreenshot = true

		local as = AudioSource()
		as.Sound = "gun_reload_1"
		as:SetParent(World)
		as.Volume = 0.5
		as.Pitch = 1
		as.Spatialized = false
		as:Play()
		Timer(1, function()
			as:RemoveFromParent()
			as = nil
		end)

		local whiteBg = ui:createFrame(Color.White)
		whiteBg.Width = Screen.Width
		whiteBg.Height = Screen.Height

		Timer(0.05, function()
			whiteBg:remove()
			whiteBg = nil

			-- hide UI elements before screenshot

			local mirrorDisplayed = mirrorAnchor ~= nil and mirrorAnchor.IsHidden == false
			if mirrorDisplayed then
				mirrorAnchor.IsHidden = true
			end

			local placeGizmoObject
			if placeGizmo then
				placeGizmoObject = placeGizmo:getObject()
				placeGizmo:setObject(nil)
			end

			local highlightHidden = blockHighlight.IsHidden
			blockHighlight.IsHidden = true

			local paletteIsVisible = palette:isVisible()
			palette:hide()

			ui:hide()

			local shownBodyParts = nil
			if isWearable then
				-- during the screenshot, hide avatar parts that are currently shown
				shownBodyParts = utils.findSubshapes(Player, function(s)
					return s.IsHiddenSelf == false
				end)
				for _, bp in ipairs(shownBodyParts) do
					bp.IsHiddenSelf = true
				end
			end

			local orientationCubeDisplayed = orientationCube and orientationCube:isVisible()
			if orientationCubeDisplayed then
				orientationCube:hide()
			end

			Timer(0.2, function()
				Screen:Capture(Environment.itemFullname, true --[[transparent background--]])

				-- restore UI elements after screenshot

				if mirrorDisplayed then
					mirrorAnchor.IsHidden = false
				end

				if placeGizmo then
					placeGizmo:setObject(placeGizmoObject)
				end

				if paletteIsVisible then
					palette:show()
				end

				ui:show()

				if orientationCubeDisplayed then
					orientationCube:show()
				end

				if isWearable then
					-- show avatar body parts again
					for _, bp in ipairs(shownBodyParts) do
						bp.IsHiddenSelf = false
					end
				end

				blockHighlight.IsHidden = highlightHidden

				waitForScreenshot = false
			end)
		end)
	end

	saveBtn = ui:buttonSecondary({ content = "💾" })
	saveBtn:setParent(modeMenu)
	saveBtn.label = ui:createText("✅", Color.Black, "small")
	saveBtn.label:setParent(saveBtn)

	saveBtn.onRelease = function()
		save()
	end

	if isWearable then
		placeModeBtn:disable()
		importBtn:disable()
	end

	modeMenu.parentDidResize = function(self)
		saveBtn.LocalPosition = { padding, padding, 0 }
		saveBtn.label.pos = { saveBtn.Width - saveBtn.label.Width - 1, 1, 0 }

		screenshotBtn.LocalPosition = { padding, saveBtn.LocalPosition.Y + saveBtn.Height + padding, 0 }

		importBtn.LocalPosition = { padding, screenshotBtn.LocalPosition.Y + screenshotBtn.Height + padding, 0 }
		placeModeBtn.LocalPosition = { padding, importBtn.LocalPosition.Y + importBtn.Height + padding, 0 }
		editModeBtn.LocalPosition = { padding, placeModeBtn.LocalPosition.Y + placeModeBtn.Height, 0 }

		w, h = computeContentSize(self)
		self.Width = w + padding * 2
		self.Height = h + padding * 2
		self.LocalPosition =
			{ padding + Screen.SafeArea.Left, Menu.Position.Y - self.Height - padding, 0 }

		if visibilityMenu ~= nil then
			visibilityMenu:refresh()
		end
	end

	modeMenu:parentDidResize()

	-- CAMERA CONTROLS

	recenterBtn = ui:buttonSecondary({ content = "🎯" })
	recenterBtn.onRelease = function()
		if currentMode == mode.edit then
			fitObjectToScreen(item, nil)
			-- if cameraFree == false then
			blockHighlightDirty = true
			-- end
			-- else
			-- setSatelliteCamera(settings.cameraStartPreviewRotation, nil, settings.cameraStartPreviewDistance, false)
		end
	end

	recenterBtn.place = function(self)
		self.LocalPosition = {
			editSubMenu.LocalPosition.X + editSubMenu.Width - self.Width * 3 - padding * 2,
			editSubMenu.LocalPosition.Y - self.Height - padding,
			0,
		}
	end

	-- EDIT MENU

	editMenu = ui:frameTextBackground()
	editMenuToggleBtns = {}
	editMenuToggleSelected = nil
	function editMenuToggleSelect(target)
		for _, btn in ipairs(editMenuToggleBtns) do
			btn:unselect()
		end
		target:select()
		editMenuToggleSelected = target
	end

	addBlockBtn = ui:buttonNeutral({ content = "➕" })
	table.insert(editMenuToggleBtns, addBlockBtn)
	addBlockBtn:setParent(editMenu)
	addBlockBtn.onRelease = function()
		editMenuToggleSelect(addBlockBtn)
		setMode(nil, editSubmode.add)
	end
	editMenuToggleSelect(addBlockBtn)

	removeBlockBtn = ui:buttonNeutral({ content = "➖" })
	table.insert(editMenuToggleBtns, removeBlockBtn)
	removeBlockBtn:setParent(editMenu)
	removeBlockBtn.onRelease = function()
		editMenuToggleSelect(removeBlockBtn)
		setMode(nil, editSubmode.remove)
	end

	replaceBlockBtn = ui:buttonNeutral({ content = "🖌️" })
	table.insert(editMenuToggleBtns, replaceBlockBtn)
	replaceBlockBtn:setParent(editMenu)
	replaceBlockBtn.onRelease = function()
		editMenuToggleSelect(replaceBlockBtn)
		setMode(nil, editSubmode.paint)
	end

	selectShapeBtn = ui:buttonNeutral({ content = "►" })
	table.insert(editMenuToggleBtns, selectShapeBtn)
	selectShapeBtn:setParent(editMenu)
	selectShapeBtn.onRelease = function()
		editMenuToggleSelect(selectShapeBtn)
		setMode(nil, editSubmode.select)
	end

	mirrorBtn = ui:buttonNeutral({ content = "🪞" })
	table.insert(editMenuToggleBtns, mirrorBtn)
	mirrorBtn:setParent(editMenu)
	mirrorBtn.onRelease = function()
		editMenuToggleSelect(mirrorBtn)
		setMode(nil, editSubmode.mirror)
	end
	if isWearable then
		mirrorBtn:disable()
		selectShapeBtn:disable()
	end

	pickColorBtn = ui:buttonNeutral({ content = "🧪" })
	table.insert(editMenuToggleBtns, pickColorBtn)
	pickColorBtn:setParent(editMenu)
	pickColorBtn.onRelease = function()
		if currentEditSubmode == editSubmode.pick then
			return
		end
		prePickSelectedBtn = editMenuToggleSelected
		prePickEditSubmode = currentEditSubmode
		editMenuToggleSelect(pickColorBtn)
		setMode(nil, editSubmode.pick)
	end

	paletteBtn = ui:buttonNeutral({ content = "🎨" })
	paletteBtn:setParent(editMenu)
	paletteBtn.onRelease = function()
		paletteDisplayed = not paletteDisplayed
		refreshToolsDisplay()
	end

	LocalEvent:Listen("selectedColorDidChange", function()
		paletteBtn:setColor(palette:getCurrentColor())
	end)

	editMenu.parentDidResize = function(self)
		addBlockBtn.LocalPosition = { padding, padding, 0 }
		removeBlockBtn.LocalPosition = { addBlockBtn.LocalPosition.X + addBlockBtn.Width, padding, 0 }
		replaceBlockBtn.LocalPosition = { removeBlockBtn.LocalPosition.X + removeBlockBtn.Width, padding, 0 }
		selectShapeBtn.LocalPosition = { replaceBlockBtn.LocalPosition.X + replaceBlockBtn.Width, padding, 0 }
		mirrorBtn.LocalPosition = { selectShapeBtn.LocalPosition.X + selectShapeBtn.Width + padding, padding, 0 }

		pickColorBtn.LocalPosition = { mirrorBtn.LocalPosition.X + mirrorBtn.Width + padding, padding, 0 }
		paletteBtn.LocalPosition = { pickColorBtn.LocalPosition.X + pickColorBtn.Width + padding, padding, 0 }

		w, h = computeContentSize(self)
		self.Width = w + padding * 2
		self.Height = h + padding * 2
		self.LocalPosition =
			{ Screen.Width - self.Width - padding - Screen.SafeArea.Right, padding + Screen.SafeArea.Bottom, 0 }
	end

	editMenu:parentDidResize()

	-- EDIT SUB MENU

	editSubMenu = ui:frameTextBackground()

	oneBlockBtn = ui:buttonNeutral({ content = "⚀" })
	oneBlockBtn:setParent(editSubMenu)
	oneBlockBtn.onRelease = function()
		oneBlockBtn:select()
		faceModeBtn:unselect()
		setFacemode(false)
	end
	oneBlockBtn:select()

	faceModeBtn = ui:buttonNeutral({ content = "⚅" })
	faceModeBtn:setParent(editSubMenu)
	faceModeBtn.onRelease = function()
		oneBlockBtn:unselect()
		faceModeBtn:select()
		setFacemode(true)
	end

	redoBtn = ui:buttonNeutral({ content = "↩️" })
	redoBtn:setParent(editSubMenu)
	redoBtn.onRelease = function()
		local lastRedoableShape = redoShapesStack[#redoShapesStack]
		if lastRedoableShape ~= nil and lastRedoableShape.CanRedo then
			lastRedoableShape:Redo()
			table.insert(undoShapesStack, lastRedoableShape)
			table.remove(redoShapesStack, #redoShapesStack)
			updateMirror()
			checkAutoSave()
			refreshUndoRedoButtons()
		end
	end

	undoBtn = ui:buttonNeutral({ content = "↪️" })
	undoBtn:setParent(editSubMenu)
	undoBtn.onRelease = function()
		local lastUndoableShape = undoShapesStack[#undoShapesStack]
		if lastUndoableShape ~= nil and lastUndoableShape.CanUndo then
			lastUndoableShape:Undo()
			table.remove(undoShapesStack, #undoShapesStack)
			table.insert(redoShapesStack, lastUndoableShape)
			updateMirror()
			checkAutoSave()
			refreshUndoRedoButtons()
		end
	end

	gridEnabled = false
	gridBtn = ui:buttonNeutral({ content = "𐄳" })
	gridBtn:setParent(editSubMenu)
	gridBtn.onRelease = function()
		gridEnabled = not gridEnabled
		if gridEnabled then
			gridBtn:select()
		else
			gridBtn:unselect()
		end
		refreshDrawMode()
	end

	editSubMenu.parentDidResize = function(self)
		redoBtn.LocalPosition = { padding, padding, 0 }
		undoBtn.LocalPosition = { redoBtn.LocalPosition.X + redoBtn.Width, padding, 0 }

		oneBlockBtn.LocalPosition = { undoBtn.LocalPosition.X + undoBtn.Width + padding, padding, 0 }
		faceModeBtn.LocalPosition = { oneBlockBtn.LocalPosition.X + oneBlockBtn.Width, padding, 0 }

		gridBtn.LocalPosition = { faceModeBtn.LocalPosition.X + faceModeBtn.Width + padding, padding, 0 }

		w, h = computeContentSize(self)
		self.Width = w + padding * 2
		self.Height = h + padding * 2
		self.LocalPosition = {
			Screen.Width - self.Width - padding - Screen.SafeArea.Right,
			Screen.Height - self.Height - padding - Screen.SafeArea.Top,
			0,
		}

		if recenterBtn ~= nil then
			recenterBtn:place()
		end
	end

	editSubMenu:parentDidResize()

	-- PLACE MENU

	placeMenu = ui:frameTextBackground()
	placeMenuToggleBtns = {}
	function placeMenuToggleSelect(target)
		for _, btn in ipairs(placeMenuToggleBtns) do
			btn:unselect()
		end
		target:select()
	end

	placeInHandBtn = createButton("✋", btnColor, btnColorSelected)
	table.insert(placeMenuToggleBtns, placeInHandBtn)
	placeInHandBtn:setParent(placeMenu)
	placeInHandBtn.onRelease = function()
		placeMenuToggleSelect(placeInHandBtn)
		poiActiveName = poiNameHand
		Player:EquipHat(nil)
		Player:EquipBackpack(nil)
		Player:EquipRightHand(item)

		cameraCurrentState.target = getEquipmentAttachPointWorldPosition("handheld")
		cameraCurrentState.cameraRotation = settings.cameraStartPreviewRotationHand
		cameraCurrentState.cameraDistance = 20
		cameraRefresh()
	end
	placeInHandBtn:select()

	placeAsHat = createButton("🤠", btnColor, btnColorSelected)
	table.insert(placeMenuToggleBtns, placeAsHat)
	placeAsHat:setParent(placeMenu)
	placeAsHat.onRelease = function()
		placeMenuToggleSelect(placeAsHat)
		poiActiveName = poiNameHat
		Player:EquipRightHand(nil)
		Player:EquipBackpack(nil)
		Player:EquipHat(item)

		cameraCurrentState.target = getEquipmentAttachPointWorldPosition("hat")
		cameraCurrentState.cameraRotation = settings.cameraStartPreviewRotationHat
		cameraCurrentState.cameraDistance = 20
		cameraRefresh()
	end

	placeAsBackpack = createButton("🎒", btnColor, btnColorSelected)
	table.insert(placeMenuToggleBtns, placeAsBackpack)
	placeAsBackpack:setParent(placeMenu)
	placeAsBackpack.onRelease = function()
		placeMenuToggleSelect(placeAsBackpack)
		poiActiveName = poiNameBackpack
		Player:EquipRightHand(nil)
		Player:EquipHat(nil)
		Player:EquipBackpack(item)

		cameraCurrentState.target = getEquipmentAttachPointWorldPosition("backpack")
		cameraCurrentState.cameraRotation = settings.cameraStartPreviewRotationBackpack
		cameraCurrentState.cameraDistance = 20
		cameraRefresh()
	end

	placeMenu.parentDidResize = function(self)
		placeInHandBtn.LocalPosition = { padding, padding, 0 }
		placeAsHat.LocalPosition = { placeInHandBtn.LocalPosition.X + placeInHandBtn.Width, padding, 0 }
		placeAsBackpack.LocalPosition = { placeAsHat.LocalPosition.X + placeAsHat.Width, padding, 0 }

		w, h = computeContentSize(self)
		self.Width = w + padding * 2
		self.Height = h + padding * 2
		self.LocalPosition =
			{ Screen.Width - self.Width - padding - Screen.SafeArea.Right, padding + Screen.SafeArea.Bottom, 0 }

		if placeSubMenu ~= nil then
			placeSubMenu:place()
		end
	end

	placeMenu:parentDidResize()

	-- MIRROR MENU
	mirrorControls = ui:frameTextBackground()
	mirrorControls:hide()

	mirrorGizmo = gizmo:create({
		orientation = gizmo.Orientation.World,
		moveSnap = 0.5,
		onMove = function()
			local shape = mirrorAnchor.selectedShape
			if not shape then
				return
			end
			mirrorAnchor.coords = shape:WorldToBlock(mirrorAnchor.Position) - { 0.5, 0.5, 0.5 }
		end,
	})

	rotateMirrorBtn = createButton("↻", ui_config.btnColor, ui_config.btnColorSelected)
	rotateMirrorBtn:setParent(mirrorControls)
	rotateMirrorBtn.onRelease = function()
		currentMirrorAxis = currentMirrorAxis + 1
		if currentMirrorAxis > mirrorAxes.z then
			currentMirrorAxis = mirrorAxes.x
		end
		updateMirror()
	end

	removeMirrorBtn = createButton("❌", ui_config.btnColor, ui_config.btnColorSelected)
	removeMirrorBtn:setParent(mirrorControls)
	removeMirrorBtn.onRelease = function()
		removeMirror()
		placeMirrorText:show()
		rotateMirrorBtn:hide()
		removeMirrorBtn:hide()
		mirrorControls.Width = placeMirrorText.Width + ui_config.padding * 2
		mirrorControls.LocalPosition =
			{ Screen.Width - mirrorControls.Width - ui_config.padding, editMenu.Height + 2 * ui_config.padding, 0 }
	end

	placeMirrorText = ui:createText("Click on shape to place mirror.", Color.White)
	placeMirrorText:setParent(mirrorControls)

	rotateMirrorBtn:hide()
	removeMirrorBtn:hide()

	mirrorControls.parentDidResize = function()
		placeMirrorText.LocalPosition = Number3(ui_config.padding, editMenu.Height / 2 - placeMirrorText.Height / 2, 0)
		rotateMirrorBtn.LocalPosition = Number3(ui_config.padding, ui_config.padding, 0)
		removeMirrorBtn.LocalPosition = rotateMirrorBtn.LocalPosition
			+ Number3(rotateMirrorBtn.Width + ui_config.padding, 0, 0)

		if placeMirrorText:isVisible() then
			mirrorControls.Width = placeMirrorText.Width + ui_config.padding * 2
		else
			mirrorControls.Width = ui_config.padding + (rotateMirrorBtn.Width + ui_config.padding) * 2
		end
		mirrorControls.Height = ui_config.padding * 2 + rotateMirrorBtn.Height
		mirrorControls.LocalPosition =
			{ Screen.Width - mirrorControls.Width - ui_config.padding, editMenu.Height + 2 * ui_config.padding, 0 }
	end
	mirrorControls:parentDidResize()

	-- SELECT MENU
	selectControls = ui:frameTextBackground()
	selectControls:hide()

	selectToggleBtns = {}
	function selectToggleBtnsSelect(target)
		for _, btn in ipairs(selectToggleBtns) do
			btn:unselect()
		end
		if target then
			target:select()
		end
	end

	selectGizmo = gizmo:create({ orientation = gizmo.Orientation.Local, moveSnap = 0.5 })

	addChild = ui:createText("Add shape", Color.White)
	addChild:setParent(selectControls)

	addBlockChildBtn = createButton("⚀", ui_config.btnColor, ui_config.btnColorSelected)
	addBlockChildBtn:setParent(selectControls)
	addBlockChildBtn.onRelease = function()
		if countTotalNbShapes() >= max_total_nb_shapes then
			print(string.format("Error: item can't have more than %d shapes.", max_total_nb_shapes))
			return
		end
		local s = MutableShape()
		s.History = true -- enable history for the edited item
		s.Palette = item.Palette -- shared palette with root shape
		s.Physics = PhysicsMode.TriggerPerBlock
		s.CollisionGroups = collisionGroup_item
		s.isItem = true
		s:AddBlock(palette:getCurrentIndex(), 0, 0, 0)
		s.Pivot = Number3(0.5, 0.5, 0.5)
		s:SetParent(focusShape)
		-- Spawn next to the parent
		s.Position = focusShape.Position - Number3(focusShape.Width / 2 + 2, 0, 0)
		table.insert(shapes, s)
		selectFocusShape(s)

		checkAutoSave()
	end

	importChildBtn = createButton("📥 Import", ui_config.btnColor, ui_config.btnColorSelected)
	importChildBtn:setParent(selectControls)
	importChildBtn.onRelease = function()
		if countTotalNbShapes() >= max_total_nb_shapes then
			print(string.format("Error: item can't have more than %d shapes.", max_total_nb_shapes))
			return
		end

		if importBlocker then
			return
		end
		importBlocker = true

		File:OpenAndReadAll(function(success, fileData)
			importBlocker = false

			if not success or fileData == nil then
				return
			end

			child = MutableShape(fileData) -- raises an error on failure
			child:SetParent(focusShape)

			item.Palette:Merge(child, { remap = true, recurse = true }) -- merge & remap each child shape to use item.Palette

			-- Spawn next to the parent
			child.Position = child.Position - Number3(focusShape.Width / 2 + child.Width * 2, 0, 0)

			item:Recurse(function(s)
				s.History = true -- enable history for the edited item
				s.Physics = PhysicsMode.TriggerPerBlock
				s.CollisionGroups = collisionGroup_item
				s.isItem = true
				table.insert(shapes, s)
			end, { includeRoot = true })

			selectFocusShape(child)

			-- refresh UI
			gridEnabled = false
			refreshUndoRedoButtons()

			checkAutoSave()
		end)
	end

	removeShapeBtn = createButton("➖ Remove Shape", ui_config.btnColor, ui_config.btnColorSelected)
	removeShapeBtn:setParent(selectControls)
	removeShapeBtn.onRelease = function()
		if not focusShape then
			return
		end
		for k, s in ipairs(shapes) do
			if s == focusShape then
				table.remove(shapes, k)
			end
		end
		focusShape:RemoveFromParent()
		selectFocusShape()
		removeShapeBtn:hide()

		checkAutoSave()
	end

	local nameInput = ui:createTextInput("", "Object Name")
	nameInput:setParent(selectControls)
	nameInput.onTextChange = function(o)
		focusShape.Name = o.Text
	end

	changePivotBtn = createButton("Change Pivot", ui_config.btnColor, ui_config.btnColorSelected)
	changePivotBtn:setParent(selectControls)

	local pivotObject = Object()

	changePivotBtn.onRelease = function()
		if not isModeChangePivot then
			moveShapeBtn:disable()
			rotateShapeBtn:disable()
			removeShapeBtn:disable()
			addBlockChildBtn:disable()
			importChildBtn:disable()

			pivotObject:SetParent(focusShape)

			item:Recurse(function(s)
				disableObject(s, s ~= focusShape) -- hide all except focus shape
			end, { includeRoot = true })

			selectGizmo:setMode(gizmo.Mode.Move)
			selectGizmo:setOrientation(gizmo.Orientation.Local)

			local pivot = focusShape.Pivot
			changePivotBtn.Text = string.format("(%.1f, %.1f, %.1f) ✅", pivot.X, pivot.Y, pivot.Z)

			selectGizmo:setOnMove(function(_)
				local newPivot = focusShape.Pivot + pivotObject.LocalPosition
				local snap = 0.5
				newPivot.X = math.floor(newPivot.X / snap) * snap
				newPivot.Y = math.floor(newPivot.Y / snap) * snap
				newPivot.Z = math.floor(newPivot.Z / snap) * snap

				changePivotBtn.Text = string.format("(%.1f, %.1f, %.1f) ✅", newPivot.X, newPivot.Y, newPivot.Z)
			end)

			pivotObject.LocalPosition = Number3.Zero
			pivotObject.LocalRotation = Number3.Zero

			selectGizmo:setObject(pivotObject)
		else
			moveShapeBtn:enable()
			rotateShapeBtn:enable()
			removeShapeBtn:enable()
			addBlockChildBtn:enable()
			importChildBtn:enable()

			selectGizmo:setOnMove(nil)

			local newPivot = focusShape.Pivot + pivotObject.LocalPosition
			local snap = 0.5
			newPivot.X = math.floor(newPivot.X / snap) * snap
			newPivot.Y = math.floor(newPivot.Y / snap) * snap
			newPivot.Z = math.floor(newPivot.Z / snap) * snap

			if newPivot ~= focusShape.Pivot then
				focusShape.Pivot = newPivot
				focusShape.Position = pivotObject.Position
			end

			item:Recurse(function(s)
				disableObject(s, false)
			end, { includeRoot = true })

			if moveShapeBtn.selected then
				selectGizmo:setObject(focusShape)
				selectGizmo:setMode(gizmo.Mode.Move)
				selectGizmo:setOrientation(gizmo.Orientation.Local)
			elseif rotateShapeBtn.selected then
				selectGizmo:setObject(focusShape)
				selectGizmo:setMode(gizmo.Mode.Rotate)
				selectGizmo:setOrientation(gizmo.Orientation.Local)
			else
				selectGizmo:setObject(nil)
			end

			changePivotBtn.Text = "Change Pivot"
		end
		isModeChangePivot = not isModeChangePivot
	end

	moveShapeBtn = createButton("⇢", ui_config.btnColor, ui_config.btnColorSelected)
	moveShapeBtn:setParent(selectControls)
	table.insert(selectToggleBtns, moveShapeBtn)
	moveShapeBtn.onRelease = function()
		if selectGizmo.object and selectGizmo.mode == gizmo.Mode.Move then
			selectToggleBtnsSelect(nil)
			selectGizmo:setObject(nil)
		else
			selectToggleBtnsSelect(moveShapeBtn)
			selectGizmo:setObject(focusShape)
			selectGizmo:setMode(gizmo.Mode.Move)
		end
	end

	rotateShapeBtn = createButton("↻", ui_config.btnColor, ui_config.btnColorSelected)
	rotateShapeBtn:setParent(selectControls)
	table.insert(selectToggleBtns, rotateShapeBtn)
	rotateShapeBtn.onRelease = function()
		if selectGizmo.object and selectGizmo.mode == gizmo.Mode.Rotate then
			selectToggleBtnsSelect(nil)
			selectGizmo:setObject(nil)
		else
			selectToggleBtnsSelect(rotateShapeBtn)
			selectGizmo:setObject(focusShape)
			selectGizmo:setMode(gizmo.Mode.Rotate)
		end
	end

	selectShapeText = ui:createText("or Select a shape.", Color.White)
	selectShapeText:setParent(selectControls)

	-- Update Collision Box Menu
	updateCollider = function()
		local minPos = colliderMinObject.Position - item:BlockToWorld(0, 0, 0)
		local maxPos = colliderMaxObject.Position - item:BlockToWorld(0, 0, 0)
		customCollisionBox = Box(minPos, maxPos)
		collider:resize(customCollisionBox.Max - customCollisionBox.Min)
		collider.Position = item:BlockToWorld(customCollisionBox.Min) - Number3(0.125, 0.125, 0.125)
		checkAutoSave()
	end

	setColliderBtn = createButton("Set Collision Box", ui_config.btnColor, ui_config.btnColorSelected)
	setColliderBtn:setParent(selectControls)
	setColliderBtn.onRelease = function()
		selectControls:hide()

		collisionBoxMenu:parentDidResize()
		collisionBoxMenu:show()

		if not customCollisionBox then
			customCollisionBox = Box(item.CollisionBox.Min, item.CollisionBox.Max)
		end
		if collider then
			collider:RemoveFromParent()
		end
		collider = box_outline:create(customCollisionBox.Max - customCollisionBox.Min, 0.25)
		collider:SetParent(World)
		collider.Position = item:BlockToWorld(customCollisionBox.Min) - Number3(0.125, 0.125, 0.125)

		if not colliderMinObject then
			colliderMinObject = Object()
			colliderMinObject:SetParent(World)
			colliderMaxObject = Object()
			colliderMaxObject:SetParent(World)
		end
		colliderMinObject.Position = item:BlockToWorld(customCollisionBox.Min)
		colliderMinGizmo:setObject(colliderMinObject)
		colliderMaxObject.Position = item:BlockToWorld(customCollisionBox.Max)
		colliderMaxGizmo:setObject(colliderMaxObject)
	end

	collisionBoxMenu = ui:frameTextBackground()
	collisionBoxMenu:hide()

	editingCollisionBoxText = ui:createText("Editing Collision Box...", Color.White)
	editingCollisionBoxText:setParent(collisionBoxMenu)

	confirmColliderBtn = createButton("✅", ui_config.btnColor, ui_config.btnColorSelected)
	confirmColliderBtn:setParent(collisionBoxMenu)
	confirmColliderBtn.onRelease = function()
		if not collider then
			return
		end
		collisionBoxMenu:hide()
		selectControls:show()
		collider:RemoveFromParent()
		collider = nil
		colliderMinGizmo:setObject(nil)
		colliderMaxGizmo:setObject(nil)
	end

	collisionBoxMenu.parentDidResize = function()
		collisionBoxMenu.Width = editingCollisionBoxText.Width + confirmColliderBtn.Width + padding * 3
		collisionBoxMenu.Height = editMenu.Height
		editingCollisionBoxText.LocalPosition =
			Number3(padding, collisionBoxMenu.Height / 2 - editingCollisionBoxText.Height / 2, 0)
		confirmColliderBtn.LocalPosition = Number3(editingCollisionBoxText.Width + 2 * padding, padding, 0)
		collisionBoxMenu.LocalPosition =
			Number3(Screen.Width - padding - collisionBoxMenu.Width, editMenu.Height + 2 * padding, 0)
	end

	selectControlsRefresh = function()
		if currentEditSubmode ~= editSubmode.select then
			return
		end

		if not currentEditSubmode or not focusShape then
			selectShapeText:show()
			setColliderBtn:show()
			addChild:hide()
			addBlockChildBtn:hide()
			importChildBtn:hide()
			removeShapeBtn:hide()
			moveShapeBtn:hide()
			rotateShapeBtn:hide()
			nameInput:hide()
			changePivotBtn:hide()
			selectControls:parentDidResize()
			return
		end

		selectShapeText:hide()
		setColliderBtn:hide()

		addChild:show()
		addBlockChildBtn:show()
		importChildBtn:show()

		-- if root, can't remove, move or rotate
		local funcSubShapesControls = focusShape == item and "hide" or "show"
		if funcSubShapesControls == "show" then
			nameInput.Text = focusShape.Name or ""
			selectGizmo:setObject(focusShape)
			if selectGizmo.mode == gizmo.Mode.Move then
				selectToggleBtnsSelect(moveShapeBtn)
			else
				selectToggleBtnsSelect(rotateShapeBtn)
			end
		end
		removeShapeBtn[funcSubShapesControls](removeShapeBtn)
		moveShapeBtn[funcSubShapesControls](moveShapeBtn)
		rotateShapeBtn[funcSubShapesControls](rotateShapeBtn)
		nameInput[funcSubShapesControls](nameInput)
		changePivotBtn[funcSubShapesControls](changePivotBtn)

		selectControls:parentDidResize()
	end

	selectControls.parentDidResize = function()
		local padding = ui_config.padding
		selectShapeText.LocalPosition = Number3(padding * 1.5, editMenu.Height / 2 - selectShapeText.Height / 2, 0)
		setColliderBtn.LocalPosition = Number3(padding, addBlockChildBtn.Height + 2 * padding, 0)
		addChild.LocalPosition = Number3(padding, editMenu.Height / 2 - selectShapeText.Height / 2, 0)
		addBlockChildBtn.LocalPosition = Number3(addChild.LocalPosition.X + addChild.Width + padding, padding, 0)
		importChildBtn.LocalPosition = Number3(
			addBlockChildBtn.LocalPosition.X + addBlockChildBtn.Width + padding,
			addBlockChildBtn.LocalPosition.Y,
			0
		)
		moveShapeBtn.LocalPosition =
			Number3(padding, addBlockChildBtn.LocalPosition.Y + addBlockChildBtn.Height + padding, 0)
		rotateShapeBtn.LocalPosition =
			Number3(moveShapeBtn.LocalPosition.X + moveShapeBtn.Width, moveShapeBtn.LocalPosition.Y, 0)
		removeShapeBtn.LocalPosition =
			Number3(rotateShapeBtn.LocalPosition.X + rotateShapeBtn.Width + padding, rotateShapeBtn.LocalPosition.Y, 0)
		nameInput.LocalPosition = Number3(padding, moveShapeBtn.LocalPosition.Y + moveShapeBtn.Height + padding, 0)
		changePivotBtn.LocalPosition = Number3(padding, nameInput.LocalPosition.Y + nameInput.Height + padding, 0)

		local width = 0
		local height = padding
		if selectShapeText:isVisible() then
			width = math.max(width, setColliderBtn.Width)
			height = height + (addBlockChildBtn.Height + padding) * 2
		end
		if addBlockChildBtn:isVisible() then
			width = math.max(width, addChild.Width + padding + importChildBtn.Width + padding + addBlockChildBtn.Width)
			height = height + addBlockChildBtn.Height + padding
		end
		if moveShapeBtn:isVisible() then
			width = math.max(width, removeShapeBtn.Width + moveShapeBtn.Width + rotateShapeBtn.Width + padding)
			height = height + moveShapeBtn.Height + nameInput.Height + changePivotBtn.Height + 3 * padding
		end

		nameInput.Width = width
		changePivotBtn.Width = width
		width = width + 2 * padding
		selectControls.Width = width
		selectControls.Height = height
		selectControls.LocalPosition =
			{ Screen.Width - selectControls.Width - padding, editMenu.Height + 2 * padding, 0 }
	end
	selectControlsRefresh()

	-- PLACE SUB MENU

	placeSubMenu = ui:frameTextBackground()
	placeSubMenuToggleBtns = {}
	function placeSubMenuToggleSelect(target)
		for _, btn in ipairs(placeSubMenuToggleBtns) do
			btn:unselect()
		end
		if target then
			target:select()
		end
	end

	placeGizmo = gizmo:create({
		orientation = gizmo.Orientation.Local,
		moveSnap = 0.5,
		onMove = function()
			savePOI()
		end,
		onRotate = function()
			savePOI()
		end,
	})

	moveBtn = createButton("⇢", btnColor, btnColorSelected)
	table.insert(placeSubMenuToggleBtns, moveBtn)
	moveBtn:setParent(placeSubMenu)
	moveBtn.onRelease = function()
		setMode(nil, pointsSubmode.move)
		if placeGizmo.object and placeGizmo.mode == gizmo.Mode.Move then
			placeSubMenuToggleSelect(nil)
			placeGizmo:setObject(nil)
		else
			placeSubMenuToggleSelect(moveBtn)
			placeGizmo:setObject(item)
			placeGizmo:setMode(gizmo.Mode.Move)
			placeGizmo:setMoveSnap(0.5)
		end
	end
	moveBtn:select()
	placeGizmo:setMode(gizmo.Mode.Move)

	rotateBtn = createButton("↻", btnColor, btnColorSelected)
	table.insert(placeSubMenuToggleBtns, rotateBtn)
	rotateBtn:setParent(placeSubMenu)
	rotateBtn.onRelease = function()
		setMode(nil, pointsSubmode.rotate)
		if placeGizmo.object and placeGizmo.mode == gizmo.Mode.Rotate then
			placeSubMenuToggleSelect(nil)
			placeGizmo:setObject(nil)
		else
			placeSubMenuToggleSelect(rotateBtn)
			placeGizmo:setObject(item)
			placeGizmo:setMode(gizmo.Mode.Rotate)
			placeGizmo:setRotateSnap(math.pi / 16)
		end
	end

	resetBtn = createButton("Reset", btnColor, btnColorSelected)
	resetBtn:setParent(placeSubMenu)
	resetBtn.onRelease = function()
		item:AddPoint(poiActiveName)

		if poiActiveName == poiNameHand then
			Player:EquipRightHand(item)
		elseif poiActiveName == poiNameHat then
			Player:EquipHat(item)
		elseif poiActiveName == poiNameBackpack then
			Player:EquipBackpack(item)
		end
	end

	placeSubMenu.place = function(self)
		moveBtn.LocalPosition = { padding, padding, 0 }
		rotateBtn.LocalPosition = { moveBtn.LocalPosition.X + moveBtn.Width, padding, 0 }
		resetBtn.LocalPosition = { rotateBtn.LocalPosition.X + rotateBtn.Width + padding, padding, 0 }

		w, h = computeContentSize(self)
		self.Width = w + padding * 2
		self.Height = h + padding * 2
		self.LocalPosition = {
			Screen.Width - self.Width - padding - Screen.SafeArea.Right,
			placeMenu.LocalPosition.Y + placeMenu.Height + padding,
			0,
		}
	end

	placeSubMenu:place()
end -- ui_init end

function computeContentSize(self)
	return computeContentWidth(self), computeContentHeight(self)
end

function computeContentHeight(self)
	local max = nil
	local min = nil
	for _, child in pairs(self.children) do
		if child:isVisible() then
			if min == nil or min > child.LocalPosition.Y then
				min = child.LocalPosition.Y
			end
			if max == nil or max < child.LocalPosition.Y + child.Height then
				max = child.LocalPosition.Y + child.Height
			end
		end
	end
	if max == nil then
		return 0
	end
	return max - min
end

function computeContentWidth(self)
	local max = nil
	local min = nil
	for _, child in pairs(self.children) do
		if child:isVisible() then
			if min == nil or min > child.LocalPosition.X then
				min = child.LocalPosition.X
			end
			if max == nil or max < child.LocalPosition.X + child.Width then
				max = child.LocalPosition.X + child.Width
			end
		end
	end
	if max == nil then
		return 0
	end
	return max - min
end

function post_item_load()
	initClientFunctions()
	setFacemode(false)
	refreshUndoRedoButtons()

	-- gizmos
	orientationCube = require("orientationcube")
	orientationCube:init()
	orientationCube:setLayer(6)

	cameraCurrentState = cameraStates.item

	initShapes = function()
		-- as of 0.0.66, the standalone palette inside item's 3zh isn't used anymore
		if standalonePalette ~= nil then
			item.Palette:Merge(standalonePalette) -- merge it so that these colors are still displayed in the editor
			item.Palette:Merge(item, { remap = true, recurse = true }) -- merge & remap each child shape to use item.Palette
		end

		-- initialize item and its sub-shapes (physics mode, shared palette, etc.)
		shapes = {}
		item:Recurse(function(s)
			if typeof(s) == "MutableShape" then
				s.Physics = PhysicsMode.TriggerPerBlock
				s.CollisionGroups = collisionGroup_item
				s.isItem = true
				s.History = true -- enable history for the edited item
				s.Palette = item.Palette -- shared palette with root shape
				table.insert(shapes, s)
			end

			if not isWearable then
				return
			end

			s.Pivot = s:GetPoint("origin").Coords

			if itemCategory == "hair" then
				bodyPartToWearablePart.Head = s
			elseif itemCategory == "jacket" then
				if s:GetParent() == World and s.ChildrenCount == 1 then
					bodyPartToWearablePart.Body = s
				elseif s:GetParent() ~= World and s.ChildrenCount == 1 then
					bodyPartToWearablePart.RightArm = s
				elseif s:GetParent() ~= World and s.ChildrenCount == 0 then
					bodyPartToWearablePart.LeftArm = s
				end
			elseif itemCategory == "pants" then
				if s.ChildrenCount == 1 then
					bodyPartToWearablePart.RightLeg = s
				else
					bodyPartToWearablePart.LeftLeg = s
				end
			elseif itemCategory == "boots" then
				if s.ChildrenCount == 1 then
					bodyPartToWearablePart.RightFoot = s
				else
					bodyPartToWearablePart.LeftFoot = s
				end
			else
				local str = "Item category is not supported, itemCategory is " .. itemCategory
				error(str, 2)
			end
		end, { includeRoot = true })
	end

	initShapes()

	local SHOW_FOCUS_MODE_BUTTONS = false
	if SHOW_FOCUS_MODE_BUTTONS then
		-- Focus mode buttons
		x = Screen.Width - 205
		y = Screen.Height / 2 - 100
		local toggleFocusBtns = {}
		for i = 1, focusMode.max do
			local btn = ui:createButton(200, 50) -- TODO: this signature doesn't exist anymore?
			btn.LocalPosition = Number3(x, y - (i - 1) * 55, 0)
			btn.Text = focusModeName[i]
			btn.onRelease = function()
				if not focusShape then
					return
				end
				if i == focusMode.othersVisible then
					setSelfAndDescendantsHiddenSelf(item, false)
					refreshDrawMode()
				elseif i == focusMode.othersTransparent then
					setSelfAndDescendantsHiddenSelf(item, false)
					refreshDrawMode()
					focusShape.PrivateDrawMode = 0
				elseif i == focusMode.othersHidden then
					setSelfAndDescendantsHiddenSelf(item, true)
					focusShape.IsHiddenSelf = false
				end
			end
			table.insert(toggleFocusBtns, btn)
		end
		-- local toggleFocusMode = ui:createToggle(toggleFocusBtns)
		selectFocusShape(item)
	end

	local colorPickerConfig = {
		closeBtnColor = ui_config.btnColor,
		extraPadding = true,
	}
	colorPicker = colorPickerModule:create(colorPickerConfig)
	colorPicker:hide()

	palette = require("palette"):create(ui, ui_config.btnColor)
	palette:setColors(item)

	colorPicker.didPickColor = function(_, color)
		local index = palette:getCurrentIndex()

		-- root shape palette is shared with children shapes & palette widget
		local prevAlpha = item.Palette[index].Color.A
		local colorInUse = item.Palette[index].BlocksCount > 0

		palette:setSelectedColor(color)

		-- models need to be refreshed only if going from opaque (alpha 255) to transparent (alpha <255), and vice-versa
		if colorInUse and color.A ~= prevAlpha and (color.A == 255 or prevAlpha == 255) then
			item:Recurse(function(o)
				if o.RefreshModel ~= nil then
					o:RefreshModel()
				end
			end, { includeRoot = true })
		end

		checkAutoSave()
	end

	colorPicker.didClose = function()
		colorPickerDisplayed = false
	end

	palette.didAdd = function(_, color)
		colorPicker:setColor(color)
		if not colorPickerDisplayed then
			colorPickerDisplayed = true
			refreshToolsDisplay()
		end
		checkAutoSave()
		updatePalettePosition()
	end

	palette.didRefresh = function(_)
		updatePalettePosition()
	end

	palette.didChangeSelection = function(_, color)
		LocalEvent:Send("selectedColorDidChange")
		colorPicker:setColor(color)
	end
	palette.requiresEdit = function(_, _, color)
		colorPickerDisplayed = not colorPickerDisplayed
		if colorPickerDisplayed then
			colorPicker:setColor(color)
		end
		refreshToolsDisplay()
	end

	updatePalettePosition = function()
		palette.LocalPosition = {
			Screen.Width - palette.Width - ui_config.padding - Screen.SafeArea.Left,
			editMenu.LocalPosition.Y + editSubMenu.Height + ui_config.padding,
			0,
		}
		colorPicker.LocalPosition =
			Number3(palette.LocalPosition.X - colorPicker.Width - ui_config.padding, palette.LocalPosition.Y, 0)
	end

	LocalEvent:Send("selectedColorDidChange")
	updatePalettePosition()

	setMode(mode.edit, editSubmode.add)
	Screen.DidResize()

	countTotalNbShapes = function()
		local nbShapes = 0
		item:Recurse(function(_)
			nbShapes = nbShapes + 1
		end, { includeRoot = true })
		return nbShapes
	end

	fitObjectToScreen(item, settings.cameraStartRotation) -- sets cameraCurrentState.target
	refreshBlockHighlight()

	-- if equipment, show preview buttons
	if not isWearable then
		return
	end

	-- T-pose
	for _, p in ipairs(bodyParts) do
		if p == "RightArm" or p == "LeftArm" or p == "RightHand" or p == "LeftHand" then
			Player[p].Rotation = Number3(0, 0, 0)
		end
		Player[p].IgnoreAnimations = true
		Player[p].Physics = PhysicsMode.TriggerPerBlock
	end
	Player.Physics = PhysicsMode.Disabled

	visibilityMenu = ui:frameTextBackground()

	local onlyItemBtn = ui:button({ content="⚅" })
	itemPlusBodyPartBtn = ui:button({ content="✋" })
	local itemPlusAvatarBtn = ui:button({ content="👤" })

	-- Button for item alone
	onlyItemBtn:setParent(visibilityMenu)
	onlyItemBtn.onRelease = function(_)
		-- update state of the 3 preview buttons
		onlyItemBtn:select()
		itemPlusBodyPartBtn:unselect()
		itemPlusAvatarBtn:unselect()

		-- update avatar visibility
		currentWearablePreviewMode = wearablePreviewMode.hide
		playerUpdateVisibility(isWearable, currentWearablePreviewMode)

		-- update wearable item position
		updateWearableShapesPosition()
	end
	onlyItemBtn:onRelease()

	-- Button for item and parent body part
	itemPlusBodyPartBtn:setParent(visibilityMenu)
	itemPlusBodyPartBtn.onRelease = function(_)
		-- update state of the 3 preview buttons
		onlyItemBtn:unselect()
		itemPlusBodyPartBtn:select()
		itemPlusAvatarBtn:unselect()

		-- update avatar visibility
		currentWearablePreviewMode = wearablePreviewMode.bodyPart
		playerUpdateVisibility(isWearable, currentWearablePreviewMode)

		-- update wearable item position
		updateWearableShapesPosition()
	end

	-- Button for item and full avatar
	itemPlusAvatarBtn:setParent(visibilityMenu)
	itemPlusAvatarBtn.onRelease = function(_)
		-- update state of the 3 preview buttons
		onlyItemBtn:unselect()
		itemPlusBodyPartBtn:unselect()
		itemPlusAvatarBtn:select()

		-- update avatar visibility
		currentWearablePreviewMode = wearablePreviewMode.fullBody
		playerUpdateVisibility(isWearable, currentWearablePreviewMode)

		-- update wearable item position
		updateWearableShapesPosition()
	end

	visibilityMenu.refresh = function(self)
		local padding = ui_config.padding

		onlyItemBtn.pos = { padding, padding, 0 }
		itemPlusBodyPartBtn.pos = onlyItemBtn.pos + { 0, onlyItemBtn.Height + padding, 0 }
		itemPlusAvatarBtn.pos = itemPlusBodyPartBtn.pos + { 0, itemPlusBodyPartBtn.Height + padding, 0 }

		w, h = computeContentSize(self)
		self.Width = w + padding * 2
		self.Height = h + padding * 2
		self.pos = modeMenu.pos + { modeMenu.Width + padding, modeMenu.Height - self.Height, 0 }
	end

	visibilityMenu:refresh()

	Player:SetParent(World)
	Player.Scale = 1
	-- remove current equipment
	Player.Avatar:loadEquipment({ type = itemCategory })

	-- need timer so that everything is loaded
	Timer(1, function()
		itemPlusBodyPartBtn:onRelease()
	end)
end

function clamp(value, min, max)
	return math.min(math.max(value, min), max)
end
