bundle = require("bundle")
time = require("time")

local CONFIG = {
	PROFILE_CELL_SIZE = 150,
	PROFILE_CELL_AVATAR_WIDTH = 100,
	PROFILE_CELL_AVATAR_HEIGHT = 120,
	WORLD_CELL_SIZE = 150,
	ITEM_CELL_SIZE = 150,
	FRIEND_CELL_SIZE = 100,
	TINY_PADDING = 2,
	CELL_PADDING = 5,
	LOAD_CONTENT_DELAY = 0.3,
	AVATAR_DEFAULT_YAW = math.rad(-170),
	AVATAR_DEFAULT_PITCH = 0,
	TINY_FONT_SCALE = 0.8,
}

local function avatarBox()
	return Box({ -9.5, -13.5, -9.5 }, { 9.5, 13.5, 9.5 })
end

local function headBox()
	return Box({ -6.5, -5.5, -6.5 }, { 6.5, 5.5, 6.5 })
end

local function feetBox()
	return Box({ -4.5, -2, -2.5 }, { 4.5, 2, 2.5 })
end

homeAvatarY = 0

-- main menu HTTP requests to be canceled when changing scene (opening item or world)
httpRequests = {}
local function cancelHTTPRequests()
	for _, req in ipairs(httpRequests) do
		req:Cancel()
	end
	httpRequests = {}
end

LocalEvent:Listen(LocalEvent.Name.WorldRequested, function()
	cancelHTTPRequests()
end)

Client.OnStart = function()
	Screen.Orientation = "portrait" -- force portrait

	Clouds.On = false

	api = require("api")
	ease = require("ease")
	particles = require("particles")

	drawerHeight = 0

	avatarCameraFocus = "body" -- body / head
	avatarCameraTarget = nil

	backgroundCamera = Camera()
	backgroundCamera.Projection = ProjectionMode.Orthographic
	backgroundCamera.On = true
	backgroundCamera.Layers = { 6 }
	World:AddChild(backgroundCamera)

	backgroundCamera.ViewOrder = 1
	Camera.ViewOrder = 2

	avatarCameraFollowHomeScroll = false
	avatarCameraX = 0

	function getAvatarCameraTargetPosition(h, w, hWithoutMargin)
		if avatarCameraTarget == nil then
			return nil
		end

		local savedRot = avatarCameraTarget.LocalRotation:Copy()
		avatarCameraTarget.LocalRotation:Set(Number3.Zero)

		local _w = Camera.TargetWidth
		local _h = Camera.TargetHeight

		Camera.TargetHeight = h
		Camera.TargetWidth = w
		Camera.Height = h
		Camera.Width = w

		local box = Box()
		local pos = Camera.Position:Copy()
		local vCover = 1.0
		local hCover = nil

		if avatarCameraFollowHomeScroll == true then
			box = avatarBox()
			avatar():centerBody()
			vCover = 0.92
		elseif avatarCameraFocus == "body" then
			box = avatarBox()
			avatar():centerBodyWithExtraRoomAbove()
			vCover = 0.9
			hCover = 1.2
		elseif avatarCameraFocus == "body_demo" then
			box = avatarBox()
			avatar():centerBodyWithExtraRoomAbove()
			vCover = 0.7
			hCover = 1.0
		elseif avatarCameraFocus == "bodyAndItem" then
			box = avatarBox()
			avatar():centerBodyWithExtraRoomAbove()
			vCover = 0.9
			hCover = 0.8
		elseif avatarCameraFocus == "head" then
			box = headBox()
			avatar():centerHead()
			vCover = 0.8
			hCover = 0.8
		elseif avatarCameraFocus == "eyes" then
			box = headBox()
			avatar():centerHead()
			vCover = 0.8
			hCover = 0.8
		elseif avatarCameraFocus == "nose" then
			box = headBox()
			avatar():centerHead()
			vCover = 0.8
			hCover = 0.8
		elseif avatarCameraFocus == "feet" then
			box = feetBox()
			avatar():centerFeet()
			vCover = 0.8
			hCover = 0.7
		end

		vCover = (hWithoutMargin * vCover) / h
		Camera:FitToScreen(box, { coverage = vCover, orientation = "vertical" })
		if hCover ~= nil then
			local d1 = Camera.Position.Z
			Camera:FitToScreen(box, { coverage = hCover, orientation = "horizontal" })
			local d2 = Camera.Position.Z
			if d1 < d2 then -- restore d1 if distance more important than d2
				Camera.Position.Z = d1
			end
		end

		local targetPos = Camera.Position:Copy()

		-- restore
		Camera.TargetHeight = _h
		Camera.TargetWidth = _w
		Camera.Height = _h
		Camera.Width = _w
		Camera.Position:Set(pos)

		avatarCameraTarget.LocalRotation:Set(savedRot)

		return targetPos
	end

	local avatarCameraState = {}
	function layoutCamera(config)
		local h, hWithoutMargin
		local w

		if avatarCameraFollowHomeScroll == true then
			hWithoutMargin = CONFIG.PROFILE_CELL_SIZE
			h = hWithoutMargin + CONFIG.CELL_PADDING * 2 + Screen.SafeArea.Top * 2
			w = avatarCameraX * 2
		else
			hWithoutMargin = Screen.Height - drawerHeight - Screen.SafeArea.Top
			h = hWithoutMargin + Screen.SafeArea.Top * 2
			w = Screen.Width
		end

		if
			avatarCameraState.h == h
			and avatarCameraState.screenWidth == Screen.Width
			and avatarCameraState.focus == avatarCameraFocus
			and avatarCameraState.target == avatarCameraTarget
			and avatarCameraState.avatarCameraFollowHomeScroll == avatarCameraFollowHomeScroll
			and (avatarCameraFollowHomeScroll == false or (avatarCameraState.avatarCameraX == avatarCameraX))
		then
			-- nothing changed, early return
			return
		end

		ease:cancel(Camera)

		local p = getAvatarCameraTargetPosition(h, w, hWithoutMargin)
		if p == nil then
			return
		end

		avatarCameraState.h = h
		avatarCameraState.screenWidth = Screen.Width
		avatarCameraState.focus = avatarCameraFocus
		avatarCameraState.target = avatarCameraTarget
		avatarCameraState.avatarCameraFollowHomeScroll = avatarCameraFollowHomeScroll
		avatarCameraState.avatarCameraX = avatarCameraX

		local targetX = Screen.Width - w
		local targetY = 0

		Camera.TargetX = targetX
		Camera.TargetY = targetY

		if config.noAnimation then
			Camera.TargetHeight = h
			Camera.TargetWidth = w
			Camera.Height = h
			Camera.Width = w
			Camera.Position:Set(p)
			return
		end

		local anim = ease:inOutSine(Camera, 0.2, {
			onDone = function()
				avatarCameraState.animation = nil
			end,
		})

		anim.TargetHeight = h
		anim.TargetWidth = w
		anim.Height = h
		anim.Width = w
		anim.Position = p
	end

	Camera:SetModeFree()
	Camera:SetParent(World)

	Sky.LightColor = Color(100, 100, 100)

	LocalEvent:Listen("signup_push_notifications", function()
		avatar():showPhone()
		avatarCameraFocus = "bodyAndItem"
		layoutCamera()
	end)

	LocalEvent:Listen("signup_flow_dob", function()
		avatar():removeItem()
		titleScreen():hide()
		avatar():show({ mode = "user" })
		avatarCameraFocus = "body"
		layoutCamera()
	end)

	LocalEvent:Listen("signup_flow_start_or_login", function()
		avatar():removeItem()
		titleScreen():show()
		avatar():show({ mode = "demo" })
		avatarCameraFocus = "body_demo"
		layoutCamera()
	end)

	LocalEvent:Listen("signup_drawer_height_update", function(height)
		drawerHeight = height
		layoutCamera()
	end)

	LocalEvent:Listen("signup_flow_login_success", function(_)
		avatar():removeItem()
		drawerHeight = 0
		titleScreen():hide()
		home():show()
	end)

	light = Light()
	light.Color = Color(150, 150, 200)
	light.Intensity = 1.0
	light.CastsShadows = true
	light.On = true
	light.Type = LightType.Directional
	World:AddChild(light)
	light.Rotation:Set(math.rad(5), math.rad(20), 0)

	Light.Ambient.SkyLightFactor = 0.2
	Light.Ambient.DirectionalLightFactor = 0.5

	local gameGrid = Data:FromBundle("images/games-background.png")

	backgroundQuad = Quad()
	backgroundQuad.IsUnlit = true
	backgroundQuad.IsDoubleSided = false
	--backgroundQuad.Color = { gradient = "V", from = Color(208, 97, 255), to = Color(63, 95, 232) }
	-- backgroundQuad.Color = { gradient = "V", from = Color(5, 5, 5), to = Color(50,68,77) }
	-- backgroundQuad.Color = { gradient = "V", from = Color(5, 5, 5), to = Color(44,90,81) }
	backgroundQuad.Color = { gradient = "V", from = Color(5, 5, 5), to = Color(44,74,90) }

	backgroundQuad.Width = Screen.RenderWidth
	backgroundQuad.Height = Screen.RenderHeight
	backgroundQuad.Anchor = { 0.5, 0.5 }
	backgroundQuad.Layers = { 6 }
	World:AddChild(backgroundQuad)
	backgroundQuad.Position.Z = 2

	backgroundLogo = Quad()
	backgroundLogo.IsUnlit = true
	backgroundLogo.IsDoubleSided = false
	backgroundLogo.Color = { Color(255, 255, 255, 0.5), alpha = true }
	backgroundLogo.Image = gameGrid
	backgroundLogo.Width = math.max(Screen.RenderWidth, Screen.RenderHeight) * 2
	backgroundLogo.Height = backgroundLogo.Width * (4.0 / 3.0)
	backgroundLogo.Tiling = backgroundLogo.Width / Number2(1000, 1000 * (1176 / 882)) -- 882 / 1176
	backgroundLogo.Anchor = { 0.5, 0.5 }
	backgroundLogo.Layers = { 6 }
	World:AddChild(backgroundLogo)
	backgroundLogo.Position.Z = 1
	backgroundLogo.Rotation.Z = math.rad(-30)

	local delta = Number2(0, 1)
	speed = 0.05
	local _x = 0
	local _y = 0
	LocalEvent:Listen(LocalEvent.Name.Tick, function(dt)
		-- _x += delta.X * dt * speed
		-- _y += delta.Y * dt * speed
		-- backgroundLogo.Offset = { _x, _y }

		-- both lines below should work but for some reason it doesn't
		backgroundLogo.Offset += delta * dt * speed
		-- backgroundLogo.Offset = backgroundLogo.Offset + delta * dt * speed

		-- backgroundLogo.Offset = backgroundLogo.Offset
		-- print(backgroundLogo.Offset)
	end)

	if Client.LoggedIn then
		home():show()
	else
		titleScreen():show()
	end
	layoutCamera({ noAnimation = true })
end

Screen.DidResize = function()
	if backgroundQuad then
		backgroundQuad.Width = Screen.RenderWidth
		backgroundQuad.Height = Screen.RenderHeight
		backgroundLogo.Width = math.max(Screen.RenderWidth, Screen.RenderHeight) * 2
		backgroundLogo.Height = backgroundLogo.Width * (4.0 / 3.0)
		-- backgroundLogo.Tiling = backgroundLogo.Width / Number2(1000, 1000)
		backgroundLogo.Tiling = backgroundLogo.Width / Number2(1000, 1000)
	end
end

local _titleScreen
function titleScreen()
	if _titleScreen then
		return _titleScreen
	end

	_titleScreen = {}

	local root
	local didResizeFunction
	local didResizeListener
	local tickListener

	_titleScreen.show = function()
		if root ~= nil then
			return
		end
		root = Object()
		root:SetParent(World)

		drawerHeight = 0
		layoutCamera({ noAnimation = true })

		local logo = Object()
		logo:SetParent(root)

		didResizeFunction = function()
			layoutCamera({ noAnimation = true })
			-- local box = Box()
			-- box:Fit(logo, { recursive = true })
			-- Camera:FitToScreen(box, 0.8)
		end

		didResizeListener = LocalEvent:Listen(LocalEvent.Name.ScreenDidResize, didResizeFunction)
		didResizeFunction()
	end

	_titleScreen.hide = function()
		if root == nil then
			return
		end
		if tickListener then
			tickListener:Remove()
			tickListener = nil
		end
		if didResizeListener then
			didResizeListener:Remove()
			didResizeListener = nil
		end
		didResizeFunction = nil

		root:Destroy()
		root = nil
	end

	return _titleScreen
end

function shuffle(array)
	local n = #array
	for i = n, 2, -1 do
		local j = math.random(i)
		array[i], array[j] = array[j], array[i]
	end
end

local _avatar
function avatar()
	if _avatar then
		return _avatar
	end

	_avatar = {}

	local avatarModule = require("avatar")

	local hairs = {
		bundle:Shape("shapes/signup_demo/air_goggles"),
		bundle:Shape("shapes/signup_demo/hair_pink_blue"),
		bundle:Shape("shapes/signup_demo/lofi_girl_head"),
		bundle:Shape("shapes/signup_demo/pink_pop_hair"),
		bundle:Shape("shapes/signup_demo/pirate_captain_hat"),
		bundle:Shape("shapes/signup_demo/santa_hair"),
		bundle:Shape("shapes/signup_demo/elf_hair"),
		bundle:Shape("shapes/signup_demo/sennin_head"),
		bundle:Shape("shapes/signup_demo/geek_long_hair"),
		bundle:Shape("shapes/signup_demo/elvis"),
		bundle:Shape("shapes/signup_demo/wolf_cut"),
		bundle:Shape("shapes/signup_demo/luffy_hair"),
		bundle:Shape("shapes/signup_demo/crown"),
		bundle:Shape("shapes/signup_demo/raccoon_head"),
		bundle:Shape("shapes/signup_demo/just_hair"),
		bundle:Shape("shapes/signup_demo/grass_cubzh"),
	}
	local hairsCurrentIndex = 0
	local hairsRandomIndexes = {}
	for i = 1, #hairs do
		table.insert(hairsRandomIndexes, i)
	end
	shuffle(hairsRandomIndexes)

	local jackets = {
		bundle:Shape("shapes/signup_demo/astronaut_top"),
		bundle:Shape("shapes/signup_demo/cute_top"),
		bundle:Shape("shapes/signup_demo/lab_coat"),
		bundle:Shape("shapes/signup_demo/princess_dresstop"),
		bundle:Shape("shapes/signup_demo/red_robot_suit"),
		bundle:Shape("shapes/signup_demo/sweater"),
		bundle:Shape("shapes/signup_demo/jedi_tunic"),
	}

	local jacketsCurrentIndex = 0
	local jacketsRandomIndexes = {}
	for i = 1, #jackets do
		table.insert(jacketsRandomIndexes, i)
	end
	shuffle(jacketsRandomIndexes)

	local pants = {
		bundle:Shape("shapes/signup_demo/overalls_pants"),
		bundle:Shape("shapes/signup_demo/jorts"),
		bundle:Shape("shapes/signup_demo/red_crewmate_pants"),
		bundle:Shape("shapes/signup_demo/stripe_pants2"),
	}

	local pantsCurrentIndex = 0
	local pantsRandomIndexes = {}
	for i = 1, #pants do
		table.insert(pantsRandomIndexes, i)
	end
	shuffle(pantsRandomIndexes)

	local boots = {
		bundle:Shape("shapes/signup_demo/astronaut_shoes"),
		bundle:Shape("shapes/signup_demo/flaming_boots"),
		bundle:Shape("shapes/signup_demo/kids_shoes"),
		bundle:Shape("shapes/signup_demo/pirate_boots_01"),
	}

	local bootsCurrentIndex = 0
	local bootsRandomIndexes = {}
	for i = 1, #boots do
		table.insert(bootsRandomIndexes, i)
	end
	shuffle(bootsRandomIndexes)

	local defaultHair = bundle:Shape("shapes/default_hair")
	local defaultJacket = bundle:Shape("shapes/default_jacket")
	local defaultPants = bundle:Shape("shapes/default_pants")
	local defaultShoes = bundle:Shape("shapes/default_shoes")

	local yaw = CONFIG.AVATAR_DEFAULT_YAW
	local pitch = CONFIG.AVATAR_DEFAULT_PITCH

	local root
	local phone
	local phoneTickListener
	local dragListener
	local listeners = {}

	local function drag(dx, dy)
		yaw = yaw - dx * 0.01
		pitch = math.min(math.rad(45), math.max(math.rad(-45), pitch + dy * 0.01))
		if root then
			root.LocalRotation:Set(Rotation(pitch, 0, 0) * Rotation(0, yaw, 0))
		end
		if phone then
			phone.LocalRotation:Set(Rotation(0, -yaw + math.rad(35), 0) * Rotation(math.rad(30), 0, 0))
			if root.avatar then
				root.avatar.LocalRotation:Set(Rotation(0, -yaw + math.rad(180), 0))
			end
		end
	end

	_avatar.drag = function(_, pe)
		drag(pe.DX, pe.DY)
	end

	_avatar.resetRotation = function()
		local avatar = root.avatar
		if avatar then
			avatar.LocalRotation:Set(0, 0, 0)
		end
		yaw = CONFIG.AVATAR_DEFAULT_YAW
		pitch = CONFIG.AVATAR_DEFAULT_PITCH
		drag(0, 0)
	end

	_avatar.setInternalDragListener = function(_, b)
		if b then
			if dragListener then
				return
			end
			dragListener = LocalEvent:Listen(LocalEvent.Name.PointerDrag, function(pe)
				if phone then
					return
				end
				drag(pe.DX, pe.DY)
			end)
			table.insert(listeners, dragListener)
		else
			if dragListener == nil then
				return
			end
			dragListener:Remove()
			dragListener = nil
		end
	end

	local mode = "demo" -- demo / user

	local emitter
	local particlesColor = Color(0, 0, 0)

	_avatar.setPosition = function(_, p)
		if root == nil then
			return
		end
		root.Position:Set(p)
	end

	_avatar.removeItem = function()
		local avatar = root.avatar
		if avatar == nil then
			return
		end
		if phoneTickListener ~= nil then
			phoneTickListener:Remove()
			phoneTickListener = nil
		end
		if phone ~= nil then
			phone:RemoveFromParent()
			phone = nil
		end
		avatar.LocalPosition.Z = 0
		_avatar:resetRotation()
	end

	_avatar.showPhone = function()
		local avatar = root.avatar
		if avatar == nil then
			return
		end
		if phone == nil then
			phone = Object()
			phone.shape = bundle:Shape("shapes/smartphone")
			phone.shape.Pivot = phone.shape.Size * 0.5
			phone.shape:SetParent(phone)
			phone.shape.LocalPosition = Number3.Zero
			phone.Scale = 0.8
			phone:SetParent(root)
		end

		local b = avatarBox()
		avatar.LocalPosition.Y = -b.Size.Y * 0.5
		avatar.LocalPosition.Z = -10

		phone.LocalPosition.Z = 10
		phone.LocalPosition.Y = -5

		if phoneTickListener == nil then
			local triggerMin = 0.3
			local triggerMax = 0.8
			local life = 1.0
			local trigger = triggerMin + math.random() * (triggerMax - triggerMin)
			local emojis = {}
			local recycled = {}
			local toRemove = {}
			local foundParticlesToRemove = false
			local generated = 0
			local progress
			phoneTickListener = LocalEvent:Listen(LocalEvent.Name.Tick, function(dt)
				for e, _ in pairs(emojis) do
					e.life = e.life - dt
					progress = math.max(0, life - e.life) / life
					e.Scale = e.config.scale * math.sin(progress * math.pi)
					if e.life <= 0 then
						e:RemoveFromParent()
						table.insert(toRemove, e)
						foundParticlesToRemove = true
					end
				end

				if foundParticlesToRemove then
					for _, e in ipairs(toRemove) do
						emojis[e] = nil
						table.insert(recycled, e)
					end
					foundParticlesToRemove = false
					toRemove = {}
				end

				trigger = trigger - dt
				if trigger <= 0 then
					Client:HapticFeedback()
					ease:cancel(phone.shape)
					phone.shape.Scale = 0.8
					ease:outBack(phone.shape, 0.2).Scale = Number3.One

					trigger = triggerMin + math.random() * (triggerMax - triggerMin)
					local shapes = {
						{ name = "shapes/heart", scale = 1.2, initRot = Rotation(0, 0, 0) },
						{ name = "shapes/emojim", scale = 0.75, initRot = Rotation(0, math.rad(90), 0) },
						{ name = "shapes/textbubble", scale = 1.0, initRot = Rotation(0, 0, 0) },
						{ name = "shapes/pezh_coin_2", scale = 1.0, initRot = Rotation(0, 0, 0) },
					}
					local p
					if generated >= 20 then
						p = table.remove(recycled, math.random(1, #recycled))
					end
					if p == nil then
						local index = math.random(1, 4)
						local config = shapes[index]
						p = bundle:Shape(config.name)
						p.config = config
						p.Scale = 0
						p.Pivot = p.Size * 0.5
						p.CollisionGroups = {}
						p.CollidesWithGroups = {}
						p.Physics = PhysicsMode.Dynamic

						generated = generated + 1
					end
					p.life = life
					emojis[p] = true
					p:SetParent(phone)
					p.Rotation:Set(p.config.initRot)
					p.LocalPosition:Set(0, -2, -2)
					local v = Number3(20, 0, 0)
					v:Rotate(0, math.random() * math.pi, 0)
					p.Velocity:Set(v + { 0, math.random(60, 70), 0 })
					p.Acceleration = -Config.ConstantAcceleration - p.Velocity * 2
				end
			end)
		end

		_avatar:resetRotation()
		yaw = math.rad(90)
		drag(0, 0)
		avatar.LocalRotation:Set(0, math.rad(30), 0)
	end

	_avatar.centerHead = function()
		local avatar = root.avatar
		if avatar == nil then
			return
		end
		local b = avatarBox()
		local headB = headBox()
		avatar.LocalPosition.Y = -b.Size.Y * 0.5
			- avatar.Head.LocalPosition.Y
			+ avatar.Head.Pivot.Y
			- headB.Size.Y * 0.5
	end

	_avatar.centerBody = function()
		local avatar = root.avatar
		if avatar == nil then
			return
		end
		local b = avatarBox()
		avatar.LocalPosition.Y = -b.Size.Y * 0.5
	end

	_avatar.centerBodyWithExtraRoomAbove = function()
		local avatar = root.avatar
		if avatar == nil then
			return
		end
		local b = avatarBox()
		avatar.LocalPosition.Y = -b.Size.Y * 0.5 - 2
	end

	_avatar.centerFeet = function()
		local avatar = root.avatar
		if avatar == nil then
			return
		end
		avatar.LocalPosition.Y = -avatar.RightFoot.Height * 0.5 - 0.5 -- shoes have half a cube vertical offset
	end

	_avatar.show = function(self, config)
		if root ~= nil then
			if mode == config.mode then
				return
			end
			self:hide()
		end

		if emitter == nil then
			emitter = particles:newEmitter({
				acceleration = -Config.ConstantAcceleration,
				velocity = function()
					local v = Number3(0, 0, math.random(40, 50))
					v:Rotate(math.random() * math.pi * 2, math.random() * math.pi * 2, 0)
					return v
				end,
				life = 3.0,
				scale = function()
					return 0.7 + math.random() * 1.0
				end,
				color = function()
					return particlesColor
				end,
			})
		end

		mode = config.mode

		root = Object()

		local eyeBlinks = true
		if mode == "demo" then
			eyeBlinks = false
		end

		local avatar = avatarModule:get({
			usernameOrId = Player.UserID,
			-- size = math.min(Screen.Height * 0.5, Screen.Width * 0.75),
			-- ui = ui,
			eyeBlinks = eyeBlinks,
		})

		avatar:SetParent(root)
		root.avatar = avatar

		avatar.Animations.Walk:Stop()
		avatar.Animations.Idle:Play()

		_avatar:centerBody()

		if mode == "demo" then
			avatar:loadEquipment({ type = "hair", shape = hairs[1] })
			avatar:loadEquipment({ type = "jacket", shape = jackets[1] })
			avatar:loadEquipment({ type = "pants", shape = pants[1] })
			avatar:loadEquipment({ type = "boots", shape = boots[1] })
		else
			avatar:loadEquipment({ type = "hair", shape = defaultHair, preventAvatarLoadOverride = false })
			avatar:loadEquipment({ type = "jacket", shape = defaultJacket, preventAvatarLoadOverride = false })
			avatar:loadEquipment({ type = "pants", shape = defaultPants, preventAvatarLoadOverride = false })
			avatar:loadEquipment({ type = "boots", shape = defaultShoes, preventAvatarLoadOverride = false })
		end

		_avatar:setInternalDragListener(true)
		drag(0, 0)

		l = LocalEvent:Listen(LocalEvent.Name.ScreenDidResize, function()
			layoutCamera()
		end)

		table.insert(listeners, l)

		l = LocalEvent:Listen("avatar_editor_should_focus_on_head", function()
			avatarCameraFocus = "head"
			layoutCamera()
		end)
		table.insert(listeners, l)

		l = LocalEvent:Listen("avatar_editor_should_focus_on_eyes", function()
			avatarCameraFocus = "eyes"
			layoutCamera()
		end)
		table.insert(listeners, l)

		l = LocalEvent:Listen("avatar_editor_should_focus_on_nose", function()
			avatarCameraFocus = "nose"
			layoutCamera()
		end)
		table.insert(listeners, l)

		l = LocalEvent:Listen("avatar_editor_should_focus_on_feet", function()
			avatarCameraFocus = "feet"
			layoutCamera()
		end)
		table.insert(listeners, l)

		l = LocalEvent:Listen("avatar_editor_should_focus_on_body", function()
			avatarCameraFocus = "body"
			layoutCamera()
		end)
		table.insert(listeners, l)

		local didAttachEquipmentParts = function(equipmentParts)
			for _, part in ipairs(equipmentParts) do
				ease:cancel(part)
				local scale = part.Scale:Copy()
				part.Scale = part.Scale * 0.8
				ease:outBack(part, 0.2).Scale = scale
			end
		end

		l = LocalEvent:Listen("avatar_editor_update", function(config)
			if config.skinColorIndex then
				local colors = avatarModule.skinColors[config.skinColorIndex]
				local avatar = root.avatar
				avatar:setColors({
					skin1 = colors.skin1,
					skin2 = colors.skin2,
					nose = colors.nose,
					mouth = colors.mouth,
				})

				ease:cancel(root)
				root.Scale = 0.8
				ease:outBack(root, 0.2).Scale = Number3(1.0, 1.0, 1.0)

				particlesColor = colors.skin1
				emitter.Position = root.Position
				emitter:spawn(10)
			end
			if config.eyesIndex then
				avatar:setEyes({
					index = config.eyesIndex,
				})
			end
			if config.eyesColorIndex then
				avatar:setEyes({
					color = avatarModule.eyeColors[config.eyesColorIndex],
				})
			end
			if config.noseIndex then
				avatar:setNose({ index = config.noseIndex })
			end
			if config.jacket then
				avatar:loadEquipment({
					type = "jacket",
					item = config.jacket,
					didAttachEquipmentParts = didAttachEquipmentParts,
				})
			end
			if config.hair then
				avatar:loadEquipment({
					type = "hair",
					item = config.hair,
					didAttachEquipmentParts = didAttachEquipmentParts,
				})
			end
			if config.pants then
				avatar:loadEquipment({
					type = "pants",
					item = config.pants,
					didAttachEquipmentParts = didAttachEquipmentParts,
				})
			end
			if config.boots then
				avatar:loadEquipment({
					type = "boots",
					item = config.boots,
					didAttachEquipmentParts = didAttachEquipmentParts,
				})
			end
		end)
		table.insert(listeners, l)

		local i = 8
		local r
		local eyesIndex = 1
		local eyesCounter = 1
		local eyesTrigger = 3
		if mode == "demo" then
			changeTimer = Timer(0.3, true, function()
				r = math.random(1, #avatarModule.skinColors)
				if r == i then
					r = i + 1
					if r > #avatarModule.skinColors then
						r = 1
					end
				end
				i = r
				local colors = avatarModule.skinColors[i]
				local avatar = root.avatar
				avatar:setColors({
					skin1 = colors.skin1,
					skin2 = colors.skin2,
					nose = colors.nose,
					mouth = colors.mouth,
				})
				eyesCounter = eyesCounter + 1
				if eyesCounter >= eyesTrigger then
					eyesCounter = 0
					eyesIndex = eyesIndex + 1
					if eyesIndex > #avatarModule.eyes then
						eyesIndex = 1
					end
					avatar:setEyes({
						index = eyesIndex,
						color = avatarModule.eyeColors[math.random(1, #avatarModule.eyeColors)],
					})
					avatar:setNose({
						index = math.random(1, #avatarModule.noses),
					})
				end

				hairsCurrentIndex = hairsCurrentIndex + 1
				if hairsCurrentIndex > #hairsRandomIndexes then
					shuffle(hairsRandomIndexes)
					hairsCurrentIndex = 1
				end

				avatar:loadEquipment({
					type = "hair",
					shape = hairs[hairsRandomIndexes[hairsCurrentIndex]],
					didAttachEquipmentParts = didAttachEquipmentParts,
				})

				jacketsCurrentIndex = jacketsCurrentIndex + 1
				if jacketsCurrentIndex > #jacketsRandomIndexes then
					shuffle(jacketsRandomIndexes)
					jacketsCurrentIndex = 1
				end

				avatar:loadEquipment({
					type = "jacket",
					shape = jackets[jacketsRandomIndexes[jacketsCurrentIndex]],
					didAttachEquipmentParts = didAttachEquipmentParts,
				})

				pantsCurrentIndex = pantsCurrentIndex + 1
				if pantsCurrentIndex > #pantsRandomIndexes then
					shuffle(pantsRandomIndexes)
					pantsCurrentIndex = 1
				end

				avatar:loadEquipment({
					type = "pants",
					shape = pants[pantsRandomIndexes[pantsCurrentIndex]],
					didAttachEquipmentParts = didAttachEquipmentParts,
				})

				bootsCurrentIndex = bootsCurrentIndex + 1
				if bootsCurrentIndex > #bootsRandomIndexes then
					shuffle(bootsRandomIndexes)
					bootsCurrentIndex = 1
				end

				avatar:loadEquipment({
					type = "boots",
					shape = boots[bootsRandomIndexes[bootsCurrentIndex]],
					didAttachEquipmentParts = didAttachEquipmentParts,
				})
			end)
		end

		avatarCameraTarget = nil

		root:SetParent(World)
		root.IsHidden = true

		Timer(0.03, function()
			root.IsHidden = false
			avatarCameraTarget = root
			layoutCamera({ noAnimation = true })
		end)

		return root
	end

	_avatar.hide = function()
		if root == nil then
			return
		end

		local avatar = root.avatar
		avatar:loadEquipment({ type = "jacket", item = "" })
		avatar:loadEquipment({ type = "hair", item = "" })
		avatar:loadEquipment({ type = "pants", item = "" })
		avatar:loadEquipment({ type = "boots", item = "" })

		if changeTimer then
			changeTimer:Cancel()
			changeTimer = nil
		end

		for _, l in ipairs(listeners) do
			l:Remove()
		end
		listeners = {}
		dragListener = nil

		root:Destroy()
		root = nil

		emitter:Destroy()
		emitter = nil
	end

	return _avatar
end

local _home
function home()
	if _home then
		return _home
	end

	_home = {}

	local theme = require("uitheme").current
	local ui = require("uikit")
	local uiAvatar = require("ui_avatar")

	local root
	local tickListener

	local notificationsReq
	local notificationCountListeners
	local friendNotificationsReq
	local friendNotificationCountListeners

	_home.pause = function()
		avatarCameraFollowHomeScroll = false
		avatar():setInternalDragListener(true)
		avatar():setPosition(Number3.Zero)
		avatar():resetRotation()
		layoutCamera()

		if tickListener then
			tickListener:Pause()
		end
	end

	_home.resume = function()
		avatarCameraFollowHomeScroll = true
		avatar():setInternalDragListener(false)
		avatar():setPosition(Number3(0, homeAvatarY, 0))
		avatar():resetRotation()
		layoutCamera()

		if tickListener then
			tickListener:Resume()
		end
	end

	_home.show = function()
		if root ~= nil then
			return
		end

		avatar():show({ mode = "user" })
		avatarCameraFollowHomeScroll = true
		layoutCamera()

		root = ui:frame() -- { color = Color(255, 0, 0, 0.3) }
		root.parentDidResize = function(self)
			self.Width = Screen.Width
			self.Height = Screen.Height
		end
		root:parentDidResize()

		local profileCell -- cell to showcase avatar

		local padding = theme.padding

		local recycledWorldCells = {}
		local recycledLoadingAnimations = {}
		local worldThumbnails = {} -- cache for loaded world thumbnails

		local recycledItemCells = {}
		local itemShapes = {} -- cache for loaded items
		local activeItemShapes = {}

		local recycledFriendCells = {}
		local friendAvatarCache = {}

		local cellSelector = ui:frameScrollCellSelector()
		cellSelector:setParent(nil)

		local t = 0.0
		tickListener = LocalEvent:Listen(LocalEvent.Name.Tick, function(dt)
			t = t + dt
			for itemShape, _ in pairs(activeItemShapes) do
				itemShape.pivot.LocalRotation:Set(-0.1, t, -0.2)
			end
		end)

		local function cellResizeFn(self)
			self.Width = self.parent.Width
			self.title.pos = { padding * 2, self.Height - self.title.Height - padding }

			if self.scroll then
				self.scroll.pos = { padding, padding }
				self.scroll.Height = self.Height - self.title.Height - padding * 3
				self.scroll.Width = self.Width - padding * 2
			end

			if self.button then
				self.button.pos.Y = self.title.pos.Y + self.title.Height * 0.5 - self.button.Height * 0.5
				self.button.pos.X = self.Width - self.button.Width - padding * 2
			end
		end

		local function worldCellResizeFn(self)
			if self.parent.Height == nil then
				return
			end

			self.Height = self.parent.Height

			if self.shape then
				self.shape.pos = { 0, 0 }
				self.shape.Height = self.Height
				self.shape.Width = self.Width
				self.shape.pivot.LocalRotation:Set(-0.1, 0, -0.2)
			end

			if self.loadingAnimation then
				self.loadingAnimation.pos = {
					self.Width * 0.5 - self.loadingAnimation.Width * 0.5,
					self.Height * 0.5 - self.loadingAnimation.Height * 0.5,
				}
			end

			if self.itemShape then
				self.itemShape.pos = { 0, 0 }
				self.itemShape.Height = self.Height
				self.itemShape.Width = self.Width
				self.itemShape.pivot.LocalRotation:Set(-0.1, 0, -0.2)
			end

			if self.avatar then
				self.avatar.pos = { padding, padding }
				self.avatar.Height = self.Height - padding * 2
				self.avatar.Width = self.Width - padding * 2
			end

			if self.thumbnail then
				self.thumbnail.pos = { padding, padding }
				self.thumbnail.Width = self.Width - padding * 2
				self.thumbnail.Height = self.Height - padding * 2
			end

			if self.likesFrame then
				self.likesFrame.pos = {
					padding + theme.paddingTiny,
					self.Height - self.likesFrame.Height - padding - theme.paddingTiny,
				}
				self.titleFrame.LocalPosition.Z = -500 -- ui.kForegroundDepth
			end
		end

		local function itemCellResizeFn(self)
			self.Height = self.parent.Height

			if self.shape then
				self.shape.pos = { 0, 0 }
				self.shape.Height = self.Height
				self.shape.Width = self.Width
				self.shape.pivot.LocalRotation:Set(-0.1, 0, -0.2)
			end

			if self.loadingAnimation then
				self.loadingAnimation.pos = {
					self.Width * 0.5 - self.loadingAnimation.Width * 0.5,
					self.Height * 0.5 - self.loadingAnimation.Height * 0.5,
				}
			end

			if self.itemShape then
				self.itemShape.pos = { 0, 0 }
				self.itemShape.Height = self.Height
				self.itemShape.Width = self.Width
				self.itemShape.pivot.LocalRotation:Set(-0.1, 0, -0.2)
			end

			if self.likesFrame then
				self.likesFrame.pos = {
					padding,
					self.Height - self.likesFrame.Height - padding,
				}
				self.titleFrame.LocalPosition.Z = -500 -- ui.kForegroundDepth
			end
		end

		local function requestWorlds(dataFetcher, config)
			if dataFetcher.req then
				dataFetcher.req:Cancel()
			end

			dataFetcher.req = api:getWorlds({
				category = config.category,
				sortBy = config.sortBy,
				fields = { "title", "created", "updated", "views", "likes" },
			}, function(worlds, err)
				if err ~= nil then
					return
				end

				dataFetcher.entities = worlds
				dataFetcher.nbEntities = #worlds

				if dataFetcher.scroll then
					dataFetcher.scroll:refresh()
				end

				if dataFetcher.displayNumberOfEntries and dataFetcher.row and dataFetcher.title then
					if dataFetcher.nbEntities > 0 then
						dataFetcher.row.title.Text = dataFetcher.title .. " (" .. dataFetcher.nbEntities .. ")"
					else
						dataFetcher.row.title.Text = dataFetcher.title
					end
				end
			end)
		end

		local function recycleCellLoadingAnimation(cell)
			if cell.loadingAnimation ~= nil then
				cell.loadingAnimation:setParent(nil)
				table.insert(recycledLoadingAnimations, cell.loadingAnimation)
				cell.loadingAnimation = nil
			end
		end

		local function recycleWorldCell(cell)
			recycleCellLoadingAnimation(cell)
			if cell.thumbnail ~= nil then
				cell.thumbnail:setParent(nil)
				cell.thumbnail = nil
			end
			if cell.loadThumbnailTimer then
				cell.loadThumbnailTimer:Cancel()
				cell.loadThumbnailTimer = nil
			end
			if cell.req then
				cell.req:Cancel()
				cell.req = nil
			end
			cell:setParent(nil)
			table.insert(recycledWorldCells, cell)
		end

		local function getOrCreateWorldCell(world, category)
			local cell = table.remove(recycledWorldCells)

			if cell == nil then
				cell = ui:frameScrollCell()
				cell.Width = CONFIG.WORLD_CELL_SIZE

				local titleFrame = ui:frameTextBackground()
				titleFrame:setParent(cell)
				titleFrame.pos = { padding + theme.paddingTiny, padding + theme.paddingTiny }

				local title = ui:createText("…", {
					color = Color.White,
					size = "small",
					bold = true,
				})
				title:setParent(titleFrame)
				title.pos = { theme.paddingTiny, theme.paddingTiny }

				cell.titleFrame = titleFrame
				cell.title = title

				-- LIKES
				local likesFrame = ui:frameTextBackground()
				likesFrame:setParent(cell)
				likesFrame.LocalPosition.Z = -500 -- ui.kForegroundDepth

				local likes = ui:createText("…", Color.White, "small")
				likes.object.Scale = CONFIG.TINY_FONT_SCALE
				likes:setParent(likesFrame)
				likes.pos = { theme.paddingTiny, theme.paddingTiny }

				cell.likesFrame = likesFrame
				cell.likes = likes

				cell.parentDidResize = worldCellResizeFn

				cell.onPress = function(self)
					cellSelector:setParent(self)
					cellSelector.Width = self.Width
					cellSelector.Height = self.Height
					Client:HapticFeedback()
				end

				cell.onRelease = function(self)
					Menu:ShowWorld({ world = self.world })
				end

				cell.onCancel = function(_)
					cellSelector:setParent(nil)
				end
			end

			cell.category = category or ""

			if world then
				local thumbnail = worldThumbnails[cell.category .. "_" .. world.id]
				if thumbnail ~= nil then
					thumbnail:setParent(cell)
					cell.thumbnail = thumbnail
				else
					local loadingAnimation = table.remove(recycledLoadingAnimations)
					if loadingAnimation == nil then
						loadingAnimation = require("ui_loading_animation"):create()
					end

					loadingAnimation:setParent(cell)
					cell.loadingAnimation = loadingAnimation

					cell.loadThumbnailTimer = Timer(CONFIG.LOAD_CONTENT_DELAY, function()
						cell.req = api:getWorldThumbnail({ 
							worldID = world.id,
							width = 250,
							callback = function(img, err)
								recycleCellLoadingAnimation(cell)
								if err ~= nil then
									return
								end

								local thumbnail = ui:frame({ image = img })
								thumbnail:setParent(cell)
								cell.thumbnail = thumbnail
								worldThumbnails[cell.category .. "_" .. world.id] = thumbnail
								worldCellResizeFn(cell)
							end
						})
						table.insert(httpRequests, cell.req)
					end)
				end

				cell.world = world
				cell.title.Text = world.title

				local txt = ""
				if world.likes and world.likes > 0 then
					txt = txt .. "❤️ " .. world.likes
				end
				if world.views and world.views > 0 then
					if txt ~= "" then
						txt = txt .. " "
					end
					txt = txt .. "👁️ " .. world.views
				end
				if txt ~= "" then
					cell.likes.Text = txt
					cell.likesFrame:show()
				else
					cell.likesFrame:hide()
				end
			else
				cell.title.Text = "…"
				cell.likes.Text = "…"
			end

			cell.title.object.MaxWidth = cell.Width - (padding + theme.paddingTiny * 2) * 2
			cell.titleFrame.Width = cell.title.Width + theme.paddingTiny * 2
			cell.titleFrame.Height = cell.title.Height + theme.paddingTiny * 2

			cell.likes.object.MaxWidth = (cell.Width - (padding + theme.paddingTiny * 2) * 2)
				* (1.0 / CONFIG.TINY_FONT_SCALE)
			cell.likesFrame.Width = cell.likes.Width + theme.paddingTiny * 2
			cell.likesFrame.Height = cell.likes.Height + theme.paddingTiny * 2
			cell.likesFrame.pos = {
				padding + theme.paddingTiny,
				cell.Height - cell.likesFrame.Height - padding - theme.paddingTiny,
			}
			cell.titleFrame.LocalPosition.Z = -500 -- ui.kForegroundDepth

			return cell
		end

		-- ITEMS

		local function prettifyItemName(str)
			local s = string.gsub(str, "_%a", string.upper)
			s = string.gsub(s, "_", " ")
			s = string.gsub(s, "^%l", string.upper)
			return s
		end

		local function requestItems(dataFetcher, config)
			if dataFetcher.req then
				dataFetcher.req:Cancel()
			end

			dataFetcher.req = api:getItems({
				category = config.category,
				sortBy = config.sortBy,
				fields = { "repo", "name", "created", "updated", "likes" },
			}, function(items, err)
				if err ~= nil then
					return
				end

				dataFetcher.entities = items
				dataFetcher.nbEntities = #items

				if dataFetcher.scroll then
					dataFetcher.scroll:refresh()
				end

				if dataFetcher.displayNumberOfEntries and dataFetcher.row and dataFetcher.title then
					if dataFetcher.nbEntities > 0 then
						dataFetcher.row.title.Text = dataFetcher.title .. " (" .. dataFetcher.nbEntities .. ")"
					else
						dataFetcher.row.title.Text = dataFetcher.title
					end
				end
			end)
		end

		local function recycleItemCell(cell)
			recycleCellLoadingAnimation(cell)
			if cell.loadShapeTimer then
				cell.loadShapeTimer:Cancel()
				cell.loadShapeTimer = nil
			end
			if cell.req then
				cell.req:Cancel()
				cell.req = nil
			end
			if cell.itemShape then
				activeItemShapes[cell.itemShape] = nil
				cell.itemShape:setParent(nil)
				cell.itemShape = nil
			end
			cell:setParent(nil)
			table.insert(recycledItemCells, cell)
		end

		local function getOrCreateItemCell(item, category)
			local cell = table.remove(recycledItemCells)

			if cell == nil then
				cell = ui:frameScrollCell()
				cell.Width = CONFIG.ITEM_CELL_SIZE

				local titleFrame = ui:frameTextBackground()
				titleFrame:setParent(cell)
				titleFrame.pos = { padding, padding }
				titleFrame.LocalPosition.Z = -500 -- ui.kForegroundDepth

				local title = ui:createText("…", Color.White, "small")
				title:setParent(titleFrame)
				title.pos = { theme.paddingTiny, theme.paddingTiny }

				cell.titleFrame = titleFrame
				cell.title = title

				-- LIKES
				local likesFrame = ui:frameTextBackground()
				likesFrame:setParent(cell)
				likesFrame.LocalPosition.Z = -500 -- ui.kForegroundDepth

				local likes = ui:createText("…", Color.White, "small")
				likes.object.Scale = CONFIG.TINY_FONT_SCALE
				likes:setParent(likesFrame)
				likes.pos = { theme.paddingTiny, theme.paddingTiny }

				cell.likesFrame = likesFrame
				cell.likes = likes

				cell.parentDidResize = itemCellResizeFn

				cell.onPress = function(self)
					cellSelector:setParent(self)
					cellSelector.Width = self.Width
					cellSelector.Height = self.Height
					Client:HapticFeedback()
				end

				cell.onRelease = function(self)
					Menu:ShowItem({ item = self.item })
				end

				cell.onCancel = function(_)
					cellSelector:setParent(nil)
				end
			end

			cell.category = category or ""
			cell.item = item

			if cell.item then
				local item = cell.item
				local itemShape = itemShapes[cell.category .. "_" .. item.repo .. "." .. item.name]
				if itemShape ~= nil then
					-- print("USE CACHED itemShape:", cell.category .. "_" .. item.repo .. "." .. item.name, itemShape)
					itemShape:setParent(cell)
					activeItemShapes[itemShape] = true
					cell.itemShape = itemShape
				else
					local loadingAnimation = table.remove(recycledLoadingAnimations)
					if loadingAnimation == nil then
						loadingAnimation = require("ui_loading_animation"):create()
					end

					loadingAnimation:setParent(cell)
					cell.loadingAnimation = loadingAnimation

					cell.loadShapeTimer = Timer(CONFIG.LOAD_CONTENT_DELAY, function()
						cell.req = Object:Load(item.repo .. "." .. item.name, function(obj)
							recycleCellLoadingAnimation(cell)
							if obj == nil then
								return
							end

							local itemShape = ui:createShape(obj, { spherized = true })
							cell.itemShape = itemShape
							itemShape:setParent(cell)
							activeItemShapes[itemShape] = true
							itemShape.pivot.LocalRotation:Set(-0.1, 0, -0.2)
							itemShapes[cell.category .. "_" .. item.repo .. "." .. item.name] = itemShape
							cell:parentDidResize()
						end)
						table.insert(httpRequests, cell.req)
					end)
				end
				cell.title.Text = prettifyItemName(item.name)

				local txt = ""
				if item.likes and item.likes > 0 then
					txt = txt .. "❤️ " .. item.likes
				end
				if txt ~= "" then
					cell.likes.Text = txt
					cell.likesFrame:show()
				else
					cell.likesFrame:hide()
				end
			else
				cell.title.Text = "…"
				cell.likes.Text = "…"
			end

			cell.title.object.MaxWidth = cell.Width - (padding + theme.paddingTiny) * 2
			cell.titleFrame.Width = cell.title.Width + theme.paddingTiny * 2
			cell.titleFrame.Height = cell.title.Height + theme.paddingTiny * 2

			cell.likes.object.MaxWidth = (cell.Width - (padding + theme.paddingTiny * 2) * 2)
				* (1.0 / CONFIG.TINY_FONT_SCALE)
			cell.likesFrame.Width = cell.likes.Width + theme.paddingTiny * 2
			cell.likesFrame.Height = cell.likes.Height + theme.paddingTiny * 2
			cell.likesFrame.pos = {
				padding,
				cell.Height - cell.likesFrame.Height - padding,
			}
			cell.titleFrame.LocalPosition.Z = -500 -- ui.kForegroundDepth

			return cell
		end

		local function requestFriends(dataFetcher)
			if dataFetcher.req then
				dataFetcher.req:Cancel()
			end

			dataFetcher.req = api:getFriends({ fields = { "id", "username", "lastSeen" } }, function(friends, err)
				if err ~= nil then
					return
				end

				local function sortByLastSeen(a, b)
					if a.lastSeen ~= nil and b.lastSeen ~= nil then
						return a.lastSeen > b.lastSeen
					end
					return a.id > b.id
				end

				table.sort(friends, sortByLastSeen)

				dataFetcher.entities = friends
				dataFetcher.nbEntities = #friends

				if dataFetcher.scroll then
					dataFetcher.scroll:flush()
					dataFetcher.scroll:refresh()
				end

				if dataFetcher.row and dataFetcher.title then
					if dataFetcher.nbEntities > 0 then
						dataFetcher.row.title.Text = dataFetcher.title .. " (" .. dataFetcher.nbEntities .. ")"
					else
						dataFetcher.row.title.Text = dataFetcher.title
					end
				end
			end)
		end

		local function getOrCreateFriendCell()
			local cell = table.remove(recycledFriendCells)

			if cell == nil then
				cell = ui:frameScrollCell()
				cell.Width = CONFIG.FRIEND_CELL_SIZE
				cell.parentDidResize = worldCellResizeFn

				cell.onPress = function(self)
					cellSelector:setParent(self)
					cellSelector.Width = self.Width
					cellSelector.Height = self.Height
					Client:HapticFeedback()
				end

				cell.onRelease = function(self)
					Menu:ShowProfile({
						id = self.userID,
						username = self.username,
					})
				end

				cell.onCancel = function(_)
					cellSelector:setParent(nil)
				end
			end
			return cell
		end

		local function recycleFriendCell(cell)
			if cell.avatar then
				cell.avatar:setParent(nil)
				cell.avatar = nil
			end
			cell:setParent(nil)
			table.insert(recycledFriendCells, cell)
		end

		local addFriendsCell

		local categoryUnusedCells = {}
		local categoryCells = {}
		local categories = {
			{
				title = "👥 Friends",
				displayNumberOfEntries = true,
				cellSize = CONFIG.FRIEND_CELL_SIZE,
				loadCell = function(index, dataFetcher)
					if index <= dataFetcher.nbEntities then
						local friend = dataFetcher.entities[index]
						local friendCell = getOrCreateFriendCell()

						local avatar = friendAvatarCache[index]
						if avatar == nil then
							avatar = uiAvatar:getHeadAndShoulders({
								usernameOrId = friend.id,
							})
							friendAvatarCache[index] = avatar

							local usernameFrame = ui:frameTextBackground()
							usernameFrame:setParent(avatar)
							usernameFrame.LocalPosition.Z = ui.kForegroundDepth

							local username = ui:createText("", {
								color = Color.White,
								size = "small",
							})
							username:setParent(usernameFrame)
							username.pos = { theme.paddingTiny, theme.paddingTiny }

							avatar.username = username
							avatar.usernameFrame = usernameFrame

							-- LAST SEEN
							local lastSeenFrame = ui:frameTextBackground()
							lastSeenFrame:setParent(avatar)
							lastSeenFrame.LocalPosition.Z = ui.kForegroundDepth

							local lastSeen = ui:createText("", {
								color = Color.White,
								size = "small",
								italic = true,
							})

							lastSeen.object.Scale = CONFIG.TINY_FONT_SCALE
							lastSeen:setParent(lastSeenFrame)
							lastSeen.pos = { theme.paddingTiny, theme.paddingTiny }

							avatar.lastSeenFrame = lastSeenFrame
							avatar.lastSeen = lastSeen
						end

						avatar:setParent(friendCell)

						friendCell.userID = friend.id
						friendCell.username = friend.username

						avatar.username.object.Scale = 1
						avatar.username.Text = friend.username
						-- username text scale to fit in the cell
						local scale = math.min(
							1,
							(CONFIG.FRIEND_CELL_SIZE - padding * 2 - theme.paddingTiny * 2) / avatar.username.Width
						)
						avatar.username.object.Scale = scale

						avatar.usernameFrame.Width = avatar.username.Width + theme.paddingTiny * 2
						avatar.usernameFrame.Height = avatar.username.Height + theme.paddingTiny * 2

						local osTime = time.iso8601_to_os_time(friend.lastSeen)
						local t, units = time.ago(osTime, {
							years = false,
							months = false,
							seconds_label = "s",
							minutes_label = "m",
							hours_label = "h",
							days_label = "d",
						})
						avatar.lastSeen.Text = "👁️ " .. t .. units .. " ago"
						avatar.lastSeenFrame.Width = avatar.lastSeen.Width + theme.paddingTiny * 2
						avatar.lastSeenFrame.Height = avatar.lastSeen.Height + theme.paddingTiny * 2
						avatar.lastSeenFrame.pos.Y = CONFIG.FRIEND_CELL_SIZE
							- avatar.lastSeenFrame.Height
							- padding
							- theme.paddingTiny

						friendCell.avatar = avatar

						return friendCell
					elseif index == dataFetcher.nbEntities + 1 then
						if addFriendsCell == nil then
							addFriendsCell = ui:frameScrollCell()
							addFriendsCell.Width = CONFIG.FRIEND_CELL_SIZE * 3
							addFriendsCell.parentDidResize = worldCellResizeFn

							local image = ui:frame({
								image = {
									data = Data:FromBundle("images/friends.png"),
									alpha = true,
								},
							})
							image.Width = CONFIG.FRIEND_CELL_SIZE * 3 - padding * 2
							image.Height = image.Width * (1.0 / 3.0)
							image:setParent(addFriendsCell)

							local btn = ui:buttonPositive({ content = "👥 Add Friends", padding = theme.padding })
							btn:setParent(addFriendsCell)

							btn.parentDidResize = function(self)
								local parent = self.parent
								self.pos = {
									parent.Width * 0.5 - self.Width * 0.5,
									theme.padding,
								}
								image.pos = {
									parent.Width * 0.5 - image.Width * 0.5,
									parent.Height * 0.5 - image.Height * 0.5,
								}
							end

							btn.onRelease = function()
								Menu:ShowFriends()
							end
						end
						return addFriendsCell
					end
				end,
				unloadCell = function(_, cell)
					if cell == addFriendsCell then
						cell:setParent(nil)
					else
						recycleFriendCell(cell)
					end
				end,
				extraSetup = function(dataFetcher)
					requestFriends(dataFetcher)
				end,
			},
			{
				title = "✨ Featured Worlds",
				cellSize = CONFIG.WORLD_CELL_SIZE,
				loadCell = function(index, dataFetcher)
					if index <= dataFetcher.nbEntities then
						local world = dataFetcher.entities[index]
						return getOrCreateWorldCell(world, "featured")
					end
				end,
				unloadCell = function(_, cell)
					recycleWorldCell(cell)
				end,
				extraSetup = function(dataFetcher)
					requestWorlds(dataFetcher, { category = "featured" })
				end,
			},
			{
				title = "😛 Fun with friends",
				cellSize = CONFIG.WORLD_CELL_SIZE,
				loadCell = function(index, dataFetcher)
					if index <= dataFetcher.nbEntities then
						local world = dataFetcher.entities[index]
						return getOrCreateWorldCell(world, "fun_with_friends")
					end
				end,
				unloadCell = function(_, cell)
					recycleWorldCell(cell)
				end,
				extraSetup = function(dataFetcher)
					requestWorlds(dataFetcher, { category = "fun_with_friends" })
				end,
			},
			{
				title = "🤠 Playing solo",
				cellSize = CONFIG.WORLD_CELL_SIZE,
				loadCell = function(index, dataFetcher)
					if index <= dataFetcher.nbEntities then
						local world = dataFetcher.entities[index]
						return getOrCreateWorldCell(world, "solo")
					end
				end,
				unloadCell = function(_, cell)
					recycleWorldCell(cell)
				end,
				extraSetup = function(dataFetcher)
					requestWorlds(dataFetcher, { category = "solo" })
				end,
			},
			{
				title = "🍏 New Items",
				buttonLabel = "all items",
				buttonAction = function()
					Menu:ShowItems()
				end,
				cellSize = CONFIG.ITEM_CELL_SIZE,
				loadCell = function(index, dataFetcher)
					if index <= dataFetcher.nbEntities then
						local item = dataFetcher.entities[index]
						return getOrCreateItemCell(item, "popular_items")
					end
				end,
				unloadCell = function(_, cell)
					recycleItemCell(cell)
				end,
				extraSetup = function(dataFetcher)
					requestItems(dataFetcher, { sortBy = "updatedAt:desc" })
				end,
			},
			{
				title = "❤️ Top Rated",
				cellSize = CONFIG.WORLD_CELL_SIZE,
				loadCell = function(index, dataFetcher)
					if index <= dataFetcher.nbEntities then
						local world = dataFetcher.entities[index]
						return getOrCreateWorldCell(world, "top_rated")
					end
				end,
				unloadCell = function(_, cell)
					recycleWorldCell(cell)
				end,
				extraSetup = function(dataFetcher)
					requestWorlds(dataFetcher, { sortBy = "likes:desc" })
				end,
			},
			{
				title = "⚔️ Popular Items",
				buttonLabel = "all items",
				buttonAction = function()
					Menu:ShowItems()
				end,
				cellSize = CONFIG.ITEM_CELL_SIZE,
				loadCell = function(index, dataFetcher)
					if index <= dataFetcher.nbEntities then
						local item = dataFetcher.entities[index]
						return getOrCreateItemCell(item, "popular_items")
					end
				end,
				unloadCell = function(_, cell)
					recycleItemCell(cell)
				end,
				extraSetup = function(dataFetcher)
					requestItems(dataFetcher, { sortBy = "likes:desc" })
				end,
			},
		}
		local nbCategories = #categories

		local function createCategoryCell(category)
			cell = ui:frameGenericContainer()
			cell.parentDidResize = cellResizeFn

			local title = ui:createText("Title", {
				color = Color.White,
				size = "default",
				outline = 0.2,
			})
			title:setParent(cell)

			cell.Height = title.Height + (category.cellSize or 100) + padding * 3 + CONFIG.CELL_PADDING * 2
			cell.title = title

			cell.button = ui:buttonLink({ content = "", textSize = "small" })
			cell.button:setParent(cell)

			return cell
		end

		local scroll

		local function editAvatarFn()
			if bottomBar then
				bottomBar:hide()
			end
			scroll:hide()
			avatar():show({ mode = "user" })
			avatarCameraFocus = "body" -- skin tab displayed first
			home():pause()

			drawer = require("drawer"):create({ ui = ui })

			local okBtn = ui:buttonPositive({
				content = "Done!",
				textSize = "big",
				unfocuses = false,
				padding = 5,
			})
			okBtn:setParent(drawer)
			okBtn.onRelease = function()
				home():resume()
				drawer:remove()
				if bottomBar then
					bottomBar:show()
				end
				scroll:show()
				drawer = nil
			end

			avatarEditor = require("ui_avatar_editor"):create({
				ui = ui,
				requestHeightCallback = function(height)
					drawer:updateConfig({
						layoutContent = function(self)
							local drawerHeight = height + padding * 2 + Screen.SafeArea.Bottom
							drawerHeight = math.floor(math.min(Screen.Height * 0.6, drawerHeight))

							self.Height = drawerHeight

							okBtn.pos = {
								self.Width - okBtn.Width - padding,
								self.Height + padding,
							}

							LocalEvent:Send("signup_drawer_height_update", drawerHeight)

							if avatarEditor then
								avatarEditor.Width = self.Width - padding * 2
								avatarEditor.Height = drawerHeight - Screen.SafeArea.Bottom - padding * 2
								avatarEditor.pos = { padding, Screen.SafeArea.Bottom + padding }
							end
						end,
					})
					drawer:bump()
				end,
			})

			avatarEditor:setParent(drawer)
			drawer:show()
		end

		scroll = ui:scroll({
			-- backgroundColor = Color(0, 255, 0, 0.3),
			-- gradientColor = Color(37, 23, 59), -- Color(155, 97, 250),
			padding = {
				top = Screen.SafeArea.Top + CONFIG.CELL_PADDING,
				bottom = CONFIG.CELL_PADDING,
				left = CONFIG.CELL_PADDING,
				right = CONFIG.CELL_PADDING,
			},
			cellPadding = CONFIG.CELL_PADDING,
			loadCell = function(index)
				if index == 1 then
					if profileCell == nil then
						-- profileCell = ui:frame({ color = Color(0, 0, 0, 0.2) })
						profileCell = ui:frame()
						profileCell.Height = CONFIG.PROFILE_CELL_SIZE

						local avatarTransparentFrame = ui:frame()
						avatarTransparentFrame:setParent(profileCell)

						avatarTransparentFrame.onDrag = function(_, pe)
							avatar():drag(pe)
						end

						local usernameFrame = ui:frame()
						-- local usernameFrame = ui:frameTextBackground()
						usernameFrame:setParent(profileCell)

						local username = ui:createText(Player.Username, {
							color = Color.White,
							size = "default",
							outline = 0.2,
						})
						username:setParent(usernameFrame)
						username.pos = { theme.paddingTiny, theme.paddingTiny }

						local editUsernameBtn
						if Player.Username == "newbie" then
							editUsernameBtn = ui:buttonNeutral({ content = "✏️" })
							editUsernameBtn:setParent(profileCell)

							editUsernameBtn.onRelease = function()
								Menu:sendHomeDebugEvent("User presses EDIT USERNAME button")
								Menu:ShowUsernameForm()
							end

							local l
							l = LocalEvent:Listen("username_set", function()
								username.Text = Player.Username
								editUsernameBtn:remove()
								editUsernameBtn = nil
								profileCell:parentDidResize() -- layout
								l:Remove()
								l = nil
							end)
						end

						local editAvatarBtn = ui:buttonNeutral({ content = "✏️ Edit avatar" })
						editAvatarBtn:setParent(profileCell)

						editAvatarBtn.onRelease = function(_)
							Menu:sendHomeDebugEvent("User presses EDIT AVATAR button")
							editAvatarFn()
						end

						local visitHouseBtn = ui:buttonNeutral({
							content = "🏠 Visit house",
							-- displayAsDisabled = true,
						})
						local comingSoonAlert
						visitHouseBtn.onRelease = function(_)
							Menu:sendHomeDebugEvent("User presses VISIT HOUSE button")
							if comingSoonAlert ~= nil then
								return
							end
							comingSoonAlert = require("alert"):create(
								"House customization is coming soon! Stay tuned to personalize your house and invite friends. 👥"
							)

							comingSoonAlert:setPositiveCallback("OK", function()
								comingSoonAlert:remove()
								comingSoonAlert = nil
							end)
						end
						visitHouseBtn:setParent(profileCell)

						profileCell.parentDidResize = function(self)
							self.Width = self.parent.Width

							usernameFrame.Width = username.Width + theme.paddingTiny * 2
							usernameFrame.Height = username.Height + theme.paddingTiny * 2

							local usernameWidth = usernameFrame.Width
							local usernameHeight = usernameFrame.Height
							if editUsernameBtn then
								local size = math.max(editUsernameBtn.Width, editUsernameBtn.Height)
								editUsernameBtn.Width = size
								editUsernameBtn.Height = size
								usernameHeight = math.max(usernameHeight, editUsernameBtn.Height)
							end

							local infoWidth = math.max(usernameWidth, editAvatarBtn.Width, visitHouseBtn.Width)

							local infoHeight =
								math.max(usernameHeight + editAvatarBtn.Height + visitHouseBtn.Height + padding * 2)

							local avatarWidth = CONFIG.PROFILE_CELL_AVATAR_WIDTH

							avatarTransparentFrame.Width = avatarWidth + padding * 2 -- occupy a bit more space for easier drag inputs
							avatarTransparentFrame.Height = self.Height

							local y = self.Height * 0.5 + infoHeight * 0.5 - usernameHeight

							avatarTransparentFrame.pos.X = Screen.Width - avatarTransparentFrame.Width - padding
							local x = avatarTransparentFrame.pos.X - infoWidth

							local previousAvatarCameraX = avatarCameraX
							avatarCameraX = padding + avatarWidth * 0.5

							usernameFrame.pos = { x + infoWidth - usernameFrame.Width, y + usernameHeight * 0.5 - usernameFrame.Height * 0.5 }

							if editUsernameBtn then
								editUsernameBtn.pos = {
									usernameFrame.pos.X - editUsernameBtn.Width - padding,
									y + usernameHeight * 0.5 - editUsernameBtn.Height * 0.5,
								}
							end

							y = y - padding - editAvatarBtn.Height
							editAvatarBtn.pos = { x, y }
							y = y - padding - visitHouseBtn.Height
							visitHouseBtn.pos = { x, y }

							if previousAvatarCameraX ~= avatarCameraX then
								layoutCamera()
							end
						end
					end
					return profileCell
				elseif index <= nbCategories + 1 then
					local categoryIndex = index - 1
					local category = categories[categoryIndex]

					local cell = categoryCells[categoryIndex]
					if cell == nil then
						cell = table.remove(categoryUnusedCells)
						if cell == nil then
							-- no cell in recycle pool, create it
							cell = createCategoryCell(category)
						end
						cell.categoryIndex = categoryIndex
						categoryCells[categoryIndex] = cell

						cell.title.Text = category.title

						if category.buttonAction then
							cell.button:show()
							cell.button.Text = category.buttonLabel or "..."
							cell.button.onRelease = category.buttonAction
						else
							cell.button:hide()
							cell.button.onRelease = nil
						end

						if category.loadCell ~= nil then
							if cell.scroll then
								cell.scroll:remove()
							end

							local dataFetcher = {
								entities = {},
								nbEntities = 0,
								row = cell,
								title = category.title,
								displayNumberOfEntries = category.displayNumberOfEntries,
							}

							local scroll = ui:scroll({
								-- backgroundColor = Color(255, 255, 255),
								-- backgroundColor = Color(43, 45, 49),
								backgroundColor = theme.buttonTextColor,
								padding = CONFIG.CELL_PADDING,
								cellPadding = CONFIG.CELL_PADDING,
								direction = "right",
								loadCell = category.loadCell,
								unloadCell = category.unloadCell,
								userdata = dataFetcher,
								centerContent = true,
							})

							dataFetcher.scroll = scroll

							scroll:setParent(cell)
							cell.scroll = scroll

							scroll.onRemove = function()
								if dataFetcher.req then
									dataFetcher.req:Cancel()
									dataFetcher.req = nil
								end
								dataFetcher.row = nil
								dataFetcher.scroll = nil
							end

							if category.extraSetup then
								category.extraSetup(dataFetcher)
							end
						end
					end
					return cell
				end
			end,
			unloadCell = function(_, _)
				-- TODO: recycle
			end,
			scrollPositionDidChange = function(p)
				p = math.max(-Screen.SafeArea.Top, p)
				homeAvatarY = p * 0.2
				avatar():setPosition(Number3(0, homeAvatarY, 0))
			end,
		})
		scroll:setParent(root)

		bottomBar = ui:frame()

		local function createBottomBarButton(text, icon)
			local btn = ui:frame({ color = Color(0, 0, 0) })
			btn.onPress = function()
				Client:HapticFeedback()
			end

			local content = ui:frame()

			icon = ui:frame({ image = {
				data = Data:FromBundle(icon or "images/logo.png"),
				cutout = true,
			} })
			icon.Width = 20
			icon.Height = 20
			icon:setParent(content)
			btn.icon = icon

			local title = ui:createText(text, { size = "small", color = Color.White })
			title:setParent(content)

			content.Width = 50
			content.Height = title.Height + icon.Height + padding * 2.2

			content.parentDidResize = function(self)
				self.Width = self.parent.Width
				self.pos = { 0, self.parent.Height - self.Height }

				local y = self.Height - padding - icon.Height
				icon.pos = { self.Width * 0.5 - icon.Width * 0.5, y }
				y = y - padding * 0.2 - title.Height
				title.pos = { self.Width * 0.5 - title.Width * 0.5, y }
			end

			content:setParent(btn)
			btn.content = content

			btn:setParent(bottomBar)
			return btn
		end

		-- local btnHome = createBottomBarButton("Home", "images/logo.png")
		local btnExplore = createBottomBarButton("Explore", "images/icon-explore.png")
		local btnProfile = createBottomBarButton("Profile", "images/icon-profile.png")
		local btnFriends = createBottomBarButton("Friends", "images/icon-friends.png")
		local btnCreate = createBottomBarButton("Create", "images/icon-create.png")

		btnExplore.onRelease = function()
			Menu:sendHomeDebugEvent("User presses EXPLORE button")
			Menu:ShowWorlds()
		end

		btnProfile.onRelease = function()
			Menu:sendHomeDebugEvent("User presses PROFILE button")
			Menu:ShowProfile({ player = Player, editAvatar = editAvatarFn })
		end

		btnFriends.onRelease = function()
			Menu:sendHomeDebugEvent("User presses FRIENDS button")
			Menu:ShowFriends()
		end

		local badge = require("notifications"):createBadge({ count = 0 })
		badge:setParent(btnFriends.icon)

		local function refreshFriendsBadge()
			if friendNotificationsReq ~= nil then
				friendNotificationsReq:Cancel()
			end
			friendNotificationsReq = require("user"):getUnreadNotificationCount({
				category = "social",
				callback = function(count, err)
					friendNotificationsReq = nil
					if err ~= nil then
						return
					end
					badge:setCount(count)
				end,
			})
		end

		if friendNotificationCountListeners == nil then
			friendNotificationCountListeners = {}
			local l = LocalEvent:Listen(LocalEvent.Name.NotificationCountDidChange, refreshFriendsBadge)
			table.insert(friendNotificationCountListeners, l)
			l = LocalEvent:Listen(LocalEvent.Name.AppDidBecomeActive, refreshFriendsBadge)
			table.insert(friendNotificationCountListeners, l)
		end

		refreshFriendsBadge()

		btnCreate.onRelease = function()
			Menu:sendHomeDebugEvent("User presses CREATE button")
			Menu:ShowCreations()
			-- URL:Open("https://app.cu.bzh?worldID=a113f59f-5e18-4726-81f7-bf31dd64cd80")
		end

		bottomBar.parentDidResize = function(self)
			self.Width = self.parent.Width
			local btnWidth = self.Width / 4.0

			local h = btnExplore.content.Height + Screen.SafeArea.Bottom

			self.Height = h
			btnExplore.Height = h
			btnProfile.Height = h
			btnFriends.Height = h
			btnCreate.Height = h

			btnExplore.Width = btnWidth
			btnProfile.Width = btnWidth
			btnFriends.Width = btnWidth
			btnCreate.Width = btnWidth

			btnExplore.pos = { 0, 0 }
			btnCreate.pos = btnExplore.pos + { btnWidth, 0 }
			btnProfile.pos = btnCreate.pos + { btnWidth, 0 }
			btnFriends.pos = btnProfile.pos + { btnWidth, 0 }

			scroll.pos = { 0, self.Height }
			scroll.Width = Screen.Width
			scroll.Height = Screen.Height - self.Height --  - Screen.SafeArea.Top
		end
		bottomBar:setParent(root)

		home():resume()
	end

	_home.hide = function()
		if root == nil then
			return
		end

		if tickListener then
			tickListener:Remove()
			tickListener = nil
		end

		if notificationsReq ~= nil then
			notificationsReq:Cancel()
			notificationsReq = nil
		end
		if notificationCountListeners ~= nil then
			for _, l in ipairs(notificationCountListeners) do
				l:Remove()
			end
			notificationCountListeners = nil
		end

		if friendNotificationsReq ~= nil then
			friendNotificationsReq:Cancel()
			friendNotificationsReq = nil
		end
		if friendNotificationCountListeners ~= nil then
			for _, l in ipairs(friendNotificationCountListeners) do
				l:Remove()
			end
			friendNotificationCountListeners = nil
		end

		root:remove()
		root = nil

		avatar():hide()
	end

	return _home
end

Client.DirectionalPad = nil
