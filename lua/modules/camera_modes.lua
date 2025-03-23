cameraModes = {}

-- each entry is a table with:
--[[
{
	config = { camera, target, targetIsPlayer, ... },
	listeners = {},
}
--]]
cameras = {}

conf = require("config")

worldObject = Object() -- object in World used to compute positions
worldObject:SetParent(World)

function clearListeners(entry)
	if type(entry.listeners) ~= "table" then
		error("camera_modes - internal error (1)")
	end
	for _, listener in ipairs(entry.listeners) do
		listener:Remove()
	end
	entry.listeners = {}
end

function remove(entry)
	clearListeners(entry)
	cameras[entry.config.camera] = nil
end

function insert(config)
	local camera = config.camera

	if typeof(camera) ~= "Camera" then
		error("camera_modes - internal error (2)")
	end

	local c = cameras[camera]
	if c then
		remove(c)
	end

	camera.Tick = nil

	local entry = {
		config = config,
		listeners = {},
	}
	cameras[camera] = entry

	return entry
end

function showAvatar(entry)
	if not entry.config.targetIsPlayer then
		return
	end

	local player = entry.config.target

	player.Head.IsHidden = false
	player.Head.IsHiddenSelf = false
	player.Body.IsHiddenSelf = false
	player.RightArm.IsHiddenSelf = false
	player.LeftArm.IsHiddenSelf = false
	player.RightHand.IsHiddenSelf = false
	player.LeftHand.IsHiddenSelf = false
	player.RightLeg.IsHiddenSelf = false
	player.LeftLeg.IsHiddenSelf = false
	player.RightFoot.IsHiddenSelf = false
	player.LeftFoot.IsHiddenSelf = false

	player.Avatar:updateConfig({
		eyeBlinks = true,
		hiddenEquipments = {},
	})
end

function hideAvatar(entry)
	if not entry.config.targetIsPlayer then
		return
	end

	local player = entry.config.target

	player.Head.IsHidden = false
	player.Head.IsHiddenSelf = true
	player.Body.IsHiddenSelf = true
	player.RightArm.IsHiddenSelf = true
	player.LeftArm.IsHiddenSelf = true
	player.RightHand.IsHiddenSelf = true
	player.LeftHand.IsHiddenSelf = true
	player.RightLeg.IsHiddenSelf = true
	player.LeftLeg.IsHiddenSelf = true
	player.RightFoot.IsHiddenSelf = true
	player.LeftFoot.IsHiddenSelf = true

	player.Avatar:updateConfig({
		eyeBlinks = false,
		hiddenEquipments = { "hair", "jacket", "pants", "boots" },
	})
end

function turnOffPhysics(camera)
	camera.Physics = PhysicsMode.Disabled
	camera.CollisionGroups = {}
	camera.CollidesWithGroups = {}
end

cameraModes.setFree = function(self, config)
	if self ~= cameraModes then
		error("camera_modes:setFree(config) should be called with `:`", 2)
	end
	if config ~= nil and type(config) ~= "table" then
		error("camera_modes:setFree(config) - config should be a table", 2)
	end

	config = { camera = config.camera or Camera }
	local camera = config.camera

	insert(config)

	turnOffPhysics(config.camera)

	-- `true` parameter allows to maintain the World position
	camera:SetParent(World, true)
end

cameraModes.setSatellite = function(self, config)
	if self ~= cameraModes then
		error("camera_modes:setSatellite(config) should be called with `:`", 2)
	end
	if type(config) ~= "table" then
		error("camera_modes:setSatellite(config) - config should be a table", 2)
	end
	local _config = { -- default config
		camera = Camera, -- main Camera by default
		target = nil, -- must be set
		distance = 30,
	}

	if config then
		for k, v in pairs(_config) do
			if typeof(config[k]) == typeof(v) then
				_config[k] = config[k]
			end
		end
		_config.target = config.target
	end

	if _config.target == nil then
		error("camera_modes:setSatellite(config) - config.target can't be nil", 2)
	end

	if
		type(_config.target) == "table"
		and type(_config.target[1]) == "number"
		and type(_config.target[2]) == "number"
		and type(_config.target[3]) == "number"
	then
		_config.target = Number3(_config.target)
	end

	config = _config

	local entry = insert(config)

	local camera = config.camera

	turnOffPhysics(camera)
	camera:SetParent(World, true)

	local refresh = function()
		local target = config.target.Position or config.target
		camera.Position = target - camera.Forward * config.distance
	end

	listener = LocalEvent:Listen(LocalEvent.Name.Tick, function()
		refresh()
	end)
	table.insert(entry.listeners, listener)
	refresh()
end

cameraModes.setFirstPerson = function(self, config)
	if self ~= cameraModes then
		error("camera_modes:setFirstPerson(config) should be called with `:`", 2)
	end
	if type(config) ~= "table" then
		error("camera_modes:setFirstPerson(config) - config should be a table", 2)
	end

	local _config = { -- default config
		showPointer = false,
		camera = Camera, -- main Camera by default
		target = nil, -- must be set
		offset = Number3(0, 0, 0),
	}

	if config then
		for k, v in pairs(_config) do
			if typeof(config[k]) == typeof(v) then
				_config[k] = config[k]
			end
		end
		_config.target = config.target
	end

	if _config.target == nil then
		error("camera_modes:setFirstPerson(config) - config.target can't be nil", 2)
	end

	_config.targetIsPlayer = typeof(_config.target) == "Player"

	config = _config
	local camera = config.camera

	local entry = insert(config)

	turnOffPhysics(camera)

	if config.targetIsPlayer then
		camera:SetParent(config.target.Head)
	else
		camera:SetParent(config.target)
	end

	if config.offset then
		camera.LocalPosition:Set(config.offset)
	else
		camera.LocalPosition:Set(Number3.Zero)
	end

	camera.LocalRotation:Set(0, 0, 0)

	if config.showPointer then
		Pointer:Show()
	else
		Pointer:Hide()
	end

	hideAvatar(entry)
end

cameraModes.setThirdPerson = function(self, config)
	if self ~= cameraModes then
		error("camera_modes:setThirdPerson(config) should be called with `:`", 2)
	end

	local defaultConfig = { -- default config
		showPointer = true,
		distance = 40,
		minDistance = 0,
		maxDistance = 75,
		camera = Camera, -- main Camera by default
		target = nil, -- must be set
		offset = nil, -- offset from target
		rotationOffset = nil,
		rotation = nil,
		rigidity = 0.5,
		collidesWithGroups = Map.CollisionGroups,
		rotatesWithTarget = true,
	}

	config = conf:merge(defaultConfig, config, {
		acceptTypes = {
			target = { "Object", "Shape", "MutableShape", "Number3", "Player", "Quad" },
			offset = { "Number3" },
			rotationOffset = { "Rotation", "Number3", "table" },
			rotation = { "Rotation", "Number3", "table" },
			collidesWithGroups = { "CollisionGroups", "table" },
		},
	})

	if config.target == nil then
		error("camera_modes:setThirdPerson(config) - config.target can't be nil", 2)
	end

	-- NOTE (aduermael): it would be nice to remove this hardcoded system for Players
	config.targetIsPlayer = typeof(config.target) == "Player"

	local entry = insert(config)

	turnOffPhysics(config.camera)

	local camera = config.camera
	local showPointer = config.showPointer
	local minDistance = config.minDistance
	local maxDistance = config.maxDistance
	local target = config.target
	local collidesWithGroups = config.collidesWithGroups
	local offset = config.offset or Number3.Zero
	local rotationOffset = config.rotationOffset or Rotation(0, 0, 0)
	local targetIsPlayer = typeof(target) == "Player"
	local targetHasRotation = typeof(target) == "Object"
		or typeof(target) == "Shape"
		or typeof(target) == "MutableShape"
	local rotatesWithTarget = config.rotatesWithTarget

	camera:SetParent(World)
	if config.rotation then
		if not pcall(function()
			worldObject.Rotation:Set(config.rotation)
		end) then
			error("can't set camera rotation", 2)
		end
	end

	if showPointer then
		Pointer:Show()
	else
		Pointer:Hide()
	end

	local camDistance = config.distance
	local listener

	listener = LocalEvent:Listen(LocalEvent.Name.PointerWheel, function(delta)
		camDistance = camDistance + delta * 0.1
		camDistance = math.min(maxDistance, camDistance)
		camDistance = math.max(minDistance, camDistance)
	end)
	table.insert(entry.listeners, listener)

	local boxHalfSize = Number3(1, 1, 1)
	local box = Box()
	local impact
	local distance
	local rigidityFactor = config.rigidity * 60.0
	local lerpFactor

	listener = LocalEvent:Listen(LocalEvent.Name.Tick, function(dt)
		worldObject.Position:Set(target.Position + offset)

		if targetIsPlayer then
			worldObject.Position.Y = worldObject.Position.Y + target.CollisionBox.Max.Y * target.Scale.Y
			if rotatesWithTarget then
				worldObject.Rotation:Set(target.Head.Rotation * rotationOffset)
			end
		elseif targetHasRotation then
			if rotatesWithTarget then
				worldObject.Rotation:Set(target.Rotation * rotationOffset)
			else
				worldObject.Rotation:Set(rotationOffset)
			end
		else
			worldObject.Rotation:Set(rotationOffset)
		end

		box.Min = worldObject.Position - boxHalfSize -- box.Min:Set doesn't work
		box.Max = worldObject.Position + boxHalfSize -- box.Max:Set doesn't work

		impact = box:Cast(Number3.Up, 3, collidesWithGroups)

		distance = 3
		if impact and impact.Distance < distance then
			distance = impact.Distance
		end

		worldObject.Position = worldObject.Position + Number3.Up * distance

		box.Min = worldObject.Position - boxHalfSize -- box.Min:Set doesn't work
		box.Max = worldObject.Position + boxHalfSize -- box.Max:Set doesn't work

		impact = box:Cast(camera.Backward, camDistance, collidesWithGroups)

		if camDistance < 4 then -- in Head, make it invisible
			if targetIsPlayer then
				hideAvatar(entry)
				if target.equipments.hair then
					target.equipments.hair.IsHiddenSelf = true
				end
			end
		else
			if targetIsPlayer then
				showAvatar(entry)
				if target.equipments.hair then
					target.equipments.hair.IsHiddenSelf = false
				end
			end
		end

		distance = camDistance
		if impact and impact.Distance < distance then
			distance = impact.Distance * 0.95
		end

		lerpFactor = math.min(rigidityFactor * dt, 1.0)
		camera.Position:Lerp(camera.Position, worldObject.Position + worldObject.Backward * distance, lerpFactor)
		camera.Rotation:Slerp(camera.Rotation, worldObject.Rotation, lerpFactor)
	end)
	table.insert(entry.listeners, listener)
end

cameraModes.setConfig = function(self, config)
	if self ~= cameraModes then
		error("camera_modes:setConfig(config) should be called with `:`", 2)
	end

	local defaultConfig = {
		camera = Camera, -- main Camera by default
		positionTarget = nil, -- target to follow
		positionTargetOffset = nil, -- offset from the target
		positionTargetBackoffDistance = 40, -- distance from the target
		positionTargetMinBackoffDistance = 0, -- minimum distance from the target
		positionTargetMaxBackoffDistance = 75, -- maximum distance from the target
		rotationTarget = nil, -- target to rotate to (if target has a rotation then rotates to target.Rotation)
		rotationTargetOffset = nil, -- offset from the rotation target
		rigidity = 0.5, -- rigidity of the camera
		collidesWithGroups = nil, -- doesn't collide with anything by default
		collisionBoxSize = Number3(2, 2, 2)
	}

	config = conf:merge(defaultConfig, config, {
		acceptTypes = {
			camera = { "Camera" },
			positionTarget = { "Object", "Shape", "MutableShape", "Number3", "Player", "Quad", "Mesh" },
			positionTargetOffset = { "Number3", "table" },
			rotationTarget = { "Object", "Shape", "MutableShape", "Number3", "Player", "Quad", "Mesh" },
			rotationTargetOffset = { "Rotation", "Number3", "table" },
			collidesWithGroups = { "CollisionGroups", "table" },
		},
	})

	config.version = 2

	local entry = insert(config)

	turnOffPhysics(config.camera)

	local camera = config.camera

	-- position
	local positionTarget
	if config.positionTarget ~= nil then
		if typeof(config.positionTarget) == "Number3" then
			positionTarget = config.positionTarget
		elseif typeof(config.positionTarget.Position) == "Number3" then
			positionTarget = config.positionTarget.Position
		else
			error("can't assign position target", 2)
		end
	end
	local positionTargetOffset = config.positionTargetOffset or Number3.Zero
	local distance = config.positionTargetBackoffDistance
	local minDistance = config.positionTargetMinBackoffDistance
	local maxDistance = config.positionTargetMaxBackoffDistance
	
	-- rotation
	local rotationTarget
	if config.rotationTarget ~= nil then
		if typeof(config.rotationTarget) == "Rotation" then
			rotationTarget = config.rotationTarget
		elseif typeof(config.rotationTarget) == "Number3" then
			rotationTarget = Rotation(config.rotationTarget)
		elseif typeof(config.rotationTarget.Rotation) == "Rotation" then
			rotationTarget = config.rotationTarget.Rotation
		else
			error("can't assign rotation target", 2)
		end
	end
	local rotationTargetOffset = config.rotationTargetOffset or Rotation(0, 0, 0)
	
	-- others
	local rigidity = config.rigidity
	local collidesWithGroups = config.collidesWithGroups
	local collisionBoxSize = config.collisionBoxSize

	camera:SetParent(World)

	if distance < minDistance then
		minDistance = distance
	elseif distance > maxDistance then
		maxDistance = distance
	end

	local listener
	listener = LocalEvent:Listen(LocalEvent.Name.PointerWheel, function(delta)
		distance = distance + delta * 0.1
		distance = math.min(maxDistance, distance)
		distance = math.max(minDistance, distance)
	end)
	table.insert(entry.listeners, listener)

	local boxHalfSize = collisionBoxSize * 0.5
	local box = Box()
	local rigidityFactor = config.rigidity * 60.0
	local impact
	local lerpFactor
	local backoffDistance

	listener = LocalEvent:Listen(LocalEvent.Name.Tick, function(dt)

		if rotationTarget ~= nil then
			worldObject.Rotation:Set(rotationTargetOffset * rotationTarget)
		else
			worldObject.Rotation:Set(rotationTargetOffset * camera.Rotation)
		end

		if positionTarget ~= nil then
			worldObject.Position:Set(positionTarget + positionTargetOffset)

			box.Min = worldObject.Position - boxHalfSize -- box.Min:Set doesn't work
			box.Max = worldObject.Position + boxHalfSize -- box.Max:Set doesn't work
			
			impact = box:Cast(worldObject.Backward, distance, collidesWithGroups)
			
			backoffDistance = distance
			if impact and impact.Distance < backoffDistance then
				backoffDistance = impact.Distance
			end

			lerpFactor = math.min(rigidityFactor * dt, 1.0)

			camera.Position:Lerp(camera.Position, worldObject.Position + worldObject.Backward * backoffDistance, lerpFactor)
			camera.Rotation:Slerp(camera.Rotation, worldObject.Rotation, lerpFactor)
		end
	end)
	table.insert(entry.listeners, listener)
end

return cameraModes
