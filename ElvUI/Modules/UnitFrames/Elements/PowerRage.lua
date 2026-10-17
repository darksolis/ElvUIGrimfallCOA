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

local function UpdateCustomRage(self, event, unit)
	if event == "PLAYER_TARGET_CHANGED" then unit = "target" end
	if event == "PLAYER_FOCUS_CHANGED" then unit = "focus" end
	if not unit then unit = self.unit end
	
	if self.unit ~= unit then return end
	
	self.Rage:SetValue(UnitPower(unit, 1) or 0)
	if self.Rage.PostUpdate then self.Rage:PostUpdate(unit) end
end

local function UpdateCustomMaxRage(self, event, unit)
	if event == "PLAYER_TARGET_CHANGED" then unit = "target" end
	if event == "PLAYER_FOCUS_CHANGED" then unit = "focus" end
	if not unit then unit = self.unit end
	
	if self.unit ~= unit then return end
	
	local max = UnitPowerMax(unit, 1)
	if not max or max == 0 then max = 100 end
	
	self.Rage.max = max
	self.Rage:SetMinMaxValues(0, max)
	if self.Rage.PostUpdate then self.Rage:PostUpdate(unit) end
end

function UF:Construct_RageBar(frame, bg, text, textPos)
	local rage = CreateFrame("StatusBar", nil, frame)
	UF.statusbars[rage] = true

	rage.RaisedElementParent = CreateFrame("Frame", nil, rage)
	rage.RaisedElementParent:SetFrameLevel(rage:GetFrameLevel() + 100)
	rage.RaisedElementParent:SetAllPoints()

	rage.PostUpdate = self.PostUpdateRage
	rage.PostUpdateColor = self.PostUpdateRageColor

	if bg then
		rage.BG = rage:CreateTexture(nil, "BORDER")
		rage.BG:SetAllPoints()
		rage.BG:SetTexture(E.media.blankTex)
	end

	if text then
		local anchorPoint = (type(textPos) == "string" and validPoints[textPos]) and textPos or "CENTER"
		rage.value = frame.RaisedElementParent:CreateFontString(nil, "OVERLAY")
		UF:Configure_FontString(rage.value)
		rage.value:Point(anchorPoint, rage, anchorPoint, -2, 0)
		rage.value.frequentUpdates = true
		rage.value:Hide()
	end

	rage.colorDisconnected = false
	rage.colorTapping = false
	rage:CreateBackdrop("Default", nil, nil, self.thinBorders, true)

	local clipFrame = CreateFrame('Frame', nil, rage)
	clipFrame:SetAllPoints()
	clipFrame:EnableMouse(false)
	clipFrame.__frame = frame
	rage.ClipFrame = clipFrame
	
	rage:Hide()

	return rage
end

function UF:Configure_Rage(frame)
	if not frame.VARIABLES_SET then return end
	if not frame.Rage then return end

	local db = frame.db


	if frame.unitframeType == "player" then
		frame.USE_RAGEBAR = IsHero() and db.rage and db.rage.enable
	else
		frame.USE_RAGEBAR = db.rage and db.rage.enable
	end

	local rage = frame.Rage
	rage.origParent = frame

	if frame.USE_RAGEBAR then
		if not frame:IsElementEnabled("Rage") then
			frame:EnableElement("Rage")
		end
		
		rage:Show()
		if rage.value then rage.value:Show() end

		local unit = frame.unit or "player"
		local max = UnitPowerMax(unit, 1)
		if not max or max == 0 then max = 100 end
		local cur = UnitPower(unit, 1) or 0

		rage.max = max
		rage:SetMinMaxValues(0, max)
		rage:SetValue(cur)

		frame:RegisterEvent("UNIT_RAGE", UpdateCustomRage)
		frame:RegisterEvent("UNIT_MAXRAGE", UpdateCustomMaxRage)

		if frame.unit == "target" then
			frame:RegisterEvent("PLAYER_TARGET_CHANGED", UpdateCustomRage)
			frame:RegisterEvent("PLAYER_TARGET_CHANGED", UpdateCustomMaxRage)
		elseif frame.unit == "focus" then
			frame:RegisterEvent("PLAYER_FOCUS_CHANGED", UpdateCustomRage)
			frame:RegisterEvent("PLAYER_FOCUS_CHANGED", UpdateCustomMaxRage)
		end
	else
		if frame:IsElementEnabled("Rage") then
			frame:DisableElement("Rage")
		end
		
		rage:Hide()
		if rage.value then
			rage.value:Hide()
			frame:Tag(rage.value, "")
		end

		frame:UnregisterEvent("UNIT_RAGE", UpdateCustomRage)
		frame:UnregisterEvent("UNIT_MAXRAGE", UpdateCustomMaxRage)

		if frame.unit == "target" then
			frame:UnregisterEvent("PLAYER_TARGET_CHANGED", UpdateCustomRage)
			frame:UnregisterEvent("PLAYER_TARGET_CHANGED", UpdateCustomMaxRage)
		elseif frame.unit == "focus" then
			frame:UnregisterEvent("PLAYER_FOCUS_CHANGED", UpdateCustomRage)
			frame:UnregisterEvent("PLAYER_FOCUS_CHANGED", UpdateCustomMaxRage)
		end
		return
	end

	E:SetSmoothing(rage, self.db.smoothbars)

	local anchor = frame.Health
	if frame.USE_POWERBAR and not frame.USE_POWERBAR_DETACHED and not frame.USE_INSET_POWERBAR and not frame.USE_MINI_POWERBAR then
		anchor = frame.Power
	end
	

	if frame.USE_ENERGYBAR and frame.Energy and frame.Energy:IsShown() then
		anchor = frame.Energy
	end

	rage:ClearAllPoints()
	if rage.value then rage.value:ClearAllPoints() end
	rage:SetWidth(frame.UNIT_WIDTH - (frame.BORDER * 2))

	local barHeight = db.rage and db.rage.height or 10
	rage:SetHeight(barHeight - (frame.BORDER + frame.SPACING) * 2)

	local xOffset = db.rage and db.rage.xOffset or 0
	local yOffset = db.rage and db.rage.yOffset or 0

	rage:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", xOffset, -yOffset - frame.SPACING)
	rage:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", xOffset, -yOffset - frame.SPACING)
	rage:SetFrameLevel(anchor:GetFrameLevel() + 2)

	if rage.value and db.rage then
		local attachPoint = self:GetObjectAnchorPoint(frame, db.rage.attachTextTo)
		local rawPos = db.rage.position
		local tPos = (type(rawPos) == "string" and validPoints[rawPos]) and rawPos or "CENTER"

		rage.value:SetPoint(tPos, attachPoint or rage, tPos, 0, 0)
		frame:Tag(rage.value, db.rage.text_format or "")

		if db.rage.colors and db.rage.colors.enable and db.rage.colors.color then
			rage.value:SetTextColor(
				db.rage.colors.color.r or 1,
				db.rage.colors.color.g or 1,
				db.rage.colors.color.b or 1,
				db.rage.colors.color.a or 1
			)
		else
			rage.value:SetTextColor(1, 1, 1, 1)
		end
	end

	local strataData = db.rage and db.rage.strataAndLevel or {}
	if strataData.useCustomStrata then
		rage:SetFrameStrata(strataData.frameStrata or "LOW")
	else
		rage:SetFrameStrata("LOW")
	end

	if strataData.useCustomLevel then
		rage:SetFrameLevel(strataData.frameLevel or 1)
		rage.backdrop:SetFrameLevel(rage:GetFrameLevel() - 1)
	end

	if frame.RAGEBAR_DETACHED and db.rage and db.rage.parent == "UIPARENT" then
		rage:SetParent(E.UIParent)
	else
		rage:SetParent(frame)
	end

	rage.custom_backdrop = UF.db.colors.customragebackdrop and UF.db.colors.rage_backdrop
	UF:ToggleTransparentStatusBar(UF.db.colors.transparentRage, rage, rage.BG, nil, UF.db.colors.invertRage)		
	UF:PostUpdateRageColor(rage)
end

function UF:PostUpdateRageColor(rageBar)
	local rage = rageBar or self
	local r, g, b = 0.78, 0.25, 0.25
	

	if ElvUF.colors and ElvUF.colors.power then
		local c = ElvUF.colors.power["RAGE"] or ElvUF.colors.power[1]
		if c and type(c.r) == "number" then r, g, b = c.r, c.g, c.b end
	end
	
	rage:SetStatusBarColor(r, g, b)
	if rage.BG and UF.UpdateBackdropTextureColor then
		UF:UpdateBackdropTextureColor(rage.BG, r, g, b)
	end

	if rage.origParent and rage.origParent.isForced then
		rage:SetValue(random(1, rage.max or 100))
	end
end

function UF:PostUpdateRage(unit)
	local parent = self.origParent or self:GetParent()
	if parent.isForced then self:SetValue(random(1, self.max or 100)) end
end