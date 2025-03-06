local uitheme = {
	_themes = {
		dark = {
			textColor = Color.White,
			errorTextColor = Color(225, 59, 58),
			warningTextColor = Color(251, 206, 0),

			textColorSecondary = Color(80, 80, 80),
			paddingTiny = 3,
			padding = 6,
			paddingBig = 12,
			cellPadding = 5,
			scrollPadding = 5,
			gridSpacing = 4,
			gridCellColor = Color(0, 0, 0, 0.6),
			gridCellColorPressed = Color(255, 255, 255, 0.6),
			gridCellFrameColor = Color(0, 0, 0, 0.8),

			-- BUTTONS
			-- NEUTRAL
			buttonColor = Color(181, 186, 193),
			buttonColorSecondary = Color(63, 63, 63, 0.8),
			buttonTextColor = Color(30, 31, 34),
			buttonColorPressed = Color(100, 100, 100),
			buttonTextColorPressed = Color.White,
			buttonColorSelected = Color(70, 2013, 178),
			buttonTextColorSelected = Color.White,

			urlColor = Color(0, 171, 228),

			-- POSITIVE
			buttonPositiveTextColor = Color(255, 255, 255),

			-- NEGATIVE
			buttonNegativeTextColor = Color(255, 255, 255),

			-- SECONDARY
			buttonSecondaryTextColor = Color(255, 255, 255),

			-- APPLE
			buttonAppleTextColor = Color(255, 255, 255),

			buttonColorDisabled = Color(20, 20, 20, 0.5),
			buttonTextColorDisabled = Color(84, 84, 84, 0.5),

			buttonTopBorderBrightnessDiff = 0.18,
			buttonBottomBorderBrightnessDiff = -0.15,
			buttonBorderSize = 3,
			textInputBorderSize = 2,

			modalBorder = 0,
			modalTopBarPadding = 3,
			modalContentPadding = 6,
			modalBottomBarPadding = 6,
			modalMargin = 12, -- minimum space around modal
			modalTabSpace = 3,
			modalTopBarColor = Color(63, 63, 63),
			modalBottomBarColor = Color(63, 63, 63),
			modalTabColorSelected = Color(63, 63, 63),
			modalTabColorPressed = Color(80, 80, 80),
			modalTabColorIdle = Color(28, 28, 28),

			colorNegative = Color(227, 53, 56),
			colorPositive = Color(139, 195, 74),
			colorExplore = Color(1, 112, 236),
			colorCreate = Color(236, 103, 11),
			colorDiscord = Color(90, 101, 234),

			textInputCursorWidth = 2,
			textInputCursorBlinkTime = 0.3,

			textInputDefaultWidth = 100,
			textInputBackgroundColor = Color(80, 80, 80),
			textInputBackgroundColorPressed = Color(150, 150, 150),
			textInputBackgroundColorFocused = Color(38, 130, 204),
			textInputBackgroundColorDisabled = Color(150, 150, 150),

			textInputTextColor = Color(230, 230, 230),
			textInputTextColorPressed = Color.White,
			textInputTextColorFocused = Color.White,
			textInputTextColorDisabled = Color(255, 255, 255, 0.3),

			textInputPlaceholderColor = Color(255, 255, 255, 0.3),
			textInputPlaceholderColorPressed = Color(0, 0, 0, 0.2),
			textInputPlaceholderColorFocused = Color(0, 0, 0, 0.2),
			textInputPlaceholderColorDisabled = Color(0, 0, 0, 0.1),

			textInputBorderBrightnessDiff = -0.1,
		},
		oled = {
			textColor = Color.White,
			errorTextColor = Color(225, 59, 58),
			warningTextColor = Color(251, 206, 0),

			textColorSecondary = Color(80, 80, 80),
			paddingTiny = 3,
			padding = 6,
			paddingBig = 12,
			gridSpacing = 4,
			gridCellColor = Color(0, 0, 0, 0.6),
			gridCellColorPressed = Color(255, 255, 255, 0.6),
			gridCellFrameColor = Color(0, 0, 0, 0.8),
			buttonColor = Color(0, 0, 0),
			buttonColorSecondary = Color(46, 46, 46, 0.8),
			buttonTextColor = Color(255, 255, 255),
			buttonColorPressed = Color(40, 40, 40),
			buttonTextColorPressed = Color.White,
			buttonColorSelected = Color(168, 168, 168),
			buttonTextColorSelected = Color.White,
			buttonColorDisabled = Color(112, 112, 112, 0.5),
			buttonTextColorDisabled = Color(84, 84, 84, 0.5),
			buttonTopBorderBrightnessDiff = 0.18,
			buttonBottomBorderBrightnessDiff = -0.15,
			buttonBorderSize = 3,
			textInputBorderSize = 2,

			modalBorder = 0,
			modalTopBarPadding = 3,
			modalContentPadding = 6,
			modalBottomBarPadding = 3,
			modalMargin = 12, -- minimum space around modal
			modalTabSpace = 3,
			modalTopBarColor = Color(0, 0, 0),
			modalBottomBarColor = Color(31, 31, 31),
			modalTabColorSelected = Color(63, 63, 63),
			modalTabColorPressed = Color(80, 80, 80),
			modalTabColorIdle = Color(28, 28, 28),

			colorNegative = Color(227, 53, 56),
			colorPositive = Color(139, 195, 74),
			colorExplore = Color(1, 112, 236),
			colorCreate = Color(228, 228, 228),
			colorDiscord = Color(228, 228, 228),

			textInputCursorWidth = 2,
			textInputCursorBlinkTime = 0.3,

			textInputDefaultWidth = 100,
			textInputBackgroundColor = Color(80, 80, 80),
			textInputBackgroundColorPressed = Color(150, 150, 150),
			textInputBackgroundColorFocused = Color(38, 130, 204),
			textInputBackgroundColorDisabled = Color(150, 150, 150),

			textInputTextColor = Color(230, 230, 230),
			textInputTextColorPressed = Color.White,
			textInputTextColorFocused = Color(220, 220, 220),
			textInputTextColorDisabled = Color(255, 255, 255, 0.3),

			textInputPlaceholderColor = Color(255, 255, 255, 0.3),
			textInputPlaceholderColorPressed = Color(0, 0, 0, 0.2),
			textInputPlaceholderColorFocused = Color(0, 0, 0, 0.2),
			textInputPlaceholderColorDisabled = Color(0, 0, 0, 0.1),

			textInputBorderBrightnessDiff = -0.1,
		},
	},

	current = nil,
}

uitheme.current = uitheme._themes.dark

local meta = {
	__index = function(t, k)
		return t.current[k]
	end,
	__newindex = function(_, _)
		error("can't set new keys in uitheme")
	end,
}

setmetatable(uitheme, meta)

return uitheme
