local E, L, V, P, G = unpack(ElvUI)
local CC = E:NewModule("ElvUIClickCast", "AceEvent-3.0")
local addonName = ...

local _G = _G
local type, pairs, ipairs, tonumber, tostring, rawget = type, pairs, ipairs, tonumber, tostring, rawget
local tinsert, tremove = table.insert, table.remove
local format = string.format
local strupper, strlower, strmatch, gsub = string.upper, string.lower, string.match, string.gsub

CC.addonName = addonName
CC.version = "0.22.17"
CC.pendingApply = false
CC.pendingScan = false
CC.initialized = false
CC.registeredFrames = CC.registeredFrames or {}
CC.nativeAttrs = CC.nativeAttrs or {}
CC.ownedAttrs = CC.ownedAttrs or {}
CC.nativeMouseWheel = CC.nativeMouseWheel or {}
CC.ownedMouseWheel = CC.ownedMouseWheel or {}
CC.errors = CC.errors or {}
CC.spellbookCache = nil
CC.characterMacroCache = nil

P.elvuiClickCast = P.elvuiClickCast or {}
P.elvuiClickCast.enabled = true
P.elvuiClickCast.alwaysTargeting = "disabled"
P.elvuiClickCast.worldCastingEnabled = false
P.elvuiClickCast.editor = P.elvuiClickCast.editor or { scroll = 0 }


local function CopyDefaults(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    for key, value in pairs(src) do
        if dst[key] == nil then
            if type(value) == "table" then
                dst[key] = {}
                CopyDefaults(dst[key], value)
            else
                dst[key] = value
            end
        elseif type(value) == "table" and type(dst[key]) == "table" then
            CopyDefaults(dst[key], value)
        end
    end
end

local function CopyTable(src)
    if type(src) ~= "table" then return src end
    local dst = {}
    for key, value in pairs(src) do
        dst[key] = type(value) == "table" and CopyTable(value) or value
    end
    return dst
end
CC.CopyTable = CopyTable

local function CreateCellDefaultBindings()
    return {
        { key = "BUTTON1", relation = "ANY", actionType = "TARGET", action = "" },
        { key = "BUTTON2", relation = "ANY", actionType = "MENU", action = "" },
    }
end

local CHARACTER_BINDINGS_SCHEMA = 2

function CC:EnsureDB()
    if not E.db then return nil end

    E.db.elvuiClickCast = E.db.elvuiClickCast or {}
    CopyDefaults(E.db.elvuiClickCast, P.elvuiClickCast)

    local db = E.db.elvuiClickCast
    if rawget(db, "defaultsInitialized") ~= true then
        db.defaultsInitialized = true
    end

    db.editor = db.editor or { scroll = 0 }
    if db.alwaysTargeting ~= "left" and db.alwaysTargeting ~= "any" then
        db.alwaysTargeting = "disabled"
    end

    if db.worldCastingEnabled == true and _G.ElvUI_ClickCastWorldConsent ~= true then
        db.worldCastingEnabled = false
    end
    return db
end

function CC:EnsureCharacterDB(profileDB)
    local charDB = _G.ElvUI_ClickCastCharacterDB
    if type(charDB) ~= "table" then
        charDB = {}
        _G.ElvUI_ClickCastCharacterDB = charDB
    end

    local schema = rawget(charDB, "schema")
    if schema == CHARACTER_BINDINGS_SCHEMA then
        return charDB
    end
    if type(schema) == "number" and schema > CHARACTER_BINDINGS_SCHEMA then
        -- Written by a newer addon version: never restructure or downgrade it.
        return charDB
    end

    -- schema is nil (fresh DB or v1 legacy) or an older value: migrate to v2.
    local db = profileDB or self:EnsureDB()
    local legacyBindings = db and rawget(db, "bindings")
    local legacyAlreadyClaimed = db and rawget(db, "characterBindingsMigrated") == true

    -- v1 kept the flat list in charDB.bindings; move it into the "Default"
    -- profile. A migratedFromProfile marker set by the v1 legacy migration
    -- survives untouched through the v1 -> v2 upgrade.
    local flatBindings = rawget(charDB, "bindings")
    if type(flatBindings) == "table" then
        charDB.profiles = charDB.profiles or {}
        local defaultProfile = charDB.profiles["Default"]
        if type(defaultProfile) ~= "table" then
            defaultProfile = {}
            charDB.profiles["Default"] = defaultProfile
        end
        if type(defaultProfile.bindings) ~= "table" then
            defaultProfile.bindings = flatBindings
        end
        charDB.bindings = nil
    end

    if type(charDB.profiles) ~= "table" then
        charDB.profiles = {}
    end

    if not charDB.profiles["Default"] then
        if type(legacyBindings) == "table" and not legacyAlreadyClaimed then
            -- Pre-characterDB era: bindings lived in the ElvUI profile DB.
            charDB.profiles["Default"] = { bindings = CopyTable(legacyBindings) }
            db.characterBindingsMigrated = true
            charDB.migratedFromProfile = E.data and E.data.keys and E.data.keys.profile or true
        else
            charDB.profiles["Default"] = { bindings = CreateCellDefaultBindings() }
        end
    end

    -- Partial v2 robustness: fill missing profile-management fields.
    if type(charDB.profiles["Default"].bindings) ~= "table" then
        charDB.profiles["Default"].bindings = CreateCellDefaultBindings()
    end
    if type(charDB.activeProfile) ~= "string" or not charDB.profiles[charDB.activeProfile] then
        charDB.activeProfile = "Default"
    end
    charDB.talentProfiles = type(charDB.talentProfiles) == "table" and charDB.talentProfiles or {}
    if type(charDB.talentProfiles[1]) ~= "string" or not charDB.profiles[charDB.talentProfiles[1]] then
        charDB.talentProfiles[1] = "Default"
    end
    if type(charDB.talentProfiles[2]) ~= "string" or not charDB.profiles[charDB.talentProfiles[2]] then
        charDB.talentProfiles[2] = "Default"
    end
    if charDB.autoSwitch ~= true then charDB.autoSwitch = false end

    -- Every profile must expose a table in its bindings key.
    for profileName, profile in pairs(charDB.profiles) do
        if type(profileName) == "string" and type(profile) == "table" then
            if type(profile.bindings) ~= "table" then
                profile.bindings = CreateCellDefaultBindings()
            end
        end
    end

    charDB.bindingsInitialized = true
    charDB.schema = CHARACTER_BINDINGS_SCHEMA
    return charDB
end

function CC:GetBindings()
    local db = self:EnsureDB()
    local charDB = self:EnsureCharacterDB(db)
    if not charDB then return {} end
    local active = type(charDB.activeProfile) == "string" and charDB.activeProfile or "Default"
    return self:GetProfileBindings(active)
end

function CC:SetBindings(bindings)
    local db = self:EnsureDB()
    local charDB = self:EnsureCharacterDB(db)
    if not charDB then return false end
    local profileName = type(charDB.activeProfile) == "string" and charDB.activeProfile or "Default"
    local profile = charDB.profiles[profileName]
    if not profile then
        profile = {}
        charDB.profiles[profileName] = profile
    end
    profile.bindings = type(bindings) == "table" and bindings or {}
    return true
end

function CC:GetProfiles()
    local charDB = self:EnsureCharacterDB()
    local names = {}
    for name in pairs(charDB.profiles or {}) do
        if type(name) == "string" then names[#names + 1] = name end
    end
    if #names == 0 then names[1] = "Default" end
    table.sort(names, function(a, b) return strlower(a) < strlower(b) end)
    return names
end

function CC:GetActiveProfile()
    local charDB = self:EnsureCharacterDB()
    if charDB and type(charDB.activeProfile) == "string" and charDB.profiles and charDB.profiles[charDB.activeProfile] then
        return charDB.activeProfile
    end
    return "Default"
end

function CC:GetProfileBindings(profileName)
    local charDB = self:EnsureCharacterDB()
    if not charDB or not charDB.profiles then return {} end
    local profile = charDB.profiles[profileName]
    if not profile then profile = charDB.profiles["Default"] end
    return profile and profile.bindings or {}
end

function CC:ValidateProfileName(name, excludeName)
    if type(name) ~= "string" then return nil, "Profile name must be text." end
    name = gsub(name, "^%s+", "")
    name = gsub(name, "%s+$", "")
    if name == "" then return nil, "A profile name cannot be empty." end
    local excluded = type(excludeName) == "string" and strlower(excludeName) or nil
    local wanted = strlower(name)
    local charDB = self:EnsureCharacterDB()
    for existing in pairs(charDB.profiles or {}) do
        if type(existing) == "string" and strlower(existing) == wanted and strlower(existing) ~= excluded then
            return nil, "A profile named \"" .. existing .. "\" already exists."
        end
    end
    return name
end

function CC:AddProfile(name, copyFromName)
    local clean, err = self:ValidateProfileName(name)
    if not clean then return false, err end
    local charDB = self:EnsureCharacterDB()
    local bindings
    local source = copyFromName and charDB.profiles and charDB.profiles[copyFromName]
    if source and type(source.bindings) == "table" then
        bindings = {}
        for i, binding in ipairs(source.bindings) do
            bindings[i] = self.CopyTable(binding)
        end
    else
        bindings = CreateCellDefaultBindings()
    end
    charDB.profiles[clean] = { bindings = bindings }
    return true, clean
end

function CC:DuplicateActiveProfile(name)
    return self:AddProfile(name, self:GetActiveProfile())
end

function CC:RenameProfile(oldName, newName)
    local charDB = self:EnsureCharacterDB()
    if not charDB.profiles or not charDB.profiles[oldName] then
        return false, "Profile \"" .. tostring(oldName) .. "\" was not found."
    end
    local clean, err = self:ValidateProfileName(newName, oldName)
    if not clean then return false, err end
    local profile = charDB.profiles[oldName]
    charDB.profiles[clean] = profile
    charDB.profiles[oldName] = nil
    if charDB.activeProfile == oldName then charDB.activeProfile = clean end
    for group, profileName in pairs(charDB.talentProfiles or {}) do
        if profileName == oldName then charDB.talentProfiles[group] = clean end
    end
    return true, clean
end

function CC:DeleteProfile(name)
    local charDB = self:EnsureCharacterDB()
    if not charDB.profiles or not charDB.profiles[name] then
        return false, "Profile \"" .. tostring(name) .. "\" was not found."
    end
    if charDB.activeProfile == name then
        return false, "Cannot delete the active profile. Switch to another profile first."
    end
    local count = 0
    for _ in pairs(charDB.profiles) do count = count + 1 end
    if count <= 1 then
        return false, "Cannot delete the only profile."
    end
    charDB.profiles[name] = nil
    -- Talent-group assignments pointing at the deleted profile fall back to
    -- "Default", which is guaranteed to exist by EnsureCharacterDB.
    for group, profileName in pairs(charDB.talentProfiles or {}) do
        if profileName == name then charDB.talentProfiles[group] = "Default" end
    end
    return true
end

function CC:SetActiveProfile(name)
    local charDB = self:EnsureCharacterDB()
    if not charDB.profiles or not charDB.profiles[name] then
        return false, "Profile \"" .. tostring(name) .. "\" was not found."
    end
    if charDB.activeProfile == name then return true end
    charDB.activeProfile = name
    self:RequestApply("profile switch")
    return true
end

function CC:SetAutoSwitch(enabled)
    local charDB = self:EnsureCharacterDB()
    charDB.autoSwitch = enabled == true
    return true
end

function CC:SetTalentProfile(talentGroup, profileName)
    local charDB = self:EnsureCharacterDB()
    talentGroup = tonumber(talentGroup) or 1
    if talentGroup < 1 or talentGroup > 2 then
        return false, "Talent groups are 1 or 2."
    end
    if not charDB.profiles or not charDB.profiles[profileName] then
        return false, "Profile \"" .. tostring(profileName) .. "\" was not found."
    end
    charDB.talentProfiles = charDB.talentProfiles or {}
    charDB.talentProfiles[talentGroup] = profileName
    return true
end

function CC:GetCurrentTalentGroup()
    local group = GetActiveTalentGroup and GetActiveTalentGroup() or 1
    return tonumber(group) or 1
end

function CC:IsEnabled()
    local db = self:EnsureDB()
    return db and db.enabled ~= false
end

function CC:GetAlwaysTargeting()
    local db = self:EnsureDB()
    return db and db.alwaysTargeting or "disabled"
end

function CC:IsWorldCastingAuthorized()
    return _G.ElvUI_ClickCastWorldConsent == true
end

function CC:IsWorldCastingEnabled()
    local db = self:EnsureDB()
    return db and db.worldCastingEnabled == true and self:IsWorldCastingAuthorized()
end

function CC:SetWorldCastingEnabled(enabled)
    local db = self:EnsureDB()
    if not db then return false end
    if enabled and not self:IsWorldCastingAuthorized() then return false, "confirmation" end
    db.worldCastingEnabled = enabled == true
    self:RequestApply(enabled and "World Casting enabled" or "World Casting disabled")
    return true
end

function CC:AuthorizeWorldCasting(forEditor)
    _G.ElvUI_ClickCastWorldConsent = true
    if forEditor and self.editorFrame and self.editorFrame.sessionActive then
        self.editorFrame.draftWorldCastingEnabled = true
        self.editorFrame.dirty = true
        if self.RefreshWorldCastingButton then self:RefreshWorldCastingButton() end
        if self.RefreshEditor then self:RefreshEditor() end
        if self.EditorMessage then self:EditorMessage("World Casting enabled for this draft. Save Changes to apply it.", "warn") end
    else
        self:SetWorldCastingEnabled(true)
    end
end

function CC:CanWorldCastPhysicalKey(key)
    key = self:NormalizePhysicalKey(key)
    return key ~= "BUTTON1" and key ~= "BUTTON2"
end


local WORLD_ACTION_POLICY = {
    SPELL = true,
    ITEM = true,
    TARGET = true,
    FOCUS = true,
    ASSIST = true,
    MACRO = true,
    CUSTOM = true,
    MENU = false,
}

function CC:ActionSupportsWorldCasting(actionType)
    actionType = actionType or "SPELL"
    return WORLD_ACTION_POLICY[actionType] == true
end

function CC:GetForcedFrameOnlyReason(actionType, key)
    actionType = actionType or "SPELL"
    if not self:ActionSupportsWorldCasting(actionType) then
        if actionType == "MENU" then
            return "Unit Menu requires the registered ElvUI/oUF frame menu provider and is locked to registered frames."
        end
        return "This action type is locked to registered frames."
    end
    if key ~= nil and not self:CanWorldCastPhysicalKey(key) then
        return "Plain unmodified Left and Right Click are always locked to registered frames."
    end
    return nil
end

function CC:IsBindingForcedFrameOnly(binding, keyOverride)
    if not binding then return true end
    local actionType = binding.actionType or "SPELL"
    local key = keyOverride ~= nil and keyOverride or binding.key
    return self:GetForcedFrameOnlyReason(actionType, key) ~= nil
end

function CC:IsBindingWorldCapable(binding, keyOverride)
    if not binding or self:IsBindingForcedFrameOnly(binding, keyOverride) then return false end
    return binding.frameOnly ~= true
end

function CC:EnsureWorldCastingPopup()
    if not _G.StaticPopupDialogs or _G.StaticPopupDialogs["ELVUICLICKCAST_WORLD_CASTING_CONFIRM"] then return end
    _G.StaticPopupDialogs["ELVUICLICKCAST_WORLD_CASTING_CONFIRM"] = {
        text = "Enable World Casting?\n\nEligible bindings, including Saved Macro and Custom Macro, are World-capable by default and may activate outside registered ElvUI frames. Macro bodies execute exactly as authored; ClickCast does not inject or rewrite macro targeting. Individual actions can opt out with Frame Only.\n\nUnit Menu and plain unmodified Left and Right Click always remain frame-only.",
        button1 = "Enable",
        button2 = "Cancel",
        OnAccept = function()
            local forEditor = CC.pendingWorldConsentForEditor == true
            CC.pendingWorldConsentForEditor = false
            CC:AuthorizeWorldCasting(forEditor)
        end,
        OnCancel = function() CC.pendingWorldConsentForEditor = false end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
end

function CC:ShowWorldCastingConfirmation(forEditor)
    self.pendingWorldConsentForEditor = forEditor == true
    local popup = StaticPopup_Show and StaticPopup_Show("ELVUICLICKCAST_WORLD_CASTING_CONFIRM")


    if popup and popup.SetFrameStrata then popup:SetFrameStrata("TOOLTIP") end
    if popup and popup.Raise then popup:Raise() end
    return popup
end

function CC:SetAlwaysTargeting(value)
    local db = self:EnsureDB()
    if not db then return end
    if value ~= "left" and value ~= "any" then value = "disabled" end
    db.alwaysTargeting = value
    self:RequestApply("Always Targeting changed")
end

function CC:Print(message)
    E:Print("ClickCast: " .. tostring(message))
end

function CC:SetError(message)
    self.errors[#self.errors + 1] = tostring(message)
    if #self.errors > 30 then tremove(self.errors, 1) end
end

function CC:GetModifierKey()
    local key = ""
    if IsAltKeyDown() then key = key .. "ALT-" end
    if IsControlKeyDown() then key = key .. "CTRL-" end
    if IsShiftKeyDown() then key = key .. "SHIFT-" end
    return key
end

function CC:NormalizePhysicalKey(key)
    if not key or key == "" then return nil end
    key = strupper(tostring(key))
    key = gsub(key, "LEFTBUTTON", "BUTTON1")
    key = gsub(key, "RIGHTBUTTON", "BUTTON2")
    key = gsub(key, "MIDDLEBUTTON", "BUTTON3")
    return key
end

function CC:MouseButtonToKey(button)
    if button == "LeftButton" then return "BUTTON1" end
    if button == "RightButton" then return "BUTTON2" end
    if button == "MiddleButton" then return "BUTTON3" end
    local n = button and strmatch(button, "^Button(%d+)$")
    if n then return "BUTTON" .. n end
    return nil
end

function CC:BindingDisplay(key)
    key = tostring(key or "")
    key = gsub(key, "ALT%-", "Alt+")
    key = gsub(key, "CTRL%-", "Ctrl+")
    key = gsub(key, "SHIFT%-", "Shift+")
    key = gsub(key, "MOUSEWHEELUP", "Wheel Up")
    key = gsub(key, "MOUSEWHEELDOWN", "Wheel Down")
    key = gsub(key, "BUTTON1", "Left Click")
    key = gsub(key, "BUTTON2", "Right Click")
    key = gsub(key, "BUTTON3", "Middle Click")
    key = gsub(key, "BUTTON(%d+)", "Button %1")
    return key
end

function CC:RelationDisplay(relation)
    if relation == "FRIEND" then return "Help" end
    if relation == "ENEMY" then return "Harm" end
    return "Any"
end

function CC:ActionSupportsRelation(actionType)
    return actionType ~= "MACRO" and actionType ~= "CUSTOM"
end

function CC:IsOpaqueMacroAction(actionType)
    return actionType == "MACRO" or actionType == "CUSTOM"
end

function CC:GetEffectiveSpellRelation(binding, list, bindingIndex)
    if not binding or (binding.actionType or "SPELL") ~= "SPELL" then return binding and (binding.relation or "ANY") or "ANY" end
    local requested = binding.relation or "ANY"
    if requested ~= "ANY" then return requested end

    local key = self:NormalizePhysicalKey(binding.key)
    local otherRelation
    for index, other in ipairs(list or self:GetBindings()) do
        if index ~= bindingIndex
            and other ~= binding
            and (other.actionType or "SPELL") == "SPELL"
            and self:NormalizePhysicalKey(other.key) == key then
            local relation = other.relation or "ANY"
            if relation == "FRIEND" or relation == "ENEMY" then
                if otherRelation and otherRelation ~= relation then return "ANY" end
                otherRelation = relation
            end
        end
    end

    if otherRelation == "FRIEND" then return "ENEMY" end
    if otherRelation == "ENEMY" then return "FRIEND" end
    return "ANY"
end

function CC:BindingRelationDisplay(binding, list, bindingIndex)
    if not binding then return "" end
    local actionType = binding.actionType or "SPELL"
    if self:IsOpaqueMacroAction(actionType) then return "As Authored" end

    local relation = binding.relation or "ANY"
    if actionType == "SPELL" and relation == "ANY" then
        local effective = self:GetEffectiveSpellRelation(binding, list, bindingIndex)
        if effective ~= "ANY" then
            return "Any > " .. self:RelationDisplay(effective)
        end
    end
    return self:RelationDisplay(relation)
end

function CC:GetAvailableSpellRelations(key, editIndex, list)
    local options = {"ANY", "FRIEND", "ENEMY"}
    key = self:NormalizePhysicalKey(key)
    if not key then return options end

    local occupied
    for index, other in ipairs(list or self:GetBindings()) do
        if index ~= editIndex
            and self:NormalizePhysicalKey(other.key) == key
            and (other.actionType or "SPELL") == "SPELL" then
            occupied = other.relation or "ANY"
            break
        end
    end

    if occupied == "ANY" then return {"FRIEND", "ENEMY"} end
    if occupied == "FRIEND" then return {"ENEMY", "ANY"} end
    if occupied == "ENEMY" then return {"FRIEND", "ANY"} end
    return options
end

function CC:ActionTypeDisplay(actionType)
    local values = {
        SPELL = "Spell",
        MACRO = "Macro",
        CUSTOM = "Custom Macro",
        ITEM = "Item / Slot",
        TARGET = "Target",
        FOCUS = "Focus",
        ASSIST = "Assist",
        MENU = "Unit Menu",
    }
    return values[actionType] or tostring(actionType or "")
end

function CC:AlwaysTargetingDisplay(value)
    if value == "left" then return "Left Spell" end
    if value == "any" then return "Any Spells" end
    return "Disabled"
end

function CC:BuildSpellbookCache()
    local byName, entries = {}, {}
    local tabs = GetNumSpellTabs and GetNumSpellTabs() or 0
    local bookType = BOOKTYPE_SPELL or "spell"

    for tab = 1, tabs do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        if offset and numSpells then
            for slot = offset + 1, offset + numSpells do
                local name, rank = GetSpellName(slot, bookType)
                if name then
                    local key = strlower(name)
                    local icon
                    if GetSpellTexture then icon = GetSpellTexture(slot, bookType) end
                    if not icon then
                        local _, _, spellIcon = GetSpellInfo(name)
                        icon = spellIcon
                    end

                    local spellID
                    if GetSpellLink then
                        local link = GetSpellLink(slot, bookType)
                        spellID = link and tonumber(strmatch(link, "spell:(%d+)")) or nil
                    end

                    local entry = byName[key]
                    if not entry then
                        entry = {
                            name = name,
                            rank = rank or "",
                            icon = icon,
                            slot = slot,
                            spellID = spellID,
                        }
                        byName[key] = entry
                    else


                        entry.name = name
                        entry.rank = rank or entry.rank or ""
                        entry.icon = icon or entry.icon
                        entry.slot = slot
                        entry.spellID = spellID or entry.spellID
                    end
                end
            end
        end
    end

    for _, entry in pairs(byName) do tinsert(entries, entry) end
    table.sort(entries, function(a, b) return strlower(a.name) < strlower(b.name) end)
    self.spellbookCache = entries
    self.spellbookByName = byName
    return entries
end

function CC:GetSpellbookEntries(force)
    if force or not self.spellbookCache then return self:BuildSpellbookCache() end
    return self.spellbookCache
end

function CC:ResolveSpell(action)
    if action == nil or action == "" then return nil, "No spell was entered." end

    local numeric = tonumber(action)
    local name, rank, icon
    if numeric then
        name, rank, icon = GetSpellInfo(numeric)
    else
        name, rank, icon = GetSpellInfo(action)
    end

    if not name then
        local wanted = strlower(tostring(action))
        local entries = self:GetSpellbookEntries()
        for _, entry in ipairs(entries) do
            if strlower(entry.name) == wanted then
                name, rank, icon = entry.name, entry.rank, entry.icon
                break
            end
        end
    end

    if not name then
        return nil, "Spell not found. Choose a learned spell or enter a learned Spell ID/name."
    end


    if not self.spellbookByName then self:GetSpellbookEntries() end
    local cached = self.spellbookByName and self.spellbookByName[strlower(name)]
    if cached then
        rank = cached.rank or rank
        icon = cached.icon or icon
    end

    local secureName = name
    local secureRank = rank or ""
    if secureRank ~= "" then


        if strmatch(secureRank, "^%(") then
            secureName = name .. secureRank
        else
            secureName = name .. "(" .. secureRank .. ")"
        end
    end

    return {
        name = name,
        rank = secureRank,
        secureName = secureName,
        icon = icon,
        spellID = numeric or (cached and cached.spellID) or nil,
        spellbookSlot = cached and cached.slot or nil,
    }
end


local function TrimItemInput(value)
    value = tostring(value or "")
    if _G.strtrim then return _G.strtrim(value) end
    value = gsub(value, "^%s+", "")
    value = gsub(value, "%s+$", "")
    return value
end

local function ParseItemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(strmatch(link, "item:(%d+)"))
end

local function GetItemMetadata(token)
    if not GetItemInfo then return nil end
    local name, link, quality, itemLevel, requiredLevel, itemType, itemSubType, stackCount, equipLoc, icon = GetItemInfo(token)
    if not name then return nil end
    return {
        name = name,
        link = link,
        itemID = ParseItemIDFromLink(link),
        icon = icon,
    }
end

function CC:FindOwnedItemByName(action)
    local wanted = strlower(TrimItemInput(action))
    if wanted == "" then return nil end


    if GetInventoryItemLink then
        for slot = 1, 19 do
            local link = GetInventoryItemLink("player", slot)
            if link then
                local info = GetItemMetadata(link)
                if info and strlower(info.name) == wanted then
                    info.ownedSlot = slot
                    return info
                end
            end
        end
    end


    if GetContainerNumSlots and GetContainerItemLink then
        for bag = 0, 4 do
            local count = GetContainerNumSlots(bag) or 0
            for slot = 1, count do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local info = GetItemMetadata(link)
                    if info and strlower(info.name) == wanted then
                        info.ownedBag = bag
                        info.ownedBagSlot = slot
                        return info
                    end
                end
            end
        end
    end
    return nil
end

function CC:ResolveItem(action)
    local raw = TrimItemInput(action)
    if raw == "" then return nil, "Enter an item name, item ID, or equipped slot (1-19)." end

    local lower = strlower(raw)


    local hyperlinkID = tonumber(strmatch(raw, "|Hitem:(%d+)"))
    if hyperlinkID then
        local info = GetItemMetadata(hyperlinkID) or {}
        return {
            kind = "ITEM_ID",
            itemID = hyperlinkID,
            name = info.name,
            link = info.link,
            icon = info.icon or (GetItemIcon and GetItemIcon(hyperlinkID)),
            secureToken = "item:" .. hyperlinkID,
            canonicalAction = "item:" .. hyperlinkID,
            display = info.link or info.name or ("Item ID " .. hyperlinkID),
        }
    end


    local explicitSlot = tonumber(strmatch(lower, "^slot%s*:%s*(%d+)$") or strmatch(lower, "^slot%s+(%d+)$"))
    if explicitSlot then
        if explicitSlot < 1 or explicitSlot > 19 then
            return nil, "Equipped slot must be between 1 and 19."
        end
        local link = GetInventoryItemLink and GetInventoryItemLink("player", explicitSlot) or nil
        local info = link and GetItemMetadata(link) or nil
        return {
            kind = "SLOT",
            slot = explicitSlot,
            name = info and info.name or nil,
            link = link,
            icon = GetInventoryItemTexture and GetInventoryItemTexture("player", explicitSlot) or (info and info.icon),
            secureToken = tostring(explicitSlot),
            canonicalAction = "slot:" .. explicitSlot,
            display = link or ("Equipment Slot " .. explicitSlot),
        }
    end


    local explicitID = tonumber(strmatch(lower, "^item%s*:%s*(%d+)$") or strmatch(lower, "^item%s+(%d+)$"))
    if explicitID then
        if explicitID <= 0 then return nil, "Item ID must be greater than zero." end
        local info = GetItemMetadata(explicitID) or {}
        return {
            kind = "ITEM_ID",
            itemID = explicitID,
            name = info.name,
            link = info.link,
            icon = info.icon or (GetItemIcon and GetItemIcon(explicitID)),
            secureToken = "item:" .. explicitID,
            canonicalAction = "item:" .. explicitID,
            display = info.link or info.name or ("Item ID " .. explicitID),
        }
    end


    local numeric = tonumber(raw)
    if numeric and numeric == math.floor(numeric) then
        if numeric >= 1 and numeric <= 19 then
            return self:ResolveItem("slot:" .. numeric)
        elseif numeric > 19 then
            return self:ResolveItem("item:" .. numeric)
        end
    end


    local info = GetItemMetadata(raw) or self:FindOwnedItemByName(raw)
    if not info then
        return nil, "Item not found by name. Use an exact item name, item:<ID>, or slot:<1-19>."
    end

    local itemID = info.itemID
    return {
        kind = "ITEM_NAME",
        itemID = itemID,
        name = info.name,
        link = info.link,
        icon = info.icon or (itemID and GetItemIcon and GetItemIcon(itemID)),
        secureToken = itemID and ("item:" .. itemID) or info.name,
        canonicalAction = info.name,
        display = info.link or info.name,
    }
end


local function AddUniqueNumber(list, seen, value)
    value = tonumber(value)
    if value and value > 0 and not seen[value] then
        seen[value] = true
        list[#list + 1] = value
    end
end

function CC:BuildCharacterMacroCache()
    local entries = {}
    local _, perChar = GetNumMacros and GetNumMacros() or 0, 0
    if GetNumMacros then
        local globalCount, characterCount = GetNumMacros()
        perChar = characterCount or 0
    end

    local caps, seenCaps = {}, {}
    AddUniqueNumber(caps, seenCaps, _G.MAX_ACCOUNT_MACROS)
    AddUniqueNumber(caps, seenCaps, _G.MAX_GLOBAL_MACROS)

    AddUniqueNumber(caps, seenCaps, 120)
    AddUniqueNumber(caps, seenCaps, 36)

    local best = {}
    if perChar > 0 and GetMacroInfo then
        for _, cap in ipairs(caps) do
            local candidate = {}
            for i = 1, perChar do
                local index = cap + i
                local name, icon, body = GetMacroInfo(index)
                if name and name ~= "" then
                    candidate[#candidate + 1] = { index = index, name = name, icon = icon, body = body or "" }
                end
            end
            if #candidate > #best then best = candidate end
        end
    end


    if perChar > 0 and #best < perChar and GetMacroInfo then
        local candidate = {}
        for index = 37, 220 do
            local name, icon, body = GetMacroInfo(index)
            if name and name ~= "" then
                candidate[#candidate + 1] = { index = index, name = name, icon = icon, body = body or "" }
                if #candidate >= perChar then break end
            end
        end
        if #candidate > #best then best = candidate end
    end

    table.sort(best, function(a, b) return strlower(a.name) < strlower(b.name) end)
    self.characterMacroCache = best
    return best
end

function CC:GetCharacterMacros(force)
    if force or not self.characterMacroCache then return self:BuildCharacterMacroCache() end
    return self.characterMacroCache
end

function CC:ResolveMacro(action)
    local wanted = tostring(action or "")
    if wanted == "" then return nil, "Enter an existing macro name." end


    for _, entry in ipairs(self:GetCharacterMacros()) do
        if entry.name == wanted then return entry end
    end

    if GetMacroIndexByName and GetMacroInfo then
        local index = GetMacroIndexByName(wanted)
        if index and index > 0 then
            local name, icon, body = GetMacroInfo(index)
            if name then return { index = index, name = name, icon = icon, body = body or "" } end
        end
    end
    return nil, "That macro name does not exist."
end

function CC:GetMacroText(action)
    local macro = self:ResolveMacro(action)
    return macro and macro.body or nil
end

function CC:GetBindingActionLabel(binding)
    if not binding then return "" end
    local actionType = binding.actionType or "SPELL"
    local action = binding.action
    local label

    if actionType == "SPELL" then
        local info = self:ResolveSpell(action)
        label = info and info.name or tostring(action or "Invalid Spell")
        if binding.groundCasting == true then label = label .. "  [Ground]" end
    elseif actionType == "ITEM" then
        local item = self:ResolveItem(action)
        label = item and item.display or tostring(action or "")
    elseif actionType == "TARGET" or actionType == "FOCUS" or actionType == "ASSIST" or actionType == "MENU" then
        label = self:ActionTypeDisplay(actionType)
    else
        label = tostring(action or "")
    end

    if self:IsBindingForcedFrameOnly(binding) or binding.frameOnly == true then
        label = label .. "  [Frame Only]"
    end
    return label
end

function CC:GetBindingIcon(binding)
    if not binding then return nil end
    if binding.actionType == "SPELL" then
        local info = self:ResolveSpell(binding.action)
        return info and info.icon
    elseif binding.actionType == "ITEM" then
        local item = self:ResolveItem(binding.action)
        return item and item.icon or nil
    elseif binding.actionType == "MACRO" then
        local macro = self:ResolveMacro(binding.action)
        return macro and macro.icon
    end
    return nil
end

function CC:ValidateBinding(binding)
    if type(binding) ~= "table" then return false, "Binding is missing." end
    local key = self:NormalizePhysicalKey(binding.key)
    if not key or key == "" then return false, "Capture a mouse/key binding first." end

    local actionType = binding.actionType or "SPELL"
    local validType = actionType == "SPELL" or actionType == "MACRO" or actionType == "CUSTOM" or actionType == "ITEM"
        or actionType == "TARGET" or actionType == "FOCUS" or actionType == "ASSIST" or actionType == "MENU"
    if not validType then return false, "Invalid action type." end

    local relation = binding.relation
    if self:IsOpaqueMacroAction(actionType) then
        relation = "ANY"
    else
        if relation == nil or relation == "" then relation = "ANY" end
        if relation ~= "ANY" and relation ~= "FRIEND" and relation ~= "ENEMY" then return false, "Invalid relation." end
    end

    if actionType == "SPELL" then
        local spell, err = self:ResolveSpell(binding.action)
        if not spell then return false, err end
    elseif actionType == "MACRO" then
        local macro, macroErr = self:ResolveMacro(binding.action)
        if not macro then return false, macroErr end
    elseif actionType == "CUSTOM" then
        if not binding.action or binding.action == "" then return false, "Enter macro text." end
    elseif actionType == "ITEM" then
        local item, itemErr = self:ResolveItem(binding.action)
        if not item then return false, itemErr end
    end
    return true
end

function CC:ValidateBindingAgainstList(binding, editIndex, list)
    local ok, err = self:ValidateBinding(binding)
    if not ok then return false, err end
    list = list or self:GetBindings()

    local key = self:NormalizePhysicalKey(binding.key)
    local actionType = binding.actionType or "SPELL"
    local relation = binding.relation or "ANY"
    local sameKey = {}
    for index, other in ipairs(list) do
        if index ~= editIndex and self:NormalizePhysicalKey(other.key) == key then
            sameKey[#sameKey + 1] = { index = index, binding = other }
        end
    end


    if #sameKey >= 2 then
        return false, self:BindingDisplay(key) .. " already has two actions. Edit or remove one before adding another."
    end


    if self:IsOpaqueMacroAction(actionType) then
        if #sameKey > 0 then
            return false, self:ActionTypeDisplay(actionType) .. " runs exactly as authored and must own " .. self:BindingDisplay(key) .. " exclusively."
        end
        return true
    end

    for _, entry in ipairs(sameKey) do
        local other = entry.binding
        local otherType = other.actionType or "SPELL"
        if self:IsOpaqueMacroAction(otherType) then
            return false, self:ActionTypeDisplay(otherType) .. " already owns " .. self:BindingDisplay(key) .. " exclusively."
        end


        if actionType == "SPELL" or otherType == "SPELL" then
            if actionType ~= "SPELL" or otherType ~= "SPELL" then
                return false, self:BindingDisplay(key) .. " cannot mix Spell with " .. self:ActionTypeDisplay(actionType == "SPELL" and otherType or actionType) .. "."
            end
            if (other.relation or "ANY") == relation then
                return false, self:BindingDisplay(key) .. " already has a Spell for " .. self:RelationDisplay(relation) .. "."
            end
        elseif (other.relation or "ANY") == relation then
            return false, self:BindingDisplay(key) .. " is already bound for " .. self:RelationDisplay(relation) .. ". Edit or remove the existing binding first."
        end
    end
    return true
end

function CC:NormalizeBindingForStorage(binding)
    if type(binding) ~= "table" then return nil end
    local actionType = binding.actionType or "SPELL"
    local normalizedAction = binding.action
    if actionType == "ITEM" then
        local item = self:ResolveItem(binding.action)
        if item then normalizedAction = item.canonicalAction end
    end

    local normalizedKey = self:NormalizePhysicalKey(binding.key)
    local normalized = {
        key = normalizedKey,
        relation = self:IsOpaqueMacroAction(actionType) and "ANY" or (binding.relation or "ANY"),
        actionType = actionType,
        action = normalizedAction,
        groundCasting = actionType == "SPELL" and binding.groundCasting == true or nil,
    }


    if not self:IsBindingForcedFrameOnly(normalized, normalizedKey) and binding.frameOnly == true then
        normalized.frameOnly = true
    end
    return normalized
end

function CC:SaveBinding(binding, editIndex)
    local ok, err = self:ValidateBindingAgainstList(binding, editIndex, self:GetBindings())
    if not ok then return false, err end
    local bindings = self:GetBindings()
    local copy = self:NormalizeBindingForStorage(binding)
    if not copy then return false, "Binding could not be normalized." end
    if editIndex and bindings[editIndex] then bindings[editIndex] = copy else tinsert(bindings, copy) end
    self:RequestApply("binding saved")
    return true
end

function CC:DeleteBinding(index)
    local bindings = self:GetBindings()
    if bindings[index] then
        tremove(bindings, index)
        self:RequestApply("binding deleted")
        return true
    end
    return false, "Binding was not found."
end

function CC:SetEnabled(enabled)
    local db = self:EnsureDB()
    if not db then return end
    db.enabled = not not enabled
    self:RequestApply(enabled and "enabled" or "disabled")
end

function CC:RequestApply(reason)
    if InCombatLockdown() then
        self.pendingApply = true
        if reason then self.pendingReason = reason end
        if self.RefreshEditor then self:RefreshEditor() end
        return
    end
    self.pendingApply = false
    if self.ApplyBindings then self:ApplyBindings() end
    if self.RefreshEditor then self:RefreshEditor() end
end

function CC:PLAYER_REGEN_ENABLED()


    local queuedApply = self.pendingApply == true
    self.pendingApply = false

    if queuedApply and self.ApplyBindings then
        self:ApplyBindings()
    end

    if self.pendingScan and self.ScanClickCastFrames then
        self.pendingScan = false
        self:ScanClickCastFrames()
    end

    if self.RefreshEditor then self:RefreshEditor() end
end

function CC:SPELLS_CHANGED()
    self:GetSpellbookEntries(true)


    self:RequestApply("spellbook updated")
    if self.RefreshSpellPicker then self:RefreshSpellPicker() end
    if self.RefreshEditor then self:RefreshEditor() end
end

function CC:UPDATE_MACROS()
    self:GetCharacterMacros(true)


    self:RequestApply("macros updated")
    if self.RefreshMacroPicker then self:RefreshMacroPicker() end
    if self.RefreshEditor then self:RefreshEditor() end
end

function CC:PLAYER_ENTERING_WORLD()
    self:GetSpellbookEntries(true)
    if self.ScanClickCastFrames then self:ScanClickCastFrames() end
    self:RequestApply("entering world")
    E:Delay(1, function() if CC.ScanClickCastFrames then CC:ScanClickCastFrames() end end)
    E:Delay(3, function() if CC.ScanClickCastFrames then CC:ScanClickCastFrames() end end)
end

function CC:GroupChanged()
    if InCombatLockdown() then self.pendingScan = true return end
    if self.ScanClickCastFrames then self:ScanClickCastFrames() end
end

function CC:OnTalentGroupChanged()
    local charDB = self:EnsureCharacterDB()
    if not charDB.autoSwitch then return end
    local group = self:GetCurrentTalentGroup()
    local target = charDB.talentProfiles and charDB.talentProfiles[group]
    if target and target ~= charDB.activeProfile and charDB.profiles and charDB.profiles[target] then
        self:SetActiveProfile(target)
        -- The open editor draft belongs to the previously active profile.
        -- Restarting the session prevents a dirty draft from being committed
        -- into the profile we just switched to.
        local f = self.editorFrame
        if f and f:IsShown() and f.sessionActive then
            if f.dirty then
                self:CancelEditorChanges()
                self:RefreshEditor()
            else
                self:BeginEditorSession(true)
                self:RefreshEditor()
            end
            self:EditorMessage("Talent group changed: profile \"" .. tostring(target) .. "\" is now active.", "normal")
        end
    end
end

function CC:RefreshAfterElvUIProfileChange(reason)


    self.profileRefreshSerial = (self.profileRefreshSerial or 0) + 1
    local serial = self.profileRefreshSerial
    E:Delay(0, function()
        if serial ~= CC.profileRefreshSerial then return end

        CC:EnsureDB()
        if InCombatLockdown() then
            CC.pendingApply = true
            CC.pendingScan = true
        else
            if CC.ScanClickCastFrames then CC:ScanClickCastFrames() end
            CC:RequestApply(reason or "ElvUI profile changed")
        end


        local f = CC.editorFrame
        if f and f:IsShown() then
            if CC.CloseSelectMenu then CC:CloseSelectMenu() end
            if CC.CloseSpellPicker then CC:CloseSpellPicker() end
            if CC.CloseMacroPicker then CC:CloseMacroPicker() end
            if CC.CloseCustomMacroWriter then CC:CloseCustomMacroWriter() end
            if CC.StopInlineBindingCapture then CC:StopInlineBindingCapture(true) end
            if CC.BeginEditorSession then CC:BeginEditorSession(true) end
            if CC.RefreshEditor then CC:RefreshEditor() end
            if CC.EditorMessage then CC:EditorMessage("Active ElvUI profile changed; ClickCast reloaded this profile.", "normal") end
        elseif CC.RefreshEditor then
            CC:RefreshEditor()
        end
    end)
end

function CC:OnElvUIProfileChanged()
    self:RefreshAfterElvUIProfileChange("ElvUI profile changed")
end

function CC:OnElvUIProfileCopied()
    self:RefreshAfterElvUIProfileChange("ElvUI profile copied")
end

function CC:OnElvUIProfileDeleted(_, profileName)
end

function CC:EnsureCliqueConflictPopup()
    if not E.PopupDialogs or E.PopupDialogs.ELVUICLICKCAST_CLIQUE_CONFLICT then return end

    E.PopupDialogs.ELVUICLICKCAST_CLIQUE_CONFLICT = {
        text = "ElvUI_ClickCast has detected an incompatible click cast addon: |cffff3333Clique|r\n\nOnly one Click Casting addon can be active at a time.",
        button1 = "Disable It",
        button2 = "Disable ElvUI_ClickCast",
        OnAccept = function()
            DisableAddOn("Clique")
            ReloadUI()
        end,
        OnCancel = function()
            DisableAddOn(CC.addonName or "ElvUI_ClickCast")
            ReloadUI()
        end,
        whileDead = 1,
        hideOnEscape = false,
        noCancelOnReuse = true,
        showAlert = 1,
    }
end

function CC:ShowCliqueConflict()
    if not (IsAddOnLoaded and IsAddOnLoaded("Clique")) then return false end
    self.cliqueConflictDetected = true
    self:EnsureCliqueConflictPopup()
    if E.StaticPopup_Show then
        E:StaticPopup_Show("ELVUICLICKCAST_CLIQUE_CONFLICT")
    elseif StaticPopup_Show then
        StaticPopup_Show("ELVUICLICKCAST_CLIQUE_CONFLICT")
    end
    return true
end

function CC:ADDON_LOADED(_, loadedAddon)
    if loadedAddon == "Clique" then self:ShowCliqueConflict() end
end

function CC:Initialize()
    self:EnsureDB()
    self.initialized = true
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("PARTY_MEMBERS_CHANGED", "GroupChanged")
    self:RegisterEvent("RAID_ROSTER_UPDATE", "GroupChanged")
    pcall(function() self:RegisterEvent("SPELLS_CHANGED") end)
    pcall(function() self:RegisterEvent("LEARNED_SPELL_IN_TAB", "SPELLS_CHANGED") end)
    pcall(function() self:RegisterEvent("UPDATE_MACROS") end)
    pcall(function() self:RegisterEvent("ADDON_LOADED") end)
    pcall(function() self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", "OnTalentGroupChanged") end)
    pcall(function() self:RegisterEvent("PLAYER_TALENT_UPDATE", "OnTalentGroupChanged") end)

    if E.data and E.data.RegisterCallback then
        E.data.RegisterCallback(self, "OnProfileChanged", "OnElvUIProfileChanged")
        E.data.RegisterCallback(self, "OnProfileCopied", "OnElvUIProfileCopied")
        E.data.RegisterCallback(self, "OnProfileDeleted", "OnElvUIProfileDeleted")
    end

    self:EnsureWorldCastingPopup()
    self:EnsureCliqueConflictPopup()
    self:ShowCliqueConflict()
    if self.InitializeSecureEngine then self:InitializeSecureEngine() end
    if self.InitializeEditor then self:InitializeEditor() end
    if self.InitializeOptions then self:InitializeOptions() end

    E:Delay(0.2, function()
        if CC.ScanClickCastFrames then CC:ScanClickCastFrames() end
        CC:RequestApply("initialization")
    end)
end

SLASH_ELVUICLICKCAST1 = "/ecc"
SLASH_ELVUICLICKCAST2 = "/clickcast"
SlashCmdList.ELVUICLICKCAST = function(msg)
    msg = strlower(tostring(msg or ""))
    if msg == "status" then
        local count = 0
        for _ in pairs(CC.registeredFrames) do count = count + 1 end
        CC:Print(format("%d registered ElvUI frames, %d saved bindings, Always Targeting: %s, World Casting: %s%s.", count, #CC:GetBindings(), CC:AlwaysTargetingDisplay(CC:GetAlwaysTargeting()), CC:IsWorldCastingEnabled() and "Enabled" or "Disabled", CC.cliqueConflictDetected and "; Clique conflict detected" or ""))
        if CC.GetCompiledPlanStatsText then CC:Print(CC:GetCompiledPlanStatsText()) end
        if CC.GetWorldCastingStatsText then CC:Print(CC:GetWorldCastingStatsText()) end
    elseif msg == "stats" then
        CC:Print(CC.GetCompiledPlanStatsText and CC:GetCompiledPlanStatsText() or "Compile counters are unavailable.")
        if CC.GetWorldCastingStatsText then CC:Print(CC:GetWorldCastingStatsText()) end
    elseif strmatch(msg, "^key%s+") then
        local key = CC:NormalizePhysicalKey(strmatch(msg, "^key%s+(.+)$"))
        if key then
            local native = GetBindingAction and GetBindingAction(key, false) or ""
            local effective = GetBindingAction and GetBindingAction(key, true) or ""
            CC:Print(format("Key %s: native=%s; effective=%s%s", key, native ~= "" and native or "NONE", effective ~= "" and effective or "NONE", native == effective and "; override=NO" or "; override=YES"))
        else
            CC:Print("Usage: /ecc key <physical key>, for example /ecc key Q")
        end
    elseif msg == "apply" then
        CC:RequestApply("slash command")
        CC:Print(InCombatLockdown() and "Binding apply queued until combat ends." or "Bindings reapplied.")
    else
        if CC.ShowEditor then CC:ShowEditor() end
    end
end

local function InitializeCallback() CC:Initialize() end
E:RegisterModule(CC:GetName(), InitializeCallback)
