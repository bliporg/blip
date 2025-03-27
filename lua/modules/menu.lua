if IsServer == true then
	return require("empty_table"):create("menu is not supposed to be used by Server")
end

local menu = {}

bundle = require("bundle")
loc = require("localize")
-- str = require("str")
ui = require("uikit").systemUI(System)
modal = require("modal")
theme = require("uitheme").current
ease = require("ease")
friends = require("friends")
settings = require("settings")
api = require("api")
systemApi = require("system_api", System)
alert = require("alert")
codes = require("inputcodes")
sfx = require("sfx")
logo = require("logo")
uiPointer = require("ui_pointer")
signup = require("signup")

-- CONSTANTS

MODAL_MARGIN = theme.paddingBig -- space around modals
BACKGROUND_COLOR_ON = Color(0, 0, 0, 200)
BACKGROUND_COLOR_OFF = Color(0, 0, 0, 0)
ALERT_BACKGROUND_COLOR_ON = Color(0, 0, 0, 200)
ALERT_BACKGROUND_COLOR_OFF = Color(0, 0, 0, 0)
CHAT_SCREEN_WIDTH_RATIO = 0.4
CHAT_MAX_WIDTH = 600
CHAT_MIN_WIDTH = 200
CHAT_SCREEN_HEIGHT_RATIO = 0.33
CHAT_MIN_HEIGHT = 160
CHAT_MAX_HEIGHT = 500
CONNECTION_RETRY_DELAY = 5.0 -- in seconds
PADDING = theme.padding
PADDING_BIG = 9
TOP_BAR_HEIGHT = 40

CUBZH_MENU_MAIN_BUTTON_HEIGHT = 60
CUBZH_MENU_SECONDARY_BUTTON_HEIGHT = 40

DEV_MODE = System.LocalUserIsAuthor and System.ServerIsInDevMode
IN_WORLD_EDITOR = Environment["worldId"] == "world_editor"
AI_ASSISTANT_ENABLED = true -- feature is not ready yet

-- VARS

minified = not System.IsHomeAppRunning
wasActive = nil
modalWasShown = false
alertWasShown = false
cppMenuIsActive = false
chatDisplayed = false -- when false, only a mini chat console is displayed in the top bar
_DEBUG = false
_DebugColor = function()
	return Color(math.random(150, 255), math.random(150, 255), math.random(150, 255))
end
pointer = nil

-- MODALS

activeFlow = nil
activeModal = nil
activeModalKey = nil

didBecomeActiveCallbacks = {}
didResignActiveCallbacks = {}

MODAL_KEYS = {
	PROFILE = 1,
	CHAT = 2,
	FRIENDS = 3,
	SETTINGS = 4,
	COINS = 5,
	WORLDS = 6,
	ITEMS = 7,
	BUILD = 8,
	MARKETPLACE = 9,
	CUBZH_MENU = 10,
	OUTFITS = 11,
	WORLD = 12,
	ITEM = 13,
	CREATIONS = 14,
	USERNAME_FORM = 15,
	VERIFY_ACCOUNT_FORM = 16,
	NOTIFICATIONS = 17,
}

-- User account management

function connect()
	if Players.Max <= 1 then
		return -- no need to connect when max players not > 1
	end
	if Client.Connected then
		return -- already connected
	end
	if connectionIndicator:isVisible() then
		return -- already trying to connect
	end

	if connectionRetryTimer ~= nil then
		connectionRetryTimer:Cancel()
		connectionRetryTimer = nil
	end

	connBtn:show()
	connectionIndicator:show()
	noConnectionIndicator:hide()

	connectionIndicatorStartAnimation()

	System:ConnectToServer()
end

function startConnectTimer()
	if connectionRetryTimer ~= nil then
		connectionRetryTimer:Cancel()
	end
	connectionRetryTimer = Timer(CONNECTION_RETRY_DELAY, function()
		connect()
	end)

	connShape.Tick = nil
	connectionIndicator:hide()
	noConnectionIndicator:show()
end

function maxModalWidth()
	local computed = Screen.Width - Screen.SafeArea.Left - Screen.SafeArea.Right - MODAL_MARGIN * 2
	local max = 400
	local w = math.min(max, computed)
	return w
end

function maxModalHeight()
	local availableHeight = topBar.Position.Y - Screen.SafeArea.Bottom
	local minusFixedMargin = availableHeight - MODAL_MARGIN * 2
	local percentage = availableHeight * 0.9
	local max = 700
	return math.min(max, percentage, minusFixedMargin)
end

function updateModalPosition(modal)
	local vMin = Screen.SafeArea.Bottom + MODAL_MARGIN
	local vMax = topBar.Position.Y - MODAL_MARGIN
	local vCenter = vMin + (vMax - vMin) * 0.5
	modal.pos = { Screen.Width * 0.5 - modal.Width * 0.5, vCenter - modal.Height * 0.5 }
end

function closeModal()
	if activeModal ~= nil then
		activeModal:close()
		activeModal = nil
		activeModalKey = nil
		refreshButtons()
	end
end

-- pops active modal content
-- closing modal when reaching root content
function popModal()
	if activeModal == nil then
		return
	end
	if #activeModal.contentStack > 1 then
		activeModal:pop()
	else
		closeModal()
	end
end

function showModal(key, config)
	if not key then
		return
	end

	if key == activeModalKey then
		activeModal:bounce()
		return
	end

	if activeModal ~= nil then
		if activeModal.close ~= nil then
			activeModal:close()
		else
			-- if modal is a drawer
			activeModal:remove()
		end
		activeModal = nil
		activeModalKey = nil
	end

	local content
	if key == MODAL_KEYS.PROFILE then
		local c = { uikit = ui }
		if config.editAvatar ~= nil then
			c.editAvatar = function()
				closeModal()
				config.editAvatar()
			end
		end

		if config.player ~= nil then
			c.username = config.player.Username
			c.userID = config.player.UserID
		end
		if config.id ~= nil then
			c.userID = config.id
			c.username = config.username
		end
		content = require("profile"):create(c)
		activeModal = modal:create(content, maxModalWidth, maxModalHeight, updateModalPosition, ui)
	elseif key == MODAL_KEYS.OUTFITS then
		local c = { uikit = ui, username = Player.Username }
		if config.player ~= nil then
			c.username = config.player.Username
		end
		content = require("ui_outfit"):create(c)
		activeModal = modal:create(content, maxModalWidth, maxModalHeight, updateModalPosition, ui)
	elseif key == MODAL_KEYS.CHAT then
		local inputText = ""
		if console then
			inputText = console:getText()
		end
		content = require("chat"):createModalContent({ uikit = ui, inputText = inputText })
		activeModal = modal:create(content, maxModalWidth, maxModalHeight, updateModalPosition, ui)
	elseif key == MODAL_KEYS.FRIENDS then
		activeModal = friends:create(maxModalWidth, maxModalHeight, updateModalPosition, ui)
	elseif key == MODAL_KEYS.COINS then
		content = require("coins"):createModalContent({ uikit = ui })
		activeModal = modal:create(content, maxModalWidth, maxModalHeight, updateModalPosition, ui)
	elseif key == MODAL_KEYS.NOTIFICATIONS then
		content = require("notifications"):createModalContent({ uikit = ui })
		activeModal = modal:create(content, maxModalWidth, maxModalHeight, updateModalPosition, ui)
	elseif key == MODAL_KEYS.MARKETPLACE then
		content = require("gallery"):createModalContent({ uikit = ui })
		activeModal = modal:create(content, maxModalWidth, maxModalHeight, updateModalPosition, ui)
	elseif key == MODAL_KEYS.CUBZH_MENU then
		content = getCubzhMenuModalContent()
		activeModal = modal:create(content, maxModalWidth, maxModalHeight, updateModalPosition, ui)
	elseif key == MODAL_KEYS.WORLDS then
		content = require("gallery"):createModalContent({
			uikit = ui,
			type = "worlds",
			displayLikes = true,
			categories = { "featured" },
		})
		activeModal = modal:create(content, maxModalWidth, maxModalHeight, updateModalPosition, ui)
	elseif key == MODAL_KEYS.WORLD then
		local config = config or {}
		config.uikit = ui
		content = require("world_details"):createModalContent(config)
		activeModal = modal:create(content, maxModalWidth, maxModalHeight, updateModalPosition, ui)
	elseif key == MODAL_KEYS.ITEMS then
		content = require("gallery"):createModalContent({ uikit = ui, type = "items", perPage = 100 })
		activeModal = modal:create(content, maxModalWidth, maxModalHeight, updateModalPosition, ui)
	elseif key == MODAL_KEYS.ITEM then
		local config = config or {}
		config.uikit = ui
		content = require("item_details"):createModalContent(config)
		activeModal = modal:create(content, maxModalWidth, maxModalHeight, updateModalPosition, ui)
	elseif key == MODAL_KEYS.CREATIONS then
		content = require("creations"):createModalContent({ uikit = ui })
		activeModal = modal:create(content, maxModalWidth, maxModalHeight, updateModalPosition, ui)
	elseif key == MODAL_KEYS.SETTINGS then
		content = settings:createModalContent({ clearCache = true, account = true, uikit = ui })
		activeModal = modal:create(content, maxModalWidth, maxModalHeight, updateModalPosition, ui)
	elseif key == MODAL_KEYS.USERNAME_FORM then
		local config = config or {}
		config.uikit = ui
		content = require("username_form"):createModalContent(config)
		activeModal = modal:create(content, maxModalWidth, maxModalHeight, updateModalPosition, ui)
	elseif key == MODAL_KEYS.VERIFY_ACCOUNT_FORM then
		local config = config or {}
		config.uikit = ui
		content = require("verify_account_form"):createModalContent(config)
		activeModal = modal:create(content, maxModalWidth, maxModalHeight, updateModalPosition, ui)
	end

	if activeModal ~= nil then
		menu:RemoveHighlight()

		ui.unfocus() -- unfocuses node currently focused

		if key ~= MODAL_KEYS.WORLDS then
			activeModal:setParent(background)
		end

		activeModalKey = key

		activeModal.didClose = function()
			activeModal = nil
			activeModalKey = nil
			refreshChat()
			refreshButtons()
			triggerCallbacks()
		end

		sfx("whooshes_small_1", { Volume = 0.5, Pitch = 2.0, Spatialized = false })
	end

	refreshChat()
	refreshButtons()
	triggerCallbacks()

	return modal, content
end

function showAlert(config)
	if alertModal ~= nil then
		alertModal:bounce()
		return
	end

	alertModal = alert:create(config.message or "", { uikit = ui, background = false })
	alertModal:setParent(alertBackground)

	if config.positiveCallback then
		alertModal:setPositiveCallback(config.positiveLabel or "OK", config.positiveCallback)
	end
	if config.negativeCallback then
		alertModal:setNegativeCallback(config.negativeLabel or "No", config.negativeCallback)
	end
	if config.neutralCallback then
		alertModal:setNeutralCallback(config.neutralLabel or "...", config.neutralCallback)
	end

	alertModal.didClose = function()
		alertModal = nil
		triggerCallbacks()
	end

	triggerCallbacks()
end

function showLoading(text)
	-- do not show loading while in world editor
	-- (tmp, we need to show something when publishing)
	if IN_WORLD_EDITOR then 
		return 
	end

	if loadingModal ~= nil then
		loadingModal:setText(text)
		return
	end

	loadingModal = require("loading_modal"):create(text, { uikit = ui })
	loadingModal:setParent(alertBackground)

	loadingModal.didClose = function()
		loadingModal = nil
		triggerCallbacks()
	end

	triggerCallbacks()
end

function hideLoading()
	if loadingModal == nil then
		return
	end
	loadingModal:close()
	loadingModal = nil
	triggerCallbacks()
end

blockedEvents = {}

function blockEvent(name)
	local listener = LocalEvent:Listen(name, function()
		return true
	end, { topPriority = true, system = System })
	table.insert(blockedEvents, listener)
end

function blockEvents()
	blockEvent(LocalEvent.Name.DirPad)
	blockEvent(LocalEvent.Name.AnalogPad)
end

function unblockEvents()
	for _, listener in ipairs(blockedEvents) do
		listener:Remove()
	end
	blockedEvents = {}
end

function triggerCallbacks()
	local isActive = menu:IsActive()

	if isActive ~= wasActive then
		wasActive = isActive
		if isActive then
			for _, callback in pairs(didBecomeActiveCallbacks) do
				callback()
			end
		else
			for _, callback in pairs(didResignActiveCallbacks) do
				callback()
			end
		end

		if isActive then
			blockEvents()
			System.PointerForceShown = true
			removeBadge()
		else
			unblockEvents()
			System.PointerForceShown = false
		end
	end

	local modalIsShown = activeModal ~= nil and not cppMenuIsActive

	if modalIsShown ~= modalWasShown then
		modalWasShown = modalIsShown
		ease:cancel(background)
		if modalIsShown then
			background.onPress = function() end -- blocker
			background.onRelease = function() end -- blocker
			ease:linear(background, 0.22).Color = BACKGROUND_COLOR_ON
		else
			background.onPress = nil
			background.onRelease = nil
			ease:linear(background, 0.22).Color = BACKGROUND_COLOR_OFF
		end
	end

	local alertIsSHown = (alertModal ~= nil or loadingModal ~= nil) and not cppMenuIsActive

	if alertIsSHown ~= alertWasShown then
		alertWasShown = alertIsSHown
		ease:cancel(alertBackground)
		if alertIsSHown then
			alertBackground.onPress = function() end -- blocker
			alertBackground.onRelease = function() end -- blocker
			ease:linear(alertBackground, 0.22).Color = ALERT_BACKGROUND_COLOR_ON
		else
			alertBackground.onPress = nil
			alertBackground.onRelease = nil
			ease:linear(alertBackground, 0.22).Color = ALERT_BACKGROUND_COLOR_OFF
		end
	end
end

function refreshDisplay()
	if cppMenuIsActive then
		hideTopBar()

		if activeModal then
			activeModal:hide()
		end
		if loadingModal then
			loadingModal:hide()
		end
		if alertModal then
			alertModal:hide()
		end
	else
		showTopBar()
		
		if activeModal then
			activeModal:show()
		end
		if loadingModal then
			loadingModal:show()
		end
		if alertModal then
			alertModal:show()
		end

		if System.IsChatEnabled then
			chatBtn:show()
		else
			chatBtn:hide()
		end

		if not minified then
			pezhBtn:show()
		end
	end
end

function refreshButtons()
	if activeModalKey == nil then
		if chat ~= nil then
			chatIcon:hide()
			chatIconSelected:show()
		else
			chatIcon:show()
			chatIconSelected:hide()
		end
	else
		if activeModalKey == MODAL_KEYS.CHAT then
			chatIcon:hide()
			chatIconSelected:show()
		else
			chatIcon:show()
			chatIconSelected:hide()
		end
	end

	if activeModalKey == MODAL_KEYS.NOTIFICATIONS then
		notificationsIcon:hide()
		notificationsIconSelected:show()
	else
		notificationsIcon:show()
		notificationsIconSelected:hide()
	end

	if activeModalKey == MODAL_KEYS.SETTINGS then
		if cubzhBtn.iconSelected then
			cubzhBtn.icon:hide()
			cubzhBtn.iconSelected:show()
		end
	else
		if cubzhBtn.iconSelected then
			cubzhBtn.icon:show()
			cubzhBtn.iconSelected:hide()
		end
	end

	if activeModalKey == MODAL_KEYS.CUBZH_MENU then
		-- TODO
	end
end

-- BACKGROUND

background = ui:createFrame(BACKGROUND_COLOR_OFF)

background.parentDidResize = function(_)
	background.Width = Screen.Width
	background.Height = Screen.Height
end
background:parentDidResize()

-- turn ON alpha-blending for the transparent background, to blend correctly w/ texts under it
alertBackground = ui:frame({ color = { ALERT_BACKGROUND_COLOR_OFF, alpha = true } })
alertBackground.pos.Z = ui.kAlertDepth

alertBackground.parentDidResize = function(_)
	alertBackground.Width = Screen.Width
	alertBackground.Height = Screen.Height
end
alertBackground:parentDidResize()

-- ACTION COLUMN

actionColumn = ui:createFrame(Color.transparent)
actionColumn:setParent(background)
actionColumn:hide()

-- SETTINGS BTN

settingsBtn = ui:createFrame(_DEBUG and _DebugColor() or Color.transparent)
settingsBtn:setParent(actionColumn)

settingsBtn.onRelease = function()
	if activeModal ~= nil then
		activeModal:push(settings:createModalContent({ clearCache = true, account = true, uikit = ui }))
	end
end

local tmp = ui:createText("⚙️", Color.White, "big")
local size = math.max(tmp.Width, tmp.Height)
tmp:remove()

local settingsIcon = ui:frame({ image = {
	data = Data:FromBundle("images/icon-settings.png"),
	alpha = true,
} })
settingsIcon.Width = size
settingsIcon.Height = size
settingsIcon:setParent(settingsBtn)
-- settingsIcon.parentDidResize = btnContentParentDidResize
-- cubzhBtn.icon = settingsIcon

-- settingsIcon = ui:createText("⚙️", Color.White, "big")
settingsIcon:setParent(settingsBtn)

settingsBtn.getMinSize = function(_)
	return Number2(settingsIcon.Width, settingsIcon.Height)
end

settingsIcon.parentDidResize = function(_)
	local parent = settingsIcon.parent
	settingsIcon.pos =
		{ parent.Width * 0.5 - settingsIcon.Width * 0.5, parent.Height * 0.5 - settingsIcon.Height * 0.5 }
end

-- SHARE BTN

shareBtn = ui:createFrame(_DEBUG and _DebugColor() or Color.transparent)
shareBtn:setParent(actionColumn)

shareBtn.onRelease = function()
	Dev:CopyToClipboard(Dev.ServerURL)

	if shareBtnConfirmation ~= nil then
		if shareBtnConfirmationTimer ~= nil then
			shareBtnConfirmationTimer:Cancel()
			shareBtnConfirmationTimer = nil
		end
		ease:cancel(shareBtnConfirmation.pos)
		shareBtnConfirmation:remove()
	end

	shareBtnConfirmation = ui:createText("📋 Link copied!", Color.White, "small")
	shareBtnConfirmation:setParent(shareBtn)

	shareBtnConfirmation.pos =
		{ -shareBtnConfirmation.Width - PADDING, shareBtn.Height * 0.5 - shareBtnConfirmation.Height * 0.5 }

	local backup = shareBtnConfirmation.pos.X
	shareBtnConfirmation.pos.X = backup + 50
	ease:outBack(shareBtnConfirmation.pos, 0.22 * 1.2).X = backup

	shareBtnConfirmationTimer = Timer(1.5, function()
		shareBtnConfirmation:remove()
		shareBtnConfirmation = nil
		shareBtnConfirmationTimer = nil
	end)
end

shareLabel = ui:createText("Share", Color.White, "small")
shareLabel:setParent(shareBtn)

shareIcon = ui:createText("↗", Color.White, "big")
shareIcon:setParent(shareBtn)

shareBtn.getMinSize = function(_)
	return Number2(math.max(shareLabel.Width, shareIcon.Width), shareLabel.Height + shareIcon.Height)
end

shareLabel.parentDidResize = function(_)
	local parent = shareLabel.parent
	local contentHeight = shareLabel.Height + shareIcon.Height
	shareLabel.pos = { parent.Width * 0.5 - shareLabel.Width * 0.5, parent.Height * 0.5 - contentHeight * 0.5 }
	shareIcon.pos = {
		parent.Width * 0.5 - shareIcon.Width * 0.5,
		parent.Height * 0.5 + contentHeight * 0.5 - shareIcon.Height,
	}
end

-- LIKE BTN

nbLikes = nil
liked = false

likeBtn = ui:createFrame(_DEBUG and _DebugColor() or Color.transparent)
likeBtn:setParent(actionColumn)
likeWorldReq = nil

likeBtn.onRelease = function()
	if Environment.worldId == nil then
		return
	end
	liked = not liked

	if nbLikes == nil then
		nbLikes = liked and 1 or nil
	else
		if liked then
			nbLikes = nbLikes + 1
		else
			nbLikes = nbLikes - 1
		end
	end

	actionColumnUpdateContent()

	if likeWorldReq ~= nil then
		likeWorldReq:Cancel()
	end
	if getWorldInfoReq ~= nil then
		getWorldInfoReq:Cancel()
		getWorldInfoReq = nil
	end

	likeWorldReq = systemApi:likeWorld(Environment.worldId, liked, function(_)
		likeWorldReq = nil
		getWorldInfo()
	end)
end

likeLabel = ui:createText(nbLikes ~= nil and string.format("%d", nbLikes) or "…", Color.White, "small")
likeLabel:setParent(likeBtn)

likeIcon = ui:createText("🤍", Color.White, "big")
likeIcon:setParent(likeBtn)

likeBtn.getMinSize = function(_)
	return Number2(math.max(likeLabel.Width, likeIcon.Width), likeLabel.Height + likeIcon.Height)
end

likeLabel.parentDidResize = function(_)
	local parent = likeLabel.parent
	local contentHeight = likeLabel.Height + likeIcon.Height
	likeLabel.pos = { parent.Width * 0.5 - likeLabel.Width * 0.5, parent.Height * 0.5 - contentHeight * 0.5 }
	likeIcon.pos = {
		parent.Width * 0.5 - likeIcon.Width * 0.5,
		parent.Height * 0.5 + contentHeight * 0.5 - likeIcon.Height,
	}
end

-- COMMENTS BTN

commentsBtn = ui:createFrame(_DEBUG and _DebugColor() or Color.transparent)
commentsBtn:setParent(actionColumn)

commentsBtn.onRelease = function()
	showAlert({ message = "Coming soon!" })
end

-- commentsLabel = ui:createText("3", Color.White, "small")
-- commentsLabel:setParent(commentsBtn)

commentsIcon = ui:createText("💬", Color.White, "big")
commentsIcon:setParent(commentsBtn)

commentsBtn.getMinSize = function(_)
	-- return Number2(math.max(commentsLabel.Width, commentsIcon.Width), commentsLabel.Height + commentsIcon.Height)
	return Number2(commentsIcon.Width, commentsIcon.Height)
end

commentsIcon.parentDidResize = function(_)
	local parent = commentsIcon.parent
	commentsIcon.pos = {
		parent.Width * 0.5 - commentsIcon.Width * 0.5,
		parent.Height * 0.5 - commentsIcon.Height * 0.5,
	}
end

-- ACTION COLUMN LAYOUT

function actionColumnUpdateContent()
	likeLabel.Text = nbLikes ~= nil and string.format("%d", nbLikes) or "…"
	if liked then
		likeIcon.Text = "❤️"
	else
		likeIcon.Text = "🤍"
	end
	likeLabel:parentDidResize()
end

function showActionColumn()
	if actionColumn:isVisible() then
		return
	end

	actionColumn:parentDidResize() -- force layout

	local backup = likeBtn.pos.Y
	likeBtn.pos.Y = likeBtn.pos.Y - 100 * 1.2
	ease:outBack(likeBtn.pos, 0.22 * 1.2).Y = backup

	backup = commentsBtn.pos.Y
	commentsBtn.pos.Y = commentsBtn.pos.Y - 100 * 1.1
	ease:outBack(commentsBtn.pos, 0.22 * 1.1).Y = backup

	backup = shareBtn.pos.Y
	shareBtn.pos.Y = shareBtn.pos.Y - 100
	ease:outBack(shareBtn.pos, 0.22).Y = backup

	backup = settingsBtn.pos.Y
	settingsBtn.pos.Y = settingsBtn.pos.Y + 100
	ease:outBack(settingsBtn.pos, 0.22).Y = backup

	actionColumn:show()
end

-- function hideActionColumn() end

actionColumn.parentDidResize = function(_)
	ease:cancel(settingsBtn.pos)
	ease:cancel(likeBtn.pos)
	ease:cancel(commentsBtn.pos)
	ease:cancel(shareBtn.pos)

	local height = Screen.Height - Screen.SafeArea.Top

	local settingsBtnMinSize = settingsBtn:getMinSize()
	local shareBtnMinSize = shareBtn:getMinSize()
	local likeBtnMinSize = likeBtn:getMinSize()
	local commentsBtnMinSize = commentsBtn:getMinSize()

	local contentWidth = math.max(
		shareBtnMinSize.Width,
		likeBtnMinSize.Width,
		commentsBtnMinSize.Width,
		settingsBtnMinSize.Width
	) + PADDING * 2
	local width = contentWidth + Screen.SafeArea.Right

	actionColumn.Height = height
	actionColumn.Width = width

	actionColumn.pos.X = Screen.Width - actionColumn.Width

	settingsBtn.Width = contentWidth
	settingsBtn.Height = settingsBtnMinSize.Height + PADDING_BIG * 2
	settingsBtn.pos = { 0, actionColumn.Height - settingsBtn.Height }

	shareBtn.Width = contentWidth
	shareBtn.Height = shareBtnMinSize.Height + PADDING_BIG * 2
	shareBtn.pos = { 0, Screen.SafeArea.Bottom + PADDING }

	commentsBtn.Width = contentWidth
	commentsBtn.Height = commentsBtnMinSize.Height + PADDING_BIG * 2
	commentsBtn.pos = { 0, shareBtn.pos.Y + shareBtn.Height }

	likeBtn.Width = contentWidth
	likeBtn.Height = likeBtnMinSize.Height + PADDING_BIG * 2
	likeBtn.pos = { 0, commentsBtn.pos.Y + commentsBtn.Height }
end
actionColumn:parentDidResize()

-- NOTIFICATION
-- only one object, recycled

local notificationIconSize = 25
local notificationIconPadding = theme.paddingBig
local notificationPadding = theme.padding
local notificationBottomPadding = 2
local noticationTimer
local notificationTick

notificationFrame = ui:frameNotification()
notificationFrame.Width = 200
notificationFrame.Height = 100

local notificationText = ui:createText("text", { size = "small", color = Color.White })
notificationText.object.MaxWidth = 300
notificationText:setParent(notificationFrame)

local notificationIcon

local previousCategory
local notificationIconGeneric
local notificationIconMoney
local notificationIconLike
local notificationIconSocial
local function refreshNotificationIcon(category)
	category = category or "generic"
	if category == previousCategory then
		return
	end
	previousCategory = category
	if notificationIcon ~= nil then
		notificationIcon:setParent(nil)
	end
	if category == "money" then
		if notificationIconMoney == nil then
			notificationIconMoney =
				ui:createShape(bundle:Shape("shapes/pezh_coin_2"), { spherized = false, doNotFlip = true })
		end
		notificationIcon = notificationIconMoney
	elseif category == "like" then
		if notificationIconLike == nil then
			notificationIconLike = ui:createShape(bundle:Shape("shapes/heart"), { spherized = false, doNotFlip = true })
		end
		notificationIcon = notificationIconLike
	elseif category == "social" then
		if notificationIconSocial == nil then
			notificationIconSocial =
				ui:createShape(bundle:Shape("shapes/friends_icon"), { spherized = false, doNotFlip = true })
		end
		notificationIcon = notificationIconSocial
	else
		if notificationIconGeneric == nil then
			notificationIconGeneric =
				ui:createShape(bundle:Shape("shapes/alert_badge"), { spherized = false, doNotFlip = true })
		end
		notificationIcon = notificationIconGeneric
	end

	notificationIcon:setParent(nil)
	notificationIcon.Width = notificationIconSize
	notificationIcon.Height = notificationIconSize
	notificationIcon:setParent(notificationFrame)
end

function absNodePos(node)
	local p = node.pos:Copy()
	local parent = node.parent
	while parent ~= nil do
		p.X = p.X + parent.pos.X
		p.Y = p.Y + parent.pos.Y
		parent = parent.parent
	end
	return p
end

function layoutNotification()
	local parent = notificationFrame.parent
	if parent == nil then
		return
	end

	local x = topBar.Position.X

	notificationText.object.MaxWidth = math.min(Screen.Width * 0.8, 300)

	notificationFrame.Height = math.max(
		notificationIconSize + notificationPadding * 4,
		notificationText.Height + notificationPadding * 2
	) + notificationBottomPadding

	notificationFrame.Width = notificationIconSize
		+ notificationText.Width
		+ notificationIconPadding * 2
		+ notificationIconPadding

	if notificationIcon ~= nil then
		notificationIcon.pos = {
			notificationIconPadding,
			(notificationFrame.Height - notificationBottomPadding) * 0.5
				- notificationIconSize * 0.5
				+ notificationBottomPadding,
		}
	end

	local y = (notificationFrame.Height - notificationBottomPadding) * 0.5
		- notificationText.Height * 0.5
		+ notificationBottomPadding

	notificationText.pos = { notificationIconSize + notificationIconPadding * 2, y }

	notificationFrame.pos = {
		x,
		topBar.pos.Y - notificationFrame.Height - PADDING,
	}
end

function bumpNotification()
	ease:cancel(notificationFrame.pos)
	local posX = notificationFrame.pos.X
	notificationFrame.pos.X = notificationFrame.pos.X - 100
	ease:outBack(notificationFrame.pos, 0.3).X = posX
end

function hideNotification()
	notificationFrame.onRelease = nil
	noticationTimer:Cancel()
	noticationTimer = nil
	ease:linear(notificationFrame.pos, 0.2, {
		onDone = function()
			notificationFrame:setParent(nil)
			notificationTick:Remove()
			notificationTick = nil
		end,
	}).X = -notificationFrame.Width
		
end

notificationFrame.parentDidResize = function()
	layoutNotification()
end

notificationFrame:setParent(nil)

function showNotification(_, text, category)
	if noticationTimer ~= nil then
		noticationTimer:Cancel()
		noticationTimer = nil
	end
	notificationText.Text = text

	refreshNotificationIcon(category)

	if category == "money" then
		sfx("coin_1", { Volume = 0.5, Pitch = 1.0, Spatialized = false })
	else
		sfx("buttonpositive_3", { Volume = 0.5, Pitch = 1.0, Spatialized = false })
	end

	notificationFrame.onRelease = function()
		hideNotification()
		if category == "money" then
			pezhBtn:onRelease()
		end
	end

	if notificationFrame.parent ~= background then
		notificationFrame:setParent(background)
		notificationFrame.pos.Z = -50
	else
		layoutNotification()
	end
	bumpNotification()
	noticationTimer = Timer(4.0, function()
		hideNotification()
	end)

	if notificationTick == nil then
		notificationTick = LocalEvent:Listen(LocalEvent.Name.Tick, function(dt)
			if notificationIcon ~= nil then
				notificationIcon.pivot.Rotation = notificationIcon.pivot.Rotation * Rotation(0, dt * 3.0, 0)
			end
		end)
	end
end

-- TOP BAR

topBar = ui:frame({
	image = {
		data = Data:FromBundle("images/menu-background.png"),
		slice9 = { 0.5, 0.5 },
		slice9Scale = 1.0,
		alpha = true,
	},
})

-- menu-background.png
topBar:setParent(background)
topBar:hide()

topBarBtnPress = function(self)
	self.Color = Color(0, 0, 0, 0.5)
	Client:HapticFeedback()
end

topBarBtnRelease = function(self)
	self.Color = _DEBUG and _DebugColor() or Color(0, 0, 0, 0)
end

btnContentParentDidResize = function(self)
	local padding = PADDING
	if self == pezhShape then
		padding = PADDING_BIG
	end
	local parent = self.parent
	local ratio = self.Width / self.Height
	self.Height = parent.Height - padding * 2
	self.Width = ratio * self.Height
	self.pos = { self.parent.Width * 0.5 - self.Width * 0.5, self.parent.Height * 0.5 - self.Height * 0.5 }
end

-- MAIN MENU BTN

cubzhBtn = ui:createFrame(_DEBUG and _DebugColor() or Color.transparent)
cubzhBtn:setParent(topBar)

uiBadge = require("ui_badge")

cubzhBtnBadge = nil

function showBadge(str)
	removeBadge()
	cubzhBtnBadge = uiBadge:create({ text = str, ui = ui })
	cubzhBtnBadge.internalParentDidResize = cubzhBtnBadge.parentDidResize
	cubzhBtnBadge.parentDidResize = function(self)
		self.pos.X = self.parent.Width * 0.5
		self.pos.Y = 0
		self:internalParentDidResize()
	end
	cubzhBtnBadge:setParent(cubzhBtn)
end

function removeBadge()
	if cubzhBtnBadge ~= nil then
		cubzhBtnBadge:remove()
		cubzhBtnBadge = nil
	end
end

if System.IsHomeAppRunning then
	local settingsIcon = ui:frame({ image = {
		data = Data:FromBundle("images/icon-settings.png"),
		alpha = true,
	} })
	settingsIcon.Width = 50
	settingsIcon.Height = 50
	settingsIcon:setParent(cubzhBtn)
	settingsIcon.parentDidResize = btnContentParentDidResize
	cubzhBtn.icon = settingsIcon

	local settingsIconSelected =
		ui:frame({ image = {
			data = Data:FromBundle("images/icon-settings-selected.png"),
			alpha = true,
		} })
	settingsIconSelected.Width = 50
	settingsIconSelected.Height = 50
	settingsIconSelected:setParent(cubzhBtn)
	settingsIconSelected.parentDidResize = btnContentParentDidResize
	settingsIconSelected:hide()
	cubzhBtn.iconSelected = settingsIconSelected
else
	local exitIcon = ui:frame({ image = {
		data = Data:FromBundle("images/icon-exit.png"),
		alpha = true,
	} })
	exitIcon.Width = 50
	exitIcon.Height = 50
	exitIcon:setParent(cubzhBtn)
	exitIcon.parentDidResize = btnContentParentDidResize
	cubzhBtn.icon = exitIcon
end

-- CONNECTIVITY BTN

connBtn = ui:createFrame(_DEBUG and _DebugColor() or Color.transparent)

connBtn:setParent(topBar)
connBtn:hide()

connBtn.onPress = topBarBtnPress
connBtn.onCancel = topBarBtnRelease
connBtn.onRelease = function(self)
	topBarBtnRelease(self)
	connect()
end

connShape = bundle:Shape("shapes/connection_indicator")
connectionIndicator = ui:createShape(connShape, { doNotFlip = true })
connectionIndicator:setParent(connBtn)
connectionIndicator:hide()
connectionIndicator.parentDidResize = function(self)
	local parent = self.parent
	self.Height = parent.Height * 0.4
	self.Width = self.Height
	self.pos = { parent.Width * 0.5 - self.Width * 0.5, parent.Height * 0.5 - self.Height * 0.5 }
end

noConnShape = bundle:Shape("shapes/no_conn_indicator")
noConnectionIndicator = ui:createShape(noConnShape)
noConnectionIndicator:setParent(connBtn)
noConnectionIndicator:hide()
noConnectionIndicator.parentDidResize = function(self)
	local parent = self.parent
	self.Height = parent.Height * 0.4
	self.Width = self.Height
	self.pos = { parent.Width - self.Width - PADDING, parent.Height * 0.5 - self.Height * 0.5 }
end

function connectionIndicatorValid()
	Client:HapticFeedback()
	connShape.Tick = nil
	local palette = connShape.Palette
	palette[1].Color = theme.colorPositive
	palette[2].Color = theme.colorPositive
	palette[3].Color = theme.colorPositive
	palette[4].Color = theme.colorPositive
	sfx("metal_clanging_2", { Volume = 0.2, Pitch = 5.0, Spatialized = false })
end

function connectionIndicatorStartAnimation()
	local animTime = 0.7
	local animTimePortion = animTime / 4.0
	local t = 0.0

	local palette = connShape.Palette
	local darkGrayLevel = 100
	local darkGray = Color(darkGrayLevel, darkGrayLevel, darkGrayLevel)
	local white = Color.White

	palette[1].Color = darkGray
	palette[2].Color = darkGray
	palette[3].Color = darkGray
	palette[4].Color = darkGray

	local v
	connShape.Tick = function(_, dt)
		t = t + dt
		local palette = connShape.Palette

		t = math.min(animTime, t)

		if t < animTime * 0.25 then
			v = t / animTimePortion
			palette[1].Color:Lerp(darkGray, white, v)
			palette[2].Color = darkGray
			palette[3].Color = darkGray
			palette[4].Color = darkGray
		elseif t < animTime * 0.5 then
			v = (t - animTimePortion) / animTimePortion
			palette[1].Color = white
			palette[2].Color:Lerp(darkGray, white, v)
			palette[3].Color = darkGray
			palette[4].Color = darkGray
		elseif t < animTime * 0.75 then
			v = (t - animTimePortion * 2) / animTimePortion
			palette[1].Color = white
			palette[2].Color = white
			palette[3].Color:Lerp(darkGray, white, v)
			palette[4].Color = darkGray
		else
			v = (t - animTimePortion * 3) / animTimePortion
			palette[1].Color = white
			palette[2].Color = white
			palette[3].Color = white
			palette[4].Color:Lerp(darkGray, white, v)
		end

		if t >= animTime then
			t = 0.0
		end
	end
end

-- NOTIFICATIONS

notificationsBtn = ui:createFrame(_DEBUG and _DebugColor() or Color.transparent)
notificationsBtn:setParent(topBar)
if minified then
	notificationsBtn:hide()
end

notificationsIcon = ui:frame({
	image = {
		data = Data:FromBundle("images/icon-bell.png"),
		alpha = true,
	},
})
notificationsIcon.Width = 50
notificationsIcon.Height = 50
notificationsIcon:setParent(notificationsBtn)

notificationsIconSelected =
	ui:frame({ image = {
		data = Data:FromBundle("images/icon-bell-selected.png"),
		alpha = true,
	} })
notificationsIconSelected.Width = 50
notificationsIconSelected.Height = 50
notificationsIconSelected:setParent(notificationsBtn)
notificationsIconSelected:hide()

notificationsIcon.parentDidResize = function(self)
	local parent = self.parent
	self.Height = parent.Height - PADDING * 2
	self.Width = self.Height
	self.pos = { PADDING, PADDING }

	notificationsIconSelected.Height = parent.Height - PADDING * 2
	notificationsIconSelected.Width = self.Height
	notificationsIconSelected.pos = { PADDING, PADDING }
end

local badge = require("notifications"):createBadge({
	count = 0,
	ui = ui,
	type = "notifications",
	height = 16,
	padding = 3,
	vPadding = 0,
})

badge.internalParentDidResize = badge.parentDidResize
badge.parentDidResize = function(self)
	self:internalParentDidResize()
	self.pos.X = self.parent.Width * 0.70 - self.Width * 0.5
	self.pos.Y = self.parent.Height * 0.70 - self.Height * 0.5
end

badge:setParent(notificationsBtn)

local function refreshBellCount()
	if notificationsReq ~= nil then
		notificationsReq:Cancel()
	end
	notificationsReq = require("user"):getUnreadNotificationCount({
		callback = function(count, err)
			notificationsReq = nil
			if err ~= nil then
				return
			end
			badge:setCount(count)
		end,
	})
end

if notificationCountListeners == nil then
	notificationCountListeners = {}
	local l = LocalEvent:Listen(LocalEvent.Name.NotificationCountDidChange, refreshBellCount)
	table.insert(notificationCountListeners, l)
	l = LocalEvent:Listen(LocalEvent.Name.AppDidBecomeActive, refreshBellCount)
	table.insert(notificationCountListeners, l)
end

refreshBellCount()

notificationsBtn.onPress = topBarBtnPress
notificationsBtn.onCancel = topBarBtnRelease
notificationsBtn.onRelease = function(self)
	topBarBtnRelease(self)
	showModal(MODAL_KEYS.NOTIFICATIONS)
	menu:sendHomeDebugEvent("User presses NOTIFICATIONS button")
	badge:setCount(0)
end

-- CHAT

chatBtn = ui:createFrame(_DEBUG and _DebugColor() or Color.transparent)
chatBtn:setParent(topBar)

chatIcon = ui:frame({ image = {
	data = Data:FromBundle("images/icon-chat.png"),
	alpha = true,
} })
chatIcon.Width = 50
chatIcon.Height = 50
chatIcon:setParent(chatBtn)

chatIconSelected = ui:frame({ image = {
	data = Data:FromBundle("images/icon-chat-selected.png"),
	alpha = true,
} })
chatIconSelected.Width = 50
chatIconSelected.Height = 50
chatIconSelected:setParent(chatBtn)
chatIconSelected:hide()

chatIcon.parentDidResize = function(self)
	local parent = self.parent
	self.Height = parent.Height - PADDING * 2
	self.Width = self.Height
	self.pos = { PADDING, PADDING }

	chatIconSelected.Height = parent.Height - PADDING * 2
	chatIconSelected.Width = self.Height
	chatIconSelected.pos = { PADDING, PADDING }
end

chatBadge = nil

function updateChatBadge(nbLogs, errorLogs, warningLogs)
	local totalLogs = nbLogs + errorLogs + warningLogs
	if totalLogs == 0 then
		removeChatBadge()
		return
	end
	if chatBadge ~= nil then
		chatBadge:setCount(totalLogs)
		return
	end

	chatBadge = require("notifications"):createBadge({
		count = totalLogs,
		ui = ui,
		type = "logs",
		height = 16,
		padding = 3,
		vPadding = 0,
	})
	chatBadge.internalParentDidResize = chatBadge.parentDidResize
	chatBadge.parentDidResize = function(self)
		self:internalParentDidResize()
		self.pos.X = math.max(self.parent.Width * 0.5, self.parent.Width * 0.70 - self.Width * 0.5)
		self.pos.Y = self.parent.Height * 0.70 - self.Height * 0.5
	end
	chatBadge:setParent(chatBtn)
end

function removeChatBadge()
	if chatBadge ~= nil then
		chatBadge:remove()
		chatBadge = nil
	end
end

local unreadLogs = 0
local unreadErrorLogs = 0
local unreadWarningLogs = 0
local logCountRefreshTimer
updateChatBadge(unreadLogs, unreadErrorLogs, unreadWarningLogs)
LocalEvent:Listen(LocalEvent.Name.Log, function(log)
	if chatDisplayed then
		return
	end
	unreadLogs += 1
	if logCountRefreshTimer ~= nil then
		return
	end
	logCountRefreshTimer = Timer(0.1, function()
		logCountRefreshTimer = nil
		updateChatBadge(unreadLogs, unreadErrorLogs, unreadWarningLogs)
	end)
end)

function resetLogCount()
	unreadLogs = 0
	unreadErrorLogs = 0
	unreadWarningLogs = 0
	updateChatBadge(unreadLogs, unreadErrorLogs, unreadWarningLogs)
end

-- displayes chat as expected based on state
function refreshChat()
	if chatDisplayed and cppMenuIsActive == false then
		if activeModal then
			removeChat()
		else
			if chat == nil then
				resetLogCount()
			end
			createChat()
		end
	else
		removeChat()
	end
end

-- DEV MODE / AI BUTTON

if DEV_MODE == true then
	if AI_ASSISTANT_ENABLED == true then
		aiBtn = ui:createFrame(_DEBUG and _DebugColor() or Color.transparent)
		aiBtn:setParent(topBar)

		local aiUINeedsFirstLayout = false

		local function refreshLayout(animate)
			if aiInput == nil then
				return
			end

			ease:cancel(aiInput.pos)
			ease:cancel(aiCharacter.pos)
			ease:cancel(aiCharacterBubble.pos)

			local promptEnabled = aiCharacterText:isVisible()
			local updatePosition = aiUINeedsFirstLayout or animate == false
			aiUINeedsFirstLayout = false

			local parent = aiInput.parent
			aiInput.Width = math.min(600, parent.Width - PADDING * 2)

			if aiCharacterText:isVisible() then
				aiCharacterText.object.MaxWidth = aiInput.Width - aiCharacter.Width - PADDING * 3
				aiCharacterBubble.Width = aiCharacterText.Width + PADDING * 2
				aiCharacterBubble.Height = math.min(200, aiCharacterText.Height + PADDING * 2)
			else
				aiCharacterBubble.Width = aiCharacterLoadingAnimation.Width + PADDING * 3
				aiCharacterBubble.Height = aiCharacterLoadingAnimation.Height + PADDING * 3
			end

			local targetInputPosition = {
				parent.Width * 0.5 - aiInput.Width * 0.5,
				Screen.SafeArea.Bottom + PADDING,
			}
			local targetCharacterPosition = {
				targetInputPosition[1],
				targetInputPosition[2] + aiInput.Height + PADDING,
			}

			if promptEnabled == false then
				-- move character and bubble just above safe area
				targetCharacterPosition[2] = Screen.SafeArea.Bottom + PADDING
				-- move input below viewport
				targetInputPosition[2] = -aiInput.Height - PADDING
			end

			local targetBubblePosition = {
				targetCharacterPosition[1] + aiCharacter.Width + PADDING,
				math.max(
					targetCharacterPosition[2],
					targetCharacterPosition[2] + aiCharacter.Height * 0.5 - aiCharacterBubble.Height * 0.5
				),
			}

			if updatePosition then
				aiInput.pos = targetInputPosition
				aiCharacter.pos = targetCharacterPosition
				aiCharacterBubble.pos = targetBubblePosition
			end

			if animate then
				if updatePosition then
					if promptEnabled then
						local posY = aiInput.pos.Y
						aiInput.pos.Y -= 100
						ease:outBack(aiInput.pos, 0.2, {
							onDone = function()
								aiInput:focus()
							end,
						}).Y =
							posY

						posY = aiCharacter.pos.Y
						aiCharacter.pos.Y -= 150
						ease:outBack(aiCharacter.pos, 0.25, {
							onDone = function() end,
						}).Y = posY

						posY = aiCharacterBubble.pos.Y
						aiCharacterBubble.pos.Y -= 150
						ease:outBack(aiCharacterBubble.pos, 0.3, {
							onDone = function() end,
						}).Y = posY
					end
				else
					if promptEnabled then
						ease:outBack(aiInput.pos, 0.2, {
							onDone = function()
								aiInput:focus()
							end,
						}).Y =
							targetInputPosition[2]
						ease:outBack(aiCharacter.pos, 0.22, {
							onDone = function() end,
						}).Y =
							targetCharacterPosition[2]
						ease:outBack(aiCharacterBubble.pos, 0.24, {
							onDone = function() end,
						}).Y =
							targetBubblePosition[2]
					else
						ease:inBack(aiInput.pos, 0.2, {
							onDone = function() end,
						}).Y = targetInputPosition[2]
						ease:inBack(aiCharacter.pos, 0.22, {
							onDone = function() end,
						}).Y =
							targetCharacterPosition[2]
						ease:inBack(aiCharacterBubble.pos, 0.24, {
							onDone = function() end,
						}).Y =
							targetBubblePosition[2]
					end
				end
			end
		end

		local function removeAIPrompt()
			if aiInput ~= nil then
				ease:cancel(aiInput.pos)
				aiInput:remove()
				aiInput = nil
			end
			if aiCharacterBubble ~= nil then
				ease:cancel(aiCharacterBubble.pos)
				aiCharacterBubble:remove()
				aiCharacterBubble = nil
			end
			if aiCharacter ~= nil then
				ease:cancel(aiCharacter.pos)
				aiCharacter:remove()
				aiCharacter = nil
			end
		end

		local function setAILoading()
			aiCharacterLoadingAnimation:show()
			aiCharacterText:hide()
			refreshLayout(true)
		end

		local revealTextTick = nil
		local fullStr = ""
		local displayedStr = ""
		local textRevealMaxDuration = 0.3 -- in seconds
		local charsPerSecond = 1
		local function revealText(str)
			if str:sub(1, #displayedStr) == displayedStr then
				fullStr = str
			else
				displayedStr = ""
				fullStr = str
			end
			aiCharacterText.Text = displayedStr
			charsPerSecond = math.max(1, math.ceil((#fullStr - #displayedStr) / textRevealMaxDuration))
			
			if revealTextTick ~= nil then
				return
			end

			revealTextTick = LocalEvent:Listen(LocalEvent.Name.Tick, function(dt)
				local charsToAdd = math.min(math.ceil(dt * charsPerSecond), #fullStr - #displayedStr)
				displayedStr = displayedStr .. fullStr:sub(#displayedStr + 1, #displayedStr + charsToAdd) 
				aiCharacterText.Text = displayedStr
				if #displayedStr >= #fullStr then
					revealTextTick:Remove()
					revealTextTick = nil
				end
			end)
		end

		local function setAIText(text, textType)
			if textType == "code" then
				aiCharacterText.object.Scale = 0.5
				aiCharacterText.Color = Color(220, 220, 220)
			else
				aiCharacterText.object.Scale = 1.0
				aiCharacterText.Color = Color.White
			end
			aiCharacterText.Text = text -- set now to prepare layout
			aiCharacterText:show()
			aiCharacterLoadingAnimation:hide()
			refreshLayout(true)
			revealText(text)
			-- sfx("waterdrop_2", { Volume = 0.5, Pitch = 1.0, Spatialized = false })
		end

		local aiIcon = ui:frame({
			image = {
				data = Data:FromBundle("images/icon-ai.png"),
				alpha = true,
			},
		})
		aiIcon.Width = 50
		aiIcon.Height = 50

		aiIcon.parentDidResize = function(self)
			local parent = self.parent
			self.Height = parent.Height - PADDING * 2
			self.Width = self.Height
			self.pos = { PADDING, PADDING }
		end
		aiIcon:setParent(aiBtn)

		aiBtn.onPress = topBarBtnPress
		aiBtn.onCancel = topBarBtnRelease
		aiBtn.onRelease = function(self)
			if idleBuddy == nil then
				idleBuddy = Data:FromBundle("images/ai-buddy-idle.png")
				welcomingBuddy = Data:FromBundle("images/ai-buddy-welcoming.png")
				buddyWhenUserIsTyping = Data:FromBundle("images/ai-buddy-user-typing.png")
				buddyThinking = Data:FromBundle("images/ai-buddy-thinking.png")
			end

			topBarBtnRelease(self)

			if aiInput == nil then
				sfx("waterdrop_2", { Volume = 0.5, Pitch = 1.0, Spatialized = false })
				aiUINeedsFirstLayout = true

				aiCharacter = ui:frame({ image = {
					data = welcomingBuddy,
					alpha = true,
				} })
				aiCharacter.Width = 60
				aiCharacter.Height = 47
				aiCharacter:setParent(background)

				aiCharacterBubble = ui:frame({
					image = {
						data = Data:FromBundle("images/chat-background.png"),
						slice9 = { 0.5, 0.5 },
						slice9Scale = 1.0,
						alpha = true,
					},
					mask = true,
				})
				aiCharacterBubble:setParent(background)

				aiCharacterLoadingAnimation = require("ui_loading_animation"):create({ ui = ui })
				aiCharacterLoadingAnimation.pos = { PADDING * 1.5, PADDING * 1.5 }
				aiCharacterLoadingAnimation:setParent(aiCharacterBubble)
				aiCharacterLoadingAnimation:hide()

				aiCharacterText = ui:createText("Hey! I'm Buzz, I can code, what do you want to do? 🙂", {
					size = "small",
					color = Color.White,
				})
				aiCharacterText.object.MaxWidth = 200
				aiCharacterText.pos = { PADDING, PADDING }
				aiCharacterText:setParent(aiCharacterBubble)

				aiInput = ui:createTextInput("", "", {
					textSize = "small",
					returnKeyType = "send",
				})
				aiInput:setParent(background)
				-- background, text, placeholder, border
				aiInput:setColor(Color(10, 10, 10, 0.9), Color.White, Color(255, 255, 255, 0.4), Color(255, 255, 255, 0.5))
				aiInput:setColorPressed(
					Color(10, 10, 10, 0.9),
					Color.White,
					Color(255, 255, 255, 0.4),
					Color(255, 255, 255, 0.5)
				)
				aiInput:setColorFocused(
					Color(10, 10, 10, 0.9),
					Color.White,
					Color(255, 255, 255, 0.4),
					Color(255, 255, 255, 0.5)
				)

				aiInput.parentDidResize = function(self)
					refreshLayout(false)
				end
				refreshLayout(true)

				local typing = false
				aiInput.onTextChange = function(self)
					if self.Text == "" then
						if typing then
							aiCharacter.background.Image = idleBuddy
							typing = false
						end
					else
						if typing == false then
							aiCharacter.background.Image = buddyWhenUserIsTyping
							typing = true
						end
					end
				end

				aiInput.onSubmit = function(self)
					if self.Text == "" then
						removeAIPrompt()
						return
					end
					setAILoading()
					local body = {
						prompt = self.Text,
						script = System.Script,
					}
					local headers = {}
					headers["Content-Type"] = "application/json"
					self.Text = ""
					typing = false
					aiCharacter.background.Image = buddyThinking
					-- print("sending: " .. body.prompt)

					local cursor = 1
					local buffer = ""
					local messages = {}
					local currentMessage = nil
					local MARKER_START = "\n>>>>>>>"
					local MESSAGE_TYPES = { "CHAT", "SCRIPT" }
					local CURSOR_STATE = {
						LOOKING_FOR_MARKER_START = 1,
						AT_END_OF_MARKER_START = 2,
						READING_CONTENT = 3,
					}
					local cursorState = CURSOR_STATE.LOOKING_FOR_MARKER_START

					local function callback(res)
						aiCharacter.background.Image = idleBuddy
						if res.StatusCode ~= 200 then
							-- print("error: " .. res.StatusCode)
							setAIText("❌ ERROR: " .. res.StatusCode)
							return
						end

						-- print("res.Body:\n", res.Body:ToString())

						-- Legacy JSON handling
						-- local data = JSON:Decode(res.Body)
						-- if data.type == "chat" then
						-- 	setAIText(data.output)
						-- elseif data.type == "code" then
						-- 	removeAIPrompt()
						-- 	-- System:PublishScript(data.output)
						-- end

						buffer = buffer .. res.Body:ToString()
						-- print("buffer:\n", buffer)

						while true do
							if cursorState == CURSOR_STATE.LOOKING_FOR_MARKER_START then
								-- look for first marker
								local markerPos = buffer:find(MARKER_START, cursor)
								if markerPos then
									cursor = markerPos + #MARKER_START
									cursorState = CURSOR_STATE.AT_END_OF_MARKER_START
								else
									break -- no start marker found in buffer from cursor
								end
							elseif cursorState == CURSOR_STATE.AT_END_OF_MARKER_START then
								local nextNewline = buffer:find("\n", cursor)
								if nextNewline then
									local identifier = buffer:sub(cursor, nextNewline - 1)
									for _, messageType in ipairs(MESSAGE_TYPES) do
										if identifier == messageType then
											cursor = nextNewline + 1
											cursorState = CURSOR_STATE.READING_CONTENT
											currentMessage = {
												type = identifier,
												content = "",
											}
											break
										end
									end
									if cursorState ~= CURSOR_STATE.READING_CONTENT then
										-- invalid identifier, keep looking for next marker
										cursor = nextNewline -- \n could be the start of the next marker
										cursorState = CURSOR_STATE.LOOKING_FOR_MARKER_START
									end
								else
									break -- new line found after marker start
								end
							elseif cursorState == CURSOR_STATE.READING_CONTENT then
								local nextMarkerPos = buffer:find(MARKER_START, cursor)
								if nextMarkerPos then
									currentMessage.content = buffer:sub(cursor, nextMarkerPos - 1)
									cursor = nextMarkerPos
									cursorState = CURSOR_STATE.LOOKING_FOR_MARKER_START
									-- print(currentMessage.type .." -> " .. currentMessage.content)
									if currentMessage.type == "CHAT" then
										setAIText(currentMessage.content)
									elseif currentMessage.type == "SCRIPT" then
										setAIText(currentMessage.content, "code")
									end
								else
									currentMessage.content = buffer:sub(cursor)
									for i = 1, #MARKER_START - 1 do
										local suffix = currentMessage.content:sub(-i)
										if MARKER_START:sub(1, i) == suffix then
											currentMessage.content = currentMessage.content:sub(1, -i - 1)
											break
										end
									end
									if currentMessage.type == "CHAT" then
										setAIText(currentMessage.content)
									elseif currentMessage.type == "SCRIPT" then
										setAIText(currentMessage.content, "code")
									end
									if res.EndOfStream then
										if currentMessage.type == "SCRIPT" then
											removeAIPrompt()
											System:PublishScript(currentMessage.content)
										end
									end
									break
								end
							else
								-- invalid cursor state
								break
							end
						end
					end

					HTTP:Post({
						url = "http://10.0.1.2",
						headers = headers,
						body = body,
						streamed = true,
						callback = callback,
					})
				end
			else
				removeAIPrompt()
			end
		end
	end

	if IN_WORLD_EDITOR == true then
		playBtn = ui:createFrame(_DEBUG and _DebugColor() or Color.transparent)
		playBtn:setParent(topBar)

		local playIcon = ui:frame({
			image = {
				data = Data:FromBundle("images/icon-play.png"),
				alpha = true,
			},
		})
		playIcon.Width = 50
		playIcon.Height = 50

		playIcon.parentDidResize = function(self)
			local parent = self.parent
			self.Height = parent.Height - PADDING * 2
			self.Width = self.Height
			self.pos = { PADDING, PADDING }
		end
		playIcon:setParent(playBtn)

		playBtn.onPress = topBarBtnPress
		playBtn.onCancel = topBarBtnRelease
		playBtn.onRelease = function(self)
			topBarBtnRelease(self)
			System.WorldEditorPlay()
		end
	else
		stopBtn = ui:createFrame(_DEBUG and _DebugColor() or Color.transparent)
		stopBtn:setParent(topBar)

		local stopIcon = ui:frame({
			image = {
				data = Data:FromBundle("images/icon-stop.png"),
				alpha = true,
			},
		})
		stopIcon.Width = 50
		stopIcon.Height = 50

		stopIcon.parentDidResize = function(self)
			local parent = self.parent
			self.Height = parent.Height - PADDING * 2
			self.Width = self.Height
			self.pos = { PADDING, PADDING }
		end
		stopIcon:setParent(stopBtn)

		stopBtn.onPress = topBarBtnPress
		stopBtn.onCancel = topBarBtnRelease
		stopBtn.onRelease = function(self)
			topBarBtnRelease(self)
			System.WorldEditorStop()
		end
	end
end

cubzhBtn.onPress = topBarBtnPress
cubzhBtn.onCancel = topBarBtnRelease
cubzhBtn.onRelease = function(self)
	topBarBtnRelease(self)
	if System.IsHomeAppRunning then
		showModal(MODAL_KEYS.SETTINGS)
	else
		showModal(MODAL_KEYS.CUBZH_MENU)
	end
end

chatBtn.onPress = topBarBtnPress
chatBtn.onCancel = topBarBtnRelease
chatBtn.onRelease = function(self)
	topBarBtnRelease(self)
	if activeModal then
		showModal(MODAL_KEYS.CHAT)
	else
		chatDisplayed = not chatDisplayed
		refreshChat()
	end
	refreshButtons()
end

-- hide chat button by default
-- display when authenticated if System.IsChatEnabled
chatBtn:hide()

-- PEZH

pezhBtn = ui:createFrame(_DEBUG and _DebugColor() or Color.transparent)
pezhBtn:setParent(topBar)

pezhShape = ui:createShape(bundle:Shape("shapes/pezh_coin_2"), { spherized = false, doNotFlip = true })
pezhShape:setParent(pezhBtn)
pezhShape.parentDidResize = btnContentParentDidResize

-- LocalEvent:Listen(LocalEvent.Name.Tick, function(dt)
-- 	pezhShape.pivot.Rotation = pezhShape.pivot.Rotation * Rotation(0, dt, 0)
-- end)

pezhBtn.onPress = topBarBtnPress
pezhBtn.onCancel = topBarBtnRelease
pezhBtn.onRelease = function(self)
	System:DebugEvent("User presses COINS button", { context = "top bar" })
	topBarBtnRelease(self)
	showModal(MODAL_KEYS.COINS)
	sfx("coin_1", { Volume = 0.75, Pitch = 1.0, Spatialized = false })
end

if minified then
	pezhBtn:hide()
	pezhShape:setParent(nil)
end

-- CHAT

local chatBackgroundData
function createChat()
	if chat ~= nil then
		return -- chat already created
	end

	if chatBackgroundData == nil then
		chatBackgroundData = Data:FromBundle("images/chat-background.png")
	end
	chat = ui:frame({
		image = {
			data = chatBackgroundData,
			slice9 = { 0.5, 0.5 },
			slice9Scale = 1.0,
			alpha = true,
		},
	})

	-- chat = ui:createFrame(Color(0, 0, 0, 0.8))
	chat:setParent(background)

	console = require("chat"):create({
		uikit = ui,
		time = false,
		onSubmitEmpty = function()
			hideChat()
			refreshButtons()
		end,
		onFocus = function() end,
		onFocusLost = function() end,
	})
	console.Width = 200
	console.Height = 500
	console:setParent(chat)

	chat.parentDidResize = function()
		local w = Screen.Width * CHAT_SCREEN_WIDTH_RATIO
		w = math.min(w, CHAT_MAX_WIDTH)
		w = math.max(w, CHAT_MIN_WIDTH)
		chat.Width = w

		local h = Screen.Height * CHAT_SCREEN_HEIGHT_RATIO
		h = math.min(h, CHAT_MAX_HEIGHT)
		h = math.max(h, CHAT_MIN_HEIGHT)
		chat.Height = h

		console.Width = chat.Width - theme.paddingTiny * 2
		console.Height = chat.Height - theme.paddingTiny * 2

		console.pos = { theme.paddingTiny, theme.paddingTiny }
		chat.pos = { theme.padding, topBar.pos.Y - chat.Height - PADDING }
	end
	chat:parentDidResize()
end

function removeChat()
	if chat == nil then
		return -- nothing to remove
	end
	local c = chat
	chat = nil
	console = nil
	c:remove()
end

function showChat(input)
	if not Client.LoggedIn and Environment.USER_AUTH ~= "disabled" then
		return
	end
	chatDisplayed = true
	refreshChat()
	if console then
		console:focus()
		if input ~= nil then
			console:setText(input)
		end
	end
end

function hideChat()
	if Environment.CHAT_CONSOLE_DISPLAY == "always" then
		if console ~= nil and console:hasFocus() == true then
			console:unfocus()
		end
		return
	end
	chatDisplayed = false
	refreshChat()
end

refreshChat()

-- CUBZH MENU CONTENT

function getCubzhMenuModalContent()
	local dev = System.LocalUserIsAuthor and System.ServerIsInDevMode

	local content = modal:createContent()
	content.closeButton = true
	content.title = "Cubzh"
	content.icon = "⎔"

	local node = ui:createFrame()
	content.node = node

	local btnWorlds = ui:buttonNeutral({ content = "🌎 Worlds", textSize = "default", padding = theme.padding })
	btnWorlds:setParent(node)
	btnWorlds.Height = CUBZH_MENU_SECONDARY_BUTTON_HEIGHT
	btnWorlds.onRelease = function()
		if activeModal ~= nil then
			local content = require("gallery"):createModalContent({
				uikit = ui,
				type = "worlds",
				displayLikes = true,
				categories = { "featured" },
				perPage = 100,
			})
			activeModal:push(content)
		end
	end

	local btnItems
	if dev then
		btnItems = ui:buttonNeutral({ content = "⚔️ Items", textSize = "default", padding = theme.padding })
		btnItems:setParent(node)
		btnItems.Height = CUBZH_MENU_SECONDARY_BUTTON_HEIGHT

		btnItems.onRelease = function()
			if activeModal ~= nil then
				local content = require("gallery"):createModalContent({
					uikit = ui,
					type = "items",
					perPage = 100,
				})
				activeModal:push(content)
			end
		end
	end

	local btnLeave = ui:buttonNegative({ content = "Leave", textSize = "default" })
	btnLeave:setParent(node)
	btnLeave.Height = CUBZH_MENU_MAIN_BUTTON_HEIGHT

	btnLeave.onRelease = function()
		System:GoHome()
	end

	local buttons

	local btnCode = ui:buttonSecondary({
		content = dev and "🤓 Edit Code" or "🤓 Read Code",
		textSize = "small",
	})
	btnCode:setParent(node)

	btnCode.onRelease = function()
		if dev then
			System.EditCode()
		else
			System.ReadCode()
		end
		closeModal()
	end

	local btnHelp = ui:buttonSecondary({
		content = "👾 Help!",
		textSize = "small",
	})
	btnHelp:setParent(node)

	btnHelp.onRelease = function()
		URL:Open("https://discord.gg/cubzh")
	end

	if dev then
		buttons = {
			{ btnWorlds },
			{ btnItems },
			{ btnLeave },
		}
	else
		buttons = {
			{ btnWorlds },
			{ btnLeave },
		}
	end

	content.bottomCenter = { btnCode, btnHelp }

	content.idealReducedContentSize = function(_, width, _, minWidth)
		local height = 0
		local maxRowWidth = 0
		local widthBackup
		local ok

		for i, row in ipairs(buttons) do
			local w = 0
			for _, btn in ipairs(row) do
				widthBackup = btn.Width
				ok = pcall(function()
					btn.Width = nil
				end)
				if ok == false then
					btn.Width = 100 -- default width
				end
				w = w + btn.Width + (i > 1 and theme.padding or 0)
				if ok then
					btn.Width = widthBackup
				end
			end
			maxRowWidth = math.max(maxRowWidth, w)
		end

		width = math.max(math.min(width, maxRowWidth), minWidth)

		local h
		for i, row in ipairs(buttons) do
			h = 0
			for _, btn in ipairs(row) do
				if btn.dynamicHeight then
					btn.Width = width
					btn:parentDidResize()
				end
				h = math.max(h, btn.Height)
			end
			row.height = h
			height = height + h + (i > 1 and theme.padding or 0)
		end

		return Number2(width, height)
	end

	btnLeave.parentDidResize = function(_)
		local width = node.Width

		for _, row in ipairs(buttons) do
			local h = 0
			for _, btn in ipairs(row) do
				h = math.max(h, btn.Height)
			end
			row.height = h
		end

		for _, row in ipairs(buttons) do
			local w = (width - theme.padding * (#row - 1)) / #row
			for _, btn in ipairs(row) do
				btn.Width = w
			end
		end

		local row
		local cursorY = 0
		local cursorX = 0
		for i = #buttons, 1, -1 do
			row = buttons[i]

			for _, btn in ipairs(row) do
				btn.pos = { cursorX, cursorY, 0 }
				cursorX = cursorX + btn.Width + theme.padding
			end

			cursorY = cursorY + row.height + theme.padding
			cursorX = 0
		end
	end

	content.didBecomeActive = function()
		btnLeave:parentDidResize()
		showActionColumn()
	end

	content.willResignActive = function()
		actionColumn:hide()
	end

	return content
end

topBar.parentDidResize = function(self)
	local height = TOP_BAR_HEIGHT

	self.Height = height
	self.pos = {
		Screen.SafeArea.Left + PADDING,
		Screen.Height - System.SafeAreaTop - self.Height - PADDING,
	}

	local width = cubzhBtn.Width

	cubzhBtn.pos = { 0, 0 }

	-- SETTINGS / EXPERIENCE EXIT

	cubzhBtn.Height = height
	cubzhBtn.Width = height
	local previousBtn = cubzhBtn

	-- PEZH BUTTON

	if pezhBtn:isVisible() then
		pezhBtn.Height = height
		pezhBtn.Width = height
		pezhBtn.pos = { previousBtn.pos.X + previousBtn.Width, 0 }
		previousBtn = pezhBtn
		width += pezhBtn.Width
	end

	-- NOTIFICATIONS BUTTON

	if notificationsBtn:isVisible() then
		notificationsBtn.Height = height
		notificationsBtn.Width = height
		notificationsBtn.pos = { previousBtn.pos.X + previousBtn.Width, 0 }
		previousBtn = notificationsBtn
		width += notificationsBtn.Width
	end

	-- CONNECTION BUTTON

	if connBtn:isVisible() then
		connBtn.Height = height
		connBtn.Width = height
		connBtn.pos = { previousBtn.pos.X + previousBtn.Width, 0 }
		previousBtn = connBtn
		width += connBtn.Width
	end

	-- CHAT BUTTON

	if chatBtn:isVisible() then
		chatBtn.Height = height
		chatBtn.Width = height
		chatBtn.pos = { previousBtn.pos.X + previousBtn.Width, 0 }
		previousBtn = chatBtn
		width += chatBtn.Width
	end

	-- AI BUTTON

	if aiBtn ~= nil and aiBtn:isVisible() then
		aiBtn.Height = height
		aiBtn.Width = height
		aiBtn.pos = { previousBtn.pos.X + previousBtn.Width, 0 }
		previousBtn = aiBtn
		width += aiBtn.Width
	end

	-- PLAY BUTTON

	if playBtn ~= nil and playBtn:isVisible() then
		playBtn.Height = height
		playBtn.Width = height
		playBtn.pos = { previousBtn.pos.X + previousBtn.Width, 0 }
		previousBtn = playBtn
		width += playBtn.Width
	end

	-- STOP BUTTON

	if stopBtn ~= nil and stopBtn:isVisible() then
		stopBtn.Height = height
		stopBtn.Width = height
		stopBtn.pos = { previousBtn.pos.X + previousBtn.Width, 0 }
		previousBtn = stopBtn	
		width += stopBtn.Width
	end

	self.Width = width

end
topBar:parentDidResize()

-- BOTTOM BAR

bottomBar = ui:createFrame(Color(0, 0, 0, 0.6))
bottomBar:setParent(background)

appVersion = ui:createText("Blip " .. Client.AppVersion .. " (alpha) #" .. Client.BuildNumber, Color(100,100,100), "small")
appVersion:setParent(bottomBar)

copyright = ui:createText("© Voxowl, Inc.", Color(100,100,100), "small")
copyright:setParent(bottomBar)

bottomBar.parentDidResize = function(self)
	local padding = theme.padding

	self.Width = Screen.Width
	self.Height = Screen.SafeArea.Bottom + appVersion.Height + padding * 2

	appVersion.pos = { Screen.SafeArea.Left + padding * 2, Screen.SafeArea.Bottom + padding, 0 }
	copyright.pos =
		{ Screen.Width - Screen.SafeArea.Right - copyright.Width - padding * 2, Screen.SafeArea.Bottom + padding, 0 }
end
bottomBar:parentDidResize()

menu.AddDidBecomeActiveCallback = function(self, callback)
	if self ~= menu then
		error("Menu:AddDidBecomeActiveCallback should be called with `:`", 2)
	end
	if type(callback) ~= "function" then
		return
	end
	didBecomeActiveCallbacks[callback] = callback
end

menu.RemoveDidBecomeActiveCallback = function(self, callback)
	if self ~= menu then
		error("Menu:RemoveDidBecomeActiveCallback should be called with `:`", 2)
	end
	if type(callback) ~= "function" then
		return
	end
	didBecomeActiveCallbacks[callback] = nil
end

menu.AddDidResignActiveCallback = function(self, callback)
	if self ~= menu then
		error("Menu:AddWillResignActiveCallback should be called with `:`", 2)
	end
	if type(callback) ~= "function" then
		return
	end
	didResignActiveCallbacks[callback] = callback
end

menu.RemoveDidResignActiveCallback = function(self, callback)
	if self ~= menu then
		error("Menu:RemoveWillResignActiveCallback should be called with `:`", 2)
	end
	if type(callback) ~= "function" then
		return
	end
	didResignActiveCallbacks[callback] = nil
end

menu.IsActive = function(_)
	return activeModal ~= nil or alertModal ~= nil or loadingModal ~= nil or cppMenuIsActive
end

menu.BottomBar = bottomBar

function menuSectionCanBeShown()
	if not Client.LoggedIn and Environment.USER_AUTH ~= "disabled" then
		return false
	end
	if topBar:isVisible() == false then
		return false
	end
	if menu:IsActive() then
		return false
	end
	return true
end

---@function Show Shows Cubzh menu if possible. (if user is authenticated, and menu not already active)
--- Returns true on success, false otherwise.
---@code local menu = require("menu")
--- menu:Show() -- shows Cubzh menu
---@return boolean
menu.Show = function(_)
	if menuSectionCanBeShown() == false then
		return false
	end
	cubzhBtn:onRelease()
	return true
end

---@function Highlight Highlights Cubzh menu button in the top bar if possible. (if user is authenticated, and menu not already active)
--- Returns true on success, false otherwise.
---@code local menu = require("menu")
--- menu:Highlight()
---@return boolean
menu.Highlight = function(_)
	if menuSectionCanBeShown() == false then
		return false
	end
	if pointer == nil then
		pointer = uiPointer:create({ uikit = ui })
	end
	pointer:pointAt({ target = cubzhBtn, from = "below" })
	return true
end

---@function RemoveHighlight Stops highlighting elements in the menu.
---@code local menu = require("menu")
--- menu:RemoveHighlight()
menu.RemoveHighlight = function(_)
	if pointer ~= nil then
		pointer:remove()
		pointer = nil
	end
end

---@function ShowFriends Shows friends menu if possible. (if user is authenticated, and menu not already active)
--- Returns true on success, false otherwise.
---@code local menu = require("menu")
--- menu:ShowFriends() -- shows friends menu
---@return boolean
menu.ShowFriends = function(_)
	if menuSectionCanBeShown() == false then
		return false
	end
	showModal(MODAL_KEYS.FRIENDS)
	return true
end

---@function HighlightCubzhMenu Highlights Cubzh button in the top bar if possible. (if user is authenticated, and menu not already active)
--- Returns true on success, false otherwise.
---@code local menu = require("menu")
--- menu:HighlightCubzhMenu()
---@return boolean
menu.HighlightCubzhMenu = function(_)
	if menuSectionCanBeShown() == false then
		return false
	end
	if pointer == nil then
		pointer = uiPointer:create({ uikit = ui })
	end
	pointer:pointAt({ target = cubzhBtn, from = "below" })

	return true
end

---@function ShowProfile Shows local user profile menu if possible. (if user is authenticated, and menu not already active)
--- Returns true on success, false otherwise.
---@code local menu = require("menu")
--- menu:ShowProfile() -- shows local user profile menu
--- menu:ShowProfile({ player = somePlayer }) -- shows profile of given Player
--- menu:ShowProfile({ id = somePlayerID }) -- shows profile of Player with given UserID
---@return boolean
menu.ShowProfile = function(_, config)
	if menuSectionCanBeShown() == false then
		return false
	end
	config = config or {}
	-- player can be nil, displays local player in that case
	showModal(MODAL_KEYS.PROFILE, config)
	return true
end

---@function ShowNotifications Shows received notications menu if possible. (if user is authenticated, and menu not already active)
--- Returns true on success, false otherwise.
---@code local menu = require("menu")
--- menu:ShowNotifications()
---@return boolean
menu.ShowNotifications = function(_)
	if menuSectionCanBeShown() == false then
		return false
	end
	showModal(MODAL_KEYS.NOTIFICATIONS)
	return true
end

menu.ShowOutfits = function(_, player)
	if menuSectionCanBeShown() == false then
		return false
	end
	-- player can be nil, displays local player in that case
	showModal(MODAL_KEYS.OUTFITS, { player = player })
	return true
end

---@function ShowProfileFace Shows local user profile menu to edit face if possible. (if user is authenticated, and menu not already active)
--- Returns true on success, false otherwise.
---@code local menu = require("menu")
--- menu:ShowProfileFace() -- shows local user profile menu, on edit face tab
---@return boolean
menu.ShowProfileFace = function(_)
	if menuSectionCanBeShown() == false then
		return false
	end
	local _, content = showModal(MODAL_KEYS.PROFILE)
	content:showFaceEdit()
	return true
end

---@function ShowProfileWearables Shows local user profile menu to edit wearables if possible. (if user is authenticated, and menu not already active)
--- Returns true on success, false otherwise.
---@code local menu = require("menu")
--- menu:ShowProfileWearables() -- shows local user profile menu, on edit wearables tab
---@return boolean
menu.ShowProfileWearables = function(_)
	if menuSectionCanBeShown() == false then
		return false
	end
	local _, content = showModal(MODAL_KEYS.PROFILE)
	content:showWearablesEdit()
	return true
end

---@function HighlightProfile Highlights local user profile button in the top bar if possible. (if user is authenticated, and menu not already active)
--- Returns true on success, false otherwise.
---@code local menu = require("menu")
--- menu:HighlightProfile()
---@return boolean
menu.HighlightProfile = function(_)
	if menuSectionCanBeShown() == false then
		return false
	end
	if pointer == nil then
		pointer = uiPointer:create({ uikit = ui })
	end
	pointer:pointAt({ target = profileFrame, from = "below" })
	return true
end

---@function ShowWorlds Shows the world gallery if possible. (if user is authenticated, and menu not already active)
--- Returns true on success, false otherwise.
---@code local menu = require("menu")
--- menu:ShowWorlds() -- shows worlds gallery
---@return boolean
menu.ShowWorlds = function(_, config)
	if menuSectionCanBeShown() == false then
		return false
	end
	showModal(MODAL_KEYS.WORLDS, config)
	return true
end

---@function ShowWorld Shows world identified by id. (if user is authenticated, and menu not already active)
--- Returns true on success, false otherwise.
---@code local menu = require("menu")
--- menu:ShowWorld({id = "some-world-id"})
---@return boolean
menu.ShowWorld = function(self, config)
	if self ~= menu then
		error("Menu:ShowWorld(config): use `:`", 2)
	end
	if menuSectionCanBeShown() == false then
		return false
	end
	showModal(MODAL_KEYS.WORLD, config)
	return true
end

---@function ShowItems Shows the item gallery if possible. (if user is authenticated, and menu not already active)
--- Returns true on success, false otherwise.
---@code local menu = require("menu")
--- menu:ShowItems() -- shows items gallery
---@return boolean
menu.ShowItems = function(_, config)
	if menuSectionCanBeShown() == false then
		return false
	end
	showModal(MODAL_KEYS.ITEMS, config)
	return true
end

---@function ShowItem Shows item identified by id. (if user is authenticated, and menu not already active)
--- Returns true on success, false otherwise.
---@code local menu = require("menu")
--- menu:ShowItem({id = "some-item-id"})
---@return boolean
menu.ShowItem = function(self, config)
	if self ~= menu then
		error("Menu:ShowItem(config): use `:`", 2)
	end
	if menuSectionCanBeShown() == false then
		return false
	end
	showModal(MODAL_KEYS.ITEM, config)
	return true
end

---@function ShowCreations Shows user creations. (if user is authenticated, and menu not already active)
--- Returns true on success, false otherwise.
---@code local menu = require("menu")
--- menu:ShowCreations() -- shows user creations
---@return boolean
menu.ShowCreations = function(_)
	if menuSectionCanBeShown() == false then
		return false
	end
	if not System.IsPhoneExempted and not System.HasVerifiedPhoneNumber then
		local text = "A verified phone number is mandatory to create."
		if System.IsUserUnder13 == true then
			text = "A verified parent or guardian's phone number is mandatory to create."
		end
		showModal(MODAL_KEYS.VERIFY_ACCOUNT_FORM, { text = text })
		return
	end
	if Player.Username == "newbie" then
		Menu:ShowUsernameForm({ text = "A Username is mandatory to create, ready to pick one now?" })
		return
	end
	showModal(MODAL_KEYS.CREATIONS)
	return true
end

-- undocumented on purpose
-- works only from home
menu.ShowUsernameForm = function(_, config)
	if menuSectionCanBeShown() == false then
		return false
	end
	if not System.IsPhoneExempted and not System.HasVerifiedPhoneNumber then
		showModal(MODAL_KEYS.VERIFY_ACCOUNT_FORM, {})
		return
	end
	showModal(MODAL_KEYS.USERNAME_FORM, config)
	return true
end

-- "Auth complete" callbacks called when valid credentials are stored on the device and verified.
-- (on account creation, when user logs in, when app starts and verify credentials are still valid)

authCompleteCallbacks = {}

function authCompleted()
	for _, callback in ipairs(authCompleteCallbacks) do
		callback()
	end
end

-- Triggered when the user account is created
menu.OnAuthComplete = function(self, callback)
	if self ~= menu then
		return
	end
	if type(callback) ~= "function" then
		return
	end
	if Client.LoggedIn then
		-- already authenticated, trigger callback now!
		callback()
	else
		table.insert(authCompleteCallbacks, callback)
	end
end

-- system reserved exposed functions

menu.openURLWarning = function(_, url, system)
	if system ~= System then
		error("menu.openURLWarning requires System privileges")
	end
	local config = {
		message = "Taking you to " .. url .. "\nAre you sure you want to go there?",
		positiveCallback = function()
			system:OpenURL(url)
		end,
		negativeCallback = function() end,
	}
	showAlert(config)
end

menu.loading = function(_, message, system)
	if system ~= System then
		error("menu:loading requires System privileges")
	end
	if type(message) ~= "string" then
		error("menu:loading(message, system) expects message to be a string")
	end
	showLoading(message)
end

menu.ShowAlert = function(_, config, system)
	if system ~= System then
		error("menu:ShowAlert requires System privileges")
	end
	showAlert(config)
end

menu.sendHomeDebugEvent = function(_, name, properties)
	if System.IsHomeAppRunning then
		properties = properties or {}
		properties.context = "home"
		System:DebugEvent(name, properties)
	end
end

local mt = {
	__index = function(_, k)
		if k == "Height" then
			return topBar.Height
		elseif k == "Width" then
			return topBar.Width
		elseif k == "Position" then
			return Number2(topBar.pos.X, topBar.pos.Y)
		end
	end,
	__newindex = function()
		error("Menu is read-only", 2)
	end,
	__metatable = false,
	__tostring = function()
		return "[Menu]"
	end,
	__type = "Menu",
}

setmetatable(menu, mt)

LocalEvent:Listen(LocalEvent.Name.FailedToLoadWorld, function()
	hideLoading()
	-- TODO: display alert, could receive world info to retry
end)

local keysDown = {} -- captured keys

LocalEvent:Listen(LocalEvent.Name.KeyboardInput, function(_, keyCode, _, down)
	if not down then
		if keysDown[keyCode] then
			keysDown[keyCode] = nil
			return true -- capture
		else
			return -- return without catching
		end
	end

	-- key is down from here

	if
		keyCode ~= codes.ESCAPE
		and keyCode ~= codes.RETURN
		and keyCode ~= codes.NUMPAD_RETURN
		and keyCode ~= codes.SLASH
	then
		-- key not handled by menu
		return
	end

	if not keysDown[keyCode] then
		keysDown[keyCode] = true
	else
		return -- key already down, not considering repeated inputs
	end

	if down then
		if keyCode == codes.ESCAPE then
			if activeModal ~= nil then
				popModal()
			elseif console ~= nil and console:hasFocus() == true then
				console:unfocus()
			else
				menu:Show()
			end
		elseif keyCode == codes.RETURN or keyCode == codes.NUMPAD_RETURN then
			keysDown[keyCode] = false
			showChat("")
		elseif keyCode == codes.SLASH then
			keysDown[keyCode] = false
			showChat("/")
		end
	end

	return true -- capture
end, { topPriority = true, system = System })

LocalEvent:Listen(LocalEvent.Name.CppMenuStateChanged, function(_)
	cppMenuIsActive = System.IsCppMenuActive

	if cppMenuIsActive then
		ui:turnOff()
	else
		ui:turnOn()
	end

	refreshDisplay()
	triggerCallbacks()
	refreshChat()
	refreshButtons()
end)

LocalEvent:Listen(LocalEvent.Name.ServerConnectionSuccess, function()
	connectionIndicatorValid()
	if Client.ServerConnectionSuccess then
		Client.ServerConnectionSuccess()
	end
end)

LocalEvent:Listen(LocalEvent.Name.ServerConnectionFailed, function()
	if Client.ServerConnectionFailed then
		Client.ServerConnectionFailed()
	end
	startConnectTimer()
end)

LocalEvent:Listen(LocalEvent.Name.ServerConnectionLost, function()
	if Client.ServerConnectionLost then
		Client.ServerConnectionLost()
	end
	startConnectTimer()
end)

LocalEvent:Listen(LocalEvent.Name.ServerConnectionStart, function()
	if Client.ConnectingToServer then
		Client.ConnectingToServer()
	end
end)

LocalEvent:Listen(LocalEvent.Name.DidReceivePushNotification, function(title, body, category, _)
	showNotification(title, body, category)
end)

-- sign up / sign in flow

function hideTopBar()
	topBar:hide()
end

function showTopBar()
	if Environment.CUBZH_MENU == "disabled" then
		return
	end
	if not Client.LoggedIn and Environment.USER_AUTH ~= "disabled" then
		return
	end
	topBar:show()
end

function hideBottomBar()
	bottomBar:hide()
end

function showBottomBar()
	bottomBar:show()
end

if Environment.CHAT_CONSOLE_DISPLAY == "always" then
	chatDisplayed = true
	refreshChat()
end

function getWorldInfo()
	if getWorldInfoReq ~= nil then
		getWorldInfoReq:Cancel()
		getWorldInfoReq = nil
	end
	if Environment.worldId ~= nil then
		getWorldInfoReq = api:getWorld(Environment.worldId, { "likes", "liked" }, function(world, err)
			if err ~= nil then
				return
			end
			nbLikes = world.likes
			liked = world.liked
			actionColumnUpdateContent()
		end)
	end
end

menu:OnAuthComplete(function()
	showTopBar()
	hideBottomBar()

	if activeFlow ~= nil then
		activeFlow:remove()
	end

	getWorldInfo()

	-- connects client to server if it makes sense (maxPlayers > 1)
	connect()

	if System.IsChatEnabled then
		chatBtn:show()
	else
		chatBtn:hide()
	end

	topBar:parentDidResize()
	if chat then
		chat:parentDidResize()
	end

	-- check if there's an environment to launch, otherwise, listen for event
	if System.HasEnvironmentToLaunch then
		System:LaunchEnvironment()
	else
		LocalEvent:Listen(LocalEvent.Name.ReceivedEnvironmentToLaunch, function()
			if System.HasEnvironmentToLaunch then
				System:LaunchEnvironment()
			end
		end)
	end

	if System.Under13DisclaimerNeedsApproval then
		showAlert({
			message = "⚠️ Be safe online! ⚠️\n\nDo NOT share personal details, watch out for phishing, scams and always think about who you're talking to.\n\nIf anything goes wrong, talk to someone you trust. 🙂",
			positiveLabel = loc("Yes sure!"),
			positiveCallback = function()
				System.ApproveUnder13Disclaimer()
			end,
		})
	end

	LocalEvent:Send("signup_flow_login_success")
end)

if Environment.USER_AUTH == "disabled" then
	showTopBar()
	topBar:parentDidResize()
	hideBottomBar()
elseif not Client.LoggedIn then
	local signupFlow = signup:startFlow({
		ui = ui,
		avatarPreviewStep = function()
			LocalEvent:Send("signup_flow_avatar_preview")
			hideBottomBar()
		end,
		loginStep = function()
			LocalEvent:Send("signup_flow_login")
			hideBottomBar()
		end,
		signUpOrLoginStep = function()
			LocalEvent:Send("signup_flow_start_or_login")
			showBottomBar()
		end,
		loginSuccess = function()
			authCompleted()
		end,
		avatarEditorStep = function()
			LocalEvent:Send("signup_flow_avatar_editor")
		end,
		dobStep = function()
			LocalEvent:Send("signup_flow_dob")
		end,
		pushNotificationsStep = function()
			LocalEvent:Send("signup_push_notifications")
		end,
	})
	activeFlow = signupFlow
end

return menu
