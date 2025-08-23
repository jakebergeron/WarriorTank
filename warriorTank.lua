-- WarriorTank: safer, TurtleWoW-friendly version
WarriorTank = {}

-- ====== Core constants & utilities ======
local BOOK = BOOKTYPE_SPELL or "spell"

-- Simple spell index cache (name -> spellbook index)
local WarriorTank_SpellIndexCache = {}

local function WarriorTank_ClearCache()
  for k in pairs(WarriorTank_SpellIndexCache) do
    WarriorTank_SpellIndexCache[k] = nil
  end
end

local function WarriorTank_RebuildSpellIndexCache()
  WarriorTank_ClearCache()
  local i = 1
  while true do
    local name, rank = GetSpellName(i, BOOK)
    if not name then break end
    -- store latest index for this name (in 1.12, higher ranks are usually later)
    WarriorTank_SpellIndexCache[name] = i
    i = i + 1
  end
end

-- Ensure cache stays fresh as the spellbook changes
do
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_LOGIN")
  f:RegisterEvent("SPELLS_CHANGED")
  f:RegisterEvent("LEARNED_SPELL_IN_TAB")
  f:SetScript("OnEvent", function() WarriorTank_RebuildSpellIndexCache() end)
end

-- Check if we know a spell by name
local function WarriorTank_Knows(spellName)
  if not spellName then return false end
  local idx = WarriorTank_SpellIndexCache[spellName]
  if idx then return true end
  -- lazy rebuild attempt if cache is cold
  WarriorTank_RebuildSpellIndexCache()
  return WarriorTank_SpellIndexCache[spellName] ~= nil
end

-- Safe cooldown by spell name; returns (start, duration, enabled)
local function WarriorTank_GetCooldownByName(spellName)
  if not spellName then return 0, 0, 1 end
  local idx = WarriorTank_SpellIndexCache[spellName]
  if not idx then
    WarriorTank_RebuildSpellIndexCache()
    idx = WarriorTank_SpellIndexCache[spellName]
  end
  if not idx then
    -- Not known; treat as ready so callers can skip gracefully
    return 0, 0, 1
  end
  local s, d, e = GetSpellCooldown(idx, BOOK)
  return s or 0, d or 0, e or 1
end

-- ====== Addon bootstrap ======
function WarriorTank_OnLoad()
  this:RegisterEvent("PLAYER_ENTERING_WORLD")
  this:RegisterEvent("ADDON_LOADED")
  DEFAULT_CHAT_FRAME:AddMessage("WarriorTank addon loaded. Type /tank for usage.")

  SlashCmdList["WARRIORTANK"] = function()
    local msg = "To use WarriorTank addon, create a macro and type /script WarriorTank_main();"
    DEFAULT_CHAT_FRAME:AddMessage(msg)
  end
  SLASH_WARRIORTANK1 = "/tank"
end

-- ====== Public API ======
function WarriorTank_main()
  -- Talent checks (tree 1=Arms, 2=Fury, 3=Protection; row/col based on Turtle/WotLK-like talents)
  local msNameTalent, msIcon, msTier, msColumn, msCurrRank, msMaxRank = GetTalentInfo(1, 18)
  local btNameTalent, btIcon, btTier, btColumn, btCurrRank, btMaxRank = GetTalentInfo(2, 17)

  -- Choose an intended "main damage" ability by talents, then **validate known** and fallback
  local intendedMain = "Shield Slam"             -- Prot default
  if (msCurrRank == 1) then intendedMain = "Mortal Strike"
  elseif (btCurrRank == 1) then intendedMain = "Bloodthirst"
  end

  local mainDamage = intendedMain
  if not WarriorTank_Knows(mainDamage) then
    -- Friendly fallbacks for lower levels
    if     WarriorTank_Knows("Shield Slam")     then mainDamage = "Shield Slam"
    elseif WarriorTank_Knows("Mortal Strike")   then mainDamage = "Mortal Strike"
    elseif WarriorTank_Knows("Bloodthirst")     then mainDamage = "Bloodthirst"
    else   mainDamage = "Heroic Strike" -- always available early
    end
  end

  local abilities = { "Shield Block", "Revenge", "Sunder Armor", "Heroic Strike", mainDamage }

  local sunder = KLHTM_Sunder
  local cast   = CastSpellByName
  local rage   = UnitMana("player") or 0

  -- Textures used for buff/action checks
  local sbTexture       = "Ability_Defend"
  local revengeTexture  = "Ability_Warrior_Revenge"

  -- Main ability rage costs (approx; modded by talents if any)
  local mainCost = 30
  if (mainDamage == "Shield Slam") then mainCost = 20 end

  -- Improved Sunder reduces rage cost by rank
  local impSunderNameTalent, impSunderIcon, impSunderTier, impSunderColumn, impSunderCurrRank, impSunderMaxRank = GetTalentInfo(3, 10)
  local sunderRage = (15 - (impSunderCurrRank or 0))
  if sunderRage < 10 then sunderRage = 10 end -- safety floor

  -- Cooldowns (safe by-name lookups; no invalid slot errors)
  local sbStart,  sbDuration,  sbEnabled   = WarriorTank_GetCooldownByName("Shield Block")
  local revStart, revDuration, revEnabled  = WarriorTank_GetCooldownByName("Revenge")
  local mainStart, mainDuration, mainEnabled = WarriorTank_GetCooldownByName(mainDamage)

  -- Is Revenge usable? Guard against nil/0 slots.
  local revengeSlot   = WarriorTank_findActionSlot(revengeTexture)
  local revengeUsable = 0
  if revengeSlot and revengeSlot > 0 then
    revengeUsable = IsUsableAction(revengeSlot) and 1 or 0
  end

  -- ====== Rotation ======
  -- 1) Shield Block if not active, not on CD, and enough rage
  if (not WarriorTank_isBuffTextureActive(sbTexture) and sbDuration == 0 and rage >= 10) then
    cast("Shield Block")

  -- 2) Main damage spender if ready and enough rage
  elseif (rage >= mainCost and mainDuration == 0) then
    cast(mainDamage)

  -- 3) Revenge if usable, off CD, and enough rage
  elseif (rage >= 5 and revengeUsable == 1 and revDuration == 0) then
    cast("Revenge")

  -- 4) Sunder for threat if we have rage
  elseif (rage >= sunderRage) then
    if type(sunder) == "function" then
      sunder()
    else
      cast("Sunder Armor")
    end
  end

  -- 5) Heroic Strike as rage dump (queue)
  if (rage >= 60) then
    cast("Heroic Strike")
  end
end

-- ====== Helpers ======
function WarriorTank_getSpellId(spell)
  if not spell then return nil end
  local i = 1
  while true do
    local spellName, spellRank = GetSpellName(i, BOOK)
    if not spellName then break end
    if spellName == spell then return i end
    i = i + 1
  end
  return nil
end

function WarriorTank_isBuffTextureActive(texture)
  if not texture then return false end
  local i = 0
  local g = GetPlayerBuff
  local isBuffActive = false
  while not (g(i) == -1) do
    local tex = GetPlayerBuffTexture(g(i))
    if tex and strfind(tex, texture) then
      isBuffActive = true
      break
    end
    i = i + 1
  end
  return isBuffActive
end

function WarriorTank_findActionSlot(spellTexture)
  if not spellTexture then return 0 end
  for i = 1, 120 do
    local tex = GetActionTexture(i)
    if tex and strfind(tex, spellTexture) then
      return i
    end
  end
  return 0
end

-- Warm the cache early for first use (in case /tank is used immediately after login)
WarriorTank_RebuildSpellIndexCache()
