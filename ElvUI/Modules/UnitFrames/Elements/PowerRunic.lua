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

local function UpdateCustomRunicFromRunePowerUpdate(self, event)
	if not self.USE_RUNICBAR or not self.Runic then return end
	self.Runic:SetValue(UnitPower(self.unit, 6) or 0)
	if self.Runic.PostUpdate then self.Runic:PostUpdate(self.unit) end
end

-- local function UpdateCustomRunicFromPowerUpdate(self, event, unit, powerType)
	-- if powerType ~= "RUNIC_POWER" then return end
	-- if not unit then unit = self.unit end
	-- if self.unit ~= unit then return end

	-- self.Runic:SetValue(UnitPower(unit, 6) or 0)
	-- if self.Runic.PostUpdate then self.Runic:PostUpdate(unit) end
-- end


local function UpdateCustomRunic(self, event, unit)
	if event == "PLAYER_TARGET_CHANGED" then unit = "target" end
	if event == "PLAYER_FOCUS_CHANGED" then unit = "focus" end
	if not unit then unit = self.unit end
	if self.unit ~= unit then return end
	
	self.Runic:SetValue(UnitPower(unit, 6) or 0)
	if self.Runic.PostUpdate then self.Runic:PostUpdate(unit) end
end

local function UpdateCustomMaxRunic(self, event, unit)
	if event == "PLAYER_TARGET_CHANGED" then unit = "target" end
	if event == "PLAYER_FOCUS_CHANGED" then unit = "focus" end
	if not unit then unit = self.unit end
	if self.unit ~= unit then return end
	
	local max = UnitPowerMax(unit, 6)
	if not max or max == 0 then max = 100 end
	
	self.Runic.max = max
	self.Runic:SetMinMaxValues(0, max)
	if self.Runic.PostUpdate then self.Runic:PostUpdate(unit) end
end

function UF:Construct_RunicBar(frame, bg, text, textPos)
	local runic = CreateFrame("StatusBar", nil, frame)
	UF.statusbars[runic] = true

	runic.RaisedElementParent = CreateFrame("Frame", nil, runic)
	runic.RaisedElementParent:SetFrameLevel(runic:GetFrameLevel() + 100)
	runic.RaisedElementParent:SetAllPoints()

	runic.PostUpdate = self.PostUpdateRunic
	runic.PostUpdateColor = self.PostUpdateRunicColor

	if bg then
		runic.BG = runic:CreateTexture(nil, "BORDER")
		runic.BG:SetAllPoints()
		runic.BG:SetTexture(E.media.blankTex)
	end

	if text then
		local anchorPoint = (type(textPos) == "string" and validPoints[textPos]) and textPos or "CENTER"
		runic.value = frame.RaisedElementParent:CreateFontString(nil, "OVERLAY")
		UF:Configure_FontString(runic.value)
		runic.value:Point(anchorPoint, runic, anchorPoint, -2, 0)
		runic.value.frequentUpdates = true
		runic.value:Hide()
	end

	runic.colorDisconnected = false
	runic.colorTapping = false
	runic:CreateBackdrop("Default", nil, nil, self.thinBorders, true)

	local clipFrame = CreateFrame('Frame', nil, runic)
	clipFrame:SetAllPoints()
	clipFrame:EnableMouse(false)
	clipFrame.__frame = frame
	runic.ClipFrame = clipFrame
	runic:Hide()

	return runic
end

function UF:Configure_Runic(frame)
	if not frame.VARIABLES_SET then return end
	if not frame.Runic then return end

	local db = frame.db

	if frame.unitframeType == "player" then
		frame.USE_RUNICBAR = IsHero() and db.runic and db.runic.enable
	else
		frame.USE_RUNICBAR = db.runic and db.runic.enable
	end

	local runic = frame.Runic
	runic.origParent = frame

	if frame.USE_RUNICBAR then
		if not frame:IsElementEnabled("Runic") then
			frame:EnableElement("Runic")
		end
		
		runic:Show()
		if runic.value then runic.value:Show() end

		local unit = frame.unit or "player"
		local max = UnitPowerMax(unit, 6)
		if not max or max == 0 then max = 100 end
		local cur = UnitPower(unit, 6) or 0

		runic.max = max
		runic:SetMinMaxValues(0, max)
		runic:SetValue(cur)

		frame:RegisterEvent("UNIT_RUNIC_POWER", UpdateCustomRunic)
		frame:RegisterEvent("UNIT_MAXRUNIC_POWER", UpdateCustomMaxRunic)
		frame:RegisterEvent("RUNE_POWER_UPDATE", UpdateCustomRunicFromRunePowerUpdate)
		--frame:RegisterEvent("UNIT_POWER_UPDATE", UpdateCustomRunicFromPowerUpdate)
		
		if frame.unit == "target" then
			frame:RegisterEvent("PLAYER_TARGET_CHANGED", UpdateCustomRunic)
			frame:RegisterEvent("PLAYER_TARGET_CHANGED", UpdateCustomMaxRunic)
		elseif frame.unit == "focus" then
			frame:RegisterEvent("PLAYER_FOCUS_CHANGED", UpdateCustomRunic)
			frame:RegisterEvent("PLAYER_FOCUS_CHANGED", UpdateCustomMaxRunic)
		end
	else
		if frame:IsElementEnabled("Runic") then
			frame:DisableElement("Runic")
		end
		runic:Hide()
		if runic.value then 
			runic.value:Hide() 
			frame:Tag(runic.value, "")
		end
		
		frame:UnregisterEvent("UNIT_RUNIC_POWER", UpdateCustomRunic)
		frame:UnregisterEvent("UNIT_MAXRUNIC_POWER", UpdateCustomMaxRunic)
		frame:UnregisterEvent("RUNE_POWER_UPDATE", UpdateCustomRunicFromRunePowerUpdate)
		--frame:UnregisterEvent("UNIT_POWER_UPDATE", UpdateCustomRunicFromPowerUpdate)
		
		if frame.unit == "target" then
			frame:UnregisterEvent("PLAYER_TARGET_CHANGED", UpdateCustomRunic)
			frame:UnregisterEvent("PLAYER_TARGET_CHANGED", UpdateCustomMaxRunic)
		elseif frame.unit == "focus" then
			frame:UnregisterEvent("PLAYER_FOCUS_CHANGED", UpdateCustomRunic)
			frame:UnregisterEvent("PLAYER_FOCUS_CHANGED", UpdateCustomMaxRunic)
		end
		return
	end

	E:SetSmoothing(runic, self.db.smoothbars)

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
	if frame.USE_MANABAR and frame.Mana and frame.Mana:IsShown() then
		anchor = frame.Mana
	end

	runic:ClearAllPoints()
	if runic.value then runic.value:ClearAllPoints() end
	runic:SetWidth(frame.UNIT_WIDTH - (frame.BORDER * 2))
	
	local barHeight = (db.runic and db.runic.height) or 10
	runic:SetHeight(barHeight - (frame.BORDER + frame.SPACING) * 2)
	
	local xOffset = (db.runic and db.runic.xOffset) or 0
	local yOffset = (db.runic and db.runic.yOffset) or 0

	runic:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", xOffset, -yOffset - frame.SPACING)
	runic:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", xOffset, -yOffset - frame.SPACING)
	runic:SetFrameLevel(anchor:GetFrameLevel() + 2)

	if runic.value and db.runic then
		local attachPoint = self:GetObjectAnchorPoint(frame, db.runic.attachTextTo)
		local rawPos = db.runic.position
		local tPos = (type(rawPos) == "string" and validPoints[rawPos]) and rawPos or "CENTER"
		
		runic.value:SetPoint(tPos, attachPoint or runic, tPos, 0, 0)
		frame:Tag(runic.value, db.runic.text_format or "")

		if db.runic.colors and db.runic.colors.enable and db.runic.colors.color then
			runic.value:SetTextColor(
				db.runic.colors.color.r or 1, 
				db.runic.colors.color.g or 1, 
				db.runic.colors.color.b or 1, 
				db.runic.colors.color.a or 1
			)
		else
			runic.value:SetTextColor(1, 1, 1, 1)
		end
	end

	local strataData = (db.runic and db.runic.strataAndLevel) or {}
	if strataData.useCustomStrata then 
		runic:SetFrameStrata(strataData.frameStrata or "LOW")
	else 
		runic:SetFrameStrata("LOW") 
	end
	
	if strataData.useCustomLevel then
		runic:SetFrameLevel(strataData.frameLevel or 1)
		runic.backdrop:SetFrameLevel(runic:GetFrameLevel() - 1)
	end

	if frame.RUNICBAR_DETACHED and db.runic and db.runic.parent == "UIPARENT" then 
		runic:SetParent(E.UIParent)
	else 
		runic:SetParent(frame) 
	end

	runic.custom_backdrop = UF.db.colors.customrunicbackdrop and UF.db.colors.runic_backdrop
	UF:ToggleTransparentStatusBar(UF.db.colors.transparentRunic, runic, runic.BG, nil, UF.db.colors.invertRunic)	
	UF:PostUpdateRunicColor(runic)
end

function UF:PostUpdateRunicColor(runicBar)
	local runic = runicBar or self
	local r, g, b = 0, 0.82, 1
	--local r, g, b = 0, 0.3, 0.2
	if ElvUF.colors and ElvUF.colors.power then
		local c = ElvUF.colors.power["RUNIC_POWER"] or ElvUF.colors.power[6]
		if c and type(c.r) == "number" then r, g, b = c.r, c.g, c.b end
	end

	runic:SetStatusBarColor(r, g, b)
	if runic.BG and UF.UpdateBackdropTextureColor then
		UF:UpdateBackdropTextureColor(runic.BG, r, g, b)
	end

	if runic.origParent and runic.origParent.isForced then
		runic:SetValue(random(1, runic.max or 100))
	end
end

function UF:PostUpdateRunic(unit)
	local parent = self.origParent or self:GetParent()
	if parent.isForced then
		self:SetValue(random(1, self.max or 100))
	end
end