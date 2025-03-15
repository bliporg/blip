local worldEditor = {}

local sfx = require("sfx")
local ease = require("ease")
local ui = require("uikit")
local ambience = require("ambience")
local worldEditorCommon = require("world_editor_common")
local ccc = require("ccc")

-- constants
local NEW_OBJECT_MAX_DISTANCE = 50
local THIRD_PERSON_CAMERA_DISTANCE = 40

local defaultAmbience = { 
	sky = { 
		skyColor = {0,168,255}, 
		horizonColor = {137,222,229}, 
		abyssColor = {76,144,255}, 
		lightColor = {142,180,204}, 
		lightIntensity = 0.6 
	}, 
	fog = { 
		color = {19,159,204}, 
		near = 300, 
		far = 700, 
		lightAbsorbtion = 0.4 
	}, 
	sun = { 
		color = {255,247,204}, 
		intensity = 1.0, 
		rotation = {1.061161,3.089219,0.0} 
	}, 
	ambient = { 
		skyLightFactor = 0.1, 
		dirLightFactor = 0.2 
	} 
}

function requireSkybox()
	local skybox = {}
	skybox.load = function(config, func)
		local defaultConfig = {
			scale = 1000,
			url = "https://e7.pngegg.com/pngimages/57/621/png-clipart-skybox-texture-mapping-panorama-others-texture-atmosphere.png",
		}

		local url = config.url or defaultConfig.url
		local scale = config.scale or defaultConfig.scale
		if func == nil then
			func = function(obj)
				obj:SetParent(Camera)
				obj.Tick = function(self)
					self.Rotation = Rotation(0, 0, 0)
					self.Position = Camera.Position - Number3(self.Scale.X, self.Scale.Y, -self.Scale.Z) / 2
				end
			end
		end

		HTTP:Get(url, function(data)
			if data.StatusCode ~= 200 then
				error("Error: " .. data.StatusCode)
			end

			local image = data.Body
			local object = Object()

			object.Scale = scale

			local back = Quad()
			back.Image = image
			back.Size = Number2(1, 1)
			back.Tiling = Number2(0.25, 0.3335)
			back.Offset = Number2(0, 0.3335)
			back:SetParent(object)
			back.IsUnlit = true

			local left = Quad()
			left.Image = image
			left.Size = Number2(1, 1)
			left.Tiling = Number2(0.25, 0.3335)
			left.Offset = Number2(0.25, 0.3335)
			left.Position = back.Position + Number3(1, 0, 0)
			left.Rotation.Y = math.pi / 2
			left:SetParent(object)
			left.IsUnlit = true

			local front = Quad()
			front.Image = image
			front.Size = Number2(1, 1)
			front.Tiling = Number2(0.25, 0.3335)
			front.Offset = Number2(0.5, 0.3335)
			front.Position = back.Position + Number3(1, 0, -1)
			front.Rotation.Y = math.pi
			front:SetParent(object)
			front.IsUnlit = true

			local right = Quad()
			right.Image = image
			right.Size = Number2(1, 1)
			right.Tiling = Number2(0.25, 0.3335)
			right.Offset = Number2(0.75, 0.3335)
			right.Position = back.Position + Number3(0, 0, -1)
			right.Rotation.Y = -math.pi / 2
			right:SetParent(object)
			right.IsUnlit = true

			local down = Quad()
			down.Image = image
			down.Size = Number2(1, 1 * 1.001)
			down.Tiling = Number2(0.25, 0.3335)
			down.Offset = Number2(0.25, 0.6668)
			down.Position = back.Position + Number3(-1 * 0.001, 1 * 0.002, 0)
			down.Rotation = Rotation(math.pi / 2, math.pi / 2, 0)
			down:SetParent(object)
			down.IsUnlit = true

			local up = Quad()
			up.Image = image
			up.Size = Number2(1, 1)
			up.Tiling = Number2(0.25, 0.3335)
			up.Offset = Number2(0.25, 0)
			up.Position = back.Position + Number3(1, 1, 0)
			up.Rotation = Rotation(-math.pi / 2, math.pi / 2, 0)
			up:SetParent(object)
			up.IsUnlit = true

			object:SetParent(Camera)
			object.Tick = function(self)
				self.Rotation:Set(0, 0, 0)
				self.Position = Camera.Position - Number3(self.Scale.X, self.Scale.Y, -self.Scale.Z) / 2
			end

			func(object)
		end)
	end
	return skybox
end

local skybox = requireSkybox()

-- Import common events and constants from common module
local events = worldEditorCommon.events

local uuidv4 = worldEditorCommon.uuidv4

local loadWorld = worldEditorCommon.loadWorld
local maps = worldEditorCommon.maps

local theme = require("uitheme").current
local padding = theme.padding

local objects = {}
local objectsByUUID = {}
local map
local mapIndex = 1
local mapName

local CameraMode = {
	FREE = 1,
	THIRD_PERSON = 2,
	THIRD_PERSON_FLYING = 3,
}
local cameraMode
local camDirY, camDirX = 0, 0
local cameraSpeed = Number3.Zero

-- UI COMPONENTS
local ambienceBtn
local ambiencePanel
local cameraBtn
local transformGizmo
local objectInfoFrame
local physicsBtn

local trail

local TRAIL_COLOR = Color.White
local OBJECTS_COLLISION_GROUP = CollisionGroups(7)

local function setCameraMode(mode)
	if cameraMode == mode then
		return
	end
	cameraMode = mode
	if mode == CameraMode.THIRD_PERSON then
		-- Camera:SetModeThirdPerson()
		Camera:SetModeFree()
		ccc:set({
			target = Player,
			cameraColliders = OBJECTS_COLLISION_GROUP,
		})
		Player.Physics = PhysicsMode.Dynamic
		Player.IsHidden = false
		if trail then
			trail:show()
		end
	else
		ccc:unset()
		Camera:SetModeFree()
		Player.Physics = PhysicsMode.Disabled
		Player.IsHidden = true
		if trail then
			trail:hide()
		end
	end
end

local function getObjectInfoTable(obj)
	return {
		uuid = obj.uuid,
		fullname = obj.fullname,
		Position = obj.Position or Number3.Zero,
		Rotation = obj.Rotation or Number3.Zero,
		Scale = obj.Scale or Number3.One,
		Name = obj.Name or obj.fullname,
		Physics = obj.realPhysicsMode or PhysicsMode.StaticPerBlock,
	}
end

-- STATE

local pressedObject
local selectedObject

local states = {
	LOADING = 1,
	PICK_WORLD = 2,
	DEFAULT = 4,
	GALLERY = 5,
	SPAWNING_OBJECT = 6,
	PLACING_OBJECT = 7,
	OBJECT_SELECTED = 8,
	DUPLICATE_OBJECT = 9,
	DESTROY_OBJECT = 10,
}

local setState
local state

local function clearWorld()
	Player:RemoveFromParent()
	if map then
		map:RemoveFromParent()
		map = nil
	end
	for _, o in pairs(objects) do
		o:RemoveFromParent()
	end
	objects = {}
	objectsByUUID = {}
	mapName = nil
	
	worldEditorCommon.updateAmbience(defaultAmbience)
	require("ai_ambience"):loadGeneration(defaultAmbience)
end

local function setObjectPhysicsMode(obj, physicsMode)
	if not obj then
		print("⚠️ can't set physics mode on nil object")
		return
	end
	obj.realPhysicsMode = physicsMode
	obj:Recurse(function(o)
		if o.Physics == nil then
			return
		end
		-- If disabled, keep trigger to allow raycast
		if physicsMode == PhysicsMode.Disabled then
			o.Physics = PhysicsMode.Trigger
		else
			o.Physics = physicsMode
		end
	end, { includeRoot = true })

	worldEditorCommon.updateObject({
		uuid = obj.uuid,
		physics = physicsMode,
	})
end

function objectHitTest(pe)
	local impact = pe:CastRay(OBJECTS_COLLISION_GROUP)
	local obj = impact.Object
	-- obj can be a sub-Shape of an object,
	-- find first parent node that's editable:
	while obj and not obj.isEditable do
		obj = obj:GetParent()
	end
	return obj
end

local didTryPickObject = false
local pickObjectCameraState = {}
function tryPickObjectDown(pe)
	didTryPickObject = true
	-- saving camera state, to avoid picking object after
	-- a rotation or position change between down and up
	pickObjectCameraState.pos = Camera.Position:Copy()
	pickObjectCameraState.rot = Camera.Rotation:Copy()
	local obj = objectHitTest(pe)
	pressedObject = obj
end

function tryPickObjectUp(pe)
	if didTryPickObject == false then
		return
	end
	if math.abs(Camera.Rotation:Angle(pickObjectCameraState.rot)) > 0 then
		return
	end

	didTryPickObject = false

	if pressedObject == nil then
		setState(states.DEFAULT)
		return
	end
	local obj = objectHitTest(pe)
	if obj ~= pressedObject then
		setState(states.DEFAULT)
		return
	end
	pressedObject = nil
	setState(states.OBJECT_SELECTED, obj)
end

local setObjectAlpha = function(obj, alpha)
	obj:Recurse(function(o)
		if not o.Palette then
			return
		end
		if not o.savedAlpha then
			o.savedAlpha = {}
			for k = 1, #o.Palette do
				local c = o.Palette[k]
				o.savedAlpha[k] = c.Color.Alpha / 255
			end
		end
		for k = 1, #o.Palette do
			local c = o.Palette[k]
			c.Color.Alpha = o.savedAlpha[k] * alpha
		end
		o:RefreshModel()
	end, { includeRoot = true })
end

local freezeObject = function(obj)
	if not obj then
		return
	end
	obj:Recurse(function(o)
		if typeof(o) == "Object" then
			return
		end
		o.CollisionGroups = { 6 }
		o.CollidesWithGroups = {}
	end, { includeRoot = true })
end

local unfreezeObject = function(obj)
	if not obj then
		return
	end
	obj:Recurse(function(o)
		if typeof(o) == "Object" then
			return
		end
		o.CollisionGroups = OBJECTS_COLLISION_GROUP
		o.CollidesWithGroups = Map.CollisionGroups + Player.CollisionGroups + OBJECTS_COLLISION_GROUP
	end, { includeRoot = true })
end

local spawnObject = function(data, onDone)
	if data.obj then -- Loaded with loadWorld, already created, no need to place it
		local obj = data.obj
		obj.isEditable = true
		local physicsMode = data.Physics or PhysicsMode.StaticPerBlock
		setObjectPhysicsMode(obj, physicsMode)
		obj:Recurse(function(o)
			if typeof(o) == "Object" then
				return
			end
			o.CollisionGroups = CollisionGroups(3) + OBJECTS_COLLISION_GROUP
			o.CollidesWithGroups = Map.CollisionGroups + Player.CollisionGroups + OBJECTS_COLLISION_GROUP
			o:ResetCollisionBox()
		end, { includeRoot = true })
		if obj.uuid ~= -1 then
			objects[obj.uuid] = obj
		end
		if onDone then
			onDone(obj)
		end
		return
	end
	local fullname = data.fullname
	Object:Load(fullname, function(obj)
		if not obj then
			print("Can't load", fullname)
			return
		end

		local uuid = uuidv4()
		local fullname = data.fullname
		local name = data.Name
		local position = data.Position or Number3(0, 0, 0)
		local rotation = data.Rotation or Rotation(0, 0, 0)
		local scale = data.Scale or 0.5
		local physicsMode = data.Physics or PhysicsMode.StaticPerBlock

		obj:SetParent(World)

		-- Handle multishape (world space, change position after)
		local box = Box()
		box:Fit(obj, true)
		obj.Pivot = Number3(obj.Width / 2, box.Min.Y + obj.Pivot.Y, obj.Depth / 2)

		setObjectPhysicsMode(obj, physicsMode)

		obj.uuid = uuid
		obj.Position = position
		obj.Rotation = rotation
		obj.Scale = scale

		obj:Recurse(function(o)
			if typeof(o) == "Object" then
				return
			end
			o.CollisionGroups = CollisionGroups(3) + OBJECTS_COLLISION_GROUP
			o.CollidesWithGroups = Map.CollisionGroups + Player.CollisionGroups + OBJECTS_COLLISION_GROUP
			o:ResetCollisionBox()
		end, { includeRoot = true })

		obj.isEditable = true
		obj.fullname = fullname
		obj.Name = name or fullname

		objects[obj.uuid] = obj
		worldEditorCommon.addObject(obj)

		if onDone then
			onDone(obj)
		end
	end)
end

local editObject = function(objInfo)
	local obj = objects[objInfo.uuid]
	if not obj then
		print("Error: can't edit object")
		return
	end

	for field, value in pairs(objInfo) do
		obj[field] = value
	end

	if objInfo.Physics then
		setObjectPhysicsMode(obj, objInfo.Physics)
	end

	local alpha = objInfo.alpha
	if alpha ~= nil then
		setObjectAlpha(obj, alpha)
	end
end

local putObjectAtImpact = function(obj, origin, direction, distance)
	if type(distance) ~= "number" then
		distance = NEW_OBJECT_MAX_DISTANCE
	else
		distance = math.min(distance, NEW_OBJECT_MAX_DISTANCE)
	end
	obj.Position:Set(origin + direction * distance)
end

local dropNewObject = function()
	local placingObj = worldEditor.placingObj
	worldEditor.placingObj = nil
	unfreezeObject(placingObj)

	if not objects[placingObj.uuid] then
		objects[placingObj.uuid] = placingObj
	else
		worldEditorCommon.updateObject({
			uuid = placingObj.uuid,
			position = placingObj.Position,
			rotation = placingObj.Rotation,
		})
	end
	setState(states.OBJECT_SELECTED, placingObj)
end


-- States

local statesSettings = {
	[states.LOADING] = {
		onStateBegin = function()
			require("object_skills").addStepClimbing(Player)
			setState(states.PICK_WORLD)
			require("controls"):turnOff()
			Player.Motion:Set(Number3.Zero)
		end,
	},
	[states.PICK_WORLD] = {
		onStateBegin = function()
			uiShowWorldPicker()
			require("controls"):turnOff()
			Player.Motion:Set(Number3.Zero)
		end,
		onStateEnd = function()
			uiRemoveWorldPicker()
		end,
	},
	[states.DEFAULT] = {
		onStateBegin = function()
			require("controls"):turnOn()
			uiShowDefaultMenu()
		end,
		onStateEnd = function()
			uiHideDefaultMenu()
		end,
		pointerDown = function(pe)
			tryPickObjectDown(pe)
		end,
		pointerUp = function(pe)
			tryPickObjectUp(pe)
		end,
	},
	[states.GALLERY] = {
		onStateBegin = function()
			worldEditor.gallery:show()
			worldEditor.gallery:bounce()
			require("controls"):turnOff()
			Player.Motion = { 0, 0, 0 }
		end,
		onStateEnd = function()
			worldEditor.gallery:hide()
			require("controls"):turnOn()
		end,
	},
	[states.SPAWNING_OBJECT] = {
		onStateBegin = function(data)
			worldEditor.rotationShift = data.rotationShift or 0
			spawnObject(data, function(obj)
				setState(states.PLACING_OBJECT, obj)
			end)
		end,
	},
	[states.PLACING_OBJECT] = { -- NOTE(aduermael): maybe we can remove this state
		onStateBegin = function(obj)
			worldEditor.placingCancelBtn:show()
			worldEditor.placingObj = obj
			freezeObject(obj)
			if worldEditor.rotationShift == nil then
				worldEditor.rotationShift = 0
			end
			
			-- When in first person, or mobile, we can  use pointer move event to place the object.
			-- So just dropping the object at point of impact with camera forward ray.
			if cameraMode == CameraMode.FREE or Client.IsMobile then
				local impact = Camera:CastRay(Map.CollisionGroups + OBJECTS_COLLISION_GROUP, obj)
				putObjectAtImpact(obj, Camera.Position, Camera.Forward, impact.Distance)
				obj.Rotation.Y = worldEditor.rotationShift
				dropNewObject() -- ends state
			end
		end,
		onStateEnd = function()
			worldEditor.placingCancelBtn:hide()
		end,
		pointerMove = function(pe)
			local placingObj = worldEditor.placingObj
			local impact = pe:CastRay(Map.CollisionGroups + OBJECTS_COLLISION_GROUP, placingObj)
			putObjectAtImpact(placingObj, pe.Position, pe.Direction, impact.Distance)
			placingObj.Rotation.Y = worldEditor.rotationShift
		end,
		pointerUp = function(pe)
			if pe.Index ~= 4 then
				return
			end
			dropNewObject()
		end,
		pointerWheelPriority = function(delta)
			worldEditor.rotationShift = worldEditor.rotationShift + math.pi * 0.0625 * (delta > 0 and 1 or -1)
			worldEditor.placingObj.Rotation.Y = worldEditor.rotationShift
			return true
		end,
	},
	[states.OBJECT_SELECTED] = {
		onStateBegin = function(obj)
			selectedObject = obj
			require("box_gizmo"):toggle(obj, Color.White)
			worldEditor.nameInput.Text = obj.Name
			worldEditor.nameInput.onTextChange = function(o)
				selectedObject.Name = o.Text
				worldEditorCommon.updateObject({
					uuid = obj.uuid,
					name = o.Text,
				})
			end
			objectInfoFrame:bump()

			physicsBtn:setPhysicsMode(obj.realPhysicsMode)
			Timer(0.1, function()
				freezeObject(selectedObject)
			end)

			local currentScale = obj.Scale:Copy()
			ease:inOutQuad(obj, 0.15).Scale = currentScale * 1.1
			Timer(0.15, function()
				ease:inOutQuad(obj, 0.15).Scale = currentScale
			end)
			sfx("waterdrop_3", { Spatialized = false, Pitch = 1 + math.random() * 0.1 })

			if trail ~= nil then
				trail:remove()
			end
			trail = require("trail"):create(Player, obj, TRAIL_COLOR, 0.5)

			if cameraMode == CameraMode.FREE then
				trail:hide()
			end

			transformGizmo = require("transformgizmo"):create({
				target = selectedObject,
				onChange = function(target) end,
				onDone = function(target)
					worldEditorCommon.updateObject({
						uuid = target.uuid,
						position = target.Position,
						rotation = target.Rotation,
						scale = target.Scale,
					})
					worldEditorCommon.updateShadow(target)
				end,
			})
		end,
		tick = function() end,
		pointerDown = function(pe)
			tryPickObjectDown(pe)
		end,
		pointerUp = function(pe)
			tryPickObjectUp(pe)
		end,
		onStateEnd = function()
			if transformGizmo then
				transformGizmo:remove()
				transformGizmo = nil
			end

			if selectedObject then
				unfreezeObject(selectedObject)
			end

			if trail ~= nil then
				trail:remove()
				trail = nil
			end

			require("box_gizmo"):toggle(nil)
			objectInfoFrame:hide()
			saveWorld()
			selectedObject = nil
		end,
		pointerWheelPriority = function(delta)
			selectedObject:RotateWorld(Number3(0, 1, 0), math.pi * 0.0625 * (delta > 0 and 1 or -1))
			selectedObject.Rotation = selectedObject.Rotation -- trigger OnSetCallback
			worldEditorCommon.updateObject({
				uuid = selectedObject.uuid,
				rotation = target.Rotation,
			})
			return true
		end,
	},
	[states.DUPLICATE_OBJECT] = {
		onStateBegin = function(uuid)
			local obj = objects[uuid]
			if not obj then
				print("Error: can't duplicate this object")
				setState(states.DEFAULT)
				return
			end
			local data = getObjectInfoTable(obj)
			data.uuid = uuidv4()
			data.rotationShift = worldEditor.rotationShift or 0
			local previousObj = obj
			spawnObject(data, function(obj)
				obj.Position = previousObj.Position + Number3(5, 0, 5)
				obj.Rotation = previousObj.Rotation
				setState(states.OBJECT_SELECTED, obj)
			end)
		end,
		onStateEnd = function()
			objectInfoFrame:hide()
		end,
	},
	[states.DESTROY_OBJECT] = {
		onStateBegin = function(uuid)
			objectInfoFrame:hide()
			local obj = objects[uuid]
			if not obj then
				print("Error: can't remove this object")
				setState(states.DEFAULT)
				return
			end
			obj:RemoveFromParent()
			objects[uuid] = nil
			worldEditorCommon.removeObject(uuid)
			setState(states.DEFAULT)
		end,
		onStateEnd = function()
			saveWorld()
		end,
	},
}

setState = function(newState, data)
	if state then
		local onStateEnd = statesSettings[state].onStateEnd
		if onStateEnd then
			onStateEnd(newState, data)
		end
	end

	state = newState

	local onStateBegin = statesSettings[state].onStateBegin
	if onStateBegin then
		onStateBegin(data)
	end
end

-- Listeners

local listeners = {
	Tick = "tick",
	PointerDown = "pointerDown",
	PointerMove = "pointerMove",
	PointerDrag = "pointerDrag",
	PointerDragBegin = "pointerDragBegin",
	PointerDragEnd = "pointerDragEnd",
	PointerUp = "pointerUp",
	PointerWheel = "pointerWheel",
	PointerLongPress = "pointerLongPress",
}

local function handleLocalEventListener(listenerName, pe)
	local stateSettings = statesSettings[state]
	local callback

	callback = stateSettings[listenerName]
	if callback then
		if callback(pe) then
			return true
		end
	end
end

for localEventName, listenerName in pairs(listeners) do
	LocalEvent:Listen(LocalEvent.Name[localEventName], function(pe)
		return handleLocalEventListener(listenerName .. "Priority", pe)
	end, { topPriority = true })
	LocalEvent:Listen(LocalEvent.Name[localEventName], function(pe)
		return handleLocalEventListener(listenerName, pe)
	end, { topPriority = false })
end

local worldPicker
function uiShowWorldPicker()
	if worldPicker ~= nil then
		return
	end
	local content
	worldPicker, content = require("creations"):createModal({
		uikit = ui,
		categories = { "worlds" },
		title = "Open World...",
		onOpen = function(_, cell)
			require("api"):getWorld(cell.id, { "mapBase64" }, function(data, err)
				if err then
					print(err)
					return
				end

				loadWorld({
					b64 = data.mapBase64,
					title = cell.title,
					worldID = cell.id,
					onDone = function()
						setState(states.DEFAULT)
						startDefaultMode()
					end,
					onLoad = function(obj, data)
						if data == "Map" then
							if map then
								map:RemoveFromParent()
							end
							map = obj
							return
						end
						data.obj = obj
						spawnObject(data)
					end,
				})

				local ambience = worldEditorCommon.getAmbience()
				if ambience == nil then
					worldEditorCommon.updateAmbience(defaultAmbience)
					require("ai_ambience"):loadGeneration(defaultAmbience)
				end

				
				-- local textureURL = "https://i.ibb.co/hgRhk0t/Standard-Cube-Map.png"
				-- local textureURL = "https://files.cu.bzh/skyboxes/green-mushrooms512.png"
				-- local textureURL = "https://files.cu.bzh/skyboxes/skybox_2.png"
				-- skybox.load({ url = textureURL }, function(obj) end)
			end)
		end,
	})
	-- content.tabs[3].selected = true
	-- content.tabs[3].action()
	-- worldEditor.uiPickWorld = uiPickWorld
end

function uiRemoveWorldPicker()
	if worldPicker == nil then
		return
	end
	worldPicker:remove()
	worldPicker = nil
end

startDefaultMode = function()
	Fog.On = true
	dropPlayer = function()
		Player.Rotation:Set(0, 0, 0)
		Player.Velocity:Set(0, 0, 0)
		if map then
			Player.Position = Number3(map.Width * 0.5, map.Height + 10, map.Depth * 0.5) * map.Scale
		else
			Player.Position:Set(0, 20, 0)
		end
	end
	
	Player:SetParent(World)
	setCameraMode(CameraMode.THIRD_PERSON)
	dropPlayer()

	require("jumpfly")

	Client.Tick = function(dt)
		if cameraMode == CameraMode.FREE then
			Camera.Position += cameraSpeed * dt
		else
			if Player.Position.Y < -500 then
				dropPlayer()
				Player:TextBubble("💀 Oops!", true)
			end
		end
	end
end

local uiDefaultMenu
function uiShowDefaultMenu()
	if uiDefaultMenu ~= nil then
		uiDefaultMenu:show()
		return
	end

	uiDefaultMenu = ui:createNode()

	local addObjectBtn = ui:buttonSecondary({ 
		content = "➕ Object", 
		padding = padding,
		textSize = "small",
	})
	addObjectBtn.parentDidResize = function(self)
		self.pos = { 
			Screen.Width - Screen.SafeArea.Right - self.Width - padding, 
			Screen.Height - Screen.SafeArea.Top - self.Height - padding 
		}
	end
	addObjectBtn.onRelease = function()
		setState(states.GALLERY)
	end
	addObjectBtn:setParent(uiDefaultMenu)

	-- Gallery
	local galleryOnOpen = function(cell)
		local fullname = cell.repo .. "." .. cell.name
		setState(states.SPAWNING_OBJECT, { fullname = fullname })
	end
	local initGallery
	initGallery = function()
		worldEditor.gallery = require("gallery"):create(function() -- maxWidth
			return Screen.Width - Screen.SafeArea.Right - Screen.SafeArea.Left - theme.padding * 2
		end, function() -- maxHeight
			return Menu.Position.Y - Screen.SafeArea.Bottom - theme.padding * 2
		end, function(m) -- position
			m.pos = {
				Screen.Width * 0.5 - m.Width * 0.5,
				Screen.SafeArea.Bottom 
				+ padding
				+ (Menu.Position.Y - Screen.SafeArea.Bottom - theme.padding * 2) * 0.5
				- m.Height * 0.5,
			}
		end, { onOpen = galleryOnOpen, type = "items" })
		worldEditor.gallery.didClose = function()
			setState(states.DEFAULT)
			initGallery()
		end
		worldEditor.gallery:hide()
	end
	initGallery()

	-- Placing
	local placingCancelBtn = ui:createButton("❌")
	placingCancelBtn.onRelease = function()
		setState(states.DEFAULT)
		worldEditor.placingObj:RemoveFromParent()
		worldEditor.placingObj = nil
	end
	placingCancelBtn.parentDidResize = function()
		placingCancelBtn.pos = { Screen.Width * 0.5 - placingCancelBtn.Width * 0.5, placingCancelBtn.Height * 2 }
	end
	placingCancelBtn:parentDidResize()
	placingCancelBtn:hide()
	worldEditor.placingCancelBtn = placingCancelBtn

	-- OBJECT INFO FRAME

	objectInfoFrame = ui:frameGenericContainer()

	local nameInput = ui:createTextInput("", "Item Name", { textSize = "small" })
	worldEditor.nameInput = nameInput
	nameInput:setParent(objectInfoFrame)

	physicsBtn = ui:buttonSecondary({ content = "", textSize = "small" })
	physicsBtn.physicsMode = PhysicsMode.Static
	physicsBtn.setPhysicsMode = function(self, mode)
		physicsBtn.physicsMode = mode
		if mode == PhysicsMode.Static then
			self.Text = "⚀ Static"
		elseif mode == PhysicsMode.Trigger then
			self.Text = "► Trigger"
		elseif mode == PhysicsMode.Disabled then
			self.Text = "❌ Disabled"
		elseif mode == PhysicsMode.StaticPerBlock then
			self.Text = "⚅ Static Per Block"
		else
			self.Text = "⚠️ UNKNOWN PHYSICS MODE"
		end
	end
	physicsBtn.onRelease = function(self)
		local obj = selectedObject
		if self.physicsMode == PhysicsMode.StaticPerBlock then
			setObjectPhysicsMode(obj, PhysicsMode.Static)
			self:setPhysicsMode(PhysicsMode.Static)
		elseif self.physicsMode == PhysicsMode.Static then
			setObjectPhysicsMode(obj, PhysicsMode.Trigger)
			self:setPhysicsMode(PhysicsMode.Trigger)
		elseif self.physicsMode == PhysicsMode.Trigger then
			setObjectPhysicsMode(obj, PhysicsMode.Disabled)
			self:setPhysicsMode(PhysicsMode.Disabled)
		else
			setObjectPhysicsMode(obj, PhysicsMode.StaticPerBlock)
			self:setPhysicsMode(PhysicsMode.StaticPerBlock)
		end
	end
	physicsBtn:setParent(objectInfoFrame)

	local duplicateBtn = ui:buttonSecondary({ content = "📑 Duplicate", textSize = "small" })
	duplicateBtn.onRelease = function()
		setState(states.DUPLICATE_OBJECT, selectedObject.uuid)
	end
	duplicateBtn:setParent(objectInfoFrame)

	local deleteBtn = ui:buttonSecondary({ content = "🗑️ Delete", textSize = "small" })
	deleteBtn.onRelease = function()
		setState(states.DESTROY_OBJECT, selectedObject.uuid)
	end
	deleteBtn:setParent(objectInfoFrame)
	
	local validateBtn = ui:buttonSecondary({ content = "✅ Validate", textSize = "small" })
	validateBtn.onRelease = function()
		setState(states.DEFAULT, selectedObject.uuid)
	end
	validateBtn:setParent(objectInfoFrame)

	objectInfoFrame.parentDidResize = function(self)
		self.Width = math.min(200, Screen.Width - Menu.Width - Screen.SafeArea.Right - Screen.SafeArea.Left - padding * 3)

		local width = self.Width - padding * 2
		nameInput.Width = width
		physicsBtn.Width = width
		duplicateBtn.Width = width
		deleteBtn.Width = width
		validateBtn.Width = width

		self.Height = nameInput.Height + padding
		+ physicsBtn.Height + padding
		+ duplicateBtn.Height + padding
		+ deleteBtn.Height + padding
		+ validateBtn.Height + padding
		+ padding

		local y = self.Height

		y -= nameInput.Height + padding
		nameInput.pos = { padding, y }

		y -= physicsBtn.Height + padding
		physicsBtn.pos = { padding, y }

		y -= duplicateBtn.Height + padding
		duplicateBtn.pos = { padding, y }	
		
		y -= deleteBtn.Height + padding
		deleteBtn.pos = { padding, y }

		y -= validateBtn.Height + padding
		validateBtn.pos = { padding, y }

		self.pos = {
			Screen.Width - Screen.SafeArea.Right - self.Width - padding, 
			Screen.Height - Screen.SafeArea.Top - self.Height - padding,
		}
	end

	objectInfoFrame.bump = function(self)
		if self:isVisible() then
			return
		end
		self:show()
		ease:cancel(self.pos)
		self:parentDidResize()
		local x = self.pos.X
		self.pos.X = x + 100
		ease:outBack(self.pos, 0.3).X = x
	end
	objectInfoFrame:hide()
	objectInfoFrame:parentDidResize()

	-- Ambience editor
	ambienceBtn = ui:buttonSecondary({ 
		content = "☀️ Ambience", 
		textSize = "small",
	})
	ambienceBtn.onRelease = function(self)
		ambienceBtn:hide()
		cameraBtn:hide()

		if ambiencePanel ~= nil then
			ambiencePanel:bump()
			return
		end

		ambiencePanel = ui:frameGenericContainer()

		local title = ui:createText(self.Text, Color.White, "small")
		title:setParent(ambiencePanel)

		local btnClose = ui:buttonNegative({ content = "close", textSize = "small", padding = padding })
		btnClose:setParent(ambiencePanel)

		local aiInput = ui:createTextInput("", "Morning light, dawn…", { textSize = "small" })
		aiInput:setParent(ambiencePanel)

		local aiBtn = ui:buttonNeutral({ content = "✨", textSize = "small", padding = padding })
		aiBtn:setParent(ambiencePanel)

		local skyboxLabel = ui:createText("Include skybox:", Color(150, 150, 150), "small")
		skyboxLabel:setParent(ambiencePanel)

		local includeSkybox = true
		local skyboxBtn = ui:buttonSecondary({
			textFont = Font.Pixel,
			content = "✅",
			textSize = "default",
			padding = 2,
		})
		skyboxBtn.onRelease = function(self)
			includeSkybox = not includeSkybox
			if includeSkybox then
				self.Text = "✅"
			else
				self.Text = "  "
			end
		end
		skyboxBtn:setParent(ambiencePanel)

		local loading = require("ui_loading_animation"):create({ ui = ui })
		loading:setParent(ambiencePanel)
		loading:hide()

		local cell = ui:frame()

		local sunLabel = ui:createText("☀️ Sun", { size = "small", color = Color.White })
		sunLabel:setParent(cell)

		local sunRotationYLabel = ui:createText("0  ", { font = Font.Pixel, size = "default", color = Color.White })
		sunRotationYLabel:setParent(cell)

		local sliderHandleSize = 30

		local sliderButton = ui:buttonNeutral({ content = "" })
		sliderButton.Height = sliderHandleSize
		sliderButton.Width = sliderHandleSize

		local sunRotationSlider = ui:slider({
			defaultValue = 180, -- TODO: fix ambience first then get current value
			min = 0,
			max = 360,
			step = 1,
			button = sliderButton,
			onValueChange = function(v)
				sunRotationYLabel.Text = "" .. v
				local ambience = worldEditorCommon.getAmbience()
				if ambience.sun.rotation then
					ambience.sun.rotation.Y = math.rad(v)
					worldEditorCommon.updateAmbience(ambience)
					require("ai_ambience"):loadGeneration(ambience)
				end
			end,
		})
		sunRotationSlider:setParent(cell)

		local sunRotationXLabel = ui:createText("0  ", { font = Font.Pixel, size = "default", color = Color.White })
		sunRotationXLabel:setParent(cell)

		local sliderButton = ui:buttonNeutral({ content = "" })
		sliderButton.Height = sliderHandleSize
		sliderButton.Width = sliderHandleSize

		local sunRotationXSlider = ui:slider({
			defaultValue = 0, -- TODO: fix ambience first then get current value
			min = -90,
			max = 90,
			step = 1,
			button = sliderButton,
			onValueChange = function(v)
				sunRotationXLabel.Text = "" .. v
				local ambience = worldEditorCommon.getAmbience()
				if ambience.sun.rotation then
					ambience.sun.rotation.X = math.rad(v)
					worldEditorCommon.updateAmbience(ambience)
					require("ai_ambience"):loadGeneration(ambience)
				end
			end,
		})
		sunRotationXSlider:setParent(cell)

		local fogLabel = ui:createText("☁️ Fog (near/far)", { size = "small", color = Color.White })
		fogLabel:setParent(cell)

		local sliderButton = ui:buttonNeutral({ content = "" })
		sliderButton.Height = sliderHandleSize
		sliderButton.Width = sliderHandleSize

		local fogNearSlider = ui:slider({
			defaultValue = 0, -- TODO: fix ambience first then get current value
			min = -90,
			max = 90,
			step = 1,
			button = sliderButton,
			onValueChange = function(v) end,
		})
		fogNearSlider:setParent(cell)

		local sliderButton = ui:buttonNeutral({ content = "" })
		sliderButton.Height = sliderHandleSize
		sliderButton.Width = sliderHandleSize

		local fogFarSlider = ui:slider({
			defaultValue = 0, -- TODO: fix ambience first then get current value
			min = -90,
			max = 90,
			step = 1,
			button = sliderButton,
			onValueChange = function(v) end,
		})
		fogFarSlider:setParent(cell)

		cell.Height = sunLabel.Height
			+ theme.paddingTiny
			+ sliderHandleSize
			+ theme.paddingTiny
			+ sliderHandleSize
			+ theme.paddingTiny
			+ fogLabel.Height
			+ theme.paddingTiny
			+ sliderHandleSize
			+ theme.paddingTiny
			+ sliderHandleSize

		cell.parentDidResize = function(self)
			local parent = self.parent
			self.Width = parent.Width

			local y = self.Height - sunLabel.Height
			sunLabel.pos = { 0, y }
			y = y - theme.paddingTiny - sliderHandleSize

			sunRotationSlider.Width = self.Width - sunRotationYLabel.Width - theme.padding
			sunRotationSlider.pos = { 0, y }

			sunRotationYLabel.pos = {
				sunRotationSlider.pos.X + sunRotationSlider.Width + theme.padding,
				sunRotationSlider.pos.Y + sliderHandleSize * 0.5 - sunRotationYLabel.Height * 0.5,
			}
			y = y - theme.paddingTiny - sliderHandleSize

			sunRotationXSlider.Width = self.Width - sunRotationYLabel.Width - theme.padding
			sunRotationXSlider.pos = { 0, y }

			sunRotationXLabel.pos = {
				sunRotationXSlider.pos.X + sunRotationXSlider.Width + theme.padding,
				sunRotationXSlider.pos.Y + sliderHandleSize * 0.5 - sunRotationXLabel.Height * 0.5,
			}
			y = y - theme.paddingTiny - fogLabel.Height

			fogLabel.pos = { 0, y }

			y = y - theme.paddingTiny - sliderHandleSize
			fogNearSlider.Width = self.Width - sunRotationYLabel.Width - theme.padding
			fogNearSlider.pos = { 0, y }

			y = y - theme.paddingTiny - sliderHandleSize
			fogFarSlider.Width = self.Width - sunRotationYLabel.Width - theme.padding
			fogFarSlider.pos = { 0, y }
		end

		cell:setParent(nil)

		local function generate()
			local prompt = aiInput.Text
			if prompt == "" then
				return
			end

			aiInput:hide()
			aiBtn:hide()
			loading:show()

			require("ai_ambience"):generate({
				prompt = aiInput.Text,
				loadWhenDone = false,
				onDone = function(generation, loadedAmbiance)

					sfx("metal_clanging_2", { Spatialized = false, Volume = 0.6 })
					loadedAmbiance = require("ai_ambience"):loadGeneration(generation)
					worldEditorCommon.updateAmbience(loadedAmbiance)
					sunRotationSlider:setValue(math.floor(math.deg(loadedAmbiance.sun.rotation.Y)))
					sunRotationXSlider:setValue(math.floor(math.deg(loadedAmbiance.sun.rotation.X)))
					aiInput:show()
					aiBtn:show()
					loading:hide()
					saveWorld()

					-- prompt = "SYSTEM: Generate a skybox in pixel art style. Do NOT include ground details, just empty sky volume, include skyline details only if specified.\n\nPROMPT: "
					-- 	.. prompt

					-- local body = {}
					-- body.prompt = prompt

					-- local headers = {}
					-- headers["Content-Type"] = "application/json"

					-- -- do not send request when skybox is not requested
					-- HTTP:Post("http://localhost", headers, body, function(res)
					-- 	if res.StatusCode == 200 then
					-- 		loadedAmbiance = require("ai_ambience"):loadGeneration(generation)

					-- 		local body = JSON:Decode(res.Body:ToString())
					-- 		if body.url ~= nil then
					-- 			local textureURL = "http://localhost" .. body.url
					-- 			skybox.load({ url = textureURL }, function(obj)
					-- 				sfx("metal_clanging_2", { Spatialized = false, Volume = 0.6 })
					-- 				worldEditorCommon.updateAmbience(loadedAmbiance)
					-- 				sunRotationSlider:setValue(math.floor(math.deg(loadedAmbiance.sun.rotation.Y)))
					-- 				sunRotationXSlider:setValue(math.floor(math.deg(loadedAmbiance.sun.rotation.X)))
					-- 				aiInput:show()
					-- 				aiBtn:show()
					-- 				loading:hide()
					-- 				saveWorld()
					-- 			end)
					-- 		else
					-- 			sfx("metal_clanging_2", { Spatialized = false, Volume = 0.6 })
					-- 			worldEditorCommon.updateAmbience(loadedAmbiance)
					-- 			sunRotationSlider:setValue(math.floor(math.deg(loadedAmbiance.sun.rotation.Y)))
					-- 			sunRotationXSlider:setValue(math.floor(math.deg(loadedAmbiance.sun.rotation.X)))
					-- 			aiInput:show()
					-- 			aiBtn:show()
					-- 			loading:hide()
					-- 			saveWorld()
					-- 		end
					-- 	end
					-- end)
				end,
				onError = function(err)
					print("❌", err)
					aiInput:show()
					aiBtn:show()
					loading:hide()
				end,
			})
		end

		aiInput.onSubmit = generate
		aiBtn.onRelease = generate

		btnClose.onRelease = function()
			ambiencePanel:hide()
			ambienceBtn:show()
			cameraBtn:show()
		end

		local scroll = ui:createScroll({
			backgroundColor = theme.buttonTextColor,
			loadCell = function(index, _) -- index, userdata
				if index == 1 then
					return cell
				end
			end,
			unloadCell = function(_, cell, _) -- index, cell, userdata
				cell:setParent(nil)
				return nil
			end,
			cellPadding = padding,
			padding = padding,
		})
		scroll:setParent(ambiencePanel)

		ambiencePanel.parentDidResize = function(self)
			self.Width = 200
			self.Height = math.min(500, Menu.Position.Y - Screen.SafeArea.Bottom - padding * 2)

			self.pos = {
				Menu.Position.X,
				Menu.Position.Y - self.Height - padding,
			}

			title.pos = {
				self.Width * 0.5 - title.Width * 0.5,
				self.Height - title.Height - padding,
			}

			aiInput.Width = self.Width - aiBtn.Width - padding * 3
			local h = math.max(aiInput.Height, aiBtn.Height)
			aiInput.Height = h
			aiBtn.Height = h

			aiInput.pos = {
				padding,
				title.pos.Y - h - padding,
			}

			aiBtn.pos = {
				aiInput.pos.X + aiInput.Width + padding,
				aiInput.pos.Y,
			}

			loading.pos = {
				self.Width * 0.5 - loading.Width * 0.5,
				aiInput.pos.Y + aiBtn.Height * 0.5 - loading.Height * 0.5,
			}

			skyboxBtn.pos = {
				aiBtn.pos.X + aiBtn.Width - skyboxBtn.Width,
				aiInput.pos.Y - skyboxBtn.Height - padding,
			}

			skyboxLabel.pos = {
				skyboxBtn.pos.X - skyboxLabel.Width - padding,
				skyboxBtn.pos.Y + skyboxBtn.Height * 0.5 - skyboxLabel.Height * 0.5,
			}

			btnClose.pos = {
				self.Width * 0.5 - btnClose.Width * 0.5,
				padding,
			}

			scroll.pos.Y = btnClose.pos.Y + btnClose.Height + padding
			scroll.pos.X = padding
			scroll.Height = aiInput.pos.Y - skyboxBtn.Height - padding * 2 - scroll.pos.Y
			scroll.Width = self.Width - padding * 2
		end

		ambiencePanel.bump = function(self, force)
			if force ~= true and self:isVisible() then
				return
			end
			self:show()
			ease:cancel(self.pos)
			self:parentDidResize()
			local x = self.pos.X
			self.pos.X = x - 100
			ease:outBack(self.pos, 0.3).X = x
		end

		ambiencePanel:bump(true)
	end

	-- Camera
	cameraBtn = ui:buttonSecondary({ content = "🎥", textSize = "small" })
	cameraBtn.onRelease = function()
		if cameraMode == CameraMode.THIRD_PERSON then
			setCameraMode(CameraMode.FREE)
		else
			setCameraMode(CameraMode.THIRD_PERSON)
		end
	end
	cameraBtn.parentDidResize = function()
		ambienceBtn.pos = {
			Screen.SafeArea.Left + padding,
			Menu.Position.Y - ambienceBtn.Height - padding,
		}

		cameraBtn.pos = {
			ambienceBtn.pos.X,
			ambienceBtn.pos.Y - cameraBtn.Height - padding,
		}
	end
	cameraBtn:parentDidResize()
end

function uiHideDefaultMenu()
	if uiDefaultMenu ~= nil then
		uiDefaultMenu:hide()
	end
end

-- Auto-save timer
local autoSaveTimer = nil
function saveWorld()
	if autoSaveTimer ~= nil then
		autoSaveTimer:Cancel()
	end
	if state >= states.DEFAULT then
		worldEditorCommon.saveWorld()
	end
	autoSaveTimer = Timer(30, saveWorld)
end
autoSaveTimer = Timer(30, saveWorld)

setState(states.LOADING)

function updateCameraSpeed()
	cameraSpeed = (Camera.Forward * camDirY + Camera.Right * camDirX) * 50
end

function rotateCamera(pe)
	if cameraMode == CameraMode.FREE then
		Camera.Rotation.X += pe.DY * -0.01
		Camera.Rotation.Y += pe.DX * 0.01
		updateCameraSpeed()
	end
end

Client.DirectionalPad = function(x, y)
	camDirX = x
	camDirY = y
	updateCameraSpeed()
end

Client.AnalogPad = nil
Pointer.Drag2 = rotateCamera
Pointer.Drag = rotateCamera

return worldEditor