local E, L, V, P, G = unpack(ElvUI)
local CM = E:GetModule("CooldownManager")

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UnitThreatSituation = UnitThreatSituation
local IsSpellInRange = IsSpellInRange
local CheckInteractDistance = CheckInteractDistance
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local unpack, pairs, ipairs = unpack, pairs, ipairs

-- ============================================================================
-- Screen Overlays Module: Raid Buffs Checklist, Aggro Alert, Range Alert
-- ============================================================================
local Overlays = {}
CM.Overlays = Overlays

-- ----------------------------------------------------------------------------
-- 1. Missing Raid Buffs Checklist Frame
-- ----------------------------------------------------------------------------
function Overlays:CreateRaidBuffsFrame()
	if self.raidBuffsFrame then return self.raidBuffsFrame end

	local frame = CreateFrame("Frame", "ElvUI_CMRaidBuffsOverlay", E.UIParent)
	frame:SetSize(320, 36)
	frame:Point("TOP", E.UIParent, "TOP", 0, -120)
	frame.icons = {}

	E:CreateMover(frame, "ElvUI_CMRaidBuffsMover", "Missing Raid Buffs Checklist", nil, nil, nil, "ALL,SOLO", nil, "elvuiPlugins,cooldownManager")
	self.raidBuffsFrame = frame
	return frame
end

function Overlays:UpdateRaidBuffs()
	local cfg = E.db.cooldownManager and E.db.cooldownManager.overlays and E.db.cooldownManager.overlays.raidBuffs
	if not cfg or not cfg.enable then
		if self.raidBuffsFrame then self.raidBuffsFrame:Hide() end
		return
	end

	if cfg.hideInCombat and InCombatLockdown() then
		if self.raidBuffsFrame then self.raidBuffsFrame:Hide() end
		return
	end

	local frame = self:CreateRaidBuffsFrame()
	local size = cfg.iconSize or 28
	local spacing = cfg.spacing or 4

	if not CM.RaidBuffGroups then return end
	local missingIndex = 0
	for _, group in ipairs(CM.RaidBuffGroups) do
		local hasBuff = CM:IsRaidBuffActive(group)
		if not hasBuff then
			missingIndex = missingIndex + 1
			local btn = frame.icons[missingIndex]
			if not btn then
				btn = CreateFrame("Frame", nil, frame)
				btn:SetTemplate("Default")
				btn.icon = btn:CreateTexture(nil, "ARTWORK")
				btn.icon:SetInside()
				btn.icon:SetTexCoord(unpack(E.TexCoords))
				frame.icons[missingIndex] = btn
			end

			btn:SetSize(size, size)
			btn.icon:SetTexture(group.icon)
			btn:ClearAllPoints()
			btn:Point("LEFT", frame, "LEFT", (missingIndex - 1) * (size + spacing), 0)
			btn:Show()
		end
	end

	for i = missingIndex + 1, #frame.icons do
		frame.icons[i]:Hide()
	end

	if missingIndex == 0 then
		frame:Hide()
	else
		frame:SetSize(missingIndex * (size + spacing) - spacing, size)
		frame:Show()
	end
end

-- ----------------------------------------------------------------------------
-- 2. Aggro Alert Overlay ("AGGRO ON YOU")
-- ----------------------------------------------------------------------------
function Overlays:CreateAggroFrame()
	if self.aggroFrame then return self.aggroFrame end

	local frame = CreateFrame("Frame", "ElvUI_CMAggroOverlay", E.UIParent)
	frame:SetSize(300, 40)
	frame:Point("CENTER", E.UIParent, "CENTER", 0, 180)

	frame.text = frame:CreateFontString(nil, "OVERLAY")
	frame.text:FontTemplate(nil, 22, "OUTLINE")
	frame.text:SetPoint("CENTER")
	frame.text:SetText("|cffff0000▲ AGGRO ON YOU ▲|r")

	E:CreateMover(frame, "ElvUI_CMAggroMover", "Aggro Alert Text", nil, nil, nil, "ALL,SOLO", nil, "elvuiPlugins,cooldownManager")
	self.aggroFrame = frame
	return frame
end

function Overlays:UpdateAggro()
	local cfg = E.db.cooldownManager and E.db.cooldownManager.overlays and E.db.cooldownManager.overlays.aggroAlert
	if not cfg or not cfg.enable then
		if self.aggroFrame then self.aggroFrame:Hide() end
		return
	end

	if not InCombatLockdown() then
		if self.aggroFrame then self.aggroFrame:Hide() end
		return
	end

	local threat = UnitThreatSituation("player")
	if threat and threat >= 2 then
		local frame = self:CreateAggroFrame()
		frame.text:FontTemplate(E.LSM:Fetch("font", E.db.cooldownManager.font or "Expressway"), cfg.fontSize or 22, "OUTLINE")
		frame:Show()
	else
		if self.aggroFrame then self.aggroFrame:Hide() end
	end
end

-- ----------------------------------------------------------------------------
-- 3. Range Alert Overlay ("OUT OF RANGE")
-- ----------------------------------------------------------------------------
function Overlays:CreateRangeFrame()
	if self.rangeFrame then return self.rangeFrame end

	local frame = CreateFrame("Frame", "ElvUI_CMRangeOverlay", E.UIParent)
	frame:SetSize(300, 36)
	frame:Point("CENTER", E.UIParent, "CENTER", 0, 140)

	frame.text = frame:CreateFontString(nil, "OVERLAY")
	frame.text:FontTemplate(nil, 18, "OUTLINE")
	frame.text:SetPoint("CENTER")
	frame.text:SetText("|cffff3333OUT OF RANGE|r")

	E:CreateMover(frame, "ElvUI_CMRangeMover", "Out of Range Alert", nil, nil, nil, "ALL,SOLO", nil, "elvuiPlugins,cooldownManager")
	self.rangeFrame = frame
	return frame
end

function Overlays:UpdateRange()
	local cfg = E.db.cooldownManager and E.db.cooldownManager.overlays and E.db.cooldownManager.overlays.rangeAlert
	if not cfg or not cfg.enable then
		if self.rangeFrame then self.rangeFrame:Hide() end
		return
	end

	if not UnitExists("target") or not UnitCanAttack("player", "target") or UnitIsDeadOrGhost("target") then
		if self.rangeFrame then self.rangeFrame:Hide() end
		return
	end

	local inRange = false
	-- Probe with Auto Attack or interact distance
	if CheckInteractDistance("target", 3) then
		inRange = true
	elseif cfg.spellCheck and cfg.spellCheck ~= "" then
		if IsSpellInRange(cfg.spellCheck, "target") == 1 then
			inRange = true
		end
	end

	if not inRange then
		local frame = self:CreateRangeFrame()
		frame.text:FontTemplate(E.LSM:Fetch("font", E.db.cooldownManager.font or "Expressway"), cfg.fontSize or 18, "OUTLINE")
		frame:Show()
	else
		if self.rangeFrame then self.rangeFrame:Hide() end
	end
end

function Overlays:UpdateAll()
	self:UpdateRaidBuffs()
	self:UpdateAggro()
	self:UpdateRange()
end
