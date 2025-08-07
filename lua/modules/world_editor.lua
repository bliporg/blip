local worldEditor = {}

local animationsAdded = false
function addPlayerAnimations()
	if animationsAdded then 
		return
	end
	animationsAdded = true
	local player = Player

	local leftLeg = Player.LeftLeg

	local animFly = Animation("Fly", { speed = 1, loops = 0, priority = 255 })
	local bodyFloat = {
		{ time = 0.0, position = { 0, 12, 0 } },
		{ time = 0.5, position = { 0, 11, 0 } },
		{ time = 1.0, position = { 0, 12, 0 } },
	}
	local moveLeftLeg = {
		{ time = 0.0, rotation = { 0, 0, 0 } },
		{ time = 0.5, rotation = { math.rad(10), 0, 0 } },
		{ time = 1.0, rotation = { 0, 0, 0 } },
	}
	local moveRightLeg = {
		{ time = 0.0, rotation = { 0, 0, 0 } },
		{ time = 0.5, rotation = { math.rad(10), 0, 0 } },
		{ time = 1.0, rotation = { 0, 0, 0 } },
	}
	local moveLeftFoot = {
		{ time = 0.0, rotation = { 0, 0, 0 } },
	}
	local moveRightFoot = {
		{ time = 0.0, rotation = { 0, 0, 0 } },
	}

	local moveLeftArm = {
		{ time = 0.0, rotation = { 0, 0, 1.14537 + 0.1 } },
		{ time = 0.5, rotation = { 0, 0, 1.14537 } },
		{ time = 1.0, rotation = { 0, 0, 1.14537 + 0.1 } },
	}
	local moveLeftHand = {
		{ time = 0.0, rotation = { 0, 0.294524, -0.0981748 } },
		{ time = 0.5, rotation = { 0, 0.19635, -0.0981748 } },
		{ time = 1.0, rotation = { 0, 0.294524, -0.0981748 } },
	}
	local moveRightArm = {
		{ time = 0.0, rotation = { 0, 0, -1.14537 - 0.1 } },
		{ time = 0.5, rotation = { 0, 0, -1.14537 } },	
		{ time = 1.0, rotation = { 0, 0, -1.14537 - 0.1 } },
	}
	local moveRightHand = {
		{ time = 0.0, rotation = { 0, -0.294524, 0 } },
		{ time = 0.5, rotation = { 0, -0.19635, 0 } },
		{ time = 1.0, rotation = { 0, -0.294524, 0 } },
	}

	local animFlyConfig = {
		Body = bodyFloat,
		LeftLeg = moveLeftLeg,
		RightLeg = moveRightLeg,
		LeftFoot = moveLeftFoot,
		RightFoot = moveRightFoot,
		LeftArm = moveLeftArm,
		RightArm = moveRightArm,
		LeftHand = moveLeftHand,
		RightHand = moveRightHand,
	}

	for name, v in pairs(animFlyConfig) do
		for _, frame in ipairs(v) do
			animFly:AddFrameInGroup(name, frame.time, { position = frame.position, rotation = frame.rotation })
			animFly:Bind(
				name,
				(name == "Body" and not player.Avatar[name]) and player.Avatar or player.Avatar[name]
			)
		end
	end
	player.Animations.Fly = animFly
end

local sfx = require("sfx")
local ease = require("ease")
local ui = require("uikit")
local ambience = require("ambience")
local world = require("world")
local ccc = require("ccc")
local jumpfly = require("jumpfly")
local bundle = require("bundle")

local jetpack = bundle:Shape("shapes/jetpack.3zh")
jetpack:Recurse(function(o)
	o.IsUnlit = true
end)

jetpack.anim = function()
	local t = 0
	jetpack.Tick = function(o, dt)
		t += dt * 10
		jetpack.Children[1].Scale.Y = 1 + math.sin(t) * 0.05
	end
end

jetpack.stopAnim = function()
	jetpack.Tick = nil
end

-- Constants
local NEW_OBJECT_MAX_DISTANCE = 50
local THIRD_PERSON_CAMERA_DISTANCE = 40
local TRAIL_COLOR = Color.White
local COLLISION_GROUP_OBJECT = CollisionGroups(3)
local COLLISION_GROUP_MAP = CollisionGroups(1)
local COLLISION_GROUP_PLAYER = CollisionGroups(2)

local defaultAmbienceGeneration = { 
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

-- Import events and constants from world module
local events = world.events

local loadWorld = world.loadWorld
local maps = world.maps

local theme = require("uitheme").current
local padding = theme.padding

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
local walkModeBtn
local flyModeBtn
local transformGizmo
local objectInfoFrame
local physicsBtn
local addObjectBtn
local gallery
local newObjectCancelBtn
local newObjectBeingPlaced
local objectNameInput

selectedObjectContainer = Object() -- Object containing the object being edited
selectedObjectContainer.Physics = PhysicsMode.Disabled
selectedObjectContainer:SetParent(World)

local trail

local function hideAllPanels()
	if ambiencePanel ~= nil then
		ambiencePanel:hide()
	end
	if gallery ~= nil then
		gallery:hide()
	end
	ambienceBtn:show()
	cameraBtn:show()
	walkModeBtn:show()
	flyModeBtn:show()
	addObjectBtn:show()
	require("controls"):turnOn()
end

local function setCameraMode(mode)
	if cameraMode == mode then
		return
	end
	cameraMode = mode

	cameraBtn:unselect()
	walkModeBtn:unselect()
	flyModeBtn:unselect()

	if mode == CameraMode.THIRD_PERSON then
		Camera:SetModeFree()
		ccc:set({
			target = Player,
			cameraColliders = COLLISION_GROUP_OBJECT,
		})
		Player.Physics = PhysicsMode.Dynamic
		Player.IsHidden = false
		if trail then
			trail:show()
		end
		jumpfly:stopFlying()
		walkModeBtn:select()

		Player:EquipBackpack(nil)
		if Player.Animations.Fly then
			Player.Animations.Fly:Stop()
		end
		jetpack.stopAnim()

	elseif mode == CameraMode.THIRD_PERSON_FLYING then
		Camera:SetModeFree()
		ccc:set({
			target = Player,
			cameraColliders = COLLISION_GROUP_OBJECT,
		})
		Player.Physics = PhysicsMode.Dynamic
		Player.IsHidden = false
		if trail then
			trail:show()
		end

		flyModeBtn:select()

		Player:EquipBackpack(jetpack)
		ease:cancel(jetpack)
		jetpack.LocalPosition.Y -= 3
		jetpack.Scale = 0.5

		ease:outBack(jetpack, 0.3).Scale = Number3(0.8, 0.8, 0.8)

		jetpack.anim()

		Player.Velocity.Y = 30 -- little jump (before setting fly mode)
		addPlayerAnimations() -- adds animations if not already added
		Timer(0.2, function()
			Player.Animations.Fly:Play()
			jumpfly:fly()
		end)
	else
		ccc:unset()
		Camera:SetModeFree()
		Player.Physics = PhysicsMode.Disabled
		Player.IsHidden = true
		if trail then
			trail:hide()
		end
		cameraBtn:select()
	end
end

local function copyObjectInfo(obj)
	if obj.uuid == nil then
		print("error: trying to get object info without uuid")
		return nil
	end
	
	local objectInfo = world.getObjectInfo(obj.uuid)
	if objectInfo == nil then
		print("error: can't get object info")
		return nil
	end

	local newObjectInfo = {
		uuid = nil, -- will be assigned later
		fullname = objectInfo.fullname,
		Name = objectInfo.Name,
		Physics = objectInfo.Physics,
		CollisionGroups = objectInfo.CollisionGroups,
		CollidesWithGroups = objectInfo.CollidesWithGroups,
	}

	if objectInfo.Position then
		newObjectInfo.Position = objectInfo.Position:Copy()
	end
	if objectInfo.Rotation then
		newObjectInfo.Rotation = objectInfo.Rotation:Copy()
	end
	if objectInfo.Scale then
		newObjectInfo.Scale = objectInfo.Scale:Copy()
	end
	
	return newObjectInfo
end

local possiblePhysicsModes = function(obj)
	if typeof(obj) == "Object" or typeof(obj) == "Mesh" or typeof(obj) == "Quad" then
		return { PhysicsMode.Static, PhysicsMode.Dynamic, PhysicsMode.Trigger, PhysicsMode.Disabled }
	elseif typeof(obj) == "Shape" or typeof(obj) == "MutableShape" then
		return { PhysicsMode.StaticPerBlock, PhysicsMode.Static, PhysicsMode.Dynamic, PhysicsMode.Trigger, PhysicsMode.Disabled }
	end
	return {}
end

local defaultPhysicsMode = function(obj)
	return possiblePhysicsModes(obj)[1]
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

local function setObjectPhysicsMode(obj, physicsMode)
	if not obj then
		print("⚠️ can't set physics mode on nil object")
		return
	end
	obj.realPhysicsMode = physicsMode
	obj:Recurse(function(o)
		if o.Physics == nil or typeof(o) == "Object" then
			return
		end
		-- If disabled, keep trigger to allow raycast
		if physicsMode == PhysicsMode.Disabled then
			o.Physics = PhysicsMode.Trigger
		else
			o.Physics = physicsMode
		end
	end, { includeRoot = true })

	world.updateObject({
		uuid = obj.uuid,
		Physics = physicsMode,
	})
end

function objectHitTest(pe)
	local impact = pe:CastRay(COLLISION_GROUP_OBJECT)
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
		o.CollisionGroups = COLLISION_GROUP_OBJECT
		o.CollidesWithGroups = COLLISION_GROUP_MAP + COLLISION_GROUP_PLAYER + COLLISION_GROUP_OBJECT
	end, { includeRoot = true })
end

local spawnObject = function(objectInfo, onDone)
	if objectInfo.obj then -- Loaded with loadWorld, already created, no need to place it
		local obj = objectInfo.obj
		obj.isEditable = true
		local physicsMode = objectInfo.Physics or defaultPhysicsMode(obj)
		setObjectPhysicsMode(obj, physicsMode)
		obj:Recurse(function(o)
			if typeof(o) == "Object" then
				return
			end
			o.CollisionGroups = COLLISION_GROUP_OBJECT
			o.CollidesWithGroups = COLLISION_GROUP_MAP + COLLISION_GROUP_PLAYER + COLLISION_GROUP_OBJECT
			o:ResetCollisionBox()
		end, { includeRoot = true })
		if onDone then
			onDone(obj)
		end
		return
	end
	local fullname = objectInfo.fullname
	Object:Load(fullname, function(obj)
		if obj == nil then
			print("couldn't load", fullname)
			return
		end

		obj:SetParent(World)

		-- Handle multishape (world space, change position after)
		local box = Box()
		box:Fit(obj, { recurse = true, localBox = true })
		if obj.Pivot then
			obj.Pivot = Number3(obj.Width / 2, box.Min.Y + obj.Pivot.Y, obj.Depth / 2)
		end

		setObjectPhysicsMode(obj, objectInfo.Physics or defaultPhysicsMode(obj))

		obj.Position = objectInfo.Position or Number3(0, 0, 0)
		obj.Rotation = objectInfo.Rotation or Rotation(0, 0, 0)
		obj.Scale = objectInfo.Scale or 0.5

		obj:Recurse(function(o)
			if typeof(o) == "Object" then
				return
			end
			o.CollisionGroups = COLLISION_GROUP_OBJECT
			o.CollidesWithGroups = COLLISION_GROUP_MAP + COLLISION_GROUP_PLAYER + COLLISION_GROUP_OBJECT
			o:ResetCollisionBox()
		end, { includeRoot = true })

		obj.isEditable = true
		obj.fullname = objectInfo.fullname
		obj.Name = objectInfo.Name or obj.fullname

		world.addObject(obj) -- attributes a uuid to the object

		if onDone then
			onDone(obj)
		end
	end)
end

local editObject = function(objInfo)
	local obj = world.getObject(objInfo.uuid)
	if not obj then
		error("can't edit object")
		return
	end

	for field, value in objInfo do
		obj[field] = value
	end

	if objInfo.Physics then
		setObjectPhysicsMode(obj, objInfo.Physics)
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
	if newObjectBeingPlaced == nil then
		return
	end
	local obj = newObjectBeingPlaced
	newObjectBeingPlaced = nil
	unfreezeObject(obj)

	world.updateObject({
		uuid = obj.uuid,
		Position = obj.Position,
		Rotation = obj.Rotation,
	})
	
	setState(states.OBJECT_SELECTED, obj)
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
			require("controls"):turnOff()
			Player.Motion:Set(Number3.Zero)
			loadEditedWorld()
		end,
		onStateEnd = function()
		end,
	},
	[states.DEFAULT] = {
		onStateBegin = function()
			require("controls"):turnOn()
			uiShowDefaultMenu()
		end,
		onStateEnd = function()
			hideAllPanels()
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
			hideAllPanels()
			addObjectBtn:hide()
			ambienceBtn:hide()
			cameraBtn:hide()
			walkModeBtn:hide()
			flyModeBtn:hide()
			gallery:show()
			gallery:bounce()
			require("controls"):turnOff()
			Player.Motion = { 0, 0, 0 }
		end,
		onStateEnd = function()
			hideAllPanels()
		end,
	},
	[states.SPAWNING_OBJECT] = {
		onStateBegin = function(objectInfo) -- objectInfo only contains `fullname` here
			spawnObject(objectInfo, function(obj)
				setState(states.PLACING_OBJECT, obj)
			end)
		end,
	},
	[states.PLACING_OBJECT] = { -- NOTE(aduermael): maybe we can remove this state
		onStateBegin = function(obj)
			newObjectCancelBtn:show()
			newObjectBeingPlaced = obj
			freezeObject(obj)
			if rotationShift == nil then
				rotationShift = 0
			end
			
			-- When in first person, or mobile, we can  use pointer move event to place the object.
			-- So just dropping the object at point of impact with camera forward ray.
			if cameraMode == CameraMode.FREE or Client.IsMobile then
				local impact = Camera:CastRay(COLLISION_GROUP_MAP + COLLISION_GROUP_OBJECT, obj)
				putObjectAtImpact(obj, Camera.Position, Camera.Forward, impact.Distance)
				obj.Rotation.Y = rotationShift
				dropNewObject() -- ends state
			end
		end,
		onStateEnd = function()
			newObjectCancelBtn:hide()
		end,
		pointerMove = function(pe)
			if newObjectBeingPlaced == nil then
				return
			end
			local impact = pe:CastRay(COLLISION_GROUP_MAP + COLLISION_GROUP_OBJECT, newObjectBeingPlaced)
			putObjectAtImpact(newObjectBeingPlaced, pe.Position, pe.Direction, impact.Distance)
			newObjectBeingPlaced.Rotation.Y = rotationShift
		end,
		pointerUp = function(pe)
			if pe.Index ~= 4 then
				return
			end
			dropNewObject()
		end,
		pointerWheelPriority = function(delta)
			worldEditor.rotationShift = rotationShift + math.pi * 0.0625 * (delta > 0 and 1 or -1)
			newObjectBeingPlaced.Rotation.Y = rotationShift
			return true
		end,
	},
	[states.OBJECT_SELECTED] = {
		onStateBegin = function(obj)
			selectedObject = obj

			selectedObjectContainer.Scale = 1
			selectedObjectContainer.Rotation:Set(0, 0, 0)

			local box = Box()
			box:Fit(obj, { recurse = true, localBox = true })
			selectedObjectContainer.Position = box.Center

			obj:SetParent(selectedObjectContainer, true)

			local objectsWithColliders = {}
			obj:Recurse(function(o)
				if o.Physics == nil or typeof(o) == "Object" then
					return
				end
				table.insert(objectsWithColliders, o)
			end, { includeRoot = true })
			Dev.DisplayColliders = objectsWithColliders

			objectNameInput.Text = obj.Name
			objectNameInput.onTextChange = function(o)
				selectedObject.Name = o.Text
				world.updateObject({
					uuid = obj.uuid,
					Name = o.Text,
				})
			end
			objectInfoFrame:bump()

			physicsBtn:setPhysicsMode(obj.realPhysicsMode)
			freezeObject(selectedObject)

			local currentScale = obj.Scale:Copy()
			ease:inOutQuad(obj, 0.15, {
				onDone = function()
					ease:inOutQuad(obj, 0.15).Scale = currentScale
				end,
			}).Scale = currentScale * 1.1
			sfx("waterdrop_3", { Spatialized = false, Pitch = 1 + math.random() * 0.1 })

			if trail ~= nil then
				trail:remove()
			end
			trail = require("trail"):create(Player, obj, TRAIL_COLOR, 0.5)

			if cameraMode == CameraMode.FREE then
				trail:hide()
			end

			transformGizmo = require("transformgizmo"):create({
				target = selectedObjectContainer,
				onChange = function(target) end,
				onDone = function(target)
					if selectedObject == nil then return end
					world.updateObject({
						uuid = selectedObject.uuid,
						Position = selectedObject.Position,
						Rotation = selectedObject.Rotation,
						Scale = selectedObject.Scale,
					})
					world.updateShadow(selectedObject)
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
			Dev.DisplayColliders = false
			objectNameInput.onTextChange = nil
			objectNameInput.Text = ""

			if transformGizmo then
				transformGizmo:remove()
				transformGizmo = nil
			end

			if selectedObject then
				if selectedObject.Parent == selectedObjectContainer then
					selectedObject:SetParent(World, true)
					selectedObject.Scale = selectedObjectContainer.Scale * selectedObject.Scale
				end
				
				unfreezeObject(selectedObject)
			end

			if trail ~= nil then
				trail:remove()
				trail = nil
			end

			objectInfoFrame:hide()
			saveWorld()
			selectedObject = nil
		end,
		pointerWheelPriority = function(delta)
			selectedObject:RotateWorld(Number3(0, 1, 0), math.pi * 0.0625 * (delta > 0 and 1 or -1))
			selectedObject.Rotation = selectedObject.Rotation -- trigger OnSetCallback
			world.updateObject({
				uuid = selectedObject.uuid,
				Rotation = target.Rotation,
			})
			return true
		end,
	},
	[states.DUPLICATE_OBJECT] = {
		onStateBegin = function(uuid)
			local obj = world.getObject(uuid)
			if not obj then
				print("error: can't duplicate this object")
				setState(states.DEFAULT)
				return
			end
			local objectInfo = copyObjectInfo(obj)
			local previousObj = obj
			spawnObject(objectInfo, function(obj)
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
			local obj = world.getObject(uuid)
			if not obj then
				print("error: can't remove this object (uuid: " .. uuid .. ")")
				setState(states.DEFAULT)
				return
			end
			obj:RemoveFromParent()
			world.removeObject(uuid)
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
	PointerLongPress = "pointerLongPress"
}

local function handleLocalEventListener(listenerName, pe)
	local stateSettings = statesSettings[state]
	local callback = stateSettings[listenerName]
	if callback then
		if callback(pe) then
			return true
		end
	end
end

for eventName, listenerName in pairs(listeners) do
	local event = LocalEvent.Name[eventName]
	-- Priority listener
	LocalEvent:Listen(event, function(pe)
		return handleLocalEventListener(listenerName .. "Priority", pe)
	end, { topPriority = true })
	-- Normal listener
	LocalEvent:Listen(event, function(pe)
		return handleLocalEventListener(listenerName, pe)
	end, { topPriority = false })
end

function loadEditedWorld()
	local worldID = Environment["EDITED_WORLD_ID"]
	require("api"):getWorld(worldID, { "mapBase64", "title" }, function(data, err)
		if err then
			print(err)
			return
		end

		world.load({
			b64 = data.mapBase64,
			title = data.title,
			worldID = worldID,
			addBasePlateIfNeeded = true,
			onDone = function(info)
				local ambienceAdded = false
				local ambience = world.getAmbience()
				if ambience == nil then
					ambienceAdded = true
					local a = require("ai_ambience"):loadGeneration(defaultAmbienceGeneration)
					world.updateAmbience(a)
				end
				setState(states.DEFAULT)
				startDefaultMode()
				if info.basePlateAdded or ambienceAdded then
					saveWorld()
				end
			end,
			onLoad = function(obj, objectInfo)
				if objectInfo == "Map" then
					if map then
						map:RemoveFromParent()
					end
					map = obj
					return
				end
				objectInfo.obj = obj
				spawnObject(objectInfo)
			end,
		})
	end)
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

	jumpfly:setup({
		airJumps = -1, -- infinite air jumps
		onFlyStart = function()
			setCameraMode(CameraMode.THIRD_PERSON_FLYING)
		end,
		onFlyEnd = function()
			setCameraMode(CameraMode.THIRD_PERSON)
		end,
	})

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

function uiShowDefaultMenu()
	if addObjectBtn ~= nil then
		addObjectBtn:show()
		return
	end

	addObjectBtn = ui:buttonSecondary({ 
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
	addObjectBtn:parentDidResize()
	addObjectBtn.onRelease = function()
		setState(states.GALLERY)
	end

	-- Gallery
	local galleryOnOpen = function(cell)
		local fullname = cell.repo .. "." .. cell.name
		setState(states.SPAWNING_OBJECT, { fullname = fullname })
	end
	local initGallery
	initGallery = function()
		gallery = require("gallery"):create(function() -- maxWidth
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
		gallery.didClose = function()
			setState(states.DEFAULT)
			initGallery()
		end
		gallery:hide()
	end
	initGallery()

	-- Placing
	newObjectCancelBtn = ui:createButton("❌")
	newObjectCancelBtn.onRelease = function()
		setState(states.DEFAULT)
		newObjectBeingPlaced:RemoveFromParent()
		newObjectBeingPlaced = nil
	end
	newObjectCancelBtn.parentDidResize = function()
		newObjectCancelBtn.pos = { Screen.Width * 0.5 - newObjectCancelBtn.Width * 0.5, newObjectCancelBtn.Height * 2 }
	end
	newObjectCancelBtn:parentDidResize()
	newObjectCancelBtn:hide()

	-- OBJECT INFO FRAME

	objectInfoFrame = ui:frameGenericContainer()

	objectNameInput = ui:createTextInput("", "Item Name", { textSize = "small" })
	objectNameInput:setParent(objectInfoFrame)

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
		objectNameInput.Width = width
		physicsBtn.Width = width
		duplicateBtn.Width = width
		deleteBtn.Width = width
		validateBtn.Width = width

		self.Height = objectNameInput.Height + padding
		+ physicsBtn.Height + padding
		+ duplicateBtn.Height + padding
		+ deleteBtn.Height + padding
		+ validateBtn.Height + padding
		+ padding

		local y = self.Height

		y -= objectNameInput.Height + padding
		objectNameInput.pos = { padding, y }

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
		hideAllPanels()

		require("controls"):turnOff()
		ambienceBtn:hide()
		cameraBtn:hide()
		walkModeBtn:hide()
		flyModeBtn:hide()

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
				local ambience = world.getAmbience()
				if ambience.sun.rotation then
					ambience.sun.rotation.Y = math.rad(v)
					world.updateAmbience(ambience)
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
				local ambience = world.getAmbience()
				if ambience.sun.rotation then
					ambience.sun.rotation.X = math.rad(v)
					world.updateAmbience(ambience)
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
					world.updateAmbience(loadedAmbiance)
					sunRotationSlider:setValue(math.floor(math.deg(loadedAmbiance.sun.rotation.Y)))
					sunRotationXSlider:setValue(math.floor(math.deg(loadedAmbiance.sun.rotation.X)))
					aiInput:show()
					aiBtn:show()
					loading:hide()
					saveWorld()
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
			hideAllPanels()
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

			btnClose.pos = {
				self.Width * 0.5 - btnClose.Width * 0.5,
				padding,
			}

			scroll.pos.Y = btnClose.pos.Y + btnClose.Height + padding
			scroll.pos.X = padding
			scroll.Height = aiInput.pos.Y - padding - scroll.pos.Y
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

	local cameraIcon = ui:frame({ image = {
		data = Data:FromBundle("images/icon-camera.png"),
		alpha = true,
	} })
	cameraIcon.Width = 20 cameraIcon.Height = 20
	cameraBtn = ui:buttonSecondary({ content = cameraIcon })
	cameraBtn.onRelease = function()
		setCameraMode(CameraMode.FREE)
	end

	local walkIcon = ui:frame({ image = {
		data = Data:FromBundle("images/icon-walk.png"),
		alpha = true,
	} })
	walkIcon.Width = 20 walkIcon.Height = 20
	walkModeBtn = ui:buttonSecondary({ content = walkIcon })
	walkModeBtn.onRelease = function()
		setCameraMode(CameraMode.THIRD_PERSON)
	end

	local flyIcon = ui:frame({ image = {
		data = Data:FromBundle("images/icon-jetpack.png"),
		alpha = true,
	} })
	flyIcon.Width = 20 flyIcon.Height = 20
	flyModeBtn = ui:buttonSecondary({ content = flyIcon })
	flyModeBtn.onRelease = function()
		setCameraMode(CameraMode.THIRD_PERSON_FLYING)
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

		walkModeBtn.pos = {
			cameraBtn.pos.X + cameraBtn.Width + padding,
			cameraBtn.pos.Y,
		}

		flyModeBtn.pos = {
			walkModeBtn.pos.X + walkModeBtn.Width + padding,
			cameraBtn.pos.Y,
		}
	end
	cameraBtn:parentDidResize()
	
end

-- Auto-save timer
local autoSaveTimer = nil
function saveWorld()
	if autoSaveTimer ~= nil then
		autoSaveTimer:Cancel()
	end
	if state >= states.DEFAULT then
		world.save()
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
