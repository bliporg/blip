--[[
	pages = require("pages")
	local p = pages:create()
	p:setNbPages(10)
	p:setPage(2)
	p:setPageDidChange(function(page) print(page) end)
--]]

local pages = {}

pages.create = function(_, uikit)
	local theme = require("uitheme").current
	local ui = uikit or require("uikit")

	local node = ui:createNode()
	node.nbPages = 1
	node.page = 1
	node.pageDidChange = nil

	local nextBtn = ui:button({ content="➡️" })
	nextBtn:setParent(node)

	local prevBtn = ui:button({ content="⬅️" })
	prevBtn:setParent(node)

	local label = ui:createText("1/1", theme.textColor)
	label:setParent(node)

	node._width = function()
		return prevBtn.Width + theme.padding + label.Width + theme.padding + nextBtn.Width
	end

	node._height = function()
		return math.max(prevBtn.Height, label.Height)
	end

	node._refresh = function(self)
		label.Text = string.format("%d/%d", self.page, self.nbPages)

		local backup = self.contentDidResize
		self.contentDidResize = nil

		prevBtn.Text = "⬅️"
		prevBtn.Width = nil
		local w = prevBtn.Width

		if self.page > 1 then
			prevBtn:enable()
		else
			prevBtn.Text = ""
			prevBtn.Width = w
			prevBtn:disable()
		end

		nextBtn.Text = "➡️"
		nextBtn.Width = nil
		w = nextBtn.Width

		if self.page < self.nbPages then
			nextBtn:enable()
		else
			nextBtn.Text = ""
			nextBtn.Width = w
			nextBtn:disable()
		end

		self.contentDidResize = backup

		local h = self.Height
		prevBtn.pos = { 0, h * 0.5 - prevBtn.Height * 0.5, 0 }
		label.pos = { prevBtn.pos.X + prevBtn.Width + theme.padding, h * 0.5 - label.Height * 0.5, 0 }
		nextBtn.pos = { label.pos.X + label.Width + theme.padding, h * 0.5 - nextBtn.Height * 0.5, 0 }
	end

	node.contentDidResize = function(self)
		self:_refresh()
	end

	node.setNbPages = function(self, n)
		self.nbPages = n
		if self.nbPages < 1 then
			self.nbPages = 1
		end
		self:_refresh()
	end

	node.setPage = function(self, n)
		self.page = n
		if self.page < 1 then
			self.page = 1
		end
		self:_refresh()
	end

	node.setPageDidChange = function(self, callback)
		self.pageDidChange = callback
	end

	node._triggerPageDidChangeCallback = function(self)
		if self.pageDidChange then
			self.pageDidChange(self.page)
		end
	end

	nextBtn.onRelease = function(_)
		node.page = node.page + 1
		if node.page > node.nbPages then
			node.page = node.nbPages
		else
			node:_triggerPageDidChangeCallback()
		end
		node:_refresh()
	end

	prevBtn.onRelease = function(_)
		node.page = node.page - 1
		if node.page < 1 then
			node.page = 1
		else
			node:_triggerPageDidChangeCallback()
		end
		node:_refresh()
	end

	node:_refresh()
	return node
end

return pages
