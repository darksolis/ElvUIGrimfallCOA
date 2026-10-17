ElvUI Grimfall CoA compatibility patch 1

INSTALL
Exit WoW completely. Back up Interface/AddOns and WTF first.
Replace the supplied addon folders in Interface/AddOns. Do not nest them
inside an ElvUIGrimfall folder. Keep WTF and your saved profiles.
First test with only ElvUI and ElvUI_OptionsUI enabled; leave the bundled
optional ElvUI plugins disabled until the core frames and profiles work.

CHECK IN GAME
Player/target/pet frames; target another custom class; create a temporary
profile, switch to it, switch back, and open /ec again. Test party/raid
frames and class sorting. Try outside combat.
For errors: /console scriptErrors 1 then /reload, reproduce once and
send the FIRST full error, your class name, and a screenshot.

CHANGES
Unknown custom class tokens retain identity, get a neutral color only when
no server color exists, and get empty range/buff defaults rather than guessed
spell lists. Guard unknown class role/spec lookups and missing talent points.
Handle string or boolean group role APIs. Stop forcing runes on every class;
construct six rune widgets only for DEATHKNIGHT or primary rune power type.
Include registered custom classes in unit-frame class sorting.

LIMITATIONS
Static Lua compilation and mocked regression checks do not simulate the
Grimfall client. This is a first compatibility build, not a claim of full
21-class certification. Primary power bars are retained; specialized custom
class resources and class spell indicators need server API details and live
testing. This CoA build replaces the classless-only always-runes behavior.
