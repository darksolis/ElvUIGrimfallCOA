local E, L, V, P, G = unpack(ElvUI)
local NP = E:GetModule('NamePlates')
local UF = E:GetModule('UnitFrames')
local LSM = E.Libs.LSM

local ipairs = ipairs
local unpack = unpack
local UnitPlayerControlled = UnitPlayerControlled
local UnitClass = UnitClass
local UnitReaction = UnitReaction
local UnitIsConnected = UnitIsConnected
local CreateFrame = CreateFrame
local UnitIsTapped = UnitIsTapped
local UnitIsTappedByPlayer = UnitIsTappedByPlayer
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsPlayer = UnitIsPlayer
local UnitBuff = UnitBuff
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax

local ElvUI_ShieldScannerTooltip = _G.ElvUI_ShieldScannerTooltip or CreateFrame("GameTooltip", "ElvUI_ShieldScannerTooltip", nil, "GameTooltipTemplate")

local Settings = _G.ElvUI_AbsorbSettings or {
	Colors = {
		{r = 0.3, g = 0.7, b = 1.0, a = 0.6},
		{r = 0.5, g = 0.5, b = 1.0, a = 0.6},
		{r = 0.2, g = 0.8, b = 0.8, a = 0.6},
		{r = 0.6, g = 0.4, b = 0.9, a = 0.6},
		{r = 0.4, g = 0.7, b = 0.5, a = 0.6},
	},
	IconSize = 12,
	MinIconWidth = 18,
	SeparatorWidth = 1.5,
	SeparatorColor = {r = 1, g = 1, b = 1, a = 0.6},
}

local KNOWN_SHIELDS = {
	["Power Word: Shield"] = true,
	["Void Shield"] = true,
	["Forbidden Ritual"] = true,
	["Hateforged Barrier"] = true,
	["Phoenix Shield"] = true,
	["Sacred Shield"] = true,
	["Ice Barrier"] = true,
	["Mana Shield"] = true,
	["Anti-Magic Shell"] = true,
	["Savage Defense"] = true,
	["Divine Aegis"] = true,
	["Blood Shield"] = true,
}

local shieldCache = {}

local function ParseAbsorbFromLine(lineText)
	local lowerText = string.lower(lineText)
	if not (string.find(lowerText, "absorb", 1, true) or string.find(lowerText, "protect", 1, true) or string.find(lowerText, "damage", 1, true)) then
		return nil
	end
	
	local valStr = string.match(lowerText, "absorb[a-z]*%s+up%s+to%s+(%d[%d%.,]*)")
		or string.match(lowerText, "absorb[a-z]*%s+a%s+maximum%s+of%s+(%d[%d%.,]*)")
		or string.match(lowerText, "absorb[a-z]*%s+(%d[%d%.,]*)")
		or string.match(lowerText, "absorbing%s+up%s+to%s+(%d[%d%.,]*)")
		or string.match(lowerText, "absorbing%s+(%d[%d%.,]*)")
	if valStr then
		valStr = string.gsub(valStr, "[%,%.%s]", "")
		local val = tonumber(valStr)
		if val and val > 0 then return val end
	end

	for numStr, suffix in string.gmatch(lowerText, "(%d[%d%.,]*)%s+([%a%s%,]*)damage") do
		local isPercent = false
		local startPos = string.find(lowerText, numStr, 1, true)
		if startPos and startPos > 1 then
			local prevChar = string.sub(lowerText, startPos - 1, startPos - 1)
			if prevChar == "%" then isPercent = true end
		end
		if not isPercent then
			numStr = string.gsub(numStr, "[%,%.%s]", "")
			local val = tonumber(numStr)
			if val and val > 0 then return val end
		end
	end

	for numStr in string.gmatch(lowerText, "(%d[%d%.,]*)") do
		local startPos = string.find(lowerText, numStr, 1, true)
		local prevChar = startPos and startPos > 1 and string.sub(lowerText, startPos - 1, startPos - 1)
		local following = string.sub(lowerText, startPos + string.len(numStr))
		local isTime = string.find(following, "^%s*sec") or string.find(following, "^%s*min") or string.find(following, "^%s*hour")
		local isPercent = (prevChar == "%") or string.find(following, "^%s*%%")
		
		if not isPercent and not isTime then
			numStr = string.gsub(numStr, "[%,%.%s]", "")
			local val = tonumber(numStr)
			if val and val > 1 then
				return val
			end
		end
	end

	return nil
end

local unitShieldCache = {}

local function GetUnitShields(unit, personalOnly)
	local totalNativeAbsorb = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0
	local cached = unitShieldCache[unit]
	
	local cacheHit = false
	if cached and cached.personalOnly == personalOnly and cached.totalNativeAbsorb == totalNativeAbsorb then
		cacheHit = true
		local idx = 1
		while true do
			local name, _, _, count, _, _, expirationTime = UnitBuff(unit, idx)
			local cachedBuff = cached.buffs[idx]
			if not name then
				if cachedBuff ~= nil then
					cacheHit = false
				end
				break
			end
			if not cachedBuff or cachedBuff.name ~= name or cachedBuff.count ~= count or cachedBuff.expirationTime ~= expirationTime then
				cacheHit = false
				break
			end
			idx = idx + 1
		end
	end
	
	if cacheHit then
		return cached.shields
	end

	local shields = {}
	local unparsedShields = {}
	local totalParsed = 0
	
	local i = 1
	while true do
		local name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId = UnitBuff(unit, i)
		if not name then break end
		
		local isPlayerCaster = (unitCaster == "player" or unitCaster == "vehicle" or unitCaster == "pet")
		if unitCaster == nil and (UnitIsUnit(unit, "player") or unit == "player" or UnitIsUnit(unit, "pet") or unit == "pet" or UnitIsUnit(unit, "vehicle") or unit == "vehicle") then
			isPlayerCaster = true
		end
		if not personalOnly or isPlayerCaster then
			local absorbAmount = 0
			if name == "Arcane Barrier" or spellId == 1112478 then
				local caster = unitCaster or "player"
				local maxMana = UnitManaMax(caster) or 0
				absorbAmount = math.floor(maxMana * 0.10)
				if absorbAmount <= 0 then
					absorbAmount = 1000
				end
				table.insert(shields, {
					name = name,
					icon = icon,
					spellId = spellId,
					amount = absorbAmount,
					isPlayer = isPlayerCaster
				})
				totalParsed = totalParsed + absorbAmount
			else
				local isShield = shieldCache[name]
				if isShield == nil then
					if KNOWN_SHIELDS[name] 
						or string.find(name, "Shield", 1, true) 
						or string.find(name, "Barrier", 1, true) 
						or string.find(name, "Ward", 1, true) 
						or string.find(name, "Shell", 1, true) 
						or string.find(name, "Absorb", 1, true)
						or string.find(name, "Aegis", 1, true)
						or string.find(name, "Bulwark", 1, true)
						or string.find(name, "Cocoon", 1, true)
						or string.find(name, "Carapace", 1, true)
						or string.find(name, "Wall", 1, true)
						or string.find(name, "Shroud", 1, true)
						or string.find(name, "Guard", 1, true)
					then
						shieldCache[name] = true
						isShield = true
					end
				end
				
				if isShield ~= false then
					ElvUI_ShieldScannerTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
					ElvUI_ShieldScannerTooltip:ClearLines()
					ElvUI_ShieldScannerTooltip:SetUnitBuff(unit, i)
					
					local firstLine = _G["ElvUI_ShieldScannerTooltipTextLeft1"]:GetText()
					local secondLine = _G["ElvUI_ShieldScannerTooltipTextLeft2"]:GetText()
					local tooltipLoaded = (firstLine == name and secondLine and secondLine ~= "")
					
					if tooltipLoaded then
						local val = nil
						for j = 1, ElvUI_ShieldScannerTooltip:NumLines() do
							local lineText = _G["ElvUI_ShieldScannerTooltipTextLeft" .. j]:GetText()
							if lineText then
								val = ParseAbsorbFromLine(lineText)
								if val then
									break
								end
							end
						end
						if val then
							absorbAmount = val
						end
						if isShield == nil then
							shieldCache[name] = (val ~= nil)
							isShield = (val ~= nil)
						end
					end
				end

				if isShield == true or KNOWN_SHIELDS[name] then
					local shieldInfo = {
						name = name,
						icon = icon,
						spellId = spellId,
						amount = absorbAmount,
						isPlayer = isPlayerCaster
					}
					if absorbAmount > 0 then
						table.insert(shields, shieldInfo)
						totalParsed = totalParsed + absorbAmount
					else
						table.insert(unparsedShields, shieldInfo)
					end
				end
			end
		end
		i = i + 1
	end

	if totalNativeAbsorb > totalParsed and #unparsedShields > 0 then
		local unassigned = totalNativeAbsorb - totalParsed
		local share = math.floor(unassigned / #unparsedShields)
		if share > 0 then
			for _, s in ipairs(unparsedShields) do
				s.amount = share
				table.insert(shields, s)
			end
			totalParsed = totalParsed + unassigned
		end
	end

	if not personalOnly and totalNativeAbsorb > totalParsed then
		local remaining = totalNativeAbsorb - totalParsed
		if #shields > 0 then
			shields[#shields].amount = shields[#shields].amount + remaining
		else
			table.insert(shields, {
				name = "Shield",
				icon = "Interface\\Icons\\spell_holy_powerwordshield",
				spellId = nil,
				amount = remaining,
				isFallback = true,
				isPlayer = (UnitIsUnit(unit, "player") or unit == "player" or UnitIsUnit(unit, "pet") or unit == "pet" or UnitIsUnit(unit, "vehicle") or unit == "vehicle")
			})
		end
	end

	local buffs = {}
	local idx = 1
	while true do
		local name, _, _, count, _, _, expirationTime = UnitBuff(unit, idx)
		if not name then break end
		buffs[idx] = {
			name = name,
			count = count or 0,
			expirationTime = expirationTime or 0
		}
		idx = idx + 1
	end

	unitShieldCache[unit] = {
		personalOnly = personalOnly,
		totalNativeAbsorb = totalNativeAbsorb,
		buffs = buffs,
		shields = shields
	}

	return shields
end

function NP:Health_UpdateColor(_, unit)
	if not unit or self.unit ~= unit then return end
	local element = self.Health

	local r, g, b, t
	if element.colorDisconnected and not UnitIsConnected(unit) then
		t = self.colors.disconnected
	elseif (element.colorClass and self.isPlayer) or (element.colorClassNPC and not self.isPlayer) or (element.colorClassPet and UnitPlayerControlled(unit) and not self.isPlayer) then
		local _, class = UnitClass(unit)
		t = self.colors.class[class]
	elseif element.colorReaction and UnitReaction(unit, 'player') then
		local reaction = UnitReaction(unit, 'player')
		t = NP.db.colors.reactions[reaction == 4 and 'neutral' or reaction <= 3 and 'bad' or 'good']
	elseif element.colorSmooth then
		r, g, b = self:ColorGradient(element.cur or 1, element.max or 1, unpack(element.smoothGradient or self.colors.smooth))
	elseif element.colorHealth then
		t = NP.db.colors.health
	end

	if t then
		r, g, b = t.r, t.g, t.b
		element.r, element.g, element.b = r, g, b -- save these for the style filter to switch back
	end

	local db = NP:PlateDB(self)
	if db.greyTappedTargets and UnitIsTapped(unit) and not UnitIsTappedByPlayer(unit) and not UnitIsPlayer(unit) and not UnitIsDeadOrGhost(unit) then
		r, g, b = 0.5, 0.5, 0.5
		element.r, element.g, element.b = r, g, b
	end

	local sf = NP:StyleFilterChanges(self)
	if sf.HealthColor then
		r, g, b = sf.HealthColor.r, sf.HealthColor.g, sf.HealthColor.b
	end

	if b then
		element:SetStatusBarColor(r, g, b)

		if element.bg then
			element.bg:SetVertexColor(r * NP.multiplier, g * NP.multiplier, b * NP.multiplier)
		end
	end

	if element.PostUpdateColor then
		element:PostUpdateColor(unit, r, g, b)
	end
end

function NP:Construct_Health(nameplate)
	local Health = CreateFrame('StatusBar', nameplate:GetName()..'Health', nameplate)
	Health:SetParent(nameplate)
	Health:CreateBackdrop('Transparent', nil, nil, nil, nil, true, true)
	Health:SetStatusBarTexture(LSM:Fetch('statusbar', NP.db.statusbar))
	Health.considerSelectionInCombatHostile = true
	Health.UpdateColor = NP.Health_UpdateColor

	NP.StatusBars[Health] = true

	local statusBarTexture = Health:GetStatusBarTexture()
	local healthFlashTexture = Health:CreateTexture(nameplate:GetName()..'FlashTexture', 'OVERLAY')
	healthFlashTexture:SetTexture(LSM:Fetch('background', 'ElvUI Blank'))
	healthFlashTexture:Point('BOTTOMLEFT', statusBarTexture, 'BOTTOMLEFT')
	healthFlashTexture:Point('TOPRIGHT', statusBarTexture, 'TOPRIGHT')
	healthFlashTexture:Hide()
	nameplate.HealthFlashTexture = healthFlashTexture

	local clipFrame = CreateFrame("Frame", nil, Health)
	clipFrame:SetScript("OnUpdate", UF.HealthClipFrame_OnUpdate)
	clipFrame:SetAllPoints()
	clipFrame:EnableMouse(false)
	clipFrame.__frame = Health
	Health.ClipFrame = clipFrame

	return Health
end

function NP:Health_SetColors(nameplate, threatColors)
	if threatColors then -- managed by ThreatIndicator_PostUpdate
		nameplate.Health:SetColorTapping(nil)
		nameplate.Health:SetColorSelection(nil)
		nameplate.Health.colorReaction = nil
		nameplate.Health.colorClass = nil
	else
		local db = NP:PlateDB(nameplate)
		nameplate.Health:SetColorTapping(true)
		nameplate.Health:SetColorSelection(true)
		nameplate.Health.colorReaction = true
		nameplate.Health.colorClass = db.health and db.health.useClassColor
	end
end

function NP:Update_Health(nameplate, skipUpdate)
	local db = NP:PlateDB(nameplate)

	NP:Health_SetColors(nameplate)

	if skipUpdate then return end

	if db.health.enable then
		if not nameplate:IsElementEnabled('Health') then
			nameplate:EnableElement('Health')
		end

		nameplate.Health:Point('CENTER')
		nameplate.Health:Point('LEFT')
		nameplate.Health:Point('RIGHT')

		E:SetSmoothing(nameplate.Health, NP.db.smoothbars)
	elseif nameplate:IsElementEnabled('Health') then
		nameplate:DisableElement('Health')
	end

	nameplate.Health.width = db.health.width
	nameplate.Health.height = db.health.height
	nameplate.Health:Height(db.health.height)
end

function NP:Update_HealComm(nameplate)
	local db = NP:PlateDB(nameplate)

	if db.health.enable and db.health.healPrediction then
		if not nameplate:IsElementEnabled('HealCommBar') then
			nameplate:EnableElement('HealCommBar')
		end

		nameplate.HealCommBar.myBar:SetStatusBarColor(NP.db.colors.healPrediction.personal.r, NP.db.colors.healPrediction.personal.g, NP.db.colors.healPrediction.personal.b)
		nameplate.HealCommBar.otherBar:SetStatusBarColor(NP.db.colors.healPrediction.others.r, NP.db.colors.healPrediction.others.g, NP.db.colors.healPrediction.others.b)
	elseif nameplate:IsElementEnabled('HealCommBar') then
		nameplate:DisableElement('HealCommBar')
	end
end

function NP.HealthClipFrame_HealComm(frame)
	local pred = frame.HealCommBar
	if pred then
		NP:SetAlpha_HealComm(pred, true)
		NP:SetVisibility_HealComm(pred)
	end
end

function NP:SetAlpha_HealComm(obj, show)
	obj.myBar:SetAlpha(show and 1 or 0)
	obj.otherBar:SetAlpha(show and 1 or 0)
	if obj.shieldPool then
		for _, bar in ipairs(obj.shieldPool) do
			bar:SetAlpha(show and 1 or 0)
		end
	end
end

function NP:SetVisibility_HealComm(obj)
	-- the first update is from `HealthClipFrame_HealComm`
	-- we set this variable to allow `Configure_HealComm` to
	-- update the elements overflow lock later on by option
	if not obj.allowClippingUpdate then
		obj.allowClippingUpdate = true
	end

	local parent = obj.maxOverflow > 1 and obj.health or obj.parent
	obj.myBar:SetParent(parent)
	obj.otherBar:SetParent(parent)
	if obj.shieldPool then
		for _, bar in ipairs(obj.shieldPool) do
			bar:SetParent(parent)
		end
	end
end

function NP:Construct_HealComm(frame)
	local health = frame.Health
	local parent = health.ClipFrame

	local myBar = CreateFrame("StatusBar", nil, parent)
	local otherBar = CreateFrame("StatusBar", nil, parent)
	local absorbBar = CreateFrame("StatusBar", nil, parent)

	myBar:SetFrameLevel(health:GetFrameLevel()+1)
	otherBar:SetFrameLevel(health:GetFrameLevel()+1)

	NP.StatusBars[myBar] = true
	NP.StatusBars[otherBar] = true

	local shieldPool = {}
	for k = 1, 5 do
		local sBar
		if k == 1 then
			sBar = absorbBar
		else
			sBar = CreateFrame("StatusBar", nil, parent)
		end
		sBar:SetFrameLevel(health:GetFrameLevel()+1)
		NP.StatusBars[sBar] = true

		-- Create icon texture overlay
		local icon = sBar:CreateTexture(nil, "OVERLAY")
		icon:SetSize(Settings.IconSize, Settings.IconSize)
		sBar.icon = icon

		-- Create boundary separator line
		local separator = sBar:CreateTexture(nil, "OVERLAY")
		separator:SetWidth(Settings.SeparatorWidth)
		separator:SetColorTexture(Settings.SeparatorColor.r, Settings.SeparatorColor.g, Settings.SeparatorColor.b, Settings.SeparatorColor.a)
		sBar.separator = separator

		-- Create absorb value text overlay
		local text = sBar:CreateFontString(nil, "OVERLAY")
		text:SetFont(LSM:Fetch("font", "PT Sans Narrow"), 8, "OUTLINE")
		sBar.text = text

		-- Create outline frame
		local outline = CreateFrame("Frame", nil, sBar)
		outline:SetAllPoints(sBar)
		outline:Hide()
		sBar.outline = outline

		outline.top = outline:CreateTexture(nil, "OVERLAY")
		outline.top:SetTexture("Interface\\Buttons\\WHITE8x8")
		outline.top:SetHeight(1)
		outline.top:SetPoint("TOPLEFT", sBar, "TOPLEFT", 0, 0)
		outline.top:SetPoint("TOPRIGHT", sBar, "TOPRIGHT", 0, 0)

		outline.bottom = outline:CreateTexture(nil, "OVERLAY")
		outline.bottom:SetTexture("Interface\\Buttons\\WHITE8x8")
		outline.bottom:SetHeight(1)
		outline.bottom:SetPoint("BOTTOMLEFT", sBar, "BOTTOMLEFT", 0, 0)
		outline.bottom:SetPoint("BOTTOMRIGHT", sBar, "BOTTOMRIGHT", 0, 0)

		outline.left = outline:CreateTexture(nil, "OVERLAY")
		outline.left:SetTexture("Interface\\Buttons\\WHITE8x8")
		outline.left:SetWidth(1)
		outline.left:SetPoint("TOPLEFT", sBar, "TOPLEFT", 0, 0)
		outline.left:SetPoint("BOTTOMLEFT", sBar, "BOTTOMLEFT", 0, 0)

		outline.right = outline:CreateTexture(nil, "OVERLAY")
		outline.right:SetTexture("Interface\\Buttons\\WHITE8x8")
		outline.right:SetWidth(1)
		outline.right:SetPoint("TOPRIGHT", sBar, "TOPRIGHT", 0, 0)
		outline.right:SetPoint("BOTTOMRIGHT", sBar, "BOTTOMRIGHT", 0, 0)

		local glowTex = E.media.glowTex or "Interface\\AddOns\\ElvUI\\Media\\Textures\\GlowTex"
		local glow = CreateFrame("Frame", nil, outline)
		glow:SetBackdrop({
			edgeFile = glowTex,
			edgeSize = 4,
		})
		glow:SetPoint("TOPLEFT", sBar, "TOPLEFT", -3, 3)
		glow:SetPoint("BOTTOMRIGHT", sBar, "BOTTOMRIGHT", 3, -3)
		outline.glow = glow

		outline:SetScript("OnUpdate", function(self, elapsed)
			self.time = (self.time or 0) + elapsed
			if self.style == "GLOW" then
				local alpha = 0.3 + 0.3 * math.sin(self.time * 4)
				self.glow:SetAlpha(alpha)
			end
		end)

		shieldPool[k] = sBar
	end

	local healPrediction = {
		myBar = myBar,
		otherBar = otherBar,
		absorbBar = absorbBar,
		shieldPool = shieldPool,
		PostUpdate = NP.UpdateHealComm,
		maxOverflow = 1,
		health = health,
		parent = parent,
		frame = frame
	}

	NP:SetAlpha_HealComm(healPrediction)

	return healPrediction
end

function NP:Configure_HealComm(frame)
	local db = NP:PlateDB(frame)

	if db.health.enable and db.health.healPrediction then
		if not frame:IsElementEnabled('HealComm4') then
			frame:EnableElement('HealComm4')
		end

		local healPrediction = frame.HealCommBar
		local myBar = healPrediction.myBar
		local otherBar = healPrediction.otherBar
		local absorbBar = healPrediction.absorbBar
		local c = db.colors.healPrediction
		healPrediction.maxOverflow = 1 + (c.maxOverflow or 0)

		if healPrediction.allowClippingUpdate then
			NP:SetVisibility_HealComm(healPrediction)
		end

		local health = frame.Health
		local orientation = health:GetOrientation()

		myBar:SetOrientation(orientation)
		otherBar:SetOrientation(orientation)
		if healPrediction.shieldPool then
			for _, bar in ipairs(healPrediction.shieldPool) do
				bar:SetOrientation(orientation)
			end
		end

		if orientation == "HORIZONTAL" then
			local width = health:GetWidth()
			width = (width > 0 and width) or health.WIDTH
			local healthTexture = health:GetStatusBarTexture()

			myBar:Size(width, 0)
			myBar:ClearAllPoints()
			myBar:Point("TOP", health, "TOP")
			myBar:Point("BOTTOM", health, "BOTTOM")
			myBar:Point("LEFT", healthTexture, "RIGHT")

			otherBar:Size(width, 0)
			otherBar:ClearAllPoints()
			otherBar:Point("TOP", health, "TOP")
			otherBar:Point("BOTTOM", health, "BOTTOM")
			otherBar:Point("LEFT", myBar:GetStatusBarTexture(), "RIGHT")

			if healPrediction.shieldPool then
				for _, bar in ipairs(healPrediction.shieldPool) do
					bar:Size(width, 0)
				end
			end
		else
			local height = health:GetHeight()
			height = (height > 0 and height) or health.HEIGHT
			local healthTexture = health:GetStatusBarTexture()

			myBar:Size(0, height)
			myBar:ClearAllPoints()
			myBar:Point("LEFT", health, "LEFT")
			myBar:Point("RIGHT", health, "RIGHT")
			myBar:Point("BOTTOM", healthTexture, "TOP")

			otherBar:Size(0, height)
			otherBar:ClearAllPoints()
			otherBar:Point("LEFT", health, "LEFT")
			otherBar:Point("RIGHT", health, "RIGHT")
			otherBar:Point("BOTTOM", myBar:GetStatusBarTexture(), "TOP")

			if healPrediction.shieldPool then
				for _, bar in ipairs(healPrediction.shieldPool) do
					bar:Size(0, height)
				end
			end
		end

		frame.HealCommBar.myBar:SetStatusBarColor(NP.db.colors.healPrediction.personal.r, NP.db.colors.healPrediction.personal.g, NP.db.colors.healPrediction.personal.b)
		frame.HealCommBar.otherBar:SetStatusBarColor(NP.db.colors.healPrediction.others.r, NP.db.colors.healPrediction.others.g, NP.db.colors.healPrediction.others.b)

		if frame:IsElementEnabled('HealComm4') then
			frame:UpdateElement('HealComm4')
		end
	elseif frame:IsElementEnabled('HealComm4') then
		frame:DisableElement('HealComm4')
	end
end

local function UpdateFillBar(frame, previousTexture, bar, amount)
	if amount == 0 then
		bar:Hide()
		return previousTexture
	end

	local orientation = frame:GetOrientation()
	bar:ClearAllPoints()
	if orientation == "HORIZONTAL" then
		bar:SetPoint("TOPLEFT", previousTexture, "TOPRIGHT")
		bar:SetPoint("BOTTOMLEFT", previousTexture, "BOTTOMRIGHT")
	else
		bar:SetPoint("BOTTOMRIGHT", previousTexture, "TOPRIGHT")
		bar:SetPoint("BOTTOMLEFT", previousTexture, "TOPLEFT")
	end

	local totalWidth, totalHeight = frame:GetSize()
	if orientation == "HORIZONTAL" then
		bar:Width(totalWidth)
	else
		bar:Height(totalHeight)
	end

	return bar:GetStatusBarTexture()
end

local function ShieldBar_OnUpdate(self, elapsed)
	self.pulseTime = (self.pulseTime or 0) + elapsed
	local baseAlpha = self.baseAlpha or 0.6
	local alpha = baseAlpha + 0.2 * math.sin(self.pulseTime * 5)
	if alpha < 0.1 then alpha = 0.1 end
	if alpha > 1 then alpha = 1 end
	local r, g, b = self:GetStatusBarColor()
	self:SetStatusBarColor(r, g, b, alpha)
end

local function FormatAbsorbValue(val, short)
	if not short then return tostring(val) end
	if val >= 1000000 then
		return string.format("%.1fm", val / 1000000)
	elseif val >= 1000 then
		return string.format("%.1fk", val / 1000)
	else
		return tostring(val)
	end
end

function NP:UpdateHealComm(unit, myIncomingHeal, allIncomingHeal, absorb)
	local health = self.health
	local previousTexture = health:GetStatusBarTexture()

	previousTexture = UpdateFillBar(health, previousTexture, self.myBar, myIncomingHeal)
	previousTexture = UpdateFillBar(health, previousTexture, self.otherBar, allIncomingHeal)

	local shieldPool = self.shieldPool
	if not shieldPool then return end

	-- Hide all shield bars and text overlays initially, and clear scripts
	for _, bar in ipairs(shieldPool) do
		bar:Hide()
		bar:SetScript("OnUpdate", nil)
		if bar.text then bar.text:Hide() end
	end

	-- Get config DB for this nameplate
	local db = self.frame and NP:PlateDB(self.frame)
	local hpPred = db and db.health and db.health.healPrediction

	local absorbsEnable = (hpPred and hpPred.absorbsEnable ~= nil) and hpPred.absorbsEnable or true
	local showAbsorbIcons = (hpPred and hpPred.showAbsorbIcons ~= nil) and hpPred.showAbsorbIcons or true
	local absorbIconSize = (hpPred and hpPred.absorbIconSize) or Settings.IconSize
	local absorbIconXOffset = (hpPred and hpPred.absorbIconXOffset) or 0
	local absorbIconYOffset = (hpPred and hpPred.absorbIconYOffset) or 0
	local showAbsorbText = (hpPred and hpPred.showAbsorbText ~= nil) and hpPred.showAbsorbText or true
	local shortAbsorbText = (hpPred and hpPred.shortAbsorbText ~= nil) and hpPred.shortAbsorbText or true
	local absorbTextXOffset = (hpPred and hpPred.absorbTextXOffset) or 0
	local absorbTextYOffset = (hpPred and hpPred.absorbTextYOffset) or 0
	local absorbsPersonalOnly = (hpPred and hpPred.absorbsPersonalOnly ~= nil) and hpPred.absorbsPersonalOnly or false
	local absorbSeparatorWidth = (hpPred and hpPred.absorbSeparatorWidth) or Settings.SeparatorWidth
	local absorbSeparatorAlpha = (hpPred and hpPred.absorbSeparatorAlpha) or Settings.SeparatorColor.a
	local absorbPulse = (hpPred and hpPred.absorbPulse ~= nil) and hpPred.absorbPulse or false
	local clampAbsorbs = hpPred and hpPred.clampAbsorbs or false

	if not absorbsEnable then return end

	local totalNativeAbsorb = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0

	local shields = GetUnitShields(unit, absorbsPersonalOnly)
	if #shields == 0 then return end

	local totalParsed = 0
	for _, s in ipairs(shields) do
		totalParsed = totalParsed + s.amount
	end

	local displayTotalAbsorb = absorbsPersonalOnly and totalParsed or math.max(totalNativeAbsorb, totalParsed)
	if displayTotalAbsorb <= 0 then return end

	local healthVal = UnitHealth(unit) or 0
	local maxHealth = UnitHealthMax(unit) or 0
	if maxHealth <= 0 then return end

	local orientation = health:GetOrientation()
	local totalWidth, totalHeight = health:GetSize()
	local isOverflowing = (healthVal + (myIncomingHeal or 0) + (allIncomingHeal or 0) + displayTotalAbsorb) > maxHealth

	local scaleFactor = 1
	if clampAbsorbs and isOverflowing and totalParsed > maxHealth then
		scaleFactor = maxHealth / totalParsed
	end

	local lastAnchor = previousTexture

	for k, shield in ipairs(shields) do
		if k > #shieldPool then break end
		local bar = shieldPool[k]

		-- Set Color from Settings
		local color
		local hAbs = E.db.unitframe.colors.healAbsorbs
		if hAbs then
			if shield.isPlayer then
				color = hAbs.absorbPlayer or {r = 0.3, g = 0.7, b = 1.0, a = 0.6}
			else
				color = hAbs.absorbOther or {r = 0.5, g = 0.5, b = 1.0, a = 0.6}
			end
		else
			color = Settings.Colors[((k - 1) % #Settings.Colors) + 1]
		end
		bar:SetStatusBarColor(color.r, color.g, color.b, color.a)
		bar.baseAlpha = color.a

		-- Set Outline
		if bar.outline then
			local style, col
			if hAbs then
				if shield.isPlayer then
					style = hAbs.absorbPlayerOutline or "NONE"
					col = hAbs.absorbPlayerOutlineColor or {r = 1, g = 1, b = 1, a = 1}
				else
					style = hAbs.absorbOtherOutline or "NONE"
					col = hAbs.absorbOtherOutlineColor or {r = 1, g = 1, b = 1, a = 1}
				end
			else
				style = "NONE"
			end
			
			if style == "NONE" then
				bar.outline:Hide()
			else
				bar.outline:Show()
				bar.outline.style = style
				bar.outline.time = 0
				
				if style == "SOLID" then
					bar.outline.top:SetTexture("Interface\\Buttons\\WHITE8x8")
					bar.outline.bottom:SetTexture("Interface\\Buttons\\WHITE8x8")
					bar.outline.left:SetTexture("Interface\\Buttons\\WHITE8x8")
					bar.outline.right:SetTexture("Interface\\Buttons\\WHITE8x8")
					
					bar.outline.top:SetTexCoord(0, 1, 0, 1)
					bar.outline.bottom:SetTexCoord(0, 1, 0, 1)
					bar.outline.left:SetTexCoord(0, 1, 0, 1)
					bar.outline.right:SetTexCoord(0, 1, 0, 1)
					
					bar.outline.top:SetVertexColor(col.r, col.g, col.b, col.a)
					bar.outline.bottom:SetVertexColor(col.r, col.g, col.b, col.a)
					bar.outline.left:SetVertexColor(col.r, col.g, col.b, col.a)
					bar.outline.right:SetVertexColor(col.r, col.g, col.b, col.a)
					
					bar.outline.top:Show()
					bar.outline.bottom:Show()
					bar.outline.left:Show()
					bar.outline.right:Show()
					bar.outline.glow:Hide()
				elseif style == "GLOW" then
					bar.outline.top:Hide()
					bar.outline.bottom:Hide()
					bar.outline.left:Hide()
					bar.outline.right:Hide()
					
					bar.outline.glow:SetBackdropBorderColor(col.r, col.g, col.b, col.a)
					bar.outline.glow:Show()
				end
			end
		end

		-- Set Icon
		if bar.icon then
			bar.icon:SetTexture(shield.icon)
			bar.icon:SetSize(absorbIconSize, absorbIconSize)
			if showAbsorbIcons and not shield.isFallback then
				bar.icon:Show()
			else
				bar.icon:Hide()
			end
		end

		-- Set Separator
		if bar.separator then
			bar.separator:SetWidth(absorbSeparatorWidth)
			bar.separator:SetColorTexture(Settings.SeparatorColor.r, Settings.SeparatorColor.g, Settings.SeparatorColor.b, absorbSeparatorAlpha)
		end

		bar:ClearAllPoints()

		if orientation == "HORIZONTAL" then
			local width = (shield.amount / maxHealth) * totalWidth * scaleFactor
			if width > totalWidth then width = totalWidth end

			if isOverflowing then
				-- Grow from right to left
				if k == 1 then
					bar:SetPoint("TOPRIGHT", health, "TOPRIGHT")
					bar:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT")
				else
					bar:SetPoint("TOPRIGHT", shieldPool[k - 1], "TOPLEFT")
					bar:SetPoint("BOTTOMRIGHT", shieldPool[k - 1], "BOTTOMLEFT")
				end
				if bar.separator then
					bar.separator:ClearAllPoints()
					bar.separator:SetPoint("TOPLEFT", bar, "TOPLEFT")
					bar.separator:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT")
					bar.separator:Show()
				end
			else
				-- Grow from left to right
				if k == 1 then
					bar:SetPoint("TOPLEFT", lastAnchor, "TOPRIGHT")
					bar:SetPoint("BOTTOMLEFT", lastAnchor, "BOTTOMRIGHT")
				else
					bar:SetPoint("TOPLEFT", shieldPool[k - 1], "TOPRIGHT")
					bar:SetPoint("BOTTOMLEFT", shieldPool[k - 1], "BOTTOMRIGHT")
				end
				if bar.separator then
					bar.separator:ClearAllPoints()
					bar.separator:SetPoint("TOPRIGHT", bar, "TOPRIGHT")
					bar.separator:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
					bar.separator:Show()
				end
			end

			-- Position Icon next to separator line
			local iconShown = false
			local iconSide = "LEFT"
			if bar.icon and showAbsorbIcons then
				bar.icon:ClearAllPoints()
				if #shields == 1 then
					bar.icon:SetPoint("LEFT", bar, "LEFT", 2 + absorbIconXOffset, 0 + absorbIconYOffset)
					iconSide = "LEFT"
				else
					if isOverflowing then
						if k < #shields then
							bar.icon:SetPoint("LEFT", bar, "LEFT", 2 + absorbIconXOffset, 0 + absorbIconYOffset)
							iconSide = "LEFT"
						else
							bar.icon:SetPoint("RIGHT", bar, "RIGHT", -2 + absorbIconXOffset, 0 + absorbIconYOffset)
							iconSide = "RIGHT"
						end
					else
						if k < #shields then
							bar.icon:SetPoint("RIGHT", bar, "RIGHT", -2 + absorbIconXOffset, 0 + absorbIconYOffset)
							iconSide = "RIGHT"
						else
							bar.icon:SetPoint("LEFT", bar, "LEFT", 2 + absorbIconXOffset, 0 + absorbIconYOffset)
							iconSide = "LEFT"
						end
					end
				end
				if (shield.amount / maxHealth) >= 0.08 then
					bar.icon:Show()
					iconShown = true
				else
					bar.icon:Hide()
				end
			end

			-- Position Text
			if bar.text then
				bar.text:ClearAllPoints()
				if showAbsorbText and (shield.amount / maxHealth) >= 0.10 then
					local textVal = FormatAbsorbValue(shield.amount, shortAbsorbText)
					bar.text:SetText(textVal)
					if iconShown then
						if iconSide == "LEFT" then
							bar.text:SetPoint("LEFT", bar.icon, "RIGHT", 2 + absorbTextXOffset, 0 + absorbTextYOffset)
						else
							bar.text:SetPoint("RIGHT", bar.icon, "LEFT", -2 + absorbTextXOffset, 0 + absorbTextYOffset)
						end
					else
						bar.text:SetPoint("CENTER", bar, "CENTER", absorbTextXOffset, absorbTextYOffset)
					end
					bar.text:Show()
				else
					bar.text:Hide()
				end
			end

			bar:SetWidth(width)
		else
			-- Vertical orientation
			local height = (shield.amount / maxHealth) * totalHeight * scaleFactor
			if height > totalHeight then height = totalHeight end

			if isOverflowing then
				-- Grow from top to bottom
				if k == 1 then
					bar:SetPoint("TOPLEFT", health, "TOPLEFT")
					bar:SetPoint("TOPRIGHT", health, "TOPRIGHT")
				else
					bar:SetPoint("TOPLEFT", shieldPool[k - 1], "BOTTOMLEFT")
					bar:SetPoint("TOPRIGHT", shieldPool[k - 1], "BOTTOMRIGHT")
				end
				if bar.separator then
					bar.separator:ClearAllPoints()
					bar.separator:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT")
					bar.separator:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
					bar.separator:Show()
				end
			else
				-- Grow from bottom to top
				if k == 1 then
					bar:SetPoint("BOTTOMLEFT", lastAnchor, "TOPLEFT")
					bar:SetPoint("BOTTOMRIGHT", lastAnchor, "TOPRIGHT")
				else
					bar:SetPoint("BOTTOMLEFT", shieldPool[k - 1], "TOPLEFT")
					bar:SetPoint("BOTTOMRIGHT", shieldPool[k - 1], "TOPRIGHT")
				end
				if bar.separator then
					bar.separator:ClearAllPoints()
					bar.separator:SetPoint("TOPLEFT", bar, "TOPLEFT")
					bar.separator:SetPoint("TOPRIGHT", bar, "TOPRIGHT")
					bar.separator:Show()
				end
			end

			-- Position Icon next to separator line
			local iconShown = false
			local iconSide = "BOTTOM"
			if bar.icon and showAbsorbIcons then
				bar.icon:ClearAllPoints()
				if #shields == 1 then
					bar.icon:SetPoint("BOTTOM", bar, "BOTTOM", 0 + absorbIconXOffset, 2 + absorbIconYOffset)
					iconSide = "BOTTOM"
				else
					if isOverflowing then
						if k < #shields then
							bar.icon:SetPoint("TOP", bar, "TOP", 0 + absorbIconXOffset, -2 + absorbIconYOffset)
							iconSide = "TOP"
						else
							bar.icon:SetPoint("BOTTOM", bar, "BOTTOM", 0 + absorbIconXOffset, 2 + absorbIconYOffset)
							iconSide = "BOTTOM"
						end
					else
						if k < #shields then
							bar.icon:SetPoint("BOTTOM", bar, "BOTTOM", 0 + absorbIconXOffset, 2 + absorbIconYOffset)
							iconSide = "BOTTOM"
						else
							bar.icon:SetPoint("TOP", bar, "TOP", 0 + absorbIconXOffset, -2 + absorbIconYOffset)
							iconSide = "TOP"
						end
					end
				end
				if (shield.amount / maxHealth) >= 0.08 then
					bar.icon:Show()
					iconShown = true
				else
					bar.icon:Hide()
				end
			end

			-- Position Text
			if bar.text then
				bar.text:ClearAllPoints()
				if showAbsorbText and (shield.amount / maxHealth) >= 0.10 then
					local textVal = FormatAbsorbValue(shield.amount, shortAbsorbText)
					bar.text:SetText(textVal)
					if iconShown then
						if iconSide == "BOTTOM" then
							bar.text:SetPoint("BOTTOM", bar.icon, "TOP", 0 + absorbTextXOffset, 2 + absorbTextYOffset)
						else
							bar.text:SetPoint("TOP", bar.icon, "BOTTOM", 0 + absorbTextXOffset, -2 + absorbTextYOffset)
						end
					else
						bar.text:SetPoint("CENTER", bar, "CENTER", absorbTextXOffset, absorbTextYOffset)
					end
					bar.text:Show()
				else
					bar.text:Hide()
				end
			end

			bar:SetHeight(height)
		end

		-- Hide separator on the last shield in the active list
		if k == #shields and bar.separator then
			bar.separator:Hide()
		end

		bar:SetMinMaxValues(0, shield.amount)
		bar:SetValue(shield.amount)
		bar:Show()

		-- Start pulse animation if enabled
		if absorbPulse then
			bar.pulseTime = 0
			bar:SetScript("OnUpdate", ShieldBar_OnUpdate)
		end
	end
end
