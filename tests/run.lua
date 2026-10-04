-- Tests hors jeu : lancer depuis la racine de l'addon avec `lua tests/run.lua`.
GetLocale = function() return "enUS" end
local ns = {}
for _, file in ipairs({ "Locales/Locale.lua", "Data/Spells.lua", "Core/Decision.lua", "Core/Auras.lua", "Core/Config.lua" }) do
    assert(loadfile(file))("FriendlyBuffer", ns)
end

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("ECHEC  " .. name .. "\n       " .. tostring(err))
    end
end

local function eq(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s : attendu %s, obtenu %s", label or "valeur", tostring(expected), tostring(actual)), 2)
    end
end

local function knowsAll() return true end
local function knows(set) return function(id) return set[id] == true end end
local SETTINGS = { thresholdShort = 60, thresholdLong = 180, groupBuffs = false }

local function ctxFor(class, targetClass, overrides)
    overrides = overrides or {}
    return {
        isKnown = overrides.isKnown or knowsAll,
        settings = overrides.settings or SETTINGS,
        priorities = ns.Spells[class].defaults[targetClass],
    }
end

local function aura(family, power, opts)
    opts = opts or {}
    return { family = family, power = power, mine = opts.mine or false, remaining = opts.remaining, duration = opts.duration or 0 }
end

-- BestRank -------------------------------------------------------------------

test("BestRank : écart de 10 niveaux", function()
    local rank = ns.Decision.BestRank(ns.Spells.PRIEST.families.fortitude.ranks, knowsAll, 20)
    eq(rank.id, 1245, "rang pour niveau 20") -- niveau requis 24 <= 30
end)

test("BestRank : niveau inconnu = 60", function()
    local rank = ns.Decision.BestRank(ns.Spells.PRIEST.families.fortitude.ranks, knowsAll, -1)
    eq(rank.id, 10938)
end)

test("BestRank : sort non connu ignoré", function()
    local rank = ns.Decision.BestRank(ns.Spells.PRIEST.families.fortitude.ranks, knows({ [1243] = true, [1244] = true }), 60)
    eq(rank.id, 1244)
end)

test("BestRank : aucun rang utilisable", function()
    local rank = ns.Decision.BestRank(ns.Spells.PRIEST.families.spirit.ranks, knowsAll, 10)
    eq(rank, nil)
end)

-- Cumulatif ------------------------------------------------------------------

local PRIEST = ns.Spells.PRIEST

test("Prêtre : guerrier sans buff -> robustesse manquante", function()
    local need = ns.Decision.Evaluate(PRIEST, ctxFor("PRIEST", "WARRIOR"), { level = 60, auras = {} })
    eq(need.family, "fortitude"); eq(need.reason, "missing"); eq(need.single.id, 10938)
end)

test("Prêtre : guerrier avec robustesse -> rien (esprit désactivé)", function()
    local need = ns.Decision.Evaluate(PRIEST, ctxFor("PRIEST", "WARRIOR"),
        { level = 60, auras = { aura("fortitude", 6, { remaining = 1500, duration = 1800 }) } })
    eq(need, nil)
end)

test("Prêtre : mage avec robustesse -> esprit divin manquant", function()
    local need = ns.Decision.Evaluate(PRIEST, ctxFor("PRIEST", "MAGE"),
        { level = 60, auras = { aura("fortitude", 6, { remaining = 1500, duration = 1800 }) } })
    eq(need.family, "spirit"); eq(need.reason, "missing")
end)

test("Prêtre : robustesse qui expire", function()
    local need = ns.Decision.Evaluate(PRIEST, ctxFor("PRIEST", "WARRIOR"),
        { level = 60, auras = { aura("fortitude", 6, { remaining = 100, duration = 1800 }) } })
    eq(need.reason, "expiring"); eq(need.remaining, 100)
end)

test("Seuil court pour les buffs de 10 min", function()
    local need = ns.Decision.Evaluate(PRIEST, ctxFor("PRIEST", "WARRIOR"),
        { level = 60, auras = { aura("fortitude", 6, { remaining = 100, duration = 600 }) } })
    eq(need, nil)
end)

test("Durée inconnue -> jamais expirant", function()
    local need = ns.Decision.Evaluate(PRIEST, ctxFor("PRIEST", "WARRIOR"),
        { level = 60, auras = { aura("fortitude", 6) } })
    eq(need, nil)
end)

test("Rang inférieur détecté", function()
    local need = ns.Decision.Evaluate(PRIEST, ctxFor("PRIEST", "WARRIOR"),
        { level = 60, auras = { aura("fortitude", 4, { remaining = 1500, duration = 1800 }) } })
    eq(need.reason, "lower"); eq(need.single.id, 10938)
end)

test("Rang inférieur ignoré si la cible est trop bas niveau", function()
    local need = ns.Decision.Evaluate(PRIEST, ctxFor("PRIEST", "WARRIOR"),
        { level = 20, auras = { aura("fortitude", 3, { remaining = 1500, duration = 1800 }) } })
    eq(need, nil)
end)

test("Manquant prioritaire sur expirant", function()
    local need = ns.Decision.Evaluate(PRIEST, ctxFor("PRIEST", "MAGE"),
        { level = 60, auras = { aura("fortitude", 6, { remaining = 100, duration = 1800 }) } })
    eq(need.family, "spirit"); eq(need.reason, "missing")
end)

test("Buff de groupe : membre du groupe avec option active", function()
    local ctx = ctxFor("PRIEST", "WARRIOR", { settings = { thresholdShort = 60, thresholdLong = 180, groupBuffs = true } })
    local need = ns.Decision.Evaluate(PRIEST, ctx, { level = 60, isGroup = true, auras = {} })
    eq(need.group.id, 21564)
end)

test("Buff de groupe : jamais pour un inconnu", function()
    local ctx = ctxFor("PRIEST", "WARRIOR", { settings = { thresholdShort = 60, thresholdLong = 180, groupBuffs = true } })
    local need = ns.Decision.Evaluate(PRIEST, ctx, { level = 60, isGroup = false, auras = {} })
    eq(need.group, nil)
end)

test("Buff de groupe : option désactivée", function()
    local need = ns.Decision.Evaluate(PRIEST, ctxFor("PRIEST", "WARRIOR"), { level = 60, isGroup = true, auras = {} })
    eq(need.group, nil)
end)

test("Mage : guerrier ignoré par défaut", function()
    local need = ns.Decision.Evaluate(ns.Spells.MAGE, ctxFor("MAGE", "WARRIOR"), { level = 60, auras = {} })
    eq(need, nil)
end)

test("Druide : épines sur guerrier après la marque", function()
    local need = ns.Decision.Evaluate(ns.Spells.DRUID, ctxFor("DRUID", "WARRIOR"),
        { level = 60, auras = { aura("mark", 7, { remaining = 1500, duration = 1800 }) } })
    eq(need.family, "thorns")
end)

-- Exclusif (paladin) ---------------------------------------------------------

local PALADIN = ns.Spells.PALADIN

test("Paladin : prêtre sans bénédiction -> sagesse", function()
    local need = ns.Decision.Evaluate(PALADIN, ctxFor("PALADIN", "PRIEST"), { level = 60, auras = {} })
    eq(need.family, "wisdom"); eq(need.reason, "missing")
end)

test("Paladin : sagesse d'un autre paladin -> rois", function()
    local need = ns.Decision.Evaluate(PALADIN, ctxFor("PALADIN", "PRIEST"),
        { level = 60, auras = { aura("wisdom", 6, { remaining = 200, duration = 300 }) } })
    eq(need.family, "kings")
end)

test("Paladin : ma sagesse en place -> rien", function()
    local need = ns.Decision.Evaluate(PALADIN, ctxFor("PALADIN", "PRIEST"),
        { level = 60, auras = { aura("wisdom", 6, { mine = true, remaining = 200, duration = 300 }) } })
    eq(need, nil)
end)

test("Paladin : ma sagesse expire -> la renouveler", function()
    local need = ns.Decision.Evaluate(PALADIN, ctxFor("PALADIN", "PRIEST"),
        { level = 60, auras = { aura("wisdom", 6, { mine = true, remaining = 30, duration = 300 }) } })
    eq(need.family, "wisdom"); eq(need.reason, "expiring")
end)

test("Paladin : ma bénédiction désactivée pour cette classe -> remplacée", function()
    local need = ns.Decision.Evaluate(PALADIN, ctxFor("PALADIN", "PRIEST"),
        { level = 60, auras = { aura("might", 7, { mine = true, remaining = 200, duration = 300 }) } })
    eq(need.family, "wisdom"); eq(need.reason, "missing")
end)

test("Paladin : rois non connu -> salut", function()
    local known = {}
    for _, fam in pairs(PALADIN.families) do for _, rk in ipairs(fam.ranks) do known[rk.id] = true end end
    known[20217] = nil
    local need = ns.Decision.Evaluate(PALADIN, ctxFor("PALADIN", "PRIEST", { isKnown = knows(known) }),
        { level = 60, auras = { aura("wisdom", 6) } })
    eq(need.family, "salvation")
end)

test("Paladin : tout est déjà posé par d'autres -> rien", function()
    local auras = { aura("wisdom", 6), aura("kings", 1), aura("salvation", 1), aura("light", 3) }
    local need = ns.Decision.Evaluate(PALADIN, ctxFor("PALADIN", "PRIEST"), { level = 60, auras = auras })
    eq(need, nil)
end)

test("Paladin : bénédiction supérieure en version groupe", function()
    local ctx = ctxFor("PALADIN", "WARRIOR", { settings = { thresholdShort = 60, thresholdLong = 180, groupBuffs = true } })
    local need = ns.Decision.Evaluate(PALADIN, ctx, { level = 60, isGroup = true, auras = {} })
    eq(need.family, "might"); eq(need.group.id, 25916)
end)

-- Auras ----------------------------------------------------------------------

test("Auras.Normalize : spellId reconnu", function()
    local list = ns.Auras.Normalize({
        { spellId = 25290, sourceUnit = "player", duration = 300, expirationTime = 1100 },
        { spellId = 99999, name = "Autre chose", duration = 10, expirationTime = 1005 },
    }, 1000)
    eq(#list, 1); eq(list[1].family, "wisdom"); eq(list[1].power, 6); eq(list[1].mine, true); eq(list[1].remaining, 100)
end)

test("Auras.Normalize : version groupe = même puissance", function()
    local list = ns.Auras.Normalize({ { spellId = 21564, sourceUnit = "party1", duration = 3600, expirationTime = 0 } }, 1000)
    eq(list[1].family, "fortitude"); eq(list[1].power, 6); eq(list[1].mine, false); eq(list[1].remaining, nil)
end)

test("Auras.Normalize : secours par nom", function()
    ns.Auras.NameIndex["Marque du fauve"] = "mark"
    local list = ns.Auras.Normalize({ { name = "Marque du fauve", duration = 0 } }, 1000)
    eq(list[1].family, "mark"); eq(list[1].power, nil)
end)

-- Config / tri ---------------------------------------------------------------

test("MergePriorities : ordre gardé, inconnus retirés, nouveaux ajoutés", function()
    local merged = ns.Config.MergePriorities(
        { { key = "spirit", enabled = false }, { key = "bidon", enabled = true }, { key = "fortitude", enabled = true } },
        PRIEST.defaults.MAGE, PRIEST.families)
    eq(#merged, 3); eq(merged[1].key, "spirit"); eq(merged[1].enabled, false)
    eq(merged[2].key, "fortitude"); eq(merged[3].key, "shadowprot")
end)

test("Config.Load : valeurs par défaut", function()
    local db = ns.Config.Load({ displayMode = "info" }, PRIEST)
    eq(db.displayMode, "info"); eq(db.groupBuffs, false); eq(#db.priorities.WARRIOR, 3)
end)

test("Compare : urgence, groupe, nom", function()
    local rows = {
        { name = "Zed", isGroup = true, need = { reason = "lower" } },
        { name = "Bob", isGroup = false, need = { reason = "missing" } },
        { name = "Al", isGroup = true, need = { reason = "missing" } },
    }
    table.sort(rows, ns.Decision.Compare)
    eq(rows[1].name, "Al"); eq(rows[2].name, "Bob"); eq(rows[3].name, "Zed")
end)

test("Compare : joueurs derrière un obstacle en dernier", function()
    local rows = {
        { name = "Al", isGroup = true, blocked = true, need = { reason = "missing" } },
        { name = "Zed", isGroup = false, need = { reason = "lower" } },
    }
    table.sort(rows, ns.Decision.Compare)
    eq(rows[1].name, "Zed"); eq(rows[2].name, "Al")
end)

test("Config.Load : style des noms par défaut", function()
    local db = ns.Config.Load({}, PRIEST)
    eq(db.plateFont, "friz"); eq(db.plateFontSize, 12); eq(db.plateOutline, "none"); eq(db.plateShadow, true)
end)

test("Config.Load : ancien mode « range » converti", function()
    local db = ns.Config.Load({ displayMode = "range" }, PRIEST)
    eq(db.displayMode, "info")
end)

-- Traductions --------------------------------------------------------------

local SOURCES = { "FriendlyBuffer.lua", "Core/Config.lua", "Core/Scanner.lua", "UI/MainFrame.lua", "UI/Options.lua", "UI/Nameplates.lua" }
local LOCALES = { frFR = "frFR", deDE = "deDE", esES = "esES", esMX = "esES", itIT = "itIT", ptBR = "ptBR",
    ruRU = "ruRU", koKR = "koKR", zhCN = "zhCN", zhTW = "zhTW" }

local usedKeys = {}
for _, file in ipairs(SOURCES) do
    local src = assert(io.open(file)):read("*a")
    for key in src:gmatch('L%["(.-)"%]') do usedKeys[key] = true end
end

for locale, file in pairs(LOCALES) do
    test("Traduction " .. locale .. " : complète et sans clé inutile", function()
        GetLocale = function() return locale end
        local lns = {}
        assert(loadfile("Locales/Locale.lua"))("FriendlyBuffer", lns)
        assert(loadfile("Locales/" .. file .. ".lua"))("FriendlyBuffer", lns)
        local translated = rawget(lns, "L")
        for key in pairs(usedKeys) do
            if rawget(translated, key) == nil then error("clé non traduite : " .. key) end
        end
        for key, value in pairs(translated) do
            if not usedKeys[key] then error("clé inutilisée : " .. key) end
            -- Mêmes %s / %d dans le même ordre que l'anglais (string.format n'est pas positionnel).
            if key:gsub("[^%%]", ""):len() > 0 then
                local function specs(s) local out = {} for spec in s:gmatch("%%[sd]") do out[#out + 1] = spec end return table.concat(out) end
                if specs(key) ~= specs(value) then error("formats différents pour : " .. key) end
            end
        end
    end)
end
GetLocale = function() return "enUS" end

test("Langue non traduite : texte anglais", function()
    eq(ns.L["Reset"], "Reset")
end)

print(string.format("%d réussis, %d échoués", passed, failed))
if failed > 0 then os.exit(1) end
