local E, L, V, P, G = unpack(ElvUI)
local CC = E:GetModule("ElvUIClickCast")

local _G = _G
local type, pairs, ipairs, tonumber, tostring = type, pairs, ipairs, tonumber, tostring
local format = string.format
local strmatch, strlower, strsub, gsub = string.match, string.lower, string.sub, string.gsub
local tinsert = table.insert

local function AttributeName(prefix, attribute, suffix)
    prefix = prefix or ""
    suffix = tostring(suffix)
    local lead = prefix ~= "" and (prefix .. "-") or ""
    local tail = tonumber(suffix) and suffix or ("-" .. suffix)
    return lead .. attribute .. tail
end

local function GetMouseParts(key)
    local n = strmatch(key or "", "BUTTON(%d+)$")
    if not n then return nil end
    local token = "BUTTON" .. n
    local prefix = strsub(key, 1, #key - #token)
    prefix = gsub(prefix, "%-$", "")
    prefix = strlower(prefix)
    return prefix, tostring(tonumber(n))
end

function CC:IsEligibleFrame(frame)
    if not frame or type(frame.GetName) ~= "function" or type(frame.SetAttribute) ~= "function" then return false end
    local name = frame:GetName()
    if not name or not strmatch(name, "^ElvUF_") then return false end
    if name == "ElvUF_Parent" then return false end


    local unit = frame.GetAttribute and frame:GetAttribute("unit") or nil
    if not unit or unit == "" then unit = frame.unit end
    if type(unit) ~= "string" or unit == "" then return false end
    if strmatch(strlower(unit), "^nameplate") then return false end
    return true
end

function CC:OwnAttribute(frame, attr, value)
    self.nativeAttrs[frame] = self.nativeAttrs[frame] or {}
    self.ownedAttrs[frame] = self.ownedAttrs[frame] or {}
    if not self.nativeAttrs[frame][attr] then self.nativeAttrs[frame][attr] = { value = frame:GetAttribute(attr) } end
    frame:SetAttribute(attr, value)
    self.ownedAttrs[frame][attr] = { value = value }
end

function CC:RestoreOwnedAttributes(frame)
    local owned, native = self.ownedAttrs[frame], self.nativeAttrs[frame]
    if not owned then return end
    for attr, record in pairs(owned) do
        local current = frame:GetAttribute(attr)
        if native and native[attr] and current ~= record.value then native[attr].value = current end
        frame:SetAttribute(attr, native and native[attr] and native[attr].value or nil)
    end
    self.ownedAttrs[frame], self.nativeAttrs[frame] = nil, nil
end


local function AssignCompiledBranch(group, relation, binding)
    if group.branches[relation] then return false end
    group.branches[relation] = binding
    return true
end

local function IsUnmodifiedLeft(group)
    return group and group.prefix == "" and tostring(group.suffix) == "1"
end

local function SpellRequiresSelectedTarget(self, group)
    local always = self:GetAlwaysTargeting()
    return always == "any" or (always == "left" and IsUnmodifiedLeft(group))
end

local deadOnlySpellNames
local function BuildDeadOnlySpellNames()
    if deadOnlySpellNames then return deadOnlySpellNames end
    deadOnlySpellNames = {}
    for _, spellID in ipairs({61999, 20484, 50769, 7328, 2006, 2008}) do
        local name = GetSpellInfo and GetSpellInfo(spellID)
        if name then deadOnlySpellNames[strlower(name)] = true end
    end
    return deadOnlySpellNames
end

local function GetSpellLifeCondition(spell)
    if spell and spell.name and BuildDeadOnlySpellNames()[strlower(spell.name)] then
        return "dead"
    end
    return "nodead"
end

function CC:BuildCompiledBindings()
    self.compileRevision = (self.compileRevision or 0) + 1
    local compiled = {
        keys = {}, keyOrder = {}, hoverKeys = {}, frameWrites = {}, needsMouseWheel = false,
        stats = {
            revision = self.compileRevision,
            keyPlans = 0,
            actionDescriptorAttempts = 0,
            actionDescriptors = 0,
            spellMacroBuilds = 0,
            macroBodyResolutions = 0,
            attributeDescriptors = 0,
            worldPolicyLockedDescriptors = 0,
            explicitFrameOnlyDescriptors = 0,
            frameApplications = 0,
            attributeWritesApplied = 0,
            perFramePayloadBuilds = 0,
        },
    }

    for index, binding in ipairs(self:GetBindings()) do
        local ok, err = self:ValidateBinding(binding)
        if ok then
            local key = self:NormalizePhysicalKey(binding.key)
            local group = compiled.keys[key]
            if not group then
                group = { key = key, branches = {} }
                compiled.keys[key] = group
                tinsert(compiled.keyOrder, key)
            end

            local actionType = binding.actionType or "SPELL"
            local configuredRelation = self:IsOpaqueMacroAction(actionType) and "ANY" or (binding.relation or "ANY")
            if not AssignCompiledBranch(group, configuredRelation, binding) then
                self:SetError("Binding " .. index .. ": " .. self:BindingDisplay(key) .. " already has a " .. self:RelationDisplay(configuredRelation) .. " binding. The later conflicting row was not compiled.")
            end
        else
            self:SetError("Binding " .. index .. ": " .. tostring(err))
        end
    end

    local virtualIndex = 0
    for _, key in ipairs(compiled.keyOrder) do
        local group = compiled.keys[key]
        local prefix, suffix = GetMouseParts(key)
        if prefix then
            group.prefix, group.suffix, group.hover = prefix, suffix, false
        else
            virtualIndex = virtualIndex + 1
            group.prefix, group.suffix, group.hover = "", "ecc" .. virtualIndex, true
            tinsert(compiled.hoverKeys, { key = key, suffix = group.suffix })
        end

        local any = group.branches.ANY
        local friend = group.branches.FRIEND
        local enemy = group.branches.ENEMY
        group.hasSpell = (any and any.actionType == "SPELL")
            or (friend and friend.actionType == "SPELL")
            or (enemy and enemy.actionType == "SPELL")
            or false

        if group.hasSpell then


            for relation, binding in pairs(group.branches) do
                if binding and binding.actionType ~= "SPELL" then
                    self:SetError(self:BindingDisplay(key) .. ": " .. self:ActionTypeDisplay(binding.actionType) .. " / " .. self:RelationDisplay(relation) .. " is suppressed because a Spell binding owns this physical key.")
                end
            end

            any = any and any.actionType == "SPELL" and any or nil
            friend = friend and friend.actionType == "SPELL" and friend or nil
            enemy = enemy and enemy.actionType == "SPELL" and enemy or nil
            group.branches = {}
            group.spellBranches = {}

            if any and friend and enemy then


                self:SetError(self:BindingDisplay(key) .. ": legacy Any + Help + Harm Spell trio is invalid. Any was suppressed; edit this key to a maximum of two Spell rows.")
                group.spellBranches.FRIEND = friend
                group.spellBranches.ENEMY = enemy
            elseif any and friend then
                group.spellBranches.FRIEND = friend
                group.spellBranches.ENEMY = any
                group.anyEffective = "ENEMY"
            elseif any and enemy then
                group.spellBranches.FRIEND = any
                group.spellBranches.ENEMY = enemy
                group.anyEffective = "FRIEND"
            elseif any then
                group.spellBranches.ANY = any
                group.anyEffective = "ANY"
            else
                group.spellBranches.FRIEND = friend
                group.spellBranches.ENEMY = enemy
            end
        else

            local opaque = any and self:IsOpaqueMacroAction(any.actionType or "") and any or nil
            if opaque then
                for relation, binding in pairs(group.branches) do
                    if binding ~= opaque then
                        self:SetError(self:BindingDisplay(key) .. ": " .. self:ActionTypeDisplay(binding.actionType) .. " / " .. self:RelationDisplay(relation) .. " was suppressed because " .. self:ActionTypeDisplay(opaque.actionType) .. " owns this key exactly as authored.")
                    end
                end
                group.branches = { ANY = opaque }
            end
        end

        if strmatch(key, "MOUSEWHEELUP$") or strmatch(key, "MOUSEWHEELDOWN$") then
            compiled.needsMouseWheel = true
        end


        compiled.keys[key] = self:CompileKeyActionPlan(group, compiled)
    end


    compiled.world = self:BuildCompiledWorldPlan(compiled)
    return compiled
end

local function SpellUsesGroundCasting(binding)
    return binding and binding.actionType == "SPELL" and binding.groundCasting == true
end

local function AddCompiledWrite(writes, attr, value)
    writes[#writes + 1] = { attr = attr, value = value }
end

function CC:BuildSingleSpellMacro(group, binding, targetUnit, stats)
    if not binding or binding.actionType ~= "SPELL" then return nil end
    local spell = self:ResolveSpell(binding.action)
    if not spell then return nil end

    if stats then stats.spellMacroBuilds = stats.spellMacroBuilds + 1 end

    local condition = GetSpellLifeCondition(spell)
    local macro = "/cast [" .. (targetUnit or "@mouseover") .. "," .. condition .. "] " .. spell.secureName

    if SpellRequiresSelectedTarget(self, group) then


        macro = "/target [@mouseover]\n" .. macro
    end
    if spell.spellID ~= 370665 then
        macro = macro .. "\n/stopspelltarget"
    end
    return macro
end


function CC:CompileActionDescriptor(group, binding, relation, stats)
    if not binding then return nil end
    stats.actionDescriptorAttempts = stats.actionDescriptorAttempts + 1
    if self._applyingFrameBindings then
        stats.perFramePayloadBuilds = (stats.perFramePayloadBuilds or 0) + 1
    end

    local actionType = binding.actionType or "SPELL"
    local forcedFrameOnlyReason = self:GetForcedFrameOnlyReason(actionType, group and group.key or binding.key)
    local explicitFrameOnly = forcedFrameOnlyReason == nil and binding.frameOnly == true
    local descriptor = {
        actionType = actionType,
        configuredRelation = binding.relation or "ANY",
        effectiveRelation = relation or "ANY",
        action = binding.action,
        worldCapable = forcedFrameOnlyReason == nil and not explicitFrameOnly,
        frameOnly = forcedFrameOnlyReason ~= nil or explicitFrameOnly,
        forcedFrameOnly = forcedFrameOnlyReason ~= nil,
        forcedFrameOnlyReason = forcedFrameOnlyReason,
    }

    if stats then
        if forcedFrameOnlyReason then
            stats.worldPolicyLockedDescriptors = (stats.worldPolicyLockedDescriptors or 0) + 1
        elseif explicitFrameOnly then
            stats.explicitFrameOnlyDescriptors = (stats.explicitFrameOnlyDescriptors or 0) + 1
        end
    end

    if actionType == "SPELL" then
        descriptor.groundCasting = SpellUsesGroundCasting(binding)
        descriptor.targetUnit = descriptor.groundCasting and "@player" or "@mouseover"
        descriptor.secureType = "macro"
        descriptor.macrotext = self:BuildSingleSpellMacro(group, binding, descriptor.targetUnit, stats)
        if not descriptor.macrotext then return nil end
    elseif actionType == "MACRO" then
        stats.macroBodyResolutions = stats.macroBodyResolutions + 1
        descriptor.secureType = "macro"
        descriptor.macrotext = self:GetMacroText(binding.action)
        if not descriptor.macrotext then return nil end
    elseif actionType == "CUSTOM" then
        descriptor.secureType = "macro"
        descriptor.macrotext = tostring(binding.action or "")
    elseif actionType == "ITEM" then


        local item = self:ResolveItem(binding.action)
        if not item then return nil end
        descriptor.secureType = "item"
        descriptor.item = item.secureToken
        descriptor.itemKind = item.kind
        descriptor.itemID = item.itemID
        descriptor.itemSlot = item.slot
    elseif actionType == "TARGET" or actionType == "FOCUS" or actionType == "ASSIST" or actionType == "MENU" then
        descriptor.secureType = strlower(actionType)
    else
        return nil
    end

    stats.actionDescriptors = stats.actionDescriptors + 1
    return descriptor
end

local function AppendActionDescriptorWrites(writes, prefix, suffix, descriptor)
    if not descriptor then return end

    AddCompiledWrite(writes, AttributeName(prefix, "type", suffix), descriptor.secureType)
    if descriptor.secureType == "macro" then
        AddCompiledWrite(writes, AttributeName(prefix, "macro", suffix), nil)
        AddCompiledWrite(writes, AttributeName(prefix, "macrotext", suffix), descriptor.macrotext)
    elseif descriptor.secureType == "item" then
        AddCompiledWrite(writes, AttributeName(prefix, "item", suffix), descriptor.item)
    end
end


function CC:CompileKeyActionPlan(group, compiled)
    local stats = compiled.stats
    local prefix, suffix = group.prefix, group.suffix
    local plan = {
        key = group.key,
        prefix = prefix,
        suffix = suffix,
        hover = group.hover and true or false,
        mode = "EMPTY",
        kind = group.hasSpell and "SPELL" or "GENERAL",
        anyEffective = group.anyEffective,
    }
    local writes = {}

    if group.hasSpell then
        local spellBranches = group.spellBranches or {}
        if spellBranches.ANY then
            plan.mode = "ANY"
            plan.any = self:CompileActionDescriptor(group, spellBranches.ANY, "ANY", stats)
            AppendActionDescriptorWrites(writes, prefix, suffix, plan.any)
        else
            plan.mode = "ROUTED"

            AddCompiledWrite(writes, AttributeName(prefix, "type", suffix), "")

            if spellBranches.FRIEND then
                local friendSuffix = "friend" .. tostring(suffix)
                plan.friend = self:CompileActionDescriptor(group, spellBranches.FRIEND, "FRIEND", stats)
                plan.friendSuffix = friendSuffix
                AddCompiledWrite(writes, AttributeName(prefix, "helpbutton", suffix), friendSuffix)
                AppendActionDescriptorWrites(writes, prefix, friendSuffix, plan.friend)
            end

            if spellBranches.ENEMY then
                local enemySuffix = "enemy" .. tostring(suffix)
                plan.enemy = self:CompileActionDescriptor(group, spellBranches.ENEMY, "ENEMY", stats)
                plan.enemySuffix = enemySuffix
                AddCompiledWrite(writes, AttributeName(prefix, "harmbutton", suffix), enemySuffix)
                AppendActionDescriptorWrites(writes, prefix, enemySuffix, plan.enemy)
            end
        end
    else
        local branches = group.branches or {}
        if branches.ANY then
            plan.mode = "ANY"
            plan.any = self:CompileActionDescriptor(group, branches.ANY, "ANY", stats)
            AppendActionDescriptorWrites(writes, prefix, suffix, plan.any)
        elseif branches.FRIEND or branches.ENEMY then
            plan.mode = "ROUTED"
            AddCompiledWrite(writes, AttributeName(prefix, "type", suffix), "")
        end

        if branches.FRIEND then
            local friendSuffix = "friend" .. tostring(suffix)
            plan.mode = branches.ANY and "ANY_FALLBACK" or "ROUTED"
            plan.friend = self:CompileActionDescriptor(group, branches.FRIEND, "FRIEND", stats)
            plan.friendSuffix = friendSuffix
            AddCompiledWrite(writes, AttributeName(prefix, "helpbutton", suffix), friendSuffix)
            AppendActionDescriptorWrites(writes, prefix, friendSuffix, plan.friend)
        end

        if branches.ENEMY then
            local enemySuffix = "enemy" .. tostring(suffix)
            plan.mode = branches.ANY and "ANY_FALLBACK" or "ROUTED"
            plan.enemy = self:CompileActionDescriptor(group, branches.ENEMY, "ENEMY", stats)
            plan.enemySuffix = enemySuffix
            AddCompiledWrite(writes, AttributeName(prefix, "harmbutton", suffix), enemySuffix)
            AppendActionDescriptorWrites(writes, prefix, enemySuffix, plan.enemy)
        end
    end

    stats.keyPlans = stats.keyPlans + 1
    stats.attributeDescriptors = stats.attributeDescriptors + #writes

    for i = 1, #writes do
        compiled.frameWrites[#compiled.frameWrites + 1] = writes[i]
    end


    return plan
end


local function WorldPlanAddStateKey(stateTable, key, suffix)
    stateTable[#stateTable + 1] = { key = key, suffix = tostring(suffix) }
end

function CC:BuildCompiledWorldPlan(compiled)
    local world = {
        writes = {}, keys = {}, frameRelays = {},
        states = { HELP = {}, HARM = {}, OTHER = {}, NONE = {} },
        enabledActionCount = 0,
        noMouseoverItemKeyCount = 0,
        noMouseoverMacroKeyCount = 0,
        spellActionCount = 0,
        macroActionCount = 0,
        nativeActionCount = 0,
        forcedFrameOnlyKeyCount = 0,
    }
    local worldIndex = 0

    local function IsWorldCapable(descriptor)
        return descriptor and descriptor.worldCapable == true
    end

    local function CountWorldDescriptor(descriptor)
        if not IsWorldCapable(descriptor) then return end
        world.enabledActionCount = world.enabledActionCount + 1
        if descriptor.actionType == "SPELL" then
            world.spellActionCount = world.spellActionCount + 1
        elseif descriptor.actionType == "MACRO" or descriptor.actionType == "CUSTOM" then
            world.macroActionCount = world.macroActionCount + 1
        else
            world.nativeActionCount = world.nativeActionCount + 1
        end
    end

    for _, key in ipairs(compiled.keyOrder or {}) do
        local plan = compiled.keys[key]
        if plan then
            if (plan.any or plan.friend or plan.enemy) and not self:CanWorldCastPhysicalKey(key) then
                world.forcedFrameOnlyKeyCount = world.forcedFrameOnlyKeyCount + 1
            end


            local any = IsWorldCapable(plan.any) and plan.any or nil
            local friend = IsWorldCapable(plan.friend) and plan.friend or nil
            local enemy = IsWorldCapable(plan.enemy) and plan.enemy or nil

            local helpEffective = plan.friend or plan.any
            local harmEffective = plan.enemy or plan.any
            local otherEffective = plan.any
            local helpActive = IsWorldCapable(helpEffective)
            local harmActive = IsWorldCapable(harmEffective)
            local otherActive = IsWorldCapable(otherEffective)


            local noneItem = IsWorldCapable(plan.any)
                and plan.any.secureType == "item"
                and plan.any.effectiveRelation == "ANY"
                and plan.any or nil
            local noneMacro = IsWorldCapable(plan.any)
                and plan.any.secureType == "macro"
                and (plan.any.actionType == "MACRO" or plan.any.actionType == "CUSTOM")
                and plan.any.effectiveRelation == "ANY"
                and plan.any or nil
            local noneActive = noneItem ~= nil or noneMacro ~= nil

            if helpActive or harmActive or otherActive or noneActive then
                if self:CanWorldCastPhysicalKey(key) then
                    worldIndex = worldIndex + 1
                    local suffix = "eccworld" .. tostring(worldIndex)
                    local prefix = ""
                    local entry = {
                        key = key,
                        suffix = suffix,
                        frameSuffix = plan.hover and plan.suffix or nil,
                        any = any, friend = friend, enemy = enemy,
                        helpActive = helpActive, harmActive = harmActive, otherActive = otherActive,
                        noneActive = noneActive, noneItem = noneItem, noneMacro = noneMacro,
                    }
                    world.keys[#world.keys + 1] = entry
                    if entry.frameSuffix then
                        world.frameRelays[#world.frameRelays + 1] = entry
                    end


                    if not world.hasMouseoverUnit then
                        AddCompiledWrite(world.writes, "unit", "mouseover")
                        world.hasMouseoverUnit = true
                    end

                    if any then
                        if any.secureType == "macro"
                            and (any.actionType == "MACRO" or any.actionType == "CUSTOM")
                        then
                            AddCompiledWrite(world.writes, AttributeName(prefix, "unit", suffix), "none")
                        end
                        AppendActionDescriptorWrites(world.writes, prefix, suffix, any)
                    elseif friend or enemy then
                        AddCompiledWrite(world.writes, AttributeName(prefix, "type", suffix), "")
                    end

                    if friend then
                        local friendSuffix = "friend" .. suffix
                        AddCompiledWrite(world.writes, AttributeName(prefix, "helpbutton", suffix), friendSuffix)
                        AppendActionDescriptorWrites(world.writes, prefix, friendSuffix, friend)
                    end
                    if enemy then
                        local enemySuffix = "enemy" .. suffix
                        AddCompiledWrite(world.writes, AttributeName(prefix, "harmbutton", suffix), enemySuffix)
                        AppendActionDescriptorWrites(world.writes, prefix, enemySuffix, enemy)
                    end

                    if noneItem then
                        local noneSuffix = "none" .. suffix
                        entry.noneSuffix = noneSuffix
                        AddCompiledWrite(world.writes, AttributeName(prefix, "unit", noneSuffix), "player")
                        AppendActionDescriptorWrites(world.writes, prefix, noneSuffix, noneItem)
                        WorldPlanAddStateKey(world.states.NONE, key, noneSuffix)
                        world.noMouseoverItemKeyCount = world.noMouseoverItemKeyCount + 1
                    elseif noneMacro then


                        entry.noneSuffix = suffix
                        WorldPlanAddStateKey(world.states.NONE, key, suffix)
                        world.noMouseoverMacroKeyCount = world.noMouseoverMacroKeyCount + 1
                    end

                    if helpActive then WorldPlanAddStateKey(world.states.HELP, key, suffix) end
                    if harmActive then WorldPlanAddStateKey(world.states.HARM, key, suffix) end
                    if otherActive then WorldPlanAddStateKey(world.states.OTHER, key, suffix) end

                    CountWorldDescriptor(any)
                    CountWorldDescriptor(friend)
                    CountWorldDescriptor(enemy)
                end
            end
        end
    end

    return world
end

local function BuildWorldBindingLines(entries)
    local lines = {}
    for i = 1, #entries do
        local entry = entries[i]


        lines[#lines + 1] = format("self:SetBindingClick(false, %q, self, %q)", entry.key, entry.suffix)
    end
    return table.concat(lines, "\n")
end

function CC:BuildWorldStateSnippet(world)
    local clear, seen = {}, {}
    for _, state in ipairs({"HELP", "HARM", "OTHER", "NONE"}) do
        for i = 1, #(world.states[state] or {}) do
            local key = world.states[state][i].key
            if not seen[key] then
                seen[key] = true
                clear[#clear + 1] = format("self:ClearBinding(%q)", key)
            end
        end
    end

    local help = BuildWorldBindingLines(world.states.HELP or {})
    local harm = BuildWorldBindingLines(world.states.HARM or {})
    local other = BuildWorldBindingLines(world.states.OTHER or {})
    local none = BuildWorldBindingLines(world.states.NONE or {})


    return table.concat(clear, "\n")
        .. "\nlocal ccHeader = self:GetFrameRef('cc_header')"
        .. "\nif ccHeader then"
        .. "\n    local ccProbe = (ccHeader:GetAttribute('cc_world_probe') or 0) + 1"
        .. "\n    ccHeader:SetAttribute('cc_world_probe', ccProbe)"
        .. "\n    ccHeader:SetAttribute('cc_world_last_state', newstate)"
        .. "\nend"
        .. "\nif newstate == \"HELP_COMBAT\" or newstate == \"HELP_OOC\" then\n" .. help
        .. "\nelseif newstate == \"HARM_COMBAT\" or newstate == \"HARM_OOC\" then\n" .. harm
        .. "\nelseif newstate == \"OTHER_COMBAT\" or newstate == \"OTHER_OOC\" then\n" .. other
        .. "\nelseif newstate == \"NONE_COMBAT\" or newstate == \"NONE_OOC\" then\n" .. none
        .. "\nend\n"
end

function CC:ClearWorldButtonAttributes()
    if not self.worldButton or not self.worldOwnedAttrs then return end
    for attr in pairs(self.worldOwnedAttrs) do
        self.worldButton:SetAttribute(attr, nil)
    end
    self.worldOwnedAttrs = {}
end

function CC:ApplyWorldCasting(compiled)
    if not self.worldButton then return end
    if InCombatLockdown() then self.pendingApply = true return end


    if self.worldButton.Execute then
        self.worldButton:Execute([[self:ClearBindings()]])
    end

    if UnregisterStateDriver then UnregisterStateDriver(self.worldButton, "worldrel") end
    self:ClearWorldButtonAttributes()

    local world = compiled and compiled.world or nil
    local active = self:IsEnabled() and self:IsWorldCastingEnabled()
        and world and world.enabledActionCount > 0

    if active then
        self.worldOwnedAttrs = self.worldOwnedAttrs or {}
        for i = 1, #(world.writes or {}) do
            local write = world.writes[i]
            self.worldButton:SetAttribute(write.attr, write.value)
            self.worldOwnedAttrs[write.attr] = true
        end


        local stateSnippet = self:BuildWorldStateSnippet(world)
        self.worldButton:SetAttribute("_onstate-worldrel", stateSnippet)
        self.worldOwnedAttrs["_onstate-worldrel"] = true
        if RegisterStateDriver then
            RegisterStateDriver(self.worldButton, "worldrel", "[@mouseover,help,exists,combat] HELP_COMBAT;[@mouseover,help,exists] HELP_OOC;[@mouseover,harm,exists,combat] HARM_COMBAT;[@mouseover,harm,exists] HARM_OOC;[@mouseover,exists,combat] OTHER_COMBAT;[@mouseover,exists] OTHER_OOC;[combat] NONE_COMBAT;NONE_OOC")
        end


        if self.worldButton.Execute then
            self.worldButton:Execute("local newstate = self:GetAttribute('state-worldrel') or 'NONE_OOC'\n" .. stateSnippet)
        end
    else


        self.worldButton:SetAttribute("_onstate-worldrel", [[self:ClearBindings()]])
        self.worldOwnedAttrs = self.worldOwnedAttrs or {}
        self.worldOwnedAttrs["_onstate-worldrel"] = true
        if RegisterStateDriver then RegisterStateDriver(self.worldButton, "worldrel", "NONE") end
    end
end

function CC:GetWorldCastingStatsText()
    local world = self.compiled and self.compiled.world or nil
    if not world then return "World plan unavailable." end
    local state = self.worldButton and self.worldButton.GetAttribute and self.worldButton:GetAttribute("state-worldrel") or nil
    local handoffs = self.header and self.header.GetAttribute and (self.header:GetAttribute("cc_world_handoffs") or 0) or 0
    local cancels = self.header and self.header.GetAttribute and (self.header:GetAttribute("cc_world_stale_cancels") or 0) or 0
    local stats = self.compiled and self.compiled.stats or nil
    return format("World Casting: %s; %d world-capable actions (%d Spell / %d Macro / %d native) across %d global keys; no-mouseover owners: %d Any Item / %d opaque Macro; %d plain Left/Right keys forced Frame Only; %d action descriptors policy-locked Frame Only; secure relation/combat state %s; stale-owner handoffs %d / safe cancels %d; no nameplate scan/registration.",
        self:IsWorldCastingEnabled() and "Enabled" or "Disabled",
        world.enabledActionCount or 0,
        world.spellActionCount or 0,
        world.macroActionCount or 0,
        world.nativeActionCount or 0,
        #(world.keys or {}),
        world.noMouseoverItemKeyCount or 0,
        world.noMouseoverMacroKeyCount or 0,
        world.forcedFrameOnlyKeyCount or 0,
        stats and stats.worldPolicyLockedDescriptors or 0,
        tostring(state or "NONE"),
        handoffs,
        cancels)
end


local WORLD_STALE_OWNER_PRECLICK = [[
if self:GetAttribute('cc_world_active') and not self:IsUnderMouse() then
    local ccButton = tostring(button)
    local ccRelay

    if UnitExists('mouseover') then
        if PlayerCanAssist('mouseover') then
            ccRelay = self:GetAttribute('cc_world_help_' .. ccButton)
        elseif PlayerCanAttack('mouseover') then
            ccRelay = self:GetAttribute('cc_world_harm_' .. ccButton)
        else
            ccRelay = self:GetAttribute('cc_world_other_' .. ccButton)
        end
    else
        ccRelay = self:GetAttribute('cc_world_none_' .. ccButton)
    end

    local ccClear = self:GetAttribute('cc_hover_clear')
    if ccClear and control then
        control:RunFor(self, ccClear)
    end

    local ccCount = (owner:GetAttribute('cc_world_handoffs') or 0) + 1
    owner:SetAttribute('cc_world_handoffs', ccCount)

    if ccRelay then
        return ccRelay
    end

    local ccCancel = (owner:GetAttribute('cc_world_stale_cancels') or 0) + 1
    owner:SetAttribute('cc_world_stale_cancels', ccCancel)
    return false
end
]]

function CC:InstallWorldClickWrapper(frame)
    if not self.header or not frame then return end
    self.worldClickWrappedFrames = self.worldClickWrappedFrames or {}
    if self.worldClickWrappedFrames[frame] then return end


    self.header:WrapScript(frame, "OnClick", WORLD_STALE_OWNER_PRECLICK)
    self.worldClickWrappedFrames[frame] = true
end

function CC:ApplyWorldRelayFrameWrites(frame, compiled)
    local world = compiled and compiled.world or nil
    if not world or not self.worldButton then return end
    if not self:IsWorldCastingEnabled() or world.enabledActionCount <= 0 then return end
    if not world.frameRelays or #world.frameRelays == 0 then return end

    self:OwnAttribute(frame, "cc_world_active", true)

    for i = 1, #world.frameRelays do
        local entry = world.frameRelays[i]
        local frameSuffix = tostring(entry.frameSuffix)
        local worldSuffix = tostring(entry.suffix)


        self:OwnAttribute(frame, AttributeName("", "unit", worldSuffix), "none")
        self:OwnAttribute(frame, AttributeName("", "type", worldSuffix), "click")
        self:OwnAttribute(frame, AttributeName("", "clickbutton", worldSuffix), self.worldButton)

        if entry.helpActive then
            self:OwnAttribute(frame, "cc_world_help_" .. frameSuffix, worldSuffix)
        end
        if entry.harmActive then
            self:OwnAttribute(frame, "cc_world_harm_" .. frameSuffix, worldSuffix)
        end
        if entry.otherActive then
            self:OwnAttribute(frame, "cc_world_other_" .. frameSuffix, worldSuffix)
        end
        if entry.noneActive and entry.noneSuffix then
            local noneSuffix = tostring(entry.noneSuffix)
            self:OwnAttribute(frame, AttributeName("", "unit", noneSuffix), "none")
            self:OwnAttribute(frame, AttributeName("", "type", noneSuffix), "click")
            self:OwnAttribute(frame, AttributeName("", "clickbutton", noneSuffix), self.worldButton)
            self:OwnAttribute(frame, "cc_world_none_" .. frameSuffix, noneSuffix)
        end
    end

    self:InstallWorldClickWrapper(frame)
end


function CC:ApplyCompiledFrameWrites(frame, compiled)
    local writes = compiled and compiled.frameWrites or nil
    if not writes then return end

    local stats = compiled.stats
    if stats then
        stats.frameApplications = stats.frameApplications + 1
        stats.attributeWritesApplied = stats.attributeWritesApplied + #writes
    end

    for i = 1, #writes do
        local write = writes[i]
        self:OwnAttribute(frame, write.attr, write.value)
    end
end

function CC:GetCompiledPlanStats()
    return self.compiled and self.compiled.stats or nil
end

function CC:GetCompiledPlanStatsText()
    local stats = self:GetCompiledPlanStats()
    if not stats then return "No compiled plan yet." end

    local frames = stats.frameApplications or 0
    local actions = stats.actionDescriptorAttempts or 0
    local attrs = stats.attributeDescriptors or 0
    local repeatFrames = frames > 1 and (frames - 1) or 0
    local avoidedPayloadBuilds = actions * repeatFrames
    local avoidedAttributeBuilds = attrs * repeatFrames

    return format(
        "plan r%d: %d keys, %d/%d actions resolved, %d attribute descriptors; World policy locked %d descriptors, explicit Frame Only %d; frame applications %d, writes %d; per-frame payload/descriptor builds %d; legacy-equivalent rebuilds avoided: %d payload / %d attribute descriptors",
        stats.revision or 0,
        stats.keyPlans or 0,
        stats.actionDescriptors or 0,
        actions,
        attrs,
        stats.worldPolicyLockedDescriptors or 0,
        stats.explicitFrameOnlyDescriptors or 0,
        frames,
        stats.attributeWritesApplied or 0,
        stats.perFramePayloadBuilds or 0,
        avoidedPayloadBuilds,
        avoidedAttributeBuilds
    )
end


function CC:BuildHoverSnippets(compiled)
    local hasHover = compiled.hoverKeys and #compiled.hoverKeys > 0
    if not hasHover then return nil, nil, nil, nil end

    local enter, forceClear = {}, {}

    if hasHover then
        for _, entry in ipairs(compiled.hoverKeys) do
            local escapedKey = format("%q", entry.key)
            forceClear[#forceClear + 1] = "self:ClearBinding(" .. escapedKey .. ")"
        end
        forceClear[#forceClear + 1] = "if danglingButton == self then danglingButton = nil end"


        enter[#enter + 1] = "local ccSelfClear = self:GetAttribute('cc_hover_clear')"
        enter[#enter + 1] = "if ccSelfClear and control then control:RunFor(self, ccSelfClear) end"
        enter[#enter + 1] = "if danglingButton and danglingButton ~= self and control then"
        enter[#enter + 1] = "    local ccOldClear = danglingButton:GetAttribute('cc_hover_clear')"
        enter[#enter + 1] = "    if ccOldClear then control:RunFor(danglingButton, ccOldClear) end"
        enter[#enter + 1] = "end"
        enter[#enter + 1] = "danglingButton = self"
    end

    if hasHover then
        for _, entry in ipairs(compiled.hoverKeys) do
            local escapedKey, escapedSuffix = format("%q", entry.key), format("%q", entry.suffix)
            enter[#enter + 1] = "self:SetBindingClick(true, " .. escapedKey .. ", self, " .. escapedSuffix .. ")"
        end
    end

    local forceClearSnippet = hasHover and table.concat(forceClear, "\n") or ""
    local leaveSnippet = ""
    local hideSnippet = ""
    if hasHover then
        leaveSnippet = table.concat({
            "if not self:IsUnderMouse() then",
            "    local ccClear = self:GetAttribute('cc_hover_clear')",
            "    if ccClear and control then control:RunFor(self, ccClear) end",
            "end",
        }, "\n")
        hideSnippet = table.concat({
            "local ccClear = self:GetAttribute('cc_hover_clear')",
            "if ccClear and control then control:RunFor(self, ccClear) end",
        }, "\n")
    end

    return table.concat(enter, "\n"), leaveSnippet, hideSnippet, forceClearSnippet
end

function CC:OwnMouseWheel(frame, enabled)
    if not frame or type(frame.EnableMouseWheel) ~= "function" then return end
    self.nativeMouseWheel = self.nativeMouseWheel or {}
    self.ownedMouseWheel = self.ownedMouseWheel or {}

    if not self.nativeMouseWheel[frame] then
        local value = false
        if type(frame.IsMouseWheelEnabled) == "function" then value = frame:IsMouseWheelEnabled() and true or false end
        self.nativeMouseWheel[frame] = { value = value }
    end

    frame:EnableMouseWheel(enabled and true or false)
    self.ownedMouseWheel[frame] = enabled and true or false
end

function CC:RestoreMouseWheel(frame)
    if not frame or not self.ownedMouseWheel or self.ownedMouseWheel[frame] == nil then return end
    local owned = self.ownedMouseWheel[frame]
    local native = self.nativeMouseWheel and self.nativeMouseWheel[frame]

    if type(frame.IsMouseWheelEnabled) == "function" then
        local current = frame:IsMouseWheelEnabled() and true or false
        if native and current ~= owned then native.value = current end
    end

    if type(frame.EnableMouseWheel) == "function" and native then
        frame:EnableMouseWheel(native.value and true or false)
    end
    self.ownedMouseWheel[frame] = nil
    if self.nativeMouseWheel then self.nativeMouseWheel[frame] = nil end
end

function CC:InstallHoverWrapper(frame, enterSnippet, leaveSnippet, hideSnippet, forceClearSnippet, needsMouseWheel)
    if not self.header then return end
    self.header:UnwrapScript(frame, "OnEnter")
    self.header:UnwrapScript(frame, "OnLeave")
    self.header:UnwrapScript(frame, "OnHide")
    self.header:UnwrapScript(frame, "OnShow")

    if enterSnippet and enterSnippet ~= "" then
        if forceClearSnippet and forceClearSnippet ~= "" then self:OwnAttribute(frame, "cc_hover_clear", forceClearSnippet) end
        self.header:WrapScript(frame, "OnEnter", enterSnippet)
        if leaveSnippet and leaveSnippet ~= "" then self.header:WrapScript(frame, "OnLeave", leaveSnippet) end
        if hideSnippet and hideSnippet ~= "" then self.header:WrapScript(frame, "OnHide", hideSnippet) end
        self.header:WrapScript(frame, "OnShow", "if self:IsUnderMouse() then\n" .. enterSnippet .. "\nend")
    end

    if needsMouseWheel then self:OwnMouseWheel(frame, true) end
end

function CC:ForceClearActiveHover()
    if not self.header or InCombatLockdown() then return false end
    self.hoverClearSerial = (self.hoverClearSerial or 0) + 1
    self.header:SetAttribute("cc_forceclear", self.hoverClearSerial)
    return true
end


function CC:SuppressNativeMouseActions(frame)
    if not frame or not frame.GetAttribute then return end
    for button = 1, 2 do
        local exact = "type" .. button
        local wildcard = "*type" .. button
        if frame:GetAttribute(exact) ~= nil then
            self:OwnAttribute(frame, exact, "")
        end
        if frame:GetAttribute(wildcard) ~= nil then
            self:OwnAttribute(frame, wildcard, "")
        end
    end
end

function CC:ApplyFrameBindings(frame, compiled, enterSnippet, leaveSnippet, hideSnippet, forceClearSnippet)
    if InCombatLockdown() then self.pendingApply = true return end
    self:RestoreOwnedAttributes(frame)
    self:RestoreMouseWheel(frame)
    if self:IsEnabled() then
        self._applyingFrameBindings = true
        self:SuppressNativeMouseActions(frame)
        self:ApplyCompiledFrameWrites(frame, compiled)
        self:ApplyWorldRelayFrameWrites(frame, compiled)
        self:InstallHoverWrapper(frame, enterSnippet, leaveSnippet, hideSnippet, forceClearSnippet, compiled.needsMouseWheel)
        self._applyingFrameBindings = nil
    else
        self:InstallHoverWrapper(frame, nil, nil, nil, nil, false)
    end
end

function CC:RegisterFrame(frame)
    if not self:IsEligibleFrame(frame) then return false end
    if InCombatLockdown() then self.pendingScan = true return false end
    if not self.registeredFrames[frame] then
        self.registeredFrames[frame] = true
        if self.compiled then
            self:ApplyFrameBindings(frame, self.compiled, self.hoverEnterSnippet, self.hoverLeaveSnippet, self.hoverHideSnippet, self.hoverForceClearSnippet)
        end
    end
    return true
end

function CC:ScanClickCastFrames()
    if InCombatLockdown() then self.pendingScan = true return end
    local frames = _G.ClickCastFrames
    if type(frames) ~= "table" then return end
    for frame, enabled in pairs(frames) do if enabled then self:RegisterFrame(frame) end end
end

function CC:ApplyBindings()
    if InCombatLockdown() then self.pendingApply = true return end


    self:ForceClearActiveHover()

    self.compiled = self:BuildCompiledBindings()
    self.hoverEnterSnippet, self.hoverLeaveSnippet, self.hoverHideSnippet, self.hoverForceClearSnippet = self:BuildHoverSnippets(self.compiled)
    for frame in pairs(self.registeredFrames) do
        if self:IsEligibleFrame(frame) then
            self:ApplyFrameBindings(frame, self.compiled, self.hoverEnterSnippet, self.hoverLeaveSnippet, self.hoverHideSnippet, self.hoverForceClearSnippet)
        end
    end
    self:ApplyWorldCasting(self.compiled)
end

function CC:GetRegisteredFrameCount()
    local count = 0
    for _ in pairs(self.registeredFrames) do count = count + 1 end
    return count
end

function CC:InitializeSecureEngine()
    if self.header then return end
    self.header = CreateFrame("Frame", "ElvUIClickCastSecureHeader", UIParent, "SecureHandlerBaseTemplate,SecureHandlerAttributeTemplate")


    self.worldButton = CreateFrame("Button", "ElvUIClickCastWorldButton", UIParent, "SecureActionButtonTemplate,SecureHandlerStateTemplate")
    self.worldButton:RegisterForClicks("AnyUp")
    self.worldButton:SetWidth(1)
    self.worldButton:SetHeight(1)
    self.worldButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -8, -8)
    self.worldOwnedAttrs = {}
    if self.worldButton.SetFrameRef then
        self.worldButton:SetFrameRef("cc_header", self.header)
    end
    self.header:SetAttribute("_onattributechanged", [[
        if name == "state-hasunit" and value == "false" and danglingButton then
            if not danglingButton:IsUnderMouse() and control then
                local ccClear = danglingButton:GetAttribute("cc_hover_clear")
                if ccClear then control:RunFor(danglingButton, ccClear) end
            end
        elseif name == "cc_world_probe" and danglingButton then
            if not danglingButton:IsUnderMouse() and control then
                local ccClear = danglingButton:GetAttribute("cc_hover_clear")
                if ccClear then control:RunFor(danglingButton, ccClear) end
            end
        elseif name == "cc_forceclear" and danglingButton and control then
            if not danglingButton:IsUnderMouse() then
                local ccClear = danglingButton:GetAttribute("cc_hover_clear")
                if ccClear then control:RunFor(danglingButton, ccClear) end
            end
            danglingButton = nil
        end
    ]])
    if RegisterStateDriver then RegisterStateDriver(self.header, "hasunit", "[@mouseover, exists] true; false") end
end
