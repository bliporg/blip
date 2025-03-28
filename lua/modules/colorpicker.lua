local colorPicker = {}

colorPicker.create = function(_, config)
	local theme = require("uitheme").current

	local _config = { -- default config
		closeBtnColor = nil,
		closeBtnIcon = "❌",
		previewColorInCloseBtn = false,
		transparency = true,
		colorPreview = true,
		colorCode = true,
		-- number or function returning number
		maxWidth = 500,
		maxHeight = 300,
		extraPadding = false, -- adds padding all around components
		uikit = require("uikit"),
	}
	if config ~= nil then
		if config.closeBtnColor ~= nil then
			_config.closeBtnColor = config.closeBtnColor
		end
		if config.closeBtnIcon ~= nil then
			_config.closeBtnIcon = config.closeBtnIcon
		end
		if config.previewColorInCloseBtn ~= nil then
			_config.previewColorInCloseBtn = config.previewColorInCloseBtn
		end
		if config.transparency ~= nil then
			_config.transparency = config.transparency
		end
		if config.colorPreview ~= nil then
			_config.colorPreview = config.colorPreview
		end
		if config.colorCode ~= nil then
			_config.colorCode = config.colorCode
		end
		if config.maxWidth ~= nil then
			_config.maxWidth = config.maxWidth
		end
		if config.maxHeight ~= nil then
			_config.maxHeight = config.maxHeight
		end
		if config.extraPadding ~= nil then
			_config.extraPadding = config.extraPadding
		end
		if config.uikit ~= nil then
			_config.uikit = config.uikit
		end
	end
	config = _config

	local uikit = config.uikit

	local node = uikit:createNode()
	node.config = config

	local cursorModel = MutableShape()

	cursorModel:AddBlock(Color.Black, 0, 0, 0)
	cursorModel:AddBlock(Color.Black, 0, 1, 0)
	cursorModel:AddBlock(Color.Black, 0, 2, 0)

	cursorModel:AddBlock(Color.Black, 1, 0, 0)
	cursorModel:AddBlock(Color.White, 1, 1, 0)
	cursorModel:AddBlock(Color.Black, 1, 2, 0)

	cursorModel:AddBlock(Color.Black, 2, 1, 0)

	local _hueSliderCursor = Shape(cursorModel)
	_hueSliderCursor.CollisionGroups = {}

	cursorModel:AddBlock(Color.Black, 2, 0, 0)
	cursorModel:AddBlock(Color.Black, 2, 2, 0)

	local _hsvCursor = Shape(cursorModel)
	_hsvCursor.CollisionGroups = {}
	local hueSliderCursor = uikit:createShape(_hueSliderCursor, {
		doNotFlip = true,
		perBlockCollisions = true,
	})
	hueSliderCursor:setParent(node)
	hueSliderCursor.pos.Z = -550 -- remove this once uikit better manages layers

	local alphaSliderCursor
	if config.transparency then
		local _alphaSliderCursor = Shape(_hueSliderCursor)
		_alphaSliderCursor.CollisionGroups = {}

		alphaSliderCursor = uikit:createShape(_alphaSliderCursor, {
			doNotFlip = true,
			perBlockCollisions = true,
		})
		alphaSliderCursor:setParent(node)
		alphaSliderCursor.pos.Z = -550 -- remove this once uikit better manages layers
	end

	local hsvCursor = uikit:createShape(_hsvCursor, {
		doNotFlip = true,
		perBlockCollisions = true,
	})
	hsvCursor:setParent(node)
	hsvCursor.pos.Z = -550 -- remove this once uikit better manages layers

	node.currentAlpha = 255
	node.previousColor = nil
	node.currentColor = Color(255, 0, 0)

	node.nbAlphaSteps = 6.0

	node.setMaxSize = function(self, w, h)
		self.config.maxWidth = w
		self.config.maxHeight = h
		self:_refresh()
	end

	-- callbacks
	node.didPickColor = nil -- function(self, color)
	node.didClose = nil

	node.close = function(self)
		self:setParent(nil)
		if self.didClose ~= nil then
			self:didClose()
		end
	end

	local bg = uikit:frameTextBackground()
	bg:setParent(node)
	node.background = bg
	local closeBtn = uikit:buttonNeutral({ content = config.closeBtnIcon })
	if config.closeBtnColor then
		closeBtn:setColor(config.closeBtnColor, Color.White)
	end
	closeBtn:setParent(node)
	node.closeBtn = closeBtn
	closeBtn.onRelease = function(_)
		if node.onClose ~= nil then
			node.onClose()
		else
			node:close()
		end
	end

	local hexCodeBtn = uikit:button({ content="#FFFFFF" })
	if config.closeBtnColor then
		hexCodeBtn:setColor(config.closeBtnColor, Color.White)
	end
	-- hexCodeBtn:setParent(node) -- TODO: turn this back on / implement feature
	hexCodeBtn:hide()
	hexCodeBtn.onRelease = function(_)
		-- node:close()
	end

	node._width = function(self)
		return self.background.Width
	end

	node._height = function(self)
		return self.background.Height
	end

	local paletteShape = MutableShape()
	paletteShape.CollisionGroups = {}

	local h = 160 -- degrees
	node.paletteShapeSize = 11

	local c = Color(0, 0, 0)
	for s = 0, (node.paletteShapeSize - 1) do
		for v = 0, (node.paletteShapeSize - 1) do
			c.H = h
			c.S = s / 10.0
			c.V = v / 10.0
			local i = paletteShape.Palette:AddColor(c)
			paletteShape:AddBlock(c, s, v, 0)
			local b = paletteShape:GetBlock(s, v, 0)
			b.PaletteIndex = i
		end
	end

	local uiPaletteShape = uikit:createShape(paletteShape, { doNotFlip = true })
	uiPaletteShape:setParent(node)

	local function pickSV(x, y)
		local currentColor = node.currentColor

		if x < 0 then
			currentColor.S = 0
		elseif x > uiPaletteShape.Width then
			currentColor.S = 1.0
		else
			currentColor.S = x / uiPaletteShape.Width
		end

		if y < 0 then
			currentColor.V = 0
		elseif y > uiPaletteShape.Height then
			currentColor.V = 1.0
		else
			currentColor.V = y / uiPaletteShape.Height
		end

		node:_refreshColor()
		node:_didPickColor()
	end

	local pickSVFromPointerEvent = function(pe)
		local pressed = uiPaletteShape
		local pressedX = pressed.pos.X
		local pressedY = pressed.pos.Y

		local p = pressed.parent
		while p ~= nil do
			pressedX = pressedX + p.pos.X
			pressedY = pressedY + p.pos.Y
			p = p.parent
		end

		local x = pe.X * Screen.Width
		local y = pe.Y * Screen.Height

		pickSV(x - pressedX, y - pressedY)
	end
	uiPaletteShape.onPress = function(_, _, _, pe)
		pickSVFromPointerEvent(pe)
	end
	uiPaletteShape.onDrag = function(_, pe)
		pickSVFromPointerEvent(pe)
	end

	local hueShape = MutableShape()
	hueShape.CollisionGroups = {}

	c = Color(0, 0, 0)
	local nbHueSteps = 64 -- can't be more than 128
	for h = 0, nbHueSteps - 1 do
		c.H = h * (360.0 / (nbHueSteps - 1))
		c.S = 1.0
		c.V = 1.0
		hueShape:AddBlock(c, 0, h, 0)
	end

	local uiHueShape = uikit:createShape(hueShape, {
		doNotFlip = true,
		perBlockCollisions = true,
	})
	uiHueShape:setParent(node)

	local function pickH(_, y)
		local h
		if y < 0 then
			h = 0
		elseif y > uiHueShape.Height then
			h = 1.0
		else
			h = y / uiHueShape.Height
		end

		node.currentColor.Hue = h * 360.0
		node:_refreshColor()
		node:_didPickColor()
	end

	local pickHFromPointerEvent = function(pe)
		local pressed = uiPaletteShape
		local pressedX = pressed.pos.X
		local pressedY = pressed.pos.Y

		local p = pressed.parent
		while p ~= nil do
			pressedX = pressedX + p.pos.X
			pressedY = pressedY + p.pos.Y
			p = p.parent
		end

		local x = pe.X * Screen.Width
		local y = pe.Y * Screen.Height

		pickH(x - pressedX, y - pressedY)
	end
	uiHueShape.onPress = function(_, _, _, pe)
		pickHFromPointerEvent(pe)
	end
	uiHueShape.onDrag = function(_, pe)
		pickHFromPointerEvent(pe)
	end

	local uiFinalShape
	if config.colorPreview then
		local finalShape = MutableShape()
		finalShape.CollisionGroups = {}
		for i = 0, 7 do
			for j = 0, 7 do
				finalShape:AddBlock((i + j) % 2 == 0 and Color.White or Color.Grey, i, j, 0)
			end
		end

		node.finalShape = finalShape
		uiFinalShape = uikit:createShape(finalShape, {
			doNotFlip = true,
			perBlockCollisions = true,
		})
		uiFinalShape:setParent(node)
	end

	local parseHexaColor = function(input)
		input = input:gsub("[%[%]()#]", "")
		-- Convert hex color components to numbers
		local r = tonumber(input:sub(1, 2), 16)
		local g = tonumber(input:sub(3, 4), 16)
		local b = tonumber(input:sub(5, 6), 16)

		-- Check that the conversion was successful
		if r == nil or g == nil or b == nil then
			return false
		end
		if r < 0 or r > 255 then
			return false
		end
		if g < 0 or g > 255 then
			return false
		end
		if b < 0 or b > 255 then
			return false
		end

		return true, r, g, b
	end

	local parseRGBColor = function(input)
		input = input:gsub("[%[%]()#]", "")
		local colors = {}
		for color in input:gmatch("([^, ]+)") do
			table.insert(colors, tonumber(color))
			if #colors > 3 then
				return false
			end
		end

		if #colors ~= 3 then
			return false
		end

		for i, c in ipairs(colors) do
			local n = tonumber(c)
			if n == nil then
				return false
			end
			n = math.floor(n)
			if n == nil or n < 0 or n > 255 then
				return false
			end
			colors[i] = n
		end

		return true, colors[1], colors[2], colors[3]
	end

	local colorCode
	if config.colorCode then
		colorCode = uikit:createTextInput("(255,255,255)", "", "small")
		colorCode.pos.Z = 900
		colorCode:setParent(node)
		node.colorCode = colorCode
		colorCode.onFocus = function()
			uiFinalShape:hide()
			colorCode.Text = ""
		end
		colorCode.onFocusLost = function()
			uiFinalShape:show()

			local ok, r, g, b = parseRGBColor(colorCode.Text)
			if ok then
				node:setColor(Color(r, g, b))
				return
			end

			ok, r, g, b = parseHexaColor(colorCode.Text)
			if ok then
				node:setColor(Color(r, g, b))
				return
			end

			colorCode.Text = "("
				.. math.floor(node.currentColor.R)
				.. ","
				.. math.floor(node.currentColor.G)
				.. ","
				.. math.floor(node.currentColor.B)
				.. ")"
		end
		colorCode.onSubmit = function()
			local ok, r, g, b = parseRGBColor(colorCode.Text)
			if ok then
				node:setColor(Color(r, g, b))
				return
			end

			ok, r, g, b = parseHexaColor(colorCode.Text)
			if ok then
				node:setColor(Color(r, g, b))
				return
			end
		end
	end

	local bgAlpha
	local bgAlphaColor
	local alpha
	if config.transparency then
		local nbAlphaSteps = node.nbAlphaSteps

		bgAlpha = uikit:createFrame(Color.White)
		bgAlpha:setParent(node)

		local bgAlphaShape = MutableShape()
		for i = 0, 63 do
			bgAlphaShape:AddBlock(
				(math.floor(i / 4) + i) % 2 == 0 and Color.White or Color.Grey,
				i % 4,
				math.floor(i / 4),
				0
			)
		end

		bgAlphaColor = uikit:createShape(bgAlphaShape, {
			doNotFlip = true,
			perBlockCollisions = true,
		})
		bgAlphaColor:setParent(bgAlpha)
		bgAlphaShape.CollisionGroups = {}

		local shapeAlpha = MutableShape()
		for i = 1, nbAlphaSteps do
			local value = i / nbAlphaSteps
			local c = Color(1.0, 1.0, 1.0, value)
			shapeAlpha:AddBlock(c, 0, i - 1, 0)
		end

		alpha = uikit:createShape(shapeAlpha, {
			doNotFlip = true,
			perBlockCollisions = true,
		})
		alpha:setParent(bgAlpha)
		alpha.onPress = function(_, shape, block)
			node.currentAlpha = shape.Palette[block.PaletteIndex].Color.A
			node:_refreshColor()
			node:_didPickColor()
		end

		bgAlphaColor.pos = { theme.padding, theme.padding }
		bgAlphaColor.pos.Z = -1

		alpha.pos = { theme.padding, theme.padding }
		alpha.pos.Z = bgAlphaColor.pos.Z - 1
	end

	node._setColor = function(self, color)
		if color == nil then
			return
		end
		local c = Color(color) -- temporary, to access HSV

		if self.currentColor == nil then
			self.currentColor = Color(255, 255, 255, 255)
		end

		self.currentColor.Hue = c.Hue
		self.currentColor.Saturation = c.Saturation
		self.currentColor.Value = c.Value
	end

	node._refresh = function(self)
		local maxHeight
		if type(self.config.maxHeight) == "function" then
			maxHeight = self.config.maxHeight()
		else
			maxHeight = self.config.maxHeight
		end

		local maxWidth
		if type(self.config.maxWidth) == "function" then
			maxWidth = self.config.maxWidth()
		else
			maxWidth = self.config.maxWidth
		end

		local padding = theme.padding

		closeBtn.Width = nil
		local columnWidth = closeBtn.Width
		local bottomBarHeight = closeBtn.Height

		local minWidth = hexCodeBtn.Width + columnWidth + padding
		if config.extraPadding then
			minWidth = minWidth + padding * 2
		end
		if config.transparency then
			minWidth = minWidth + columnWidth + padding
		end

		if maxWidth < minWidth then
			maxWidth = minWidth
		end

		local minHeight = hexCodeBtn.Height + hexCodeBtn.Width + padding
		if config.extraPadding then
			minHeight = minHeight + padding * 2
		end
		local height = maxHeight
		if height < minHeight then
			height = minHeight
		end

		-- color area is a square
		local colorAreaSize = height - bottomBarHeight - padding
		if config.extraPadding then
			colorAreaSize = colorAreaSize - padding * 2
		end

		local width = colorAreaSize + columnWidth + padding
		if config.extraPadding then
			width = width + padding * 2
		end
		if config.transparency then
			width = width + columnWidth + padding
		end

		-- width too big, compute using that limit
		if width > maxWidth then
			width = maxWidth
			colorAreaSize = width - columnWidth - padding
			if config.extraPadding then
				colorAreaSize = colorAreaSize - padding * 2
			end
			if config.transparency then
				colorAreaSize = colorAreaSize - columnWidth - padding
			end
			height = hexCodeBtn.Height + colorAreaSize + padding
			if config.extraPadding then
				height = height + padding * 2
			end
		end

		bg.Width = width
		bg.Height = height

		if config.colorPreview then
			closeBtn.pos = { bg.Width - columnWidth, 0 }
			if config.extraPadding then
				closeBtn.pos = closeBtn.pos + { -padding, padding }
			end
		else
			closeBtn.pos = { 0, 0 }
			closeBtn.Width = width
			if config.extraPadding then
				closeBtn.pos = closeBtn.pos + { padding, padding }
				closeBtn.Width = closeBtn.Width - padding * 2
			end
		end

		if config.colorPreview then
			uiFinalShape.Width = bg.Width - closeBtn.Width - padding
			if config.extraPadding then
				uiFinalShape.Width = uiFinalShape.Width - padding * 2
			end
			uiFinalShape.Height = bottomBarHeight
			uiFinalShape.pos = { padding, padding }
		end

		if colorCode then
			colorCode.Width = bg.Width - closeBtn.Width - padding
			if config.extraPadding then
				colorCode.Width = colorCode.Width - padding * 2
			end
			colorCode.Height = bottomBarHeight
			colorCode.pos = { padding, padding }
		end

		hexCodeBtn.pos = { padding, padding }

		uiPaletteShape.pos = { 0, bg.Height - colorAreaSize }
		if config.extraPadding then
			uiPaletteShape.pos = uiPaletteShape.pos + { padding, -padding }
		end

		uiPaletteShape.Width = colorAreaSize
		uiPaletteShape.Height = colorAreaSize

		uiHueShape.Width = columnWidth
		uiHueShape.Height = colorAreaSize
		uiHueShape.pos = { colorAreaSize + padding, bottomBarHeight + padding }
		if config.extraPadding then
			uiHueShape.pos = uiHueShape.pos + { padding, padding, 0 }
		end

		local hue = 0.0 -- 0 to 360
		if self.currentColor ~= nil then
			hue = self.currentColor.Hue
		end

		hueSliderCursor.pos = uiHueShape.pos
			- { 0, hueSliderCursor.Height * 0.5, 0 }
			+ { 0, uiHueShape.Height * hue / 360.0, 0 }

		hue = 0.0 -- 0 to 360
		local saturation = 0.0 -- 0 to 1
		local value = 0.0 -- 0 to 1
		if self.currentColor ~= nil then
			hue = self.currentColor.Hue
			saturation = self.currentColor.Saturation
			value = self.currentColor.Value
		end
		local sStep = math.floor(saturation * self.paletteShapeSize)
		if sStep >= self.paletteShapeSize then
			sStep = self.paletteShapeSize - 1
		end
		local vStep = math.floor(value * self.paletteShapeSize)
		if vStep >= self.paletteShapeSize then
			vStep = self.paletteShapeSize - 1
		end
		local svStepSize = uiPaletteShape.Width / self.paletteShapeSize
		hueSliderCursor.pos = uiHueShape.pos
			- { 0, hueSliderCursor.Height * 0.5, 0 }
			+ { 0, uiHueShape.Height * hue / 360.0, 0 }
		hsvCursor.pos = uiPaletteShape.pos
			- { hsvCursor.Width * 0.5, hsvCursor.Height * 0.5, 0 }
			+ { svStepSize * (sStep + 0.5), svStepSize * (vStep + 0.5), 0 }

		if config.transparency then
			bgAlpha.Width = columnWidth
			bgAlpha.Height = colorAreaSize
			bgAlpha.pos = { colorAreaSize + columnWidth + padding, bottomBarHeight + padding * 2 }

			if config.extraPadding then
				bgAlpha.pos.X = bgAlpha.pos.X + padding * 2
			end

			local r = self.currentAlpha / 255
			local step = math.ceil(r * self.nbAlphaSteps) - 1
			local stepHeight = bgAlpha.Height / self.nbAlphaSteps
			alphaSliderCursor.pos = bgAlpha.pos
				- { 0, alphaSliderCursor.Height * 0.5 }
				+ { 0, stepHeight * (step + 0.5) }

			bgAlphaColor.Width = bgAlpha.Width - 2 * padding
			bgAlphaColor.Height = bgAlpha.Height - 2 * padding
			alpha.Width = bgAlphaColor.Width
			alpha.Height = bgAlphaColor.Height
		end

		if self.didRefresh ~= nil then
			self:didRefresh()
		end
	end
	node._refreshColor = function(self)
		local refreshHue = false

		if self.currentColor ~= nil then
			if self.previousColor == nil then
				refreshHue = true
				self.previousColor = Color(255, 255, 255, 255)
			elseif self.previousColor.Hue ~= self.currentColor.Hue then
				refreshHue = true
			end
		end

		if refreshHue then
			local c = Color(0, 0, 0)
			local i = 1
			for s = 0, (self.paletteShapeSize - 1) do
				for v = 0, (self.paletteShapeSize - 1) do
					c.H = self.currentColor.H
					c.S = s / 10.0
					c.V = v / 10.0
					paletteShape.Palette[i].Color = c
					i = i + 1
				end
			end
			self.previousColor.Hue = self.currentColor.Hue
			self.previousColor.Saturation = self.currentColor.Saturation
			self.previousColor.Value = self.currentColor.Value
		end

		local alpha = self.currentAlpha / 255
		local iAlpha = 1.0 - alpha

		local c1 = Color(Color.White)

		c1.R = math.floor((c1.R * iAlpha) + (self.currentColor.R * alpha))
		c1.G = math.floor((c1.G * iAlpha) + (self.currentColor.G * alpha))
		c1.B = math.floor((c1.B * iAlpha) + (self.currentColor.B * alpha))

		local c2 = Color(Color.Grey)
		c2.R = math.floor(c2.R * iAlpha + self.currentColor.R * alpha)
		c2.G = math.floor(c2.G * iAlpha + self.currentColor.G * alpha)
		c2.B = math.floor(c2.B * iAlpha + self.currentColor.B * alpha)

		if self.finalShape then
			self.finalShape.Palette[1].Color = c1
			self.finalShape.Palette[2].Color = c2
		end

		if self.config.previewColorInCloseBtn then
			self.closeBtn:setColor(c1)
		end

		if self.colorCode then
			self.colorCode.Text = "("
				.. math.floor(self.currentColor.R)
				.. ","
				.. math.floor(self.currentColor.G)
				.. ","
				.. math.floor(self.currentColor.B)
				.. ")"
		end

		if alphaSliderCursor then
			local r = self.currentAlpha / 255
			local step = math.ceil(r * self.nbAlphaSteps) - 1
			local stepHeight = bgAlpha.Height / self.nbAlphaSteps
			alphaSliderCursor.pos = bgAlpha.pos
				- { 0, alphaSliderCursor.Height * 0.5 }
				+ { 0, stepHeight * (step + 0.5) }
		end

		local hue = 0.0 -- 0 to 360
		local saturation = 0.0 -- 0 to 1
		local value = 0.0 -- 0 to 1
		if self.currentColor ~= nil then
			hue = self.currentColor.Hue
			saturation = self.currentColor.Saturation
			value = self.currentColor.Value
		end

		hueSliderCursor.pos = uiHueShape.pos
			- { 0, hueSliderCursor.Height * 0.5 }
			+ { 0, uiHueShape.Height * hue / 360.0 }
		hsvCursor.pos.X = uiPaletteShape.pos.X - hsvCursor.Width * 0.5 + saturation * uiPaletteShape.Width
		hsvCursor.pos.Y = uiPaletteShape.pos.Y - hsvCursor.Height * 0.5 + value * uiPaletteShape.Height
	end

	node._didPickColor = function(self)
		if self.didPickColor ~= nil then
			self:didPickColor(self:getColor())
		end
	end

	node.setColor = function(self, color)
		self:_setColor(color)
		self:_refreshColor()
	end

	node.getColor = function(_)
		local c = Color(node.currentColor)
		c.Alpha = node.currentAlpha
		return c
	end

	node:_refresh()

	return node
end

return colorPicker
