-- this module provides UI components and 3D handles to transform 3D objects.

gizmo = {}

ui = require("uikit")
conf = require("config")
ease = require("ease")
bundle = require("bundle")
plane = require("plane"):New(Number3.Zero, Number3.Right, Number3.Up)

local PERSPECTIVE_GIZMO_LAYER = 8
local PERSPECTIVE_GIZMO_DISTANCE = 50
local PERSPECTIVE_GIZMO_ALIGNMENT_THRESHOLD = 0.9

local RADIAL_MENU_DEFAULT_RADIUS = 70

local camera = Camera()
camera:SetParent(Camera)
camera.On = true
camera.Layers = { PERSPECTIVE_GIZMO_LAYER }

camera.Width = Screen.Width
camera.TargetWidth = Screen.Width
camera.Height = Screen.Height
camera.TargetHeight = Screen.Height

target = nil
onChange = nil
onDone = nil
radialMenu = nil -- radial menu node
tickListener = nil

grid = Quad()
grid.IsDoubleSided = false
grid.Height = 10000
grid.Width = 10000
grid.IsUnlit = true
grid.Anchor = { 0.5, 0.5 }
grid.Image = {
	data = Data:FromBundle("images/frame-white-64x64.png"),
	alpha = true,
}
grid.Tiling = Number2(3000, 3000)
-- grid.Tiling = Number2(2000, 2000)

lockGrid = false

local scaleHandles = Object()
local handleDistance = 5
scaleHandles.Scale = 0.7

local scaleHandleX = bundle:Shape("shapes/scale_handle")
scaleHandleX.IsUnlit = true
scaleHandleX.Shadow = false
scaleHandleX.Pivot:Set(scaleHandleX.Size * 0.5)
scaleHandleX.Layers = { PERSPECTIVE_GIZMO_LAYER }

scaleHandleY = scaleHandleX:Copy()
scaleHandleZ = scaleHandleX:Copy()

scaleHandleX.Rotation:Set(0, math.pi * -0.5, 0)
scaleHandleX.LocalPosition.X = handleDistance
scaleHandleX.Palette[1].Color = Color(211, 70, 39)
scaleHandleX.Palette[2].Color = Color(235, 114, 82)

scaleHandleY.Rotation:Set(math.pi * 0.5, 0, 0)
scaleHandleY.LocalPosition.Y = handleDistance
scaleHandleY.Palette[1].Color = Color(116, 212, 38)
scaleHandleY.Palette[2].Color = Color(150, 235, 82)

scaleHandleZ.Rotation:Set(0, 0, 0)
scaleHandleZ.LocalPosition.Z = -handleDistance
scaleHandleZ.Palette[1].Color = Color(39, 120, 211)
scaleHandleZ.Palette[2].Color = Color(82, 153, 235)

scaleHandleX:SetParent(scaleHandles)
scaleHandleY:SetParent(scaleHandles)
scaleHandleZ:SetParent(scaleHandles)

function refresh()
	if target == nil or radialMenu == nil then
		return
	end

	local center = getCenter(target)

	local dotForward = Camera.Forward:Dot(Number3.Forward)
	local absDotForward = math.abs(dotForward)
	local dotRight = Camera.Forward:Dot(Number3.Right)
	local absDotRight = math.abs(dotRight)
	local dotUp = Camera.Forward:Dot(Number3.Up)

	-- axis specific handles
	scaleHandles.Position = center

	local dir = center - Camera.Position
	dir:Normalize()

	scaleHandles.Position:Set(Camera.Position + dir * PERSPECTIVE_GIZMO_DISTANCE)

	if absDotRight >= PERSPECTIVE_GIZMO_ALIGNMENT_THRESHOLD then
		scaleHandleX:RemoveFromParent()
	else
		scaleHandleX:SetParent(scaleHandles)
	end

	-- radial menu
	local screenPos = Camera:WorldToScreen(center)
	if screenPos.X == nil or screenPos.Y == nil then
		radialMenu:hide()
		return
	else
		radialMenu:show()
	end
	radialMenu.pos = { screenPos.X * Screen.Width, screenPos.Y * Screen.Height }

	-- grid
	updateGridRotation()
end

function getCenter(target)
	local box = Box()
	box:Fit(target, { recursive = true })
	return box.Center
end

function showGrid()
	if target == nil then
		return
	end
	grid:SetParent(World)
	local center = getCenter(target)
	grid.Position = center
	plane.origin = center
end

function updateGridRotation()
	if target == nil then
		return
	end
	if lockGrid then
		return
	end

	local dotForward = Camera.Forward:Dot(Number3.Forward)
	local absDotForward = math.abs(dotForward)
	local dotRight = Camera.Forward:Dot(Number3.Right)
	local absDotRight = math.abs(dotRight)
	local dotUp = Camera.Forward:Dot(Number3.Up)
	local absDotUp = math.abs(dotUp)
	local m = math.max(absDotForward, absDotRight, absDotUp)

	if m == absDotForward then
		if dotForward < 0 then
			grid.Rotation = Rotation(0, math.pi, 0)
		else
			grid.Rotation = Rotation(0, 0, 0)
		end
	elseif m == absDotRight then
		if dotRight < 0 then
			grid.Rotation = Rotation(0, math.pi * 1.5, 0)
		else
			grid.Rotation = Rotation(0, math.pi * 0.5, 0)
		end
	else
		grid.Rotation = Rotation(math.pi * 0.5, 0, 0)
	end

	plane.normal = grid.Forward
end

defaultRadialHandleConfig = {
	image = "",
	text = "🙂",
	icon = "",
	angle = 0,
	radius = RADIAL_MENU_DEFAULT_RADIUS,
	onRelease = function() end,
	onPress = function() end,
	onDrag = function() end,
}

function addRadialHandle(root, config)
	config = conf:merge(defaultRadialHandleConfig, config)

	local content

	if config.icon ~= "" then
		content = ui:frame({ image = {
			data = Data:FromBundle(config.icon),
			cutout = true,
		} })
		content.Width = 25
		content.Height = 25
	else
		content = config.text
	end

	local btn = ui:buttonSecondary({ content = content })
	local size = math.max(btn.Width, btn.Height)
	btn.Width = size
	btn.Height = size
	btn:setParent(root)
	btn.pos = -Number2(btn.Width, btn.Height) * 0.5

	local angle = math.rad(config.angle)
	local v = Number2(math.cos(angle), math.sin(angle))
	local target = v * config.radius - Number2(btn.Width, btn.Height) * 0.5

	ease:outBack(btn, 0.3).pos = Number3(target.X, target.Y, 0)

	btn.onPress = config.onPress
	btn.onRelease = config.onRelease
	btn.onCancel = config.onRelease
	btn.onDrag = config.onDrag

	btn.config = config

	btn.onRemove = function(self)
		self.config = nil
	end

	return btn
end

local moveStartPos
local moveTargetStartPos
function startMove(_, _, _, pointerEvent)
	if target == nil then
		return
	end

	lockGrid = false

	local ray = Ray(pointerEvent.Position, pointerEvent.Direction)

	moveStartPos = plane:hit(ray)
	if moveStartPos == nil then
		return
	end

	moveTargetStartPos = target.Position:Copy()
end

function endMove(_)
	moveStartPos = nil
	moveTargetStartPos = nil

	lockGrid = false
	onDone(target)
end

function dragMove(_, pointerEvent)
	if target == nil then
		return
	end
	if moveStartPos == nil then
		return
	end

	local ray = Ray(pointerEvent.Position, pointerEvent.Direction)
	local p = plane:hit(ray)

	if p == nil then
		return
	end

	target.Position:Set(moveTargetStartPos + (p - moveStartPos))
	onChange(target)
end

local rotStartX
local rotTargetStartRot
function startRot(_, _, _, pointerEvent)
	if target == nil then
		return
	end
	rotStartX = pointerEvent.X * Screen.Width
	rotTargetStartRot = target.Rotation:Copy()
end

function endRot(_)
	rotStartX = nil
	rotTargetStartRot = nil
	onDone(target)
end

function dragRot(_, pointerEvent)
	if target == nil then
		return
	end
	if rotStartX == nil then
		return
	end

	local diff = pointerEvent.X * Screen.Width - rotStartX

	target.Rotation:Set(Rotation(0, -diff * 0.04, 0) * rotTargetStartRot)
	onChange(target)
end

local scaleStartY
local scaleTargetStartScale
function startScale(_, _, _, pointerEvent)
	if target == nil then
		return
	end
	scaleStartY = pointerEvent.Y * Screen.Width
	scaleTargetStartScale = target.Scale:Copy()
end

function endScale(_)
	scaleStartY = nil
	scaleTargetStartScale = nil
	onDone(target)
end

function dragScale(_, pointerEvent)
	if target == nil then
		return
	end
	if scaleStartY == nil then
		return
	end

	local diff = pointerEvent.Y * Screen.Width - scaleStartY

	target.Scale:Set(scaleTargetStartScale + Number3.One * diff * 0.01)
	onChange(target)
end

defaultConfig = {
	target = nil,
	radius = RADIAL_MENU_DEFAULT_RADIUS,
	onChange = function(_) end, -- target
	onDone = function(_) end, -- target
}

gizmo.create = function(self, config)
	if self ~= gizmo then
		error("transformgizmo:create(config) should be called with `:`")
	end

	ok, err = pcall(function()
		config = conf:merge(
			defaultConfig,
			config,
			{ acceptTypes = { target = { "Object", "Shape", "MutableShape", "Player" } } }
		)
	end)

	if not ok then
		error("trasnformGizmo:create(config) - config error: " .. err, 2)
	end

	target = config.target
	onChange = config.onChange
	onDone = config.onDone

	if radialMenu == nil then
		radialMenu = ui:createNode()
		radialMenu.parentDidResize = function(_)
			refresh()
		end
		radialMenu:parentDidResize()

		addRadialHandle(radialMenu, {
			icon = "images/icon-move.png",
			angle = -50,
			radius = config.radius,
			onPress = startMove,
			onRelease = endMove,
			onDrag = dragMove,
		})
		addRadialHandle(radialMenu, {
			icon = "images/icon-rotate.png", -- rotate
			angle = -90,
			radius = config.radius,
			onPress = startRot,
			onRelease = endRot,
			onDrag = dragRot,
		})
		addRadialHandle(radialMenu, {
			icon = "images/icon-scale.png", -- scale
			angle = -130,
			radius = config.radius,
			onPress = startScale,
			onRelease = endScale,
			onDrag = dragScale,
		})
	end

	scaleHandles:SetParent(World)

	tickListener = LocalEvent:Listen(LocalEvent.Name.Tick, function(_)
		refresh()
	end)

	showGrid()
	refresh()

	radialMenu.onRemove = function()
		tickListener:Remove()
		tickListener = nil
		target = nil
		grid:SetParent(nil)
		scaleHandles:SetParent(nil)
		radialMenu = nil
	end

	return radialMenu
end

return gizmo
