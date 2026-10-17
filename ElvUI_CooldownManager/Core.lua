local E, L, V, P, G = unpack(ElvUI)
local CM = E:NewModule("CooldownManager", "AceEvent-3.0", "AceTimer-3.0")
local EP = LibStub("LibElvUIPlugin-1.0")

local addonName = ...
local pairs = pairs

-- ============================================================================
-- WoW 3.3.5a Event Handlers
-- ============================================================================
function CM:SPELL_UPDATE_COOLDOWN()
	self:UpdateAllBars()
end

function CM:UNIT_AURA(event, unit)
	if unit == "player" then
		self:UpdateAllBars()
	end
	if CM.UnitFrameWatch then
		CM.UnitFrameWatch:Update()
	end
end

function CM:UNIT_SPELLCAST_SUCCEEDED(event, unit, spellName, spellRank)
	if unit == "player" then
		self:UpdateAllBars()
	end
end

function CM:SPELLS_CHANGED()
	self:ScanSpellbook()
	self:UpdateAllBars()
end

function CM:UPDATE_BINDINGS()
	if self.InvalidateKeybindCache then
		self:InvalidateKeybindCache()
	end
	self:UpdateAllBars()
end

function CM:PLAYER_REGEN_DISABLED()
	self:UpdateAllBars()
	if CM.Overlays then CM.Overlays:UpdateAll() end
end

function CM:PLAYER_REGEN_ENABLED()
	self:UpdateAllBars()
	if CM.Overlays then CM.Overlays:UpdateAll() end
end

function CM:UNIT_THREAT_SITUATION_UPDATE()
	if CM.Overlays then CM.Overlays:UpdateAggro() end
end

function CM:PLAYER_TARGET_CHANGED()
	if CM.Overlays then CM.Overlays:UpdateRange() end
end

function CM:UNIT_POWER_UPDATE(event, unit)
	if unit == "player" and CM.PowerBars then
		CM.PowerBars:Update()
	end
end

function CM:PLAYER_ENTERING_WORLD()
	self:ScanSpellbook()
	self:UpdateAllBars()
	if CM.Overlays then CM.Overlays:UpdateAll() end
	if CM.UnitFrameWatch then CM.UnitFrameWatch:Update() end
	if CM.PowerBars then CM.PowerBars:Update() end
end

-- ============================================================================
-- Module Initialization within ElvUI Architecture
-- ============================================================================
function CM:Initialize()
	self.db = E.db.cooldownManager

	-- 1. Scan player's initial spellbook
	self:ScanSpellbook()

	-- 2. Construct predefined bars
	if self.db.bars then
		for barKey, config in pairs(self.db.bars) do
			self:ConstructBar(barKey, config)
		end
	end

	-- 3. Construct custom bars saved in current profile
	if self.db.customBars then
		for barKey, config in pairs(self.db.customBars) do
			self:ConstructBar(barKey, config)
		end
	end

	-- 4. Register game events
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	self:RegisterEvent("UNIT_AURA")
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	self:RegisterEvent("SPELLS_CHANGED")
	self:RegisterEvent("PLAYER_TALENT_UPDATE", "SPELLS_CHANGED")
	self:RegisterEvent("UPDATE_BINDINGS")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
	self:RegisterEvent("PLAYER_TARGET_CHANGED")
	self:RegisterEvent("UNIT_POWER_UPDATE")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")

	-- 5. Periodic update timer (for screen overlays, unitframe indicators & power bar)
	self:ScheduleRepeatingTimer(function()
		if CM.Overlays then CM.Overlays:UpdateAll() end
		if CM.UnitFrameWatch then CM.UnitFrameWatch:Update() end
		if CM.PowerBars then CM.PowerBars:Update() end
	end, 0.4)

	-- 6. Register options into ElvUI configuration window
	if EP then
		EP:RegisterPlugin(addonName, function() CM:InsertOptions() end)
	end

	-- 7. Initial render
	self:UpdateAllBars()
	if CM.PowerBars then CM.PowerBars:Update() end
end

local function InitializeCallback()
	CM:Initialize()
end

-- Official registration into ElvUI module loading pipeline
E:RegisterModule(CM:GetName(), InitializeCallback)
