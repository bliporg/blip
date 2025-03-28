--- Spawn interactable shapes with a callback and detection areas for an in-world message and button display.

---@code iShape = require("iShape")
---exampleConfig = {
--- position = Number3(10, 10, 10),
--- rotation = Number3(0, math.pi, 0),
--- scale = 0.5,
--- callback = function() print("Do something!") end,
--- bubbleText = "This does something when you click or collide",
--- buttonText = "Click me",
--- buttonCallback = function() print("Do something else ?") end,
--- callbackTriggerDistance = 1 * MAP_SCALE
--- bubbleTriggerDistance = 10 * MAP_SCALE
--- buttonTriggerDistance = 10 * MAP_SCALE
---}
---iShape:create(shape, exampleConfig)

---@type iShape

local iShape = {}
local index = {}

local mt = {
	__index = index,
	__newindex = function(t, k, v)
		error("Modules cannot be modified", 2)
	end,
	__metatable = false,
}
setmetatable(iShape, mt)

local _COLLISION_GROUPS = { 6 }
local _TEXT_OFFSET = { 0, 1, 0 }
local _BUTTON_OFFSET = { 0, 3, 0 }
local _TIMER = 3
local _DEFAULT_TRIGGER_DISTANCE = 10

local _createBaseShape = function(pShape, pConfig)
	local s = Shape(pShape)
	s:SetParent(World)
	s.Physics = PhysicsMode.StaticPerBlock
	s.Pivot = { s.Width * 0.5, 0, s.Depth * 0.5 }
	s.Scale = pConfig.scale or 1
	s.LocalPosition = pConfig.position or { 0, 0, 0 }
	s.LocalRotation = pConfig.rotation or { 0, 0, 0 }

	return s
end

local _createOffsetCollisionBox = function(pShape, pDistance)
	local b = Box(
		{ -pShape.Width * 0.5 - pDistance, -pShape.Height * 0.5 - pDistance, -pShape.Depth * 0.5 - pDistance },
		{ pShape.Width * 0.5 + pDistance, pShape.Height * 0.5 + pDistance, pShape.Depth * 0.5 + pDistance }
	)

	return b
end

local _addTextTriggerArea = function(pShape, pConfig)
	pShape.message = Text()
	pShape.message.Type = TextType.Screen
	pShape.message.Text = pConfig.bubbleText or "You can edit this text using iShape:setMessage(string)"
	pShape.message.FontSize = 30
	pShape.message.Tail = true
	pShape.message.BackgroundColor = Color.White
	pShape.message.Color = Color.DarkGrey

	pShape.triggerBubbleArea = Object()
	pShape.triggerBubbleArea:SetParent(pShape)
	pShape.triggerBubbleArea.Physics = PhysicsMode.Trigger
	pShape.triggerBubbleArea.CollisionGroups = _COLLISION_GROUPS
	pShape.triggerBubbleArea.CollidesWithGroups = Player.CollisionGroups
	pShape.triggerBubbleArea.CollisionBox =
		_createOffsetCollisionBox(pShape, (pConfig.bubbleTriggerDistance or _DEFAULT_TRIGGER_DISTANCE))
	pShape.triggerBubbleArea.OnCollisionBegin = function(self, other)
		if other ~= Player then
			return
		else
			pShape.message:SetParent(World)
			pShape.message.Position = pShape.Position + { 0, pShape.Height, 0 } + _TEXT_OFFSET
		end
	end
	pShape.triggerBubbleArea.OnCollisionEnd = function(self, other)
		if other ~= Player then
			return
		else
			pShape.message:RemoveFromParent()
		end
	end
end

local _addCallbackTriggerArea = function(pShape, pConfig)
	pShape.triggerCallbackArea = Object()
	pShape.triggerCallbackArea:SetParent(pShape)
	pShape.triggerCallbackArea.Physics = PhysicsMode.Trigger
	pShape.triggerCallbackArea.CollisionGroups = { 6 }
	pShape.triggerCallbackArea.CollidesWithGroups = Player.CollisionGroups
	pShape.triggerCallbackArea.CollisionBox =
		_createOffsetCollisionBox(pShape, (pConfig.callbackTriggerDistance or _DEFAULT_TRIGGER_DISTANCE))
	pShape.triggerCallbackArea.OnCollisionBegin = function(self, other)
		if other ~= Player then
			return
		else
			self.timer = Timer(_TIMER, function()
				pShape.callback()
			end)
			self.countdown = _TIMER
		end
	end
	pShape.triggerCallbackArea.OnCollisionEnd = function(self, other)
		if other ~= Player then
			return
		else
			self.timer:Cancel()
		end
	end
	pShape.triggerCallbackArea.OnCollision = function(self, other)
		if self.timer and self.timer.RemainingTime < self.countdown then
			print("Callback in " .. self.countdown)
			self.countdown = self.countdown - 1
		end
	end
end

local _addButton = function(pShape, pConfig)
	pShape.button = require("uikit"):button({ content=pConfig.buttonText or "Button Text", textSize = "default" })
	pShape.button.onRelease = pConfig.buttonCallback or pConfig.callback
	pShape.button:hide()

	pShape.triggerButtonArea = Object()
	pShape.triggerButtonArea:SetParent(pShape)
	pShape.triggerButtonArea.Physics = PhysicsMode.Trigger
	pShape.triggerButtonArea.CollisionGroups = _COLLISION_GROUPS
	pShape.triggerButtonArea.CollidesWithGroups = Player.CollisionGroups
	pShape.triggerButtonArea.CollisionBox =
		_createOffsetCollisionBox(pShape, (pConfig.buttonTriggerDistance or _DEFAULT_TRIGGER_DISTANCE))
	pShape.triggerButtonArea.OnCollision = function(self, other)
		if other ~= Player then
			return
		else
			local p = Camera:WorldToScreen(pShape.Position + { 0, pShape.Height, 0 } + _BUTTON_OFFSET)
			local v = pShape.Position - Camera.Position
			local isVisible = Camera.Forward:Dot(v) >= 0
			if p and isVisible then
				pShape.button:show()
				pShape.button.pos = { p.Width * Screen.Width - pShape.button.Width * 0.5, p.Height * Screen.Height, 0 }
			else
				pShape.button:hide()
			end
		end
	end
	pShape.triggerButtonArea.OnCollisionEnd = function(self, other)
		if other ~= Player then
			return
		else
			pShape.button:hide()
		end
	end
end

---@function creates an iShape
---@param config table
---@code iShape = require("iShape")
---myConfig = {
--- position = Number3(10, 0, 10)
--- scale = 3
--- callback = function() print("I've been clicked") end
---}
---myInteractableShape = iShape.create(Items.user.shape, myConfig)
index.create = function(shape, config)
	-- Checking config
	local _config = {}
	_config.callback = type(config.callback) == "function" and config.callback or nil
	_config.callbackTriggerDistance = type(config.callbackTriggerDistance) == "number"
			and config.callbackTriggerDistance
		or nil
	_config.bubbleText = type(config.bubbleText) == "string" and config.bubbleText or nil
	_config.bubbleTriggerDistance = type(config.bubbleTriggerDistance) == "number" and config.bubbleTriggerDistance
		or nil
	_config.buttonText = type(config.buttonText) == "string" and config.buttonText or nil
	_config.buttonCallback = type(config.buttonCallback) == "function" and config.buttonCallback or nil
	_config.buttonTriggerDistance = type(config.buttonTriggerDistance) == "number" and config.buttonTriggerDistance
		or nil
	_config.position = type(config.position) == "Number3" and config.position or nil
	_config.rotation = type(config.rotation) == "Number3" and config.rotation or nil
	_config.scale = type(config.scale) == "number" and config.scale or nil

	-- Creating shape and adding relevant configs
	local _shape = _createBaseShape(shape, _config)

	-- Direct modification functions
	---@function Sets the OnClick callback for an existing iShape
	---@param function
	---@code myInteractableShape:setCallback(function() print("This is a new callback") end)
	_shape.setCallback = function(self, callback)
		if self ~= _shape then
			error("iShape:setCallback should be called with `:`", 2)
		end
		if type(callback) ~= "function" then
			error("Parameter is not a function", 2)
		end
		self.callback = callback
	end
	---@function Sets the Button callback for an existing iShape with a button
	---@param function
	---@code myInteractableShape:setButtonCallback(function() print("This is a new button callback") end)
	_shape.setButtonCallback = function(self, callback)
		if self ~= _shape then
			error("iShape:setButtonCallback should be called with `:`", 2)
		end
		if type(callback) ~= "function" then
			error("Parameter is not a function", 2)
		end
		self.button.onRelease = callback
	end
	---@function Sets the bubble text message for an existing iShape with a text bubble
	---@param text
	---@code myInteractableShape:setBubbleText("New text bubble content")
	_shape.setBubbleText = function(self, text)
		if self ~= _shape then
			error("iShape:setMessage should be called with `:`", 2)
		end
		if type(text) ~= "string" then
			error("Parameter is not a string", 2)
		end
		self.message.Text = text
	end
	---@function Sets the button text for an existing iShape with a button
	---@param text
	---@code myInteractableShape:setButtonText("New text bubble content")
	_shape.setButtonText = function(self, text)
		if self ~= _shape then
			error("iShape:setButtonText should be called with `:`", 2)
		end
		if type(text) ~= "string" then
			error("Parameter is not a string", 2)
		end
		self.button.Text = text
	end
	---@function Sets the trigger distance in blocks (factor in the scale) for the callback On Collision with the Player
	---@param integer
	---@code myInteractableShape:setCallbackTriggerDistance(10)
	_shape.setCallbackTriggerDistance = function(self, distance)
		if self ~= _shape then
			error("iShape:setCallbackTriggerDistance should be called with `:`", 2)
		end
		if type(distance) ~= "number" then
			error("Parameter is not a number", 2)
		end
		if self.triggerCallbackArea then
			self.triggerCallbackArea.CollisionBox = _createOffsetCollisionBox(self, distance)
		else
			_addCallbackTriggerArea(self, { callbackTriggerDistance = distance })
		end
	end
	---@function Sets the trigger distance in blocks (factor in the scale) for the Text bubble to appear
	---@param integer
	---@code myInteractableShape:setBubbleTriggerDistance(10)
	_shape.setBubbleTriggerDistance = function(self, distance)
		if self ~= _shape then
			error("iShape:setBubbleTriggerDistance should be called with `:`", 2)
		end
		if type(distance) ~= "number" then
			error("Parameter is not a number", 2)
		end
		if self.triggerBubbleArea then
			self.triggerBubbleArea.CollisionBox = _createOffsetCollisionBox(self, distance)
		else
			_addTextTriggerArea(self, { bubbleTriggerDistance = distance })
		end
	end
	---@function Sets the trigger distance in blocks (factor in the scale) for the button to appear
	---@param integer
	---@code myInteractableShape:setButtonTriggerDistance(10)
	_shape.setButtonTriggerDistance = function(self, distance)
		if self ~= _shape then
			error("iShape:setButtonTriggerDistance should be called with `:`", 2)
		end
		if type(distance) ~= "number" then
			error("Parameter is not a number", 2)
		end
		if self.triggerButtonArea then
			self.triggerButtonArea.CollisionBox = _createOffsetCollisionBox(self, distance)
		else
			_addButton(self, { buttonTriggerDistance = distance })
		end
	end

	if _config.callback then
		_shape:setCallback(_config.callback)
	end
	if _config.callbackTriggerDistance then
		_addCallbackTriggerArea(_shape, _config)
	end
	if _config.bubbleText or _config.bubbleTriggerdistance then
		_addTextTriggerArea(_shape, _config)
	end
	if _config.buttonText or _config.buttonCallback or _config.buttonTriggerDistance then
		_addButton(_shape, _config)
	end

	local onPointerDown = LocalEvent:Listen(LocalEvent.Name.PointerDown, function(pointerEvent)
		local impact = pointerEvent:CastRay(_shape.CollisionGroups)
		if impact ~= nil and impact.Object == _shape then
			_shape.callback()
		end
	end)

	return _shape
end

return iShape
