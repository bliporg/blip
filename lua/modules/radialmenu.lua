radialMenu = {}
_menu = nil

conf = require("config")
ease = require("ease")
ui = require("uikit")

local defaultConfig = {
	target = Player.Avatar,
	offset = { 0, 0, 0 },
	nodes = {
		{
			type = "text",
			text = "Timer 0",
			angle = 45,
			radius = 80,
			onRelease = function() end,
			tick = function(o, dt)
				o.txt.Text = "Timer " .. math.floor(o.buttonT)
				o.buttonT = o.buttonT + dt
				o:contentDidResize()
			end,
			onMenuOpen = function(o)
				o.buttonT = 0
			end,
		},
		{
			type = "button",
			text = "Button",
			angle = 135,
			radius = 80,
			onRelease = function()
				print("Button pressed")
			end,
			tick = function() end,
			onMenuOpen = function() end,
		},
		{
			type = "button",
			text = "❌",
			angle = -90,
			radius = 80,
			onRelease = function()
				radialMenu.remove()
			end,
			tick = function() end,
			onMenuOpen = function() end,
		},
	},
}

local createRadialNode = function(config)
	if config.type == "text" then
		local frame = ui:createFrame(Color(0, 0, 0, 150))
		frame:setParent(_menu)
		frame.txt = ui:createText(config.text, Color.White)
		frame.txt:setParent(frame)
		frame.txt.pos = { 8, 8 }

		frame.ticklistener = config.tick
		frame.Width = frame.txt.Width + 8 * 2
		frame.Height = frame.txt.Height + 8 * 2
		frame.pos = -Number2(frame.Width, frame.Height) * 0.5
		local angle = math.rad(config.angle)
		local v = Number2(math.cos(angle), math.sin(angle))
		local target = v * config.radius - Number2(frame.Width, frame.Height) * 0.5
		ease:outBack(frame, 0.3).pos = Number3(target.X, target.Y, 0)

		frame.contentDidResize = function(self)
			self.Width = self.txt.Width + 8 * 2
			self.Height = self.txt.Height + 8 * 2
		end
		frame:contentDidResize()

		if config.onMenuOpen ~= nil then
			config.onMenuOpen(frame)
		end

		return frame
	elseif config.type == "button" then
		local btn = ui:button({ content=config.text })
		btn:setParent(_menu)
		btn.pos = -Number2(btn.Width, btn.Height) * 0.5
		local angle = math.rad(config.angle)
		local v = Number2(math.cos(angle), math.sin(angle))
		local target = v * config.radius - Number2(btn.Width, btn.Height) * 0.5
		ease:outBack(btn, 0.3).pos = Number3(target.X, target.Y, 0)
		btn.onRelease = config.onRelease
		btn.ticklistener = config.tick
		if config.onMenuOpen ~= nil then
			config.onMenuOpen(btn)
		end

		return btn
	else
		error("type not supported", 2)
		return nil
	end
end

radialMenu.create = function(_, config)
	radialMenu.remove()
	_config = conf:merge(
		defaultConfig,
		config,
		{ acceptTypes = { target = { "Object", "Shape", "MutableShape", "Player" } } }
	)
	_menu = ui:createNode()
	_menu.nodes = {}
	for _, nodeConfig in ipairs(_config.nodes) do
		table.insert(_menu.nodes, createRadialNode(nodeConfig))
	end

	_menu.updatePosition = function(self)
		local pos = _config.target:PositionLocalToWorld(_config.offset)
		local screenPos = Camera:WorldToScreen(pos)

		if screenPos.X == nil or screenPos.Y == nil then
			self:hide()
			return
		else
			self:show()
		end

		self.pos = { screenPos.X * Screen.Width, screenPos.Y * Screen.Height }
	end

	_menu.parentDidResize = function(self)
		self:updatePosition()
	end
	_menu:parentDidResize()

	_menu.listener = LocalEvent:Listen(LocalEvent.Name.Tick, function(dt)
		_menu:updatePosition()
		for _, node in ipairs(_menu.nodes) do
			if node.ticklistener ~= nil then
				node.ticklistener(node, dt)
			end
		end
	end)

	return _menu
end

radialMenu.remove = function()
	if _menu == nil then
		return
	end
	_menu.listener:Remove()
	_menu:remove()
	_menu = nil
end

return radialMenu
