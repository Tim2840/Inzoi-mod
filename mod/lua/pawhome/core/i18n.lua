-- Localisation: dotted keys, {placeholders}, English fallback.
local I18n = { locale = "en", tables = {} }

I18n.SUPPORTED = { "en", "zh-TW" }
local MODULES = { ["en"] = "pawhome.localization.en", ["zh-TW"] = "pawhome.localization.zh_TW" }

local function flatten(src, prefix, out)
    for k, v in pairs(src) do
        local key = prefix and (prefix .. "." .. k) or k
        if type(v) == "table" then flatten(v, key, out) else out[key] = v end
    end
    return out
end

local function load(locale)
    if I18n.tables[locale] then return I18n.tables[locale] end
    local ok, src = pcall(require, MODULES[locale])
    I18n.tables[locale] = ok and flatten(src, nil, {}) or {}
    return I18n.tables[locale]
end

-- Accepts "zh-TW", "zh_TW", "zh-Hant", "zh", "en-US", ... and picks the closest.
function I18n.normalize(locale)
    local l = tostring(locale or ""):lower():gsub("_", "-")
    if l:match("^zh") then return "zh-TW" end
    return "en"
end

function I18n.setLocale(locale)
    I18n.locale = I18n.normalize(locale)
    load("en"); load(I18n.locale)
    return I18n.locale
end

function I18n.has(key, locale)
    return load(locale or I18n.locale)[key] ~= nil
end

function I18n.keys(locale)
    local out = {}
    for k in pairs(load(locale)) do out[#out + 1] = k end
    table.sort(out)
    return out
end

function I18n.t(key, params)
    local s = load(I18n.locale)[key] or load("en")[key]
    if s == nil then return key end
    if params then
        s = s:gsub("{([%w_]+)}", function(name)
            local v = params[name]
            if v == nil then return "{" .. name .. "}" end
            return tostring(v)
        end)
    end
    return s
end

return I18n
