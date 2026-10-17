local E, L, V, P, G = unpack(ElvUI)

-- ============================================================================
-- Profile Defaults (P) for ElvUI
-- Handles automatic persistence, profile swapping, and export/import.
-- ============================================================================

-- Centralised default block — all bar settings live here once
local function BarDefaults(overrides)
	local base = {
		enable            = true,

		-- Display Style
		displayStyle      = "ICON",         -- "ICON" | "STATUSBAR"
		barWidth          = 180,            -- Width of draining status bar
		barHeight         = 20,             -- Height of status bar / status bar icon
		statusBarTexture  = "ElvUI Norm",   -- Status bar texture

		-- Layout
		iconSize          = 32,
		iconScale         = 1.0,            -- Multiplier applied on top of iconSize
		spacing           = 4,
		orientation       = "HORIZONTAL",   -- "HORIZONTAL" | "VERTICAL"
		growthDirection   = "RIGHT",        -- "RIGHT" | "LEFT" | "UP" | "DOWN"
		maxIcons          = 10,
		perLine           = 0,              -- Icons per row/column before wrapping (0 = no wrap)

		-- Visibility filters
		hideEmpty         = false,
		showOnlyCombat    = false,

		-- Icon & Cooldown display
		showReady         = true,           -- Show icon even when ability is ready (not on CD)
		showCount         = true,           -- Show stack/charge count text
		showSwipe         = true,           -- Cooldown swipe spiral animation
		showDuration      = true,           -- Countdown text over icon
		durationThreshold = 0,              -- 0 = always show; N = only show when remaining <= N s
		colorDuration     = false,          -- Color-code timer: green > 5s, yellow ≤ 5s, red ≤ 2s
		showGCD           = true,           -- Show Global Cooldown sweep (<= 1.5s) on icons

		-- Keybind Display
		showKeybind       = true,           -- Display keybind text on icon (e.g. S1, Q, F1)
		keybindFontSize   = 10,             -- Keybind font size

		-- Spell name label
		showLabel         = false,          -- Show spell name below each icon
		labelFontSize     = 9,              -- Font size for the label

		-- Sort
		sortByRemaining   = false,          -- Sort icons: shortest remaining CD first

		-- Visual effects & Audio
		desaturateOnCD    = true,           -- Grayscale while on cooldown / buff inactive
		glowOnReady       = false,          -- Pulse highlight when ability comes off cooldown
		glowActionButton  = false,          -- Glow the corresponding action bar button on screen
		playSoundOnReady  = false,          -- Play sound when CD becomes ready or buff is gained
		readySound        = "ReadyCheck",   -- Sound file to play

		-- Opacity
		overrideAlpha     = false,          -- Enable a flat bar-wide alpha override
		barAlpha          = 1.0,            -- Flat alpha applied to the whole bar
		cooldownAlpha     = 0.8,            -- Per-icon alpha while on cooldown
		readyAlpha        = 1.0,            -- Per-icon alpha while ready
		inactiveAlpha     = 0.4,            -- Per-icon alpha when buff not active

		-- Background panel behind the bar
		showBackground    = false,
		bgR               = 0.0,
		bgG               = 0.0,
		bgB               = 0.0,
		bgA               = 0.5,

		-- Tooltip
		showTooltip       = true,
		showTooltipDesc   = true,           -- Full description vs. name-only header

		-- Click-to-cast
		clickable         = false,          -- Click icon to cast the tracked spell

		-- Tracking
		trackType         = "COOLDOWN",     -- "COOLDOWN" | "BUFF"

		-- Anchoring to another bar
		attachTo          = "NONE",         -- "NONE" | barKey
		attachDirection   = "BELOW",        -- "ABOVE" | "BELOW" | "LEFT" | "RIGHT" | "CUSTOM"
		attachPoint       = "TOPLEFT",
		anchorPoint       = "BOTTOMLEFT",
		xOffset           = 0,
		yOffset           = -4,

		-- Spell list
		spells            = {},             -- { [spellID] = true }
	}
	if overrides then
		for k, v in pairs(overrides) do base[k] = v end
	end
	return base
end

P.cooldownManager = {
	enable      = true,
	font        = "Expressway",
	fontSize    = 11,
	fontOutline = "OUTLINE",
	onlyMaxRank = true,

	bars = {
		cooldowns = BarDefaults({
			name          = "Primary Cooldowns",
			iconSize      = 34,
			maxIcons      = 12,
			showReady     = true,
			trackType     = "COOLDOWN",
		}),
		utilities = BarDefaults({
			name          = "Utility",
			iconSize      = 28,
			maxIcons      = 10,
			showReady     = true,
			trackType     = "COOLDOWN",
		}),
		buffs = BarDefaults({
			name          = "Buffs",
			iconSize      = 32,
			maxIcons      = 10,
			hideEmpty     = true,
			showReady     = false,
			trackType     = "BUFF",
		}),
	},

	-- Overlays & Screen Alerts (disabled by default)
	overlays = {
		raidBuffs = {
			enable       = false,
			hideInCombat = true,
			iconSize     = 28,
			spacing      = 4,
		},
		aggroAlert = {
			enable   = false,
			fontSize = 22,
		},
		rangeAlert = {
			enable     = false,
			fontSize   = 18,
			spellCheck = "",
		},
	},

	-- HoT & Buff Tracking on ElvUI UnitFrames
	unitFrameWatch = {
		enable = true,
		trackers = {
			{ enable = true, spell = "Rejuvenation", point = "TOPLEFT", size = 14, style = "ICON", showTimer = true, showCount = true },
			{ enable = true, spell = "Regrowth", point = "TOPRIGHT", size = 14, style = "ICON", showTimer = true, showCount = true },
			{ enable = true, spell = "Lifebloom", point = "BOTTOMRIGHT", size = 14, style = "ICON", showTimer = true, showCount = true },
		},
	},

	-- Personal resource & power bar
	powerBars = {
		enable      = true,
		name        = "Personal Power Bar",
		barWidth    = 160,
		barHeight   = 18,
		texture     = "ElvUI Norm",
		showText    = true,
		hideInCombat = false,
	},

	-- User-created custom bars (populated dynamically at runtime)
	customBars = {},
}
