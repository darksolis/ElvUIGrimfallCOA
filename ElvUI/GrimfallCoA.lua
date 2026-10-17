-- CoA compatibility: retain server class tokens; do not impersonate a stock class.
local function RegisterClass(token)
    if type(token) ~= "string" or token == "" then return end
    if not RAID_CLASS_COLORS[token] then
        local c = CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[token]
        RAID_CLASS_COLORS[token] = {r = c and c.r or 0.65, g = c and c.g or 0.75, b = c and c.b or 1}
    end
end
for token in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do RegisterClass(token) end
for token in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do RegisterClass(token) end
RegisterClass(select(2, UnitClass("player")))
