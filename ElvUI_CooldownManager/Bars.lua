local E, L, V, P, G = unpack(ElvUI)
local CM = E:GetModule("CooldownManager")

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local pairs, ipairs, unpack, sort = pairs, ipairs, unpack, table.sort
local GameTooltip = GameTooltip
local GetTime = GetTime
local PlaySound = PlaySound
local PlaySoundFile = PlaySoundFile

CM.bars = {} -- [barKey] = barFrame

-- Masque support
local MSQ = LibStub and LibStub("Masque", true)
local masqueGroups = {}

local function GetMasqueGroup(barKey, barName)
	if not MSQ then return nil end
	if masqueGroups[barKey] then return masqueGroups[barKey] end
	local group = MSQ:Group("ElvUI Cooldown Manager", barName or barKey)
	masqueGroups[barKey] = group
	return group
end

-- ============================================================================
-- Safe ElvUI Mover helpers (prevents 'mover doesn't exist' LUA errors)
-- ============================================================================
function CM:DisableMover(barKey)
	local bar = self.bars[barKey]
	local moverName = bar and bar.moverName or ("ElvUI_CMBar_" .. barKey .. "_Mover")
	if E.CreatedMovers and E.CreatedMovers[moverName] then
		E:DisableMover(moverName)
	end
end

function CM:EnableMover(barKey)
	local bar = self.bars[barKey]
	local moverName = bar and bar.moverName or ("ElvUI_CMBar_" .. barKey .. "_Mover")
	if E.DisabledMovers and E.DisabledMovers[moverName] then
		E:EnableMover(moverName)
	end
end

-- ============================================================================
-- Sound helper
-- ============================================================================
local SOUND_PRESETS = {
	["ReadyCheck"]    = "Sound\\Interface\\ReadyCheck.wav",
	["LevelUp"]       = "Sound\\Interface\\LevelUp.wav",
	["RaidWarning"]   = "Sound\\Interface\\RaidWarning.wav",
	["FlagCaptured"]  = "Sound\\Spells\\PVPFlagTaken.wav",
	["AuctionOpen"]   = "Sound\\Interface\\AuctionWindowOpen.wav",
}

local function PlayReadySound(soundKey)
	local soundPath = SOUND_PRESETS[soundKey] or SOUND_PRESETS["ReadyCheck"]
	if soundPath then
		PlaySoundFile(soundPath)
	else
		PlaySound("ReadyCheck")
	end
end

-- ============================================================================
-- Action Bar Button Glow helper (flashes real action bar buttons)
-- ============================================================================
local function GlowRealActionButton(spellName, enable)
	if not spellName or spellName == "" then return end
	for i = 1, 120 do
		local actionType, id = GetActionInfo(i)
		if actionType == "spell" and id then
			local sName = GetSpellInfo(id)
			if sName and sName == spellName then
				local btn = _G["ElvUI_Bar1Button" .. i] or _G["ActionButton" .. i]
				if btn then
					if enable then
						if E.ShowOverlayGlow then E:ShowOverlayGlow(btn) end
					else
						if E.HideOverlayGlow then E:HideOverlayGlow(btn) end
					end
				end
			end
		end
	end
end

-- ============================================================================
-- ButtonGlow — compatible with ElvUI 3.3.5a
-- ============================================================================
local function ShowGlow(btn)
	if btn._glowing then return end
	btn._glowing = true
	if E.ShowOverlayGlow then
		E:ShowOverlayGlow(btn)
	else
		UIFrameFlash(btn, 0.25, 0.25, 1.5, false, 0, 0)
	end
end

local function HideGlow(btn)
	if not btn._glowing then return end
	btn._glowing = false
	if E.HideOverlayGlow then
		E:HideOverlayGlow(btn)
	end
	UIFrameFlashStop(btn)
end

-- ============================================================================
-- Color-coded timer (green → yellow → red)
-- ============================================================================
local function ApplyTimerColor(fs, rem)
	if     rem <= 2 then fs:SetTextColor(1,   0.2,  0.2,  1)  -- red
	elseif rem <= 5 then fs:SetTextColor(1,   0.85, 0,    1)  -- yellow
	else                 fs:SetTextColor(0.4, 1,    0.4,  1)  -- green
	end
end

local function ResetTimerColor(fs)
	fs:SetTextColor(1, 1, 1, 1)
end

-- ============================================================================
-- Helper: show/update duration text
-- ============================================================================
local function UpdateTimerText(timeFS, remaining, config)
	if not config.showDuration then
		timeFS:Hide()
		return
	end
	local threshold = config.durationThreshold or 0
	if remaining and remaining > 0 and (threshold == 0 or remaining <= threshold) then
		timeFS:SetText(CM:FormatTime(remaining))
		if config.colorDuration then
			ApplyTimerColor(timeFS, remaining)
		else
			ResetTimerColor(timeFS)
		end
		timeFS:Show()
	else
		timeFS:SetText("")
		timeFS:Hide()
	end
end

-- ============================================================================
-- Create a single tracker button (ICON mode)
-- ============================================================================
local function CreateBarButton(bar, index)
	local button = CreateFrame("Button", ("%s_Button%d"):format(bar:GetName(), index), bar)
	button:SetTemplate("Default")
	button:StyleButton()

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetInside()
	button.icon:SetTexCoord(unpack(E.TexCoords))

	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetInside()
	button.cooldown:SetReverse(true)

	-- Stacks
	button.count = button:CreateFontString(nil, "OVERLAY")
	button.count:FontTemplate(nil, 11, "OUTLINE")
	button.count:Point("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)

	-- Keybind text (top-left)
	button.keyText = button:CreateFontString(nil, "OVERLAY")
	button.keyText:FontTemplate(nil, 10, "OUTLINE")
	button.keyText:Point("TOPLEFT", button, "TOPLEFT", 1, -1)
	button.keyText:SetTextColor(0.9, 0.9, 0.9)

	-- Countdown timer (centre)
	button.time = button:CreateFontString(nil, "OVERLAY")
	button.time:FontTemplate(nil, 11, "OUTLINE")
	button.time:Point("CENTER", button, "CENTER", 0, 0)

	-- Spell name label (below)
	button.label = button:CreateFontString(nil, "OVERLAY")
	button.label:FontTemplate(nil, 9, "OUTLINE")
	button.label:Point("TOP", button, "BOTTOM", 0, -2)
	button.label:SetJustifyH("CENTER")
	button.label:SetWidth(48)
	button.label:Hide()

	button.barKey   = bar.key
	button._glowing = false
	button._wasOnCD = false

	-- Tooltip
	button:SetScript("OnEnter", function(self)
		local db = CM:GetBarConfig(self.barKey)
		if not db or not db.showTooltip or not self.spellID then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if db.showTooltipDesc then
			GameTooltip:SetSpellByID(self.spellID)
		else
			local s = CM:GetSpellData(self.spellID)
			if s then
				GameTooltip:AddLine(s.name, 1, 1, 1)
				if s.rank and s.rank ~= "" then
					GameTooltip:AddLine(s.rank, 0.7, 0.7, 0.7)
				end
			else
				GameTooltip:SetSpellByID(self.spellID)
			end
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	button:SetScript("OnClick", function(self, mouseBtn)
		if mouseBtn == "LeftButton" then
			local db = CM:GetBarConfig(self.barKey)
			if db and db.clickable and self.spellID then
				CM:CastTracked(self.spellID, self.isItem)
			end
		end
	end)

	button:Hide()

	local msqGroup = GetMasqueGroup(bar.key, bar.name)
	if msqGroup then
		msqGroup:AddButton(button)
	end

	return button
end

-- ============================================================================
-- Create a single tracker row (STATUSBAR mode)
-- ============================================================================
local function CreateBarStatusBar(bar, index)
	local row = CreateFrame("Frame", ("%s_SB%d"):format(bar:GetName(), index), bar)

	row.iconFrame = CreateFrame("Frame", nil, row)
	row.iconFrame:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
	row.icon:SetAllPoints()
	row.icon:SetTexCoord(unpack(E.TexCoords))

	row.statusBar = CreateFrame("StatusBar", nil, row)
	row.statusBar:SetPoint("TOPLEFT", row.iconFrame, "TOPRIGHT", 2, 0)
	row.statusBar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)

	local normTex = E.LSM:Fetch("statusbar", "ElvUI Norm")
	row.statusBar:SetStatusBarTexture(normTex)
	row.statusBar:SetMinMaxValues(0, 1)

	row.bg = row.statusBar:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetTexture(normTex)
	row.bg:SetVertexColor(0.1, 0.1, 0.1, 0.8)

	row.nameText = row.statusBar:CreateFontString(nil, "OVERLAY")
	row.nameText:Point("LEFT", row.statusBar, "LEFT", 4, 0)
	row.nameText:FontTemplate(nil, 11, "OUTLINE")

	row.timeText = row.statusBar:CreateFontString(nil, "OVERLAY")
	row.timeText:Point("RIGHT", row.statusBar, "RIGHT", -4, 0)
	row.timeText:FontTemplate(nil, 11, "OUTLINE")

	row.barKey = bar.key
	row:Hide()
	return row
end

-- ============================================================================
-- Construct and initialise bar container frame
-- ============================================================================
function CM:ConstructBar(barKey, config)
	if self.bars[barKey] then return self.bars[barKey] end

	local frameName = "ElvUI_CMBar_" .. barKey
	local moverName = frameName .. "_Mover"

	local holder = CreateFrame("Frame", frameName .. "_Holder", E.UIParent)
	holder:SetSize(config.iconSize * 6, config.iconSize)
	holder:Point("CENTER", E.UIParent, "CENTER", 0, 0)

	local bar = CreateFrame("Frame", frameName, E.UIParent)
	bar:SetClampedToScreen(true)
	bar:SetSize(config.iconSize * 6, config.iconSize)
	bar:Point("CENTER", holder, "CENTER", 0, 0)

	bar.key        = barKey
	bar.holder     = holder
	bar.moverName  = moverName
	bar.buttons    = {}
	bar.statusBars = {}

	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints(bar)
	bar.bg:SetTexture([[Interface\ChatFrame\ChatFrameBackground]])
	bar.bg:Hide()

	local moverTitle = config.name or ("Bar " .. barKey)
	E:CreateMover(holder, moverName, moverTitle, nil, nil, nil, "ALL,SOLO", nil, "elvuiPlugins,cooldownManager")

	-- Throttled OnUpdate (~12 fps)
	bar.elapsed = 0
	bar:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = self.elapsed + elapsed
		if self.elapsed < 0.08 then return end
		self.elapsed = 0

		local db = CM:GetBarConfig(self.key)
		if not db then return end

		if db.displayStyle == "STATUSBAR" then
			for _, sb in ipairs(self.statusBars) do
				if sb:IsShown() and sb.expirationTime and sb.expirationTime > 0 then
					local rem = sb.expirationTime - GetTime()
					if rem < 0 then rem = 0 end
					if sb.duration and sb.duration > 0 then
						sb.statusBar:SetValue(rem / sb.duration)
					end
					UpdateTimerText(sb.timeText, rem, db)
				end
			end
		else
			for _, btn in ipairs(self.buttons) do
				if btn:IsShown() and btn.expirationTime and btn.expirationTime > 0 then
					local rem = btn.expirationTime - GetTime()
					if rem < 0 then rem = 0 end
					UpdateTimerText(btn.time, rem, db)
				end
			end
		end
	end)

	self.bars[barKey] = bar
	return bar
end

-- ============================================================================
-- Retrieve bar config
-- ============================================================================
function CM:GetBarConfig(barKey)
	if not self.db then return nil end
	if self.db.bars       and self.db.bars[barKey]      then return self.db.bars[barKey]      end
	if self.db.customBars and self.db.customBars[barKey] then return self.db.customBars[barKey] end
	return nil
end

-- ============================================================================
-- Gather spell data for a bar
-- ============================================================================
local tempEntries = {}

local function CollectBarEntries(config, CM_ref)
	for i = #tempEntries, 1, -1 do tempEntries[i] = nil end

	for spellID, enabled in pairs(config.spells) do
		if enabled then
			local spellData = CM_ref:GetSpellData(spellID)
			if spellData then
				local shouldShow = false
				local start, duration, onCooldown, remaining = 0, 0, false, 0
				local expirationTime, hasBuff, stackCount = 0, false, 0

				if config.trackType == "BUFF" then
					local bActive, count, dur, exp, rem = CM_ref:GetPlayerBuff(spellData.id, spellData.name)
					hasBuff = bActive
					if hasBuff then
						shouldShow     = true
						start          = exp - dur
						duration       = dur
						remaining      = rem
						stackCount     = count
						expirationTime = exp
					elseif config.showReady then
						shouldShow = true
					end
				else
					local s, d, onCD, rem = CM_ref:GetCooldownInfo(spellData.id, config.showGCD)
					start, duration, onCooldown, remaining = s, d, onCD, rem
					if onCooldown then
						shouldShow     = true
						expirationTime = start + duration
					elseif config.showReady then
						shouldShow = true
					end
				end

				if shouldShow then
					local keybind = ""
					if config.showKeybind then
						keybind = CM_ref:GetSpellKeybind(spellData.name)
					end

					tempEntries[#tempEntries + 1] = {
						spellData      = spellData,
						start          = start,
						duration       = duration,
						onCooldown     = onCooldown,
						remaining      = remaining,
						expirationTime = expirationTime,
						hasBuff        = hasBuff,
						stackCount     = stackCount,
						keybind        = keybind,
					}
				end
			end
		end
	end

	if config.sortByRemaining then
		sort(tempEntries, function(a, b)
			local ra = (a.remaining > 0) and a.remaining or 99999
			local rb = (b.remaining > 0) and b.remaining or 99999
			return ra < rb
		end)
	end

	return tempEntries
end

-- ============================================================================
-- Update a bar
-- ============================================================================
function CM:UpdateBar(barKey)
	local bar    = self.bars[barKey]
	local config = self:GetBarConfig(barKey)
	if not bar or not config then return end

	-- Disabled bar state
	if not self.db.enable or not config.enable then
		bar:Hide()
		self:DisableMover(barKey)
		return
	else
		-- Only enable mover if NOT anchored
		if not config.attachTo or config.attachTo == "NONE" then
			self:EnableMover(barKey)
		end
	end

	-- Combat-only
	if config.showOnlyCombat and not InCombatLockdown() then
		bar:Hide()
		return
	end

	local font        = E.LSM:Fetch("font", self.db.font or "Expressway")
	local fontSize    = self.db.fontSize or 11
	local fontOutline = self.db.fontOutline or "OUTLINE"

	local entries  = CollectBarEntries(config, self)
	local maxIcons = config.maxIcons or 12
	local visible  = math.min(#entries, maxIcons)

	local isStatusBar = (config.displayStyle == "STATUSBAR")

	-- Hide non-active mode components
	if isStatusBar then
		for _, btn in ipairs(bar.buttons) do btn:Hide() end
	else
		for _, sb in ipairs(bar.statusBars) do sb:Hide() end
	end

	-- ── Render Visible Items ──────────────────────────────────────────────────
	for i = 1, visible do
		local e = entries[i]

		if isStatusBar then
			local sb = bar.statusBars[i]
			if not sb then
				sb = CreateBarStatusBar(bar, i)
				bar.statusBars[i] = sb
			end

			local bWidth  = config.barWidth or 180
			local bHeight = config.barHeight or 20
			sb:SetSize(bWidth, bHeight)
			sb.iconFrame:SetSize(bHeight, bHeight)
			sb.icon:SetTexture(e.spellData.icon)

			local sbTexture = E.LSM:Fetch("statusbar", config.statusBarTexture or "ElvUI Norm")
			sb.statusBar:SetStatusBarTexture(sbTexture)
			sb.bg:SetTexture(sbTexture)

			sb.nameText:FontTemplate(font, fontSize, fontOutline)
			sb.nameText:SetText(e.spellData.name)

			sb.timeText:FontTemplate(font, fontSize, fontOutline)
			sb.duration       = e.duration
			sb.expirationTime = e.expirationTime

			if e.duration > 0 and e.remaining > 0 then
				sb.statusBar:SetValue(e.remaining / e.duration)
				UpdateTimerText(sb.timeText, e.remaining, config)
			else
				sb.statusBar:SetValue(0)
				sb.timeText:SetText("")
			end

			local isNowOnCD = (e.onCooldown or not e.hasBuff)
			if config.desaturateOnCD and isNowOnCD then
				sb.icon:SetDesaturated(true)
			else
				sb.icon:SetDesaturated(false)
			end

			sb:Show()
		else
			-- ICON mode
			local btn = bar.buttons[i]
			if not btn then
				btn = CreateBarButton(bar, i)
				bar.buttons[i] = btn
			end

			local iconSize = config.iconSize or 32
			local scale    = config.iconScale or 1.0
			local effSize  = iconSize * scale
			btn:SetSize(effSize, effSize)

			btn.barKey         = bar.key
			btn.spellID        = e.spellData.id
			btn.isItem         = e.spellData.isItem
			btn.expirationTime = e.expirationTime
			btn.icon:SetTexture(e.spellData.icon)

			btn.count:FontTemplate(font, fontSize, fontOutline)
			btn.time:FontTemplate(font, fontSize, fontOutline)

			-- Keybind Text
			if config.showKeybind and e.keybind ~= "" then
				btn.keyText:FontTemplate(font, config.keybindFontSize or 10, fontOutline)
				btn.keyText:SetText(e.keybind)
				btn.keyText:Show()
			else
				btn.keyText:Hide()
			end

			-- Stack Count
			if config.showCount and e.stackCount and e.stackCount > 1 then
				btn.count:SetText(e.stackCount)
				btn.count:Show()
			else
				btn.count:Hide()
			end

			-- Spell Label
			if config.showLabel then
				local lfs = config.labelFontSize or 9
				btn.label:FontTemplate(font, lfs, fontOutline)
				btn.label:SetText(e.spellData.name)
				btn.label:Show()
			else
				btn.label:Hide()
			end

			-- Swipe + Timer
			if e.duration > 0 and (e.onCooldown or config.trackType == "BUFF") then
				if config.showSwipe then
					btn.cooldown:SetCooldown(e.start, e.duration)
					btn.cooldown:Show()
				else
					btn.cooldown:Hide()
				end
				UpdateTimerText(btn.time, e.remaining, config)
			else
				btn.cooldown:Hide()
				btn.time:SetText("")
				btn.time:Hide()
			end

			-- Desaturation & Alpha
			local readyAlpha    = config.readyAlpha    or 1.0
			local cdAlpha       = config.cooldownAlpha or 0.8
			local inactAlpha    = config.inactiveAlpha or 0.4
			local isNowOnCD     = false

			if config.trackType == "BUFF" then
				if e.hasBuff then
					btn.icon:SetDesaturated(false)
					btn:SetAlpha(readyAlpha)
				else
					btn.icon:SetDesaturated(config.desaturateOnCD and true or false)
					btn:SetAlpha(inactAlpha)
					isNowOnCD = true
				end
			else
				if e.onCooldown then
					btn.icon:SetDesaturated(config.desaturateOnCD and true or false)
					btn:SetAlpha(cdAlpha)
					isNowOnCD = true
				else
					btn.icon:SetDesaturated(false)
					btn:SetAlpha(readyAlpha)
				end
			end

			if config.overrideAlpha then
				btn:SetAlpha(config.barAlpha or 1.0)
			end

			-- Glow transition & audio
			if btn._wasOnCD and not isNowOnCD then
				if config.glowOnReady then
					ShowGlow(btn)
					self:ScheduleTimer(function() HideGlow(btn) end, 1.5)
				end
				if config.glowActionButton then
					GlowRealActionButton(e.spellData.name, true)
					self:ScheduleTimer(function() GlowRealActionButton(e.spellData.name, false) end, 1.5)
				end
				if config.playSoundOnReady then
					PlayReadySound(config.readySound)
				end
			elseif isNowOnCD then
				HideGlow(btn)
			end
			btn._wasOnCD = isNowOnCD

			btn:Show()
		end
	end

	-- Hide remaining slots
	if isStatusBar then
		for i = visible + 1, #bar.statusBars do bar.statusBars[i]:Hide() end
	else
		for i = visible + 1, #bar.buttons do bar.buttons[i]:Hide() end
	end

	if visible == 0 and config.hideEmpty and not E.MoveMode then
		bar:Hide()
		return
	end

	bar:Show()

	-- Background
	if config.showBackground then
		bar.bg:SetVertexColor(config.bgR or 0, config.bgG or 0, config.bgB or 0, config.bgA or 0.5)
		bar.bg:Show()
	else
		bar.bg:Hide()
	end

	-- ── Dynamic Sizing & Positioning ──────────────────────────────────────────
	local spacing    = config.spacing or 4
	local isVertical = (config.orientation == "VERTICAL")
	local growth     = config.growthDirection or "RIGHT"
	local perLine    = config.perLine or 0

	local barW, barH = 0, 0

	if isStatusBar then
		local bWidth  = config.barWidth or 180
		local bHeight = config.barHeight or 20
		barW = bWidth
		barH = visible > 0 and (visible * (bHeight + spacing) - spacing) or bHeight

		bar:SetSize(barW, barH)
		bar.holder:SetSize(barW, barH)

		for i = 1, visible do
			local sb     = bar.statusBars[i]
			local prevSB = bar.statusBars[i - 1]
			sb:ClearAllPoints()
			if i == 1 then
				sb:Point("TOPLEFT", bar, "TOPLEFT", 0, 0)
			else
				sb:Point("TOPLEFT", prevSB, "BOTTOMLEFT", 0, -spacing)
			end
		end
	else
		-- ICON mode with wrapping support
		local iconSize = config.iconSize or 32
		local scale    = config.iconScale or 1.0
		local effSize  = iconSize * scale
		local labelH   = (config.showLabel and ((config.labelFontSize or 9) + 3)) or 0
		local cellH    = effSize + labelH

		local cols, rows = visible, 1
		if perLine > 0 and visible > 0 then
			cols = math.min(visible, perLine)
			rows = math.ceil(visible / perLine)
		end

		if not isVertical then
			barW = cols > 0 and (cols * (effSize + spacing) - spacing) or effSize
			barH = rows * (cellH + spacing) - spacing
		else
			barW = rows * (effSize + spacing) - spacing
			barH = cols > 0 and (cols * (cellH + spacing) - spacing) or cellH
		end

		bar:SetSize(barW, barH)
		bar.holder:SetSize(barW, barH)

		for i = 1, visible do
			local btn = bar.buttons[i]
			btn:ClearAllPoints()

			local col, row
			if perLine > 0 then
				col = (i - 1) % perLine
				row = math.floor((i - 1) / perLine)
			else
				col = i - 1
				row = 0
			end

			local xOff, yOff
			if not isVertical then
				if growth == "LEFT" then
					xOff = -col * (effSize + spacing)
				else
					xOff = col * (effSize + spacing)
				end
				yOff = -row * (cellH + spacing)

				if growth == "LEFT" then
					btn:Point("TOPRIGHT", bar, "TOPRIGHT", xOff, yOff)
				else
					btn:Point("TOPLEFT", bar, "TOPLEFT", xOff, yOff)
				end
			else
				if growth == "UP" then
					yOff = col * (cellH + spacing)
				else
					yOff = -col * (cellH + spacing)
				end
				xOff = row * (effSize + spacing)

				if growth == "UP" then
					btn:Point("BOTTOMLEFT", bar, "BOTTOMLEFT", xOff, yOff)
				else
					btn:Point("TOPLEFT", bar, "TOPLEFT", xOff, yOff)
				end
			end
		end
	end

	-- ── Anchoring ─────────────────────────────────────────────────────────────
	if config.attachTo and config.attachTo ~= "NONE" and self.bars[config.attachTo] then
		self:DisableMover(barKey)
		bar:ClearAllPoints()

		local parent = self.bars[config.attachTo]
		local pt, rpt = config.attachPoint or "TOPLEFT", config.anchorPoint or "BOTTOMLEFT"
		local x, y   = config.xOffset or 0, config.yOffset or -4
		local dir     = config.attachDirection or "BELOW"

		if     dir == "ABOVE" then pt="BOTTOM"; rpt="TOP";    y = (y~=0 and y) or 4;  x = x or 0
		elseif dir == "BELOW" then pt="TOP";    rpt="BOTTOM"; y = (y~=0 and y) or -4; x = x or 0
		elseif dir == "LEFT"  then pt="RIGHT";  rpt="LEFT";   x = (x~=0 and x) or -4; y = y or 0
		elseif dir == "RIGHT" then pt="LEFT";   rpt="RIGHT";  x = (x~=0 and x) or 4;  y = y or 0
		end
		bar:Point(pt, parent, rpt, x, y)
	else
		bar:ClearAllPoints()
		bar:Point("CENTER", bar.holder, "CENTER", 0, 0)
		self:EnableMover(barKey)
	end
end

-- ============================================================================
-- Update all bars
-- ============================================================================
function CM:UpdateAllBars()
	if not self.db or not self.db.enable then
		for _, bar in pairs(self.bars) do bar:Hide() end
		return
	end

	local all = {}
	if self.db.bars       then for k in pairs(self.db.bars)       do all[k] = true end end
	if self.db.customBars then for k in pairs(self.db.customBars) do all[k] = true end end

	for k in pairs(all) do
		local cfg = self:GetBarConfig(k)
		if not (cfg and cfg.attachTo and cfg.attachTo ~= "NONE") then
			self:UpdateBar(k)
		end
	end

	for k in pairs(all) do
		local cfg = self:GetBarConfig(k)
		if cfg and cfg.attachTo and cfg.attachTo ~= "NONE" then
			self:UpdateBar(k)
		end
	end
end
