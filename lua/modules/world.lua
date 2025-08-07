-- world.lua
-- Core module used to load, and save worlds.
-- Used by all worlds to load worlds created with the world editor.
-- Current version: 3

local world = {}

local MAP_SCALE_DEFAULT = 5
local SERIALIZE_VERSION = 3

local COLLISION_GROUP_MAP = CollisionGroups(1)
local COLLISION_GROUP_PLAYER = CollisionGroups(2)
local COLLISION_GROUP_OBJECT = CollisionGroups(3)

local SERIALIZED_CHUNKS_ID = {
	MAP = 0,
	AMBIENCE = 1,
	OBJECTS = 2,
	BLOCKS = 3, -- DEPRECATED: Not used anymore but kept for backward compatibility
}

-- State tracking
local loaded = {
	b64 = nil,
	title = nil,
	worldID = nil,
	ambience = nil,
	objectsByUUID = {}, -- entries are of type Object (same references as in the World Object)
	-- indexed by uuid, contains source of through information for each Object.
	-- example: an Object in the scene (World Object temporarily uses Disabled physics,
	-- in the context of world edition for example, but we don't want to save it as such.
	-- Fields from objectsInfo instances always prevail over the World Object ones.
	objectsInfo = {},
	minimum_item_size_for_shadows_sqr = 1,
	-- not used anymore, some old worlds might still have it
	map = nil,
	mapName = nil,
	mapScale = nil,
}

-- Ambience field definitions with serialization/deserialization functions
local ambienceFields = { -- key, serialize and deserialize functions
	["sky.skyColor"] = {
		"ssc",
		function(d, v)
			if typeof(v) == "Color" then
				d:WriteColor(v)
			else
				d:WriteColor(Color(math.floor(v[1]), math.floor(v[2]), math.floor(v[3])))
			end
		end,
		function(d)
			return d:ReadColor()
		end,
	},
	["sky.horizonColor"] = {
		"shc",
		function(d, v)
			if typeof(v) == "Color" then
				d:WriteColor(v)
			else
				d:WriteColor(Color(math.floor(v[1]), math.floor(v[2]), math.floor(v[3])))
			end
		end,
		function(d)
			return d:ReadColor()
		end,
	},
	["sky.abyssColor"] = {
		"sac",
		function(d, v)
			if typeof(v) == "Color" then
				d:WriteColor(v)
			else
				d:WriteColor(Color(math.floor(v[1]), math.floor(v[2]), math.floor(v[3])))
			end
		end,
		function(d)
			return d:ReadColor()
		end,
	},
	["sky.lightColor"] = {
		"slc",
		function(d, v)
			if typeof(v) == "Color" then
				d:WriteColor(v)
			else
				d:WriteColor(Color(math.floor(v[1]), math.floor(v[2]), math.floor(v[3])))
			end
		end,
		function(d)
			return d:ReadColor()
		end,
	},
	["sky.lightIntensity"] = {
		"sli",
		function(d, v)
			d:WriteFloat(v)
		end,
		function(d)
			return d:ReadFloat()
		end,
	},
	["fog.color"] = {
		"foc",
		function(d, v)
			if typeof(v) == "Color" then
				d:WriteColor(v)
			else
				d:WriteColor(Color(math.floor(v[1]), math.floor(v[2]), math.floor(v[3])))
			end
		end,
		function(d)
			return d:ReadColor()
		end,
	},
	["fog.near"] = {
		"fon",
		function(d, v)
			d:WriteFloat(v)
		end,
		function(d)
			return d:ReadFloat()
		end,
	},
	["fog.far"] = {
		"fof",
		function(d, v)
			d:WriteFloat(v)
		end,
		function(d)
			return d:ReadFloat()
		end,
	},
	["fog.lightAbsorbtion"] = {
		"foa",
		function(d, v)
			d:WriteFloat(v)
		end,
		function(d)
			return d:ReadFloat()
		end,
	},
	["sun.color"] = {
		"suc",
		function(d, v)
			if typeof(v) == "Color" then
				d:WriteColor(v)
			else
				d:WriteColor(Color(math.floor(v[1]), math.floor(v[2]), math.floor(v[3])))
			end
		end,
		function(d)
			return d:ReadColor()
		end,
	},
	["sun.intensity"] = {
		"sui",
		function(d, v)
			d:WriteFloat(v)
		end,
		function(d)
			return d:ReadFloat()
		end,
	},
	["sun.rotation"] = {
		"sur",
		function(d, v)
			d:WriteFloat(v.X)
			d:WriteFloat(v.Y)
		end,
		function(d)
			local x = d:ReadFloat()
			local y = d:ReadFloat()
			return Rotation(x, y, 0)
		end,
	},
	["ambient.skyLightFactor"] = {
		"asl",
		function(d, v)
			d:WriteFloat(v)
		end,
		function(d)
			return d:ReadFloat()
		end,
	},
	["ambient.dirLightFactor"] = {
		"adl",
		function(d, v)
			d:WriteFloat(v)
		end,
		function(d)
			return d:ReadFloat()
		end,
	},
}

-- Helper for writing a color regardless of input type
local writeColor = function(d, v)
	if typeof(v) == "Color" then
		d:WriteColor(v)
	else
		d:WriteColor(Color(math.floor(v[1]), math.floor(v[2]), math.floor(v[3])))
	end
end

-- Serialization Functions
-- ----------------------

-- Write map chunk to data stream
local writeChunkMap = function(d, name, scale)
	if name == nil or scale == nil then
		error("can't serialize map", 2)
		return false
	end
	d:WriteByte(SERIALIZED_CHUNKS_ID.MAP)
	d:WriteDouble(scale)
	d:WriteUInt32(#name)
	d:WriteString(name)
	return true
end

-- Read map chunk from data stream
local readChunkMap = function(d)
	local scale = d:ReadDouble()
	local len = d:ReadUInt32()
	local name = d:ReadString(len)
	return name, scale
end

-- Write ambience chunk to data stream
local writeChunkAmbience = function(d, ambience)
	if ambience == nil then
		error("can't serialize ambience chunk", 2)
		return false
	end
	d:WriteByte(SERIALIZED_CHUNKS_ID.AMBIENCE)
	local cursorLengthField = d.Cursor
	d:WriteUInt16(0) -- temporary write size
	
	local fieldsList = {}

	for k1, v1 in pairs(ambience) do
		if type(v1) == "string" then
			table.insert(fieldsList, {
				"txt",
				v1,
				function(d, name)
					d:WriteUInt8(#name)
					d:WriteString(name)
				end,
			})
		elseif type(v1) == "table" then
			for k2, v2 in pairs(v1) do
				local ambienceField = ambienceFields[k1 .. "." .. k2]
				if ambienceField then
					local key = ambienceField[1] -- get key
					local serializeFunction = ambienceField[2]
					table.insert(fieldsList, { key, v2, serializeFunction })
				end
			end
		end
	end
	
	local nbFields = #fieldsList
	d:WriteUInt8(nbFields)
	
	for _, value in ipairs(fieldsList) do
		d:WriteString(value[1]) -- all keys are 3 letters
		local serializeFunction = value[3]
		serializeFunction(d, value[2])
	end

	-- Update size field
	local size = d.Cursor - cursorLengthField
	d.Cursor = cursorLengthField
	d:WriteUInt16(size)
	d.Cursor = d.Length

	return true
end

-- Read ambience chunk from data stream
local readChunkAmbience = function(d)
	local ambience = {}
	d:ReadUInt16() -- read size
	local nbFields = d:ReadUInt8()
	
	for _ = 1, nbFields do
		local key = d:ReadString(3)
		local found = false
		
		for fullFieldName, v in pairs(ambienceFields) do
			if v[1] == key then
				local value = v[3](d) -- read value
				local category, name = fullFieldName:gsub("%.(.*)", ""), fullFieldName:match("%.(.*)")
				ambience[category] = ambience[category] or {}
				ambience[category][name] = value
				found = true
				break
			end
		end
		
		if not found then
			if key == "txt" then
				local length = d:ReadUInt8()
				ambience.text = d:ReadString(length)
			else
				error("unknown key " .. key, 2)
			end
		end
	end
	
	return ambience
end

-- Group objects by fullname for efficient serialization
local groupObjects = function(objectsInfo)
	local t = {}
	for uuid, objectInfo in objectsInfo do
		if not t[objectInfo.fullname] then
			t[objectInfo.fullname] = {}
		end
		table.insert(t[objectInfo.fullname], objectInfo)
	end
	return t
end

-- Write objects chunk to data stream
local writeChunkObjects = function(d, world)
	if world.objectsInfo == nil or world.objectsByUUID == nil then
		error("can't serialize objects chunk", 2)
		return false
	end
	
	d:WriteByte(SERIALIZED_CHUNKS_ID.OBJECTS)
	local cursorLengthField = d.Cursor
	d:WriteUInt32(0) -- temporary write size

	local objectsGrouped = groupObjects(world.objectsInfo)
	local nbObjects = world.nbObjects
	d:WriteUInt16(nbObjects)
	
	for fullname, group in objectsGrouped do
		d:WriteUInt16(#fullname)
		d:WriteString(fullname)
		d:WriteUInt16(#group)

		for _, objectInfo in ipairs(group) do
			local cursorNbFields = d.Cursor
			local nbFields = 0
			d:WriteUInt8(0) -- temporary nbFields

			if objectInfo.uuid then
				d:WriteString("id")
				d:WriteUInt8(#objectInfo.uuid)
				d:WriteString(objectInfo.uuid)
				nbFields = nbFields + 1
			end
			
			if objectInfo.Position and objectInfo.Position ~= Number3(0, 0, 0) then
				d:WriteString("po")
				d:WriteNumber3(objectInfo.Position)
				nbFields = nbFields + 1
			end
			
			if objectInfo.Rotation and objectInfo.Rotation ~= Rotation(0, 0, 0) then
				d:WriteString("ro")
				d:WriteRotation(objectInfo.Rotation)
				nbFields = nbFields + 1
			end
			
			if objectInfo.Scale and objectInfo.Scale ~= Number3(1, 1, 1) then
				d:WriteString("sc")
				if type(object.Scale) == "number" then
					objectInfo.Scale = objectInfo.Scale * Number3(1, 1, 1)
				end
				d:WriteNumber3(objectInfo.Scale)
				nbFields = nbFields + 1
			end
			
			if objectInfo.Name and objectInfo.Name ~= objectInfo.fullname then
				d:WriteString("na")
				d:WriteUInt8(#objectInfo.Name)
				d:WriteString(objectInfo.Name)
				nbFields = nbFields + 1
			end
			
			if objectInfo.Physics ~= nil then
				d:WriteString("pm")
				d:WritePhysicsMode(objectInfo.Physics)
				nbFields = nbFields + 1
			end

			if objectInfo.CollisionGroups ~= nil then
				d:WriteString("cg")
				d:WriteCollisionGroups(objectInfo.CollisionGroups)
				nbFields = nbFields + 1
			end

			if objectInfo.CollidesWithGroups ~= nil then
				d:WriteString("cw")
				d:WriteCollisionGroups(objectInfo.CollidesWithGroups)
				nbFields = nbFields + 1
			end

			-- Update nbFields value
			d.Cursor = cursorNbFields
			d:WriteUInt8(nbFields)
			d.Cursor = d.Length
		end
	end

	-- Update size field
	local size = d.Cursor - cursorLengthField
	d.Cursor = cursorLengthField
	d:WriteUInt32(size)
	d.Cursor = d.Length

	return true
end

-- Read objects chunk from data stream (for version 3)
local readChunkObjects = function(d)
	local objectsInfo = {}
	d:ReadUInt32() -- read size
	local nbObjects = d:ReadUInt16()
	local fetchedObjects = 0
	
	while fetchedObjects < nbObjects do
		local fullnameSize = d:ReadUInt16()
		local fullname = d:ReadString(fullnameSize)
		local nbInstances = d:ReadUInt16()
		
		for _ = 1, nbInstances do
			local instance = {
				fullname = fullname,
			}
			
			local nbFields = d:ReadUInt8()
			for _ = 1, nbFields do
				local key = d:ReadString(2)
				
				if key == "po" then
					instance.Position = d:ReadNumber3()
				elseif key == "ro" then
					instance.Rotation = d:ReadRotation()
				elseif key == "sc" then
					instance.Scale = d:ReadNumber3()
				elseif key == "na" then
					local nameLength = d:ReadUInt8()
					instance.Name = d:ReadString(nameLength)
				elseif key == "id" then
					local idLength = d:ReadUInt8()
					instance.uuid = d:ReadString(idLength)
				elseif key == "pm" then
					instance.Physics = d:ReadPhysicsMode()
				elseif key == "cg" then
					instance.CollisionGroups = d:ReadCollisionGroups()
				elseif key == "cw" then
					instance.CollidesWithGroups = d:ReadCollisionGroups()
				else
					error("Wrong format while deserializing", 2)
					return false
				end
			end
			
			if instance.uuid == nil then
				error("Object has no uuid")
			end
			objectsInfo[instance.uuid] = instance
			fetchedObjects = fetchedObjects + 1
		end
	end
	
	return objectsInfo, fetchedObjects
end

-- Read blocks chunk (deprecated but needed for compatibility)
local readChunkBlocks = function(d)
	local blocks = {}
	d:ReadUInt16()
	local nbBlocks = d:ReadUInt16()
	
	for _ = 1, nbBlocks do
		d:ReadUInt16() -- keyLength
		d:ReadString() -- key
		local blockAction = d:ReadUInt8()
		
		if blockAction == 1 then -- add
			d:ReadColor() -- color
		end
	end
	
	return blocks
end

-- Serialize a world to base64 string
local serializeWorldBase64 = function(world)
	local d = Data()
	d:WriteByte(SERIALIZE_VERSION) -- version
	
	if loaded.mapName then
		if loaded.mapScale ~= nil then
			writeChunkMap(d, loaded.mapName, loaded.mapScale)
		else
			writeChunkMap(d, loaded.mapName, MAP_SCALE_DEFAULT)
		end
	end
	
	if world.ambience then
		writeChunkAmbience(d, world.ambience)
	end
	
	if world.nbObjects > 0 then
		writeChunkObjects(d, world)
	end
	
	return d:ToString({ format = "base64" })
end

-- Deserialize a world from base64 string
local deserializeWorldBase64 = function(str)
	local world = {
		objectsInfo = {},
		nbObjects = 0,
		mapName = nil,
		mapScale = nil,
		ambience = nil,
	}
	
	if str == nil then
		return world
	end
	
	local d = Data(str, { format = "base64" })
	local version = d:ReadByte()
	
	if version == 2 or version == 3 then
		while d.Cursor < d.Length do
			local chunk = d:ReadByte()
			if chunk == SERIALIZED_CHUNKS_ID.MAP then
				world.mapName, world.mapScale = readChunkMap(d)
			elseif chunk == SERIALIZED_CHUNKS_ID.AMBIENCE then
				world.ambience = readChunkAmbience(d)
			elseif chunk == SERIALIZED_CHUNKS_ID.OBJECTS then
				if version == 2 then
					world.objectsInfo, world.nbObjects = require("world_v2").readChunkObjects(d)
				else
					world.objectsInfo, world.nbObjects = readChunkObjects(d)
				end
			elseif chunk == SERIALIZED_CHUNKS_ID.BLOCKS then
				readChunkBlocks(d) -- Not used but need to read to move cursor
			end
		end
	else -- just a table
		d.Cursor = 0
		world = d:ToTable()
	end
	
	return world
end

-- World Operations
-- ---------------

-- Generate a UUID v4
world.uuidv4 = function()
	local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
	return string.gsub(template, "[xy]", function(c)
		local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
		return string.format("%x", v)
	end)
end

-- Update shadow properties based on object size
world.updateShadow = function(obj) 
	local castShadow = false 

	if loaded.minimum_item_size_for_shadows_sqr ~= nil then
		local box = Box()
		box:Fit(obj, true)
		castShadow = box.Size.SquaredLength >= loaded.minimum_item_size_for_shadows_sqr
	end

	obj:Recurse(function(l)
		if typeof(l.Shadow) == "boolean" then
			l.Shadow = castShadow
		end
	end, { includeRoot = true })
end

-- Load an object into the world
local function loadObject(obj, objInfo)
	if loaded.objectsByUUID == nil then
		return
	end

	loaded.objectsByUUID[objInfo.uuid] = obj
	obj:SetParent(World)

	local k = Box()
	k:Fit(obj, true)
	if obj.Pivot then
		obj.Pivot = Number3(obj.Width * 0.5, k.Min.Y + obj.Pivot.Y, obj.Depth * 0.5)
	end

	obj.Position = objInfo.Position or Number3(0, 0, 0)
	obj.Rotation = objInfo.Rotation or Rotation(0, 0, 0)
	obj.Scale = objInfo.Scale or 0.5
	obj.uuid = objInfo.uuid
	if objInfo.CollisionGroups ~= nil then
		obj.CollisionGroups = objInfo.CollisionGroups
	else
		obj.CollisionGroups = COLLISION_GROUP_OBJECT
	end
	if objInfo.CollidesWithGroups ~= nil then
		obj.CollidesWithGroups = objInfo.CollidesWithGroups
	else
		obj.CollidesWithGroups = COLLISION_GROUP_MAP + COLLISION_GROUP_PLAYER
	end

	obj.Name = objInfo.Name or objInfo.fullname
	obj.fullname = objInfo.fullname

	local physics = objInfo.Physics or PhysicsMode.StaticPerBlock
	obj:Recurse(function(o)
		if o.Physics == nil or typeof(o) == "Object" then
			return
		end
		o.Physics = physics
	end, { includeRoot = true })

	world.updateShadow(obj)
end

-- Load a map into the world
local function loadMap(d, n, didLoad)
	Object:Load(d, function(j)
		local map = MutableShape(j, { recurse = true })
		loaded.map = map
		if n ~= nil then
			map.Scale = n
		else
			map.Scale = MAP_SCALE_DEFAULT
		end
		map:Recurse(function(o)
			o.CollisionGroups = COLLISION_GROUP_MAP
			o.CollidesWithGroups = COLLISION_GROUP_OBJECT + COLLISION_GROUP_PLAYER
			o.Physics = PhysicsMode.StaticPerBlock
		end, { includeRoot = true })
		map:SetParent(World)
		map.Position = { 0, 0, 0 }
		map.Pivot = { 0, 0, 0 }
		
		if didLoad then
			didLoad()
		end
	end)
end

world.getObject = function(uuid)
	if loaded.objectsByUUID == nil or uuid == nil then
		return nil
	end
	return loaded.objectsByUUID[uuid]
end

world.getObjectInfo = function(uuid)
	if loaded.objectsInfo == nil or uuid == nil then
		return nil
	end
	return loaded.objectsInfo[uuid]
end

-- Add an object to the loaded world
world.addObject = function(obj)
	if loaded == nil then
		return
	end

	if obj.uuid ~= nil and loaded.objectsByUUID[obj.uuid] ~= nil then 
		error("object already exists")
	end
	
	obj.uuid = world.uuidv4()
	loaded.objectsByUUID[obj.uuid] = obj
	loaded.objectsInfo[obj.uuid] = {
		uuid = obj.uuid,
		fullname = obj.fullname,
		Name = obj.Name,
		Position = obj.Position:Copy(),
		Rotation = obj.Rotation:Copy(),
		Scale = obj.Scale:Copy(),
		Physics = obj.Physics,
		CollisionGroups = COLLISION_GROUP_OBJECT, -- default collision group
		CollidesWithGroups = COLLISION_GROUP_MAP + COLLISION_GROUP_PLAYER,
	}
	loaded.nbObjects += 1
end

-- Default update config for objects
local defaultUpdateConfig = {
	uuid = nil,
	position = nil,
	rotation = nil,
	scale = nil,
	name = nil,
	physics = nil,
}

-- Update an object in the loaded world
world.updateObject = function(config)
	local ok, err = pcall(function()
		config = require("config"):merge(defaultUpdateConfig, config, {
			acceptTypes = {
				uuid = { "string" },
				Position = { "Number3" },
				Rotation = { "Rotation" },
				Scale = { "Number3", "number", "integer" },
				Name = { "string" },
				Physics = { "PhysicsMode" },
				CollisionGroups = { "CollisionGroups" },
				CollidesWithGroups = { "CollisionGroups" },
			},
		})
	end)
	
	if not ok then
		error("world_loader:updateObject(config) - config error: " .. err, 2)
	end
	
	if config.uuid == nil or loaded.objectsByUUID == nil then
		return
	end
	
	local objectInfo = loaded.objectsInfo[config.uuid]
	if objectInfo == nil then
		return
	end
	
	if config.Position ~= nil then
		objectInfo.Position = config.Position:Copy()
	end
	
	if config.Rotation ~= nil then
		objectInfo.Rotation = config.Rotation:Copy()
	end
	
	if config.Scale ~= nil then
		if type(config.Scale) == "Number3" then
			objectInfo.Scale = config.Scale:Copy()
		else
			objectInfo.Scale = config.Scale
		end
	end
	
	if config.Physics ~= nil then
		objectInfo.Physics = config.Physics
	end
	
	if config.Name ~= nil then
		objectInfo.Name = config.Name
	end

	if config.CollisionGroups ~= nil then
		objectInfo.CollisionGroups = config.CollisionGroups
	end

	if config.CollidesWithGroups ~= nil then
		objectInfo.CollidesWithGroups = config.CollidesWithGroups
	end
end

-- Remove an object from the loaded world
world.removeObject = function(uuid)
	if loaded.objectsByUUID == nil or uuid == nil then
		return
	end
	if loaded.objectsByUUID[uuid] ~= nil or loaded.objectsInfo[uuid] ~= nil then
		loaded.objectsByUUID[uuid] = nil
		loaded.objectsInfo[uuid] = nil
		loaded.nbObjects -= 1
	end
end

-- Update ambience settings
world.updateAmbience = function(ambience)
	if loaded == nil then
		return
	end
	loaded.ambience = ambience
end

-- Get current ambience settings
world.getAmbience = function()
	return loaded.ambience
end

-- Public API for serialization/deserialization
world.serializeWorld = function(world)
	return serializeWorldBase64(world)
end

world.deserializeWorld = function(str)
	return deserializeWorldBase64(str)
end

-- Default config for loading worlds
local defaultLoadWorldConfig = {
	skipMap = false,
	onLoad = nil,
	onDone = nil,
	fullnameItemKey = "fullname",
	optimisations = {
		minimum_item_size_for_shadows = 10,
	},
	b64 = nil,
	title = nil,
	worldID = nil,
}

-- Load a world from a base64 string
world.load = function(config)
	local ok, err = pcall(function()
		config = require("config"):merge(defaultLoadWorldConfig, config, {
			acceptTypes = {
				b64 = { "string" },
				title = { "string" },
				worldID = { "string" },
				onLoad = { "function" },
				onDone = { "function" },
				addBasePlateIfNeeded = { "boolean" },
			},
		})
	end)
	
	if not ok then
		error("world:loadWorld(config) - config error: " .. err, 2)
	end

	local worldInfo = world.deserializeWorld(config.b64)

	-- Create a base plate if no map or objects exist
	local basePlateAdded = false
	if config.addBasePlateIfNeeded and worldInfo.mapName == nil and (worldInfo.nbObjects == nil or worldInfo.nbObjects == 0) then
		local scale = MAP_SCALE_DEFAULT
		local basePlate = {
			fullname = "aduermael.baseplate",
			uuid = world.uuidv4(),
			Position = Number3(0, 0, 0),
			Rotation = Rotation(0, 0, 0),
			Scale = Number3(scale, scale, scale),
			Physics = PhysicsMode.StaticPerBlock,
			CollisionGroups = COLLISION_GROUP_MAP,
			CollidesWithGroups = COLLISION_GROUP_OBJECT + COLLISION_GROUP_PLAYER
		}
		worldInfo.objectsInfo[basePlate.uuid] = basePlate
		worldInfo.nbObjects = 1
		basePlateAdded = true
	end

	local onDone = function()
		if config.onDone then
			config.onDone({ basePlateAdded = basePlateAdded })
		end
	end

	-- Setup loaded state
	loaded = {
		b64 = config.b64,
		title = config.title,
		worldID = config.worldID,
		ambience = worldInfo.ambience,
		objectsInfo = worldInfo.objectsInfo,
		nbObjects = worldInfo.nbObjects,
		objectsByUUID = {},
		minimum_item_size_for_shadows_sqr = config.optimisations.minimum_item_size_for_shadows^2 or 1,
		map = nil,
		mapName = worldInfo.mapName,
		mapScale = worldInfo.mapScale,
	}

	-- Load objects and ambience after map is loaded (or immediately if skipping map)
	local loadObjectsAndAmbience = function()
		if config.skipMap then
			if type(loaded.mapScale) == "number" then
				Map.Scale = loaded.mapScale
			else
				Map.Scale = MAP_SCALE_DEFAULT
			end
			loaded.map = Map
			loaded.mapScale = Map.Scale
		else
			if config.onLoad then
				config.onLoad(loaded.map, "Map")
			end
		end
		
		local objectsInfo = loaded.objectsInfo
		local ambience = loaded.ambience
		
		if objectsInfo ~= nil then
			-- Load objects through massloading system
			local massLoading = require("massloading")
			local onLoad = function(obj, objectInfo)
				loadObject(obj, objectInfo)
				if config.onLoad then
					config.onLoad(obj, objectInfo)
				end
			end
			
			local massLoadingConfig = {
				onDone = onDone,
				onLoad = onLoad,
				fullnameItemKey = "fullname",
			}
			
			massLoading:load(objectsInfo, massLoadingConfig)
		end
		
		-- Apply ambience if available
		if ambience then
			require("ai_ambience"):loadGeneration(ambience)
		end
		
		-- Call onDone if no objects to load
		if objectsInfo == nil then
			onDone()
		end
	end
	
	-- Load map or proceed directly to objects
	if not config.skipMap and loaded.mapName ~= nil then
		loadMap(loaded.mapName, loaded.mapScale, loadObjectsAndAmbience)
	else
		loadObjectsAndAmbience()
	end
end

world.debug = function()
	if loaded.objectsByUUID == nil then
		return
	end
	for uuid, obj in loaded.objectsByUUID do
		print(uuid, obj, loaded.objectsInfo[uuid])
	end
end

-- Add this near the top with other local declarations
local PHYSICS_MODE_NAMES = {
	[PhysicsMode.StaticPerBlock] = "StaticPerBlock",
	[PhysicsMode.Dynamic] = "Dynamic", 
	[PhysicsMode.Trigger] = "Trigger",
	[PhysicsMode.Disabled] = "Disabled",
	[PhysicsMode.Static] = "Static"
}

world.objectsToJSON = function()
	local toEncode = {}

	if loaded.objectsInfo then
		for uuid, objectInfo in loaded.objectsInfo do
			local entity = {
				itemName = objectInfo.fullname,
			}
			
			if objectInfo.Position and objectInfo.Position ~= Number3(0, 0, 0) then
				entity.Position = { objectInfo.Position.X, objectInfo.Position.Y, objectInfo.Position.Z }
			end
			
			if objectInfo.Rotation and objectInfo.Rotation ~= Rotation(0, 0, 0) then
				entity.Rotation = { objectInfo.Rotation.X, objectInfo.Rotation.Y, objectInfo.Rotation.Z }
			end
			
			if objectInfo.Scale and objectInfo.Scale ~= Number3(1, 1, 1) then
				entity.Scale = { objectInfo.Scale.X, objectInfo.Scale.Y, objectInfo.Scale.Z }
			end
			
			if objectInfo.Name and objectInfo.Name ~= objectInfo.fullname then
				entity.Name = objectInfo.Name
			else
				entity.Name = objectInfo.fullname
			end
			
			if objectInfo.Physics ~= nil then
				entity.Physics = PHYSICS_MODE_NAMES[objectInfo.Physics] or "Static"
			else
				entity.Physics = "Disabled"
			end

			entity.CollisionGroups = {}
			local collisionGroups = objectInfo.CollisionGroups
			if collisionGroups == nil then
				collisionGroups = COLLISION_GROUP_OBJECT
			end
			for _, cg in collisionGroups do
				table.insert(entity.CollisionGroups, cg)
			end

			entity.CollidesWithGroups = {}
			local collidesWithGroups = objectInfo.CollidesWithGroups
			if collidesWithGroups == nil then
				collidesWithGroups = COLLISION_GROUP_MAP + COLLISION_GROUP_PLAYER
			end
			for _, cw in collidesWithGroups do
				table.insert(entity.CollidesWithGroups, cw)
			end

			table.insert(toEncode, entity)
		end
	end

	return JSON:Encode(toEncode)
end

-- Save the current world state
world.save = function()
	if loaded.objectsByUUID == nil or loaded.objectsInfo == nil then
		return
	end
	
	local b64 = serializeWorldBase64(loaded)
	
	if b64 ~= loaded.b64 then
		loaded.b64 = b64
		
		require("system_api", System):patchWorld(loaded.worldID, { mapBase64 = b64 }, function(err, world)
			if err then
				print("Error while saving world: ", JSON:Encode(err))
			elseif world and world.mapBase64 ~= b64 then
				print("Error: mismatch in saved world data")
			end
		end)
	end
end

return world
