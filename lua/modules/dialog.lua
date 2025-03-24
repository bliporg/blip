local mod = {}

dialog = nil
dialogFrame = nil
dialogTimer = nil
tickListener = nil

local margin = 10
local marginSmall = 5
local maxWidth = 500

mod.setMaxWidth = function(_, w)
	maxWidth = w
end

mod.create = function(_, text, target, answers, callback)
	mod:remove()

	local ui = require("uikit")
	local ease = require("ease")

	dialog = {}

	local getPos = function()
		local p
		local ok = pcall(function()
			p = target.Position:Copy()
		end)
		if ok then
			pcall(function()
				p.Y = p.Y + target.BoundingBox.Max.Y
			end)
			return p
		end
		if typeof(target) == "Number3" then
			return target
		end
		ok = pcall(function()
			p = Number3(target[1], target[2], target[3])
		end)
		if ok then
			return p
		end
		return Number3.Zero
	end

	dialogFrame = ui:createFrame(Color(0, 0, 0, 150))

	local fullText = text
	local textLen = #fullText
	local displayed = math.min(1, textLen)

	local t = ui:createText(string.sub(fullText, 1, displayed), Color.White)
	t:setParent(dialogFrame)
	t.pos = { margin, margin }
	dialogFrame.text = t

	if type(answers) ~= "table" then
		answers = {}
	end

	for i, answer in ipairs(answers) do
		local btn
		if type(answer) == "string" then
			btn = ui:button({ content=answer })
		else
			btn = ui:button({ content="ERROR" })
		end
		btn:hide()
		btn.index = i
		btn.onRelease = function(self)
			if callback ~= nil then
				callback(self.index, self.Text)
			end
		end
		btn.disabled = true
		btn:setParent(dialogFrame)
		answers[i] = btn
	end
	dialog.answers = answers

	dialogFrame.parentDidResize = function(self)
		self.text.object.MaxWidth = math.min(maxWidth, Screen.Width * 0.75)
		self.Width = self.text.Width + margin * 2
		self.Height = self.text.Height + margin * 2
	end

	dialogFrame.updatePosition = function(self)
		local screenPos = Camera:WorldToScreen(getPos())
		local x = screenPos.X or 0.5
		local y = screenPos.Y or 1

		local posX = x * Screen.Width - self.Width * 0.5
		posX = math.max(Screen.SafeArea.Left + margin, posX)
		posX = math.min(Screen.Width - Screen.SafeArea.Right - self.Width - margin, posX)

		local posY = y * Screen.Height
		posY = math.max(Screen.SafeArea.Bottom + margin, posY)
		posY = math.min(Screen.Height - Screen.SafeArea.Top - self.Height - margin, posY)

		self.pos = { posX, posY }
	end

	dialogFrame.updateAnswersPosition = function(self)
		local previous
		local totalWidth = 0
		local row = 1
		for i = 1, #answers do
			local answer = answers[i]
			answer:show()
			ease:cancel(answer.pos)
			totalWidth = totalWidth + answer.Width
			answer.pos.X = marginSmall
			if totalWidth > self.Width - 2 * margin then
				totalWidth = 0
				row = row + 1
			elseif previous then
				answer.pos.X = previous.pos.X + previous.Width + marginSmall
			end
			previous = answer

			answer.pos.Y = -answer.Height * row
			ease:outBack(answer.pos, 0.3, {
				onDone = function(_)
					answer.disabled = false
				end,
			}).Y = -answer.Height
					* row
				- marginSmall * row
		end
	end

	dialog.complete = function(_)
		if dialogTimer ~= nil then
			dialogTimer:Cancel()
			dialogTimer = nil
			displayed = textLen
			dialogFrame.text.Text = fullText
			dialogFrame:parentDidResize()
			dialogFrame:updatePosition()
			dialogFrame:updateAnswersPosition()
		end
	end

	dialog.remove = function(self)
		if dialog == self then
			mod.remove()
		end
	end

	dialogTimer = Timer(0.02, true, function()
		displayed = math.min(displayed + 1, textLen)
		dialogFrame.text.Text = string.sub(fullText, 1, displayed)

		-- sfx("hitmarker_3", { Spatialized = false, Volume = 0.1, Pitch = 0.8 + math.random() * 0.4 })

		if displayed == textLen then
			dialog:complete()
		else
			dialogFrame:parentDidResize()
		end
	end)

	tickListener = LocalEvent:Listen(LocalEvent.Name.Tick, function()
		dialogFrame:updatePosition()
	end)

	dialogFrame:parentDidResize()
	dialogFrame:updatePosition()
end

mod.remove = function()
	if dialog ~= nil then
		if dialogTimer ~= nil then
			dialogTimer:Cancel()
			dialogTimer = nil
		end

		if tickListener ~= nil then
			tickListener:Remove()
			tickListener = nil
		end

		for _, answer in ipairs(dialog.answers) do
			answer:remove()
		end

		dialogFrame:remove()
		dialogFrame = nil
		dialog = nil
	end
end

mod.complete = function()
	if dialog ~= nil then
		dialog:complete()
	end
end

return mod
