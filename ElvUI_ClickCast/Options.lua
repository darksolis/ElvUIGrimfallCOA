local E, L, V, P, G = unpack(ElvUI)
local CC = E:GetModule("ElvUIClickCast")
local EP = LibStub("LibElvUIPlugin-1.0")

local HOST_WIDGET = "ElvUIClickCastEditorHost"
local HOST_WIDGET_VERSION = 5

local CLICKCAST_MIN_CONFIG_WIDTH = 1000
local CLICKCAST_MIN_CONFIG_HEIGHT = 780
local CLICKCAST_MIN_HOST_HEIGHT = 600
local STOCK_ELVUI_MIN_WIDTH = 400
local STOCK_ELVUI_MIN_HEIGHT = 200

local max, abs = math.max, math.abs
local hostResizeOwners = setmetatable({}, {__mode = "k"})
local hostResizeHooked = setmetatable({}, {__mode = "k"})

local function GetElvConfigWindow()
    local dialog = E.Libs and E.Libs.AceConfigDialog
    local window = dialog and dialog.OpenFrames and dialog.OpenFrames.ElvUI
    return dialog, window, window and window.frame
end

local function AcquireClickCastWindowMinimum()
    local dialog, window, raw = GetElvConfigWindow()
    if not raw then return end


    if raw.SetMinResize then raw:SetMinResize(CLICKCAST_MIN_CONFIG_WIDTH, CLICKCAST_MIN_CONFIG_HEIGHT) end

    local width = raw.GetWidth and raw:GetWidth() or 0
    local height = raw.GetHeight and raw:GetHeight() or 0
    local wantedWidth = max(width or 0, CLICKCAST_MIN_CONFIG_WIDTH)
    local wantedHeight = max(height or 0, CLICKCAST_MIN_CONFIG_HEIGHT)

    if dialog and dialog.GetStatusTable then
        local status = dialog:GetStatusTable("ElvUI")
        if status then
            status.width = max(tonumber(status.width) or 0, wantedWidth)
            status.height = max(tonumber(status.height) or 0, wantedHeight)
        end
    end

    if window.SetWidth and width < wantedWidth then window:SetWidth(wantedWidth) end
    if window.SetHeight and height < wantedHeight then window:SetHeight(wantedHeight) end
end

local function ReleaseClickCastWindowMinimum()
    local _, _, raw = GetElvConfigWindow()
    if raw and raw.SetMinResize then
        raw:SetMinResize(STOCK_ELVUI_MIN_WIDTH, STOCK_ELVUI_MIN_HEIGHT)
    end
end

local function SyncEditorHostHeight(widget)
    local parent = widget and widget.parent
    local parentFrame = parent and parent.frame
    if not parentFrame then return end

    local available = (parentFrame.GetHeight and parentFrame:GetHeight() or 0) - 4
    local wanted = max(CLICKCAST_MIN_HOST_HEIGHT, available)
    local current = widget.frame and widget.frame.GetHeight and widget.frame:GetHeight() or 0
    if abs((current or 0) - wanted) > 0.5 then
        widget:SetHeight(wanted)
    end
end

local function BindEditorHostResize(widget, parent)
    local parentFrame = parent and parent.frame
    if not parentFrame then return end

    hostResizeOwners[parentFrame] = widget
    if not hostResizeHooked[parentFrame] and parentFrame.HookScript then
        hostResizeHooked[parentFrame] = true
        parentFrame:HookScript("OnSizeChanged", function(frame)
            local active = hostResizeOwners[frame]
            if not active or not active.parent or active.parent.frame ~= frame then return end
            SyncEditorHostHeight(active)
            if active.parent.DoLayout then active.parent:DoLayout() end
        end)
    end

    SyncEditorHostHeight(widget)
end

local function GetElvAceGUI()
    return (E.Libs and E.Libs.AceGUI) or LibStub("AceGUI-3.0", true)
end

local function RegisterEditorHostWidget()
    local AceGUI = GetElvAceGUI()
    if not AceGUI then return false end
    if CC.editorHostWidgetRegistered then return true end

    local function Constructor()
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:Hide()

        local widget = {
            type = HOST_WIDGET,
            frame = frame,
        }


        function widget:SetText() end
        function widget:SetFontObject() end

        function widget:SetParent(parent)
            self.base.SetParent(self, parent)
            BindEditorHostResize(self, parent)
        end

        function widget:OnAcquire()
            self:SetFullWidth(true)
            self:SetHeight(CLICKCAST_MIN_HOST_HEIGHT)
            AcquireClickCastWindowMinimum()
            frame:Show()
            CC:AttachEmbeddedEditor(frame)
        end

        function widget:OnRelease()
            local parentFrame = self.parent and self.parent.frame
            if parentFrame and hostResizeOwners[parentFrame] == self then
                hostResizeOwners[parentFrame] = nil
            end
            CC:DetachEmbeddedEditor(frame)
            ReleaseClickCastWindowMinimum()
            frame:Hide()
        end

        return AceGUI:RegisterAsWidget(widget)
    end

    AceGUI:RegisterWidgetType(HOST_WIDGET, Constructor, HOST_WIDGET_VERSION)
    CC.editorHostWidgetRegistered = true
    return true
end

function CC:InsertOptions()
    if not E.Options or not E.Options.args then return end
    if not RegisterEditorHostWidget() then
        self:Print("ClickCast editor host could not register because ElvUI AceGUI is unavailable.")
        return
    end

    E.Options.args.elvuiClickCast = {
        type = "group",
        name = "Click Cast",
        order = 100,
        args = {
            editorHost = {
                order = 1,
                type = "description",
                name = "",
                width = "full",
                dialogControl = HOST_WIDGET,
            },
        },
    }
end

function CC:InitializeOptions()
    EP:RegisterPlugin(self.addonName, function() CC:InsertOptions() end)
end
