local E, L, V, P, G = unpack(select(2, ...)) --Import: Engine, Locales, PrivateDB, ProfileDB, GlobalDB
local S = E:GetModule("Skins")

--Lua functions
local _G = _G
local unpack = unpack
--WoW API / Variables
local MAX_SKILLLINE_TABS = MAX_SKILLLINE_TABS

S:AddCallback("Skin_Spellbook", function()
	if not E.private.skins.blizzard.enable or not E.private.skins.blizzard.spellbook then return end

	SpellBookFrame:StripTextures(true)
	SpellBookFrame:CreateBackdrop("Transparent")
	SpellBookFrame.backdrop:Point("TOPLEFT", 11, -12)
	SpellBookFrame.backdrop:Point("BOTTOMRIGHT", -32, 76)

	S:SetUIPanelWindowInfo(SpellBookFrame, "width", nil, 31)
	S:SetBackdropHitRect(SpellBookFrame)

	-- Mouse Wheel Navigation.
	-- The page buttons are wired to Blizzard's global page-turn functions, not to an
	-- OnClick method on the button object, so those functions are called directly. The
	-- button enabled state already tracks the page bounds.
	SpellBookFrame:EnableMouseWheel(true)

	SpellBookFrame:SetScript("OnMouseWheel", function(_, value)
		if value > 0 then
			if SpellBookPrevPageButton:IsEnabled() == 1 then
				SpellBookPrevPageButton_OnClick()
			end
		else
			if SpellBookNextPageButton:IsEnabled() == 1 then
				SpellBookNextPageButton_OnClick()
			end
		end
	end)

	for i = 1, 3 do
		local tab = _G["SpellBookFrameTabButton"..i]
		tab:Size(122, 32)
		tab:GetNormalTexture():SetTexture(nil)
		tab:GetDisabledTexture():SetTexture(nil)
		tab:GetRegions():SetPoint("CENTER", 0, 2)
		S:HandleTab(tab)
	end

	SpellBookFrameTabButton1:Point("CENTER", SpellBookFrame, "BOTTOMLEFT", 72, 62)
	SpellBookFrameTabButton2:Point("LEFT", SpellBookFrameTabButton1, "RIGHT", -15, 0)
	SpellBookFrameTabButton3:Point("LEFT", SpellBookFrameTabButton2, "RIGHT", -15, 0)

	S:HandleNextPrevButton(SpellBookPrevPageButton, nil, nil, true)
	S:HandleNextPrevButton(SpellBookNextPageButton, nil, nil, true)

	S:HandleCloseButton(SpellBookCloseButton, SpellBookFrame.backdrop)

	S:HandleCheckBox(ShowAllSpellRanksCheckBox)

	for i = 1, SPELLS_PER_PAGE do
		local button = _G["SpellButton"..i]
		local autoCast = _G["SpellButton"..i.."AutoCastable"]
		button:StripTextures()

		autoCast:SetTexture("Interface\\Buttons\\UI-AutoCastableOverlay")
		autoCast:SetOutside(button, 16, 16)

		button:CreateBackdrop("Default", true)

		_G["SpellButton"..i.."IconTexture"]:SetTexCoord(unpack(E.TexCoords))

		E:RegisterCooldown(_G["SpellButton"..i.."Cooldown"])
	end

	hooksecurefunc("SpellButton_UpdateButton", function(self)
		local name = self:GetName()
		_G[name.."SpellName"]:SetTextColor(1, 0.80, 0.10)
		_G[name.."SubSpellName"]:SetTextColor(1, 1, 1)
		_G[name.."Highlight"]:SetTexture(1, 1, 1, 0.3)
	end)

	for i = 1, MAX_SKILLLINE_TABS do
		local tab = _G["SpellBookSkillLineTab"..i]

		tab:StripTextures()
		tab:StyleButton(nil, true)
		tab:SetTemplate("Default", true)

		tab:GetNormalTexture():SetInside()
		tab:GetNormalTexture():SetTexCoord(unpack(E.TexCoords))
	end

	SpellBookSkillLineTab1:Point("TOPLEFT", SpellBookFrame, "TOPRIGHT", -33, -65)

	SpellBookPageText:SetTextColor(1, 1, 1)
end)