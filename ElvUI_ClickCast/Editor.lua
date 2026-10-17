local E, L, V, P, G = unpack(ElvUI)
local CC = E:GetModule("ElvUIClickCast")

local _G = _G
local ipairs, pairs, tonumber, tostring, type = ipairs, pairs, tonumber, tostring, type
local max, min = math.max, math.min
local strlower, strfind, strmatch = string.lower, string.find, string.match
local format = string.format
local tinsert = table.insert

local Skins = E:GetModule("Skins", true)

local function GetAceGUI()
    local ace = E.Libs and E.Libs.AceGUI or LibStub("AceGUI-3.0", true)
    assert(ace, "ElvUI_ClickCast editor requires ElvUI OptionsUI/AceGUI")
    return ace
end


local EDITOR_FONT_SIZE = 16
local ROW_HEIGHT = 30
local ROW_GAP = 2
local VISIBLE_ROWS = 12

local RELATIONS_ALL = {
    { value = "ANY", text = "Any" },
    { value = "FRIEND", text = "Help" },
    { value = "ENEMY", text = "Harm" },
}

local ACTION_TYPES = {
    { value = "SPELL", text = "Spell" },
    { value = "MACRO", text = "Macro" },
    { value = "CUSTOM", text = "Custom Macro" },
    { value = "ITEM", text = "Item / Slot" },
    { value = "TARGET", text = "Target" },
    { value = "FOCUS", text = "Focus" },
    { value = "ASSIST", text = "Assist" },
    { value = "MENU", text = "Unit Menu" },
}

local ALWAYS_TARGETING = {
    { value = "disabled", text = "Disabled" },
    { value = "left", text = "Left Spell" },
    { value = "any", text = "Any Spells" },
}

local C = {
    bg = {0.055, 0.055, 0.055, 0.98},
    panel = {0.085, 0.085, 0.085, 0.98},
    row = {0.115, 0.115, 0.115, 1},
    hover = {0.16, 0.16, 0.16, 1},
    border = {0, 0, 0, 1},
    text = {0.94, 0.94, 0.94, 1},
    muted = {0.62, 0.62, 0.62, 1},
    danger = {0.90, 0.30, 0.30, 1},
    success = {0.34, 0.80, 0.46, 1},
    warning = {0.95, 0.72, 0.25, 1},
}


local ELV_STATE_GREEN = {0.20, 1.00, 0.20, 1}
local ELV_STATE_RED = {1.00, 0.20, 0.20, 1}

local function GetElvUIEnabledColor()
    return unpack(ELV_STATE_GREEN)
end

local function ApplyStateLabelColor(fontString, enabled)
    if not fontString then return end
    if enabled then
        fontString:SetTextColor(unpack(ELV_STATE_GREEN))
    else
        fontString:SetTextColor(unpack(C.muted))
    end
end

local BACKDROP = {
    bgFile = (E.media and E.media.blankTex) or "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = (E.media and E.media.blankTex) or "Interface\\Buttons\\WHITE8X8",
    tile = true,
    tileSize = 16,
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

local function SetBox(frame, color, border)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop(BACKDROP)
    color = color or C.panel
    border = border or C.border
    frame:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function SetBoxColor(frame, color)
    if frame and frame.SetBackdropColor then
        frame:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
    end
end

local function GetFontFaceAndFlags(object)
    local oldFont, _, oldFlags = object:GetFont()
    local font = (E.media and E.media.normFont) or oldFont
    local flags = oldFlags or ""
    local configured = E.db and E.db.general and E.db.general.fontStyle
    if type(configured) == "string" then
        if configured == "NONE" then
            flags = ""
        elseif configured == "OUTLINE" or configured == "THICKOUTLINE" or configured == "MONOCHROME" or configured == "MONOCHROMEOUTLINE" then
            flags = configured
        end
    end
    return font, flags
end

local function RegisterFontObject(parentFrame, object, size)
    if not parentFrame then return end
    parentFrame.fontObjects = parentFrame.fontObjects or {}
    parentFrame.fontObjects[#parentFrame.fontObjects + 1] = { object = object, size = max(size or EDITOR_FONT_SIZE, EDITOR_FONT_SIZE) }
end

local function ApplyFont(object, size)
    local font, flags = GetFontFaceAndFlags(object)
    if font then object:SetFont(font, max(size or EDITOR_FONT_SIZE, EDITOR_FONT_SIZE), flags or "") end
end

local function NewText(parent, text, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(GameFontNormal)
    ApplyFont(fs, size)
    fs:SetText(text or "")
    color = color or C.text
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    fs:SetJustifyH(justify or "LEFT")
    RegisterFontObject(CC.editorFrame, fs, size)
    return fs
end

local editorButtonSerial = 0

local function NextEditorButtonName()
    local name
    repeat
        editorButtonSerial = editorButtonSerial + 1
        name = "ElvUIClickCastEditorButton" .. tostring(editorButtonSerial)
    until not _G[name]
    return name
end

local function NewButton(parent, text, width, height, accent)


    local b = CreateFrame("Button", NextEditorButtonName(), parent, "UIPanelButtonTemplate2")
    b:SetWidth(width or 100)
    b:SetHeight(height or 25)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    if Skins and Skins.HandleButton then
        Skins:HandleButton(b, true)
    elseif b.SetTemplate then
        b:SetTemplate("Default")
        if b.StyleButton then b:StyleButton() end
    end

    b.label = b:GetFontString()
    if not b.label then
        b.label = NewText(b, "", EDITOR_FONT_SIZE, C.text, "CENTER")
    end
    b.label:ClearAllPoints()
    b.label:SetAllPoints(b)
    b.label:SetJustifyH("CENTER")
    b.label:SetJustifyV("MIDDLE")
    ApplyFont(b.label, EDITOR_FONT_SIZE)
    RegisterFontObject(CC.editorFrame, b.label, EDITOR_FONT_SIZE)
    b:SetText(text or "")

    function b:SetEnabledState(enabled)
        self.disabled = not enabled
        if enabled then self:Enable() else self:Disable() end
        self:SetAlpha(enabled and 1 or 0.55)
    end

    return b
end

local function NewEditBox(parent, width, height, multiline)
    local shell = CreateFrame("Frame", nil, parent)
    shell:SetWidth(width)
    shell:SetHeight(height)
    if shell.SetTemplate then
        shell:SetTemplate("Default")
    else
        SetBox(shell, C.bg, C.border)
    end

    local e = CreateFrame("EditBox", nil, shell)
    e:SetPoint("TOPLEFT", shell, "TOPLEFT", 6, -4)
    e:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -6, 4)
    e:SetFontObject(ChatFontNormal)
    ApplyFont(e, EDITOR_FONT_SIZE)
    RegisterFontObject(CC.editorFrame, e, EDITOR_FONT_SIZE)
    e:SetAutoFocus(false)
    e:SetMultiLine(multiline and true or false)
    e:SetMaxLetters(multiline and 4000 or 220)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    shell.edit = e
    return shell, e
end

function CC:ApplyEditorMedia()
    local f = self.editorFrame
    if not f then return end
    for _, entry in ipairs(f.fontObjects or {}) do
        if entry.object and entry.object.GetFont and entry.object.SetFont then
            ApplyFont(entry.object, entry.size)
        end
    end


    for _, selectControl in ipairs(f.nativeSelects or {}) do
        local widget = selectControl.widget
        if widget then
            if widget.text then ApplyFont(widget.text, EDITOR_FONT_SIZE) end
            if widget.pullout and widget.pullout.IterateItems then
                for _, item in widget.pullout:IterateItems() do
                    if item and item.text and item.text.SetFont then
                        ApplyFont(item.text, EDITOR_FONT_SIZE)
                    end
                end
            end
        end
    end

    for _, checkControl in ipairs(f.nativeChecks or {}) do
        local widget = checkControl.widget
        if widget and widget.text and widget.text.SetFont then
            ApplyFont(widget.text, EDITOR_FONT_SIZE)
        end
    end
end

function CC:CloseSelectMenu()
    local ace = E.Libs and E.Libs.AceGUI or LibStub("AceGUI-3.0", true)
    if ace and ace.ClearFocus then ace:ClearFocus() end
end

local function BuildNativeSelectList(options)
    local list, order = {}, {}
    for _, entry in ipairs(options or {}) do
        list[entry.value] = entry.text
        order[#order + 1] = entry.value
    end
    return list, order
end

local function SameSelectOptions(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
    for i = 1, #a do
        local av, bv = a[i], b[i]
        if not av or not bv or av.value ~= bv.value or av.text ~= bv.text then
            return false
        end
    end
    return true
end

local function CopySelectOptions(options)
    local copy = {}
    for i, entry in ipairs(options or {}) do
        copy[i] = { value = entry.value, text = entry.text }
    end
    return copy
end

local function NewSelect(parent, width, options, initial, onChoose)

    local ace = GetAceGUI()
    local widget = ace:Create("Dropdown")
    widget:SetLabel("")
    widget:SetHeight(26)
    widget:SetWidth(width)

    local shell = CreateFrame("Frame", nil, parent)
    shell:SetWidth(width)
    shell:SetHeight(26)
    shell.widget = widget
    shell.options = options or {}
    shell.value = initial
    shell.placeholder = "Choose"
    shell:EnableMouse(true)
    shell:SetScript("OnMouseDown", function(_, mouseButton)


        if mouseButton == "RightButton" and shell.onRightClick then
            shell.onRightClick()
        end
    end)

    widget.frame:SetParent(shell)
    widget.frame:ClearAllPoints()
    widget.frame:SetAllPoints(shell)
    widget.frame:Show()

    if widget.text then
        ApplyFont(widget.text, EDITOR_FONT_SIZE)
    end

    local function ApplyOptions()
        local optionsChanged = not SameSelectOptions(shell.appliedOptions, shell.options)
        if optionsChanged then
            local list, order = BuildNativeSelectList(shell.options)
            shell.nativeList = list
            widget:SetList(list, order)
            shell.appliedOptions = CopySelectOptions(shell.options)

            if widget.pullout and widget.pullout.IterateItems then
                for _, item in widget.pullout:IterateItems() do
                    if item and item.text and item.text.SetFont then
                        ApplyFont(item.text, EDITOR_FONT_SIZE)
                    end
                end
            end
        end

        local list = shell.nativeList or {}
        widget:SetPulloutWidth(shell:GetWidth())
        if shell.value ~= nil and list[shell.value] ~= nil then
            widget:SetValue(shell.value)
        else
            widget:SetText(shell.placeholder or "Choose")
        end
        if shell.displayTextOverride then
            widget:SetText(shell.displayTextOverride)
        end
    end

    widget:SetCallback("OnValueChanged", function(_, _, value)
        shell.value = value
        shell.displayTextOverride = nil
        if onChoose then onChoose(value) end
    end)


    local function EnableRightDelete(button)
        if not button or not button.GetScript then return end
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local nativeClick = button:GetScript("OnClick")
        button:SetScript("OnClick", function(btn, mouseButton, ...)
            if mouseButton == "RightButton" and shell.onRightClick then
                shell.onRightClick()
                return
            end
            if nativeClick then
                return nativeClick(btn, mouseButton, ...)
            end
        end)
    end
    EnableRightDelete(widget.button_cover)
    EnableRightDelete(widget.button)

    function shell:SetValue(value)
        self.value = value
        self.displayTextOverride = nil
        ApplyOptions()
    end
    function shell:SetOptions(newOptions, value, placeholder)
        self.options = newOptions or self.options
        self.value = value
        self.displayTextOverride = nil
        self.placeholder = placeholder or self.placeholder
        ApplyOptions()
    end
    function shell:SetDisplayText(displayText)
        self.displayTextOverride = displayText
        if displayText then
            widget:SetText(displayText)
        else
            ApplyOptions()
        end
    end
    function shell:GetValue()
        return self.value
    end
    function shell:SetEnabledState(enabled)
        self.disabled = not enabled
        widget:SetDisabled(not enabled)
        self:SetAlpha(enabled and 1 or 0.55)
    end

    shell:SetScript("OnSizeChanged", function(self)
        if widget.SetWidth then widget:SetWidth(self:GetWidth()) end
        if widget.SetPulloutWidth then widget:SetPulloutWidth(self:GetWidth()) end
    end)

    if CC.editorFrame then
        CC.editorFrame.nativeSelects = CC.editorFrame.nativeSelects or {}
        tinsert(CC.editorFrame.nativeSelects, shell)
    end

    ApplyOptions()
    return shell
end


local function NewCheckBox(parent, labelText, width, initial, onChanged)
    local ace = GetAceGUI()
    local widget = ace:Create("CheckBox")
    widget:SetType("checkbox")

    local shell = CreateFrame("Frame", nil, parent)
    shell:SetWidth(width or 110)
    shell:SetHeight(24)
    shell.widget = widget
    shell.labelText = labelText or ""

    widget.frame:SetParent(shell)
    widget.frame:ClearAllPoints()
    widget.frame:SetAllPoints(shell)
    widget.frame:Show()

    local function ApplyCheckColor(enabled)
        if widget.text and widget.text.SetJustifyH then
            widget.text:SetJustifyH("LEFT")
            ApplyFont(widget.text, EDITOR_FONT_SIZE)
        end
        local label = shell.labelText
        if enabled then
            label = label ~= "" and label or "Enabled"
            local r, g, b, a = GetElvUIEnabledColor()
            if widget.check and widget.check.SetVertexColor then widget.check:SetVertexColor(r, g, b, a) end
            if widget.text then widget.text:SetTextColor(r, g, b, a) end
        else
            label = label ~= "" and label or "Disabled"
            if widget.check and widget.check.SetVertexColor then widget.check:SetVertexColor(unpack(ELV_STATE_RED)) end
            if widget.text then widget.text:SetTextColor(unpack(ELV_STATE_RED)) end
        end
        if widget.SetLabel then widget:SetLabel(label) end
    end

    widget:SetValue(initial and true or false)
    ApplyCheckColor(initial and true or false)

    widget:SetCallback("OnValueChanged", function(_, _, value)
        if shell.suppressCallback then return end
        value = value and true or false
        ApplyCheckColor(value)
        if onChanged then onChanged(value) end
    end)

    function shell:SetValue(value)
        value = value and true or false
        self.suppressCallback = true
        widget:SetValue(value)
        self.suppressCallback = nil
        ApplyCheckColor(value)
    end

    function shell:SetEnabledState(enabled)
        self.disabled = not enabled
        if widget.SetDisabled then
            widget:SetDisabled(not enabled)
        end
        self:SetAlpha(enabled and 1 or 0.55)
    end

    if CC.editorFrame then
        CC.editorFrame.nativeChecks = CC.editorFrame.nativeChecks or {}
        tinsert(CC.editorFrame.nativeChecks, shell)
    end

    return shell
end


function CC:CreateNativeEditorColorPicker(parent, width, r, g, b, a, onChanged, onConfirmed)
    local ace = GetAceGUI()
    local widget = ace:Create("ColorPicker-ElvUI")
    widget.frame:SetParent(parent)
    widget.frame:ClearAllPoints()
    widget.frame:SetWidth(width or 120)
    widget.frame:SetHeight(24)
    widget.frame:Show()
    widget:SetLabel("")
    widget:SetHasAlpha(a ~= nil)
    widget:SetColor(r or 1, g or 1, b or 1, a or 1)
    if widget.text then
        ApplyFont(widget.text, EDITOR_FONT_SIZE)
    end
    if onChanged then
        widget:SetCallback("OnValueChanged", function(_, _, nr, ng, nb, na)
            onChanged(nr, ng, nb, na)
        end)
    end
    if onConfirmed then
        widget:SetCallback("OnValueConfirmed", function(_, _, nr, ng, nb, na)
            onConfirmed(nr, ng, nb, na)
        end)
    end
    return widget
end

local function GetEditorSpellRelations(CCObject, frame, key, editIndex)
    local options = {"ANY", "FRIEND", "ENEMY"}
    key = CCObject:NormalizePhysicalKey(key)
    if not key then return options end
    local occupied
    for index, other in ipairs(frame.draftBindings or {}) do
        if index ~= editIndex
            and not frame.deleted[index]
            and CCObject:NormalizePhysicalKey(other.key) == key
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
local function BuildRelationOptions(values)
    local out = {}
    for _, value in ipairs(values or {}) do
        if value == "ANY" then out[#out + 1] = { value = "ANY", text = "Any" }
        elseif value == "FRIEND" then out[#out + 1] = { value = "FRIEND", text = "Help" }
        elseif value == "ENEMY" then out[#out + 1] = { value = "ENEMY", text = "Harm" }
        end
    end
    return out
end

local function EffectiveRelationDisplay(CCObject, frame, binding, editIndex)
    local relation = binding and (binding.relation or "ANY") or "ANY"
    if relation ~= "ANY" or not binding or (binding.actionType or "SPELL") ~= "SPELL" then
        return relation == "FRIEND" and "Help" or relation == "ENEMY" and "Harm" or "Any"
    end

    local key = CCObject:NormalizePhysicalKey(binding.key)
    if not key then return "Any" end

    local paired
    for index, other in ipairs(frame.draftBindings or {}) do
        if index ~= editIndex
            and not frame.deleted[index]
            and CCObject:NormalizePhysicalKey(other.key) == key
            and (other.actionType or "SPELL") == "SPELL" then
            local otherRelation = other.relation or "ANY"
            if otherRelation == "FRIEND" then
                paired = "Any > Harm"
                break
            elseif otherRelation == "ENEMY" then
                paired = "Any > Help"
                break
            end
        end
    end

    return paired or "Any"
end

local function ClearTable(t)
    if not t then return end
    for k in pairs(t) do t[k] = nil end
end

function CC:EditorMessage(text, kind)
    local f = self.editorFrame
    if not f or not f.message then return end
    f.message:SetText(text or "")
    local color = kind == "error" and C.danger or kind == "warn" and C.warning or kind == "success" and C.success or C.muted
    f.message:SetTextColor(unpack(color))
end

function CC:BeginEditorSession(force)
    local f = self.editorFrame
    if not f then return end
    if f.sessionActive and not force then return end
    local db = self:EnsureDB()
    f.draftBindings = self.CopyTable(self:GetBindings())
    f.draftAlwaysTargeting = db.alwaysTargeting or "disabled"
    f.draftWorldCastingEnabled = db.worldCastingEnabled == true and self:IsWorldCastingAuthorized()
    f.draftEnabled = db.enabled ~= false
    f.listOffset = 0
    f.sessionActive = true
    f.dirty = false
    f.invalidIndex = nil
    f.captureIndex = nil
    ClearTable(f.deleted)
end

function CC:MarkEditorDirty()
    local f = self.editorFrame
    if not f then return end
    f.dirty = true
    f.invalidIndex = nil
end

function CC:RefreshEnableButton()
    local f = self.editorFrame
    if not f or not f.enableToggle then return end
    f.enableToggle:SetValue(f.draftEnabled and true or false)
end

function CC:RefreshWorldCastingButton()
    local f = self.editorFrame
    if not f or not f.worldCastingButton then return end
    f.worldCastingButton:SetText(f.draftWorldCastingEnabled and "ON" or "OFF")
    ApplyStateLabelColor(f.worldCastingButton.label, f.draftWorldCastingEnabled)
end

function CC:RequestWorldCastingForEditor()
    local f = self.editorFrame
    if not f then return end
    if f.draftWorldCastingEnabled then
        f.draftWorldCastingEnabled = false
        self:MarkEditorDirty()
        self:RefreshEditor()
        return
    end
    if self:IsWorldCastingAuthorized() then
        f.draftWorldCastingEnabled = true
        self:MarkEditorDirty()
        self:RefreshEditor()
        return
    end
    self:ShowWorldCastingConfirmation(true)
end

function CC:CancelEditorChanges()
    self:CloseSelectMenu()
    self:CloseSpellPicker()
    self:CloseMacroPicker()
    self:CloseCustomMacroWriter()
    self:StopInlineBindingCapture(true)
    self:BeginEditorSession(true)
    self:RefreshEditor()
    self:EditorMessage("Draft changes discarded.", "normal")
end

local function BuildProfileOptions()
    local out = {}
    for _, name in ipairs(CC:GetProfiles()) do
        out[#out + 1] = { value = name, text = name }
    end
    return out
end

local function EnsureProfileNameDialog()
    if _G.StaticPopupDialogs and _G.StaticPopupDialogs["ELVUICLICKCAST_PROFILE_NAME"] then return end
    _G.StaticPopupDialogs["ELVUICLICKCAST_PROFILE_NAME"] = {
        text = "Enter a profile name.",
        button1 = "Accept",
        button2 = "Cancel",
        hasEditBox = 1,
        maxLetters = 24,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
        OnShow = function(self)
            if self.editBox then
                self.editBox:SetText(CC.profileDialogPrefill or "")
                self.editBox:HighlightText()
                self.editBox:SetFocus()
            end
        end,
        EditBoxOnEnterPressed = function(self)
            local dialog = self.button1 and self or (self.GetParent and self:GetParent())
            if dialog and dialog.button1 and dialog.button1.Click then
                dialog.button1:Click()
            end
        end,
        OnAccept = function(self)
            local callback = CC.profileDialogCallback
            if callback then
                callback(self.editBox and self.editBox:GetText() or "")
            end
        end,
        OnCancel = function()
            CC.profileDialogCallback = nil
            CC.profileDialogPrefill = nil
        end,
    }
end

function CC:RefreshProfileToolbar()
    local f = self.editorFrame
    if not f or not f.profileSelect then return end
    local charDB = self:EnsureCharacterDB()
    local tps = charDB.talentProfiles or {}
    local active = self:GetActiveProfile()

    -- Keep the user's last explicit selection (so Delete can target a profile
    -- that stopped being the active one, e.g. after an auto-switch), falling
    -- back to the active profile when the selection no longer exists.
    local options = BuildProfileOptions()
    local current = f.profileSelect:GetValue()
    local keepCurrent = current and charDB.profiles and charDB.profiles[current]
    f.profileSelect:SetOptions(options, keepCurrent and current or active)

    f.autoSwitchCheck:SetValue(charDB.autoSwitch == true)

    local count = 0
    for _ in pairs(charDB.profiles or {}) do count = count + 1 end
    local selected = f.profileSelect:GetValue()
    local canDelete = count > 1 and selected and selected ~= active and charDB.profiles and charDB.profiles[selected]
    f.deleteProfileButton:SetEnabledState(canDelete and true or false)

    local hasTwoGroups = (GetNumTalentGroups and GetNumTalentGroups() or 1) > 1
    f.tg1Select:SetOptions(options, tps[1] or "Default")
    if f.tg2Select then
        f.tg2Select:SetOptions(options, tps[2] or "Default")
        if hasTwoGroups then f.tg2Select:Show() else f.tg2Select:Hide() end
    end
    if f.tg2Label then
        if hasTwoGroups then f.tg2Label:Show() else f.tg2Label:Hide() end
    end
end

function CC:SwitchEditorProfile(name)
    local f = self.editorFrame
    if not f then return end
    local charDB = self:EnsureCharacterDB()
    if type(name) ~= "string" or not charDB.profiles or not charDB.profiles[name] then
        self:RefreshProfileToolbar()
        if name ~= nil then
            self:EditorMessage("Profile \"" .. tostring(name) .. "\" was not found.", "error")
        end
        return
    end
    if name == self:GetActiveProfile() then return end

    -- Never commit a dirty draft into the profile we are switching to.
    if f.dirty then
        self:CancelEditorChanges()
    end
    self:SetActiveProfile(name)
    self:BeginEditorSession(true)
    self:RefreshEditor()
    self:EditorMessage("Switched to profile \"" .. tostring(name) .. "\".", "normal")
end

function CC:DeleteSelectedProfile()
    local f = self.editorFrame
    if not f or not f.profileSelect then return end
    local target = f.profileSelect:GetValue()
    if type(target) ~= "string" then return end
    if target == self:GetActiveProfile() then
        self:RefreshProfileToolbar()
        self:EditorMessage("Switch to another profile before deleting \"" .. target .. "\".", "error")
        return
    end
    local ok, err = self:DeleteProfile(target)
    self:RefreshProfileToolbar()
    if ok then
        self:EditorMessage("Profile \"" .. target .. "\" deleted.", "success")
    else
        self:EditorMessage(tostring(err or "Profile deletion failed."), "error")
    end
end

function CC:ShowNewProfileDialog()
    local f = self.editorFrame
    if not f then return end
    EnsureProfileNameDialog()
    CC.profileDialogPrefill = ""
    CC.profileDialogCallback = function(name)
        local clean, err = CC:ValidateProfileName(name)
        if not clean then
            CC:EditorMessage(tostring(err), "error")
            CC.profileDialogPrefill = tostring(name or "")
            StaticPopup_Show("ELVUICLICKCAST_PROFILE_NAME")
            return
        end
        CC.profileDialogCallback = nil
        CC.profileDialogPrefill = nil
        local ok, opErr = CC:AddProfile(clean)
        if ok then
            CC:RefreshProfileToolbar()
            CC:EditorMessage("Profile \"" .. clean .. "\" created. Select it in the dropdown to start editing.", "success")
        else
            CC:EditorMessage(tostring(opErr or "Profile creation failed."), "error")
        end
    end
    StaticPopup_Show("ELVUICLICKCAST_PROFILE_NAME")
end

function CC:ShowRenameProfileDialog()
    local f = self.editorFrame
    if not f then return end
    EnsureProfileNameDialog()
    local active = self:GetActiveProfile()
    CC.profileDialogPrefill = active
    CC.profileDialogCallback = function(name)
        local clean, err = CC:ValidateProfileName(name, active)
        if not clean then
            CC:EditorMessage(tostring(err), "error")
            CC.profileDialogPrefill = tostring(name or "")
            StaticPopup_Show("ELVUICLICKCAST_PROFILE_NAME")
            return
        end
        CC.profileDialogCallback = nil
        CC.profileDialogPrefill = nil
        local ok, opErr = CC:RenameProfile(active, clean)
        if ok then
            CC:RefreshProfileToolbar()
            CC:EditorMessage("Profile renamed to \"" .. clean .. "\".", "success")
        else
            CC:EditorMessage(tostring(opErr or "Profile rename failed."), "error")
        end
    end
    StaticPopup_Show("ELVUICLICKCAST_PROFILE_NAME")
end

function CC:ShowDuplicateProfileDialog()
    local f = self.editorFrame
    if not f then return end
    EnsureProfileNameDialog()
    local active = self:GetActiveProfile()
    local n = #self:GetProfiles() + 1
    local suggested = "Profile " .. tostring(n)
    while not self:ValidateProfileName(suggested) or strlower(suggested) == strlower(active) do
        n = n + 1
        suggested = "Profile " .. tostring(n)
    end
    CC.profileDialogPrefill = suggested
    CC.profileDialogCallback = function(name)
        local clean, err = self:ValidateProfileName(name)
        if not clean then
            self:EditorMessage(tostring(err), "error")
            CC.profileDialogPrefill = tostring(name or "")
            StaticPopup_Show("ELVUICLICKCAST_PROFILE_NAME")
            return
        end
        CC.profileDialogCallback = nil
        CC.profileDialogPrefill = nil
        local ok, opErr = self:DuplicateActiveProfile(clean)
        if ok then
            self:RefreshProfileToolbar()
            self:EditorMessage("Profile \"" .. clean .. "\" created as a copy of \"" .. active .. "\".", "success")
        else
            self:EditorMessage(tostring(opErr or "Profile duplication failed."), "error")
        end
    end
    StaticPopup_Show("ELVUICLICKCAST_PROFILE_NAME")
end

function CC:ToggleRowDeleted(index)
    local f = self.editorFrame
    if not f or not f.draftBindings or not f.draftBindings[index] then return end
    if f.deleted[index] then f.deleted[index] = nil else f.deleted[index] = true end
    f.dirty = true
    f.invalidIndex = nil
    self:CloseSelectMenu()
    self:StopInlineBindingCapture(true)
    self:RefreshEditor()
        self:EditorMessage(f.deleted[index] and "Marked for deletion. Save to apply; click X again to restore." or "Deletion mark removed.", "normal")
end

local function BuildFinalDraft(CCObject, f)
    local final = {}
    local source = {}
    for index, binding in ipairs(f.draftBindings or {}) do
        if not f.deleted[index] then
            local copy = CCObject.CopyTable(binding)
            local actionType = copy.actionType or "SPELL"
            copy.key = CCObject:NormalizePhysicalKey(copy.key)
            copy.relation = CCObject:IsOpaqueMacroAction(actionType) and "ANY" or (copy.relation or "ANY")
            copy.groundCasting = actionType == "SPELL" and copy.groundCasting == true or nil
            copy.frameOnly = CCObject:ActionSupportsWorldCasting(actionType) and CCObject:CanWorldCastPhysicalKey(copy.key) and copy.frameOnly == true or nil
            if actionType == "SPELL" then
                local spell = CCObject:ResolveSpell(copy.action)
                if spell then copy.action = spell.name end
            elseif actionType == "ITEM" then
                local item = CCObject:ResolveItem(copy.action)
                if item then copy.action = item.canonicalAction end
            elseif actionType == "TARGET" or actionType == "FOCUS" or actionType == "ASSIST" or actionType == "MENU" then
                copy.action = ""
            end
            final[#final + 1] = copy
            source[#source + 1] = index
        end
    end
    return final, source
end

function CC:CommitEditorChanges()
    local f = self.editorFrame
    if not f then return end
    self:StopInlineBindingCapture(true)
    self:CloseSelectMenu()

    local final, source = BuildFinalDraft(self, f)
    for index, binding in ipairs(final) do
        local ok, err = self:ValidateBindingAgainstList(binding, index, final)
        if not ok then
            local sourceIndex = source[index]
            f.invalidIndex = sourceIndex
            if sourceIndex then
                f.listOffset = max(0, min(sourceIndex - 1, max(0, #f.draftBindings - #f.rows)))
            end
            self:RefreshEditor()
            self:EditorMessage("Binding " .. tostring(sourceIndex or index) .. ": " .. tostring(err), "error")
            return
        end
    end

    local db = self:EnsureDB()
    local normalized = {}
    for index, binding in ipairs(final) do
        normalized[index] = self:NormalizeBindingForStorage(binding)
    end
    self:SetBindings(normalized)
    db.alwaysTargeting = f.draftAlwaysTargeting or "disabled"
    db.worldCastingEnabled = f.draftWorldCastingEnabled == true and self:IsWorldCastingAuthorized()
    db.enabled = f.draftEnabled ~= false

    self:RequestApply("editor save")
    self:BeginEditorSession(true)
    self:RefreshEditor()
    if InCombatLockdown() then
        self:EditorMessage("Saved. Secure changes are queued until combat ends.", "warn")
    else
        self:EditorMessage("Saved and applied.", "success")
    end
end

function CC:AddNewInlineBinding()
    local f = self.editorFrame
    if not f then return end
    local binding = {
        key = nil,
        relation = "ANY",
        actionType = "SPELL",
        action = "",
        groundCasting = nil,
        frameOnly = nil,
    }
    f.draftBindings[#f.draftBindings + 1] = binding
    f.dirty = true
    f.invalidIndex = nil
    f.listOffset = max(0, #f.draftBindings - #f.rows)
    self:RefreshEditor()
    self:StartInlineBindingCapture(#f.draftBindings)
end

function CC:UpdateInlineType(index, value)
    local f = self.editorFrame
    local binding = f and f.draftBindings and f.draftBindings[index]
    if not binding or f.deleted[index] then return end
    binding.actionType = value or "SPELL"
    binding.action = ""
    binding.groundCasting = nil
    binding.frameOnly = nil
    if self:IsOpaqueMacroAction(binding.actionType) then binding.relation = "ANY" end
    self:MarkEditorDirty()
    self:RefreshEditor()
end

function CC:UpdateInlineRelation(index, value)
    local f = self.editorFrame
    local binding = f and f.draftBindings and f.draftBindings[index]
    if not binding or f.deleted[index] then return end
    binding.relation = value or "ANY"
    self:MarkEditorDirty()
    self:RefreshEditor()
end

function CC:ToggleInlineGround(index)
    local f = self.editorFrame
    local binding = f and f.draftBindings and f.draftBindings[index]
    if not binding or f.deleted[index] or (binding.actionType or "SPELL") ~= "SPELL" then return end
    if binding.groundCasting == true then
        binding.groundCasting = nil
        self:MarkEditorDirty()
        self:RefreshEditor()
        self:EditorMessage("Ground Casting off. This spell targets the mouseover unit again.", "normal")
    else
        binding.groundCasting = true
        self:MarkEditorDirty()
        self:RefreshEditor()
        self:EditorMessage("Ground Casting on. Casts at your character (@player). Bypassing the ground-target reticle for area spells requires extended server API (Ascension-style); on standard 3.3.5a cores the targeting circle still appears.", "warn")
    end
end

function CC:ToggleInlineFrameOnly(index)
    local f = self.editorFrame
    local binding = f and f.draftBindings and f.draftBindings[index]
    if not binding or f.deleted[index] then return end
    if self:IsBindingForcedFrameOnly(binding) then return end
    if binding.frameOnly == true then
        binding.frameOnly = nil
    else
        binding.frameOnly = true
    end
    self:MarkEditorDirty()
    self:RefreshEditor()
end

function CC:NormalizeInlineAction(index)
    local f = self.editorFrame
    local binding = f and f.draftBindings and f.draftBindings[index]
    if not binding or f.deleted[index] then return end

    local actionType = binding.actionType or "SPELL"
    if actionType == "SPELL" and binding.action and binding.action ~= "" then
        local spell = self:ResolveSpell(binding.action)
        if spell then
            binding.action = spell.name
            self:RefreshEditor()
        end
    elseif actionType == "ITEM" and binding.action and binding.action ~= "" then
        local item = self:ResolveItem(binding.action)
        if item then
            binding.action = item.canonicalAction
            self:RefreshEditor()
        end
    end
end

function CC:StopInlineBindingCapture(cancelled)
    local f = self.editorFrame
    if not f or not f.captureFrame then return end
    f.captureIndex = nil
    f.captureFrame:EnableKeyboard(false)
    f.captureFrame:EnableMouseWheel(false)
    f.captureFrame:Hide()
    if cancelled and f:IsShown() then self:EditorMessage("Key capture cancelled.", "normal") end
end

function CC:AcceptInlinePhysicalKey(rawKey)
    local f = self.editorFrame
    local index = f and f.captureIndex
    local binding = index and f.draftBindings and f.draftBindings[index]
    if not binding or f.deleted[index] then self:StopInlineBindingCapture(true) return end
    local key = self:NormalizePhysicalKey(self:GetModifierKey() .. tostring(rawKey or ""))
    if not key then return end
    binding.key = key
    if not self:CanWorldCastPhysicalKey(key) then binding.frameOnly = nil end
    self:MarkEditorDirty()
    self:StopInlineBindingCapture(false)
    self:RefreshEditor()
    self:EditorMessage("Captured " .. self:BindingDisplay(key) .. ".", "success")
end

function CC:StartInlineBindingCapture(index)
    local f = self.editorFrame
    local binding = f and f.draftBindings and f.draftBindings[index]
    local row = binding and self:GetVisibleEditorRow(index)
    if not f or not binding or not row or not row.keyButton or f.deleted[index] then return end
    self:CloseSelectMenu()
    f.captureIndex = index
    local capture = f.captureFrame
    capture:ClearAllPoints()
    capture:SetAllPoints(row.keyButton)
    if capture.SetFrameLevel and row.keyButton.GetFrameLevel then
        capture:SetFrameLevel((row.keyButton:GetFrameLevel() or 0) + 20)
    end
    capture:EnableMouse(true)
    capture:EnableKeyboard(true)
    capture:EnableMouseWheel(true)
    capture:Show()
    capture:Raise()
    self:EditorMessage("Use the active Click to Bind field: press a key, click a mouse button, or scroll. Escape cancels.", "normal")
end

function CC:GetVisibleEditorRow(bindingIndex)
    local f = self.editorFrame
    if not f then return nil end
    for _, row in ipairs(f.rows or {}) do
        if row.bindingIndex == bindingIndex and row:IsShown() then return row end
    end
end

function CC:OpenSpellPicker(index)
    local f = self.editorFrame
    local binding = f and f.draftBindings and f.draftBindings[index]
    if not binding or (binding.actionType or "SPELL") ~= "SPELL" or f.deleted[index] then return end
    self:CloseMacroPicker()
    self:CloseCustomMacroWriter()
    local picker = f.spellPicker
    picker.targetIndex = index
    picker.search:SetText("")
    picker.offset = 0
    picker:Show()
    picker:Raise()
    picker.search:SetFocus()
    self:RefreshSpellPicker()
end

function CC:CloseSpellPicker()
    local f = self.editorFrame
    if f and f.spellPicker then
        f.spellPicker.search:ClearFocus()
        f.spellPicker.targetIndex = nil
        f.spellPicker:Hide()
    end
end

function CC:RefreshSpellPicker()
    local f = self.editorFrame
    if not f or not f.spellPicker or not f.spellPicker:IsShown() then return end
    local picker = f.spellPicker
    local query = strlower(picker.search:GetText() or "")
    local filtered = {}
    for _, spell in ipairs(self:GetSpellbookEntries()) do
        local idText = spell.spellID and tostring(spell.spellID) or ""
        if query == "" or strfind(strlower(spell.name), query, 1, true) or (idText ~= "" and strfind(idText, query, 1, true)) then
            filtered[#filtered + 1] = spell
        end
    end
    picker.filtered = filtered
    picker.offset = max(0, min(picker.offset or 0, max(0, #filtered - #picker.rows)))
    for i, row in ipairs(picker.rows) do
        local entry = filtered[picker.offset + i]
        if entry then
            row.entry = entry
            row.name:SetText(entry.name)
            local detail = entry.rank or ""
            if entry.spellID then detail = detail ~= "" and (detail .. "  ID " .. entry.spellID) or ("ID " .. entry.spellID) end
            row.rank:SetText(detail)
            if entry.icon then row.icon:SetTexture(entry.icon) row.icon:Show() else row.icon:Hide() end
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
    picker.count:SetText(format("%d learned spell families", #filtered))
end

function CC:OpenMacroPicker(index)
    local f = self.editorFrame
    local binding = f and f.draftBindings and f.draftBindings[index]
    if not binding or binding.actionType ~= "MACRO" or f.deleted[index] then return end
    self:CloseSpellPicker()
    self:CloseCustomMacroWriter()
    local picker = f.macroPicker
    picker.targetIndex = index
    picker.search:SetText("")
    picker.offset = 0
    picker:Show()
    picker:Raise()
    picker.search:SetFocus()
    self:RefreshMacroPicker()
end

function CC:CloseMacroPicker()
    local f = self.editorFrame
    if f and f.macroPicker then
        f.macroPicker.search:ClearFocus()
        f.macroPicker.targetIndex = nil
        f.macroPicker:Hide()
    end
end

function CC:RefreshMacroPicker()
    local f = self.editorFrame
    if not f or not f.macroPicker or not f.macroPicker:IsShown() then return end
    local picker = f.macroPicker
    local query = strlower(picker.search:GetText() or "")
    local filtered = {}
    for _, macro in ipairs(self:GetCharacterMacros()) do
        if query == "" or strfind(strlower(macro.name), query, 1, true) then filtered[#filtered + 1] = macro end
    end
    picker.filtered = filtered
    picker.offset = max(0, min(picker.offset or 0, max(0, #filtered - #picker.rows)))
    for i, row in ipairs(picker.rows) do
        local entry = filtered[picker.offset + i]
        if entry then
            row.entry = entry
            row.name:SetText(entry.name)
            local firstLine = tostring(entry.body or ""):match("([^\n\r]+)") or ""
            row.preview:SetText(firstLine)
            if entry.icon then row.icon:SetTexture(entry.icon) row.icon:Show() else row.icon:Hide() end
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
    picker.count:SetText(format("%d Character Macros", #filtered))
end

function CC:OpenCustomMacroWriter(index)
    local f = self.editorFrame
    local binding = f and f.draftBindings and f.draftBindings[index]
    if not binding or binding.actionType ~= "CUSTOM" or f.deleted[index] then return end
    self:CloseSpellPicker()
    self:CloseMacroPicker()
    local writer = f.customWriter
    writer.targetIndex = index
    writer.edit:SetText(tostring(binding.action or ""))
    writer:Show()
    writer:Raise()
    writer.edit:SetFocus()
end

function CC:CloseCustomMacroWriter()
    local f = self.editorFrame
    if f and f.customWriter then
        f.customWriter.edit:ClearFocus()
        f.customWriter.targetIndex = nil
        f.customWriter:Hide()
    end
end

function CC:SaveCustomMacroWriter()
    local f = self.editorFrame
    local writer = f and f.customWriter
    local index = writer and writer.targetIndex
    local binding = index and f.draftBindings and f.draftBindings[index]
    if not binding then self:CloseCustomMacroWriter() return end
    binding.action = writer.edit:GetText() or ""
    self:MarkEditorDirty()
    self:CloseCustomMacroWriter()
    self:RefreshEditor()
end

local function SetEditTextSilently(row, text)
    row.suppressActionChanged = true
    row.actionEdit:SetText(text or "")
    if row.actionEdit.SetCursorPosition and not row.actionEdit:HasFocus() then
        row.actionEdit:SetCursorPosition(0)
    end
    if row.actionEdit.HighlightText and not row.actionEdit:HasFocus() then
        row.actionEdit:HighlightText(0, 0)
    end
    row.suppressActionChanged = false
end

local function ActionEditorValue(CCObject, binding)
    local actionType = binding.actionType or "SPELL"
    if actionType == "TARGET" or actionType == "FOCUS" or actionType == "ASSIST" or actionType == "MENU" then
        return CCObject:ActionTypeDisplay(actionType)
    end
    return tostring(binding.action or "")
end

function CC:ConfigureEditorRow(row, index, binding)
    local f = self.editorFrame
    row.bindingIndex = index
    row.binding = binding
    row:SetAlpha(f.deleted[index] and 0.32 or 1)
    SetBox(row, C.row, f.invalidIndex == index and C.danger or C.border)

    local deleted = f.deleted[index] == true
    local actionType = binding.actionType or "SPELL"
    local relation = binding.relation or "ANY"

    if row.deleteButton and row.deleteButton.label then
        row.deleteButton.label:SetTextColor(deleted and unpack(C.success) or unpack(C.danger))
    end

    row.keyButton:SetText(binding.key and self:BindingDisplay(binding.key) or "Click to bind")
    row.keyButton:SetEnabledState(not deleted)

    if self:IsOpaqueMacroAction(actionType) then
        row.relationSelect:SetOptions({{value="ANY", text="As Authored"}}, "ANY")
        row.relationSelect:SetEnabledState(false)
    else
        local options = RELATIONS_ALL
        if actionType == "SPELL" then
            local allowed = GetEditorSpellRelations(self, f, binding.key, index)
            local allowedSet = {}
            for _, value in ipairs(allowed) do allowedSet[value] = true end
            if not allowedSet[relation] then
                relation = allowed[1] or "ANY"
                binding.relation = relation
                f.dirty = true
            end
            options = BuildRelationOptions(allowed)
        end
        row.relationSelect:SetOptions(options, relation)
        row.relationSelect:SetDisplayText(EffectiveRelationDisplay(self, f, binding, index))
        row.relationSelect:SetEnabledState(not deleted)
    end

    row.typeSelect:SetOptions(ACTION_TYPES, actionType)
    row.typeSelect:SetEnabledState(not deleted)

    local hasActionText = actionType == "SPELL" or actionType == "MACRO" or actionType == "ITEM"
    row.actionShell:Show()
    SetEditTextSilently(row, ActionEditorValue(self, binding))
    row.actionEdit:SetTextColor(unpack(hasActionText and C.text or C.muted))
    row.actionEdit:EnableMouse(hasActionText and not deleted)
    row.actionEdit:SetAutoFocus(false)

    local icon = self:GetBindingIcon(binding)
    if icon then row.actionIcon:SetTexture(icon) row.actionIcon:Show() else row.actionIcon:Hide() end

    row.pickButton:Hide()
    row.customButton:Hide()
    if actionType == "SPELL" or actionType == "MACRO" then
        row.pickButton:Show()
        row.pickButton:SetEnabledState(not deleted)
    elseif actionType == "CUSTOM" then
        row.customButton:Show()
        row.customButton:SetEnabledState(not deleted)
        local firstLine = tostring(binding.action or ""):match("([^\n\r]+)") or ""
        if firstLine == "" then firstLine = "Edit custom macro..." end
        SetEditTextSilently(row, firstLine)
        row.actionEdit:EnableMouse(false)
        row.actionEdit:SetTextColor(unpack(C.text))
    end

    local spellAction = actionType == "SPELL"
    row.groundButton:SetText(spellAction and (binding.groundCasting == true and "ON" or "OFF") or "-")
    row.groundButton:SetEnabledState(spellAction and not deleted)
    ApplyStateLabelColor(row.groundButton.label, spellAction and binding.groundCasting == true)

    local forcedFrameOnlyReason = self:GetForcedFrameOnlyReason(actionType, binding.key)
    local forcedFrameOnly = forcedFrameOnlyReason ~= nil
    local effectiveFrameOnly = forcedFrameOnly or binding.frameOnly == true
    row.frameOnlyButton.forcedFrameOnlyReason = forcedFrameOnlyReason
    row.frameOnlyButton:SetText(forcedFrameOnly and "LOCKED" or (effectiveFrameOnly and "ON" or "OFF"))
    row.frameOnlyButton:SetEnabledState(not forcedFrameOnly and not deleted)
    ApplyStateLabelColor(row.frameOnlyButton.label, effectiveFrameOnly)
end

function CC:RefreshEditor()
    local f = self.editorFrame
    if not f or not f:IsShown() then return end
    self:ApplyEditorMedia()
    self:RefreshEnableButton()
    self:RefreshWorldCastingButton()
    self:RefreshProfileToolbar()
    f.alwaysSelect:SetValue(f.draftAlwaysTargeting or "disabled")

    local bindings = f.draftBindings or {}
    f.listOffset = max(0, min(f.listOffset or 0, max(0, #bindings - #f.rows)))
    for i, row in ipairs(f.rows) do
        local index = f.listOffset + i
        local binding = bindings[index]
        if binding then
            row:Show()
            self:ConfigureEditorRow(row, index, binding)
        else
            row.bindingIndex = nil
            row.binding = nil
            row:Hide()
        end
    end

    f.rangeText:SetText(#bindings == 0 and "No bindings" or format("%d-%d of %d", min(#bindings, f.listOffset + 1), min(#bindings, f.listOffset + #f.rows), #bindings))
    f.saveButton:SetEnabledState(f.dirty == true)
    f.cancelButton:SetEnabledState(f.dirty == true)
    f.unsaved:SetText(f.dirty and "UNSAVED" or "")

    local registered = self.GetRegisteredFrameCount and self:GetRegisteredFrameCount() or 0
    local state = f.draftEnabled and "ON" or "OFF"
    if InCombatLockdown() and self.pendingApply then state = state .. " (queued)" end
    local firstVisible = #bindings == 0 and 0 or min(#bindings, f.listOffset + 1)
    local lastVisible = #bindings == 0 and 0 or min(#bindings, f.listOffset + #f.rows)
    f.status:SetText(format("Runtime %s  |  World %s  |  %d frames  |  %d-%d/%d", state, f.draftWorldCastingEnabled and "ON" or "OFF", registered, firstVisible, lastVisible, #bindings))
end

local function BindRightDelete(control, row)
    control.onRightClick = function()
        if row.bindingIndex then CC:ToggleRowDeleted(row.bindingIndex) end
    end
end

function CC:BuildInlineRow(parent, rowNumber)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if CC.editorFrame and CC.editorFrame.captureIndex == self.bindingIndex then return end
        if button == "RightButton" and self.bindingIndex then CC:ToggleRowDeleted(self.bindingIndex) end
    end)
    row:SetScript("OnEnter", function(self)
        if not (CC.editorFrame.deleted and CC.editorFrame.deleted[self.bindingIndex]) then SetBoxColor(self, C.hover) end
    end)
    row:SetScript("OnLeave", function(self) SetBoxColor(self, C.row) end)
    SetBox(row, C.row, C.border)

    row.keyButton = NewButton(row, "", 150, 26, false)
    row.keyButton:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.keyButton:SetScript("OnClick", function(self, button)
        if CC.editorFrame and CC.editorFrame.captureIndex == row.bindingIndex then
            local key = CC:MouseButtonToKey(button)
            if key then CC:AcceptInlinePhysicalKey(key) end
            return
        end
        if button == "RightButton" then
            if row.bindingIndex then CC:ToggleRowDeleted(row.bindingIndex) end
        elseif row.bindingIndex then
            CC:StartInlineBindingCapture(row.bindingIndex)
        end
    end)

    row.relationSelect = NewSelect(row, 150, RELATIONS_ALL, "ANY", function(value)
        if row.bindingIndex then CC:UpdateInlineRelation(row.bindingIndex, value) end
    end)
    row.relationSelect:SetPoint("LEFT", row.keyButton, "RIGHT", -1, 0)
    BindRightDelete(row.relationSelect, row)

    row.typeSelect = NewSelect(row, 145, ACTION_TYPES, "SPELL", function(value)
        if row.bindingIndex then CC:UpdateInlineType(row.bindingIndex, value) end
    end)
    row.typeSelect:SetPoint("LEFT", row.relationSelect, "RIGHT", -1, 0)
    BindRightDelete(row.typeSelect, row)

    row.actionShell, row.actionEdit = NewEditBox(row, 320, 26, false)
    row.actionShell:SetPoint("LEFT", row.typeSelect, "RIGHT", -1, 0)
    row.actionIcon = row.actionShell:CreateTexture(nil, "ARTWORK")
    row.actionIcon:SetWidth(18)
    row.actionIcon:SetHeight(18)
    row.actionIcon:SetPoint("LEFT", row.actionShell, "LEFT", 4, 0)
    row.actionEdit:ClearAllPoints()
    row.actionEdit:SetPoint("LEFT", row.actionShell, "LEFT", 25, 0)
    row.actionEdit:SetPoint("RIGHT", row.actionShell, "RIGHT", -28, 0)
    row.actionEdit:SetHeight(20)
    row.actionEdit:SetScript("OnTextChanged", function(self)
        if row.suppressActionChanged or not row.bindingIndex then return end
        local f = CC.editorFrame
        local binding = f and f.draftBindings and f.draftBindings[row.bindingIndex]
        if not binding or f.deleted[row.bindingIndex] then return end
        local actionType = binding.actionType or "SPELL"
        if actionType == "SPELL" or actionType == "MACRO" or actionType == "ITEM" then
            binding.action = self:GetText() or ""
            CC:MarkEditorDirty()
            f.saveButton:SetEnabledState(true)
            f.cancelButton:SetEnabledState(true)
            f.unsaved:SetText("UNSAVED")
        end
    end)
    row.actionEdit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if row.bindingIndex then CC:NormalizeInlineAction(row.bindingIndex) end
    end)
    row.actionEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    row.actionEdit:SetScript("OnEditFocusLost", function()
        if row.bindingIndex then CC:NormalizeInlineAction(row.bindingIndex) end
    end)
    row.actionEdit:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" and row.bindingIndex then
            self:ClearFocus()
            CC:ToggleRowDeleted(row.bindingIndex)
        end
    end)

    row.pickButton = NewButton(row.actionShell, "...", 26, 24, false)
    row.pickButton:SetPoint("RIGHT", row.actionShell, "RIGHT", -1, 0)
    row.pickButton:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if row.bindingIndex then CC:ToggleRowDeleted(row.bindingIndex) end
            return
        end
        if not row.bindingIndex then return end
        local binding = CC.editorFrame.draftBindings[row.bindingIndex]
        if binding.actionType == "SPELL" then CC:OpenSpellPicker(row.bindingIndex)
        elseif binding.actionType == "MACRO" then CC:OpenMacroPicker(row.bindingIndex) end
    end)

    row.customButton = NewButton(row.actionShell, "...", 26, 24, false)
    row.customButton:SetPoint("RIGHT", row.actionShell, "RIGHT", -1, 0)
    row.customButton:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if row.bindingIndex then CC:ToggleRowDeleted(row.bindingIndex) end
            return
        end
        if row.bindingIndex then CC:OpenCustomMacroWriter(row.bindingIndex) end
    end)

    row.groundButton = NewButton(row, "OFF", 105, 26, false)
    row.groundButton:SetPoint("LEFT", row.actionShell, "RIGHT", -1, 0)
    row.groundButton:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if row.bindingIndex then CC:ToggleRowDeleted(row.bindingIndex) end
        elseif row.bindingIndex then CC:ToggleInlineGround(row.bindingIndex) end
    end)
    row.groundButton:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Ground Casting", 1, 1, 1)
        GameTooltip:AddLine("Spell rows only. Casts the spell at your own character (@player) instead of the mouseover unit, which is what lets an area spell skip the ground-target reticle.", nil, nil, nil, true)
        GameTooltip:AddLine("Bypassing the reticle requires extended server API (Ascension-style). On standard 3.3.5a cores the targeting circle still appears and you must click it.", 0.95, 0.72, 0.25, true)
        GameTooltip:Show()
    end)
    row.groundButton:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    row.frameOnlyButton = NewButton(row, "OFF", 105, 26, false)
    row.frameOnlyButton:SetPoint("LEFT", row.groundButton, "RIGHT", -1, 0)
    row.frameOnlyButton:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if row.bindingIndex then CC:ToggleRowDeleted(row.bindingIndex) end
        elseif row.bindingIndex then CC:ToggleInlineFrameOnly(row.bindingIndex) end
    end)
    row.frameOnlyButton:SetScript("OnEnter", function(self)
        if self.forcedFrameOnlyReason and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Frame Only — Locked", 1, 1, 1)
            GameTooltip:AddLine(self.forcedFrameOnlyReason, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    row.frameOnlyButton:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    -- Custom fix (user): an explicit delete/X button per row. The addon's
    -- right-click-to-delete gesture is unusable for this user, who binds
    -- Right/Shift/Ctrl/Alt + Left/Right/Middle clicks to cast spells, so a
    -- visible button is required to remove binds without conflicting with the
    -- mouse-button spell combos.
    row.deleteButton = NewButton(row, "X", 34, 26, false)
    row.deleteButton:SetPoint("LEFT", row.frameOnlyButton, "RIGHT", -1, 0)
    row.deleteButton:SetScript("OnClick", function(self, button)
        if button ~= "LeftButton" then return end
        if row.bindingIndex then CC:ToggleRowDeleted(row.bindingIndex) end
    end)
    row.deleteButton:SetScript("OnEnter", function(self)
        if not row.bindingIndex or not GameTooltip then return end
        local f = CC.editorFrame
        local deleted = f and f.deleted and f.deleted[row.bindingIndex] == true
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(deleted and "Restore this binding" or "Delete this binding", 1, 1, 1)
        GameTooltip:AddLine(deleted and "Removes the deletion mark. The row is restored for Save." or "Marks this row for deletion. Save commits; click X again to undo.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    row.deleteButton:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    return row
end

function CC:BuildSpellPicker(frame)
    local p = CreateFrame("Frame", nil, frame)
    p:SetWidth(580)
    p:SetHeight(450)
    p:SetPoint("CENTER", frame, "CENTER", 0, 0)
    p:SetFrameStrata("TOOLTIP")
    SetBox(p, C.panel, C.border)
    if p.SetTemplate then p:SetTemplate("Transparent") end
    frame.spellPicker = p

    p.title = NewText(p, "Choose Spell", EDITOR_FONT_SIZE, C.text)
    p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -14)
    local close = NewButton(p, "X", 26, 26, false)
    close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() CC:CloseSpellPicker() end)

    local shell, search = NewEditBox(p, 552, 28, false)
    shell:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -48)
    p.search = search
    search:SetScript("OnTextChanged", function() p.offset = 0 CC:RefreshSpellPicker() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() CC:CloseSpellPicker() end)

    p.count = NewText(p, "", EDITOR_FONT_SIZE, C.muted)
    p.count:SetPoint("TOPLEFT", shell, "BOTTOMLEFT", 2, -6)

    p.rows = {}
    for i = 1, 10 do
        local r = CreateFrame("Button", nil, p)
        r:SetHeight(31)
        r:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -96 - ((i - 1) * 33))
        r:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -96 - ((i - 1) * 33))
        SetBox(r, C.row, C.border)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetWidth(22) r.icon:SetHeight(22) r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
        r.name = NewText(r, "", EDITOR_FONT_SIZE, C.text)
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 7, 0)
        r.name:SetWidth(330)
        r.rank = NewText(r, "", EDITOR_FONT_SIZE, C.muted, "RIGHT")
        r.rank:SetPoint("RIGHT", r, "RIGHT", -7, 0)
        r.rank:SetWidth(160)
        r:SetScript("OnEnter", function(self) SetBoxColor(self, C.hover) end)
        r:SetScript("OnLeave", function(self) SetBoxColor(self, C.row) end)
        r:SetScript("OnClick", function(self)
            local index = p.targetIndex
            local binding = index and frame.draftBindings and frame.draftBindings[index]
            if self.entry and binding then
                binding.action = self.entry.name
                CC:MarkEditorDirty()
                CC:CloseSpellPicker()
                CC:RefreshEditor()
            end
        end)
        p.rows[i] = r
    end
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(self, delta)
        self.offset = max(0, min(max(0, #(self.filtered or {}) - #self.rows), (self.offset or 0) - delta * 2))
        CC:RefreshSpellPicker()
    end)
    p:Hide()
end

function CC:BuildMacroPicker(frame)
    local p = CreateFrame("Frame", nil, frame)
    p:SetWidth(600)
    p:SetHeight(440)
    p:SetPoint("CENTER", frame, "CENTER", 0, 0)
    p:SetFrameStrata("TOOLTIP")
    SetBox(p, C.panel, C.border)
    if p.SetTemplate then p:SetTemplate("Transparent") end
    frame.macroPicker = p

    p.title = NewText(p, "Choose Character Macro", EDITOR_FONT_SIZE, C.text)
    p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -14)
    local close = NewButton(p, "X", 26, 26, false)
    close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() CC:CloseMacroPicker() end)

    local shell, search = NewEditBox(p, 572, 28, false)
    shell:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -48)
    p.search = search
    search:SetScript("OnTextChanged", function() p.offset = 0 CC:RefreshMacroPicker() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() CC:CloseMacroPicker() end)

    p.count = NewText(p, "", EDITOR_FONT_SIZE, C.muted)
    p.count:SetPoint("TOPLEFT", shell, "BOTTOMLEFT", 2, -6)

    p.rows = {}
    for i = 1, 9 do
        local r = CreateFrame("Button", nil, p)
        r:SetHeight(34)
        r:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -96 - ((i - 1) * 36))
        r:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -96 - ((i - 1) * 36))
        SetBox(r, C.row, C.border)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetWidth(23) r.icon:SetHeight(23) r.icon:SetPoint("LEFT", r, "LEFT", 4, 0)
        r.name = NewText(r, "", EDITOR_FONT_SIZE, C.text)
        r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 7, -1)
        r.name:SetWidth(220)
        r.preview = NewText(r, "", EDITOR_FONT_SIZE, C.muted)
        r.preview:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 7, 1)
        r.preview:SetPoint("RIGHT", r, "RIGHT", -7, 0)
        r.preview:SetWordWrap(false)
        r:SetScript("OnEnter", function(self) SetBoxColor(self, C.hover) end)
        r:SetScript("OnLeave", function(self) SetBoxColor(self, C.row) end)
        r:SetScript("OnClick", function(self)
            local index = p.targetIndex
            local binding = index and frame.draftBindings and frame.draftBindings[index]
            if self.entry and binding then
                binding.action = self.entry.name
                CC:MarkEditorDirty()
                CC:CloseMacroPicker()
                CC:RefreshEditor()
            end
        end)
        p.rows[i] = r
    end
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(self, delta)
        self.offset = max(0, min(max(0, #(self.filtered or {}) - #self.rows), (self.offset or 0) - delta * 2))
        CC:RefreshMacroPicker()
    end)
    p:Hide()
end

function CC:BuildCustomMacroWriter(frame)
    local p = CreateFrame("Frame", nil, frame)
    p:SetWidth(650)
    p:SetHeight(380)
    p:SetPoint("CENTER", frame, "CENTER", 0, 0)
    p:SetFrameStrata("TOOLTIP")
    SetBox(p, C.panel, C.border)
    if p.SetTemplate then p:SetTemplate("Transparent") end
    frame.customWriter = p

    p.title = NewText(p, "Custom Macro", EDITOR_FONT_SIZE, C.text)
    p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -14)
    p.help = NewText(p, "Exact-body macro text. ClickCast does not inject relation or target conditions.", EDITOR_FONT_SIZE, C.muted)
    p.help:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -6)

    local shell, edit = NewEditBox(p, 622, 250, true)
    shell:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -70)
    p.edit = edit
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() CC:CloseCustomMacroWriter() end)

    p.cancel = NewButton(p, "Cancel", 100, 28, false)
    p.cancel:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -122, 14)
    p.cancel:SetScript("OnClick", function() CC:CloseCustomMacroWriter() end)
    p.save = NewButton(p, "Done", 100, 28, true)
    p.save:SetPoint("LEFT", p.cancel, "RIGHT", 8, 0)
    p.save:SetScript("OnClick", function() CC:SaveCustomMacroWriter() end)
    p:Hide()
end

function CC:LayoutEmbeddedEditor()
    local frame = self.editorFrame
    if not frame or not frame.list then return end


    local parentWidth = (frame.GetParent and frame:GetParent() and frame:GetParent().GetWidth and frame:GetParent():GetWidth()) or 0
    local listFrameWidth = (frame.list and frame.list.GetWidth and frame.list:GetWidth()) or 0
    local listWidth = max(1, frame:GetWidth() or 0, parentWidth, listFrameWidth)
    local innerWidth = max(1, listWidth - 10)


    local keyWidth, relationWidth, groundWidth, frameOnlyWidth, minActionWidth
    local typeWidth = 175
    local deleteWidth = 34
    if innerWidth >= 900 then
        keyWidth, relationWidth = 150, 150
        groundWidth, frameOnlyWidth, minActionWidth = 105, 105, 200
    elseif innerWidth >= 760 then
        keyWidth, relationWidth = 125, 145
        groundWidth, frameOnlyWidth, minActionWidth = 95, 95, 125
    else
        keyWidth, relationWidth = 105, 135
        groundWidth, frameOnlyWidth, minActionWidth = 85, 85, 95
    end

    local overlap = 5
    local actionWidth = max(minActionWidth, innerWidth - (keyWidth + relationWidth + typeWidth + groundWidth + frameOnlyWidth + deleteWidth) + overlap)

    local xKey = 0
    local xRelation = xKey + keyWidth - 1
    local xType = xRelation + relationWidth - 1
    local xAction = xType + typeWidth - 1
    local xGround = xAction + actionWidth - 1
    local xFrameOnly = xGround + groundWidth - 1
    local xDelete = xFrameOnly + frameOnlyWidth - 1
    local rowWidth = xDelete + deleteWidth

    frame.header:SetWidth(rowWidth)
    local widths = {keyWidth, relationWidth, typeWidth, actionWidth, groundWidth, frameOnlyWidth, deleteWidth}
    local offsets = {xKey, xRelation, xType, xAction, xGround, xFrameOnly, xDelete}
    for i, text in ipairs(frame.headerTexts or {}) do
        text:ClearAllPoints()
        text:SetPoint("LEFT", frame.header, "LEFT", offsets[i], 0)
        text:SetWidth(widths[i])
    end

    for _, row in ipairs(frame.rows or {}) do
        row:SetWidth(rowWidth)
        row.keyButton:SetWidth(keyWidth)
        row.relationSelect:SetWidth(relationWidth)
        row.typeSelect:SetWidth(typeWidth)
        row.actionShell:SetWidth(actionWidth)
        row.groundButton:SetWidth(groundWidth)
        row.frameOnlyButton:SetWidth(frameOnlyWidth)
        row.deleteButton:SetWidth(deleteWidth)
        if row.actionEdit then
            row.actionEdit:ClearAllPoints()
            row.actionEdit:SetPoint("LEFT", row.actionShell, "LEFT", 25, 0)
            row.actionEdit:SetPoint("RIGHT", row.actionShell, "RIGHT", -28, 0)
            row.actionEdit:SetHeight(20)
            if row.actionEdit.SetCursorPosition and not row.actionEdit:HasFocus() then
                row.actionEdit:SetCursorPosition(0)
            end
            if row.actionEdit.HighlightText and not row.actionEdit:HasFocus() then
                row.actionEdit:HighlightText(0, 0)
            end
        end
    end

    if frame:IsShown() then
        CC:RefreshEditor()
    end
end

function CC:BuildEditor(parent)
    if self.editorFrame then
        if parent and self.editorFrame:GetParent() ~= parent then self.editorFrame:SetParent(parent) end
        return self.editorFrame
    end

    parent = parent or UIParent
    local frame = CreateFrame("Frame", nil, parent)
    self.editorFrame = frame
    frame.fontObjects = {}
    frame.nativeSelects = {}
    frame.nativeChecks = {}
    frame.deleted = {}
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    frame:SetFrameStrata(parent.GetFrameStrata and parent:GetFrameStrata() or "DIALOG")
    frame:EnableMouse(true)

    local top = CreateFrame("Frame", nil, frame)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -2)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -2)
    top:SetHeight(112)
    SetBox(top, C.panel, C.border)

    local runtimeLabel = NewText(top, "Enable", EDITOR_FONT_SIZE, C.muted)
    runtimeLabel:SetPoint("TOPLEFT", top, "TOPLEFT", 8, -5)
    frame.enableToggle = NewCheckBox(top, "", 108, false, function(value)
        frame.draftEnabled = value and true or false
        CC:MarkEditorDirty()
        CC:RefreshEditor()
    end)
    frame.enableToggle:SetPoint("TOPLEFT", runtimeLabel, "BOTTOMLEFT", -2, -1)

    local worldLabel = NewText(top, "World Casting", EDITOR_FONT_SIZE, C.muted)
    worldLabel:SetPoint("TOPLEFT", top, "TOPLEFT", 128, -5)
    frame.worldCastingButton = NewButton(top, "OFF", 125, 25, false)
    frame.worldCastingButton:SetPoint("TOPLEFT", worldLabel, "BOTTOMLEFT", 0, -2)
    frame.worldCastingButton:SetScript("OnClick", function(_, button) if button == "LeftButton" then CC:RequestWorldCastingForEditor() end end)

    local atLabel = NewText(top, "Always Targeting", EDITOR_FONT_SIZE, C.muted)
    atLabel:SetPoint("TOPLEFT", top, "TOPLEFT", 272, -5)
    frame.alwaysSelect = NewSelect(top, 175, ALWAYS_TARGETING, "disabled", function(value)
        frame.draftAlwaysTargeting = value
        CC:MarkEditorDirty()
        CC:RefreshEditor()
    end)
    frame.alwaysSelect:SetPoint("TOPLEFT", atLabel, "BOTTOMLEFT", 0, -2)

    -- Profile toolbar (header row 2): active-profile dropdown, profile
    -- management buttons, the auto talent-group switch and the per-group
    -- profile assignments.
    local profileLabel = NewText(top, "Profiles", EDITOR_FONT_SIZE, C.muted)
    profileLabel:SetPoint("TOPLEFT", top, "TOPLEFT", 8, -58)
    frame.profileSelect = NewSelect(top, 140, BuildProfileOptions(), CC:GetActiveProfile(), function(value)
        if value and value ~= CC:GetActiveProfile() then
            CC:SwitchEditorProfile(value)
        end
    end)
    frame.profileSelect:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", 0, -2)

    frame.newProfileButton = NewButton(top, "New", 46, 25, false)
    frame.newProfileButton:SetPoint("LEFT", frame.profileSelect, "RIGHT", 6, 0)
    frame.newProfileButton:SetScript("OnClick", function(_, button) if button == "LeftButton" then CC:ShowNewProfileDialog() end end)

    frame.renameProfileButton = NewButton(top, "Rename", 64, 25, false)
    frame.renameProfileButton:SetPoint("LEFT", frame.newProfileButton, "RIGHT", 4, 0)
    frame.renameProfileButton:SetScript("OnClick", function(_, button) if button == "LeftButton" then CC:ShowRenameProfileDialog() end end)

    frame.deleteProfileButton = NewButton(top, "Delete", 60, 25, false)
    frame.deleteProfileButton:SetPoint("LEFT", frame.renameProfileButton, "RIGHT", 4, 0)
    frame.deleteProfileButton:SetScript("OnClick", function(_, button) if button == "LeftButton" then CC:DeleteSelectedProfile() end end)

    frame.duplicateProfileButton = NewButton(top, "Duplicate", 74, 25, false)
    frame.duplicateProfileButton:SetPoint("LEFT", frame.deleteProfileButton, "RIGHT", 4, 0)
    frame.duplicateProfileButton:SetScript("OnClick", function(_, button) if button == "LeftButton" then CC:ShowDuplicateProfileDialog() end end)

    frame.autoSwitchCheck = NewCheckBox(top, "Auto Switch (Talent Groups)", 175, false, function(value)
        CC:SetAutoSwitch(value and true or false)
        CC:RefreshProfileToolbar()
    end)
    frame.autoSwitchCheck:SetPoint("LEFT", frame.duplicateProfileButton, "RIGHT", 14, 0)

    local tg1Label = NewText(top, "Talent Group 1 Profile", EDITOR_FONT_SIZE, C.muted)
    tg1Label:SetPoint("TOPLEFT", top, "TOPLEFT", 604, -58)
    frame.tg1Select = NewSelect(top, 140, BuildProfileOptions(), "Default", function(value)
        if value then CC:SetTalentProfile(1, value) end
    end)
    frame.tg1Select:SetPoint("TOPLEFT", tg1Label, "BOTTOMLEFT", 0, -2)

    local tg2Label = NewText(top, "Talent Group 2 Profile", EDITOR_FONT_SIZE, C.muted)
    tg2Label:SetPoint("TOPLEFT", top, "TOPLEFT", 754, -58)
    frame.tg2Label = tg2Label
    frame.tg2Select = NewSelect(top, 140, BuildProfileOptions(), "Default", function(value)
        if value then CC:SetTalentProfile(2, value) end
    end)
    frame.tg2Select:SetPoint("TOPLEFT", tg2Label, "BOTTOMLEFT", 0, -2)

    frame.topHelp = NewText(top, "World OFF = registered frames only. World ON = Spell, Item, Target, Focus, Assist, Macro, and Custom Macro can work in the world unless Frame Only is ON. Macro targeting stays As Authored. Unit Menu and plain Left/Right are LOCKED Frame Only.", EDITOR_FONT_SIZE, C.muted)
    frame.topHelp:SetPoint("TOPLEFT", top, "TOPLEFT", 470, -7)
    frame.topHelp:SetPoint("RIGHT", top, "RIGHT", -8, 0)
    frame.topHelp:SetHeight(45)
    frame.topHelp:SetWordWrap(true)
    frame.topHelp:SetJustifyV("TOP")

    local list = CreateFrame("Frame", nil, frame)
    frame.list = list
    list:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -8)
    list:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, -8)


    list:SetPoint("BOTTOM", frame, "BOTTOM", 0, 76)
    SetBox(list, C.panel, C.border)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        local bindings = frame.draftBindings or {}
        frame.listOffset = max(0, min(max(0, #bindings - #frame.rows), (frame.listOffset or 0) - delta * 2))
        CC:CloseSelectMenu()
        CC:StopInlineBindingCapture(true)
        CC:RefreshEditor()
    end)

    local header = CreateFrame("Frame", nil, list)
    frame.header = header
    header:SetPoint("TOPLEFT", list, "TOPLEFT", 5, -5)
    header:SetHeight(27)
    SetBox(header, C.row, C.border)

    local headers = {"Keybind", "Relation", "Type", "Action", "Ground Cast", "Frame Only", "Del"}
    frame.headerTexts = {}
    for i, label in ipairs(headers) do
        local t = NewText(header, label, EDITOR_FONT_SIZE, C.muted, "CENTER")
        frame.headerTexts[i] = t
    end

    frame.rows = {}
    for i = 1, VISIBLE_ROWS do
        local row = self:BuildInlineRow(list, i)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 5, -34 - ((i - 1) * (ROW_HEIGHT + ROW_GAP)))
        frame.rows[i] = row
    end


    local footer = CreateFrame("Frame", nil, frame)
    frame.footer = footer
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(72)
    footer:SetFrameLevel((list:GetFrameLevel() or 1) + 3)

    frame.newButton = NewButton(footer, "New Binding", 135, 29, true)
    frame.newButton:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", 0, 2)
    frame.newButton:SetScript("OnClick", function(_, button) if button == "LeftButton" then CC:AddNewInlineBinding() end end)

    frame.saveButton = NewButton(footer, "Save", 110, 29, true)
    frame.saveButton:SetPoint("LEFT", frame.newButton, "RIGHT", 50, 0)
    frame.saveButton:SetScript("OnClick", function(_, button) if button == "LeftButton" then CC:CommitEditorChanges() end end)
    frame.cancelButton = NewButton(footer, "Cancel", 110, 29, false)
    frame.cancelButton:SetPoint("LEFT", frame.saveButton, "RIGHT", 6, 0)
    frame.cancelButton:SetScript("OnClick", function(_, button) if button == "LeftButton" then CC:CancelEditorChanges() end end)

    frame.message = NewText(footer, "", EDITOR_FONT_SIZE, C.muted)
    frame.message:SetPoint("TOPLEFT", footer, "TOPLEFT", 7, -2)
    frame.message:SetPoint("RIGHT", footer, "CENTER", -8, 0)
    frame.message:SetHeight(20)
    frame.message:SetJustifyH("LEFT")
    frame.message:SetWordWrap(false)

    frame.unsaved = NewText(footer, "", EDITOR_FONT_SIZE, C.warning, "RIGHT")
    frame.unsaved:SetPoint("TOPRIGHT", footer, "TOPRIGHT", -7, -2)
    frame.unsaved:SetWidth(90)
    frame.unsaved:SetHeight(20)
    frame.unsaved:SetJustifyH("RIGHT")
    frame.unsaved:SetWordWrap(false)

    frame.status = NewText(footer, "", EDITOR_FONT_SIZE, C.muted, "RIGHT")
    frame.status:SetPoint("BOTTOMLEFT", frame.cancelButton, "BOTTOMRIGHT", 18, 5)
    frame.status:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", -7, 5)
    frame.status:SetHeight(20)
    frame.status:SetJustifyH("RIGHT")
    frame.status:SetWordWrap(false)


    frame.rangeText = NewText(footer, "", EDITOR_FONT_SIZE, C.muted, "RIGHT")
    frame.rangeText:Hide()
    frame.deleteHint = NewText(footer, "", EDITOR_FONT_SIZE, C.muted)
    frame.deleteHint:Hide()

    local capture = CreateFrame("Button", nil, frame)
    frame.captureFrame = capture
    capture:SetFrameStrata("TOOLTIP")
    if Skins and Skins.HandleButton then
        Skins:HandleButton(capture, true)
    elseif capture.SetTemplate then
        capture:SetTemplate("Default")
        if capture.StyleButton then capture:StyleButton() end
    end
    capture.label = NewText(capture, "Key / Click / Wheel", EDITOR_FONT_SIZE, C.text, "CENTER")
    capture.label:SetAllPoints(capture)
    capture:EnableMouse(true)
    if capture.SetHitRectInsets then capture:SetHitRectInsets(-4, -4, -2, -2) end
    capture:RegisterForClicks("AnyDown")
    capture:SetScript("OnClick", function(_, button)
        local key = CC:MouseButtonToKey(button)
        if key then CC:AcceptInlinePhysicalKey(key) end
    end)
    capture:SetScript("OnMouseWheel", function(_, delta) CC:AcceptInlinePhysicalKey(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
    capture:SetScript("OnLeave", function()
        if CC.editorFrame and CC.editorFrame.captureIndex then CC:StopInlineBindingCapture(true) end
    end)
    capture:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then CC:StopInlineBindingCapture(true) return end
        if key == "LALT" or key == "RALT" or key == "LCTRL" or key == "RCTRL" or key == "LSHIFT" or key == "RSHIFT" or key == "LMETA" or key == "RMETA" then return end
        CC:AcceptInlinePhysicalKey(key)
    end)
    capture:EnableKeyboard(false)
    capture:EnableMouseWheel(false)
    capture:Hide()

    self:BuildSpellPicker(frame)
    self:BuildMacroPicker(frame)
    self:BuildCustomMacroWriter(frame)

    frame:SetScript("OnSizeChanged", function()
        if frame._inLayout then return end
        frame._inLayout = true
        CC:LayoutEmbeddedEditor()
        frame._inLayout = nil
    end)
    frame:SetScript("OnShow", function()
        CC:ApplyEditorMedia()
        CC:BeginEditorSession(true)
        CC:ScanClickCastFrames()
        CC:LayoutEmbeddedEditor()
        CC:RefreshEditor()
        CC:EditorMessage("Edit inline. Use the X button to delete or restore a row; Save commits.", "normal")
    end)
    frame:SetScript("OnHide", function()
        CC:CloseSelectMenu()
        CC:CloseSpellPicker()
        CC:CloseMacroPicker()
        CC:CloseCustomMacroWriter()
        CC:StopInlineBindingCapture(false)
        frame.sessionActive = false
    end)

    frame:Hide()
    return frame
end

function CC:AttachEmbeddedEditor(parent)
    if not parent then return end
    local frame = self:BuildEditor(parent)
    if frame:GetParent() ~= parent then frame:SetParent(parent) end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    frame:Show()
    self:LayoutEmbeddedEditor()
end

function CC:DetachEmbeddedEditor(parent)
    local frame = self.editorFrame
    if not frame then return end
    if parent and frame:GetParent() ~= parent then return end
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(UIParent)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -4000, 4000)
    frame:SetWidth(1)
    frame:SetHeight(1)
end

local function GetElvConfigDialog()
    return (E.Libs and E.Libs.AceConfigDialog)
        or LibStub("AceConfigDialog-3.0-ElvUI", true)
        or LibStub("AceConfigDialog-3.0", true)
end

function CC:ShowEditor()


    local ACD = GetElvConfigDialog()
    local isOpen = ACD and ACD.OpenFrames and ACD.OpenFrames.ElvUI
    if not isOpen and E.ToggleOptionsUI then E:ToggleOptionsUI() end

    E:Delay(0.1, function()
        local dialog = GetElvConfigDialog()
        if dialog and E.Options and E.Options.args and E.Options.args.elvuiClickCast then
            pcall(function() dialog:SelectGroup("ElvUI", "elvuiClickCast") end)
        end
    end)
end

function CC:InitializeEditor()


end
