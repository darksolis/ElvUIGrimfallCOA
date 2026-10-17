local E, L, V, P, G = unpack(select(2, ...)); --Import: Engine, Locales, PrivateDB, ProfileDB, GlobalDB
local UF = E:GetModule("UnitFrames")
local _, ns = ...
local ElvUF = ns.oUF
assert(ElvUF, "ElvUI was unable to locate oUF.")

--Lua functions
local _G = _G
local tinsert = tinsert
--WoW API / Variables
local CreateFrame = CreateFrame
local CastingBarFrame_OnLoad = CastingBarFrame_OnLoad
local CastingBarFrame_SetUnit = CastingBarFrame_SetUnit

local CAN_HAVE_CLASSBAR = E.myclass == "DEATHKNIGHT" or UnitPowerType("player") == 5

function UF:Construct_PlayerFrame(frame)
	frame.ThreatIndicator = self:Construct_Threat(frame)
	frame.Health = self:Construct_HealthBar(frame, true, true, "RIGHT")
	frame.Health.frequentUpdates = true
	frame.Power = self:Construct_PowerBar(frame, true, true, "LEFT")
	frame.Power.frequentUpdates = true
	
	-- Added NEW bars for Heroes
	frame.Energy = self:Construct_EnergyBar(frame, true, true, "LEFT")
	frame.Rage = self:Construct_RageBar(frame, true, true, "LEFT")
	frame.Mana = UF:Construct_ManaBar(frame, true, true, 'LEFT')
	frame.Runic = UF:Construct_RunicBar(frame, true, true, 'LEFT')
	
	frame.Name = self:Construct_NameText(frame)
	frame.Portrait3D = self:Construct_Portrait(frame, "model")
	frame.Portrait2D = self:Construct_Portrait(frame, "texture")
	frame.Buffs = self:Construct_Buffs(frame)
	frame.Debuffs = self:Construct_Debuffs(frame)
	frame.Castbar = self:Construct_Castbar(frame, L["Player Castbar"])

	if CAN_HAVE_CLASSBAR then
		-- Only construct runes when the player actually has a rune resource.
		frame.ClassBarHolder = CreateFrame("Frame", nil, frame)
		frame.ClassBarHolder:Point("BOTTOM", E.UIParent, "BOTTOM", 0, 150)

		frame.Runes = self:Construct_DeathKnightResourceBar(frame)
		frame.ClassBar = "Runes"
	end

	frame.MouseGlow = self:Construct_MouseGlow(frame)
	frame.TargetGlow = self:Construct_TargetGlow(frame)
	frame.RaidTargetIndicator = self:Construct_RaidIcon(frame)
	frame.RaidRoleFramesAnchor = self:Construct_RaidRoleFrames(frame)
	frame.RestingIndicator = self:Construct_RestingIndicator(frame)
	frame.CombatIndicator = self:Construct_CombatIndicator(frame)
	frame.PvPText = self:Construct_PvPIndicator(frame)
	frame.DebuffHighlight = self:Construct_DebuffHighlight(frame)
	frame.HealCommBar = self:Construct_HealComm(frame)
	frame.AuraBars = self:Construct_AuraBarHeader(frame)
	frame.InfoPanel = self:Construct_InfoPanel(frame)
	frame.PvPIndicator = self:Construct_PvPIcon(frame)
	frame.Fader = self:Construct_Fader()
	frame.Cutaway = self:Construct_Cutaway(frame)
	frame.customTexts = {}

	frame:Point("BOTTOMLEFT", E.UIParent, "BOTTOM", -413, 68)
	E:CreateMover(frame, frame:GetName().."Mover", L["Player Frame"], nil, nil, nil, "ALL,SOLO", nil, "unitframe,player,generalGroup")

	frame.unitframeType = "player"
end

function UF:Update_PlayerFrame(frame, db)
	-- Work on a shallow view: preserve the user's legacy bar settings in the profile.
	local coaConfig = UF:Get_CoAResourceConfig()
	if coaConfig.enable then
		local view = {}
		for k, v in pairs(db) do view[k] = v end
		for _, key in ipairs({"power", "mana", "rage", "energy", "runic"}) do
			view[key] = {}
			for k, v in pairs(db[key] or {}) do view[key][k] = v end
			view[key].enable = false
		end
		db = view
	end
	frame.db = db

	do
		frame.ORIENTATION = db.orientation

		frame.UNIT_WIDTH = db.width
		frame.UNIT_HEIGHT = db.infoPanel.enable and (db.height + db.infoPanel.height) or db.height

		-- Mana / Power
		frame.USE_POWERBAR = db.power.enable
		frame.POWERBAR_DETACHED = db.power.detachFromFrame
		frame.USE_INSET_POWERBAR = not frame.POWERBAR_DETACHED and db.power.width == "inset" and frame.USE_POWERBAR
		frame.USE_MINI_POWERBAR = (not frame.POWERBAR_DETACHED and db.power.width == "spaced" and frame.USE_POWERBAR)
		frame.USE_POWERBAR_OFFSET = db.power.offset ~= 0 and frame.USE_POWERBAR and not frame.POWERBAR_DETACHED
		frame.POWERBAR_OFFSET = frame.USE_POWERBAR_OFFSET and db.power.offset or 0
		frame.POWERBAR_HEIGHT = not frame.USE_POWERBAR and 0 or db.power.height
		frame.POWERBAR_WIDTH = frame.USE_MINI_POWERBAR and (frame.UNIT_WIDTH - (frame.BORDER*2))/2 or (frame.POWERBAR_DETACHED and db.power.detachedWidth or (frame.UNIT_WIDTH - ((frame.BORDER+frame.SPACING)*2)))

		-- Energy
		frame.USE_ENERGYBAR = db.energy.enable
		frame.ENERGYBAR_DETACHED = db.energy.detachFromFrame
		frame.USE_INSET_ENERGYBAR = not frame.ENERGYBAR_DETACHED and db.energy.width == "inset" and frame.USE_ENERGYBAR
		frame.USE_MINI_ENERGYBAR = (not frame.ENERGYBAR_DETACHED and db.energy.width == "spaced" and frame.USE_ENERGYBAR)
		frame.USE_ENERGYBAR_OFFSET = db.energy.offset ~= 0 and frame.USE_ENERGYBAR and not frame.ENERGYBAR_DETACHED
		frame.ENERGYBAR_OFFSET = frame.USE_ENERGYBAR_OFFSET and db.energy.offset or 0
		frame.ENERGYBAR_HEIGHT = not frame.USE_ENERGYBAR and 0 or db.energy.height
		frame.ENERGYBAR_WIDTH = frame.USE_MINI_ENERGYBAR and (frame.UNIT_WIDTH - (frame.BORDER*2))/2 or (frame.ENERGYBAR_DETACHED and db.energy.detachedWidth or (frame.UNIT_WIDTH - ((frame.BORDER+frame.SPACING)*2)))

		-- Rage
		frame.USE_RAGEBAR = db.rage.enable
		frame.RAGEBAR_DETACHED = db.rage.detachFromFrame
		frame.USE_INSET_RAGEBAR = not frame.RAGEBAR_DETACHED and db.rage.width == "inset" and frame.USE_RAGEBAR
		frame.USE_MINI_RAGEBAR = (not frame.RAGEBAR_DETACHED and db.rage.width == "spaced" and frame.USE_RAGEBAR)
		frame.USE_RAGEBAR_OFFSET = db.rage.offset ~= 0 and frame.USE_RAGEBAR and not frame.RAGEBAR_DETACHED
		frame.RAGEBAR_OFFSET = frame.USE_RAGEBAR_OFFSET and db.rage.offset or 0
		frame.RAGEBAR_HEIGHT = not frame.USE_RAGEBAR and 0 or db.rage.height
		frame.RAGEBAR_WIDTH = frame.USE_MINI_RAGEBAR and (frame.UNIT_WIDTH - (frame.BORDER*2))/2 or (frame.RAGEBAR_DETACHED and db.rage.detachedWidth or (frame.UNIT_WIDTH - ((frame.BORDER+frame.SPACING)*2)))
		
		frame.USE_MANABAR = db.mana and db.mana.enable
		frame.MANABAR_DETACHED = db.mana and db.mana.detachFromFrame
		frame.USE_INSET_MANABAR = not frame.MANABAR_DETACHED and db.mana and db.mana.width == 'inset' and frame.USE_MANABAR
		frame.USE_MINI_MANABAR = not frame.MANABAR_DETACHED and db.mana and db.mana.width == 'spaced' and frame.USE_MANABAR
		frame.USE_MANABAR_OFFSET = db.mana and db.mana.offset ~= 0 and frame.USE_MANABAR and not frame.MANABAR_DETACHED
		frame.MANABAR_OFFSET = frame.USE_MANABAR_OFFSET and db.mana.offset or 0
		frame.MANABAR_HEIGHT = not frame.USE_MANABAR and 0 or (db.mana and db.mana.height) or 0

		frame.USE_RUNICBAR = db.runic and db.runic.enable
		frame.RUNICBAR_DETACHED = db.runic and db.runic.detachFromFrame
		frame.USE_INSET_RUNICBAR = not frame.RUNICBAR_DETACHED and db.runic and db.runic.width == 'inset' and frame.USE_RUNICBAR
		frame.USE_MINI_RUNICBAR = not frame.RUNICBAR_DETACHED and db.runic and db.runic.width == 'spaced' and frame.USE_RUNICBAR
		frame.USE_RUNICBAR_OFFSET = db.runic and db.runic.offset ~= 0 and frame.USE_RUNICBAR and not frame.RUNICBAR_DETACHED
		frame.RUNICBAR_OFFSET = frame.USE_RUNICBAR_OFFSET and db.runic.offset or 0
		frame.RUNICBAR_HEIGHT = not frame.USE_RUNICBAR and 0 or (db.runic and db.runic.height) or 0

		frame.USE_PORTRAIT = db.portrait and db.portrait.enable
		frame.USE_PORTRAIT_OVERLAY = frame.USE_PORTRAIT and (db.portrait.overlay or frame.ORIENTATION == "MIDDLE")
		frame.PORTRAIT_WIDTH = (frame.USE_PORTRAIT_OVERLAY or not frame.USE_PORTRAIT) and 0 or db.portrait.width

		frame.MAX_CLASS_BAR = CAN_HAVE_CLASSBAR and 6 or 0
		frame.USE_CLASSBAR = CAN_HAVE_CLASSBAR and db.classbar.enable
		frame.CLASSBAR_SHOWN = frame.ClassBar and frame[frame.ClassBar] and frame[frame.ClassBar]:IsShown() or false
		frame.CLASSBAR_DETACHED = db.classbar.detachFromFrame
		frame.USE_MINI_CLASSBAR = db.classbar.fill == "spaced" and frame.USE_CLASSBAR
		frame.CLASSBAR_HEIGHT = frame.USE_CLASSBAR and db.classbar.height or 0
		frame.CLASSBAR_WIDTH = frame.UNIT_WIDTH - ((frame.BORDER+frame.SPACING)*2) - frame.PORTRAIT_WIDTH -(frame.ORIENTATION == "MIDDLE" and (frame.POWERBAR_OFFSET*2) or frame.POWERBAR_OFFSET)
		frame.CLASSBAR_YOFFSET = (not frame.USE_CLASSBAR or not frame.CLASSBAR_SHOWN or frame.CLASSBAR_DETACHED) and 0 or (frame.USE_MINI_CLASSBAR and (frame.SPACING+(frame.CLASSBAR_HEIGHT/2)) or (frame.CLASSBAR_HEIGHT - (frame.BORDER-frame.SPACING)))

		frame.USE_INFO_PANEL = not frame.USE_MINI_POWERBAR and not frame.USE_POWERBAR_OFFSET and not frame.USE_MINI_RAGEBAR and not frame.USE_RAGEBAR_OFFSET and not frame.USE_MINI_ENERGYBAR and not frame.USE_ENERGYBAR_OFFSET and db.infoPanel.enable
		frame.INFO_PANEL_HEIGHT = frame.USE_INFO_PANEL and db.infoPanel.height or 0

		frame.BOTTOM_OFFSET = UF:GetHealthBottomOffset(frame)
		frame.VARIABLES_SET = true
	end

	frame.colors = ElvUF.colors
	frame.Portrait = frame.Portrait or (db.portrait.style == "2D" and frame.Portrait2D or frame.Portrait3D)
	frame:RegisterForClicks(self.db.targetOnMouseDown and "AnyDown" or "AnyUp")
	frame:Size(frame.UNIT_WIDTH, frame.UNIT_HEIGHT)
	_G[frame:GetName().."Mover"]:Size(frame:GetSize())

	UF:Configure_InfoPanel(frame)
	UF:Configure_Threat(frame)
	UF:Configure_RestingIndicator(frame)
	UF:Configure_CombatIndicator(frame)
	UF:Configure_ClassBar(frame)
	
    -- Correct Order for Stacking: Power -> Energy -> Rage
	UF:Configure_Power(frame)
	UF:Configure_Energy(frame)
	UF:Configure_Rage(frame)
	UF:Configure_Mana(frame)
	UF:Configure_Runic(frame)
    
	UF:Configure_HealthBar(frame)
	UF:UpdateNameSettings(frame)
	UF:Configure_PVPIndicator(frame)
	UF:Configure_Portrait(frame)
	UF:EnableDisable_Auras(frame)
	UF:Configure_Auras(frame, "Buffs")
	UF:Configure_Auras(frame, "Debuffs")
	
	frame:DisableElement("Castbar")
	UF:Configure_Castbar(frame)

	if (not db.enable and not E.private.unitframe.disabledBlizzardFrames.player) then
		CastingBarFrame_OnLoad(CastingBarFrame, "player", true, false)
		CastingBarFrame_SetUnit(CastingBarFrame, "player", true, false)
		PetCastingBarFrame_OnLoad(PetCastingBarFrame)
		CastingBarFrame_SetUnit(PetCastingBarFrame, "pet", false, false)
	elseif not db.enable and E.private.unitframe.disabledBlizzardFrames.player or (db.enable and not db.castbar.enable) then
		CastingBarFrame_SetUnit(CastingBarFrame, nil)
		CastingBarFrame_SetUnit(PetCastingBarFrame, nil)
	end

	UF:Configure_Fader(frame)
	UF:Configure_Cutaway(frame)
	UF:Configure_DebuffHighlight(frame)
	UF:Configure_RaidIcon(frame)
	UF:Configure_HealComm(frame)
	UF:Configure_AuraBars(frame)
	
	if E.db.unitframe.units.target.aurabar.attachTo == "PLAYER_AURABARS" and ElvUF_Target then
		UF:Configure_AuraBars(ElvUF_Target)
	end

	UF:Configure_PVPIcon(frame)
	UF:Configure_RaidRoleIcons(frame)
	UF:Configure_CustomTexts(frame)

	E:SetMoverSnapOffset(frame:GetName().."Mover", -(12 + db.castbar.height))
	frame:UpdateAllElements("ForceUpdate")
	UF:Configure_CoAResources(frame)
end

tinsert(UF.unitstoload, "player")

local function UpdateClassBar()
	local frame = _G.ElvUF_Player
	if frame and frame.ClassBar then
		frame:UpdateElement(frame.ClassBar)
		UF.ToggleResourceBar(frame[frame.ClassBar])
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self, event)
	self:UnregisterEvent(event)
	if not E.db.unitframe.units.player.enable then return end
	UpdateClassBar()
end)