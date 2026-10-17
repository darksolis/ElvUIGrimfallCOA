local E, L, V, P, G = unpack(ElvUI)
local mod = E:GetModule("Enhanced_Blizzard")
local LSM = LibStub("LibSharedMedia-3.0")

local defaultSettings = {
	width = 512,
	height = 60,
	font = "PT Sans Narrow",
	fontSize = 15,
	fontOutline = "NONE"
}

function mod:ErrorFrameSize(db)
	db = db or E.db.enhanced.blizzard.errorFrame

	UIErrorsFrame:Size(db.width, db.height)
	UIErrorsFrame:SetFont(LSM:Fetch("font", db.font), db.fontSize, db.fontOutline)

	if not UIErrorsFrame.mover then
		E:CreateMover(UIErrorsFrame, "UIErrorsFrameMover", L["Error Frame"], nil, nil, nil, "ALL,GENERAL", nil, "elvuiPlugins,enhanced,miscGroup,errorFrame")
	end
end

function mod:CustomErrorFrameToggle()
	if E.db.enhanced.blizzard.errorFrame.enable then
		self:ErrorFrameSize()
		E:EnableMover(UIErrorsFrame.mover:GetName())
	else
		self:ErrorFrameSize(defaultSettings)
		UIErrorsFrame:Point("TOP", 0, -122)

		if UIErrorsFrame.mover then
			E:DisableMover(UIErrorsFrame.mover:GetName())
			UIErrorsFrame.mover:ClearAllPoints()
			UIErrorsFrame.mover:Point("TOP", 0, -122)
		end
	end
end

local originalErrorSpeech

local originalAddMessage

function mod:ErrorFilterToggle()
	local db = E.db.enhanced.blizzard.errorFilter

	if db.muteErrorSpeech then
		if originalErrorSpeech == nil then
			originalErrorSpeech = GetCVar("Sound_EnableErrorSpeech")
		end
		SetCVar("Sound_EnableErrorSpeech", 0)
	elseif originalErrorSpeech ~= nil then
		SetCVar("Sound_EnableErrorSpeech", originalErrorSpeech)
		originalErrorSpeech = nil
	end

	if db.hideErrorText then
		if not originalAddMessage then
			originalAddMessage = UIErrorsFrame.AddMessage
		end
		UIErrorsFrame.AddMessage = function() end
	elseif originalAddMessage then
		UIErrorsFrame.AddMessage = originalAddMessage
		originalAddMessage = nil
	end
end