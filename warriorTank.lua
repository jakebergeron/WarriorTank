WarriorTank = {};

local WarriorTankFrame = CreateFrame("Frame")
WarriorTankFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
WarriorTankFrame:RegisterEvent("ADDON_LOADED")

WarriorTankFrame:SetScript("OnEvent", function(self, event, ...)
	Add slash command '/tank' and chat message on addon load
	end
end)

function WarriorTank_main()	
	local msNameTalent, msIcon, msTier, msColumn, msCurrRank, msMaxRank = GetTalentInfo(1,18);
	local btNameTalent, btIcon, btTier, btColumn, btCurrRank, btMaxRank = GetTalentInfo(2,17);
	local mainDamage = "Shield Slam";
	if (msCurrRank == 1) then mainDamage = "Mortal Strike";
	elseif (btCurrRank == 1) then mainDamage = "Bloodthirst"; end;
	local abilities = {"Shield Block", "Revenge", "Sunder Armor", "Heroic Strike", mainDamage};
	local ids = {};
	local sunder = KLHTM_Sunder;
	local cast = CastSpellByName;
	local rage = UnitMana("player");
	local sbTexture = "Ability_Defend";
	local revengeTexture = "Ability_Warrior_Revenge";
	local mainCost = 30;
	local impSunderNameTalent, impSunderIcon, impSunderTier, impSunderColumn, impSunderCurrRank, impSunderMaxRank = GetTalentInfo(3,10);
	if impSunderCurrRank == nil then impSunderCurrRank = 0 end
	local sunderRage = 15 - impSunderCurrRank;
	
	if(mainDamage == "Shield Slam") then mainCost = 20; end;
	for i = 1, 5, 1
		do
			local spellId = WarriorTank_getSpellId(abilities[i]);
			if(spellId ~= nil) then
				ids[i] = spellId;
			end;
	end;
	end;
	
	-- Get spell cooldowns safely
	local function safeGetSpellCooldown(spellId)
		if spellId ~= nil then
			return GetSpellCooldown(spellId, BOOKTYPE_SPELL)
		else
			return 0, 0, 0
		end
	end

	local sbStart, sbDuration, sbEnabled = safeGetSpellCooldown(ids[1])
	local mainStart, mainDuration, mainEnabled = safeGetSpellCooldown(ids[5])
	local revStart, revDuration, revEnabled = safeGetSpellCooldown(ids[2])
	local revengeSlot = WarriorTank_findActionSlot(revengeTexture);
	local revengeUsable = 0;
	if revengeSlot ~= 0 then
		revengeUsable = IsUsableAction(revengeSlot);
	end
	
	--if shield block not active and not on cd then shield block
	if (WarriorTank_isBuffTextureActive(sbTexture) == false and sbDuration == 0 and rage >= 10) then cast(abilities[1]);
	--if enough rage for mainDamage and mainDamage not on cd then mainDamage
	elseif (rage >= mainCost and mainDuration == 0) then cast(abilities[5]);
	--if enough rage for revenge and revenge can be cast and random roll less than 7 then revenge
	elseif (rage >= 5 and revengeUsable == 1 and revDuration == 0) then cast(abilities[2]);
	--if enough rage for sunder then sunder
	elseif (rage >= sunderRage) then sunder(); end;
	
	--if rage >= 60 then heroic strike
	if (rage >= 60) then cast(abilities[4]); end;

end

WarriorTank.WarriorTank_main = WarriorTank_main
_G["WarriorTank_main"] = WarriorTank_main

function WarriorTank_getSpellId(spell)
	local i = 1
	while true do
	   local spellName, spellRank = GetSpellName(i, BOOKTYPE_SPELL)
	   if not spellName then
		  break
	   end
	   if spellName == spell then
	   return i; end;
	   i = i + 1
	end
end;

function WarriorTank_isBuffTextureActive(texture)
	local i=0;
	local g=GetPlayerBuff;
		local buffTexture = GetPlayerBuffTexture(g(i));
		if(buffTexture ~= nil and string.find(buffTexture, texture)) then isBuffActive = true; end;

	while not(g(i) == -1)
	do
		if(string.find(GetPlayerBuffTexture(g(i)), texture)) then isBuffActive = true; end;
		i=i+1
	end;	
	return isBuffActive;
end;
function WarriorTank_findActionSlot(spellTexture)	
	for i = 1, 120, 1
		do
		local actionTexture = GetActionTexture(i)
		if actionTexture ~= nil then 
			if(string.find(actionTexture, spellTexture)) then return i; end;
		end;
	end;
	return 0;
end;
end;
