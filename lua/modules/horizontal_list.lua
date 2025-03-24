local horizontalListModule = {}
local horizontalListModuleMetatable = {
	__index = {
		create = function(_, data, config)
			config = config or {}
			local ui = require("uikit")
			local theme = require("uitheme").current
			local padding = config.padding or theme.padding
			local bgNode = ui:createFrame()
			bgNode:setParent(nil)

			local list = {}
			for _, v in ipairs(data) do
				local onRelease = v.onRelease or config.onRelease
				if onRelease then
					local text = (v.text or config.text) or ""
					local node = ui:button({ content=text })
					node:setParent(bgNode)
					node.t = "button"
					local color = v.color or config.color -- can be nil
					local textColor = (v.textColor or config.textColor) or Color.White
					if color then
						node:setColor(color, textColor)
					end
					node.onRelease = onRelease
					local tab = v.tab
					if tab then
						node.tab = tab
						local parent = (v.tabParent or config.tabParent) or ui.rootFrame
						node.tabParent = parent
					end
					table.insert(list, node)
				end
			end

			bgNode._width = function()
				local width = 0
				for _, v in ipairs(list) do
					width = width + v.Width + (width > 0 and padding or 0)
				end
				return width
			end

			bgNode._height = function()
				local height = 0
				for _, v in ipairs(list) do
					if v.Height > height then
						height = v.Height
					end
				end
				return height
			end

			bgNode.parentDidResize = function()
				local nextPos = Number3(0, 0, 0)

				for _, v in ipairs(list) do
					if v.content and v.content.text == "" then -- if not text, square button
						v.Width = v.Height
					end
					v.LocalPosition = nextPos
					nextPos = v.LocalPosition + Number3(v.Width + padding, 0, 0)
				end
			end
			return bgNode, list
		end,
	},
}
setmetatable(horizontalListModule, horizontalListModuleMetatable)

return horizontalListModule
