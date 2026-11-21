-- Локализация (решение 6): английский по умолчанию, русский включается в настройках
local Strings = require(script.Parent.Parent.Locale.Strings)

-- веха 8: тексты Акта 1 лежат в отдельном модуле и добавляются к общим
for lang, extra in pairs(require(script.Parent.Parent.Locale.Act1Strings)) do
	Strings[lang] = Strings[lang] or {}
	for key, text in pairs(extra) do Strings[lang][key] = text end
end

-- веха 9: тексты лобби, окна «Не спи!», обмена и украшений дома — тоже в отдельном модуле
for lang, extra in pairs(require(script.Parent.Parent.Locale.CoopStrings)) do
	Strings[lang] = Strings[lang] or {}
	for key, text in pairs(extra) do Strings[lang][key] = text end
end

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

-- Имя из конфига вида {en = "...", ru = "..."}
function Locale.Name(lang, names)
	if type(names) ~= "table" then return tostring(names) end
	return names[lang] or names.en or "?"
end

return Locale
