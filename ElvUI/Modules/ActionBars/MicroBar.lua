local E, L, V, P, G = unpack(select(2, ...)); --Import: Engine, Locales, PrivateDB, ProfileDB, GlobalDB
local AB = E:GetModule("ActionBars")

--Lua functions
local _G = _G
local unpack = unpack
local gsub, match = string.gsub, string.match
--WoW API / Variables
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local RegisterStateDriver = RegisterStateDriver

local MICRO_BUTTONS = {
	"CharacterMicroButton",
	"SpellbookMicroButton",
	"TalentMicroButton",
	"AchievementMicroButton",
	"QuestLogMicroButton",
	"SocialsMicroButton",
	"PVPMicroButton",
	"LFDMicroButton",
	"MainMenuMicroButton",
	"HelpMicroButton",
	"SkillTreeMicroButton"
}

-- ʕ •ᴥ•ʔ✿ Added SkillTreeMicroButton for Ebonhold ✿ ʕ •ᴥ•ʔ

local function onEnter(button)
	if AB.db.microbar.mouseover then
		E:UIFrameFadeIn(ElvUI_Ebonhold_MicroBar, 0.2, ElvUI_Ebonhold_MicroBar:GetAlpha(), AB.db.microbar.alpha)
	end

	if button and button ~= ElvUI_Ebonhold_MicroBar and button.backdrop then
		button.backdrop:SetBackdropBorderColor(unpack(E.media.rgbvaluecolor))
	end
end

local function onLeave(button)
	if AB.db.microbar.mouseover then
		E:UIFrameFadeOut(ElvUI_Ebonhold_MicroBar, 0.2, ElvUI_Ebonhold_MicroBar:GetAlpha(), 0)
	end

	if button and button ~= ElvUI_Ebonhold_MicroBar and button.backdrop then
		button.backdrop:SetBackdropBorderColor(unpack(E.media.bordercolor))
	end
end

function AB:HandleMicroButton(button)
	if not button then return end

	button:SetParent(ElvUI_Ebonhold_MicroBar)

	if not button.elvuiPositionProtected then
		if not button.elvuiOriginalSetPoint then
			button.elvuiOriginalSetPoint = button.SetPoint
			button.elvuiOriginalClearAllPoints = button.ClearAllPoints
			button.elvuiOriginalSetSize = button.SetSize
			button.elvuiOriginalSetWidth = button.SetWidth
			button.elvuiOriginalSetHeight = button.SetHeight
			button.elvuiOriginalSetParent = button.SetParent
		end

		button.SetPoint = function(self, ...)
			self.elvuiOriginalSetPoint(self, ...)
		end

		button.ClearAllPoints = function(self)
			self.elvuiOriginalClearAllPoints(self)
		end

		button.SetSize = function(self, ...)
			self.elvuiOriginalSetSize(self, ...)
		end

		button.SetWidth = function(self, ...)
			self.elvuiOriginalSetWidth(self, ...)
		end

		button.SetHeight = function(self, ...)
			self.elvuiOriginalSetHeight(self, ...)
		end

		button.SetParent = function(self, parent)
			self.elvuiOriginalSetParent(self, parent)
		end

		button.elvuiPositionProtected = true
	end

	-- ʕ •ᴥ•ʔ✿ If it's already skinned by ElvUI, we're done ✿ ʕ •ᴥ•ʔ
	if button.isElvUISkinned then return end

	local pushed = button:GetPushedTexture()
	local normal = button:GetNormalTexture()
	local disabled = button:GetDisabledTexture()

	if not button.backdrop then
		local f = CreateFrame("Frame", nil, button)
		f:SetFrameLevel(button:GetFrameLevel() - 1)
		f:SetTemplate("Default", true)
		f:SetOutside(button)
		button.backdrop = f
	end

	if button.GetHighlightTexture and button:GetHighlightTexture() then
		button:GetHighlightTexture():Kill()
	end
	button:HookScript("OnEnter", onEnter)
	button:HookScript("OnLeave", onLeave)
	button:SetHitRectInsets(0, 0, 0, 0)

	if pushed then
		pushed:SetTexCoord(0.17, 0.87, 0.5, 0.908)
		pushed:SetInside(button.backdrop)
	end

	if normal then
		normal:SetTexCoord(0.17, 0.87, 0.5, 0.908)
		normal:SetInside(button.backdrop)
	end

	if disabled then
		disabled:SetTexCoord(0.17, 0.87, 0.5, 0.908)
		disabled:SetInside(button.backdrop)
	end

	button.isElvUISkinned = true
	button.isSkinned = true
end

function AB:DiscoverExtraMicroButtons()
	-- Grimfall: adopt server-added micro buttons (e.g. the backported Collections button,
	-- which uses a mount icon and belongs by Social / Group Finder) and, if only the journal
	-- frame exists, build a button that opens it.
	local function indexOf(name)
		for i = 1, #MICRO_BUTTONS do
			if MICRO_BUTTONS[i] == name then return i end
		end
	end

	local function addButton(name, afterName)
		if indexOf(name) then return end
		local pos = afterName and indexOf(afterName)
		if pos then
			tinsert(MICRO_BUTTONS, pos + 1, name)
		else
			tinsert(MICRO_BUTTONS, name)
		end
	end

	-- Grimfall: keep the backported Adventure Guide inside the main row, right after
	-- the Collections button, instead of wrapping below Spellbook when it overflows
	-- buttonsPerRow (the generic scan appends it at the end). Runs on every call
	-- because it is cheap and late-arriving buttons must rejoin the row too.
	local function placeAdventureGuide()
		local adventureIdx, collectionsIdx
		for i = 1, #MICRO_BUTTONS do
			local n = strlower(MICRO_BUTTONS[i])
			if not adventureIdx and strfind(n, "adventure", 1, true) then adventureIdx = i end
			if not collectionsIdx and strfind(n, "collection", 1, true) then collectionsIdx = i end
		end
		if adventureIdx and collectionsIdx and adventureIdx ~= collectionsIdx + 1 then
			local adventureName = tremove(MICRO_BUTTONS, adventureIdx)
			if adventureIdx < collectionsIdx then collectionsIdx = collectionsIdx - 1 end
			tinsert(MICRO_BUTTONS, collectionsIdx + 1, adventureName)
		end
	end

	-- Grimfall: adopt known server buttons by exact global even after the first scan,
	-- because other addons create them on their own schedule.
	for _, knownName in ipairs({ "AdventureGuideMicroButton", "Retail_AdventureGuideMicroButton" }) do
		if _G[knownName] then addButton(knownName) end
	end
	placeAdventureGuide()

	-- The pairs() scan below is the expensive part: run it once and latch.
	if self.extraMicroButtonsDone then return end

	for name, obj in pairs(_G) do
		if type(name) == "string" and strfind(name, "MicroButton$") and type(obj) == "table"
			and obj.IsObjectType and obj:IsObjectType("Button") and not indexOf(name) then
			if strfind(strlower(name), "collection") then
				addButton(name, "SocialsMicroButton")
			else
				addButton(name)
			end
		end
	end

	local hasCollections
	for i = 1, #MICRO_BUTTONS do
		if strfind(strlower(MICRO_BUTTONS[i]), "collection") then hasCollections = true break end
	end

	if not hasCollections and _G.Retail_CollectionJournal and not _G.ElvUI_CollectionsMicroButton then
		local b = CreateFrame("Button", "ElvUI_CollectionsMicroButton", ElvUI_Ebonhold_MicroBar)
		b:SetSize(28, 58)
		local icon = b:CreateTexture(nil, "ARTWORK")
		icon:SetTexture([[Interface\Icons\Ability_Mount_RidingHorse]])
		icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
		icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
		icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
		b.icon = icon
		b:SetScript("OnClick", function()
			if type(_G.ToggleCollectionsJournal) == "function" then
				_G.ToggleCollectionsJournal()
			else
				local j = _G.Retail_CollectionJournal
				if j then if j:IsShown() then j:Hide() else j:Show() end end
			end
		end)
		addButton("ElvUI_CollectionsMicroButton", "SocialsMicroButton")
		hasCollections = true
	end

	if not _G.ElvUI_ClasslessMicroButton then
		-- Grimfall: button to toggle the Classless build frame (uses the Destiny's Dice icon)
		local b = CreateFrame("Button", "ElvUI_ClasslessMicroButton", ElvUI_Ebonhold_MicroBar)
		b:SetSize(28, 58)
		local icon = b:CreateTexture(nil, "ARTWORK")
		icon:SetTexture((select(10, GetItemInfo("Destiny's Dice")) or select(10, GetItemInfo("Destiny’s Dice"))) or [[Interface\Icons\INV_Misc_Dice_01]])
		icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
		icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
		icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
		b.icon = icon
		b:SetScript("OnClick", function()
			if type(_G.ClasslessFrame_Toggle) == "function" then
				_G.ClasslessFrame_Toggle()
			end
		end)
		b:HookScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Classless")
			GameTooltip:Show()
		end)
		b:HookScript("OnLeave", function() GameTooltip:Hide() end)
		-- pick up the real (green) Destiny’s Dice icon once item info caches
		b:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		b:SetScript("OnEvent", function(self)
			local tex = select(10, GetItemInfo("Destiny's Dice")) or select(10, GetItemInfo("Destiny’s Dice"))
			if tex then self.icon:SetTexture(tex) self:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
		end)
		addButton("ElvUI_ClasslessMicroButton", "TalentMicroButton")
	end
	placeAdventureGuide()

	if hasCollections then self.extraMicroButtonsDone = true end
end

function AB:UpdateMicroButtonsParent()
	if not ElvUI_Ebonhold_MicroBar then return end

	if InCombatLockdown() then
		AB.NeedsUpdateMicroButtonsParent = true
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end

	self:DiscoverExtraMicroButtons()

	for i = 1, #MICRO_BUTTONS do
		local button = _G[MICRO_BUTTONS[i]]
		if button then
			if button:GetParent() ~= ElvUI_Ebonhold_MicroBar then
				button.elvuiAllowChanges = true
				button:SetParent(ElvUI_Ebonhold_MicroBar)
				button.elvuiAllowChanges = nil
			end
			
			local needsFullSetup = not button.elvuiPositionProtected or not button.elvuiOriginalSetPoint
			if needsFullSetup or not button.isElvUISkinned then
				if needsFullSetup then
					button.elvuiPositionProtected = nil
					button.isElvUISkinned = nil
					button.isSkinned = nil
				end
				self:HandleMicroButton(button)
			end
		end
	end

	AB:UpdateMicroPositionDimensions()
end

function AB:PLAYER_ENTERING_WORLD()
	-- Reseed the shown-slot cache: buttons that are hidden right from the start
	-- (e.g. PVP on this server) must not keep a reserved hole in the bar.
	AB.everShownMicroButtons = {}
	self:UpdateMicroButtonsParent()
end

function AB:UpdateMicroBarVisibility()
	if InCombatLockdown() then
		AB.NeedsUpdateMicroBarVisibility = true
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end

	local visibility = self.db.microbar.visibility
	if visibility and match(visibility, "[\n\r]") then
		visibility = gsub(visibility, "[\n\r]", "")
	end

	RegisterStateDriver(ElvUI_Ebonhold_MicroBar.visibility, "visibility", (self.db.microbar.enabled and visibility) or "hide")
end

function AB:UpdateMicroPositionDimensions()
	if not ElvUI_Ebonhold_MicroBar then return end

	if InCombatLockdown() then
		AB.NeedsUpdateMicroPositionDimensions = true
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end

	local numRows = 1
	local prevButton = ElvUI_Ebonhold_MicroBar
	local offset = E:Scale(E.PixelMode and 1 or 3)
	local spacing = E:Scale(offset + self.db.microbar.buttonSpacing)
	local buttonsPerRow = self.db.microbar.buttonsPerRow

	local buttons = {}
	for i = 1, #MICRO_BUTTONS do
		local name = MICRO_BUTTONS[i]
		local button = _G[name]
		if button then
			if button:GetParent() ~= ElvUI_Ebonhold_MicroBar then
				button.elvuiAllowChanges = true
				button:SetParent(ElvUI_Ebonhold_MicroBar)
				button.elvuiAllowChanges = nil
			end
			
			local needsFullSetup = not button.elvuiPositionProtected or not button.elvuiOriginalSetPoint
			if needsFullSetup then
				button.elvuiPositionProtected = nil
				button.isElvUISkinned = nil
				button.isSkinned = nil
				self:HandleMicroButton(button)
			end
			
			-- Stable slots: keep every button that is shown now or was shown before in
			-- its MICRO_BUTTONS slot even while Blizzard transiently hides it (e.g. LFD
			-- while the group finder frame is open), so reflows never move buttons on
			-- click. Buttons never observed shown (e.g. PVP on this server) are collapsed
			-- instead of leaving a permanent hole between Collections and Group Finder.
			AB.everShownMicroButtons = AB.everShownMicroButtons or {}
			if button:IsShown() then
				AB.everShownMicroButtons[name] = true
			end
			if AB.everShownMicroButtons[name] then
				buttons[#buttons + 1] = button
			end
		end
	end

	-- Grimfall: this fork ships more micro buttons than the stock 12-per-row cap, so
	-- keep everything on one row unless the user configured an even larger layout.
	if buttonsPerRow < #buttons then buttonsPerRow = #buttons end

	for i = 1, #buttons do
		local button = buttons[i]
		local lastColumnButton = i - buttonsPerRow
		lastColumnButton = buttons[lastColumnButton]

		button.elvuiAllowChanges = true
		button:Size(self.db.microbar.buttonSize, self.db.microbar.buttonSize * 1.4)
		button:ClearAllPoints()

		if prevButton == ElvUI_Ebonhold_MicroBar then
			button:Point("TOPLEFT", prevButton, "TOPLEFT", offset, -offset)
		elseif (i - 1) % buttonsPerRow == 0 then
			button:Point("TOP", lastColumnButton, "BOTTOM", 0, -spacing)
			numRows = numRows + 1
		else
			button:Point("LEFT", prevButton, "RIGHT", spacing, 0)
		end
		button.elvuiAllowChanges = nil

		prevButton = button
	end

	if AB.db.microbar.mouseover and not ElvUI_Ebonhold_MicroBar:IsMouseOver() then
		ElvUI_Ebonhold_MicroBar:SetAlpha(0)
	else
		ElvUI_Ebonhold_MicroBar:SetAlpha(self.db.microbar.alpha)
	end

	local numButtons = #buttons
	if numButtons == 0 then
		ElvUI_Ebonhold_MicroBar:Size(0, 0)
		return
	end

	local numColumns = (numRows > 1) and buttonsPerRow or numButtons
	local buttonWidth = self.db.microbar.buttonSize
	local buttonHeight = buttonWidth * 1.4

	AB.MicroWidth = (((buttonWidth + spacing) * numColumns) - spacing) + (offset * 2)
	AB.MicroHeight = (((buttonHeight + spacing) * numRows) - spacing) + (offset * 2)
	ElvUI_Ebonhold_MicroBar:Size(AB.MicroWidth, AB.MicroHeight)

	if ElvUI_Ebonhold_MicroBar.mover then
		ElvUI_Ebonhold_MicroBar.mover:Size(ElvUI_Ebonhold_MicroBar:GetSize())
		ElvUI_Ebonhold_MicroBar.isSettingPosition = true
		ElvUI_Ebonhold_MicroBar:ClearAllPoints()
		ElvUI_Ebonhold_MicroBar:Point("TOPLEFT", ElvUI_Ebonhold_MicroBar.mover, "TOPLEFT")
		ElvUI_Ebonhold_MicroBar.isSettingPosition = nil
	end

	if ElvUI_Ebonhold_MicroBar.mover then
		if self.db.microbar.enabled then
			E:EnableMover(ElvUI_Ebonhold_MicroBar.mover:GetName())
		else
			E:DisableMover(ElvUI_Ebonhold_MicroBar.mover:GetName())
		end
	end

	self:UpdateMicroBarVisibility()
end

function AB:SetupMicroBar()
	if ElvUI_Ebonhold_MicroBar then return end

	local microBar = CreateFrame("Frame", "ElvUI_Ebonhold_MicroBar", E.UIParent)
	microBar:Point("TOPLEFT", E.UIParent, "TOPLEFT", 4, -48)
	microBar:SetFrameStrata("LOW")
	microBar:EnableMouse(true)
	microBar:SetClampedToScreen(true)
	microBar:SetScript("OnEnter", onEnter)
	microBar:SetScript("OnLeave", onLeave)

	local originalMicroBarSetPoint = microBar.SetPoint
	microBar.SetPoint = function(self, ...)
		if InCombatLockdown() and not self.isSettingPosition then
			return
		end
		originalMicroBarSetPoint(self, ...)
	end

	local originalMicroBarClearAllPoints = microBar.ClearAllPoints
	microBar.ClearAllPoints = function(self)
		if InCombatLockdown() and not self.isSettingPosition then
			return
		end
		originalMicroBarClearAllPoints(self)
	end

	microBar.visibility = CreateFrame("Frame", nil, E.UIParent, "SecureHandlerStateTemplate")
	microBar.visibility:SetScript("OnShow", function() microBar:Show() end)
	microBar.visibility:SetScript("OnHide", function() microBar:Hide() end)

	for i = 1, #MICRO_BUTTONS do
		local button = _G[MICRO_BUTTONS[i]]
		if button then
			self:HandleMicroButton(button)
		end
	end

	MicroButtonPortrait:SetAllPoints()

	-- PvP Micro Button
	PVPMicroButtonTexture:SetAllPoints()
	PVPMicroButtonTexture:SetTexture([[Interface\AddOns\ElvUI\Media\Textures\PVP-Icons]])

	if E.myfaction == "Alliance" then
		PVPMicroButtonTexture:SetTexCoord(0.545, 0.935, 0.070, 0.940)
	else
		PVPMicroButtonTexture:SetTexCoord(0.100, 0.475, 0.070, 0.940)
	end

	self:SecureHook("VehicleMenuBar_MoveMicroButtons", "UpdateMicroButtonsParent")
	if _G.MoveMicroButtons then
		self:SecureHook("MoveMicroButtons", "UpdateMicroButtonsParent")
	end
	if _G.UpdateMicroButtons then
		self:SecureHook("UpdateMicroButtons", "UpdateMicroButtonsParent")
	end

	self:RegisterEvent("PLAYER_ENTERING_WORLD")

	-- ʕ •ᴥ•ʔ✿ Delay updates to catch late-loading server buttons and override other addons ✿ ʕ •ᴥ•ʔ
	E:Delay(1, AB.UpdateMicroButtonsParent, AB)
	E:Delay(5, AB.UpdateMicroButtonsParent, AB)

	self:UpdateMicroPositionDimensions()
	MainMenuBarPerformanceBar:Kill()

	E:CreateMover(microBar, "MicrobarMover", L["Micro Bar"], nil, nil, nil, "ALL,ACTIONBARS", nil, "actionbar,microbar")
end