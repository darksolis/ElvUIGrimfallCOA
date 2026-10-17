local E, L, V, P, G = unpack(ElvUI)
local CM = E:GetModule("CooldownManager")

-- ============================================================================
-- WoW 3.3.5a Raid Buff Equivalency Groups for Pre-Pull Checklist
-- ============================================================================
CM.RaidBuffGroups = {
	{
		id = "stamina",
		name = "Stamina",
		icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
		spells = {
			[48161] = "Power Word: Fortitude",
			[48162] = "Prayer of Fortitude",
			[47440] = "Commanding Shout",
			[6307]  = "Blood Pact",
		}
	},
	{
		id = "stats",
		name = "Stats (+%",
		icon = "Interface\\Icons\\Spell_Nature_Regeneration",
		spells = {
			[48469] = "Mark of the Wild",
			[48470] = "Gift of the Wild",
			[25898] = "Greater Blessing of Kings",
			[20217] = "Blessing of Kings",
		}
	},
	{
		id = "attackPower",
		name = "Attack Power",
		icon = "Interface\\Icons\\Spell_Holy_FistOfJustice",
		spells = {
			[48934] = "Blessing of Might",
			[48938] = "Greater Blessing of Might",
			[47436] = "Battle Shout",
			[19506] = "Trueshot Aura",
			[53138] = "Abomination's Might",
			[31519] = "Unleashed Rage",
		}
	},
	{
		id = "spellPower",
		name = "Spell Power",
		icon = "Interface\\Icons\\Spell_Holy_ArcaneIntellect",
		spells = {
			[42995] = "Arcane Intellect",
			[43002] = "Arcane Brilliance",
			[58656] = "Flametongue Totem",
			[47240] = "Demonic Pact",
			[2812]  = "Fel Intelligence",
		}
	},
	{
		id = "haste",
		name = "Haste",
		icon = "Interface\\Icons\\Spell_Nature_Windfury",
		spells = {
			[3738]  = "Wrath of Air Totem",
			[53648] = "Swift Retribution",
			[24907] = "Moonkin Aura",
			[55428] = "Icy Talons",
			[29193] = "Vindication",
		}
	},
	{
		id = "crit",
		name = "Critical Strike",
		icon = "Interface\\Icons\\Spell_Nature_UnrelentingStorm",
		spells = {
			[17007] = "Leader of the Pack",
			[51470] = "Elemental Oath",
			[29801] = "Rampage",
		}
	},
	{
		id = "mp5",
		name = "Mana Regen (MP5)",
		icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
		spells = {
			[48936] = "Blessing of Wisdom",
			[48942] = "Greater Blessing of Wisdom",
			[58774] = "Mana Spring Totem",
		}
	},
	{
		id = "armor",
		name = "Armor",
		icon = "Interface\\Icons\\Spell_Holy_DevotionAura",
		spells = {
			[48947] = "Devotion Aura",
			[58753] = "Stoneskin Totem",
		}
	},
	{
		id = "shadowProtection",
		name = "Shadow Resistance",
		icon = "Interface\\Icons\\Spell_Shadow_AntiShadow",
		spells = {
			[48169] = "Shadow Protection",
			[48170] = "Prayer of Shadow Protection",
			[48943] = "Shadow Resistance Aura",
		}
	},
	{
		id = "replenishment",
		name = "Replenishment",
		icon = "Interface\\Icons\\Spell_Holy_MindVision",
		spells = {
			[48160] = "Vampiric Touch",
			[53408] = "Judgements of the Wise",
			[53292] = "Hunting Party",
			[44561] = "Enduring Winter",
			[30295] = "Soul Leech",
		}
	}
}

-- Check if player or group has at least one spell from the buff category active
function CM:IsRaidBuffActive(groupInfo)
	for spellID, spellName in pairs(groupInfo.spells) do
		local active = CM:GetPlayerBuff(spellID, spellName)
		if active then return true end
	end
	return false
end
