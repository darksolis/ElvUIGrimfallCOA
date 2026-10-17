local E, L, V, P, G = unpack(ElvUI)
local CM = E:GetModule("CooldownManager")

-- Local cache for 3.3.5a APIs
local GetSpellInfo = GetSpellInfo
local GetSpellCooldown = GetSpellCooldown
local GetNumSpellTabs = GetNumSpellTabs
local GetSpellTabInfo = GetSpellTabInfo
local GetSpellName = GetSpellName
local GetSpellLink = GetSpellLink
local GetSpellTexture = GetSpellTexture
local UnitAura = UnitAura
local GetItemInfo = GetItemInfo
local GetItemCooldown = GetItemCooldown
local GetBindingKey = GetBindingKey
local GetActionInfo = GetActionInfo
local GetTime = GetTime
local GetContainerNumSlots = GetContainerNumSlots
local GetContainerItemInfo = GetContainerItemInfo
local UseContainerItem = UseContainerItem
local GetInventorySlotInfo = GetInventorySlotInfo
local GetInventoryItemID = GetInventoryItemID
local UseInventoryItem = UseInventoryItem
local BOOKTYPE_SPELL = BOOKTYPE_SPELL or "spell"
local pairs, ipairs, tonumber, tostring, select, floor = pairs, ipairs, tonumber, tostring, select, math.floor
local format = string.format
local strmatch = string.match

CM.spellCache = {}       -- [spellID] = { id = spellID, name = name, icon = icon, rank = rank, tab = tabName, isItem = bool }
CM.spellNameCache = {}   -- Sorted list of formatted names for UI dropdowns
CM.keybindCache = {}     -- [spellName] = abbreviated keybind (invalidated on binding changes)

-- Keybind abbreviation table
local KEY_ABBREVIATIONS = {
	{ "SHIFT%-", "S" }, { "CTRL%-", "C" }, { "ALT%-", "A" }, { "META%-", "M" },
	{ "MOUSEWHEELUP", "MU" }, { "MOUSEWHEELDOWN", "MD" },
	{ "MIDDLE MOUSE", "M3" }, { "MIDDLEMOUSE", "M3" },
	{ "MOUSE BUTTON ", "M" }, { "BUTTON", "M" },
	{ "NUMPADDIVIDE", "N/" }, { "NUMPADMULTIPLY", "N*" }, { "NUMPADMINUS", "N-" },
	{ "NUMPADPLUS", "N+" }, { "NUMPADDECIMAL", "N." }, { "NUMPAD", "N" },
	{ "BACKSPACE", "BS" }, { "CAPSLOCK", "Cp" }, { "PAGEDOWN", "PD" },
	{ "PAGEUP", "PU" }, { "ESCAPE", "Esc" }, { "INSERT", "Ins" },
	{ "DELETE", "Del" }, { "SPACE", "SpB" }, { "ENTER", "Ent" },
}

function CM:AbbrevKey(key)
	if not key or key == "" then return "" end
	local text = key:upper()
	for _, pair in ipairs(KEY_ABBREVIATIONS) do
		text = text:gsub(pair[1], pair[2])
	end
	text = text:gsub("%s+", ""):gsub("%-+$", "")
	return (text:gsub("%-", ""))
end

-- ============================================================================
-- Scan player spellbook for WoW 3.3.5a
-- ============================================================================
function CM:ScanSpellbook()
	wipe(self.spellCache)
	wipe(self.spellNameCache)

	local numTabs = GetNumSpellTabs and GetNumSpellTabs() or 0
	if numTabs == 0 then return end

	local onlyMaxRank = self.db and self.db.onlyMaxRank
	if onlyMaxRank == nil and E.db and E.db.cooldownManager then
		onlyMaxRank = E.db.cooldownManager.onlyMaxRank
	end
	if onlyMaxRank == nil then onlyMaxRank = true end

	local highestByName = {}

	for tab = 1, numTabs do
		local tabName, _, offset, numSpells = GetSpellTabInfo(tab)
		if offset and numSpells then
			for slot = offset + 1, offset + numSpells do
				local name, rank = GetSpellName(slot, BOOKTYPE_SPELL)
				if name then
					local spellId
					if GetSpellLink then
						local link = GetSpellLink(slot, BOOKTYPE_SPELL)
						spellId = link and tonumber(strmatch(link, "spell:(%d+)"))
					end

					local _, _, icon = GetSpellInfo(spellId or name)
					if not icon and GetSpellTexture then
						icon = GetSpellTexture(slot, BOOKTYPE_SPELL)
					end

					local id = spellId or name
					local entry = {
						id = id,
						name = name,
						rank = rank or "",
						icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
						tab = tabName or "General",
						isItem = false,
					}

					self.spellCache[id] = entry
					highestByName[name] = entry

					if not onlyMaxRank then
						local iconTex = entry.icon and format("|T%s:16:16:0:0:64:64:4:60:4:60|t ", entry.icon) or ""
						self.spellNameCache[id] = format("%s%s%s [ID: %s]", iconTex, name, (rank and rank ~= "") and (" (" .. rank .. ")") or "", tostring(id))
					end
				end
			end
		end
	end

	if onlyMaxRank then
		for _, entry in pairs(highestByName) do
			local iconTex = entry.icon and format("|T%s:16:16:0:0:64:64:4:60:4:60|t ", entry.icon) or ""
			self.spellNameCache[entry.id] = format("%s%s%s [ID: %s]", iconTex, entry.name, (entry.rank and entry.rank ~= "") and (" (" .. entry.rank .. ")") or "", tostring(entry.id))
		end
	end
end

-- ============================================================================
-- Retrieve spell or item data (from cache or native WoW API)
-- ============================================================================
function CM:GetSpellData(spellID)
	spellID = tonumber(spellID) or spellID
	if not spellID then return nil end

	if self.spellCache[spellID] then
		return self.spellCache[spellID]
	end

	-- 1. Try Spell Database
	local name, rank, icon = GetSpellInfo(spellID)
	if name then
		local data = {
			id = spellID,
			name = name,
			rank = rank or "",
			icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
			tab = "Manual",
			isItem = false,
		}
		self.spellCache[spellID] = data
		return data
	end

	-- 2. Try Item Database (Consumables, Trinkets)
	local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(spellID)
	if itemName then
		local data = {
			id = spellID,
			name = itemName,
			rank = "Item",
			icon = itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark",
			tab = "Items",
			isItem = true,
		}
		self.spellCache[spellID] = data
		return data
	end

	return nil
end

-- ============================================================================
-- Cast a tracked spell or item from an icon click.
-- Spells fire via CastSpellByID; items are located in the inventory (or an
-- equipped slot) and used directly, since CastSpellByID cannot handle item IDs.
-- ============================================================================
function CM:CastTracked(spellID, isItem)
	if not spellID then return false end

	-- Item: locate in bags (consumables, trinkets...) or an equipped slot.
	if isItem then
		for bag = 0, NUM_BAG_SLOTS or 4 do
			local numSlots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
			for slot = 1, numSlots do
				local info = GetContainerItemInfo and GetContainerItemInfo(bag, slot)
				local itemID = info and info.itemID or (select(1, GetContainerItemInfo(bag, slot)))
				if itemID and itemID == spellID then
					UseContainerItem(bag, slot)
					return true
				end
			end
		end

		-- Equipped trinkets / usable gear
		for _, slot in ipairs({ "Trinket0", "Trinket1" }) do
			local invID = GetInventorySlotInfo(slot)
			if invID and GetInventoryItemID("player", invID) == spellID then
				UseInventoryItem(invID)
				return true
			end
		end
		return false
	end

	return CastSpellByID(spellID) ~= nil
end

-- ============================================================================
-- Resolve Action-Bar Keybind for a spell or item name
-- Results are cached per name and invalidated on binding/actionbar changes.
-- ============================================================================
function CM:InvalidateKeybindCache()
	wipe(self.keybindCache)
end

function CM:GetSpellKeybind(spellName)
	if not spellName or spellName == "" then return "" end

	local cached = self.keybindCache[spellName]
	if cached ~= nil then return cached end

	-- 1. Check direct WoW spell binding
	local key = GetBindingKey("SPELL " .. spellName)
	if key and key ~= "" then
		local abbr = self:AbbrevKey(key)
		self.keybindCache[spellName] = abbr
		return abbr
	end

	-- 2. Check Action Bar slots (1 to 120)
	for i = 1, 120 do
		local actionType, id = GetActionInfo(i)
		if actionType == "spell" and id then
			local sName = GetSpellInfo(id)
			if sName and sName == spellName then
				local bKey = GetBindingKey("ACTIONBUTTON" .. i)
				if bKey and bKey ~= "" then
					local abbr = self:AbbrevKey(bKey)
					self.keybindCache[spellName] = abbr
					return abbr
				end
			end
		elseif actionType == "item" and id then
			local iName = GetItemInfo(id)
			if iName and iName == spellName then
				local bKey = GetBindingKey("ACTIONBUTTON" .. i)
				if bKey and bKey ~= "" then
					local abbr = self:AbbrevKey(bKey)
					self.keybindCache[spellName] = abbr
					return abbr
				end
			end
		end
	end

	self.keybindCache[spellName] = ""
	return ""
end

-- ============================================================================
-- Query spell or item cooldown (supporting GCD filtering and showGCD option)
-- ============================================================================
function CM:GetCooldownInfo(spellID, showGCD)
	local data = self:GetSpellData(spellID)
	if data and data.isItem then
		local start, duration, enabled = GetItemCooldown(spellID)
		if not start then return 0, 0, false, 0, false end
		local onCooldown = (enabled == 1 and duration > 1.5)
		local remaining = 0
		if onCooldown then
			remaining = (start + duration) - GetTime()
			if remaining < 0 then remaining = 0; onCooldown = false end
		end
		return start, duration, onCooldown, remaining, false
	end

	local start, duration, enabled = GetSpellCooldown(spellID)
	if not start then
		return 0, 0, false, 0, false
	end

	local isGCD = (duration > 0 and duration <= 1.5)
	local onCooldown
	if showGCD then
		onCooldown = (enabled == 1 and duration > 0)
	else
		onCooldown = (enabled == 1 and duration > 1.5)
	end
	local remaining = 0

	if onCooldown then
		remaining = (start + duration) - GetTime()
		if remaining < 0 then
			remaining = 0
			onCooldown = false
		end
	end

	return start, duration, onCooldown, remaining, isGCD
end

-- ============================================================================
-- Query active player buff in 3.3.5a
-- ============================================================================
function CM:GetPlayerBuff(spellID, spellName)	for i = 1, 40 do
		local name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, _, _, auraSpellId = UnitAura("player", i, "HELPFUL")
		if not name then break end

		if (auraSpellId and auraSpellId == spellID) or (name == spellName) then
			local remaining = 0
			if expirationTime and expirationTime > 0 then
				remaining = expirationTime - GetTime()
				if remaining < 0 then remaining = 0 end
			end
			return true, count or 0, duration or 0, expirationTime or 0, remaining, icon
		end
	end

	return false, 0, 0, 0, 0, nil
end

-- ============================================================================
-- ElvUI-style time formatting helper
-- ============================================================================
function CM:FormatTime(seconds)
	if seconds >= 3600 then
		return format("%dh", floor(seconds / 3600 + 0.5))
	elseif seconds >= 60 then
		return format("%dm", floor(seconds / 60 + 0.5))
	elseif seconds >= 10 then
		return format("%d", floor(seconds + 0.5))
	elseif seconds > 0 then
		return format("%.1f", seconds)
	else
		return ""
	end
end
