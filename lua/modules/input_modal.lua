local inputModal = {}

inputModal.create = function(_, prompt)
	local uikit = require("uikit")
	local modal = require("modal")
	local theme = require("uitheme").current
	local ease = require("ease")

	local minButtonWidth = 100

	local content = modal:createContent()
	content.closeButton = false

	content.idealReducedContentSize = function(content, _, _)
		content:refresh()
		return Number2(content.Width, content.Height)
	end

	local maxWidth = function()
		return Screen.Width - theme.modalMargin * 2
	end

	local maxHeight = function()
		return Screen.Height - 100
	end

	local position = function(modal, forceBounce)
		local p = Number3(Screen.Width * 0.5 - modal.Width * 0.5, Screen.Height * 0.5 - modal.Height * 0.5, 0)

		if not modal.updatedPosition or forceBounce then
			modal.LocalPosition = p - { 0, 100, 0 }
			modal.updatedPosition = true
			ease:outElastic(modal, 0.3).LocalPosition = p
		else
			modal.LocalPosition = p
		end
	end

	local node = uikit:createFrame(Color(0, 0, 0, 0))
	content.node = node

	local popup = modal:create(content, maxWidth, maxHeight, position)

	local label = uikit:createText(prompt, Color.White)
	label:setParent(node)
	node.label = label

	local input = uikit:createTextInput("", "???")
	input:setParent(node)
	node.input = input

	-- buttons are displayed in that order:		-- NEUTRAL, NEGATIVE, POSITIVE
	-- POSITIVE one is displayed by default but can be hidden setting callback to nil

	node.positiveCallback = nil
	node.negativeCallback = nil
	node.neutralCallback = nil

	node.okButton = nil
	node.negativeButton = nil
	node.neutralButton = nil

	node._width = function(self)
		local buttonsWidth = 0
		if self.okButton then
			buttonsWidth = self.okButton.Width
		end
		if self.negativeButton then
			if buttonsWidth > 0 then
				buttonsWidth = buttonsWidth + theme.padding
			end
			buttonsWidth = buttonsWidth + self.negativeButton.Width
		end
		if self.neutralButton then
			if buttonsWidth > 0 then
				buttonsWidth = buttonsWidth + theme.padding
			end
			buttonsWidth = buttonsWidth + self.neutralButton.Width
		end

		local width = theme.padding

		if buttonsWidth > self.label.Width + theme.padding * 2 then
			width = width + buttonsWidth
		else
			width = width + self.label.Width + theme.padding * 2
		end

		return width
	end

	node._height = function(self)
		if self.okButton ~= nil then
			return self.label.Height + self.input.Height + theme.padding * 3 + self.okButton.Height + theme.paddingBig
		elseif self.negativeButton then
			return self.label.Height
				+ self.input.Height
				+ theme.padding * 3
				+ self.negativeButton.Height
				+ theme.paddingBig
		elseif self.neutralButton then
			return self.label.Height
				+ self.input.Height
				+ theme.padding * 3
				+ self.neutralButton.Height
				+ theme.paddingBig
		else
			return self.label.Height + self.input.Height + theme.padding * 3
		end
	end

	node.refresh = function(self)
		self.label.object.MaxWidth = math.min(300, Screen.Width * 0.8)
		self.input.Width = self.Width

		self.label.pos =
			{ self.Width * 0.5 - self.label.Width * 0.5, self.Height - self.label.Height - theme.padding, 0 }
		self.input.pos = { 0, self.label.pos.Y - theme.padding - self.input.Height, 0 }

		local buttons = {}
		if self.neutralButton then
			table.insert(buttons, self.neutralButton)
		end
		if self.negativeButton then
			table.insert(buttons, self.negativeButton)
		end
		if self.okButton then
			table.insert(buttons, self.okButton)
		end

		local buttonsWidth = 0
		for i, button in ipairs(buttons) do
			if i > 1 then
				buttonsWidth = buttonsWidth + theme.padding
			end
			buttonsWidth = buttonsWidth + button.Width
		end

		local previous
		for _, button in ipairs(buttons) do
			if previous then
				button.LocalPosition.X = previous.LocalPosition.X + previous.Width + theme.padding
			else
				button.LocalPosition.X = self.Width * 0.5 - buttonsWidth * 0.5
			end
			button.LocalPosition.Y = theme.padding
			previous = button
		end
	end

	--- Sets label and callback for positive action.
	--- Passing nil callback removes the button.
	popup.setPositiveCallback = function(self, text, callback)
		node.positiveCallback = callback

		if callback == nil then
			if node.okButton ~= nil then
				node.okButton:remove()
				node.okButton = nil
			end
		else
			if node.okButton then
				node.okButton.Text = text
			else
				local okButton = uikit:button({ content=text })
				okButton:setColor(Color(161, 217, 0), Color(45, 57, 17), false)
				okButton:setParent(node)
				okButton.onRelease = function(_)
					node.positiveCallback(node.input.Text)
					popup:close()
				end
				node.okButton = okButton
			end

			node.okButton.Width = nil
			if node.okButton.Width < minButtonWidth then
				node.okButton.Width = minButtonWidth
			end
		end
		self:refresh()
	end

	--- Sets label and callback for negative action.
	--- Passing nil callback removes the button.
	popup.setNegativeCallback = function(self, text, callback)
		node.negativeCallback = callback

		if callback == nil then
			if node.negativeButton ~= nil then
				node.negativeButton:remove()
				node.negativeButton = nil
			end
		else
			if node.negativeButton then
				node.negativeButton.Text = text
			else
				local negativeButton = uikit:button({ content=text })
				negativeButton:setColor(Color(227, 52, 55), Color.White, false)
				negativeButton:setParent(node)
				negativeButton.onRelease = function(_)
					node.negativeCallback()
					popup:close()
				end
				node.negativeButton = negativeButton
			end

			node.negativeButton.Width = nil
			if node.negativeButton.Width < minButtonWidth then
				node.negativeButton.Width = minButtonWidth
			end
		end

		self:refresh()
	end

	--- Sets label and callback for neutral action.
	--- Passing nil callback removes the button.
	popup.setNeutralCallback = function(self, text, callback)
		node.neutralCallback = callback

		if callback == nil then
			if node.neutralButton ~= nil then
				node.neutralButton:remove()
				node.neutralButton = nil
			end
		else
			if node.neutralButton then
				node.neutralButton.Text = text
			else
				local neutralButton = uikit:button({ content=text })
				neutralButton:setParent(node)
				neutralButton.onRelease = function(_)
					node.neutralCallback()
					popup:close()
				end
				node.neutralButton = neutralButton
			end

			node.neutralButton.Width = nil
			if node.neutralButton.Width < minButtonWidth then
				node.neutralButton.Width = minButtonWidth
			end
		end

		self:refresh()
	end

	popup:setPositiveCallback("OK", function() end)

	popup.bounce = function(_)
		position(popup, true)
	end

	return popup
end

return inputModal
