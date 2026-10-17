local E, L, V, P, G = unpack(ElvUI)
local CM = E:GetModule("CooldownManager")

local CreateFrame = CreateFrame
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local GetComboPoints = GetComboPoints
local InCombatLockdown = InCombatLockdown
local unpack = unpack
local format = string.format

-- ============================================================================
-- Personal Resource & Power Bar Module for CooldownManager
-- Displays the player's primary resource (mana/rage/energy/runic power, focus,
-- or combo points) as a single draggable colour-coded bar.
-- ============================================================================
local PowerBars = {}
CM.PowerBars = PowerBars

PowerBars.bar = nil -- { key, holder, moverName, statusBar, bg, text }

-- Resource colour palette (keyed by power token)
local RESOURCE_COLORS = {
	MANA         = { 0.00, 0.40, 0.90 },
	RAGE         = { 0.90, 0.10, 0.10 },
	ENERGY       = { 1.00, 0.90, 0.10 },
	RUNIC_POWER  = { 0.00, 0.80, 1.00 },
	FOCUS        = { 0.90, 0.20, 0.95 },
	COMBO_POINTS = { 1.00, 0.85, 0.00 },
}

-- Combo points power type index on 3.3.5a
local COMBO_POINT_TYPE = 7

-- ----------------------------------------------------------------------------
-- Create (once) the single personal power bar frame with an ElvUI mover.
-- ----------------------------------------------------------------------------
function PowerBars:CreatePowerFrame()
	if self.bar then return self.bar end

	local cfg = E.db.cooldownManager and E.db.cooldownManager.powerBars or P.cooldownManager.powerBars
	local barKey = "power"

	local frameName = "ElvUI_CMPower_" .. barKey
	local holder = CreateFrame("Frame", frameName .. "_Holder", E.UIParent)
	holder:SetSize(cfg.barWidth or 160, cfg.barHeight or 18)
	holder:Point("CENTER", E.UIParent, "CENTER", 0, -180)

	local bar = CreateFrame("Frame", frameName, E.UIParent)
	bar:SetSize(cfg.barWidth or 160, cfg.barHeight or 18)
	bar:Point("CENTER", holder, "CENTER", 0, 0)

	bar.key       = barKey
	bar.holder    = holder
	bar.moverName = frameName .. "_Mover"

	bar.statusBar = CreateFrame("StatusBar", nil, bar)
	bar.statusBar:SetAllPoints(bar)
	bar.statusBar:SetMinMaxValues(0, 1)
	local normTex = E.LSM:Fetch("statusbar", cfg.texture or "ElvUI Norm")
	bar.statusBar:SetStatusBarTexture(normTex)

	bar.bg = bar.statusBar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetTexture(normTex)
	bar.bg:SetVertexColor(0.1, 0.1, 0.1, 0.8)

	bar.text = bar.statusBar:CreateFontString(nil, "OVERLAY")
	bar.text:FontTemplate(E.LSM:Fetch("font", E.db.cooldownManager.font or "Expressway"), 11, "OUTLINE")
	bar.text:SetPoint("CENTER")

	E:CreateMover(holder, bar.moverName, cfg.name or "Personal Power Bar", nil, nil, nil, "ALL,SOLO", nil, "elvuiPlugins,cooldownManager")

	bar:Hide()

	self.bar = bar
	return bar
end

-- ----------------------------------------------------------------------------
-- Hide the personal power bar (module disabled or should not show).
-- The ElvUI mover is left in place so toggling stays survive a reload.
-- ----------------------------------------------------------------------------
function PowerBars:Disable()
	if self.bar then
		self.bar:Hide()
	end
end

-- ----------------------------------------------------------------------------
-- Update the personal power bar from the player's current resource.
-- ----------------------------------------------------------------------------
function PowerBars:Update()
	local cfg = E.db.cooldownManager and E.db.cooldownManager.powerBars
	if not cfg or not cfg.enable then
		self:Disable()
		return
	end

	local bar = self:CreatePowerFrame()
	if not bar then return end

	local pType, pToken = UnitPowerType("player")
	local pTypeNum = tonumber(pType) or pType

	local cur, maxv = 0, 1
	if pTypeNum == COMBO_POINT_TYPE then
		cur = GetComboPoints("player", "target")
		maxv = 5
		pToken = "COMBO_POINTS"
	else
		cur = UnitPower("player", pTypeNum)
		maxv = UnitPowerMax("player", pTypeNum)
		if maxv <= 0 then maxv = 1 end
	end

	-- Hide while in combat lockdown if requested (UI can't be moved anyway, but
	-- keeps the screen clean).
	if cfg.hideInCombat and InCombatLockdown() then
		bar:Hide()
		return
	end

	-- Apply live layout changes
	local barWidth  = cfg.barWidth  or 160
	local barHeight = cfg.barHeight or 18
	bar:SetSize(barWidth, barHeight)
	bar.holder:SetSize(barWidth, barHeight)
	bar.statusBar:SetMinMaxValues(0, maxv)
	bar.statusBar:SetStatusBarTexture(E.LSM:Fetch("statusbar", cfg.texture or "ElvUI Norm"))

	-- Colour by resource
	local color = RESOURCE_COLORS[pToken] or RESOURCE_COLORS.MANA
	bar.statusBar:SetStatusBarColor(color[1], color[2], color[3], 1.0)
	bar.statusBar:SetValue(cur)

	-- Text
	if cfg.showText then
		if pTypeNum == COMBO_POINT_TYPE then
			bar.text:SetText(maxv > 0 and format("%d", cur) or "")
		else
			bar.text:SetText(format("%d / %d", cur, maxv))
		end
		bar.text:Show()
	else
		bar.text:Hide()
	end

	bar:Show()
end
