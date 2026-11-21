-- Localization (decision 6): English by default, Russian by choice. The lobby has its own texts
local Strings = require(script.Parent.Parent.Locale.LobbyStrings)

local Locale = {}
Locale.Default = "en"
Locale.Languages = {"en", "ru"}

function Locale.IsSupported(lang)
	return type(lang) == "string" and Strings[lang] ~= nil
end

function Locale.T(lang, key, ...)
	local s = (Strings[lang] and Strings[lang][key]) or Strings.en[key] or key
	if select("#", ...) > 0 then
		local ok, res = pcall(string.format, s, ...)
		if ok then return res end
	end
	return s
end

return Locale
