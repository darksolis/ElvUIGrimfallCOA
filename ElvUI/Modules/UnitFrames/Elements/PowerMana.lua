local E, L, V, P, G = unpack(select(2, ...));
local UF = E:GetModule("UnitFrames")

local random = random
local type = type
local CreateFrame = CreateFrame
local UnitClass = UnitClass
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax

local _, ns = ...
local ElvUF = ns.oUF
assert(ElvUF, "ElvUI was unable to locate oUF.")

local validPoints = {
	["TOP"] = true, ["BOTTOM"] = true, ["LEFT"] = true, ["RIGHT"] = true,
	["TOPLEFT"] = true, ["TOPRIGHT"] = true, ["BOTTOMLEFT"] = true, ["BOTTOMRIGHT"] = true,
	["CENTER"] = true
}

local function IsHero()
	local locClass, tokenClass = UnitClass("player")
	return E.myclass == "Hero" or E.myclass == "HERO" or locClass == "Hero" or tokenClass == "Hero"
end

local function UpdateCustomMana(self, event, unit)
	if event == "PLAYER_TARGET_CHANGED" then unit = "target" end
	if event == "PLAYER_FOCUS_CHANGED" then unit = "focus" end
	if not unit then unit = self.unit end
	if self.unit ~= unit then return end
	
	self.Mana:SetValue(UnitPower(unit, 0) or 0)
	if self.Mana.PostUpdate then self.Mana:PostUpdate(unit) end
end

local function UpdateCustomMaxMana(self, event, unit)
	if event == "PLAYER_TARGET_CHANGED" then unit = "target" end
	if event == "PLAYER_FOCUS_CHANGED" then unit = "focus" end
	if not unit then unit = self.unit end
	if self.unit ~= unit then return end
	
	local max = UnitPowerMax(unit, 0)
	if not max or max == 0 then max = 100 end
	
	self.Mana.max = max
	self.Mana:SetMinMaxValues(0, max)
	if self.Mana.PostUpdate then self.Mana:PostUpdate(unit) end
end

function UF:Construct_ManaBar(frame, bg, text, textPos)
	local mana = CreateFrame("StatusBar", nil, frame)
	UF.statusbars[mana] = true

	mana.RaisedElementParent = CreateFrame("Frame", nil, mana)
	mana.RaisedElementParent:SetFrameLevel(mana:GetFrameLevel() + 100)
	mana.RaisedElementParent:SetAllPoints()

	mana.PostUpdate = self.PostUpdateMana
	mana.PostUpdateColor = self.PostUpdateManaColor

	if bg then
		mana.BG = mana:CreateTexture(nil, "BORDER")
		mana.BG:SetAllPoints()
		mana.BG:SetTexture(E.media.blankTex)
	end

	if text then
		local anchorPoint = (type(textPos) == "string" and validPoints[textPos]) and textPos or "CENTER"
		mana.value = frame.RaisedElementParent:CreateFontString(nil, "OVERLAY")
		UF:Configure_FontString(mana.value)
		mana.value:Point(anchorPoint, mana, anchorPoint, -2, 0)
		mana.value.frequentUpdates = true
		mana.value:Hide()
	end

	mana.colorDisconnected = false
	mana.colorTapping = false
	mana:CreateBackdrop("Default", nil, nil, self.thinBorders, true)

	local clipFrame = CreateFrame('Frame', nil, mana)
	clipFrame:SetAllPoints()
	clipFrame:EnableMouse(false)
	clipFrame.__frame = frame
	mana.ClipFrame = clipFrame
	mana:Hide()

	return mana
end

function UF:Configure_Mana(frame)
	if not frame.VARIABLES_SET then return end
	if not frame.Mana then return end

	local db = frame.db

	if frame.unitframeType == "player" then
		frame.USE_MANABAR = IsHero() and db.mana and db.mana.enable
	else
		frame.USE_MANABAR = db.mana and db.mana.enable
	end

	local mana = frame.Mana
	mana.origParent = frame

	if frame.USE_MANABAR then
		if not frame:IsElementEnabled("Mana") then
			frame:EnableElement("Mana")
		end
		
		mana:Show()
		if mana.value then mana.value:Show() end

		local unit = frame.unit or "player"
		local max = UnitPowerMax(unit, 0)
		if not max or max == 0 then max = 100 end
		local cur = UnitPower(unit, 0) or 0

		mana.max = max
		mana:SetMinMaxValues(0, max)
		mana:SetValue(cur)

		frame:RegisterEvent("UNIT_MANA", UpdateCustomMana)
		frame:RegisterEvent("UNIT_MAXMANA", UpdateCustomMaxMana)
		
		if frame.unit == "target" then
			frame:RegisterEvent("PLAYER_TARGET_CHANGED", UpdateCustomMana)
			frame:RegisterEvent("PLAYER_TARGET_CHANGED", UpdateCustomMaxMana)
		elseif frame.unit == "focus" then
			frame:RegisterEvent("PLAYER_FOCUS_CHANGED", UpdateCustomMana)
			frame:RegisterEvent("PLAYER_FOCUS_CHANGED", UpdateCustomMaxMana)
		end
	else
		if frame:IsElementEnabled("Mana") then
			frame:DisableElement("Mana")
		end
		mana:Hide()
		if mana.value then 
			mana.value:Hide() 
			frame:Tag(mana.value, "")
		end
		
		frame:UnregisterEvent("UNIT_MANA", UpdateCustomMana)
		frame:UnregisterEvent("UNIT_MAXMANA", UpdateCustomMaxMana)
		
		if frame.unit == "target" then
			frame:UnregisterEvent("PLAYER_TARGET_CHANGED", UpdateCustomMana)
			frame:UnregisterEvent("PLAYER_TARGET_CHANGED", UpdateCustomMaxMana)
		elseif frame.unit == "focus" then
			frame:UnregisterEvent("PLAYER_FOCUS_CHANGED", UpdateCustomMana)
			frame:UnregisterEvent("PLAYER_FOCUS_CHANGED", UpdateCustomMaxMana)
		end
		return
	end

	E:SetSmoothing(mana, self.db.smoothbars)

	local anchor = frame.Health
	if frame.USE_POWERBAR and not frame.USE_POWERBAR_DETACHED and not frame.USE_INSET_POWERBAR and not frame.USE_MINI_POWERBAR then
		anchor = frame.Power
	end
	if frame.USE_ENERGYBAR and frame.Energy and frame.Energy:IsShown() then
		anchor = frame.Energy
	end
	if frame.USE_RAGEBAR and frame.Rage and frame.Rage:IsShown() then
		anchor = frame.Rage
	end

	mana:ClearAllPoints()
	if mana.value then mana.value:ClearAllPoints() end
	mana:SetWidth(frame.UNIT_WIDTH - (frame.BORDER * 2))
	
	local barHeight = (db.mana and db.mana.height) or 10
	mana:SetHeight(barHeight - (frame.BORDER + frame.SPACING) * 2)
	
	local xOffset = (db.mana and db.mana.xOffset) or 0
	local yOffset = (db.mana and db.mana.yOffset) or 0

	mana:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", xOffset, -yOffset - frame.SPACING)
	mana:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", xOffset, -yOffset - frame.SPACING)
	mana:SetFrameLevel(anchor:GetFrameLevel() + 2)

	if mana.value and db.mana then
		local attachPoint = self:GetObjectAnchorPoint(frame, db.mana.attachTextTo)
		local rawPos = db.mana.position
		local tPos = (type(rawPos) == "string" and validPoints[rawPos]) and rawPos or "CENTER"
		
		mana.value:SetPoint(tPos, attachPoint or mana, tPos, 0, 0)
		frame:Tag(mana.value, db.mana.text_format or "")

		if db.mana.colors and db.mana.colors.enable and db.mana.colors.color then
			mana.value:SetTextColor(
				db.mana.colors.color.r or 1, 
				db.mana.colors.color.g or 1, 
				db.mana.colors.color.b or 1, 
				db.mana.colors.color.a or 1
			)
		else
			mana.value:SetTextColor(1, 1, 1, 1)
		end
	end

	local strataData = (db.mana and db.mana.strataAndLevel) or {}
	if strataData.useCustomStrata then 
		mana:SetFrameStrata(strataData.frameStrata or "LOW")
	else 
		mana:SetFrameStrata("LOW") 
	end
	
	if strataData.useCustomLevel then
		mana:SetFrameLevel(strataData.frameLevel or 1)
		mana.backdrop:SetFrameLevel(mana:GetFrameLevel() - 1)
	end

	if frame.MANABAR_DETACHED and db.mana and db.mana.parent == "UIPARENT" then 
		mana:SetParent(E.UIParent)
	else 
		mana:SetParent(frame) 
	end

	mana.custom_backdrop = UF.db.colors.custommanabackdrop and UF.db.colors.mana_backdrop
	UF:ToggleTransparentStatusBar(UF.db.colors.transparentMana, mana, mana.BG, nil, UF.db.colors.invertMana)
	UF:PostUpdateManaColor(mana)
end

function UF:PostUpdateManaColor(manaBar)
	local mana = manaBar or self
	local r, g, b = 0.31, 0.45, 0.63

	if ElvUF.colors and ElvUF.colors.power then
		local c = ElvUF.colors.power["MANA"] or ElvUF.colors.power[0]
		if c and type(c.r) == "number" then r, g, b = c.r, c.g, c.b end
	end

	mana:SetStatusBarColor(r, g, b)
	if mana.BG and UF.UpdateBackdropTextureColor then
		UF:UpdateBackdropTextureColor(mana.BG, r, g, b)
	end

	if mana.origParent and mana.origParent.isForced then
		mana:SetValue(random(1, mana.max or 100))
	end
end

function UF:PostUpdateMana(unit)
	local parent = self.origParent or self:GetParent()
	if parent.isForced then
		self:SetValue(random(1, self.max or 100))
	end
end