-- RLS Configurator 1.0.0
-- Adds a "configure a new vehicle" card to the brand factory stores of RLS Career Overhaul.
-- Flow: model -> body style -> trim -> engine (incl. engine swap from compatible donor configs)
-- -> paint -> delivery tier / hand-over (garage delivery or pickup at the dealer's freight point).
-- The configurator builds a one-off listing (new, 0 km) and hands it to the regular RLS purchase menu,
-- so taxes, insurance, trade-in and inventory keep working like a normal dealership purchase.
-- No RLS or vanilla files are overridden; disabling the mod removes every trace from the UI.
-- Settings: /gameplay/rlsConfigurator/settings.json

local M = {}

local MOD_VERSION = "1.2.3"
local LOG_TAG = "rlsConfigurator"
local SETTINGS_PATH = "/gameplay/rlsConfigurator/settings.json"
local LISTING_TTL_SECONDS = 3600
local PAINT_ARM_SECONDS = 1800
local SHOP_ID_BASE = 9000000

local settings = nil
local shopIndex = nil       -- sellerId -> shop record (with models) ; built lazily
local shopIndexLevel = nil  -- level the index was built for (dealer ids repeat across maps)
local armedPaint = nil      -- pending paint injection for the next matching shop spawn
local originalSpawnNewVehicle = nil
local wrappedSpawnNewVehicle = nil

-- Helpers -------------------------------------------------------------------------------------------

local function logI(msg, ...) log("I", LOG_TAG, string.format(msg, ...)) end
local function logW(msg, ...) log("W", LOG_TAG, string.format(msg, ...)) end
local function logE(msg, ...) log("E", LOG_TAG, string.format(msg, ...)) end

local function safeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, result, result2 = pcall(fn, ...)
  if not ok then
    logW("call failed: %s", tostring(result))
    return nil
  end
  return result, result2
end

local function currentYear()
  return tonumber(os.date("%Y")) or 2026
end

local function ceilTo(value, step)
  return math.ceil((tonumber(value) or 0) / step) * step
end

local function toSet(list)
  local set = {}
  for _, v in ipairs(list or {}) do set[v] = true end
  return set
end

-- Language ------------------------------------------------------------------------------------------
-- Bound to the game language: German when the game runs in German, English otherwise.

local STRINGS = {
  de = {
    sec = "%d Sek.", min = "%d Min.", hour = "%d Std.", hourMin = "%d Std. %d Min.",
    noConfigurator = "Dieser Händler bietet keinen Konfigurator an.",
    catalogFailed = "Katalog konnte nicht geladen werden.",
    shopNotFound = "Händler nicht gefunden.",
    configNotFound = "Ausführung nicht gefunden.",
    shoppingUnavailable = "Fahrzeugkauf ist gerade nicht verfügbar.",
    orderFailedLog = "Bestellung fehlgeschlagen (siehe beamng.log).",
    orderFailed = "Bestellung fehlgeschlagen.",
    ordered = "Dein %s ist bestellt (%s). Lieferung in ca. %s.",
    swapUnavailable = "Motortausch ist für dieses Modell nicht verfügbar.",
    orderedPickup = "Dein %s ist bestellt (%s). Abholbereit am Frachtpunkt von %s in ca. %s.",
    pickupReady = "Dein %s ist abholbereit am Frachtpunkt von %s. Eine Route wurde gesetzt.",
    swapIncompatible = "Dieser Motor passt nicht in diese Ausführung.",
    orderedPickupDealer = "Dein %s ist bestellt (%s). Abholbereit bei %s in ca. %s.",
    pickupReadyDealer = "Dein %s ist abholbereit bei %s. Eine Route wurde gesetzt.",
    routeSet = "Route zu deinem %s wurde gesetzt.",
    routeFailed = "Für dieses Fahrzeug konnte keine Route gesetzt werden.",
    redirected = "Dein %s wird in die Garage geliefert (%s). Verfügbar in ca. %s.",
    redirectFailed = "Lieferung in die Garage nicht möglich (keine freie Garage?).",
  },
  en = {
    sec = "%d s", min = "%d min", hour = "%d h", hourMin = "%d h %d min",
    noConfigurator = "This dealer does not offer the configurator.",
    catalogFailed = "The catalog could not be loaded.",
    shopNotFound = "Dealer not found.",
    configNotFound = "Configuration not found.",
    shoppingUnavailable = "Vehicle shopping is currently unavailable.",
    orderFailedLog = "Order failed (see beamng.log).",
    orderFailed = "Order failed.",
    ordered = "Your %s has been ordered (%s). Delivery in about %s.",
    swapUnavailable = "Engine swap is not available for this model.",
    orderedPickup = "Your %s has been ordered (%s). Ready for pickup at the %s freight point in about %s.",
    pickupReady = "Your %s is ready for pickup at the %s freight point. A route has been set.",
    swapIncompatible = "This engine does not fit this variant.",
    orderedPickupDealer = "Your %s has been ordered (%s). Ready for pickup at %s in about %s.",
    pickupReadyDealer = "Your %s is ready for pickup at %s. A route has been set.",
    routeSet = "A route to your %s has been set.",
    routeFailed = "No route could be set for this vehicle.",
    redirected = "Your %s is being delivered to your garage (%s). Available in about %s.",
    redirectFailed = "Garage delivery is not possible (no free garage?).",
  },
}

local function getLang()
  local lang
  if Lua and Lua.getSelectedLanguage then
    local ok, value = pcall(Lua.getSelectedLanguage, Lua)
    if ok then lang = value end
  end
  if type(lang) ~= "string" and core_settings_settings and core_settings_settings.getValue then
    local ok, value = pcall(core_settings_settings.getValue, "userLanguage")
    if ok then lang = value end
  end
  if type(lang) == "string" and string.lower(string.sub(lang, 1, 2)) == "de" then return "de" end
  return "en"
end

local function T(key)
  local lang = getLang()
  return (STRINGS[lang] and STRINGS[lang][key]) or STRINGS.en[key] or key
end

-- Settings texts may be a plain string or {de = "...", en = "..."}.
local function localized(value)
  if type(value) == "table" then
    return value[getLang()] or value.en or value.de or ""
  end
  return value
end

local function formatDuration(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  if seconds < 60 then return string.format(T("sec"), seconds) end
  local minutes = math.floor(seconds / 60 + 0.5)
  if minutes < 60 then return string.format(T("min"), minutes) end
  local hours = math.floor(minutes / 60)
  local rest = minutes - hours * 60
  if rest == 0 then return string.format(T("hour"), hours) end
  return string.format(T("hourMin"), hours, rest)
end

local function vehicleShopping() return overhaul_career_market_vehicleShopping end
local function inventory() return overhaul_career_garage_inventory end

-- Settings ------------------------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
  configuratorSurchargePct = 8,
  minConfigYear = 2000,
  excludedConfigTypes = {"Police", "Service", "Loaner", "Frame",
    "StreetKnights", "Hardcore", "dns", "joesjunkcar", "joesJunk", "joesJunkshell"},
  motorsportConfigTypes = {"Race", "Rally", "Drift", "Drag"},
  motorsportSurchargePct = 15,
  factoryLikeConfigTypes = {"Factory", "Limited Production"},
  factoryLikeConfigPatterns = {"rennspecht"},
  extraConfiguratorShops = {},
  excludedConfiguratorShops = {},
  detectLocalBrandStores = true,
  brandStoreMaxMileage = 160934,
  brandStoreNamePatterns = {"online"},
  localStoresAsOnline = true,
  allowedVehicleTypes = {"Car", "Truck"},
  excludedModels = {},
  excludedConfigPatterns = {"^rls_", "^npk_", "^sk_", "joes_junk", "used_and_abused", "noprep", "streetheat", "proturbo"},
  debugDump = false,
  dedupeModelsByName = true,
  newestGenerationYears = 8,
  subModels = {vivace = {"Vivace", "Tograc", "Ardente"}},
  subModelFallback = {vivace = "Vivace"},
  engineSwapModels = {"*"},
  engineSwapExcludedModels = {},
  energyBrandingSlotPatterns = {"branding", "badge", "emblem", "logo"},
  engineSwapFeePct = 5,
  engineSwapRefundPct = 50,
  engineSwapValueDiscountPct = 5,
  allowEnergyTypeSwap = true,
  energyChangeSlotPatterns = {"exhaust", "radiator", "intercooler", "gauges", "frunk"},
  drivetrainSlotPatterns = {"fueltank", "fuel_tank", "transfer_case", "differential", "driveshaft", "halfshaft",
    "max_rpm", "tacho", "gauges_rpm", "redline", "shifter", "pedal", "drivemode", "exhaust", "muffler"},
  exhaustBodySlotPatterns = {"bumper_r", "diffuser", "valance_r", "rear_valance"},
  preferBaseExhaust = true,
  deliveryTimeMultiplier = 1.0,
  deliveryTiers = {
    {id = "standard", label = "Standard", description = "", seconds = 1800, surchargePct = 0},
  },
  defaultDeliveryTier = "standard",
  convertFreightPickupToGarageDelivery = true,
  defaultFulfilment = "garage",
  garageDeliveryFeePct = 1,
  garageDeliveryFeeMin = 250,
  garageDeliveryFeeMax = 2500,
  shopOverrides = {},
  reputationSurchargeReduction = {["2"] = 2, ["3"] = 4, ["4"] = 6},
  packagesEnabled = true,
  packageRefundPct = 50,
  packageCategories = {
    {id = "wheels", label = {de = "Felgen & Reifen", en = "Wheels & tyres"},
      slotPatterns = {"wheel_f", "wheel_r", "spacer_f", "spacer_r"}},
    {id = "suspension", label = {de = "Fahrwerk", en = "Suspension"},
      slotPatterns = {"coilover", "spring_f", "spring_r", "shock_f", "shock_r", "swaybar", "strut_f", "strut_r", "damper"}},
  },
  orderHistoryCount = 8,
}

local function loadSettings()
  local data = jsonReadFile(SETTINGS_PATH)
  if type(data) ~= "table" then
    logW("settings file missing or invalid (%s), using defaults", SETTINGS_PATH)
    data = {}
  end
  local merged = deepcopy(DEFAULT_SETTINGS)
  for k, v in pairs(data) do
    if string.sub(k, 1, 1) ~= "_" then merged[k] = v end
  end
  if type(merged.deliveryTiers) ~= "table" or not merged.deliveryTiers[1] then
    merged.deliveryTiers = deepcopy(DEFAULT_SETTINGS.deliveryTiers)
  end
  settings = merged
  return settings
end

local function getSettings()
  return settings or loadSettings()
end

local function getTier(tierId)
  local s = getSettings()
  for _, tier in ipairs(s.deliveryTiers) do
    if tier.id == tierId then return tier end
  end
  for _, tier in ipairs(s.deliveryTiers) do
    if tier.id == s.defaultDeliveryTier then return tier end
  end
  return s.deliveryTiers[1]
end

local function tierSeconds(tier)
  local mult = tonumber(getSettings().deliveryTimeMultiplier) or 1
  return math.max(0, math.floor((tonumber(tier and tier.seconds) or 0) * mult + 0.5))
end

-- Pricing -------------------------------------------------------------------------------------------

local function buyMultiplier()
  local calc = overhaul_career_market_valueCalculator
  local mult = calc and safeCall(calc.getVehicleBuyMarketMultiplier)
  mult = tonumber(mult)
  if not mult or mult <= 0 then mult = 1 end
  return mult
end

local function catalogValueFor(info)
  local calc = overhaul_career_market_valueCalculator
  if calc and calc.getVehicleCatalogProfile then
    local profile = safeCall(calc.getVehicleCatalogProfile, info.model_key, info.key, info)
    if type(profile) == "table" and tonumber(profile.catalogValue) and profile.catalogValue > 0 then
      return profile.catalogValue
    end
  end
  return tonumber(info.effectiveCatalogValue) or tonumber(info.Value) or 0
end

-- New-car price before the configurator surcharge (what the car would cost new, incl. market multiplier).
local function basePriceFor(catalogValue)
  return ceilTo(catalogValue * buyMultiplier(), 10)
end

-- Motorsport configs (Race/Rally/Drift/Drag) carry an extra surcharge on top of the configurator one.
local function isMotorsportConfig(cfg)
  if type(cfg) ~= "table" or not cfg.configType then return false end
  for _, t in ipairs(getSettings().motorsportConfigTypes or {}) do
    if string.lower(t) == string.lower(cfg.configType) then return true end
  end
  return false
end

local function extraPctFor(cfg, donorCfg)
  if isMotorsportConfig(cfg) or isMotorsportConfig(donorCfg) then
    return tonumber(getSettings().motorsportSurchargePct) or 0
  end
  return 0
end

-- surchargePct: effective configurator surcharge of the shop (after the reputation bonus); nil = setting.
local function finalPriceFor(basePrice, tier, extraPct, surchargePct)
  local surcharge = tonumber(surchargePct) or tonumber(getSettings().configuratorSurchargePct) or 0
  local pct = surcharge + (tonumber(tier and tier.surchargePct) or 0) + (tonumber(extraPct) or 0)
  return ceilTo(basePrice * (1 + pct / 100), 100)
end

-- Dealer reputation (RLS organisation level) lowers the configurator surcharge:
-- settings.reputationSurchargeReduction maps "minimum level" -> percentage points off.
-- Returns effective surcharge %, reputation level, reduction in points.
local function surchargeFor(shop)
  local s = getSettings()
  local baseSurcharge = tonumber(s.configuratorSurchargePct) or 0
  local level = 0
  local dealer = shop and overhaul_world_facilities and safeCall(overhaul_world_facilities.getDealership, shop.id)
  local shopping = vehicleShopping()
  local access = dealer and shopping and safeCall(shopping.getSellerAccessInfo, dealer)
  if type(access) == "table" then level = tonumber(access.reputationLevel) or 0 end
  local reduction = 0
  if type(s.reputationSurchargeReduction) == "table" then
    for minLevel, points in pairs(s.reputationSurchargeReduction) do
      if level >= (tonumber(minLevel) or math.huge) then reduction = math.max(reduction, tonumber(points) or 0) end
    end
  end
  reduction = math.min(reduction, baseSurcharge)
  return baseSurcharge - reduction, level, reduction
end

-- Hand-over: pickup at the store's freight point is free, delivery to a garage costs a fee.
local function garageDeliveryFeeFor(price)
  local s = getSettings()
  local fee = (tonumber(price) or 0) * (tonumber(s.garageDeliveryFeePct) or 0) / 100
  fee = math.max(tonumber(s.garageDeliveryFeeMin) or 0, fee)
  if tonumber(s.garageDeliveryFeeMax) then fee = math.min(tonumber(s.garageDeliveryFeeMax), fee) end
  return ceilTo(fee, 10)
end

local function normalizeFulfilment(value)
  if value == "pickup" or value == "garage" then return value end
  local default = getSettings().defaultFulfilment
  return (default == "pickup") and "pickup" or "garage"
end

-- Paints --------------------------------------------------------------------------------------------

local function colorToCss(baseColor)
  if type(baseColor) ~= "table" then return "rgb(128,128,128)" end
  local r = tonumber(baseColor[1] or baseColor.r or baseColor.x) or 0.5
  local g = tonumber(baseColor[2] or baseColor.g or baseColor.y) or 0.5
  local b = tonumber(baseColor[3] or baseColor.b or baseColor.z) or 0.5
  local function c(v) return math.max(0, math.min(255, math.floor(v * 255 + 0.5))) end
  return string.format("rgb(%d,%d,%d)", c(r), c(g), c(b))
end

local function getModelData(modelKey)
  if not core_vehicles or not core_vehicles.getModel then return nil end
  return safeCall(core_vehicles.getModel, modelKey)
end

local function paintsForModel(modelKey)
  local modelData = getModelData(modelKey)
  local paints = modelData and modelData.model and modelData.model.paints
  local result = {}
  if type(paints) ~= "table" then return result end
  for name, paint in pairs(paints) do
    if type(paint) == "table" then
      table.insert(result, {
        name = name,
        color = colorToCss(paint.baseColor),
        metallic = (tonumber(paint.metallic) or 0) > 0.3,
      })
    end
  end
  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

local function defaultPaintFor(modelKey, configKey)
  local modelData = getModelData(modelKey)
  local cfg = modelData and modelData.configs and modelData.configs[configKey]
  return cfg and (cfg.defaultPaintName1 or cfg.defaultPaintName) or nil
end

-- Catalog -------------------------------------------------------------------------------------------

-- Vanilla configs often keep Brand/Type/Years only in `aggregates` (model level). Read fields the same
-- way RLS's dealership filter does: direct value first, then the aggregate set.
local function attrMatches(info, field, allowedSet)
  local direct = info[field]
  if direct ~= nil then return allowedSet[direct] == true end
  local agg = type(info.aggregates) == "table" and info.aggregates[field] or nil
  if type(agg) ~= "table" then return nil end
  for value in pairs(agg) do
    if allowedSet[value] then return true end
  end
  return false
end

local function firstAttr(info, field)
  if type(info[field]) == "string" then return info[field] end
  local agg = type(info.aggregates) == "table" and info.aggregates[field] or nil
  if type(agg) == "table" then
    for value in pairs(agg) do
      if type(value) == "string" then return value end
    end
  end
  return nil
end

local function yearsRange(info)
  local function norm(y)
    if type(y) ~= "table" then return nil end
    local mn, mx = tonumber(y.min), tonumber(y.max)
    if not mn or not mx or mn > mx then return nil end
    return {min = mn, max = mx}
  end
  return norm(info.Years) or norm(type(info.aggregates) == "table" and info.aggregates.Years or nil)
end

-- Returns true, or false plus a short reason for the drop statistics.
local function configPassesFilters(info, s, excludedModels, excludedConfigTypes, allowedTypes)
  if type(info) ~= "table" or type(info.model_key) ~= "string" or type(info.key) ~= "string" then return false, "malformed" end
  if excludedModels[info.model_key] then return false, "excludedModel" end
  local configType = firstAttr(info, "Config Type")
  if not configType then return false, "noConfigType" end
  if excludedConfigTypes[configType] or excludedConfigTypes[string.lower(configType)] then return false, "configType" end
  if attrMatches(info, "Type", allowedTypes) == false then return false, "vehicleType" end
  if not firstAttr(info, "Brand") then return false, "noBrand" end
  local years = yearsRange(info)
  if not years then return false, "noYears" end
  if years.max < (tonumber(s.minConfigYear) or 0) then return false, "tooOld" end
  local lowerKey = string.lower(info.key)
  for _, pattern in ipairs(s.excludedConfigPatterns or {}) do
    if string.find(lowerKey, pattern) then return false, "excludedPattern" end
  end
  return true
end

-- Configs listed among the normal (fuel) categories: Factory, limited runs and named exceptions like
-- the vanilla Rennspecht variants (typed "Custom" in vanilla data).
local function isFactoryLike(cfg)
  if not cfg then return false end
  local s = getSettings()
  local ct = tostring(cfg.configType or "Factory")
  for _, t in ipairs(s.factoryLikeConfigTypes or {"Factory"}) do
    if ct:lower() == tostring(t):lower() then return true end
  end
  local hay = (tostring(cfg.key or "") .. " " .. tostring(cfg.name or "")):lower()
  for _, pat in ipairs(s.factoryLikeConfigPatterns or {}) do
    if hay:find(tostring(pat):lower(), 1, true) then return true end
  end
  return false
end

local function buildConfigEntry(info)
  local years = yearsRange(info) or {}
  local year = math.min(tonumber(years.max) or currentYear(), currentYear())
  local catalogValue = catalogValueFor(info)
  if catalogValue <= 0 then return nil end
  return {
    key = info.key,
    name = info.Configuration or info.key,
    preview = info.preview,
    year = year,
    power = tonumber(info.Power),
    torque = tonumber(info.Torque),
    weight = tonumber(info.Weight),
    drivetrain = firstAttr(info, "Drivetrain"),
    fuel = firstAttr(info, "Fuel Type"),
    transmission = firstAttr(info, "Transmission"),
    bodyStyle = firstAttr(info, "Body Style"),
    configType = firstAttr(info, "Config Type"),
    catalogValue = catalogValue,
    defaultPaint = defaultPaintFor(info.model_key, info.key),
    info = info,
  }
end

-- Some vanilla models bundle several product lines in one model (e.g. the Cherrier FCV: Vivace,
-- Tograc, Ardente). settings.subModels splits such a model by configuration name or key prefix.
local function detectSubModel(info, subNames, brand)
  local name = tostring(info.Configuration or "")
  if brand and string.sub(string.lower(name), 1, #brand + 1) == string.lower(brand) .. " " then
    name = string.sub(name, #brand + 2)
  end
  local lowerName, lowerKey = string.lower(name), string.lower(info.key or "")
  for _, sub in ipairs(subNames) do
    local lowerSub = string.lower(sub)
    if string.sub(lowerName, 1, #lowerSub) == lowerSub or string.sub(lowerKey, 1, #lowerSub) == lowerSub then
      return sub
    end
  end
  for _, sub in ipairs(subNames) do
    local lowerSub = string.lower(sub)
    if string.find(lowerName, lowerSub, 1, true) or string.find(lowerKey, lowerSub, 1, true) then return sub end
  end
  return nil
end

-- Vanilla detection: a file that no mod provides (core_modmanager.getModFromPath returns nothing)
-- and that does not live under a mods folder. Used so model images always show a stock config.
local vanillaCache = {}
local function isVanillaFile(path)
  if type(path) ~= "string" or path == "" then return false end
  if vanillaCache[path] ~= nil then return vanillaCache[path] end
  local vanilla = true
  local modManager = rawget(_G, "core_modmanager")
  if modManager and modManager.getModFromPath then
    local ok, mod = pcall(modManager.getModFromPath, path)
    if ok and type(mod) == "table" then vanilla = false end
  end
  if vanilla and FS and FS.getFileRealPath then
    local ok, real = pcall(FS.getFileRealPath, FS, path)
    if ok and type(real) == "string" then
      real = string.lower((real:gsub("\\", "/")))
      if string.find(real, "/mods/", 1, true) then vanilla = false end
    end
  end
  vanillaCache[path] = vanilla
  return vanilla
end

local function configIsVanilla(cfg)
  local base = "/vehicles/" .. tostring(cfg.info and cfg.info.model_key or "") .. "/" .. tostring(cfg.key)
  return isVanillaFile(base .. ".pc") and (not cfg.preview or isVanillaFile(cfg.preview))
end

-- Model image = the base vanilla config: the model's default config if it is vanilla, otherwise the
-- cheapest vanilla Factory config, otherwise the cheapest vanilla config of any type.
local function pickVanillaPreview(record)
  local all = {}
  for _, cfg in ipairs(record.configs) do table.insert(all, cfg) end
  for _, cfg in ipairs(record.oldConfigs) do table.insert(all, cfg) end
  table.sort(all, function(a, b) return a.catalogValue < b.catalogValue end)
  local modelData = getModelData(record.model_key)
  local defaultKey = modelData and modelData.model and (modelData.model.default_pc or modelData.model.defaultConfig)
  if type(defaultKey) == "string" then defaultKey = defaultKey:match("([^/]+)%.pc$") or defaultKey end
  local factory, any
  for _, cfg in ipairs(all) do
    if cfg.preview and configIsVanilla(cfg) then
      if defaultKey and cfg.key == defaultKey then return cfg.preview end
      if not factory and cfg.configType == "Factory" then factory = cfg end
      any = any or cfg
    end
  end
  return (factory and factory.preview) or (any and any.preview) or nil
end

-- brand -> recordId -> model record. A record is a model, or a sub-model line of one.
-- Configs that are only "too old" are kept in record.oldConfigs: a store that explicitly sells the
-- model (e.g. Gavril's truck store) can still offer its newest generation.
local function collectBrandModels()
  local s = getSettings()
  local excludedModels = toSet(s.excludedModels)
  local excludedConfigTypes = {}
  for _, t in ipairs(s.excludedConfigTypes or {}) do
    excludedConfigTypes[t] = true
    excludedConfigTypes[string.lower(t)] = true
  end
  local allowedTypes = toSet(s.allowedVehicleTypes)
  local subModels = type(s.subModels) == "table" and s.subModels or {}
  local eligible = util_configListGenerator and safeCall(util_configListGenerator.getEligibleVehicles) or {}
  local brands = {}
  local kept, oldKept, reasons = 0, 0, {}
  local dump = s.debugDump and {} or nil

  local function recordFor(info, brand)
    local subNames = subModels[info.model_key]
    local sub = type(subNames) == "table" and detectSubModel(info, subNames, brand) or nil
    if type(subNames) == "table" and not sub then
      sub = (type(s.subModelFallback) == "table" and s.subModelFallback[info.model_key]) or subNames[1]
    end
    local recordId = sub and (info.model_key .. "#" .. sub) or info.model_key
    brands[brand] = brands[brand] or {}
    local record = brands[brand][recordId]
    if not record then
      local modelData = getModelData(info.model_key)
      local modelInfo = modelData and modelData.model or {}
      record = {
        id = recordId,
        model_key = info.model_key,
        brand = brand,
        name = sub or modelInfo.Name or info.Name or info.model_key,
        preview = (not sub) and modelInfo.preview or nil,
        maxYear = 0,
        configs = {},
        oldConfigs = {},
      }
      brands[brand][recordId] = record
    end
    return record
  end

  for _, info in ipairs(eligible or {}) do
    local ok, reason = configPassesFilters(info, s, excludedModels, excludedConfigTypes, allowedTypes)
    if dump then
      local years = yearsRange(info)
      table.insert(dump, {model = info.model_key, key = info.key, brand = firstAttr(info, "Brand"),
        configType = firstAttr(info, "Config Type"), type = firstAttr(info, "Type"),
        name = info.Configuration, years = years and (years.min .. "-" .. years.max) or nil,
        kept = ok == true, reason = reason})
    end
    local entry = (ok or reason == "tooOld") and buildConfigEntry(info) or nil
    if (ok or reason == "tooOld") and not entry then reason, ok = "noValue", false end
    if entry then
      local record = recordFor(info, firstAttr(info, "Brand"))
      if ok then
        table.insert(record.configs, entry)
        record.maxYear = math.max(record.maxYear, entry.year)
        if not record.preview and entry.preview and entry.configType == "Factory" then record.preview = entry.preview end
        kept = kept + 1
      else
        table.insert(record.oldConfigs, entry)
        oldKept = oldKept + 1
      end
    end
    if not ok then reasons[reason or "unknown"] = (reasons[reason or "unknown"] or 0) + 1 end
  end

  for _, records in pairs(brands) do
    for _, record in pairs(records) do
      record.preview = pickVanillaPreview(record) or record.preview
    end
  end

  -- Two current models of one brand with the same display name (e.g. an old and a remodelled
  -- generation): keep the newer one so the shop does not show the car twice.
  if s.dedupeModelsByName then
    for brand, records in pairs(brands) do
      local byName = {}
      for _, record in pairs(records) do
        if #record.configs > 0 then
          local other = byName[record.name]
          if other then
            local keep, drop = record, other
            if other.maxYear > record.maxYear or (other.maxYear == record.maxYear and #other.configs >= #record.configs) then
              keep, drop = other, record
            end
            logI("dedupe %s '%s': keeping %s (%d), dropping %s (%d)", brand, record.name,
              keep.id, keep.maxYear, drop.id, drop.maxYear)
            records[drop.id] = nil
            byName[record.name] = keep
          else
            byName[record.name] = record
          end
        end
      end
    end
  end

  local reasonText = {}
  for reason, count in pairs(reasons) do table.insert(reasonText, reason .. "=" .. count) end
  table.sort(reasonText)
  logI("catalog configs kept=%d (plus %d older for explicit store models) dropped: %s", kept, oldKept, table.concat(reasonText, " "))
  if dump and jsonWriteFile then
    table.sort(dump, function(a, b) return (a.model .. a.key) < (b.model .. b.key) end)
    pcall(jsonWriteFile, "/rlsConfigurator_catalog_debug.json", dump, true)
  end
  return brands
end

-- Newest generation of an otherwise too old model: configs that end within N years of its newest one.
local function newestGeneration(record)
  local window = tonumber(getSettings().newestGenerationYears) or 8
  local newest = 0
  for _, cfg in ipairs(record.oldConfigs) do newest = math.max(newest, cfg.year) end
  local configs = {}
  for _, cfg in ipairs(record.oldConfigs) do
    if cfg.year >= newest - window then table.insert(configs, cfg) end
  end
  return configs, newest
end

-- Brands (and explicitly listed models) of a dealer. Factory stores keep them in filter.whiteList;
-- map packs like RLS Italy put them into subFilters instead ("Arima Online Dealership": empty main
-- whitelist, one subFilter with Brand = Arima). Subfilter brands only count when every active
-- subFilter is brand-bound, so a general dealer with one brand subFilter is not mistaken for a store.
local function dealerBrandInfo(dealer)
  local wl = dealer.filter and dealer.filter.whiteList or {}
  local brands, models = {}, {}
  local maxMileage = type(wl.Mileage) == "table" and tonumber(wl.Mileage.max) or nil
  local function addAll(target, list)
    if type(list) ~= "table" then return end
    for _, v in ipairs(list) do
      local seen = false
      for _, w in ipairs(target) do if w == v then seen = true; break end end
      if not seen then table.insert(target, v) end
    end
  end
  addAll(brands, wl.Brand)
  addAll(models, wl.model_key)
  if not brands[1] and type(dealer.subFilters) == "table" then
    local active, allBranded, subMax = 0, true, nil
    for _, sub in ipairs(dealer.subFilters) do
      if type(sub) == "table" and (tonumber(sub.probability) or 1) > 0 then
        active = active + 1
        local swl = type(sub.whiteList) == "table" and sub.whiteList or {}
        if type(swl.Brand) ~= "table" or not swl.Brand[1] then allBranded = false end
        local m = type(swl.Mileage) == "table" and tonumber(swl.Mileage.max) or nil
        if m == nil then subMax = math.huge else subMax = math.max(subMax or 0, m) end
      end
    end
    if active > 0 and allBranded then
      for _, sub in ipairs(dealer.subFilters) do
        if type(sub) == "table" and (tonumber(sub.probability) or 1) > 0 then
          addAll(brands, sub.whiteList.Brand)
          addAll(models, sub.whiteList.model_key)
        end
      end
      if subMax and subMax ~= math.huge then maxMileage = maxMileage and math.min(maxMileage, subMax) or subMax end
    end
  end
  return brands, models, maxMileage
end

-- Brand stores are recognised from the map's own facility data, so stores on other maps get the
-- configurator automatically:
--   * factory stores: Brand filter plus factory/remanufactured sales channel or online-only selling
--   * local brand stores (e.g. the "Online Dealerships" on RLS Italy): Brand filter plus new-car
--     mileage (<= brandStoreMaxMileage) or a name matching brandStoreNamePatterns.
-- settings.extraConfiguratorShops / excludedConfiguratorShops override by id.
-- Returns isShop, isLocal (local = sold through a normal dealer lot, not RLS's online channel).
local function isBrandShop(dealer)
  if type(dealer) ~= "table" or type(dealer.id) ~= "string" then return false end
  local s = getSettings()
  for _, id in ipairs(s.excludedConfiguratorShops or {}) do
    if id == dealer.id then return false end
  end
  local brands, _, maxMileage = dealerBrandInfo(dealer)
  if not brands[1] then return false end
  local online = dealer.salesChannel == "factory" or dealer.salesChannel == "remanufactured" or dealer.remotePurchaseOnly == true
  if online then return true, false end
  for _, id in ipairs(s.extraConfiguratorShops or {}) do
    if id == dealer.id then return true, true end
  end
  if s.detectLocalBrandStores == false then return false end
  local limit = tonumber(s.brandStoreMaxMileage)
  if limit and maxMileage and maxMileage <= limit then return true, true end
  local haystack = string.lower(dealer.id .. " " .. tostring(dealer.name or ""))
  for _, pattern in ipairs(s.brandStoreNamePatterns or {}) do
    if type(pattern) == "string" and pattern ~= "" and string.find(haystack, string.lower(pattern), 1, true) then
      return true, true
    end
  end
  return false
end

local function buildShopIndex()
  local s = getSettings()
  local facilities = overhaul_world_facilities and safeCall(overhaul_world_facilities.getFacilities, getCurrentLevelIdentifier())
  local dealers = facilities and facilities.dealerships or {}

  local shops, shopsByBrand, order = {}, {}, {}
  for _, dealer in ipairs(dealers) do
    local isShop, isLocal = isBrandShop(dealer)
    if isShop then
      local brands, listedModels = dealerBrandInfo(dealer)
      local shop = {
        id = dealer.id,
        name = dealer.name or dealer.id,
        brands = brands,
        whitelistModels = toSet(listedModels),
        localStore = isLocal == true,
        models = {},
      }
      shops[dealer.id] = shop
      table.insert(order, shop)
      for _, brand in ipairs(shop.brands) do
        shopsByBrand[brand] = shopsByBrand[brand] or {}
        table.insert(shopsByBrand[brand], shop)
      end
    end
  end

  local brandModels = collectBrandModels()
  for _, shop in ipairs(order) do
    local override = type(s.shopOverrides) == "table" and s.shopOverrides[shop.id] or {}
    local include = toSet(override.includeModels)
    local exclude = toSet(override.excludeModels)
    local hasInclude = next(include) ~= nil
    for _, brand in ipairs(shop.brands) do
      local siblings = shopsByBrand[brand] or {}
      for _, model in pairs(brandModels[brand] or {}) do
        local modelKey = model.model_key
        local belongs
        if hasInclude then
          belongs = include[modelKey] == true
        elseif #siblings <= 1 then
          belongs = true
        elseif shop.whitelistModels[modelKey] then
          belongs = true
        else
          -- Model not explicitly listed by any shop of this brand: the first shop of the brand takes it.
          local listedSomewhere = false
          for _, sibling in ipairs(siblings) do
            if sibling.whitelistModels[modelKey] then listedSomewhere = true; break end
          end
          belongs = (not listedSomewhere) and siblings[1] == shop
        end
        if belongs and not exclude[modelKey] then
          if #model.configs > 0 then
            table.insert(shop.models, model)
          elseif #model.oldConfigs > 0 and (shop.whitelistModels[modelKey] or include[modelKey]) then
            -- The store explicitly sells this model, so offer its newest generation.
            local configs, newest = newestGeneration(model)
            if #configs > 0 then
              model.configs = configs
              model.maxYear = newest
              table.insert(shop.models, model)
            end
          end
        end
      end
    end
    table.sort(shop.models, function(a, b) return a.name < b.name end)
    for _, model in ipairs(shop.models) do
      table.sort(model.configs, function(a, b) return a.catalogValue < b.catalogValue end)
    end
    local summary = {}
    for _, model in ipairs(shop.models) do
      table.insert(summary, string.format("%s[%s, %d configs, bis %d]", model.name, model.model_key, #model.configs, model.maxYear))
    end
    logI("shop %s (%s%s): %s", shop.id, table.concat(shop.brands, "/"), shop.localStore and ", local" or "", #summary > 0 and table.concat(summary, ", ") or "keine Modelle")
  end

  -- Brands with current models but without any factory store (candidates for new stores).
  local withoutShop = {}
  for brand, models in pairs(brandModels) do
    if not shopsByBrand[brand] and brand then
      local names = {}
      for _, model in pairs(models) do
        if #model.configs > 0 then table.insert(names, string.format("%s[%s]", model.name, model.model_key)) end
      end
      table.sort(names)
      table.insert(withoutShop, string.format("%s: %s", brand, table.concat(names, ", ")))
    end
  end
  table.sort(withoutShop)
  for _, line in ipairs(withoutShop) do
    if not string.find(line, ": $") then logI("brand without store - %s", line) end
  end

  -- Facilities may not be loaded yet; do not cache an empty index.
  shopIndex = next(shops) ~= nil and shops or nil
  shopIndexLevel = shopIndex and getCurrentLevelIdentifier() or nil
  return shops
end

local function getShop(sellerId)
  if type(sellerId) ~= "string" or sellerId == "" then return nil end
  if shopIndex and shopIndexLevel ~= getCurrentLevelIdentifier() then shopIndex = nil end
  local index = shopIndex or buildShopIndex()
  return index[sellerId]
end

local function findConfig(shop, modelKey, configKey)
  for _, model in ipairs(shop.models) do
    if model.model_key == modelKey then
      for _, cfg in ipairs(model.configs) do
        if cfg.key == configKey then return model, cfg end
      end
    end
  end
  return nil
end

-- Engines (Phase 2 groundwork) ----------------------------------------------------------------------
-- The main engine of a config is read from its .pc file with the same slot rule RLS uses for traffic
-- (slot name contains "engine", but not ecu/internal/mount/cover/lid/bay/sound). The readable engine
-- name comes from the part's jbeam "information.name" when the jbeam loader is available.

local ENGINE_SLOT_BANNED = {"ecu", "internal", "mount", "cover", "bay", "sound"}
local engineCache = {}      -- "model/key" -> {slot, part, name}
local jbeamCtxCache = {}    -- model -> ioCtx or false

local function isMainEngineSlot(slotName)
  local lowerName = string.lower(tostring(slotName))
  if not string.find(lowerName, "engine", 1, true) then return false end
  for _, banned in ipairs(ENGINE_SLOT_BANNED) do
    if string.find(lowerName, banned, 1, true) then return false end
  end
  if string.find(lowerName, "%f[%w]lid%f[%W]") or string.find(lowerName, "%f[%w]lid$") then return false end
  return true
end

local function readConfigParts(modelKey, configKey)
  local data = jsonReadFile("/vehicles/" .. modelKey .. "/" .. configKey .. ".pc")
  if type(data) ~= "table" then return nil end
  local parts = data.parts or data.slotMap
  return type(parts) == "table" and parts or nil
end

local function jbeamPartName(modelKey, partName)
  local ok, jbeamIO = pcall(require, "jbeam/io")
  if not ok or type(jbeamIO) ~= "table" or not jbeamIO.startLoading or not jbeamIO.getPart then return nil end
  local ctx = jbeamCtxCache[modelKey]
  if ctx == nil then
    local okCtx, newCtx = pcall(jbeamIO.startLoading, {"/vehicles/" .. modelKey .. "/", "/vehicles/common/"})
    ctx = okCtx and newCtx or false
    jbeamCtxCache[modelKey] = ctx
  end
  if not ctx then return nil end
  local okPart, part = pcall(jbeamIO.getPart, ctx, partName)
  local info = okPart and type(part) == "table" and part.information or nil
  return info and info.name or nil
end

local function engineFor(modelKey, configKey)
  local cacheKey = modelKey .. "/" .. configKey
  if engineCache[cacheKey] ~= nil then return engineCache[cacheKey] or nil end
  local parts = readConfigParts(modelKey, configKey)
  local bestSlot, bestPart
  for slot, part in pairs(parts or {}) do
    if type(part) == "string" and part ~= "" and isMainEngineSlot(slot) then
      if not bestSlot or #slot < #bestSlot then bestSlot, bestPart = slot, part end
    end
  end
  local result = bestPart and {slot = bestSlot, part = bestPart, name = jbeamPartName(modelKey, bestPart) or bestPart} or false
  engineCache[cacheKey] = result
  return result or nil
end

-- jbeam names can be translation objects: {txt = "ui.vehicleconfig.information.name.4.4L V8 BRAND Engine",
-- ctx = {brand1 = "ui.vehicleconfig.brand.ttSport"}}. Resolve them into plain text.
local function resolveEngineName(name)
  if type(name) == "table" then
    local txt = tostring(name.txt or "")
    txt = txt:gsub("^ui%.vehicleconfig%.information%.name%.", "")
    for _, value in pairs(type(name.ctx) == "table" and name.ctx or {}) do
      local brand = tostring(value):gsub("^ui%.vehicleconfig%.brand%.", "")
      txt = txt:gsub("BRAND", brand, 1)
    end
    name = txt
  end
  if type(name) ~= "string" or name == "" then return nil end
  return name
end

local function looksLikeEngine(name)
  local lower = string.lower(name)
  return string.find(lower, "engine", 1, true) or string.find(lower, "motor", 1, true)
    or string.find(lower, "%d%.%dl") or string.find(lower, "%dl ") ~= nil
end

-- Display label of a config's powertrain, e.g. "3.0L I6 Diesel" or "Electric motor".
local function engineLabelFor(cfg, engine)
  local fuel = string.lower(tostring(cfg.fuel or ""))
  local electric = fuel == "battery" or string.find(fuel, "electric", 1, true) ~= nil
  local name = engine and resolveEngineName(engine.name)
  if electric and (not name or not looksLikeEngine(name) or string.find(string.lower(name), "cover", 1, true)) then
    return getLang() == "de" and "Elektromotor" or "Electric motor"
  end
  if not name or not looksLikeEngine(name) then
    return cfg.fuel and tostring(cfg.fuel) or (getLang() == "de" and "Motor" or "Engine")
  end
  name = name:gsub("%s+[Ee]ngine$", "")
  return name
end

local function writeEngineDump(shop)
  if not getSettings().debugDump or not jsonWriteFile then return end
  local rows = {}
  for _, model in ipairs(shop.models) do
    for _, cfg in ipairs(model.configs) do
      local engine = engineFor(model.model_key, cfg.key)
      table.insert(rows, {model = model.id or model.model_key, key = cfg.key, name = cfg.name, body = cfg.bodyStyle,
        power = cfg.power, fuel = cfg.fuel, transmission = cfg.transmission, drivetrain = cfg.drivetrain,
        engineSlot = engine and engine.slot, enginePart = engine and engine.part, engineName = engine and engine.name})
    end
  end
  pcall(jsonWriteFile, "/rlsConfigurator_engines_" .. shop.id .. ".json", rows, true)
end

local swapEnabledFor -- defined with the engine swap code below
local swapCompatibilityFor -- defined with the engine swap code below

-- Info sheet ("i" button): in-game description and the performance data BeamNG stores per config.
-- Descriptions may be translation keys; translate them when the game offers a translator.
local function translated(text)
  if type(text) ~= "string" or text == "" then return nil end
  if not string.find(text, " ", 1, true) and string.find(text, ".", 1, true) and type(translateLanguage) == "function" then
    local ok, value = pcall(translateLanguage, text, text, true)
    if ok and type(value) == "string" and value ~= "" then text = value end
  end
  return text
end

local DETAIL_FIELDS = {
  {"0-100 km/h", "accel100"}, {"0-60 mph", "accel60"}, {"Top Speed", "topSpeed"},
  {"100-0 km/h", "brake100"}, {"Braking G", "brakingG"}, {"Off-Road Score", "offRoad"},
  {"Weight/Power", "weightPower"}, {"Propulsion", "propulsion"}, {"Country", "country"},
  {"Induction Type", "induction"}, {"PowerPeakRPM", "powerRpm"}, {"TorquePeakRPM", "torqueRpm"},
}

local function configDetailsFor(cfg)
  local info = type(cfg.info) == "table" and cfg.info or {}
  local details = {description = translated(info.Description)}
  for _, field in ipairs(DETAIL_FIELDS) do
    local value = info[field[1]]
    if value == nil then value = firstAttr(info, field[1]) end
    if type(value) == "number" or type(value) == "string" then details[field[2]] = value end
  end
  return details
end

local function modelDescriptionFor(modelKey)
  local modelData = getModelData(modelKey)
  local modelInfo = modelData and modelData.model or {}
  return translated(modelInfo.Description or modelInfo.description)
end

local function catalogForUi(shop)
  local s = getSettings()
  local tiers = {}
  for _, tier in ipairs(s.deliveryTiers) do
    table.insert(tiers, {
      id = tier.id,
      label = localized(tier.label) or tier.id,
      description = localized(tier.description) or "",
      seconds = tierSeconds(tier),
      durationText = formatDuration(tierSeconds(tier)),
      surchargePct = tonumber(tier.surchargePct) or 0,
    })
  end
  local defaultTier = getTier(s.defaultDeliveryTier)
  local surcharge, repLevel, repReduction = surchargeFor(shop)
  local models = {}
  for _, model in ipairs(shop.models) do
    local configs, minPrice = {}, nil
    for _, cfg in ipairs(model.configs) do
      local base = basePriceFor(cfg.catalogValue)
      local engine = engineFor(model.model_key, cfg.key)
      table.insert(configs, {
        key = cfg.key,
        name = cfg.name,
        preview = cfg.preview,
        year = cfg.year,
        power = cfg.power,
        torque = cfg.torque,
        weight = cfg.weight,
        drivetrain = cfg.drivetrain,
        fuel = cfg.fuel,
        transmission = cfg.transmission,
        bodyStyle = cfg.bodyStyle,
        configType = cfg.configType,
        factoryLike = isFactoryLike(cfg),
        defaultPaint = cfg.defaultPaint,
        engineKey = engine and engine.part or nil,
        engineSlot = engine and engine.slot or nil,
        engineLabel = engineLabelFor(cfg, engine),
        basePrice = base,
        details = configDetailsFor(cfg),
      })
      local price = finalPriceFor(base, defaultTier, extraPctFor(cfg), surcharge)
      minPrice = minPrice and math.min(minPrice, price) or price
    end
    table.insert(models, {
      id = model.id or model.model_key,
      model_key = model.model_key,
      name = model.name,
      brand = model.brand,
      preview = model.preview or (configs[1] and configs[1].preview),
      maxYear = model.maxYear,
      fromPrice = minPrice,
      configs = configs,
      paints = paintsForModel(model.model_key),
      description = modelDescriptionFor(model.model_key),
    })
  end
  return {
    lang = getLang(),
    sellerId = shop.id,
    shopName = shop.name,
    localStore = shop.localStore == true,
    brands = shop.brands,
    surchargePct = surcharge,
    reputation = {level = repLevel, reductionPct = repReduction, baseSurchargePct = tonumber(s.configuratorSurchargePct) or 0},
    packagesEnabled = s.packagesEnabled ~= false,
    motorsport = {types = s.motorsportConfigTypes or {}, surchargePct = tonumber(s.motorsportSurchargePct) or 0},
    fulfilment = {
      default = normalizeFulfilment(nil),
      feePct = tonumber(s.garageDeliveryFeePct) or 0,
      feeMin = tonumber(s.garageDeliveryFeeMin) or 0,
      feeMax = tonumber(s.garageDeliveryFeeMax),
    },
    engineSwap = {
      compatible = swapCompatibilityFor(shop),
      models = (function()
        local keys, seen = {}, {}
        for _, model in ipairs(shop.models) do
          if not seen[model.model_key] and swapEnabledFor(model.model_key) then
            seen[model.model_key] = true
            table.insert(keys, model.model_key)
          end
        end
        return keys
      end)(),
      feePct = tonumber(s.engineSwapFeePct) or 0,
      refundPct = tonumber(s.engineSwapRefundPct) or 0,
      allowEnergyChange = s.allowEnergyTypeSwap == true,
    },
    tiers = tiers,
    defaultTier = defaultTier and defaultTier.id,
    models = models,
  }
end

-- Paint injection -----------------------------------------------------------------------------------
-- RLS spawns the bought vehicle with the config's default paint. While an order is armed, the next
-- spawn of exactly that model/config receives the chosen paint in its spawn options (same fields RLS
-- itself uses for random paints).

local function injectPaint(options, modelKey, paintNames)
  local modelData = getModelData(modelKey)
  local modelPaints = modelData and modelData.model and modelData.model.paints
  if type(modelPaints) ~= "table" or not modelPaints[paintNames[1]] then return false end
  options.paintName = paintNames[1]
  options.paintName2 = paintNames[2]
  options.paintName3 = paintNames[3]
  options.paint = deepcopy(modelPaints[paintNames[1]])
  options.paint2 = paintNames[2] and modelPaints[paintNames[2]] and deepcopy(modelPaints[paintNames[2]]) or nil
  options.paint3 = paintNames[3] and modelPaints[paintNames[3]] and deepcopy(modelPaints[paintNames[3]]) or nil
  return true
end

-- Each install captures its own predecessor, so re-wrapping after another mod wrapped us cannot recurse.
local function makeSpawnWrapper(original)
  return function(model, options, ...)
    local armed = armedPaint
    if armed and model == armed.model_key and type(options) == "table" and options.config == armed.key
        and os.time() <= armed.expires then
      if type(armed.config) == "table" then
        options.config = deepcopy(armed.config)
        logI("custom build: spawning %s/%s (engine from %s)", model, tostring(armed.key), tostring(armed.donorKey or "factory"))
      end
      if armed.paintNames then
        local ok, injected = pcall(injectPaint, options, model, armed.paintNames)
        if ok and injected then
          logI("applied paint '%s' to %s/%s", tostring(armed.paintNames[1]), model, tostring(armed.key))
        else
          logW("could not apply paint '%s' to %s", tostring(armed.paintNames[1]), model)
        end
      end
    end
    return original(model, options, ...)
  end
end

local function installSpawnWrapper()
  if not core_vehicles or type(core_vehicles.spawnNewVehicle) ~= "function" then return false end
  if wrappedSpawnNewVehicle and core_vehicles.spawnNewVehicle == wrappedSpawnNewVehicle then return true end
  originalSpawnNewVehicle = core_vehicles.spawnNewVehicle
  wrappedSpawnNewVehicle = makeSpawnWrapper(originalSpawnNewVehicle)
  core_vehicles.spawnNewVehicle = wrappedSpawnNewVehicle
  return true
end

local function uninstallSpawnWrapper()
  if core_vehicles and wrappedSpawnNewVehicle and core_vehicles.spawnNewVehicle == wrappedSpawnNewVehicle then
    core_vehicles.spawnNewVehicle = originalSpawnNewVehicle
  end
  wrappedSpawnNewVehicle = nil
end

-- Listings ------------------------------------------------------------------------------------------

local function generateShopId()
  local shopping = vehicleShopping()
  for _ = 1, 50 do
    local id = SHOP_ID_BASE + math.random(0, 999999)
    if not shopping.getVehicleInfoByShopId(id) then return id end
  end
  return SHOP_ID_BASE + math.random(0, 999999)
end

-- Local brand stores (RLS Italy "Online Dealerships") have no reachable door on the map, so they are
-- only opened from a computer. RLS sells such "local" dealers remotely only from reputation level 2 and
-- then needs a door as delivery origin. While a configurator order of such a store is open, the dealer
-- is treated as an online/factory store (remote checkout, freight point = its parking spot); the
-- original sales channel is restored right after the purchase or when the order is abandoned.
local channelOverride = nil

local function restoreDealerChannel()
  if not channelOverride then return end
  local dealer = channelOverride.dealer
  if type(dealer) == "table" then dealer.salesChannel = channelOverride.salesChannel end
  logI("restored sales channel of %s", tostring(channelOverride.id))
  channelOverride = nil
end

local function overrideDealerChannel(dealer)
  restoreDealerChannel()
  if type(dealer) ~= "table" or dealer.salesChannel == "factory" or dealer.salesChannel == "remanufactured"
      or dealer.remotePurchaseOnly then return end
  channelOverride = {dealer = dealer, id = dealer.id, salesChannel = dealer.salesChannel}
  dealer.salesChannel = "factory"
  logI("treating local brand store %s as online store for this order", tostring(dealer.id))
end

local function removeConfiguratorListings(keepShopId)
  local shopping = vehicleShopping()
  local list = shopping and safeCall(shopping.getVehiclesInShop)
  if type(list) ~= "table" then return 0 end
  local removed = 0
  for i = #list, 1, -1 do
    local listing = list[i]
    if type(listing) == "table" and listing.rlsConfigurator and listing.shopId ~= keepShopId and not listing.markedSold then
      table.remove(list, i)
      removed = removed + 1
    end
  end
  return removed
end

-- Engine swap (Phase 3 prototype) ------------------------------------------------------------------
-- The bought car = base config with its engine subtree (engine, ECU, turbo, intake, exhaust,
-- transmission ... found through the jbeam slot hierarchy) and drivetrain slots (fuel tank, transfer
-- case, differentials, shafts) replaced by those of a donor config of the same model.

-- BeamNG reports EVs with fuel "Battery" (some mods use "Electric"/"Electricity").
local function isElectricFuel(fuel)
  local lower = string.lower(tostring(fuel or ""))
  return lower == "battery" or string.find(lower, "electric", 1, true) ~= nil
end

local function isElectricConfig(cfg)
  return isElectricFuel(cfg and cfg.fuel)
end

-- engineSwapModels may list model keys or "*" (all models); engineSwapExcludedModels wins.
function swapEnabledFor(modelKey)
  for _, key in ipairs(getSettings().engineSwapExcludedModels or {}) do
    if key == modelKey then return false end
  end
  for _, key in ipairs(getSettings().engineSwapModels or {}) do
    if key == modelKey or key == "*" then return true end
  end
  return false
end

local function jbeamCtxFor(modelKey)
  local ok, jbeamIO = pcall(require, "jbeam/io")
  if not ok or type(jbeamIO) ~= "table" then return nil end
  jbeamPartName(modelKey, "__warmup__") -- creates/caches the ctx
  return jbeamCtxCache[modelKey] or nil, jbeamIO
end

local function collectSubtree(ctx, jbeamIO, parts, rootSlot, result)
  local function walk(slot, depth)
    if result[slot] or depth > 16 then return end
    result[slot] = true
    local partName = parts[slot]
    if type(partName) ~= "string" or partName == "" then return end
    local ok, part = pcall(jbeamIO.getPart, ctx, partName)
    if not ok or type(part) ~= "table" then return end
    -- getPart returns processed parts: slot rows are tables with named fields (type/name), and
    -- slotInfoUi maps slot -> info. Raw array rows are handled too.
    for _, field in ipairs({"slots", "slots2"}) do
      local rows = part[field]
      if type(rows) == "table" then
        for _, row in pairs(rows) do
          if type(row) == "table" then
            local name = row.name or row.type or row.slotType or row[1]
            if type(name) == "string" and name ~= "type" and name ~= "name" then walk(name, depth + 1) end
          end
        end
      end
    end
    if type(part.slotInfoUi) == "table" then
      for name in pairs(part.slotInfoUi) do
        if type(name) == "string" then walk(name, depth + 1) end
      end
    end
  end
  walk(rootSlot, 0)
  return result
end

local function swapSlots(ctx, jbeamIO, parts, engineSlot, otherParts, extraPatterns)
  local result = collectSubtree(ctx, jbeamIO, parts, engineSlot, {})
  local patterns = {}
  for _, pattern in ipairs(getSettings().drivetrainSlotPatterns or {}) do table.insert(patterns, pattern) end
  for _, pattern in ipairs(extraPatterns or {}) do table.insert(patterns, pattern) end
  local candidates = {}
  for slot in pairs(parts) do candidates[slot] = true end
  for slot in pairs(otherParts or {}) do candidates[slot] = true end
  for slot in pairs(candidates) do
    local lower = string.lower(slot)
    for _, pattern in ipairs(patterns) do
      if string.find(lower, pattern, 1, true) then
        collectSubtree(ctx, jbeamIO, parts, slot, result)
        break
      end
    end
  end
  return result
end

-- Returns the spawnable config table plus a short summary, or nil and a reason.
-- On an electric <-> combustion swap, badge/branding slots (e.g. "Tograc E" screen logo) are taken from
-- a config of the base car's own line with the donor's energy type, so the car keeps its name.
local function brandingFromLine(modelKey, baseRecord, donorCfg, merged)
  if not baseRecord then return {} end
  local patterns = getSettings().energyBrandingSlotPatterns or {}
  local wantElectric = isElectricConfig(donorCfg)
  local reference
  for _, cfg in ipairs(baseRecord.configs or {}) do
    if isElectricConfig(cfg) == wantElectric then
      if not reference or (cfg.configType == "Factory" and reference.configType ~= "Factory")
          or (cfg.configType == reference.configType and cfg.catalogValue < reference.catalogValue) then
        reference = cfg
      end
    end
  end
  if not reference then return {} end
  local refData = jsonReadFile("/vehicles/" .. modelKey .. "/" .. reference.key .. ".pc")
  local refParts = type(refData) == "table" and (refData.parts or refData.slotMap) or nil
  local changed = {}
  for slot, part in pairs(refParts or {}) do
    local lower = string.lower(slot)
    for _, pattern in ipairs(patterns) do
      if string.find(lower, pattern, 1, true) then
        if merged[slot] ~= part then table.insert(changed, slot .. "=" .. tostring(part)) end
        merged[slot] = part
        break
      end
    end
  end
  return changed
end

-- Part helpers for (cross-model) swaps -------------------------------------------------------------

local function getPartIn(ctx, jbeamIO, partName)
  if not ctx or type(partName) ~= "string" or partName == "" then return nil end
  local ok, part = pcall(jbeamIO.getPart, ctx, partName)
  return ok and type(part) == "table" and part or nil
end

local function partValueIn(ctx, jbeamIO, partName)
  local part = getPartIn(ctx, jbeamIO, partName)
  local info = part and part.information
  return tonumber(info and info.value) or 0
end

local function slotTypeMatches(part, slotName)
  local slotType = part and part.slotType
  if type(slotType) == "string" then return slotType == slotName end
  if type(slotType) == "table" then
    for _, t in pairs(slotType) do
      if t == slotName then return true end
    end
  end
  return false
end

-- "etkc_shifter_M" -> "etk800_shifter_M" when moving parts from model etkc to etk800. Prefixes are
-- lists: the model key plus the config's mainPartName (mods like "etkluxe_vibekers" name parts "etkluxe_").
local function mapModelPrefix(name, fromPrefixes, toPrefix)
  if type(name) ~= "string" or type(toPrefix) ~= "string" then return nil end
  if type(fromPrefixes) == "string" then fromPrefixes = {fromPrefixes} end
  for _, from in ipairs(fromPrefixes) do
    if from ~= toPrefix then
      local prefix = from .. "_"
      if string.sub(name, 1, #prefix) == prefix then return toPrefix .. "_" .. string.sub(name, #prefix + 1) end
    end
  end
  return nil
end

-- Builds the spawnable config: base config with the donor's powertrain. The donor may be another model
-- that shares the engine slot (e.g. ETK 800 / K-Series). Returns config, summary, partValueDelta
-- (catalog units: value of parts added minus value of parts removed) or nil + reason.
local function buildSwappedConfig(baseModel, baseCfg, donorModel, donorCfg, baseRecord, writeDebug)
  local basePath = "/vehicles/" .. baseModel .. "/" .. baseCfg.key .. ".pc"
  local donorPath = "/vehicles/" .. donorModel .. "/" .. donorCfg.key .. ".pc"
  local baseData, donorData = jsonReadFile(basePath), jsonReadFile(donorPath)
  if type(baseData) ~= "table" or type(donorData) ~= "table" then return nil, "config file unreadable" end
  local baseParts = baseData.parts or baseData.slotMap
  local donorParts = donorData.parts or donorData.slotMap
  if type(baseParts) ~= "table" or type(donorParts) ~= "table" then return nil, "config has no parts table" end
  local baseEngine, donorEngine = engineFor(baseModel, baseCfg.key), engineFor(donorModel, donorCfg.key)
  if not baseEngine or not donorEngine then return nil, "engine slot not found" end
  if baseEngine.slot ~= donorEngine.slot then return nil, "engine slots differ" end
  local ctx, jbeamIO = jbeamCtxFor(baseModel)
  if not ctx then return nil, "jbeam loader unavailable" end
  local donorCtx = donorModel == baseModel and ctx or jbeamCtxFor(donorModel)
  if not donorCtx then return nil, "donor jbeam unavailable" end
  local crossModel = donorModel ~= baseModel
  -- Part name prefixes: longest first so "etkluxe_vibekers_" wins over "etkluxe_".
  local donorPrefixes = {donorModel}
  if type(donorData.mainPartName) == "string" and donorData.mainPartName ~= donorModel then
    table.insert(donorPrefixes, donorData.mainPartName)
  end
  table.sort(donorPrefixes, function(a, b) return #a > #b end)
  local basePrefix = type(baseData.mainPartName) == "string" and baseData.mainPartName or baseModel
  if crossModel and not slotTypeMatches(getPartIn(ctx, jbeamIO, donorEngine.part), baseEngine.slot) then
    return nil, "engine part does not fit this model"
  end

  -- Electric <-> combustion also needs exhaust, cooling and the instrument cluster of the donor.
  local extra = nil
  local energyChange = isElectricConfig(baseCfg) ~= isElectricConfig(donorCfg)
  if energyChange then
    extra = deepcopy(getSettings().energyChangeSlotPatterns or {})
  end
  -- Exhaust: keep the base car's exhaust wherever both cars use the same exhaust slot (mid pipe,
  -- muffler, tips). Engine-specific slots (manifolds) only exist on one side and come from the donor.
  -- If tips/mufflers/exits only exist on one side, the layout differs: then the whole donor exhaust
  -- plus its rear bumper/diffuser (tip cut-outs) is used, otherwise the tips would clip.
  local keepBaseExhaust = {}
  local layoutDiffers = false
  local preferBase = getSettings().preferBaseExhaust ~= false
  local function nonEmpty(v) return type(v) == "string" and v ~= "" end
  local function donorValueFor(slot)
    local v = donorParts[slot]
    if v == nil and crossModel then
      for dSlot, dPart in pairs(donorParts) do
        if mapModelPrefix(dSlot, donorPrefixes, basePrefix) == slot then return dPart end
      end
    end
    return v
  end
  local slotsSeen = {}
  for slot in pairs(baseParts) do slotsSeen[slot] = true end
  for slot in pairs(donorParts) do slotsSeen[mapModelPrefix(slot, donorPrefixes, basePrefix) or slot] = true end
  for slot in pairs(slotsSeen) do
    local lower = string.lower(slot)
    if string.find(lower, "exhaust", 1, true) or string.find(lower, "muffler", 1, true) then
      local b, d = nonEmpty(baseParts[slot]), nonEmpty(donorValueFor(slot))
      if b and d then
        keepBaseExhaust[slot] = true
      elseif b ~= d and (string.find(lower, "tip", 1, true) or string.find(lower, "muffler", 1, true)
          or string.find(lower, "exit", 1, true)) then
        layoutDiffers = true
      elseif b ~= d and not string.find(lower, "%d") then
        layoutDiffers = true
      end
    end
  end
  if layoutDiffers or not preferBase then
    keepBaseExhaust = {}
    extra = extra or {}
    for _, pattern in ipairs(getSettings().exhaustBodySlotPatterns or {}) do table.insert(extra, pattern) end
  end
  local removeSlots = swapSlots(ctx, jbeamIO, baseParts, baseEngine.slot, donorParts, extra)
  local addSlots = swapSlots(donorCtx, jbeamIO, donorParts, donorEngine.slot, baseParts, extra)
  local baseEngineTree = collectSubtree(ctx, jbeamIO, baseParts, baseEngine.slot, {})

  local merged = {}
  for slot, part in pairs(baseParts) do
    if not removeSlots[slot] then merged[slot] = part end
  end
  local changed, skipped = {}, {}
  for slot in pairs(addSlots) do
    local part = donorParts[slot]
    if part ~= nil then
      if not crossModel or part == "" or getPartIn(ctx, jbeamIO, part) then
        merged[slot] = part
      else
        -- Model-specific donor part: use the base model's counterpart if it exists.
        local mappedSlot = mapModelPrefix(slot, donorPrefixes, basePrefix) or slot
        local mappedPart = mapModelPrefix(part, donorPrefixes, basePrefix)
        if mappedPart and getPartIn(ctx, jbeamIO, mappedPart) then
          merged[mappedSlot] = mappedPart
        else
          table.insert(skipped, slot .. "=" .. tostring(part))
        end
      end
    end
  end
  if crossModel then
    -- Body slots the donor could not fill keep the base part (instead of falling back to defaults).
    for slot in pairs(removeSlots) do
      if merged[slot] == nil and baseParts[slot] ~= nil and not baseEngineTree[slot] then
        merged[slot] = baseParts[slot]
      end
    end
  end
  -- Restore the kept base exhaust parts together with everything hanging off them (e.g. tips).
  local keptExhaust = {}
  for slot in pairs(keepBaseExhaust) do
    local subtree = collectSubtree(ctx, jbeamIO, baseParts, slot, {})
    for sub in pairs(subtree) do
      if baseParts[sub] ~= nil then
        merged[sub] = baseParts[sub]
        table.insert(keptExhaust, sub)
      end
    end
  end
  table.sort(keptExhaust)

  if energyChange then
    brandingFromLine(baseModel, baseRecord, donorCfg, merged)
  end

  -- Part value difference of everything that actually changed.
  local addedValue, removedValue = 0, 0
  local allSlots = {}
  for slot in pairs(baseParts) do allSlots[slot] = true end
  for slot in pairs(merged) do allSlots[slot] = true end
  for slot in pairs(allSlots) do
    local before, after = baseParts[slot], merged[slot]
    if before ~= after then
      table.insert(changed, slot .. "=" .. tostring(after))
      if nonEmpty(before) then removedValue = removedValue + partValueIn(ctx, jbeamIO, before) end
      if nonEmpty(after) then
        local v = partValueIn(ctx, jbeamIO, after)
        if v == 0 and crossModel then v = partValueIn(donorCtx, jbeamIO, after) end
        addedValue = addedValue + v
      end
    end
  end
  table.sort(changed)
  table.sort(skipped)

  local config = deepcopy(baseData)
  config.parts = merged
  config.slotMap = nil
  config.vars = deepcopy(baseData.vars or {})
  for key, value in pairs(donorData.vars or {}) do config.vars[key] = value end
  config.partConfigFilename = string.sub(basePath, 2)
  config.model = baseModel
  local delta = addedValue - removedValue
  if writeDebug and jsonWriteFile and getSettings().debugDump then
    pcall(jsonWriteFile, "/rlsConfigurator_lastSwap.json", {
      base = baseModel .. "/" .. baseCfg.key, donor = donorModel .. "/" .. donorCfg.key, engineSlot = baseEngine.slot,
      crossModel = crossModel, addedValue = addedValue, removedValue = removedValue, partValueDelta = delta,
      removed = (function() local t = {} for k in pairs(removeSlots) do table.insert(t, k) end table.sort(t) return t end)(),
      changed = changed, skippedDonorParts = skipped, keptBaseExhaust = keptExhaust, exhaustLayoutDiffers = layoutDiffers,
      parts = merged,
    }, true)
  end
  return config, string.format("%d slots changed, %d skipped, part delta %d", #changed, #skipped, delta), delta
end

-- Which engine parts fit which model: own engines always; engines of other models in the same shop
-- when the base model's jbeam knows the part and it fits the base engine slot (e.g. ETK 800 / K-Series
-- / 900 share "etk_engine"). Result: model_key -> list of engine part names.
local compatCache = {}
function swapCompatibilityFor(shop)
  if compatCache[shop.id] then return compatCache[shop.id] end
  local partsByModel, slotByModel = {}, {}
  for _, model in ipairs(shop.models) do
    partsByModel[model.model_key] = partsByModel[model.model_key] or {}
    for _, cfg in ipairs(model.configs) do
      local engine = engineFor(model.model_key, cfg.key)
      if engine then
        partsByModel[model.model_key][engine.part] = true
        slotByModel[model.model_key] = slotByModel[model.model_key] or engine.slot
      end
    end
  end
  local result = {}
  for baseModel, ownParts in pairs(partsByModel) do
    if swapEnabledFor(baseModel) then
      local fits, list = {}, {}
      for part in pairs(ownParts) do fits[part] = true end
      local ctx, jbeamIO = jbeamCtxFor(baseModel)
      if ctx and slotByModel[baseModel] then
        for otherModel, otherParts in pairs(partsByModel) do
          if otherModel ~= baseModel and slotByModel[otherModel] == slotByModel[baseModel] then
            for part in pairs(otherParts) do
              if not fits[part] and slotTypeMatches(getPartIn(ctx, jbeamIO, part), slotByModel[baseModel]) then
                fits[part] = true
              end
            end
          end
        end
      end
      for part in pairs(fits) do table.insert(list, part) end
      table.sort(list)
      result[baseModel] = list
    end
  end
  compatCache[shop.id] = result
  return result
end

-- Swap pricing is based on the value of the parts that actually change (jbeam part values), so a donor
-- from a more expensive car does not drag its body price along. Downgrades refund engineSwapRefundPct.
local function swapDeltaWithRefund(delta)
  local refund = (tonumber(getSettings().engineSwapRefundPct) or 0) / 100
  return delta > 0 and delta or delta * refund
end

-- Resale value base (catalog units), without configurator/delivery surcharge or conversion fee.
local function swapCatalogValueFor(baseCfg, delta)
  local discount = math.max(0, math.min(100, tonumber(getSettings().engineSwapValueDiscountPct) or 0))
  return math.max(0, math.floor((baseCfg.catalogValue + swapDeltaWithRefund(delta)) * (1 - discount / 100) + 0.5))
end

local function swapPriceFor(baseCfg, delta)
  local base = basePriceFor(baseCfg.catalogValue)
  local fee = base * (tonumber(getSettings().engineSwapFeePct) or 0) / 100
  return math.max(0, ceilTo(base + swapDeltaWithRefund(delta) * buyMultiplier() + fee, 10))
end

local function findConfigAnyRecord(shop, modelKey, configKey)
  for _, model in ipairs(shop.models) do
    if model.model_key == modelKey then
      for _, cfg in ipairs(model.configs) do
        if cfg.key == configKey then return model, cfg end
      end
    end
  end
  return nil
end

-- Equipment packages (wheels, suspension) ------------------------------------------------------------
-- A package takes the parts of one category (all slots matching its slotPatterns plus everything that
-- hangs off them, e.g. tyres and hubcaps below a wheel) from another config of the same model line.
-- Offered only when both cars use the same slots there, so the parts really fit. Price = part value
-- difference (jbeam values, downgrades refund packageRefundPct).
local packageCache = {}

local function readPcParts(modelKey, configKey)
  local data = jsonReadFile("/vehicles/" .. modelKey .. "/" .. configKey .. ".pc")
  if type(data) ~= "table" then return nil end
  local parts = data.parts or data.slotMap
  if type(parts) ~= "table" then return nil end
  return data, parts
end

local function packageCategory(id)
  for _, cat in ipairs(getSettings().packageCategories or {}) do
    if type(cat) == "table" and cat.id == id then return cat end
  end
  return nil
end

local function matchedSlots(parts, patterns)
  local roots = {}
  for slot in pairs(parts) do
    local lower = string.lower(slot)
    for _, pattern in ipairs(patterns or {}) do
      if string.find(lower, string.lower(pattern), 1, true) then roots[slot] = true; break end
    end
  end
  return roots
end

local function packageTree(ctx, jbeamIO, parts, roots)
  local tree = {}
  for slot in pairs(roots) do collectSubtree(ctx, jbeamIO, parts, slot, tree) end
  return tree
end

local function partsSignature(parts, tree)
  local list = {}
  for slot in pairs(tree) do
    local part = parts[slot]
    if type(part) == "string" and part ~= "" then table.insert(list, slot .. "=" .. part) end
  end
  table.sort(list)
  return table.concat(list, ";")
end

local function packageRefund(delta)
  local refund = (tonumber(getSettings().packageRefundPct) or 0) / 100
  return delta > 0 and delta or delta * refund
end

local function packagePriceFor(delta)
  return ceilTo(packageRefund(delta) * buyMultiplier(), 10)
end

-- Part name shown for an option: jbeam name of the first front part of the category.
local function packageLabel(ctx, jbeamIO, parts, roots)
  local slots = {}
  for slot in pairs(roots) do
    if type(parts[slot]) == "string" and parts[slot] ~= "" then table.insert(slots, slot) end
  end
  table.sort(slots, function(a, b)
    local fa = string.find(string.lower(a), "_f", 1, true) and 0 or 1
    local fb = string.find(string.lower(b), "_f", 1, true) and 0 or 1
    if fa ~= fb then return fa < fb end
    return a < b
  end)
  for _, slot in ipairs(slots) do
    local part = getPartIn(ctx, jbeamIO, parts[slot])
    local name = part and part.information and part.information.name
    if type(name) == "string" and name ~= "" then return name end
  end
  return nil
end

-- Options of all categories for one base config: {categoryId -> {option, ...}}.
local function packageOptionsFor(record, baseCfg)
  local s = getSettings()
  if s.packagesEnabled == false or not record or not baseCfg then return {} end
  local modelKey = record.model_key
  local cacheKey = tostring(record.id) .. "/" .. baseCfg.key
  if packageCache[cacheKey] then return packageCache[cacheKey] end
  local result = {}
  local baseData, baseParts = readPcParts(modelKey, baseCfg.key)
  local ctx, jbeamIO = jbeamCtxFor(modelKey)
  if not baseParts or not ctx then packageCache[cacheKey] = result; return result end
  for _, cat in ipairs(s.packageCategories or {}) do
    if type(cat) == "table" and type(cat.id) == "string" then
      local baseRoots = matchedSlots(baseParts, cat.slotPatterns)
      local baseTree = packageTree(ctx, jbeamIO, baseParts, baseRoots)
      local baseSig = partsSignature(baseParts, baseTree)
      local options, seen = {}, {[baseSig] = true}
      if next(baseRoots) then
        for _, donor in ipairs(record.configs or {}) do
          if donor.key ~= baseCfg.key then
            local _, donorParts = readPcParts(modelKey, donor.key)
            if donorParts then
              local donorRoots = matchedSlots(donorParts, cat.slotPatterns)
              local sameSlots = next(donorRoots) ~= nil
              for slot in pairs(donorRoots) do if baseParts[slot] == nil then sameSlots = false; break end end
              if sameSlots then
                for slot in pairs(baseRoots) do if donorParts[slot] == nil then sameSlots = false; break end end
              end
              if sameSlots then
                local donorTree = packageTree(ctx, jbeamIO, donorParts, donorRoots)
                local sig = partsSignature(donorParts, donorTree)
                if not seen[sig] then
                  seen[sig] = true
                  local added, removed = 0, 0
                  for slot in pairs(donorTree) do
                    local part = donorParts[slot]
                    if type(part) == "string" and part ~= "" then added = added + partValueIn(ctx, jbeamIO, part) end
                  end
                  for slot in pairs(baseTree) do
                    local part = baseParts[slot]
                    if type(part) == "string" and part ~= "" then removed = removed + partValueIn(ctx, jbeamIO, part) end
                  end
                  local delta = added - removed
                  table.insert(options, {
                    category = cat.id,
                    donorKey = donor.key,
                    sourceName = donor.name,
                    label = packageLabel(ctx, jbeamIO, donorParts, donorRoots) or donor.name,
                    partValueDelta = delta,
                    price = packagePriceFor(delta),
                  })
                end
              end
            end
          end
        end
      end
      table.sort(options, function(a, b) return a.price < b.price end)
      if #options > 0 then
        result[cat.id] = {
          id = cat.id,
          label = localized(cat.label) or cat.id,
          currentLabel = packageLabel(ctx, jbeamIO, baseParts, baseRoots),
          options = options,
        }
      end
    end
  end
  packageCache[cacheKey] = result
  return result
end

-- Applies chosen packages to a config table (parts + vars) in place. Returns total part value delta.
local function applyPackages(config, record, baseCfg, chosen)
  local options = packageOptionsFor(record, baseCfg)
  local modelKey = record.model_key
  local ctx, jbeamIO = jbeamCtxFor(modelKey)
  local _, baseParts = readPcParts(modelKey, baseCfg.key)
  local totalDelta, applied = 0, {}
  if not ctx or not baseParts then return 0, applied end
  config.parts = config.parts or {}
  config.vars = config.vars or {}
  for _, choice in ipairs(chosen or {}) do
    local catOptions = options[choice.category]
    local option
    for _, o in ipairs(catOptions and catOptions.options or {}) do
      if o.donorKey == choice.donorKey then option = o; break end
    end
    local cat = packageCategory(choice.category)
    local donorData, donorParts = readPcParts(modelKey, choice.donorKey or "")
    if option and cat and donorParts then
      local baseTree = packageTree(ctx, jbeamIO, baseParts, matchedSlots(baseParts, cat.slotPatterns))
      local donorTree = packageTree(ctx, jbeamIO, donorParts, matchedSlots(donorParts, cat.slotPatterns))
      for slot in pairs(baseTree) do config.parts[slot] = nil end
      for slot in pairs(donorTree) do
        if donorParts[slot] ~= nil then config.parts[slot] = donorParts[slot] end
      end
      -- Tuning variables of the new parts (ride height, spring rates ...) that the base car lacks.
      for key, value in pairs(type(donorData.vars) == "table" and donorData.vars or {}) do
        if config.vars[key] == nil then config.vars[key] = value end
      end
      totalDelta = totalDelta + option.partValueDelta
      table.insert(applied, {category = cat.id, categoryLabel = localized(cat.label) or cat.id,
        donorKey = option.donorKey, label = option.label, sourceName = option.sourceName,
        price = option.price, partValueDelta = option.partValueDelta})
    else
      logW("package %s/%s not available for %s", tostring(choice.category), tostring(choice.donorKey), baseCfg.key)
    end
  end
  return totalDelta, applied
end

local function baseConfigFor(modelKey, cfg)
  local data = readPcParts(modelKey, cfg.key)
  if type(data) ~= "table" then return nil end
  local config = deepcopy(data)
  config.parts = deepcopy(data.parts or data.slotMap or {})
  config.slotMap = nil
  config.vars = deepcopy(data.vars or {})
  config.partConfigFilename = "vehicles/" .. modelKey .. "/" .. cfg.key .. ".pc"
  config.model = modelKey
  return config
end

function M.requestPackages(sellerId, recordId, configKey)
  local result = {sellerId = sellerId, recordId = recordId, key = configKey, categories = {}}
  local ok, err = pcall(function()
    local shop = getShop(sellerId)
    if not shop then return end
    for _, model in ipairs(shop.models) do
      if (model.id or model.model_key) == recordId then
        for _, cfg in ipairs(model.configs) do
          if cfg.key == configKey then
            local options = packageOptionsFor(model, cfg)
            for _, cat in ipairs(getSettings().packageCategories or {}) do
              if type(cat) == "table" and options[cat.id] then table.insert(result.categories, options[cat.id]) end
            end
            return
          end
        end
      end
    end
  end)
  if not ok then logE("requestPackages failed: %s", tostring(err)) end
  guihooks.trigger("RlsConfiguratorPackages", result)
end

local function buildListing(shop, dealer, model, cfg, paintName, tier, donorCfg, swapDelta, donorModel, fulfilment, packagePrice)
  local listing = deepcopy(cfg.info)
  local base = donorCfg and swapPriceFor(cfg, swapDelta or 0) or basePriceFor(cfg.catalogValue)
  base = base + (tonumber(packagePrice) or 0)
  local surcharge = surchargeFor(shop)
  local price = finalPriceFor(base, tier, extraPctFor(cfg, donorCfg), surcharge)
  local deliveryFee = fulfilment == "garage" and garageDeliveryFeeFor(price) or 0
  price = price + deliveryFee
  if donorCfg then
    -- Show the swapped powertrain in RLS's purchase screen.
    local donorInfo = donorCfg.info or {}
    for _, field in ipairs({"Power", "Torque", "Fuel Type", "Drivetrain", "Transmission", "PowerPeakRPM", "TorquePeakRPM"}) do
      if donorInfo[field] ~= nil then listing[field] = donorInfo[field] end
    end
    listing.Configuration = tostring(cfg.name) .. " · " .. tostring(engineLabelFor(donorCfg, engineFor(donorModel or cfg.info.model_key, donorCfg.key)))
  end
  local mult = buyMultiplier()
  -- RLS re-derives the shown price as ceil10(valueBase * buyMultiplier); keep it at exactly `price`.
  local valueBase = (price - 0.01) / mult

  listing.shopId = generateShopId()
  listing.year = cfg.year
  listing.Mileage = 0
  listing.wearMileage = 0
  listing.Value = price
  listing.valueBase = valueBase
  listing.marketValue = valueBase
  listing.marketValueBase = valueBase
  listing.priceRoundingType = "default"
  listing.negotiationPossible = false
  listing.preview = cfg.preview or model.preview

  listing.sellerId = shop.id
  listing.sellerName = dealer.name or shop.name
  local access = safeCall(vehicleShopping().getSellerAccessInfo, dealer) or {}
  listing.salesChannel = dealer.salesChannel or (shop.localStore and access.salesChannel) or "factory"
  listing.associatedOrganization = dealer.associatedOrganization

  listing.remotePurchaseAllowed = access.remotePurchaseAllowed
  listing.garageDeliveryAllowed = access.garageDeliveryAllowed
  listing.deliveryDiscount = access.deliveryDiscount

  listing.fees = tonumber(dealer.fees) or 0
  listing.tax = tonumber(dealer.salesTax)
  listing.taxExempt = dealer.taxExempt
  listing.pos = safeCall(overhaul_world_facilities.getAverageDoorPositionForFacility, dealer)
  listing.mapId = getCurrentLevelIdentifier()
  listing.generationTime = os.time()
  listing.offerTTL = LISTING_TTL_SECONDS

  local insuranceClass = overhaul_career_repair_insurance
    and safeCall(overhaul_career_repair_insurance.getInsuranceClassFromVehicleShoppingData, listing)
  if insuranceClass then listing.insuranceClass = insuranceClass end

  listing.rlsConfigurator = {
    version = 1,
    paintName = paintName,
    paintNames = {paintName, paintName, paintName},
    tierId = tier.id,
    tierLabel = localized(tier.label) or tier.id,
    fulfilment = fulfilment,
    deliveryFee = deliveryFee,
    sellerName = dealer.name or shop.name,
    baseConfigName = cfg.name,
    localStore = shop.localStore == true,
    deliverySeconds = tierSeconds(tier),
    basePrice = base,
    surchargePct = surcharge + (tonumber(tier.surchargePct) or 0) + extraPctFor(cfg, donorCfg),
    orderedAt = os.time(),
  }
  return listing
end

-- UI API (called from the Vue overlay) --------------------------------------------------------------

local function sendOrderResult(ok, message)
  guihooks.trigger("RlsConfiguratorOrderResult", {ok = ok, message = message})
end

function M.requestAvailability(sellerId)
  local shop = safeCall(getShop, sellerId)
  guihooks.trigger("RlsConfiguratorAvailability", {
    sellerId = sellerId,
    available = shop ~= nil and #shop.models > 0,
    shopName = shop and shop.name or nil,
  })
end

function M.requestCatalog(sellerId)
  local shop = safeCall(getShop, sellerId)
  if not shop then
    guihooks.trigger("RlsConfiguratorCatalog", {sellerId = sellerId, error = T("noConfigurator")})
    return
  end
  local ok, data = pcall(catalogForUi, shop)
  pcall(writeEngineDump, shop)
  if not ok then
    logE("catalogForUi failed: %s", tostring(data))
    guihooks.trigger("RlsConfiguratorCatalog", {sellerId = sellerId, error = T("catalogFailed")})
    return
  end
  guihooks.trigger("RlsConfiguratorCatalog", data)
end

-- Swap quotes: the UI asks for prices of all donor options of a base config. Cached per pair.
local swapQuoteCache = {}

function M.requestSwapQuotes(sellerId, baseModel, baseKey, donorsJson)
  local result = {sellerId = sellerId, baseModel = baseModel, baseKey = baseKey, quotes = {}}
  local ok, err = pcall(function()
    local shop = getShop(sellerId)
    if not shop then return end
    local baseRecord, baseCfg = findConfig(shop, baseModel, baseKey)
    if not baseCfg then return end
    local donors = type(donorsJson) == "string" and jsonDecode(donorsJson) or {}
    for _, donorRef in ipairs(type(donors) == "table" and donors or {}) do
      local dModel, dKey = donorRef.model, donorRef.key
      local cacheKey = baseModel .. "/" .. baseKey .. "|" .. tostring(dModel) .. "/" .. tostring(dKey)
      local quote = swapQuoteCache[cacheKey]
      if quote == nil then
        local _, donor = findConfigAnyRecord(shop, dModel, dKey)
        if donor then
          local config, info, delta = buildSwappedConfig(baseModel, baseCfg, dModel, donor, baseRecord, false)
          if config then
            quote = {ok = true, basePrice = swapPriceFor(baseCfg, delta), partValueDelta = delta}
          else
            quote = {ok = false, reason = info}
          end
        else
          quote = {ok = false, reason = "donor not found"}
        end
        swapQuoteCache[cacheKey] = quote
      end
      result.quotes[tostring(dModel) .. "/" .. tostring(dKey)] = quote
    end
  end)
  if not ok then logE("requestSwapQuotes failed: %s", tostring(err)) end
  guihooks.trigger("RlsConfiguratorSwapQuotes", result)
end

local function placeOrderInternal(sellerId, modelKey, configKey, paintName, tierId, donorKey, donorModel, fulfilment, packagesJson)
  local shopping = vehicleShopping()
  if not shopping then return false, T("shoppingUnavailable") end
  local shop = getShop(sellerId)
  if not shop then return false, T("shopNotFound") end
  local dealer = overhaul_world_facilities.getDealership(sellerId)
  if not dealer then return false, T("shopNotFound") end
  local model, cfg = findConfig(shop, modelKey, configKey)
  if not cfg then return false, T("configNotFound") end

  local paints = paintsForModel(modelKey)
  local paintValid = false
  for _, paint in ipairs(paints) do
    if paint.name == paintName then paintValid = true; break end
  end
  if not paintValid then
    paintName = cfg.defaultPaint or (paints[1] and paints[1].name)
  end

  local donorCfg, swappedConfig, swapDelta
  if type(donorModel) ~= "string" or donorModel == "" then donorModel = modelKey end
  if type(donorKey) == "string" and donorKey ~= "" and (donorKey ~= configKey or donorModel ~= modelKey) then
    if not swapEnabledFor(modelKey) then return false, T("swapUnavailable") end
    local _, donor = findConfigAnyRecord(shop, donorModel, donorKey)
    if not donor then return false, T("swapUnavailable") end
    if isElectricConfig(cfg) ~= isElectricConfig(donor) and not getSettings().allowEnergyTypeSwap then
      return false, T("swapIncompatible")
    end
    local config, info, delta = buildSwappedConfig(modelKey, cfg, donorModel, donor, model, true)
    if not config then
      logW("engine swap %s <- %s/%s failed: %s", configKey, donorModel, donorKey, tostring(info))
      return false, T("swapIncompatible")
    end
    logI("engine swap %s <- %s/%s: %s", configKey, donorModel, donorKey, tostring(info))
    donorCfg, swappedConfig, swapDelta = donor, config, delta
  end

  -- Packages: applied on top of the (swapped) config; prices recomputed here, never taken from the UI.
  local chosenPackages = type(packagesJson) == "string" and packagesJson ~= "" and jsonDecode(packagesJson) or nil
  local finalConfig = swappedConfig
  local packageDelta, appliedPackages = 0, {}
  if type(chosenPackages) == "table" and chosenPackages[1] and getSettings().packagesEnabled ~= false then
    finalConfig = finalConfig or baseConfigFor(modelKey, cfg)
    if not finalConfig then return false, T("configNotFound") end
    packageDelta, appliedPackages = applyPackages(finalConfig, model, cfg, chosenPackages)
    if #appliedPackages == 0 and not swappedConfig then finalConfig = nil end
  end
  local packagePrice = 0
  for _, pkg in ipairs(appliedPackages) do packagePrice = packagePrice + pkg.price end

  local tier = getTier(tierId)
  removeConfiguratorListings(nil)
  restoreDealerChannel()
  if shop.localStore and getSettings().localStoresAsOnline ~= false then overrideDealerChannel(dealer) end
  fulfilment = normalizeFulfilment(fulfilment)
  local listing = buildListing(shop, dealer, model, cfg, paintName, tier, donorCfg, swapDelta, donorModel, fulfilment, packagePrice)
  if #appliedPackages > 0 then
    listing.rlsConfigurator.packages = appliedPackages
    local names = {}
    for _, pkg in ipairs(appliedPackages) do table.insert(names, pkg.label) end
    listing.Configuration = tostring(listing.Configuration or cfg.name) .. " · " .. table.concat(names, " · ")
  end
  if donorCfg or #appliedPackages > 0 then
    -- Resale value base of what was actually built (catalog units), see onOverhaulVehicleAddedToInventory.
    local discount = math.max(0, math.min(100, tonumber(getSettings().engineSwapValueDiscountPct) or 0))
    local delta = (donorCfg and swapDeltaWithRefund(swapDelta or 0) or 0) + packageRefund(packageDelta)
    listing.rlsConfigurator.catalogValue = math.max(0, math.floor((cfg.catalogValue + delta) * (1 - discount / 100) + 0.5))
  end
  if donorCfg then
    listing.rlsConfigurator.swap = {
      donorModel = donorModel,
      donorKey = donorCfg.key,
      engineLabel = engineLabelFor(donorCfg, engineFor(donorModel, donorCfg.key)),
      partValueDelta = swapDelta,
      catalogValue = swapCatalogValueFor(cfg, swapDelta or 0),
    }
  end
  table.insert(shopping.getVehiclesInShop(), listing)

  if (paintName or finalConfig) and installSpawnWrapper() then
    armedPaint = {
      model_key = modelKey,
      key = configKey,
      paintNames = paintName and listing.rlsConfigurator.paintNames or nil,
      config = finalConfig,
      donorKey = donorCfg and donorCfg.key or nil,
      expires = os.time() + PAINT_ARM_SECONDS,
      shopId = listing.shopId,
    }
    if finalConfig and listing.rlsConfigurator.paintNames then
      -- Keep the chosen paint inside the swapped config as well.
      local modelData = getModelData(modelKey)
      local modelPaints = modelData and modelData.model and modelData.model.paints
      if type(modelPaints) == "table" and modelPaints[paintName] then
        finalConfig.paints = {deepcopy(modelPaints[paintName]), deepcopy(modelPaints[paintName]), deepcopy(modelPaints[paintName])}
      end
    end
  end

  logI("order %s %s/%s paint=%s tier=%s packages=%d price=%d shopId=%d", sellerId, modelKey, configKey,
    tostring(paintName), tostring(tier.id), #appliedPackages, listing.Value, listing.shopId)
  shopping.openPurchaseMenu("instant", listing.shopId)
  return true
end

function M.placeOrder(sellerId, modelKey, configKey, paintName, tierId, donorKey, donorModel, fulfilment, packagesJson)
  local ok, result, message = pcall(placeOrderInternal, sellerId, modelKey, configKey, paintName, tierId, donorKey, donorModel, fulfilment, packagesJson)
  if not ok then
    logE("placeOrder failed: %s", tostring(result))
    sendOrderResult(false, T("orderFailedLog"))
    return
  end
  if not result then
    sendOrderResult(false, message or T("orderFailed"))
    return
  end
  sendOrderResult(true)
end

function M.reloadCatalog()
  loadSettings()
  shopIndex = nil
  packageCache = {}
  buildShopIndex()
end

-- Hooks ---------------------------------------------------------------------------------------------

local function applyPaintToRecord(record, modelKey, paintNames)
  if type(record) ~= "table" or type(record.config) ~= "table" then return end
  local modelData = getModelData(modelKey)
  local modelPaints = modelData and modelData.model and modelData.model.paints
  if type(modelPaints) ~= "table" then return end
  local paints = type(record.config.paints) == "table" and deepcopy(record.config.paints) or {}
  for i, name in ipairs(paintNames) do
    if name and modelPaints[name] then paints[i] = deepcopy(modelPaints[name]) end
  end
  record.config.colors = nil
  record.config.paints = paints
  record.config.paintName = paintNames[1]
  record.config.paintName2 = paintNames[2]
  record.config.paintName3 = paintNames[3]
end

-- Own order protocol: BeamNG's log is capped at 15000 lines and cuts the middle of long sessions.
local ORDER_LOG_PATH = "/rlsConfigurator_orders.json"
local function appendOrderLog(entry)
  if not jsonWriteFile or not getSettings().debugDump then return end
  local list = jsonReadFile(ORDER_LOG_PATH)
  if type(list) ~= "table" then list = {} end
  table.insert(list, entry)
  while #list > 100 do table.remove(list, 1) end
  pcall(jsonWriteFile, ORDER_LOG_PATH, list, true)
end

function M.onOverhaulVehicleAddedToInventory(data)
  local info = type(data) == "table" and data.vehicleInfo
  local order = type(info) == "table" and info.rlsConfigurator
  if type(order) ~= "table" then return end
  armedPaint = nil
  restoreDealerChannel()

  local inv = inventory()
  local inventoryId = data.inventoryId
  local record = inv and inv.getVehicles()[inventoryId]
  if not record then
    logW("bought configurator vehicle not found in inventory (%s)", tostring(inventoryId))
    return
  end

  if order.paintNames then pcall(applyPaintToRecord, record, info.model_key, order.paintNames) end

  -- RLS values inventory cars from the base config's catalog value; a swapped car gets the value of
  -- what was actually built instead (see swapCatalogValueFor).
  local valueBefore = record.configBaseValue
  local builtValue = tonumber(order.catalogValue) or (type(order.swap) == "table" and tonumber(order.swap.catalogValue)) or nil
  if builtValue then
    record.configBaseValue = builtValue
    logI("custom build value: configBaseValue %s -> %s", tostring(valueBefore), tostring(record.configBaseValue))
  end
  pcall(appendOrderLog, {
    time = os.date("%Y-%m-%d %H:%M:%S"),
    inventoryId = inventoryId,
    model = info.model_key, config = info.key, name = info.Configuration,
    paint = order.paintName, tier = order.tierId, price = info.Value,
    swap = order.swap, packages = order.packages,
    configBaseValueBefore = valueBefore, configBaseValueAfter = record.configBaseValue,
  })

  local atFreight = type(record.location) == "string" and string.find(record.location, "^freightPickup") ~= nil
  if order.localStore and not atFreight and safeCall(inv.getVehicleIdFromInventoryId, inventoryId) then
    -- Local brand store (e.g. RLS Italy online dealerships): RLS put the car straight onto the dealer
    -- lot. A built-to-order car is not there yet, so park it on RLS's pickup state like an online order.
    local garage = safeCall(inv.getClosestOwnedGarageWithSpace)
    record.location = "freightPickup:" .. tostring(info.sellerId)
    record.niceLocation = order.sellerName or "Freight Pickup"
    record.lastKnownLevel = getCurrentLevelIdentifier()
    record.freightHomeGarageId = type(garage) == "table" and garage.id or nil
    atFreight = true
    logI("local store order %s: moved from dealer lot to pickup state", tostring(inventoryId))
  end
  local pickup = order.fulfilment == "pickup"
  if pickup and atFreight then
    -- The car is still being built: take it off the freight point, it re-appears there when the
    -- delivery time is over (see updatePickups).
    safeCall(inv.removeVehicleObject, inventoryId)
    record.rlsConfiguratorPickup = {sellerId = info.sellerId, sellerName = order.sellerName, atDealer = order.localStore == true}
    if core_groundMarkers and core_groundMarkers.setPath then pcall(core_groundMarkers.setPath, nil) end
  elseif pickup then
    pickup = false -- RLS delivered to a garage itself (dealer reputation level 2+)
  end
  if not pickup and getSettings().convertFreightPickupToGarageDelivery and atFreight then
    local garageId = record.freightHomeGarageId
    safeCall(inv.removeVehicleObject, inventoryId)
    local moved = safeCall(inv.moveVehicleToGarage, inventoryId, garageId)
    if moved then
      record.freightHomeGarageId = nil
      if core_groundMarkers and core_groundMarkers.setPath then pcall(core_groundMarkers.setPath, nil) end
    else
      logW("could not move configurator vehicle %s from freight pickup to a garage", tostring(inventoryId))
    end
  end

  local wanted = tonumber(order.deliverySeconds) or 0
  local current = tonumber(record.timeToAccess) or 0
  if wanted > current then
    inv.delayVehicleAccess(inventoryId, wanted, "bought")
  end
  local total = math.max(wanted, current)

  -- Marker for the order overview (kept on the inventory record, so it survives saving).
  local packageNames = {}
  for _, pkg in ipairs(type(order.packages) == "table" and order.packages or {}) do
    table.insert(packageNames, string.format("%s: %s", tostring(pkg.categoryLabel or pkg.category), tostring(pkg.label)))
  end
  record.rlsConfiguratorOrder = {
    name = string.format("%s %s", tostring(info.Brand or ""), tostring(info.Name or info.model_key or "")),
    config = order.baseConfigName or info.Configuration,
    preview = info.preview,
    sellerId = info.sellerId,
    sellerName = order.sellerName,
    tierLabel = order.tierLabel,
    fulfilment = pickup and "pickup" or "garage",
    deliverySeconds = total,
    orderedAt = os.time(),
    price = info.Value,
    engine = type(order.swap) == "table" and order.swap.engineLabel or nil,
    packages = packageNames,
    paint = order.paintName,
  }

  local name = string.format("%s %s", tostring(info.Brand or ""), tostring(info.Name or info.model_key or ""))
  if pickup then
    ui_message(string.format(T(order.localStore and "orderedPickupDealer" or "orderedPickup"), name, tostring(order.tierLabel or ""), tostring(order.sellerName or ""),
      formatDuration(total)), 10, "rlsConfigurator", "info")
  else
    ui_message(string.format(T("ordered"), name, tostring(order.tierLabel or ""), formatDuration(total)),
      10, "rlsConfigurator", "info")
  end
  logI("delivered order inventoryId=%s delay=%ds location=%s", tostring(inventoryId), total, tostring(record.location))
end

-- Availability is driven from Lua: BeamNG 0.40 routes UI screens through the Lua ui_router, so Lua
-- knows when the RLS vehicle list is shown and for which seller.
local pickupCheckTimer = 0
local pickupSpawning = {}

local function freightSpotFor(sellerId)
  local dealer = overhaul_world_facilities and safeCall(overhaul_world_facilities.getDealership, sellerId)
  if not dealer then return nil end
  local facility = dealer
  if type(dealer.freightPickupSpotNames) == "table" then
    facility = deepcopy(dealer)
    facility.parkingSpotNames = dealer.freightPickupSpotNames
  end
  local spots = safeCall(overhaul_world_facilities.getParkingSpotsForFacility, facility) or {}
  local fallback
  for _, spot in pairs(spots) do
    if spot and spot.pos then
      fallback = fallback or spot
      local ok, busy = pcall(function() return spot:hasAnyVehicles() end)
      if ok and not busy then return spot end
    end
  end
  return fallback
end

-- Order overview ------------------------------------------------------------------------------------
-- status: production (delivery time running), pickup (ready at the dealer / freight point),
-- delivered (in a garage or already driven). Open orders first, then the latest delivered ones.
local function collectOrders()
  local inv = inventory()
  local vehicles = inv and safeCall(inv.getVehicles)
  local open, done = {}, {}
  if type(vehicles) ~= "table" then return open, done end
  for inventoryId, record in pairs(vehicles) do
    local order = type(record) == "table" and record.rlsConfiguratorOrder or nil
    if type(order) == "table" then
      local entry = deepcopy(order)
      entry.inventoryId = inventoryId
      entry.location = record.niceLocation
      local remaining = tonumber(record.timeToAccess) or 0
      if remaining > 0 then
        entry.status = "production"
        entry.remaining = remaining
        entry.remainingText = formatDuration(remaining)
        local totalTime = math.max(tonumber(order.deliverySeconds) or remaining, remaining)
        entry.progress = totalTime > 0 and (1 - remaining / totalTime) or 0
        table.insert(open, entry)
      elseif record.rlsConfiguratorPickup then
        entry.status = "pickup"
        entry.progress = 1
        table.insert(open, entry)
      else
        entry.status = "delivered"
        entry.progress = 1
        table.insert(done, entry)
      end
    end
  end
  table.sort(open, function(a, b) return (a.remaining or 0) < (b.remaining or 0) end)
  table.sort(done, function(a, b) return (a.orderedAt or 0) > (b.orderedAt or 0) end)
  return open, done
end

-- Actions from the order overview for cars waiting at a pickup point:
--   route  = set a route to the car (or to the pickup spot if it is not spawned yet)
--   garage = deliver it to a garage instead (garage delivery fee), e.g. if the spot is unreachable
function M.orderAction(inventoryIdValue, action)
  local inv = inventory()
  local inventoryId = tonumber(inventoryIdValue) or inventoryIdValue
  local vehicles = inv and safeCall(inv.getVehicles)
  local record = type(vehicles) == "table" and vehicles[inventoryId] or nil
  local order = type(record) == "table" and record.rlsConfiguratorOrder or nil
  if not order then
    logW("orderAction %s: inventory vehicle %s not found", tostring(action), tostring(inventoryIdValue))
    return M.requestOrders()
  end
  local name = tostring(order.name or "")
  local ok, err = pcall(function()
    if action == "route" then
      local pos
      local vehId = safeCall(inv.getVehicleIdFromInventoryId, inventoryId)
      local veh = vehId and getObjectByID(vehId)
      if veh then pos = veh:getPosition() end
      if not pos and record.rlsConfiguratorPickup then
        local spot = freightSpotFor(record.rlsConfiguratorPickup.sellerId or order.sellerId)
        pos = spot and spot.pos
      end
      if pos and core_groundMarkers and core_groundMarkers.setPath then
        core_groundMarkers.setPath(pos)
        ui_message(string.format(T("routeSet"), name), 6, "rlsConfigurator", "info")
      else
        ui_message(T("routeFailed"), 6, "rlsConfigurator", "warning")
      end
    elseif action == "garage" then
      if safeCall(inv.getVehicleIdFromInventoryId, inventoryId) then safeCall(inv.removeVehicleObject, inventoryId) end
      local moved = safeCall(inv.moveVehicleToGarage, inventoryId, record.freightHomeGarageId)
      if not moved then
        ui_message(T("redirectFailed"), 8, "rlsConfigurator", "warning")
        return
      end
      record.rlsConfiguratorPickup = nil
      record.freightHomeGarageId = nil
      pickupSpawning[inventoryId] = nil
      local fee = garageDeliveryFeeFor(tonumber(order.price) or 0)
      if fee > 0 and overhaul_career_economy_payment and overhaul_career_economy_payment.pay then
        local tag = {label = "Configurator: delivery to garage", tags = {"delivery"}}
        local okMeta, metadata = pcall(require, "overhaul/lib/finance/metadata")
        if okMeta and type(metadata) == "table" and metadata.tag then
          tag = metadata.tag(tag, "service", {vehicleId = inventoryId})
        end
        pcall(overhaul_career_economy_payment.pay, {money = {amount = fee, canBeNegative = true}}, tag)
      end
      local delay = 120
      inv.delayVehicleAccess(inventoryId, delay, "delivery")
      order.fulfilment = "garage"
      order.deliverySeconds = delay
      if core_groundMarkers and core_groundMarkers.setPath then pcall(core_groundMarkers.setPath, nil) end
      ui_message(string.format(T("redirected"), name, "$" .. tostring(fee), formatDuration(delay)), 8, "rlsConfigurator", "info")
      logI("order %s redirected from pickup to garage, fee %d", tostring(inventoryId), fee)
    end
  end)
  if not ok then logE("orderAction %s failed: %s", tostring(action), tostring(err)) end
  M.requestOrders()
end

function M.requestOrders()
  local ok, open, done = pcall(collectOrders)
  if not ok then
    logE("requestOrders failed: %s", tostring(open))
    open, done = {}, {}
  end
  local limit = tonumber(getSettings().orderHistoryCount) or 8
  local list = {}
  for _, entry in ipairs(open) do table.insert(list, entry) end
  for i, entry in ipairs(done) do
    if i > limit then break end
    table.insert(list, entry)
  end
  guihooks.trigger("RlsConfiguratorOrders", {lang = getLang(), orders = list, openCount = #open})
end

local VEHICLE_LIST_STATE = "overhaul.computer.vehicleShopping.vehicles"
local uiState = nil
local lastSellerId = nil
local availabilityShown = false
local availabilityCheckPending = false

-- RLS restores the seller from route params without firing the selection hook, so ask RLS first.
local function currentSelectedSellerId()
  local shopping = vehicleShopping()
  local data = shopping and safeCall(shopping.getShoppingData)
  local sellerId = type(data) == "table" and (data.selectedSellerId or data.currentSeller) or nil
  return sellerId or lastSellerId
end

local function hideAvailability()
  if not availabilityShown then return end
  availabilityShown = false
  guihooks.trigger("RlsConfiguratorAvailability", {available = false})
end

-- While the RLS purchase menu shows a configurator order, the UI relabels the freight-pickup wording
-- (the order is delivered to a garage instead, see convertFreightPickupToGarageDelivery).
local PURCHASE_STATE = "overhaul.computer.vehicleShopping.vehicles.vehiclePurchase"
local purchaseNoticeActive = false

local function setPurchaseNotice(active)
  if purchaseNoticeActive == active then return end
  purchaseNoticeActive = active
  guihooks.trigger("RlsConfiguratorPurchase", {
    active = active,
    lang = getLang(),
    garageDelivery = getSettings().convertFreightPickupToGarageDelivery == true,
  })
end

function M.onOverhaulVehicleShoppingPurchaseMenuOpened(data)
  local shopId = type(data) == "table" and data.shopId or nil
  local shopping = vehicleShopping()
  local listing = shopId and shopping and safeCall(shopping.getVehicleInfoByShopId, shopId)
  local order = type(listing) == "table" and listing.rlsConfigurator or nil
  -- Pickup orders keep RLS's "Order for Pickup" wording, garage orders get relabelled.
  setPurchaseNotice(type(order) == "table" and order.fulfilment ~= "pickup")
end

-- Pickup orders: once the delivery time is over the car is placed on the store's freight point.
-- State lives in the inventory record (rlsConfiguratorPickup), so it survives saving and loading.

local function updatePickups()
  local inv = inventory()
  local vehicles = inv and safeCall(inv.getVehicles)
  if type(vehicles) ~= "table" then return end
  local level = getCurrentLevelIdentifier()
  for inventoryId, record in pairs(vehicles) do
    local pickup = type(record) == "table" and record.rlsConfiguratorPickup or nil
    if pickup then
      local atFreight = type(record.location) == "string" and string.find(record.location, "^freightPickup") ~= nil
      if not atFreight then
        record.rlsConfiguratorPickup = nil -- collected (RLS moved it to the home garage)
      elseif not record.timeToAccess and not pickupSpawning[inventoryId]
          and (not record.lastKnownLevel or record.lastKnownLevel == level)
          and not safeCall(inv.getVehicleIdFromInventoryId, inventoryId) then
        local spot = freightSpotFor(pickup.sellerId)
        if spot then
          pickupSpawning[inventoryId] = true
          local ok, err = pcall(inv.spawnVehicle, inventoryId, nil, function(success)
            pickupSpawning[inventoryId] = nil
            if success == false then
              logW("pickup spawn failed for %s", tostring(inventoryId))
              return
            end
            local name = tostring(record.niceName or record.model or "")
            ui_message(string.format(T(pickup.atDealer and "pickupReadyDealer" or "pickupReady"), name, tostring(pickup.sellerName or "")), 10, "rlsConfigurator", "info")
            if core_groundMarkers and core_groundMarkers.setPath then pcall(core_groundMarkers.setPath, spot.pos) end
            logI("pickup ready: inventoryId=%s at %s", tostring(inventoryId), tostring(pickup.sellerId))
          end, {pos = spot.pos, rot = spot.rot})
          if not ok then
            pickupSpawning[inventoryId] = nil
            logW("pickup spawn error for %s: %s", tostring(inventoryId), tostring(err))
          end
        end
      end
    end
  end
end

function M.onUiChangedState(toState)
  if toState ~= PURCHASE_STATE then setPurchaseNotice(false) end
  -- Purchase finished or left: the override was only needed for the checkout itself.
  if channelOverride and not string.find(tostring(toState or ""), "vehiclePurchase", 1, true) then
    restoreDealerChannel()
  end
  uiState = toState
  if toState == VEHICLE_LIST_STATE then
    availabilityCheckPending = true
  else
    availabilityCheckPending = false
    hideAvailability()
  end
end

function M.onUpdate(dtReal)
  pickupCheckTimer = pickupCheckTimer + (tonumber(dtReal) or 0)
  if pickupCheckTimer >= 3 then
    pickupCheckTimer = 0
    pcall(updatePickups)
  end
  if not availabilityCheckPending then return end
  availabilityCheckPending = false
  local sellerId = currentSelectedSellerId()
  if not sellerId then return end
  local shop = safeCall(getShop, sellerId)
  local available = shop ~= nil and #shop.models > 0
  availabilityShown = available
  logI("availability %s: %s", tostring(sellerId), tostring(available))
  local payload = {sellerId = sellerId, available = available, shopName = shop and shop.name or nil, lang = getLang()}
  if available then
    -- Teaser data for the card inside the RLS list.
    local fromPrice, configCount, preview = nil, 0, nil
    local tier = getTier(getSettings().defaultDeliveryTier)
    local surcharge = surchargeFor(shop)
    for _, model in ipairs(shop.models) do
      configCount = configCount + #model.configs
      preview = preview or model.preview
      for _, cfg in ipairs(model.configs) do
        local price = finalPriceFor(basePriceFor(cfg.catalogValue), tier, extraPctFor(cfg), surcharge)
        fromPrice = fromPrice and math.min(fromPrice, price) or price
      end
    end
    payload.modelCount = #shop.models
    payload.configCount = configCount
    payload.fromPrice = fromPrice
    payload.preview = preview
    local names = {}
    for i, model in ipairs(shop.models) do
      if i > 4 then break end
      table.insert(names, model.name)
    end
    payload.modelNames = table.concat(names, ", ") .. (#shop.models > 4 and " …" or "")
    local okOrders, openOrders = pcall(collectOrders)
    payload.openOrders = okOrders and type(openOrders) == "table" and #openOrders or 0
  end
  guihooks.trigger("RlsConfiguratorAvailability", payload)
end

-- Leaving or switching the seller abandons an unfinished order: drop its listing and the paint arm.
function M.onOverhaulVehicleShoppingSelectedSellerIdChanged(sellerId)
  lastSellerId = sellerId
  local removed = removeConfiguratorListings(nil)
  if removed > 0 then logI("removed %d unfinished configurator listing(s)", removed) end
  restoreDealerChannel()
  armedPaint = nil
  if uiState == VEHICLE_LIST_STATE then availabilityCheckPending = true end
  if not sellerId then hideAvailability() end
end

-- Dealer ids repeat across maps (e.g. ETKDealership on West Coast and Italy): rebuild per level.
function M.onClientStartMission()
  shopIndex = nil
  shopIndexLevel = nil
  compatCache = {}
  swapQuoteCache = {}
  packageCache = {}
end

function M.onModActivated()
  shopIndex = nil
  compatCache = {}
  swapQuoteCache = {}
  packageCache = {}
end
M.onModDeactivated = M.onModActivated

function M.onExtensionLoaded()
  loadSettings()
  installSpawnWrapper()
  logI("loaded v%s", MOD_VERSION)
end

function M.onExtensionUnloaded()
  restoreDealerChannel()
  uninstallSpawnWrapper()
end

return M
