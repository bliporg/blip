--- This module allows you to create UI toast messages

uikit = require("uikit")
ease = require("ease")

-- Global variables
local PADDING = require("uitheme").current.padding
local ICON_MIN_SIZE = 40
local ICON_MAX_SIZE = 60
local topRightStack = {}
local centerStack = {}

local mod = {}

mod.create = function(_, config)
	local DEFAULT_CONFIG = {
		message = "hello!",
		maxWidth = 250,
		center = false,
		iconShape = nil,
		animationSpeed = 250, -- in points per second
		duration = 4.0, -- in seconds
		keepInStack = true, -- when false, the toast is not kept in the stack when a new toast comes in
		closeButton = false,
		actionText = "",
		action = nil,
	}

	config = require("config"):merge(DEFAULT_CONFIG, config, {
		acceptTypes = {
			iconShape = { "Shape", "MutableShape" },
			action = { "function" },
		},
	})

	-- create toast object
	local toast = {}
	toast.config = config
	toast.remove = remove

	local toastFrame = uikit:createFrame(Color.Black)
	toast.frame = toastFrame

	toast.stack = config.center and centerStack or topRightStack
	-- If there already is a toast on the stack, disable it
	if #toast.stack > 0 then
		local t = toast.stack[#toast.stack]
		if t.config.keepInStack == false then
			t:remove()
		else
			disable(toast.stack[#toast.stack])
		end
	end
	-- Push new toast to stack
	table.insert(toast.stack, toast)

	-- Create text
	local text = uikit:createText(config.message, Color.White)
	text:setParent(toastFrame)
	-- apply max width if specified
	if config.maxWidth then
		text.object.MaxWidth = config.maxWidth
	end

	-- Create icon (optional)
	local iconFrame
	local iconRatio
	if config.iconShape then
		iconFrame = uikit:createShape(config.iconShape, { spherized = false })
		iconRatio = iconFrame.Width / iconFrame.Height
		iconFrame:setParent(toastFrame)
	end

	local actionBtn
	if config.action then
		actionBtn = uikit:button({ content=config.actionText, borders = false, shadow = false })
		actionBtn:setParent(toastFrame)
		actionBtn.onRelease = function()
			config.action(toast)
		end
	end

	local closeBtn
	if config.closeButton then
		closeBtn = uikit:button({ content="❌", borders = false, shadow = false })
		closeBtn:setParent(toastFrame)
		closeBtn.onRelease = function()
			toast:remove()
		end
	end

	-- Setup toast layout, size, and position
	toastFrame.parentDidResize = function(self)
		local size = text.Size:Copy() -- start with text size
		local textAndIconHeight = size.Height

		if iconFrame then
			if iconRatio > 1.0 then -- width > height
				iconFrame.Width = math.max(ICON_MIN_SIZE, size.Height)
				iconFrame.Width = math.min(ICON_MAX_SIZE, iconFrame.Width)
				iconFrame.Height = iconFrame.Width / iconRatio
			else
				iconFrame.Height = math.max(ICON_MIN_SIZE, size.Height)
				iconFrame.Height = math.min(ICON_MAX_SIZE, iconFrame.Height)
				iconFrame.Width = iconFrame.Height * iconRatio
			end

			size.Width = iconFrame.Width + PADDING + size.Width
			size.Height = math.max(iconFrame.Height, size.Height)

			textAndIconHeight = size.Height
		end

		if closeBtn then
			size.Height = size.Height + PADDING + closeBtn.Height
		end

		if actionBtn then
			if closeBtn == nil then
				size.Height = size.Height + PADDING + actionBtn.Height
			end
			actionBtn.Width = nil
			if closeBtn then
				actionBtn.Width = math.max(actionBtn.Width, size.Width - closeBtn.Width - PADDING)
				size.Width = math.max(actionBtn.Width + PADDING + closeBtn.Width, size.Width)
			else
				actionBtn.Width = math.max(actionBtn.Width, size.Width)
				size.Width = math.max(actionBtn.Width, size.Width)
			end
		end

		size.Height = size.Height + PADDING * 2
		size.Width = size.Width + PADDING * 2

		local x = PADDING

		if iconFrame then
			iconFrame.pos = { x, size.Height - textAndIconHeight * 0.5 - iconFrame.Height * 0.5 - PADDING }
			x = x + iconFrame.Width + PADDING
		end

		text.pos = { x, size.Height - textAndIconHeight * 0.5 - text.Height * 0.5 - PADDING }

		if closeBtn then
			closeBtn.pos = { PADDING, PADDING }
		end

		if actionBtn then
			if closeBtn then
				actionBtn.pos = { closeBtn.pos.X + closeBtn.Width + PADDING, PADDING }
			else
				actionBtn.pos = { PADDING, PADDING }
			end
		end

		self.Size = size

		if config.center then
			self.position = Screen.Size * 0.5 - self.Size * 0.5
		else
			self.position = Screen.Size - self.Size - Number2(0, Screen.SafeArea.Top) - Number2(PADDING, PADDING)
		end
	end
	toastFrame:parentDidResize()

	-- Animate toast
	enable(toast)

	return toast
end

-- start toast timer
constructAndStartTimer = function(p_toast)
	if p_toast.config.duration ~= nil and p_toast.config.duration >= 0 then
		if p_toast.removeTimer then
			p_toast.removeTimer:Cancel()
			p_toast.removeTimer = nil
		end
		p_toast.removeTimer = Timer(p_toast.config.duration, function()
			p_toast:remove()
		end)
	end
end

-- Provide a function to remove the toast
remove = function(p_toast)
	if p_toast.removeTimer then
		p_toast.removeTimer:Cancel()
		p_toast.removeTimer = nil
	end

	-- Remove toast from stack
	local stack = p_toast.stack
	for i, toast in ipairs(stack) do
		if toast == p_toast then
			if i == #stack and i > 1 then -- toast is on top
				-- re-enable toast below
				enable(stack[i - 1])
			end
			table.remove(stack, i)
			break
		end
	end

	p_toast.frame:remove()
end

-- temporary disable toast
disable = function(p_toast)
	p_toast.frame:hide()
	if p_toast.removeTimer then
		p_toast.removeTimer:Cancel()
		p_toast.removeTimer = nil
	end
end

-- re-enable toast
enable = function(p_toast)
	local frame = p_toast.frame

	p_toast.frame:show()

	local toastPosition
	local animationDuration
	if p_toast.config.center then
		local animationDistance = frame.Height * 2
		toastPosition = Screen.Size / 2 - frame.Size / 2
		frame.position = toastPosition - Number2(0, animationDistance)
		animationDuration = animationDistance / p_toast.config.animationSpeed
	else
		toastPosition = Screen.Size - frame.Size - Number2(0, Screen.SafeArea.Top) - Number2(PADDING, PADDING)
		frame.position = toastPosition + Number2(frame.Width, 0)
		animationDuration = frame.Width / p_toast.config.animationSpeed
	end
	ease:cancel(frame)
	ease:outBack(frame, animationDuration).position = Number3(toastPosition.X, toastPosition.Y, 0)

	constructAndStartTimer(p_toast)
end

return mod
