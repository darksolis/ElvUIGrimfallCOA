local E, L, V, P, G = unpack(ElvUI)
local CM = E:GetModule("CooldownManager")

local addonName = ...
local EP = LibStub("LibElvUIPlugin-1.0")

local pairs, tostring, tonumber, wipe = pairs, tostring, tonumber, wipe
local format = string.format

CM.selectedRemoveSpell = CM.selectedRemoveSpell or {}

local function Clr(name) return format("|cffb366ff%s|r", name) end

-- ============================================================================
-- Attach-To dropdown: all bars except self
-- ============================================================================
local function GetBarTargetList(excludeKey)
	local list = { ["NONE"] = "None (Free Movement)" }
	if E.db.cooldownManager then
		if E.db.cooldownManager.bars then
			for k, cfg in pairs(E.db.cooldownManager.bars) do
				if k ~= excludeKey then list[k] = cfg.name or k end
			end
		end
		if E.db.cooldownManager.customBars then
			for k, cfg in pairs(E.db.cooldownManager.customBars) do
				if k ~= excludeKey then list[k] = cfg.name or k end
			end
		end
	end
	return list
end

-- ============================================================================
-- Active Spell List — returns a table of options for tracked spells
-- ============================================================================
local function BuildActiveSpellList(barKey)
	local args = {}
	local cfg  = CM:GetBarConfig(barKey)
	if cfg and cfg.spells then
		local order = 1
		for spellID, enabled in pairs(cfg.spells) do
			if enabled then
				local sid   = tonumber(spellID) or spellID
				local sData = CM:GetSpellData(sid)
				local sName = sData and sData.name or ("ID: " .. tostring(sid))
				local sRank = sData and sData.rank and sData.rank ~= "" and (" (" .. sData.rank .. ")") or ""
				local sIcon = sData and sData.icon and ("|T" .. sData.icon .. ":16:16:0:0:64:64:4:60:4:60|t ") or ""
				local capID = sid

				args["spell_" .. tostring(sid)] = {
					order = order,
					type  = "execute",
					name  = sIcon .. sName .. sRank .. "  |cffff4444[Remove]|r",
					desc  = "Click to remove this spell from the bar.",
					func  = function()
						local c = CM:GetBarConfig(barKey)
						if c and c.spells then
							c.spells[capID] = nil
							if CM.selectedRemoveSpell[barKey] == capID then
								CM.selectedRemoveSpell[barKey] = nil
							end
							CM:UpdateBar(barKey)
							CM:InsertOptions()
						end
					end,
				}
				order = order + 1
			end
		end
	end
	if not next(args) then
		args["empty"] = { order = 1, type = "description", name = "|cff808080No spells tracked on this bar yet.|r" }
	end
	return args
end

-- ============================================================================
-- Bar Options generator
-- ============================================================================
local ANCHOR_POINTS = {
	["TOPLEFT"] = "Top Left",    ["TOP"] = "Top",    ["TOPRIGHT"] = "Top Right",
	["LEFT"]    = "Left",        ["CENTER"] = "Center", ["RIGHT"] = "Right",
	["BOTTOMLEFT"] = "Bottom Left", ["BOTTOM"] = "Bottom", ["BOTTOMRIGHT"] = "Bottom Right",
}

local function GenerateBarOptions(barKey, isCustom)
	local function Cfg() return CM:GetBarConfig(barKey) end
	local function IsModuleDisabled() return not E.db.cooldownManager.enable end
	local function IsBarDisabled()
		local c = Cfg()
		return not (E.db.cooldownManager.enable and c and c.enable)
	end
	local function IsAttached()
		local c = Cfg(); return c and c.attachTo and c.attachTo ~= "NONE"
	end
	local function IsCustomAttach()
		local c = Cfg(); return IsAttached() and c.attachDirection == "CUSTOM"
	end

	local opts = {
		type = "group",
		name = function() local c = Cfg(); return c and c.name or barKey end,
		disabled = IsModuleDisabled,
		get  = function(info) local c = Cfg(); return c and c[info[#info]] end,
		set  = function(info, value)
			local c = Cfg()
			if c then c[info[#info]] = value; CM:UpdateAllBars() end
		end,
		args = {

			-- ── General ───────────────────────────────────────────────────────
			h_general = { order=1, type="header", name="General Bar Settings" },
			enable = {
				order=2, type="toggle", name="Enable Bar", width="full",
				disabled = IsModuleDisabled,
			},
			name = {
				order=3, type="input", name="Display Name",
				disabled=function() return IsBarDisabled() or not isCustom end,
			},
			trackType = {
				order=4, type="select", name="Tracking Type",
				disabled=IsBarDisabled,
				values={ ["COOLDOWN"]="Cooldowns", ["BUFF"]="Player Buffs" },
			},
			displayStyle = {
				order=5, type="select", name="Display Style",
				desc="Choose between Icon Grid or Draining Status Bars.",
				disabled=IsBarDisabled,
				values={ ["ICON"]="Icon Row", ["STATUSBAR"]="Draining Status Bars" },
			},

			-- ── Status Bar Options (Conditioned on displayStyle == STATUSBAR) ─
			h_statusbar = {
				order=8, type="header", name="Status Bar Style Options",
				disabled=function() local c = Cfg(); return IsBarDisabled() or not (c and c.displayStyle == "STATUSBAR") end,
			},
			barWidth = {
				order=9, type="range", name="Status Bar Width",
				min=80, max=400, step=5,
				disabled=function() local c = Cfg(); return IsBarDisabled() or not (c and c.displayStyle == "STATUSBAR") end,
				get=function() local c=Cfg(); return (c and c.barWidth) or 180 end,
				set=function(_, v) local c=Cfg(); if c then c.barWidth=v; CM:UpdateBar(barKey) end end,
			},
			barHeight = {
				order=10, type="range", name="Status Bar Height",
				min=12, max=50, step=1,
				disabled=function() local c = Cfg(); return IsBarDisabled() or not (c and c.displayStyle == "STATUSBAR") end,
				get=function() local c=Cfg(); return (c and c.barHeight) or 20 end,
				set=function(_, v) local c=Cfg(); if c then c.barHeight=v; CM:UpdateBar(barKey) end end,
			},
			statusBarTexture = {
				order=11, type="select", dialogControl="LSM30_Statusbar", name="Status Bar Texture",
				values=function() return E.LSM:HashTable("statusbar") end,
				disabled=function() local c = Cfg(); return IsBarDisabled() or not (c and c.displayStyle == "STATUSBAR") end,
				get=function() local c=Cfg(); return (c and c.statusBarTexture) or "ElvUI Norm" end,
				set=function(_, v) local c=Cfg(); if c then c.statusBarTexture=v; CM:UpdateBar(barKey) end end,
			},

			-- ── Layout & Grid ─────────────────────────────────────────────────
			h_layout = { order=15, type="header", name="Layout & Grid Options" },
			iconSize = {
				order=16, type="range", name="Icon Size",
				min=16, max=64, step=1,
				disabled=function() local c = Cfg(); return IsBarDisabled() or (c and c.displayStyle == "STATUSBAR") end,
			},
			iconScale = {
				order=17, type="range", name="Icon Scale",
				desc="Scale multiplier applied on top of Icon Size (1.0 = no change).",
				min=0.5, max=2.0, step=0.05,
				disabled=function() local c = Cfg(); return IsBarDisabled() or (c and c.displayStyle == "STATUSBAR") end,
			},
			spacing = {
				order=18, type="range", name="Spacing",
				min=-1, max=20, step=1,
				disabled=IsBarDisabled,
			},
			orientation = {
				order=19, type="select", name="Orientation",
				disabled=IsBarDisabled,
				values={ ["HORIZONTAL"]="Horizontal", ["VERTICAL"]="Vertical" },
			},
			growthDirection = {
				order=20, type="select", name="Growth Direction",
				disabled=IsBarDisabled,
				values=function()
					local c = Cfg()
					if c and c.orientation == "VERTICAL" then
						return { ["DOWN"]="Down", ["UP"]="Up" }
					else
						return { ["RIGHT"]="Right", ["LEFT"]="Left" }
					end
				end,
			},
			perLine = {
				order=21, type="range", name="Max Icons Per Row / Line",
				desc="Wraps extra icons into multiple lines/columns (0 = no wrapping).",
				min=0, max=24, step=1,
				disabled=function() local c = Cfg(); return IsBarDisabled() or (c and c.displayStyle == "STATUSBAR") end,
				get=function() local c=Cfg(); return (c and c.perLine) or 0 end,
				set=function(_, v) local c=Cfg(); if c then c.perLine=v; CM:UpdateBar(barKey) end end,
			},
			maxIcons = {
				order=22, type="range", name="Max Icons Total",
				min=1, max=24, step=1,
				disabled=IsBarDisabled,
			},

			-- ── Attach to Another Bar ─────────────────────────────────────────
			h_attach = { order=25, type="header", name="Anchor / Attach to Bar" },
			attachTo = {
				order=26, type="select", name="Attach To",
				desc="Snap this bar relative to another bar. Disables the free mover.",
				disabled=IsBarDisabled,
				values=function() return GetBarTargetList(barKey) end,
				get=function() local c=Cfg(); return (c and c.attachTo) or "NONE" end,
				set=function(_, v)
					local c=Cfg(); if c then c.attachTo=v; CM:UpdateAllBars() end
				end,
			},
			attachDirection = {
				order=27, type="select", name="Attach Direction",
				desc="Which side of the target bar this bar snaps to.",
				values={
					["ABOVE"]="Above", ["BELOW"]="Below",
					["LEFT"]="Left",   ["RIGHT"]="Right",
					["CUSTOM"]="Custom (use points below)",
				},
				disabled=function() return IsBarDisabled() or not IsAttached() end,
				get=function() local c=Cfg(); return (c and c.attachDirection) or "BELOW" end,
				set=function(_, v)
					local c=Cfg(); if c then c.attachDirection=v; CM:UpdateAllBars() end
				end,
			},
			attachPoint = {
				order=28, type="select", name="My Anchor Point",
				desc="Which point of THIS bar attaches to the parent. Custom mode only.",
				values=ANCHOR_POINTS,
				disabled=function() return IsBarDisabled() or not IsCustomAttach() end,
				get=function() local c=Cfg(); return (c and c.attachPoint) or "TOPLEFT" end,
				set=function(_, v)
					local c=Cfg(); if c then c.attachPoint=v; CM:UpdateAllBars() end
				end,
			},
			anchorPoint = {
				order=29, type="select", name="Parent Anchor Point",
				desc="Which point on the TARGET bar this bar attaches to. Custom mode only.",
				values=ANCHOR_POINTS,
				disabled=function() return IsBarDisabled() or not IsCustomAttach() end,
				get=function() local c=Cfg(); return (c and c.anchorPoint) or "BOTTOMLEFT" end,
				set=function(_, v)
					local c=Cfg(); if c then c.anchorPoint=v; CM:UpdateAllBars() end
				end,
			},
			xOffset = {
				order=30, type="range", name="X Offset",
				min=-300, max=300, step=1,
				disabled=function() return IsBarDisabled() or not IsAttached() end,
				get=function() local c=Cfg(); return (c and c.xOffset) or 0 end,
				set=function(_, v)
					local c=Cfg(); if c then c.xOffset=v; CM:UpdateAllBars() end
				end,
			},
			yOffset = {
				order=31, type="range", name="Y Offset",
				min=-300, max=300, step=1,
				disabled=function() return IsBarDisabled() or not IsAttached() end,
				get=function() local c=Cfg(); return (c and c.yOffset) or 0 end,
				set=function(_, v)
					local c=Cfg(); if c then c.yOffset=v; CM:UpdateAllBars() end
				end,
			},

			-- ── Behavior & Filters ────────────────────────────────────────────
			h_behavior = { order=35, type="header", name="Behavior & Filters" },
			hideEmpty = {
				order=36, type="toggle", name="Hide When Empty", width="full",
				disabled=IsBarDisabled,
			},
			showOnlyCombat = {
				order=37, type="toggle", name="Combat Only", width="full",
				disabled=IsBarDisabled,
			},
			showReady = {
				order=38, type="toggle", name="Show When Ready",
				desc="Keep icon visible even when the ability is not on cooldown.",
				width="full",
				disabled=IsBarDisabled,
			},
			sortByRemaining = {
				order=39, type="toggle", name="Sort by Remaining Time",
				desc="Icons with the shortest remaining cooldown appear first.",
				width="full",
				disabled=IsBarDisabled,
				get=function() local c=Cfg(); return c and c.sortByRemaining end,
				set=function(_, v)
					local c=Cfg(); if c then c.sortByRemaining=v; CM:UpdateBar(barKey) end
				end,
			},
			clickable = {
				order=40, type="toggle", name="Clickable Icons (Cast on Click)",
				desc="Left-clicking an icon will attempt to cast that spell.",
				width="full",
				disabled=IsBarDisabled,
				get=function() local c=Cfg(); return c and c.clickable end,
				set=function(_, v)
					local c=Cfg(); if c then c.clickable=v; CM:UpdateBar(barKey) end
				end,
			},

			-- ── Keybind Display ───────────────────────────────────────────────
			h_keybind = { order=42, type="header", name="Keybind Overlay" },
			showKeybind = {
				order=43, type="toggle", name="Show Keybind Text on Icons",
				desc="Display action bar keybind shortcut (e.g. S1, Q, F1) on top-left of icon.",
				width="full",
				disabled=IsBarDisabled,
				get=function() local c=Cfg(); return c and c.showKeybind end,
				set=function(_, v)
					local c=Cfg(); if c then c.showKeybind=v; CM:UpdateBar(barKey) end
				end,
			},
			keybindFontSize = {
				order=44, type="range", name="Keybind Font Size",
				min=6, max=16, step=1,
				disabled=function() local c = Cfg(); return IsBarDisabled() or not (c and c.showKeybind) end,
				get=function() local c=Cfg(); return (c and c.keybindFontSize) or 10 end,
				set=function(_, v)
					local c=Cfg(); if c then c.keybindFontSize=v; CM:UpdateBar(barKey) end
				end,
			},

			-- ── Icon Display & Timers ─────────────────────────────────────────
			h_icon = { order=45, type="header", name="Icon Display & Timers" },
			showCount = {
				order=46, type="toggle", name="Show Stack / Charge Count",
				desc="Display stack or charge numbers on the icon (bottom-right).",
				width="full",
				disabled=IsBarDisabled,
			},
			showSwipe = {
				order=47, type="toggle", name="Cooldown Spiral (Swipe)", width="full",
				disabled=IsBarDisabled,
			},
			showGCD = {
				order=48, type="toggle", name="Show Global Cooldown Sweep (GCD)",
				desc="Trigger cooldown spiral sweep during Global Cooldown (<= 1.5s).",
				width="full",
				disabled=IsBarDisabled,
				get=function() local c=Cfg(); return c and c.showGCD end,
				set=function(_, v)
					local c=Cfg(); if c then c.showGCD=v; CM:UpdateBar(barKey) end
				end,
			},
			showDuration = {
				order=49, type="toggle", name="Remaining Time Text", width="full",
				disabled=IsBarDisabled,
			},
			durationThreshold = {
				order=50, type="range", name="Show Timer Only When ≤ (seconds)",
				desc="Timer text is hidden while remaining time is above this value. 0 = always show.",
				min=0, max=180, step=1,
				disabled=function() local c=Cfg(); return IsBarDisabled() or not (c and c.showDuration) end,
				get=function() local c=Cfg(); return (c and c.durationThreshold) or 0 end,
				set=function(_, v)
					local c=Cfg(); if c then c.durationThreshold=v; CM:UpdateBar(barKey) end
				end,
			},
			colorDuration = {
				order=51, type="toggle", name="Color-Code Timer Text",
				desc="Green when plenty of time, yellow ≤ 5s, red ≤ 2s.",
				width="full",
				disabled=function() local c=Cfg(); return IsBarDisabled() or not (c and c.showDuration) end,
				get=function() local c=Cfg(); return c and c.colorDuration end,
				set=function(_, v)
					local c=Cfg(); if c then c.colorDuration=v; CM:UpdateBar(barKey) end
				end,
			},
			showLabel = {
				order=52, type="toggle", name="Show Spell Name Label",
				desc="Display the spell name in small text below each icon.",
				width="full",
				disabled=IsBarDisabled,
				get=function() local c=Cfg(); return c and c.showLabel end,
				set=function(_, v)
					local c=Cfg(); if c then c.showLabel=v; CM:UpdateBar(barKey) end
				end,
			},
			labelFontSize = {
				order=53, type="range", name="Label Font Size",
				min=6, max=14, step=1,
				disabled=function() local c=Cfg(); return IsBarDisabled() or not (c and c.showLabel) end,
				get=function() local c=Cfg(); return (c and c.labelFontSize) or 9 end,
				set=function(_, v)
					local c=Cfg(); if c then c.labelFontSize=v; CM:UpdateBar(barKey) end
				end,
			},

			-- ── Visual Effects & Audio ────────────────────────────────────────
			h_visual = { order=55, type="header", name="Visual Effects & Audio Alerts" },
			desaturateOnCD = {
				order=56, type="toggle", name="Desaturate on Cooldown",
				desc="Display icons in grayscale while on cooldown or buff is inactive.",
				width="full",
				disabled=IsBarDisabled,
			},
			glowOnReady = {
				order=57, type="toggle", name="Glow / Pulse Tracker Icon When Ready",
				desc="Flash a highlight on the tracker icon the moment it comes off cooldown.",
				width="full",
				disabled=IsBarDisabled,
				get=function() local c=Cfg(); return c and c.glowOnReady end,
				set=function(_, v)
					local c=Cfg(); if c then c.glowOnReady=v; CM:UpdateBar(barKey) end
				end,
			},
			glowActionButton = {
				order=58, type="toggle", name="Glow Action Bar Button When Ready",
				desc="Flash the actual ElvUI / Blizzard Action Bar button on screen.",
				width="full",
				disabled=IsBarDisabled,
				get=function() local c=Cfg(); return c and c.glowActionButton end,
				set=function(_, v)
					local c=Cfg(); if c then c.glowActionButton=v; CM:UpdateBar(barKey) end
				end,
			},
			playSoundOnReady = {
				order=59, type="toggle", name="Play Sound Alert When Ready",
				desc="Play an audio sound effect when spell CD finishes or buff is gained.",
				width="full",
				disabled=IsBarDisabled,
				get=function() local c=Cfg(); return c and c.playSoundOnReady end,
				set=function(_, v)
					local c=Cfg(); if c then c.playSoundOnReady=v; CM:UpdateBar(barKey) end
				end,
			},
			readySound = {
				order=60, type="select", name="Ready Sound Effect",
				values={
					["ReadyCheck"]   = "Ready Check",
					["LevelUp"]      = "Level Up",
					["RaidWarning"]  = "Raid Warning",
					["FlagCaptured"] = "PvP Flag",
					["AuctionOpen"]  = "Chime",
				},
				disabled=function() local c=Cfg(); return IsBarDisabled() or not (c and c.playSoundOnReady) end,
				get=function() local c=Cfg(); return (c and c.readySound) or "ReadyCheck" end,
				set=function(_, v)
					local c=Cfg(); if c then c.readySound=v; CM:UpdateBar(barKey) end
				end,
			},

			-- ── Opacity ───────────────────────────────────────────────────────
			h_alpha = { order=65, type="header", name="Opacity" },
			readyAlpha = {
				order=66, type="range", name="Ready Opacity",
				desc="Per-icon opacity when ability is ready.", min=0.1, max=1.0, step=0.05,
				disabled=IsBarDisabled,
			},
			cooldownAlpha = {
				order=67, type="range", name="Cooldown Opacity",
				desc="Per-icon opacity while on cooldown.", min=0.1, max=1.0, step=0.05,
				disabled=IsBarDisabled,
			},
			inactiveAlpha = {
				order=68, type="range", name="Inactive Opacity",
				desc="Per-icon opacity when buff is not active.", min=0.1, max=1.0, step=0.05,
				disabled=IsBarDisabled,
			},
			overrideAlpha = {
				order=69, type="toggle", name="Override with Flat Bar Alpha",
				desc="Ignore per-state opacity and apply a single flat alpha to all icons.",
				width="full",
				disabled=IsBarDisabled,
				get=function() local c=Cfg(); return c and c.overrideAlpha end,
				set=function(_, v)
					local c=Cfg(); if c then c.overrideAlpha=v; CM:UpdateBar(barKey) end
				end,
			},
			barAlpha = {
				order=70, type="range", name="Bar Alpha",
				desc="Flat alpha applied to all icons when Override is enabled.",
				min=0.1, max=1.0, step=0.05,
				disabled=function() local c=Cfg(); return IsBarDisabled() or not (c and c.overrideAlpha) end,
				get=function() local c=Cfg(); return (c and c.barAlpha) or 1.0 end,
				set=function(_, v)
					local c=Cfg(); if c then c.barAlpha=v; CM:UpdateBar(barKey) end
				end,
			},

			-- ── Background ────────────────────────────────────────────────────
			h_bg = { order=75, type="header", name="Background Panel" },
			showBackground = {
				order=76, type="toggle", name="Show Background",
				desc="Display a coloured panel behind the bar.",
				width="full",
				disabled=IsBarDisabled,
				get=function() local c=Cfg(); return c and c.showBackground end,
				set=function(_, v)
					local c=Cfg(); if c then c.showBackground=v; CM:UpdateBar(barKey) end
				end,
			},
			bgGroup = {
				order=77, type="group", inline=true, name="Background Color",
				disabled=function() local c=Cfg(); return IsBarDisabled() or not (c and c.showBackground) end,
				args={
					bgR = {
						order=1, type="range", name="Red",   min=0, max=1, step=0.01,
						get=function() local c=Cfg(); return (c and c.bgR) or 0 end,
						set=function(_, v) local c=Cfg(); if c then c.bgR=v; CM:UpdateBar(barKey) end end,
					},
					bgG = {
						order=2, type="range", name="Green", min=0, max=1, step=0.01,
						get=function() local c=Cfg(); return (c and c.bgG) or 0 end,
						set=function(_, v) local c=Cfg(); if c then c.bgG=v; CM:UpdateBar(barKey) end end,
					},
					bgB = {
						order=3, type="range", name="Blue",  min=0, max=1, step=0.01,
						get=function() local c=Cfg(); return (c and c.bgB) or 0 end,
						set=function(_, v) local c=Cfg(); if c then c.bgB=v; CM:UpdateBar(barKey) end end,
					},
					bgA = {
						order=4, type="range", name="Alpha", min=0, max=1, step=0.01,
						get=function() local c=Cfg(); return (c and c.bgA) or 0.5 end,
						set=function(_, v) local c=Cfg(); if c then c.bgA=v; CM:UpdateBar(barKey) end end,
					},
				},
			},

			-- ── Tooltip ───────────────────────────────────────────────────────
			h_tooltip = { order=80, type="header", name="Tooltip" },
			showTooltip = {
				order=81, type="toggle", name="Enable Tooltip",
				desc="Show a tooltip when hovering over icons.", width="full",
				disabled=IsBarDisabled,
			},
			showTooltipDesc = {
				order=82, type="toggle", name="Show Full Description",
				desc="Full spell details and description, or just name + rank.",
				width="full",
				disabled=function() local c=Cfg(); return IsBarDisabled() or not (c and c.showTooltip) end,
			},

			-- ── Spell Management ──────────────────────────────────────────────
			h_spells = { order=90, type="header", name="Spell & Item Management — Add" },
			addFromSpellbook = {
				order=91, type="select", name="Learned Spells", width="double",
				desc="Select a spell detected in your spellbook.",
				disabled=IsBarDisabled,
				values=function() return CM.spellNameCache end,
				get=function() return CM.selectedSpellbookSpell end,
				set=function(_, v) CM.selectedSpellbookSpell = v end,
			},
			btnAddSpellbook = {
				order=92, type="execute", name="Add Selected Spell",
				disabled=IsBarDisabled,
				func=function()
					if CM.selectedSpellbookSpell then
						local c = CM:GetBarConfig(barKey)
						if c then
							c.spells[CM.selectedSpellbookSpell] = true
							CM:UpdateBar(barKey)
							CM:InsertOptions()
						end
					end
				end,
			},
			addManualSpell = {
				order=93, type="input", name="Add by Spell or Item ID",
				desc="Enter any spell ID or item ID (trinkets, potions, healthstones).",
				disabled=IsBarDisabled,
				get=function() return CM.manualSpellInput or "" end,
				set=function(_, v) CM.manualSpellInput = v end,
			},
			btnAddManual = {
				order=94, type="execute", name="Add by ID",
				disabled=IsBarDisabled,
				func=function()
					local id = tonumber(CM.manualSpellInput)
					if id then
						local data = CM:GetSpellData(id)
						if data then
							local c = CM:GetBarConfig(barKey)
							if c then
								c.spells[id] = true
								CM.manualSpellInput = ""
								CM:UpdateBar(barKey)
								CM:InsertOptions()
							end
						end
					end
				end,
			},

			-- ── Remove ────────────────────────────────────────────────────────
			h_remove = { order=100, type="header", name="Spell Management — Remove" },
			removeSpellSelect = {
				order=101, type="select", name="Select Spell to Remove", width="double",
				disabled=IsBarDisabled,
				values=function()
					local list, c = {}, CM:GetBarConfig(barKey)
					if c and c.spells then
						for spellID, enabled in pairs(c.spells) do
							if enabled then
								local sid   = tonumber(spellID) or spellID
								local sData = CM:GetSpellData(sid)
								list[sid] = sData and format("%s%s [%s]", sData.name, (sData.rank and sData.rank ~= "") and (" (" .. sData.rank .. ")") or "", tostring(sid)) or tostring(sid)
							end
						end
					end
					return list
				end,
				get=function() return CM.selectedRemoveSpell[barKey] end,
				set=function(_, v) CM.selectedRemoveSpell[barKey] = v end,
			},
			btnRemoveSelected = {
				order=102, type="execute", name="Remove Selected Spell",
				disabled=IsBarDisabled,
				func=function()
					local target = CM.selectedRemoveSpell[barKey]
					if target then
						local c = CM:GetBarConfig(barKey)
						if c and c.spells then
							c.spells[target] = nil
							CM.selectedRemoveSpell[barKey] = nil
							CM:UpdateBar(barKey)
							CM:InsertOptions()
						end
					end
				end,
			},
			btnRemoveAll = {
				order=103, type="execute", name="|cffff5555Remove All Spells|r",
				desc="Remove every tracked spell from this bar at once.",
				disabled=IsBarDisabled,
				confirm=true, confirmText="Are you sure you want to remove ALL spells from this bar?",
				func=function()
					local c = CM:GetBarConfig(barKey)
					if c then
						wipe(c.spells)
						CM.selectedRemoveSpell[barKey] = nil
						CM:UpdateBar(barKey)
						CM:InsertOptions()
					end
				end,
			},

			-- ── Active List ───────────────────────────────────────────────────
			h_active = { order=110, type="header", name="Active Spells on this Bar" },
			spellsList = {
				order=111, type="group", inline=true, name=" ",
				disabled=IsBarDisabled,
				args=BuildActiveSpellList(barKey),
			},
		},
	}

	-- Danger Zone for custom bars
	if isCustom then
		opts.args.h_danger = { order=120, type="header", name="Danger Zone" }
		opts.args.deleteBar = {
			order=121, type="execute", name="|cffff3333Delete this Bar|r",
			desc="Permanently deletes this custom bar.",
			disabled=IsBarDisabled,
			confirm=true, confirmText="Are you sure you want to delete this custom bar?",
			func=function()
				if E.db.cooldownManager.customBars[barKey] then
					E.db.cooldownManager.customBars[barKey] = nil
					if CM.bars[barKey] then
						CM.bars[barKey]:Hide()
						CM:DisableMover(barKey)
						CM.bars[barKey] = nil
					end
					CM:InsertOptions()
				end
			end,
		}
	end

	return opts
end

-- ============================================================================
-- Inject into ElvUI Options
-- ============================================================================
function CM:InsertOptions()
	if not E.Options or not E.Options.args then return end

	local function IsModuleDisabled()
		return not E.db.cooldownManager.enable
	end

	E.Options.args.cooldownManager = {
		order       = 6,
		type        = "group",
		name        = Clr("Cooldown Manager"),
		childGroups = "tab",
		get = function(info) return E.db.cooldownManager[info[#info]] end,
		set = function(info, value)
			E.db.cooldownManager[info[#info]] = value
			CM:UpdateAllBars()
		end,
		args = {
			-- General tab --------------------------------------------------------
			generalTab = {
				order = 1,
				type  = "group",
				name  = "General",
				args  = {
					enable = {
						order=1, type="toggle", name="Enable Module", width="full",
						disabled=false,
					},
					onlyMaxRank = {
						order=2, type="toggle", name="Filter to Max Spell Rank",
						desc="Only show the highest learned rank of each spell in dropdowns.",
						width="full",
						disabled=IsModuleDisabled,
						get=function() return E.db.cooldownManager.onlyMaxRank end,
						set=function(_, v)
							E.db.cooldownManager.onlyMaxRank = v
							CM:ScanSpellbook()
						end,
					},
					fontGroup = {
						order=3, type="group", inline=true, name="Global Typography",
						disabled=IsModuleDisabled,
						args={
							font = {
								order=1, type="select", dialogControl="LSM30_Font", name="Font",
								values=function() return E.LSM:HashTable("font") end,
							},
							fontSize = {
								order=2, type="range", name="Font Size", min=8, max=24, step=1,
							},
							fontOutline = {
								order=3, type="select", name="Font Outline",
								values={
									["NONE"]="None", ["OUTLINE"]="Outline",
									["MONOCHROMEOUTLINE"]="Monochrome",
								},
							},
						},
					},
					rescanSpellbook = {
						order=4, type="execute", name="Rescan Spellbook",
						desc="Force-rescan to detect newly learned spells or talent changes.",
						disabled=IsModuleDisabled,
						func=function()
							CM:ScanSpellbook()
							E:Print("|cffb366ffCooldownManager:|r Spellbook scanned.")
						end,
					},
					reloadUI = {
						order=5, type="execute", name="Reload UI",
						desc="Reload the interface to apply any pending layout changes.",
						func=function() ReloadUI() end,
					},
				},
			},

			-- Predefined bars
			barCooldowns = GenerateBarOptions("cooldowns", false),
			barUtilities = GenerateBarOptions("utilities", false),
			barBuffs     = GenerateBarOptions("buffs",     false),

			-- Screen Overlays tab ------------------------------------------------
			overlaysTab = {
				order = 12,
				type  = "group",
				name  = "Screen Overlays",
				disabled = IsModuleDisabled,
				args  = {
					raidBuffsHeader = { order=1, type="header", name="Missing Raid Buffs Checklist" },
					rbEnable = {
						order=2, type="toggle", name="Enable Missing Raid Buffs",
						get=function() return E.db.cooldownManager.overlays.raidBuffs.enable end,
						set=function(_, v) E.db.cooldownManager.overlays.raidBuffs.enable=v; if CM.Overlays then CM.Overlays:UpdateRaidBuffs() end end,
					},
					rbHideCombat = {
						order=3, type="toggle", name="Hide Checklist in Combat",
						get=function() return E.db.cooldownManager.overlays.raidBuffs.hideInCombat end,
						set=function(_, v) E.db.cooldownManager.overlays.raidBuffs.hideInCombat=v; if CM.Overlays then CM.Overlays:UpdateRaidBuffs() end end,
					},
					rbIconSize = {
						order=4, type="range", name="Buff Icon Size", min=16, max=48, step=1,
						get=function() return E.db.cooldownManager.overlays.raidBuffs.iconSize end,
						set=function(_, v) E.db.cooldownManager.overlays.raidBuffs.iconSize=v; if CM.Overlays then CM.Overlays:UpdateRaidBuffs() end end,
					},

					aggroHeader = { order=10, type="header", name="Aggro Alert ('AGGRO ON YOU')" },
					aggroEnable = {
						order=11, type="toggle", name="Enable Aggro Alert",
						get=function() return E.db.cooldownManager.overlays.aggroAlert.enable end,
						set=function(_, v) E.db.cooldownManager.overlays.aggroAlert.enable=v; if CM.Overlays then CM.Overlays:UpdateAggro() end end,
					},
					aggroFontSize = {
						order=12, type="range", name="Aggro Text Size", min=14, max=36, step=1,
						get=function() return E.db.cooldownManager.overlays.aggroAlert.fontSize end,
						set=function(_, v) E.db.cooldownManager.overlays.aggroAlert.fontSize=v; if CM.Overlays then CM.Overlays:UpdateAggro() end end,
					},

					rangeHeader = { order=20, type="header", name="Range Alert ('OUT OF RANGE')" },
					rangeEnable = {
						order=21, type="toggle", name="Enable Range Alert",
						get=function() return E.db.cooldownManager.overlays.rangeAlert.enable end,
						set=function(_, v) E.db.cooldownManager.overlays.rangeAlert.enable=v; if CM.Overlays then CM.Overlays:UpdateRange() end end,
					},
					rangeSpellCheck = {
						order=22, type="input", name="Spell to Test Range Against",
						desc="Enter exact spell name to test range against your target.",
						get=function() return E.db.cooldownManager.overlays.rangeAlert.spellCheck end,
						set=function(_, v) E.db.cooldownManager.overlays.rangeAlert.spellCheck=v; if CM.Overlays then CM.Overlays:UpdateRange() end end,
					},
				},
			},

			-- UnitFrame HoT Indicators tab ---------------------------------------
			unitFrameWatchTab = {
				order = 13,
				type  = "group",
				name  = "UnitFrame Indicators",
				disabled = IsModuleDisabled,
				args  = {
					header = { order=1, type="header", name="HoT & Buff Indicators on ElvUI UnitFrames" },
					enable = {
						order=2, type="toggle", name="Enable UnitFrame Indicators",
						get=function() return E.db.cooldownManager.unitFrameWatch.enable end,
						set=function(_, v) E.db.cooldownManager.unitFrameWatch.enable=v; if CM.UnitFrameWatch then CM.UnitFrameWatch:Update() end end,
					},
					desc = {
						order=3, type="description",
						name="Displays your own HoTs and buff indicators directly on ElvUI Party and Raid UnitFrames with customizable anchor points, icons, and timers.",
					},
				},
			},

			-- Personal Power Bar tab ---------------------------------------------
			powerBarsTab = {
				order = 14,
				type  = "group",
				name  = "Power Bar",
				disabled = IsModuleDisabled,
				args  = {
					header = { order=1, type="header", name="Personal Power Bar" },
					enable = {
						order=2, type="toggle", name="Enable Personal Power Bar",
						desc="Show your primary resource (mana/rage/energy/runic power/focus/combo points) as a draggable colour-coded bar.",
						width="full",
						get=function() return E.db.cooldownManager.powerBars.enable end,
						set=function(_, v) E.db.cooldownManager.powerBars.enable=v; if CM.PowerBars then CM.PowerBars:Update() end end,
					},
					desc = {
						order=3, type="description",
						name="A single bar for your own resource. MANA=blue, RAGE=red, ENERGY=yellow, RUNIC_POWER=cyan, FOCUS=purple, COMBO_POINTS=orange. Drag it using the ElvUI mover.",
					},

					dimGroup = {
						order=10, type="group", inline=true, name="Dimensions",
						args={
							barWidth = {
								order=1, type="range", name="Bar Width", min=60, max=500, step=1,
								get=function() return E.db.cooldownManager.powerBars.barWidth end,
								set=function(_, v) E.db.cooldownManager.powerBars.barWidth=v; if CM.PowerBars then CM.PowerBars:Update() end end,
							},
							barHeight = {
								order=2, type="range", name="Bar Height", min=8, max=40, step=1,
								get=function() return E.db.cooldownManager.powerBars.barHeight end,
								set=function(_, v) E.db.cooldownManager.powerBars.barHeight=v; if CM.PowerBars then CM.PowerBars:Update() end end,
							},
						},
					},

					styleGroup = {
						order=11, type="group", inline=true, name="Style",
						args={
							texture = {
								order=1, type="select", dialogControl="LSM30_Statusbar", name="Status Bar Texture",
								values=function() return E.LSM:HashTable("statusbar") end,
								get=function() return E.db.cooldownManager.powerBars.texture end,
								set=function(_, v) E.db.cooldownManager.powerBars.texture=v; if CM.PowerBars then CM.PowerBars:Update() end end,
							},
							showText = {
								order=2, type="toggle", name="Show Value Text",
								desc="Display current/max (or combo points) on the bar.",
								width="full",
								get=function() return E.db.cooldownManager.powerBars.showText end,
								set=function(_, v) E.db.cooldownManager.powerBars.showText=v; if CM.PowerBars then CM.PowerBars:Update() end end,
							},
							hideInCombat = {
								order=3, type="toggle", name="Hide in Combat",
								desc="Hide the bar while in combat.",
								width="full",
								get=function() return E.db.cooldownManager.powerBars.hideInCombat end,
								set=function(_, v) E.db.cooldownManager.powerBars.hideInCombat=v; if CM.PowerBars then CM.PowerBars:Update() end end,
							},
						},
					},
				},
			},

			-- Create custom bar tab
			customBarsTab = {
				order = 15,
				type  = "group",
				name  = "Create New Bar",
				disabled = IsModuleDisabled,
				args  = {
					header = { order=1, type="header", name="Add Custom Bar" },
					newBarName = {
						order=2, type="input", name="Bar Name",
						get=function() return CM.newBarNameInput or "" end,
						set=function(_, v) CM.newBarNameInput = v end,
					},
					newBarType = {
						order=3, type="select", name="Tracking Type",
						values={ ["COOLDOWN"]="Cooldowns", ["BUFF"]="Player Buffs" },
						get=function() return CM.newBarTypeInput or "COOLDOWN" end,
						set=function(_, v) CM.newBarTypeInput = v end,
					},
					newBarStyle = {
						order=4, type="select", name="Display Style",
						values={ ["ICON"]="Icon Row", ["STATUSBAR"]="Draining Status Bars" },
						get=function() return CM.newBarStyleInput or "ICON" end,
						set=function(_, v) CM.newBarStyleInput = v end,
					},
					createBarBtn = {
						order=5, type="execute", name="Create Bar",
						func=function()
							local name = CM.newBarNameInput
							if name and strtrim(name) ~= "" then
								local key = "custom_" .. tostring(GetTime()):gsub("%.", "")
								E.db.cooldownManager.customBars[key] = {
									name              = name,
									enable            = true,
									displayStyle      = CM.newBarStyleInput or "ICON",
									barWidth          = 180,
									barHeight         = 20,
									statusBarTexture  = "ElvUI Norm",
									iconSize          = 32,
									iconScale         = 1.0,
									spacing           = 4,
									orientation       = "HORIZONTAL",
									growthDirection   = "RIGHT",
									maxIcons          = 10,
									perLine           = 0,
									hideEmpty         = false,
									showOnlyCombat    = false,
									showReady         = true,
									showCount         = true,
									showSwipe         = true,
									showGCD           = true,
									showDuration      = true,
									durationThreshold = 0,
									colorDuration     = false,
									showKeybind       = true,
									keybindFontSize   = 10,
									showLabel         = false,
									labelFontSize     = 9,
									sortByRemaining   = false,
									desaturateOnCD    = true,
									glowOnReady       = false,
									glowActionButton  = false,
									playSoundOnReady  = false,
									readySound        = "ReadyCheck",
									overrideAlpha     = false,
									barAlpha          = 1.0,
									cooldownAlpha     = 0.8,
									readyAlpha        = 1.0,
									inactiveAlpha     = 0.4,
									showBackground    = false,
									bgR=0, bgG=0, bgB=0, bgA=0.5,
									showTooltip       = true,
									showTooltipDesc   = true,
									clickable         = false,
									trackType         = CM.newBarTypeInput or "COOLDOWN",
									attachTo          = "NONE",
									attachDirection   = "BELOW",
									attachPoint       = "TOPLEFT",
									anchorPoint       = "BOTTOMLEFT",
									xOffset           = 0,
									yOffset           = -4,
									spells            = {},
								}
								CM.newBarNameInput = ""
								CM.newBarTypeInput = "COOLDOWN"
								CM.newBarStyleInput = "ICON"
								CM:ConstructBar(key, E.db.cooldownManager.customBars[key])
								CM:InsertOptions()
								CM:UpdateBar(key)
							end
						end,
					},
				},
			},
		},
	}

	-- Tabs for existing custom bars
	if E.db.cooldownManager.customBars then
		local idx = 20
		for barKey in pairs(E.db.cooldownManager.customBars) do
			E.Options.args.cooldownManager.args["custom_" .. barKey] = GenerateBarOptions(barKey, true)
			E.Options.args.cooldownManager.args["custom_" .. barKey].order = idx
			idx = idx + 1
		end
	end

	if E.Libs and E.Libs.AceConfigRegistry then
		E.Libs.AceConfigRegistry:NotifyChange("ElvUI")
	end
end

if EP then
	EP:RegisterPlugin(addonName, function() CM:InsertOptions() end)
end
