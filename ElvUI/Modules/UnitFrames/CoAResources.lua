local E = unpack(select(2, ...))
local UF = E:GetModule("UnitFrames")
-- Ordinary numeric 3.3.5 power pools. Runes remain on the existing rune widget.
local resources = {
 {key="mana", id=0, name="Mana", color={0.12,0.48,1}},
 {key="rage", id=1, name="Rage", color={0.95,0.18,0.16}},
 {key="focus", id=2, name="Focus", color={1,0.5,0.2}},
 {key="energy", id=3, name="Energy", color={1,0.85,0.15}},
 {key="happiness", id=4, name="Happiness", color={0.25,0.9,0.35}},
 {key="runic", id=6, name="Runic Power", color={0,0.82,1}}
}
UF.CoAResourceTypes = resources

local function ReadPower(id)
 local ok, value = pcall(UnitPower, "player", id)
 local maxOK, maximum = pcall(UnitPowerMax, "player", id)
 return ok and type(value)=="number" and math.max(0,value) or 0,
  maxOK and type(maximum)=="number" and math.max(0,maximum) or 0
end

-- Maxima alone are not evidence: custom clients may expose all stock pools.
-- Secondary Auto pools require an observed value change during this login.
function UF:CoAResourceVisible(resource, config, current, maximum, primary)
 local mode = config[resource.key]
 if mode == "HIDE" then return false end
 if mode == "SHOW" then return true end
 self.coaSeen = self.coaSeen or {}
 self.coaPrevious = self.coaPrevious or {}
 local previous = self.coaPrevious[resource.id]
 self.coaPrevious[resource.id] = current
 if primary == resource.id or (maximum > 0 and previous ~= nil and previous ~= current) then
  self.coaSeen[resource.id] = true
 end
 return self.coaSeen[resource.id] == true
end

function UF:Get_CoAResourceConfig()
 local db = E.db.unitframe.units.player
 if type(db.coaResources) ~= "table" then db.coaResources = {} end
 local c = db.coaResources
 local defaults = {enable=true,height=14,gap=2,offset=3,text=true,
  mana="AUTO",rage="AUTO",focus="AUTO",energy="AUTO",happiness="HIDE",runic="AUTO"}
 for k,v in pairs(defaults) do if c[k]==nil then c[k]=v end end
 if c.revision ~= 2 then
  self.coaSeen = {}; self.coaPrevious = {}
  local name, token = UnitClass("player")
  local identity = ((name or "")..(token or "")..(E.myclass or "")):upper():gsub("[^A-Z]", "")
  if identity:find("WITCHHUNTER",1,true) then
   for _,r in ipairs(resources) do c[r.key]="HIDE" end
   c.mana="SHOW"; c.rage="SHOW"
  end
  c.revision = 2
 end
 return c
end

local function NewBar(parent, resource)
 local bar = CreateFrame("StatusBar", nil, parent)
 bar:SetStatusBarTexture(E.media.blankTex)
 bar:SetStatusBarColor(unpack(resource.color))
 local bg = bar:CreateTexture(nil,"BACKGROUND")
 bg:SetAllPoints(); bg:SetTexture(0.04,0.04,0.04,0.95)
 bar.text = bar:CreateFontString(nil,"OVERLAY")
 bar.text:SetFont(E.media.normFont,11,"OUTLINE")
 bar.text:SetPoint("CENTER")
 return bar
end

function UF:Refresh_CoAResources(frame)
 local config = self:Get_CoAResourceConfig()
 local host = frame.CoAResources
 if not host then return end
 if not config or not config.enable then host:Hide(); return end
 local primary = UnitPowerType("player")
 local shown, signature = {}, tostring(frame:GetWidth())..":"..config.height..":"..config.gap..":"..config.offset
 for _, resource in ipairs(resources) do
  local bar = host.bars[resource.key]
  local current, maximum = ReadPower(resource.id)
  local visible = self:CoAResourceVisible(resource,config,current,maximum,primary)
  if visible then
   shown[#shown+1] = bar
   signature = signature..":"..resource.key
  end
  bar.wanted = visible
  bar:SetMinMaxValues(0,math.max(1,maximum,current))
  bar:SetValue(current)
  if config.text then
   if maximum > 0 then
    bar.text:SetFormattedText("%s  %d / %d",resource.name,current,maximum)
   else
    bar.text:SetText(resource.name.."  (not reported)")
   end
  else bar.text:SetText("") end
 end
 -- Defer child geometry/visibility changes while its secure owner is in combat.
 if not InCombatLockdown() and host.signature ~= signature then
  host:ClearAllPoints()
  host:SetPoint("TOPLEFT",frame,"BOTTOMLEFT",0,-config.offset)
  host:SetSize(frame:GetWidth(), math.max(1,#shown*(config.height+config.gap)-config.gap))
  for _, bar in pairs(host.bars) do bar:Hide() end
  for i, bar in ipairs(shown) do
   bar:ClearAllPoints()
   bar:SetPoint("TOPLEFT",host,"TOPLEFT",0,-(i-1)*(config.height+config.gap))
   bar:SetSize(frame:GetWidth(),config.height)
   bar:Show()
  end
  host.signature = signature
 end
 host:Show()
end

function UF:Configure_CoAResources(frame)
 if not frame.CoAResources then
  if InCombatLockdown() then return end
  local host = CreateFrame("Frame",nil,frame)
  frame.CoAResources = host
  host.bars = {}
  for _, resource in ipairs(resources) do host.bars[resource.key] = NewBar(host,resource) end
  local elapsed = 0
  host:SetScript("OnUpdate",function(_, delta)
   elapsed = elapsed + delta
   if elapsed < 0.1 then return end
   elapsed = 0
   UF:Refresh_CoAResources(frame)
  end)
 end
 frame.CoAResources.signature = nil
 self:Refresh_CoAResources(frame)
end

-- No AceGUI dependency: this panel remains usable if the main options fail.
function UF:Show_CoAResourcesPanel(showError)
 if InCombatLockdown() then E:Print("Open CoA resource controls after combat."); return end
 local panel = self.coaPanel
 if not panel then
  panel = CreateFrame("Frame","ElvUICoAPowerPanel",UIParent)
  self.coaPanel = panel
  panel:SetSize(400,430); panel:SetPoint("CENTER"); panel:SetFrameStrata("DIALOG")
  panel:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=24,insets={left=6,right=6,top=6,bottom=6}})
  panel:EnableMouse(true); panel:SetMovable(true); panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart",function(f) f:StartMoving() end)
  panel:SetScript("OnDragStop",function(f) f:StopMovingOrSizing() end)
  tinsert(UISpecialFrames,"ElvUICoAPowerPanel")
  local title = panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
  title:SetPoint("TOP",0,-20); title:SetText("CoA Player Resources")
  local close=CreateFrame("Button",nil,panel,"UIPanelCloseButton"); close:SetPoint("TOPRIGHT",-4,-4)
  local function Button(label,y,callback)
   local button=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
   button:SetSize(340,24);button:SetPoint("TOP",0,y);button:SetText(label)
   button:SetScript("OnClick",function() if InCombatLockdown() then return end;callback();UF:Show_CoAResourcesPanel() end)
   return button
  end
  panel.enable = Button("",-52,function() local c=UF:Get_CoAResourceConfig();c.enable=not c.enable;UF:CreateAndUpdateUF("player") end)
  Button("Witch Hunter: Mana + Rage only",-82,function()
   local c=UF:Get_CoAResourceConfig();c.enable=true
   for _,r in ipairs(resources) do c[r.key]="HIDE" end
   c.mana="SHOW";c.rage="SHOW";UF:CreateAndUpdateUF("player")
  end)
  panel.buttons={}
  for i,resource in ipairs(resources) do
   local r=resource
   panel.buttons[r.key]=Button("",-112-(i-1)*29,function()
    local c=UF:Get_CoAResourceConfig()
    c[r.key]=({AUTO="SHOW",SHOW="HIDE",HIDE="AUTO"})[c[r.key]] or "SHOW"
    UF:CreateAndUpdateUF("player")
   end)
  end
  local note=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  note:SetPoint("TOP",0,-293);note:SetWidth(345)
  note:SetText("Click each resource to cycle Auto / Show / Hide.\nAuto: primary pool or observed secondary activity.\nPress Escape to close. Settings follow your ElvUI profile.")
  panel.error=CreateFrame("EditBox",nil,panel,"InputBoxTemplate")
  panel.error:SetSize(325,24);panel.error:SetPoint("BOTTOM",0,35);panel.error:SetAutoFocus(false)
  panel.error:SetScript("OnEscapePressed",function(f) f:ClearFocus();panel:Hide() end)
  local errorNote=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  errorNote:SetPoint("BOTTOM",0,16);errorNote:SetText("Settings error: click above, Ctrl+A, Ctrl+C to copy")
 end
 local c=self:Get_CoAResourceConfig()
 panel.enable:SetText(c.enable and "Resource stack: ON" or "Resource stack: OFF")
 for _,r in ipairs(resources) do panel.buttons[r.key]:SetText(r.name..": "..c[r.key]) end
 panel.error:SetText(E.CoAOptionsError or "No settings error captured this session.")
 panel:Show()
 if showError then panel.error:SetFocus();panel.error:HighlightText() end
end
SLASH_ELVUICOAPOWER1 = "/coapower"
SlashCmdList.ELVUICOAPOWER = function(msg) UF:Show_CoAResourcesPanel(msg and msg:lower():find("error",1,true)) end
