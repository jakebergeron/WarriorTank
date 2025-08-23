-- WarriorTank: safer, TurtleWoW-friendly version with stance/shield checks + debug
WarriorTank = {}

-- ====== Config ======
local DEBUG = true  -- set true to see decisions in chat

-- ====== Core constants & API aliases ======
local BOOK = BOOKTYPE_SPELL or "spell"

-- Use a local alias so typos in global names can't break us
local API_GetShapeshiftForm = _G.GetShapeshiftForm or function() return 0 end

-- Simple spell index cache (name -> spellbook index)
local WarriorTank_SpellIndexCache = {}

local function D(msg)
  if DEBUG then DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WT|r: "..tostring(msg)) end
end

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
  D("Spell cache rebuilt.")
end

-- Keep cache fresh as the spellbook changes
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
  if not idx then return 0, 0, 1 end
  local s, d, e = GetSpellCooldown(idx, BOOK)
  return s or 0, d or 0, e or 1
end

-- ====== Stance & equipment checks ======
local function WarriorTank_GetStance()
  -- 0/1=battle, 2=defensive, 3=berserker on 1.12
  local form = API_GetShapeshiftForm()
  if form == 2 then
    return "defensive"
  elseif form == 3 then
    return "berserker"
  else
    return "battle"
  end
end

local function WarriorTank_HasShield()
  local link = GetInventoryItemLink("player", 17) -- offhand
  if not link then return false end
  local name, _, _, _, _, class, subclass = GetItemInfo(link)
  -- Vanilla returns subclass "Shields" (may be localized)
  return subclass == "Shields"
end

local function WarriorTank_IsSpellUsableByName(spellName)
  -- Lightweight usable proxy: if not on cooldown, assume usable.
  -- (We combine with stance/equipment checks where needed.)
  local _, dur = WarriorTank_GetCooldownByName(spellName)
  return dur == 0
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
  local stance = WarriorTank_GetStance()
  local rage   = UnitMana("player") or 0

  -- Talent checks (tree 1=Arms, 2=Fury, 3=Protection)
  local _,_,_,_, msCurrRank = GetTalentInfo(1, 18)
  local _,_,_,_, btCurrRank = GetTalentInfo(2, 17)

  -- Choose intended main damage by talents, then fallback if unknown
  local intendedMain = "Shield Slam"
  if (msCurrRank == 1) then
    intendedMain = "Mortal Strike"
  elseif (btCurrRank == 1) then
    intendedMain = "Bloodthirst"
  end

  local mainDamage = intendedMain
  if not WarriorTank_Knows(mainDamage) then
    if     WarriorTank_Knows("Shield Slam")   then mainDamage = "Shield Slam"
    elseif WarriorTank_Knows("Mortal Strike") then mainDamage = "Mortal Strike"
    elseif WarriorTank_Knows("Bloodthirst")   then mainDamage = "Bloodthirst"
    else   mainDamage = "Heroic Strike" -- fallback for low levels
    end
  end

  local sunder = KLHTM_Sunder
  local cast   = CastSpellByName

  -- Costs
  local mainCost = (mainDamage == "Shield Slam") and 20 or 30
  local _,_,_,_, impSunderCurrRank = GetTalentInfo(3, 10)
  local sunderRage = math.max(10, 15 - (impSunderCurrRank or 0))

  -- Cooldowns
  local _, sbDur   = WarriorTank_GetCooldownByName("Shield Block")
  local _, revDur  = WarriorTank_GetCooldownByName("Revenge")
  local _, mainDur = WarriorTank_GetCooldownByName(mainDamage)

  -- Revenge usable only if it’s on your bars (older API quirk); optional but safer
  local revengeTexture = "Ability_Warrior_Revenge"
  local revengeSlot = WarriorTank_findActionSlot(revengeTexture)
  local revengeUsable = 0
  if revengeSlot and revengeSlot > 0 then
    revengeUsable = IsUsableAction(revengeSlot) and 1 or 0
  end

  -- Buff/stance checks for Shield Block
  local sbTexture = "Ability_Defend"
  local shieldBlockUsable =
      (stance == "defensive") and
      WarriorTank_HasShield() and
      WarriorTank_IsSpellUsableByName("Shield Block") and
      (sbDur == 0) and
      not WarriorTank_isBuffTextureActive(sbTexture)

  D(string.format("stance=%s rage=%d main=%s sbUsable=%s revUsable=%d mainCD=%d",
      stance, rage, mainDamage, tostring(shieldBlockUsable), revengeUsable, mainDur))

  -- ====== Rotation ======
  -- 1) Shield Block (only if in Defensive + shield equipped)
  if shieldBlockUsable and rage >= 10 then
    D("Cast: Shield Block")
    cast("Shield Block")

  -- 2) Main damage
  elseif (rage >= mainCost and mainDur == 0) then
    D("Cast: "..mainDamage)
    cast(mainDamage)

  -- 3) Revenge
  elseif (rage >= 5 and revengeUsable == 1 and revDur == 0) then
    D("Cast: Revenge")
    cast("Revenge")

  -- 4) Sunder
  elseif (rage >= sunderRage) then
    D("Cast: Sunder Armor")
    if type(sunder) == "function" then sunder() else cast("Sunder Armor") end
  else
    D("No action: insufficient rage/requirements.")
  end

  -- 5) Rage dump
  if (rage >= 60) then
    D("Queue: Heroic Strike")
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
  while not (g(i) == -1) do
    local tex = GetPlayerBuffTexture(g(i))
    if tex and strfind(tex, texture) then
      return true
    end
    i = i + 1
  end
  return false
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

-- Warm the cache for immediate use (in case /tank is used right after login)
WarriorTank_RebuildSpellIndexCache()

-- Optional alias so both /script WarriorTank_main() and /script WarriorTank_Main() work
WarriorTank_Main = WarriorTank_main
