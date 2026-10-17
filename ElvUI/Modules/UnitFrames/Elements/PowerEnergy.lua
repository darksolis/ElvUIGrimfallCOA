
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

local function UpdateCustomEnergy(self, event, unit)
	if event == "PLAYER_TARGET_CHANGED" then unit = "target" end
	if event == "PLAYER_FOCUS_CHANGED" then unit = "focus" end
	if not unit then unit = self.unit end
	
	if self.unit ~= unit then return end
	
	self.Energy:SetValue(UnitPower(unit, 3) or 0)
	if self.Energy.PostUpdate then self.Energy:PostUpdate(unit) end
end

local function UpdateCustomMaxEnergy(self, event, unit)
	if event == "PLAYER_TARGET_CHANGED" then unit = "target" end
	if event == "PLAYER_FOCUS_CHANGED" then unit = "focus" end
	if not unit then unit = self.unit end
	
	if self.unit ~= unit then return end
	
	local max = UnitPowerMax(unit, 3)
	if not max or max == 0 then max = 100 end
	
	self.Energy.max = max
	self.Energy:SetMinMaxValues(0, max)
	if self.Energy.PostUpdate then self.Energy:PostUpdate(unit) end
end

function UF:Construct_EnergyBar(frame, bg, text, textPos)
	local energy = CreateFrame("StatusBar", nil, frame)
	UF.statusbars[energy] = true

	energy.RaisedElementParent = CreateFrame("Frame", nil, energy)
	energy.RaisedElementParent:SetFrameLevel(energy:GetFrameLevel() + 100)
	energy.RaisedElementParent:SetAllPoints()

	energy.PostUpdate = self.PostUpdateEnergy
	energy.PostUpdateColor = self.PostUpdateEnergyColor

	if bg then
		energy.BG = energy:CreateTexture(nil, "BORDER")
		energy.BG:SetAllPoints()
		energy.BG:SetTexture(E.media.blankTex)
	end

	if text then
		local anchorPoint = (type(textPos) == "string" and validPoints[textPos]) and textPos or "CENTER"
		energy.value = frame.RaisedElementParent:CreateFontString(nil, "OVERLAY")
		UF:Configure_FontString(energy.value)
		energy.value:Point(anchorPoint, energy, anchorPoint, -2, 0)
		energy.value.frequentUpdates = true
		energy.value:Hide()
	end

	energy.colorDisconnected = false
	energy.colorTapping = false
	energy:CreateBackdrop("Default", nil, nil, self.thinBorders, true)

	local clipFrame = CreateFrame('Frame', nil, energy)
	clipFrame:SetAllPoints()
	clipFrame:EnableMouse(false)
	clipFrame.__frame = frame
	energy.ClipFrame = clipFrame

	energy:Hide()

	return energy
end

function UF:Configure_Energy(frame)
	if not frame.VARIABLES_SET then return end
	if not frame.Energy then return end

	local db = frame.db
	

	if frame.unitframeType == "player" then
		frame.USE_ENERGYBAR = IsHero() and db.energy and db.energy.enable
	else
		frame.USE_ENERGYBAR = db.energy and db.energy.enable
	end

	local energy = frame.Energy
	energy.origParent = frame

	if frame.USE_ENERGYBAR then
		if not frame:IsElementEnabled("Energy") then
			frame:EnableElement("Energy")
		end
		
		energy:Show()
		if energy.value then energy.value:Show() end

		local unit = frame.unit or "player"
		local max = UnitPowerMax(unit, 3)
		if not max or max == 0 then max = 100 end
		local cur = UnitPower(unit, 3) or 0

		energy.max = max
		energy:SetMinMaxValues(0, max)
		energy:SetValue(cur)

		-- Safely register events
		frame:RegisterEvent("UNIT_ENERGY", UpdateCustomEnergy)
		frame:RegisterEvent("UNIT_MAXENERGY", UpdateCustomMaxEnergy)
		
		if frame.unit == "target" then
			frame:RegisterEvent("PLAYER_TARGET_CHANGED", UpdateCustomEnergy)
			frame:RegisterEvent("PLAYER_TARGET_CHANGED", UpdateCustomMaxEnergy)
		elseif frame.unit == "focus" then
			frame:RegisterEvent("PLAYER_FOCUS_CHANGED", UpdateCustomEnergy)
			frame:RegisterEvent("PLAYER_FOCUS_CHANGED", UpdateCustomMaxEnergy)
		end
	else
		if frame:IsElementEnabled("Energy") then
			frame:DisableElement("Energy")
		end
		
		energy:Hide()
		if energy.value then
			energy.value:Hide()
			frame:Tag(energy.value, "")
		end

		frame:UnregisterEvent("UNIT_ENERGY", UpdateCustomEnergy)
		frame:UnregisterEvent("UNIT_MAXENERGY", UpdateCustomMaxEnergy)
		
		if frame.unit == "target" then
			frame:UnregisterEvent("PLAYER_TARGET_CHANGED", UpdateCustomEnergy)
			frame:UnregisterEvent("PLAYER_TARGET_CHANGED", UpdateCustomMaxEnergy)
		elseif frame.unit == "focus" then
			frame:UnregisterEvent("PLAYER_FOCUS_CHANGED", UpdateCustomEnergy)
			frame:UnregisterEvent("PLAYER_FOCUS_CHANGED", UpdateCustomMaxEnergy)
		end
		return
	end

	E:SetSmoothing(energy, self.db.smoothbars)

	local anchor = frame.Health
	if frame.USE_POWERBAR and not frame.USE_POWERBAR_DETACHED and not frame.USE_INSET_POWERBAR and not frame.USE_MINI_POWERBAR then
		anchor = frame.Power
	end

	energy:ClearAllPoints()
	if energy.value then energy.value:ClearAllPoints() end
	energy:SetWidth(frame.UNIT_WIDTH - (frame.BORDER * 2))

	local barHeight = db.energy and db.energy.height or 10
	energy:SetHeight(barHeight - (frame.BORDER + frame.SPACING) * 2)

	local xOffset = db.energy and db.energy.xOffset or 0
	local yOffset = db.energy and db.energy.yOffset or 0

	energy:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", xOffset, -yOffset - frame.SPACING)
	energy:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", xOffset, -yOffset - frame.SPACING)
	energy:SetFrameLevel(anchor:GetFrameLevel() + 2)

	if energy.value and db.energy then
		local attachPoint = self:GetObjectAnchorPoint(frame, db.energy.attachTextTo)
		local rawPos = db.energy.position
		local tPos = (type(rawPos) == "string" and validPoints[rawPos]) and rawPos or "CENTER"

		energy.value:SetPoint(tPos, attachPoint or energy, tPos, 0, 0)
		frame:Tag(energy.value, db.energy.text_format or "")

		if db.energy.colors and db.energy.colors.enable and db.energy.colors.color then
			energy.value:SetTextColor(
				db.energy.colors.color.r or 1,
				db.energy.colors.color.g or 1,
				db.energy.colors.color.b or 1,
				db.energy.colors.color.a or 1
			)
		else
			energy.value:SetTextColor(1, 1, 1, 1)
		end
	end

	local strataData = db.energy and db.energy.strataAndLevel or {}
	if strataData.useCustomStrata then
		energy:SetFrameStrata(strataData.frameStrata or "LOW")
	else
		energy:SetFrameStrata("LOW")
	end

	if strataData.useCustomLevel then
		energy:SetFrameLevel(strataData.frameLevel or 1)
		energy.backdrop:SetFrameLevel(energy:GetFrameLevel() - 1)
	end

	if frame.ENERGYBAR_DETACHED and db.energy and db.energy.parent == "UIPARENT" then
		energy:SetParent(E.UIParent)
	else
		energy:SetParent(frame)
	end

	energy.custom_backdrop = UF.db.colors.customenergybackdrop and UF.db.colors.energy_backdrop
	UF:ToggleTransparentStatusBar(UF.db.colors.transparentEnergy, energy, energy.BG, nil, UF.db.colors.invertEnergy)
	UF:PostUpdateEnergyColor(energy)
end

function UF:PostUpdateEnergyColor(energyBar)
	local energy = energyBar or self
	local r, g, b = 0.92, 0.8, 0.2

	if ElvUF.colors and ElvUF.colors.power then
		local c = ElvUF.colors.power["ENERGY"] or ElvUF.colors.power[3]
		if c and type(c.r) == "number" then r, g, b = c.r, c.g, c.b end
	end

	energy:SetStatusBarColor(r, g, b)
	if energy.BG and UF.UpdateBackdropTextureColor then
		UF:UpdateBackdropTextureColor(energy.BG, r, g, b)
	end

	if energy.origParent and energy.origParent.isForced then
		energy:SetValue(random(1, energy.max or 100))
	end
end

function UF:PostUpdateEnergy(unit)
	local parent = self.origParent or self:GetParent()
	if parent.isForced then self:SetValue(random(1, self.max or 100)) end
end