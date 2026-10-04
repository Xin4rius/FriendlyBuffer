-- Traductions : les clés sont les textes anglais (enUS) ; une clé sans traduction s'affiche telle quelle.
-- Chaque fichier de langue ne remplit la table que si le client est dans sa langue.
local _, ns = ...

ns.LOCALE = GetLocale()
ns.L = setmetatable({}, { __index = function(_, key) return key end })
