local E, L, V, P, G = unpack(select(2, ...)); --Import: Engine, Locales, PrivateDB, ProfileDB, GlobalDB
local UF = E:GetModule("UnitFrames")
local SpellRange = E.Libs.SpellRange

--Lua functions
local pairs, ipairs = pairs, ipairs
local find = string.find
local format = string.format
local tonumber = tonumber
--WoW API / Variables
local CheckInteractDistance = CheckInteractDistance
local UnitCanAttack = UnitCanAttack
local UnitInParty = UnitInParty
local UnitInRaid = UnitInRaid
local UnitInRange = UnitInRange
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsUnit = UnitIsUnit
local GetNumSpellTabs = GetNumSpellTabs
local GetSpellBookItemInfo = GetSpellBookItemInfo
local GetSpellInfo = GetSpellInfo
local GetSpellLink = GetSpellLink
local GetSpellTabInfo = GetSpellTabInfo

local SRT = {}
local function AddTable(tbl)
	SRT[E.myclass][tbl] = {}
end

local function AddSpell(tbl, spellID)
	SRT[E.myclass][tbl][#SRT[E.myclass][tbl] + 1] = spellID
end

-- Resolve a player spellbook slot to its spellID. WotLK private servers often omit
-- GetSpellBookItemInfo, so prefer it when available and fall back to parsing the
-- spellbook hyperlink, which every 3.3.5a client provides via GetSpellLink.
local function GetSlotSpellID(slot)
	if GetSpellBookItemInfo then
		local _, spellID = GetSpellBookItemInfo(slot, "spell")
		if spellID and spellID > 0 then return spellID end
	end
	if GetSpellLink then
		local link = GetSpellLink(slot, "spell")
		if link then
			local id = tonumber(link:match("spell:(%d+)"))
			if id then return id end
		end
	end
end

-- True when the given spellID is currently in the player's spellbook. Validates the
-- configured anchor so an unlearned spell cannot silently keep its cached anchor alive.
local function IsSpellLearned(spellID)
	local numTabs = GetNumSpellTabs()
	for tab = 1, numTabs do
		local _, _, offset, numSpells = GetSpellTabInfo(tab)
		for slot = offset + 1, offset + numSpells do
			if GetSlotSpellID(slot) == spellID then
				return true
			end
		end
	end
	return false
end

-- Spellbook scanning helpers for the custom range check anchor.
-- Return a table of spellID -> display text for the highest-rank learned version of every
-- player spell with a max range > 0. The display text is spell name prefixed with its icon
-- as an inline texture, so the AceConfig dropdown (and its closed button) show both.
function UF:GetSpellbookRangeSpells()
	local best = {} -- name -> highest-rank learned record { id, rank, icon, range }
	local numTabs = GetNumSpellTabs()
	for tab = 1, numTabs do
		local _, _, offset, numSpells = GetSpellTabInfo(tab)
		for slot = offset + 1, offset + numSpells do
			local spellID = GetSlotSpellID(slot)
			if spellID then
				-- 3.3.5a GetSpellInfo returns 9+ values: name@1, rank@2, icon@3, minRange@8, range@9.
				local name, rank, icon, _, _, _, _, _, maxRange = GetSpellInfo(spellID)
				if name and maxRange and maxRange > 0 then
					local prev = best[name]
					if not prev or (rank or 0) > (prev.rank or 0) or ((rank or 0) == (prev.rank or 0) and maxRange > prev.range) then
						best[name] = { id = spellID, rank = rank, icon = icon, range = maxRange }
					end
				end
			end
		end
	end

	local spells = {}
	for name, info in pairs(best) do
		spells[info.id] = format("|T%s:16:16:0:0:64:64:4:60:4:60|t %s", info.icon, name)
	end
	return spells
end

-- Find the learned spell whose max range is the closest to `distance` from below
-- (largest maxRange <= distance). Returns the spellID or nil when no spell qualifies.
local function FindDistanceAnchorSpell(distance)
	distance = tonumber(distance) or 30
	local bestSpell, bestRange
	local numTabs = GetNumSpellTabs()
	for tab = 1, numTabs do
		local _, _, offset, numSpells = GetSpellTabInfo(tab)
		for slot = offset + 1, offset + numSpells do
			local spellID = GetSlotSpellID(slot)
			if spellID then
				local _, _, _, _, _, _, _, _, maxRange = GetSpellInfo(spellID)
				if maxRange and maxRange > 0 and maxRange <= distance and (not bestRange or maxRange > bestRange) then
					bestSpell, bestRange = spellID, maxRange
				end
			end
		end
	end
	return bestSpell
end

-- Resolve the per-profile custom range check anchor into a cached spellID on the module.
-- Mode "spell" uses the configured spellID when it is still learned (validated against the
-- spellbook, not just the global spell database); mode "distance" picks the learned spell
-- whose max range is closest to the configured yards from below. Any other mode, an
-- unlearned/unknown anchor, or a missing config resolves to nil (fall back to class tables).
function UF:UpdateCustomAnchorSpell()
	self.customAnchorSpell = nil
	local cfg = E.db and E.db.unitframe and E.db.unitframe.rangeCheck
	if not cfg then return end

	if cfg.mode == "spell" then
		if cfg.spell and cfg.spell > 0 and IsSpellLearned(cfg.spell) then
			self.customAnchorSpell = cfg.spell
		end
	elseif cfg.mode == "distance" then
		self.customAnchorSpell = FindDistanceAnchorSpell(cfg.distance)
	end
end

function UF:UpdateRangeCheckSpells()
	if not SRT[E.myclass] then SRT[E.myclass] = {} end

	for tbl, spells in pairs(E.global.unitframe.spellRangeCheck[E.myclass] or {}) do
		AddTable(tbl) --Create the table holding spells, even if it ends up being an empty table
		for spellID in pairs(spells) do
			local enabled = spells[spellID]
			if enabled then --We will allow value to be false to disable this spell from being used
				AddSpell(tbl, spellID, enabled)
			end
		end
	end

	self:UpdateCustomAnchorSpell() --Re-resolve the custom anchor on init and on LEARNED_SPELL_IN_TAB
end

local function getUnit(unit)
	-- PR5 perf: only canonicalize the token when the unit is NEITHER party-
	-- nor raid-shaped already. The legacy 'or' made this condition always true,
	-- so every fader range check ran up to 44 UnitIsUnit calls (thousands/sec
	-- at raid scale) even for units already named "raid17"/"party2".
	if not find(unit, "party") and not find(unit, "raid") then
		for i = 1, 4 do
			if UnitIsUnit(unit, "party"..i) then
				return "party"..i
			end
		end

		for i = 1, 40 do
			if UnitIsUnit(unit, "raid"..i) then
				return "raid"..i
			end
		end
	else
		return unit
	end
end

-- Anchor-first range check: returns true/false when the custom anchor applies to the unit
-- (IsSpellInRange returned 1/0), nil when there is no anchor or it does not apply, so the
-- caller falls through to the per-class spell tables unchanged.
local function customAnchorIsInRange(unit)
	local anchor = UF.customAnchorSpell
	if not anchor then return nil end

	local inRange = SpellRange.IsSpellInRange(anchor, unit)
	if not inRange then return nil end --nil: spell not usable on this unit (e.g. heal on an enemy)

	return inRange == 1
end

local function friendlyIsInRange(unit)
	if (not UnitIsUnit(unit, "player")) and (UnitInParty(unit) or UnitInRaid(unit)) then
		unit = getUnit(unit) -- swap the unit with `raid#` or `party#` when its NOT `player`, UnitIsUnit is true, and its not using `raid#` or `party#` already
	end

	local anchorInRange = customAnchorIsInRange(unit)
	if anchorInRange ~= nil then return anchorInRange end

	local inRange, checkedRange = UnitInRange(unit)
	if checkedRange and not inRange then
		return false -- blizz checked and said the unit is out of range
	end

	if CheckInteractDistance(unit, 1) then
		return true -- within 28 yards (arg2 as 1 is Compare Achievements distance)
	end

	if SRT[E.myclass] then
		if SRT[E.myclass].resSpells and UnitIsDeadOrGhost(unit) and (#SRT[E.myclass].resSpells > 0) then -- dead with rez spells
			for _, spellID in ipairs(SRT[E.myclass].resSpells) do
				if SpellRange.IsSpellInRange(spellID, unit) == 1 then
					return true -- within rez range
				end
			end

			return false -- dead but no spells are in range
		end

		if SRT[E.myclass].friendlySpells and (#SRT[E.myclass].friendlySpells > 0) then -- you have some healy spell
			for _, spellID in ipairs(SRT[E.myclass].friendlySpells) do
				if SpellRange.IsSpellInRange(spellID, unit) == 1 then
					return true -- within healy spell range
				end
			end
		end
	end

	return false -- not within 28 yards and no spells in range
end

local function petIsInRange(unit)
	local anchorInRange = customAnchorIsInRange(unit)
	if anchorInRange ~= nil then return anchorInRange end

	if CheckInteractDistance(unit, 2) then
		return true -- within 8 yards (arg2 as 2 is Trade distance)
	end

	if SRT[E.myclass] then
		if SRT[E.myclass].friendlySpells and (#SRT[E.myclass].friendlySpells > 0) then -- you have some healy spell
			for _, spellID in ipairs(SRT[E.myclass].friendlySpells) do
				if SpellRange.IsSpellInRange(spellID, unit) == 1 then
					return true
				end
			end
		end

		if SRT[E.myclass].petSpells and (#SRT[E.myclass].petSpells > 0) then -- you have some pet spell
			for _, spellID in ipairs(SRT[E.myclass].petSpells) do
				if SpellRange.IsSpellInRange(spellID, unit) == 1 then
					return true
				end
			end
		end
	end

	return false -- not within 8 yards and no spells in range
end

local function enemyIsInRange(unit)
	local anchorInRange = customAnchorIsInRange(unit)
	if anchorInRange ~= nil then return anchorInRange end

	if CheckInteractDistance(unit, 2) then
		return true -- within 8 yards (arg2 as 2 is Trade distance)
	end

	if SRT[E.myclass] then
		if SRT[E.myclass].enemySpells and (#SRT[E.myclass].enemySpells > 0) then -- you have some damage spell
			for _, spellID in ipairs(SRT[E.myclass].enemySpells) do
				if SpellRange.IsSpellInRange(spellID, unit) == 1 then
					return true
				end
			end
		end
	end

	return false -- not within 8 yards and no spells in range
end

local function enemyIsInLongRange(unit)
	local anchorInRange = customAnchorIsInRange(unit)
	if anchorInRange ~= nil then return anchorInRange end

	if SRT[E.myclass] then
		if SRT[E.myclass].longEnemySpells and (#SRT[E.myclass].longEnemySpells > 0) then -- you have some 30+ range damage spell
			for _, spellID in ipairs(SRT[E.myclass].longEnemySpells) do
				if SpellRange.IsSpellInRange(spellID, unit) == 1 then
					return true
				end
			end
		end
	end

	return false
end

function UF:UpdateRange(unit)
	if not self.Fader then return end
	local alpha

	unit = unit or self.unit

	if self.forceInRange or unit == "player" then
		alpha = self.Fader.MaxAlpha
	elseif self.forceNotInRange then
		alpha = self.Fader.MinAlpha
	elseif unit then
		if UnitCanAttack("player", unit) then
			alpha = ((enemyIsInRange(unit) or enemyIsInLongRange(unit)) and self.Fader.MaxAlpha) or self.Fader.MinAlpha
		elseif UnitIsUnit(unit, "pet") then
			alpha = (petIsInRange(unit) and self.Fader.MaxAlpha) or self.Fader.MinAlpha
		else
			alpha = (UnitIsConnected(unit) and friendlyIsInRange(unit) and self.Fader.MaxAlpha) or self.Fader.MinAlpha
		end
	else
		alpha = self.Fader.MaxAlpha
	end

	self.Fader.RangeAlpha = alpha
end