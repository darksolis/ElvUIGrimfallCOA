local E, L, V, P, G = unpack(ElvUI)
local CM = E:GetModule("CooldownManager")

local CreateFrame = CreateFrame
local UnitAura = UnitAura
local GetTime = GetTime
local unpack, pairs, ipairs = unpack, pairs, ipairs

-- ============================================================================
-- HoT & Buff Indicators for ElvUI Party / Raid UnitFrames
-- ============================================================================
local UnitFrameWatch = {}
CM.UnitFrameWatch = UnitFrameWatch

UnitFrameWatch.indicators = {} -- Pool of indicator frames attached to unitframes

-- Scan for active ElvUI UnitFrame buttons on screen
local function GetActiveUnitFrames()
	local frames = {}
	local headers = { "ElvUI_PartyHeader", "ElvUI_RaidHeader", "ElvUI_Raid40Header", "ElvUI_RaidpetHeader" }

	for _, hName in ipairs(headers) do
		local header = _G[hName]
		if header then
			for i = 1, 40 do
				local unitFrame = _G[hName .. "Group" .. math.ceil(i/5) .. "UnitButton" .. ((i-1)%5 + 1)] or _G[hName .. "UnitButton" .. i]
				if unitFrame and unitFrame:IsVisible() and unitFrame.unit then
					table.insert(frames, unitFrame)
				end
			end
		end
	end

	-- Also check single unitframes (player, target, focus, pet)
	local singleFrames = { "ElvUI_Player", "ElvUI_Target", "ElvUI_Focus", "ElvUI_Pet" }
	for _, fName in ipairs(singleFrames) do
		local frame = _G[fName]
		if frame and frame:IsVisible() and frame.unit then
			table.insert(frames, frame)
		end
	end

	return frames
end

-- Check active HoT/Buff cast by player on a unit
local function GetPlayerUnitAura(unit, spellIDOrName)
	if not unit or not spellIDOrName then return false end
	for i = 1, 40 do
		local name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, _, _, auraSpellId = UnitAura(unit, i, "HELPFUL")
		if not name then break end

		local isMine = (unitCaster == "player")
		if isMine and ((auraSpellId and auraSpellId == spellIDOrName) or (name == spellIDOrName)) then
			local rem = 0
			if expirationTime and expirationTime > 0 then
				rem = expirationTime - GetTime()
				if rem < 0 then rem = 0 end
			end
			return true, count or 0, duration or 0, expirationTime or 0, rem, icon
		end
	end
	return false
end

function UnitFrameWatch:Update()
	local cfg = E.db.cooldownManager and E.db.cooldownManager.unitFrameWatch
	if not cfg or not cfg.enable or not cfg.trackers then return end

	local activeFrames = GetActiveUnitFrames()

	for _, unitFrame in ipairs(activeFrames) do
		local unit = unitFrame.unit
		unitFrame._cmIndicators = unitFrame._cmIndicators or {}

		for idx, tracker in ipairs(cfg.trackers) do
			if tracker.enable and tracker.spell then
				local hasBuff, count, dur, exp, rem, icon = GetPlayerUnitAura(unit, tracker.spell)
				local ind = unitFrame._cmIndicators[idx]

				if hasBuff then
					if not ind then
						ind = CreateFrame("Frame", nil, unitFrame)
						ind:SetFrameLevel(unitFrame:GetFrameLevel() + 10)

						ind.icon = ind:CreateTexture(nil, "ARTWORK")
						ind.icon:SetAllPoints()

						ind.count = ind:CreateFontString(nil, "OVERLAY")
						ind.count:FontTemplate(nil, 9, "OUTLINE")
						ind.count:Point("BOTTOMRIGHT", ind, "BOTTOMRIGHT", 0, 0)

						ind.time = ind:CreateFontString(nil, "OVERLAY")
						ind.time:FontTemplate(nil, 9, "OUTLINE")
						ind.time:Point("CENTER", ind, "CENTER", 0, 0)

						unitFrame._cmIndicators[idx] = ind
					end

					local size = tracker.size or 14
					ind:SetSize(size, size)
					ind:ClearAllPoints()
					ind:Point(tracker.point or "TOPLEFT", unitFrame, tracker.point or "TOPLEFT", tracker.xOffset or 0, tracker.yOffset or 0)

					if tracker.style == "COLOR" then
						ind.icon:SetTexture([[Interface\Buttons\WHITE8X8]])
						ind.icon:SetVertexColor(tracker.r or 0.2, tracker.g or 0.8, tracker.b or 0.2, 0.9)
					else
						ind.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
						ind.icon:SetTexCoord(unpack(E.TexCoords))
						ind.icon:SetVertexColor(1, 1, 1, 1)
					end

					if tracker.showCount and count > 1 then
						ind.count:SetText(count)
						ind.count:Show()
					else
						ind.count:Hide()
					end

					if tracker.showTimer and rem > 0 then
						ind.time:SetText(CM:FormatTime(rem))
						ind.time:Show()
					else
						ind.time:Hide()
					end

					ind:Show()
				else
					if ind then ind:Hide() end
				end
			end
		end
	end
end
