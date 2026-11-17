-- Tests hors jeu : lancer depuis la racine de l'addon avec `lua tests/run.lua`.
GetLocale = function() return "enUS" end
local ns = {}
for _, file in ipairs({ "Locales/Locale.lua", "Data/Spells.lua", "Core/Decision.lua", "Core/Auras.lua", "Core/Config.lua", "Core/Specs.lua", "Core/Coord.lua" }) do
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

test("SetFamilyForAll : tous les profils, autres familles intactes", function()
    local db = ns.Config.Load({}, PRIEST)
    ns.Config.SetFamilyForAll(db, "shadowprot", true)
    for _, profile in ipairs(ns.TARGET_PROFILES) do
        for _, entry in ipairs(db.priorities[profile]) do
            if entry.key == "shadowprot" then eq(entry.enabled, true) end
        end
    end
    eq(db.priorities.WARRIOR[2].key, "spirit"); eq(db.priorities.WARRIOR[2].enabled, false)
end)

test("FamilyEnabledForAll : vrai seulement si activée partout", function()
    local db = ns.Config.Load({}, PRIEST)
    eq(ns.Config.FamilyEnabledForAll(db, "spirit"), false) -- coupée pour les classes sans mana
    ns.Config.SetFamilyForAll(db, "spirit", true)
    eq(ns.Config.FamilyEnabledForAll(db, "spirit"), true)
    ns.Config.SetFamilyForAll(db, "innerfire", false)
    eq(db.personal[1].enabled, false, "buff personnel")
end)

test("Buffs exclusifs : seul le premier activé de la liste est posé", function()
    local MAGE = ns.Spells.MAGE
    local priorities = { { key = "amplify", enabled = true }, { key = "dampen", enabled = true } }
    local ctx = { isKnown = knowsAll, settings = SETTINGS, priorities = priorities }
    local need = ns.Decision.Evaluate(MAGE, ctx, { level = 60, auras = {} })
    eq(need.family, "amplify")
    -- Amplification posée : on ne réclame pas l'atténuation, qui la remplacerait.
    eq(ns.Decision.Evaluate(MAGE, ctx, { level = 60, auras = { aura("amplify", 4) } }), nil)
    -- Amplification pas encore apprise : l'atténuation prend le relais.
    ctx.isKnown = function(id) return ns.SpellIndex[id].family ~= "amplify" end
    eq(ns.Decision.Evaluate(MAGE, ctx, { level = 60, auras = {} }).family, "dampen")
end)

test("Buffs personnels : armure de glace par défaut, armure du mage si cochée", function()
    local data = ns.Spells.MAGE.personal
    local db = ns.Config.Load({}, ns.Spells.MAGE)
    local ctx = { isKnown = knowsAll, settings = SETTINGS, priorities = db.personal }
    eq(ns.Decision.Evaluate(data, ctx, { level = 60, auras = {} }).single.id, 10220)
    ns.Config.SetFamilyForAll(db, "magearmor", true)
    eq(db.personal[2].key, "icearmor"); eq(db.personal[2].enabled, false, "armure de glace décochée")
    eq(ns.Decision.Evaluate(data, ctx, { level = 60, auras = {} }).family, "magearmor")
    eq(ns.Decision.Evaluate(data, ctx, { level = 60, auras = { aura("magearmor", 3) } }), nil)
end)

test("Reagents : composant du meilleur rang de groupe connu, sans doublon", function()
    local list = ns.Decision.Reagents(PRIEST, knowsAll)
    eq(#list, 1); eq(list[1], 17029)
    -- Seule la prière de robustesse rang 1 est connue : bougie sanctifiée.
    list = ns.Decision.Reagents(PRIEST, knows({ [21562] = true }))
    eq(#list, 1); eq(list[1], 17028)
    eq(#ns.Decision.Reagents(ns.Spells.WARRIOR, knowsAll), 0)
end)

test("SwitchContext : priorités propres à chaque contexte", function()
    local db = ns.Config.Load({}, PRIEST)
    eq(ns.Config.SwitchContext(db, PRIEST, "solo"), true)
    eq(ns.Config.SwitchContext(db, PRIEST, "solo"), false)
    ns.Config.SetFamilyForAll(db, "shadowprot", true)
    ns.Config.SwitchContext(db, PRIEST, "raid") -- part d'une copie du contexte quitté
    eq(db.priorities.WARRIOR[3].enabled, true)
    ns.Config.SetFamilyForAll(db, "shadowprot", false)
    ns.Config.SwitchContext(db, PRIEST, "solo")
    eq(db.priorities.WARRIOR[3].enabled, true, "solo intact")
    ns.Config.SwitchContext(db, PRIEST, "raid")
    eq(db.priorities.WARRIOR[3].enabled, false, "raid retrouvé")
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

-- Spécialisations ------------------------------------------------------------

test("MainTab : arbre le plus rempli", function()
    eq(ns.Specs.MainTab({ 31, 20, 0 }), 1)
    eq(ns.Specs.MainTab({ 5, 30, 16 }), 2)
    eq(ns.Specs.MainTab({ 10, 10, 0 }), 1, "égalité : le premier")
    eq(ns.Specs.MainTab({ 0, 0, 0 }), nil, "aucun talent")
    eq(ns.Specs.MainTab({}), nil, "talents illisibles")
end)

test("Profile : classe hybride, arbre connu ou non", function()
    eq(ns.Specs.Profile("SHAMAN", 2), "SHAMAN_ENHANCEMENT")
    eq(ns.Specs.Profile("DRUID", 2), "DRUID_FERAL")
    eq(ns.Specs.Profile("SHAMAN", nil), "SHAMAN")
    eq(ns.Specs.Profile("MAGE", 1), "MAGE", "classe sans profils de spé")
end)

test("Spé moderne : gardien = farouche", function()
    eq(ns.Specs.Profile("DRUID", ns.Specs.SPEC_ID_TAB[104]), "DRUID_FERAL")
end)

test("Label : classe, spé, spé inconnue", function()
    eq(ns.Specs.Label("SHAMAN_ENHANCEMENT"), "SHAMAN - Enhancement")
    eq(ns.Specs.Label("SHAMAN"), "SHAMAN (spec unknown)")
    eq(ns.Specs.Label("MAGE"), "MAGE")
end)

test("Chaque classe de buff a des priorités pour chaque profil, avec toutes ses familles", function()
    for class, data in pairs(ns.Spells) do
        local count = 0
        for _ in pairs(data.families) do count = count + 1 end
        for _, profile in ipairs(ns.TARGET_PROFILES) do
            local list = data.defaults[profile]
            if not list then error(class .. " : pas de priorités pour " .. profile) end
            eq(#list, count, class .. " / " .. profile)
        end
    end
end)

test("Paladin : chaman amélioration -> puissance avant sagesse", function()
    local need = ns.Decision.Evaluate(PALADIN, ctxFor("PALADIN", "SHAMAN_ENHANCEMENT"), { level = 60, auras = {} })
    eq(need.family, "might")
end)

test("Paladin : chaman élémentaire ou spé inconnue -> sagesse", function()
    eq(ns.Decision.Evaluate(PALADIN, ctxFor("PALADIN", "SHAMAN_ELEMENTAL"), { level = 60, auras = {} }).family, "wisdom")
    eq(ns.Decision.Evaluate(PALADIN, ctxFor("PALADIN", "SHAMAN"), { level = 60, auras = {} }).family, "wisdom")
end)

test("Paladin : guerrier fureur reçoit le salut, guerrier protection jamais", function()
    local auras = { aura("might", 7), aura("kings", 1) }
    eq(ns.Decision.Evaluate(PALADIN, ctxFor("PALADIN", "WARRIOR_FURY"), { level = 60, auras = auras }).family, "salvation")
    eq(ns.Decision.Evaluate(PALADIN, ctxFor("PALADIN", "WARRIOR_PROTECTION"), { level = 60, auras = auras }).family, "light")
end)

test("Paladin : druide farouche -> puissance, pas de salut", function()
    eq(ns.Decision.Evaluate(PALADIN, ctxFor("PALADIN", "DRUID_FERAL"), { level = 60, auras = {} }).family, "might")
    local auras = { aura("might", 7), aura("kings", 1), aura("light", 3) }
    eq(ns.Decision.Evaluate(PALADIN, ctxFor("PALADIN", "DRUID_FERAL"), { level = 60, auras = auras }), nil)
end)

test("Paladin : paladin vindicte -> puissance, sacré -> sagesse", function()
    eq(ns.Decision.Evaluate(PALADIN, ctxFor("PALADIN", "PALADIN_RETRIBUTION"), { level = 60, auras = {} }).family, "might")
    eq(ns.Decision.Evaluate(PALADIN, ctxFor("PALADIN", "PALADIN_HOLY"), { level = 60, auras = {} }).family, "wisdom")
end)

test("Prêtre : esprit pour le chaman amélioration, pas pour le druide farouche", function()
    local fort = { aura("fortitude", 6, { remaining = 1500, duration = 1800 }) }
    eq(ns.Decision.Evaluate(PRIEST, ctxFor("PRIEST", "SHAMAN_ENHANCEMENT"), { level = 60, auras = fort }).family, "spirit")
    eq(ns.Decision.Evaluate(PRIEST, ctxFor("PRIEST", "DRUID_FERAL"), { level = 60, auras = fort }), nil)
end)

test("Druide : épines sur paladin protection, pas sur paladin sacré", function()
    local mark = { aura("mark", 7, { remaining = 1500, duration = 1800 }) }
    eq(ns.Decision.Evaluate(ns.Spells.DRUID, ctxFor("DRUID", "PALADIN_PROTECTION"), { level = 60, auras = mark }).family, "thorns")
    eq(ns.Decision.Evaluate(ns.Spells.DRUID, ctxFor("DRUID", "PALADIN_HOLY"), { level = 60, auras = mark }), nil)
end)

test("Config.Load : priorités par classe sauvegardées gardées pour la spé inconnue", function()
    local saved = { priorities = { SHAMAN = { { key = "light", enabled = true } } } }
    local db = ns.Config.Load(saved, PALADIN)
    eq(db.priorities.SHAMAN[1].key, "light", "réglage conservé")
    eq(db.priorities.SHAMAN_ENHANCEMENT[1].key, "might", "nouveau profil : défauts")
    eq(db.detectSpecs, true)
end)

-- Traductions --------------------------------------------------------------

-- Résurrection, compteurs, version de groupe ------------------------------------

test("Resurrect : meilleur rang connu, sans limite de niveau", function()
    local need = ns.Decision.Resurrect(ns.Resurrection.PRIEST, knows({ [2006] = true, [2010] = true }))
    eq(need.single.id, 2010); eq(need.reason, "dead"); eq(need.family, "resurrect")
    eq(ns.Decision.Resurrect(ns.Resurrection.PRIEST, knows({})), nil, "sort non appris")
    eq(ns.Decision.Resurrect(nil, knowsAll), nil, "classe sans résurrection")
end)

test("Resurrect : les morts passent avant les autres besoins", function()
    local rows = {
        { name = "A", isGroup = true, need = { reason = "missing" } },
        { name = "B", isGroup = true, need = { reason = "dead" } },
    }
    table.sort(rows, ns.Decision.Compare)
    eq(rows[1].name, "B")
end)

test("Missing : cumulatif, chaque famille activée qui manque", function()
    local missing, wanted = ns.Decision.Missing(PRIEST, ctxFor("PRIEST", "MAGE"), { level = 60, auras = { aura("fortitude", 6) } })
    eq(missing.fortitude, nil, "robustesse posée"); eq(missing.spirit, true, "esprit manquant")
    eq(wanted.fortitude, true); eq(wanted.spirit, true); eq(wanted.shadowprot, nil, "famille désactivée")
end)

test("Missing : exclusif, la bénédiction qu'on poserait", function()
    local missing = ns.Decision.Missing(PALADIN, ctxFor("PALADIN", "PRIEST"), { level = 60, auras = {} })
    eq(missing.wisdom, true); eq(missing.kings, nil)
end)

test("ApplyGroupMin : version de groupe seulement à partir du seuil, par portée", function()
    local function row(scope) return { scope = scope, need = { family = "fortitude", group = { id = 1 } } } end
    local rows = { row(1), row(1), row(2) }
    ns.Decision.ApplyGroupMin(rows, 2, function(r) return r.scope end)
    eq(rows[1].need.group ~= nil, true, "groupe 1 : deux joueurs")
    eq(rows[3].need.group, nil, "groupe 2 : un seul joueur -> individuel")
    local single = { row(1) }
    ns.Decision.ApplyGroupMin(single, 1, function(r) return r.scope end)
    eq(single[1].need.group ~= nil, true, "seuil 1 : toujours la version de groupe")
end)

-- Dissipation ----------------------------------------------------------------

test("DispelSpells : paladin, Purification inutile une fois Épuration apprise", function()
    local spells = ns.Decision.DispelSpells(ns.Dispels.PALADIN, knowsAll)
    eq(#spells, 1); eq(spells[1].key, "cleanse")
    spells = ns.Decision.DispelSpells(ns.Dispels.PALADIN, knows({ [1152] = true }))
    eq(#spells, 1); eq(spells[1].key, "purify")
end)

test("DispelSpells : prêtre, magie au clic gauche, maladie au clic droit, meilleur rang", function()
    local spells = ns.Decision.DispelSpells(ns.Dispels.PRIEST, knowsAll)
    eq(spells[1].rank.id, 988, "Dissipation de la magie rang 2"); eq(spells[2].rank.id, 552, "Abolir maladie")
    eq(ns.Decision.DispelIndex(spells, "Magic"), 1); eq(ns.Decision.DispelIndex(spells, "Disease"), 2)
    eq(ns.Decision.DispelIndex(spells, "Curse"), nil, "malédiction : rien"); eq(ns.Decision.DispelIndex(spells, nil), nil)
end)

test("DispelSpells : sort non appris ignoré", function()
    local spells = ns.Decision.DispelSpells(ns.Dispels.DRUID, knows({ [8946] = true }))
    eq(#spells, 1); eq(spells[1].key, "curepoison")
end)

-- Coordination ---------------------------------------------------------------

test("Coord.Assign : chacun la première bénédiction libre qu'il connaît", function()
    local all = { might = true, wisdom = true, kings = true }
    local players = { { guid = "A", families = all }, { guid = "B", families = { wisdom = true, might = true } }, { guid = "C", families = all } }
    local order = { "kings", "wisdom", "might" }
    eq(ns.Coord.Assign(players, order, "A"), "kings")
    eq(ns.Coord.Assign(players, order, "B"), "wisdom", "B n'a pas Rois")
    eq(ns.Coord.Assign(players, order, "C"), "might")
    eq(ns.Coord.Assign({ { guid = "A", families = all }, { guid = "D", families = {} } }, order, "D"), nil, "rien à prendre")
end)

test("Coord.OwnsSubgroup : groupes répartis à tour de rôle", function()
    eq(ns.Coord.OwnsSubgroup(1, 2, 1), true); eq(ns.Coord.OwnsSubgroup(2, 2, 2), true)
    eq(ns.Coord.OwnsSubgroup(1, 2, 3), true); eq(ns.Coord.OwnsSubgroup(1, 2, 2), false)
end)

test("Coord : message encodé puis décodé, messages invalides rejetés", function()
    local text = ns.Coord.Encode("Player-1-0ABC", "PALADIN", { wisdom = true, kings = true })
    eq(text, "H:Player-1-0ABC:PALADIN:kings,wisdom")
    local msg = ns.Coord.Decode(text)
    eq(msg.guid, "Player-1-0ABC"); eq(msg.class, "PALADIN"); eq(msg.families.kings, true)
    eq(ns.Coord.Decode("H:Creature-1:PALADIN:kings"), nil, "pas un joueur")
    eq(ns.Coord.Decode("H:Player-1:paladin:kings"), nil, "classe mal formée")
    eq(ns.Coord.Decode("X" .. string.rep("a", 300)), nil, "trop long")
    eq(ns.Coord.Decode(nil), nil)
end)

test("Paladin : bénédiction attribuée par la coordination", function()
    local ctx = ctxFor("PALADIN", "PRIEST")
    ctx.assigned = "kings"
    local need = ns.Decision.Evaluate(PALADIN, ctx, { level = 60, auras = {} })
    eq(need.family, "kings", "au lieu de sagesse")
    need = ns.Decision.Evaluate(PALADIN, ctx, { level = 60, auras = { aura("wisdom", 6, { mine = true, remaining = 200, duration = 300 }) } })
    eq(need.family, "kings", "remplace ma sagesse")
    need = ns.Decision.Evaluate(PALADIN, ctx, { level = 60, auras = { aura("kings", 1), aura("wisdom", 6, { mine = true, remaining = 200, duration = 300 }) } })
    eq(need, nil, "rois déjà posé par un autre : ma sagesse reste")
    ctx.assigned = "sanctuary" -- désactivée pour ce profil : ignorée
    need = ns.Decision.Evaluate(PALADIN, ctx, { level = 60, auras = {} })
    eq(need.family, "wisdom")
end)

-- Copie entre personnages ----------------------------------------------------

test("CopyFrom : priorités copiées (pas partagées) et remises en accord avec la classe", function()
    local src = ns.Config.Load({}, PRIEST)
    ns.Config.SetFamilyForAll(src, "shadowprot", true)
    src.priorities.WARRIOR[#src.priorities.WARRIOR + 1] = { key = "inconnue", enabled = true }
    local db = ns.Config.Load({}, PRIEST)
    ns.Config.CopyFrom(db, PRIEST, { class = "PRIEST", priorities = src.priorities, personal = src.personal })
    eq(db.priorities.WARRIOR[3].enabled, true, "copiée")
    eq(#db.priorities.WARRIOR, 3, "famille inconnue retirée")
    db.priorities.WARRIOR[3].enabled = false
    eq(src.priorities.WARRIOR[3].enabled, true, "source intacte")
end)

local SOURCES = { "FriendlyBuffer.lua", "Core/Config.lua", "Core/Scanner.lua", "Core/Specs.lua", "UI/MainFrame.lua", "UI/Options.lua", "UI/Nameplates.lua",
    "Core/Coord.lua", "UI/Dispel.lua", "UI/Minimap.lua" }
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
