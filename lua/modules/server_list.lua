-- server list is a modal content

serverList = {}

serverList.create = function(_, config)
	if config ~= nil and type(config) ~= "table" then
		error("server_list:create(config): config should be a table", 2)
	end

	local theme = require("uitheme").current
	local modal = require("modal")
	local api = require("api")

	local _config = {
		title = "",
		worldID = "",
		uikit = require("uikit"),
	}

	if config then
		for k, v in pairs(_config) do
			if type(config[k]) == type(v) then
				_config[k] = config[k]
			end
		end
	end

	config = _config

	local ui = config.uikit

	local joinAndHideUI = function(worldID, address)
		-- joinWorld is exposed by the engine when in main menu
		System.JoinWorld(worldID, address)
	end

	local idealReducedContentSize = function(content, width, height)
		width = math.min(width, 500)
		height = math.min(height, 500)

		local cellHeight, maxLines = content.getCellHeightAndMaxLines(height)
		return Number2(width, (cellHeight + theme.padding) * maxLines - theme.padding)
	end

	local content = modal:createContent()

	local node = ui:createFrame(Color(0, 0, 0, 0))

	local noServerText = ui:createText("No server", Color.White)
	noServerText:setParent(node)
	noServerText:hide()

	local noServerBtn = ui:buttonPositive({ content = "Create one" })
	noServerBtn:setParent(node)
	noServerBtn:hide()

	local loadingCube = ui:createFrame(Color.White)
	loadingCube:setParent(node)
	loadingCube.Width = 10
	loadingCube.Height = 10
	loadingCube:hide()

	noServerBtn.onRelease = function(_)
		joinAndHideUI(config.worldID)
	end

	local pages = require("pages"):create()
	pages:setPageDidChange(function(page)
		node:refreshList((page - 1) * node.displayedCells + 1)
	end)

	content.bottomLeft = { pages }

	content.node = node
	content.idealReducedContentSize = idealReducedContentSize

	node.displayedCells = 0

	-- Data
	local data = {}
	data.worldID = config.worldID
	data.servers = {} -- servers collection
	data.request = nil

	data.updateServers = function(self)
		if data.request ~= nil then
			data.request:Cancel()
			data.request = nil
		end

		node:flushLines()
		data.servers = {}

		noServerBtn:hide()
		noServerText:hide()

		loadingCube:show()
		loadingCube.t = 0
		loadingCube.object.Tick = function(o, dt)
			if not loadingCube.pos then
				o.Tick = nil
				return
			end
			loadingCube.t = loadingCube.t + dt * 4
			loadingCube.pos =
				{ node.Width * 0.5 + math.cos(loadingCube.t) * 20, node.Height * 0.5 - math.sin(loadingCube.t) * 20, 0 }
		end

		data.request = api:getServers(self.worldID, function(err, servers)
			loadingCube:hide()
			loadingCube.object.Tick = nil

			if err or node.refreshList == nil then
				return
			end
			self.servers = servers

			if #servers > 0 then
				node:refreshList()
			else
				noServerText:show()
				noServerBtn:show()
			end
		end)
	end

	-- Lines
	node.lines = {}
	node.flushLines = function(_)
		for _, v in ipairs(node.lines) do
			v:remove()
		end
		node.lines = {}
	end

	-- Refresh list UI

	node.getCellHeightAndMaxLines = function(height)
		local t = ui:createText("A")
		local b = ui:button({ content="💬" })
		local cellHeight = math.max(t.Height, b.Height) + theme.padding * 3
		b:remove()
		t:remove()

		local h = cellHeight + theme.padding
		local maxLines = math.floor(height / h)

		if (maxLines + 1) * (cellHeight + theme.padding) - theme.padding <= height then
			maxLines = maxLines + 1
		end

		return cellHeight, maxLines
	end

	node.flushContentGetCellHeightAndMaxLines = function(self)
		self:flushLines()
		local top = self.Height
		return self.getCellHeightAndMaxLines(top)
	end

	-- returns cell
	node.createCell = function(self, cellHeight, server)
		if server.players == nil or server["max-players"] == nil or server["dev-mode"] == nil then
			return
		end

		local cell = ui:createFrame(Color(255, 255, 255, 200))
		cell.Height = cellHeight
		cell:setParent(self)
		table.insert(self.lines, cell)
		cell.Width = self.Width

		local vPos = cell.Height * 0.5

		local str = math.floor(math.floor(server.players))
			.. "/"
			.. math.floor(math.floor(server["max-players"]))
			.. " "
		if type(server.address) == "string" then
			if string.find(server.address, "us") ~= nil then
				str = str .. "🇺" -- USA
			elseif string.find(server.address, "sg") ~= nil then
				str = str .. "🇸" -- Singapore
			else
				str = str .. "🇪" -- default to Europe
			end
		end

		if server["dev-mode"] then
			str = str .. " - DEV 🏗"
		end

		local cellText = ui:createText(str, Color(20, 20, 20))
		cellText:setParent(cell)
		cellText.pos.X = theme.padding * 2
		cellText.pos.Y = vPos - cellText.Height * 0.5

		local btn = ui:button({ content="Join" })
		btn:setColor(theme.colorPositive, Color.White)
		btn:setParent(cell)
		btn.pos.Y = vPos - btn.Height * 0.5
		btn.pos.X = cell.Width - btn.Width - theme.padding * 2

		btn.worldID = data.worldID
		btn.address = server.address
		btn.onRelease = function(b)
			joinAndHideUI(b.worldID, b.address)
		end

		return cell
	end

	node.refreshList = function(self, from)
		local list = data.servers
		if list == nil then
			return
		end

		local top = self.Height

		local cellHeight, maxLines = self:flushContentGetCellHeightAndMaxLines()
		if maxLines <= 0 then
			return
		end

		self.displayedCells = maxLines -- update number of displayed cells

		local total = #list
		from = from or 1

		if maxLines > 1 and (from % maxLines ~= 1 or from > total) then
			-- go back to first page
			from = 1
		end

		local page = math.floor(from / maxLines) + 1
		local totalPages = math.floor(total / maxLines) + 1
		pages:setNbPages(totalPages)
		pages:setPage(page)

		local server, cell
		local line = 0
		for i = from, total do
			line = line + 1
			if line > maxLines then
				break
			end
			local p = i - from
			server = list[i]

			cell = self:createCell(cellHeight, server)

			if cell ~= nil and cell.Height ~= nil then
				cell.pos.Y = top - (p + 1) * cell.Height - p * theme.padding
			end
		end
	end

	node.parentDidResize = function(self)
		node:refreshList()
		noServerText.pos.X = (self.Width - noServerText.Width) * 0.5
		noServerText.pos.Y = self.Height * 0.5 + theme.padding * 0.5

		noServerBtn.pos.X = (self.Width - noServerBtn.Width) * 0.5
		noServerBtn.pos.Y = self.Height * 0.5 - noServerBtn.Height - theme.padding * 0.5

		loadingCube.pos = { self.Width * 0.5, self.Height * 0.5, 0 }
	end

	local titleStr = config.title .. "'s servers"
	local titleText = ui:createText(titleStr, Color.White)

	local refreshBtn = ui:buttonNeutral({ content = "🔁 Refresh" })
	refreshBtn.onRelease = function(_)
		data:updateServers()
	end

	content.topCenter = { titleText }
	content.bottomCenter = { refreshBtn }

	data:updateServers()

	return content
end

return serverList
