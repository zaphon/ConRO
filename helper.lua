ConRO.RaidBuffs = {};
ConRO.WarningFlags = {};

-- Global cooldown spell id
-- GlobalCooldown = 61304;

local GetSpellInfo = function(spellID)
	if not spellID then
		return nil;
	end

	local spellInfo = C_Spell.GetSpellInfo(spellID);
	if spellInfo then
		return spellInfo.name, nil, spellInfo.iconID, spellInfo.castTime, spellInfo.minRange, spellInfo.maxRange, spellInfo.spellID, spellInfo.originalIconID;
	end
end

local GetSpellCooldown = function(spellID)
	local spellCooldownInfo = C_Spell.GetSpellCooldown(spellID);
	if spellCooldownInfo then
		return spellCooldownInfo.startTime, spellCooldownInfo.duration, spellCooldownInfo.isEnabled, spellCooldownInfo.modRate;
	end
end

local UnitAura = function(unitToken, index, filter)
	local auraData = C_UnitAuras.GetAuraDataByIndex(unitToken, index, filter);
	if not auraData then
		return nil;
	end

	return AuraUtil.UnpackAuraData(auraData);
end

local UnitDebuff = UnitAura

local GetSpellCharges = function(spellID)
	local spellChargeInfo = C_Spell.GetSpellCharges(spellID);
	if spellChargeInfo then
		return spellChargeInfo.currentCharges, spellChargeInfo.maxCharges, spellChargeInfo.cooldownStartTime, spellChargeInfo.cooldownDuration, spellChargeInfo.chargeModRate;
	end
end

local INF = 2147483647;

local BOOKTYPE_SPELL = "spell";

local GetSpellBookItemName = function(index, bookType)
	local spellBank = (bookType == BOOKTYPE_SPELL) and Enum.SpellBookSpellBank.Player or Enum.SpellBookSpellBank.Pet;
	return C_SpellBook.GetSpellBookItemName(index, spellBank);
end

GetSpellBookItemInfo = function(index, bookType)
	local spellBank = (bookType == BOOKTYPE_SPELL) and Enum.SpellBookSpellBank.Player or Enum.SpellBookSpellBank.Pet;
	return C_SpellBook.GetSpellBookItemType(index, spellBank);
end

function ConRO:SpecName()
	local currentSpec = GetSpecialization();
	local currentSpecName = currentSpec and select(2, GetSpecializationInfo(currentSpec)) or 'None';
	return currentSpecName;
end

function ConRO:CheckTalents()
	--print("Bing")
	self.PlayerTalents = {};
	wipe(self.PlayerTalents)

	local configId = C_ClassTalents.GetActiveConfigID()
	if configId ~= nil then
		local configInfo = C_Traits.GetConfigInfo(configId)
		if configInfo ~= nil then
			for _, treeId in pairs(configInfo.treeIDs) do
				local nodes = C_Traits.GetTreeNodes(treeId)
				for _, nodeId in pairs(nodes) do
					local node = C_Traits.GetNodeInfo(configId, nodeId)
					if node.currentRank and node.currentRank > 0 then
						local entryId = nil

						if node.activeEntry ~= nil then
							entryId = node.activeEntry.entryID
						elseif node.nextEntry ~= nil then
							entryId = node.nextEntry.entryID
						elseif node.entryIDs ~= nil then
							entryId = node.entryIDs[1]
						end

						if entryId ~= nil then
							local entryInfo = C_Traits.GetEntryInfo(configId, entryId)
							local definitionInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)

							if definitionInfo ~= nil then
								local spellId = nil
								if definitionInfo.spellID ~= nil then
									spellId = definitionInfo.spellID
								elseif definitionInfo.overriddenSpellID ~= nil then
									spellId = definitionInfo.overriddenSpellID
								end

								if spellId ~= nil then
									local name = GetSpellInfo(spellId)
										tinsert(self.PlayerTalents, entryId);
									self.PlayerTalents[entryId] = {};

									tinsert(self.PlayerTalents[entryId], {
										id = entryId,
										talentName = name,
										rank = node.currentRank,
									})
								end
							end
						end
					end
				end
			end
		end
	end
end

function ConRO:IsPvP()
	local _is_PvP = UnitIsPVP('player');
	local _is_Arena, _is_Registered = IsActiveBattlefieldArena();
	local _Flagged = false;
		if _is_PvP or _is_Arena then
			_Flagged = true;
		end
	return _Flagged;
end

function ConRO:CheckPvPTalents()
	self.PvPTalents = {};
	local talents = C_SpecializationInfo.GetAllSelectedPvpTalentIDs();
	for k,v in ipairs(talents) do
		local _, name, _, _, _, id = GetPvpTalentInfoByID(v or 0);
		self.PvPTalents[id] = name;
	end
end

function ConRO:TalentChosen(entryCheck, rankCheck)
	if rankCheck ~= nil then
		local talent = self.PlayerTalents[entryCheck];
		if talent then
			for _,i in pairs(talent) do
				for k,v in pairs(i) do
					if k == "rank" then
						if v >= rankCheck then
							return true;
						end
					end
				end
				return false;
			end
		end
	else
		return self.PlayerTalents[entryCheck];
	end
end

function ConRO:PvPTalentChosen(talent)
	return self.PvPTalents[talent];
end

function ConRO:BurstMode(_Spell_ID, timeShift)
	local _Burst = ConRO_BurstButton:IsVisible();
	timeShift = timeShift or ConRO:EndCast();
	local _Burst_Threshold = ConRO.db.profile._Burst_Threshold;
	local _, _, baseCooldown = ConRO:Cooldown(_Spell_ID, timeShift);
	local _Burst_Mode = false;

	if _Burst and baseCooldown >= _Burst_Threshold then
		_Burst_Mode = true;
	end

	return _Burst_Mode;
end

function ConRO:FullMode(_Spell_ID, timeShift)
	local _Full = ConRO_FullButton:IsVisible();
	local _Burst = ConRO_BurstButton:IsVisible();
	timeShift = timeShift or ConRO:EndCast();
	local _Burst_Threshold = ConRO.db.profile._Burst_Threshold;
	local _, _, baseCooldown = ConRO:Cooldown(_Spell_ID, timeShift);
	local _Full_Mode = false;

	if _Burst and baseCooldown < _Burst_Threshold then
		_Full_Mode = true;
	elseif _Full then
		_Full_Mode = true;
	end

	return _Full_Mode;
end

function ConRO:Warnings(_Message, _Condition)
	if self.WarningFlags[_Message] == nil then
		self.WarningFlags[_Message] = 0;
	end
	if _Condition then
		self.WarningFlags[_Message] = self.WarningFlags[_Message] + 1;
		if self.WarningFlags[_Message] == 1 then
			UIErrorsFrame:AddMessage(_Message, 1.0, 1.0, 0.0, 1.0);
		elseif self.WarningFlags[_Message] == 15 then
			self.WarningFlags[_Message] = 0;
		end
	else
		self.WarningFlags[_Message] = 0;
	end
end

ConRO.ItemSlotList = {
	"HeadSlot",
	"NeckSlot",
	"ShoulderSlot",
	"BackSlot",
	"ChestSlot",
	"WristSlot",
	"HandsSlot",
	"WaistSlot",
	"LegsSlot",
	"FeetSlot",
	"Finger0Slot",
	"Finger1Slot",
	"Trinket0Slot",
	"Trinket1Slot",
	"MainHandSlot",
	"SecondaryHandSlot",
}

ConRO.TierSlotList = {
	"HeadSlot",
	"ShoulderSlot",
	"ChestSlot",
	"HandsSlot",
	"LegsSlot",
}

function ConRO:ItemEquipped(_item_string)
	local _match_item_NAME = false;
	local _, _item_LINK = GetItemInfo(_item_string);

	if _item_LINK ~= nil then
		local _item_NAME = GetItemInfo(_item_LINK);

		for i, v in ipairs(ConRO.ItemSlotList) do
			local _slot_LINK = GetInventoryItemLink("player", GetInventorySlotInfo(v));
			if _slot_LINK then
				local _slot_item_NAME = GetItemInfo(_slot_LINK);

				if _slot_item_NAME == _item_NAME then
					_match_item_NAME = true;
					break;
				end
			end
		end
	end
	return _match_item_NAME;
end

function ConRO:CountTier()
    local _, _, classIndex = UnitClass("player");
    local count = 0;

	for _, v in pairs(ConRO.TierSlotList) do
		local match = nil
		local _slot_LINK = GetInventoryItemLink("player", GetInventorySlotInfo(v))
		local _slot_item_NAME;

		if _slot_LINK then
			_slot_item_NAME = GetItemInfo(_slot_LINK)
		else
			break
		end

		if _slot_item_NAME == nil then
			return 0;
		end

		-- Death Knight
		if classIndex == 6 then
			match = string.match(_slot_item_NAME,"of the Risen Nightmare")
		end
		-- Demon Hunter
		if classIndex == 12 then
			match = string.match(_slot_item_NAME,"Screaming Torchfiend's")
		end
		-- Druid
		if classIndex == 11 then
			match = string.match(_slot_item_NAME,"Benevolent Embersage's")
		end
		-- Evoker
		if classIndex == 13 then
			match = string.match(_slot_item_NAME,"Werynkeeper's Timeless")
		end
		-- Hunter
		if classIndex == 3 then
			match = string.match(_slot_item_NAME,"Blazing Dreamstalker's")
		end
		-- Mage
		if classIndex == 8 then
			match = string.match(_slot_item_NAME,"Wayward Chronomancer's")
		end
		-- Monk
		if classIndex == 10 then
			match = string.match(_slot_item_NAME,"Mystic Heron's")
		end
		-- Paladin
		if classIndex == 2 then
			match = string.match(_slot_item_NAME,"Zealous Pyreknight's")
		end
		-- Priest
		if classIndex == 5 then
			match = string.match(_slot_item_NAME,"of Lunar Communion")
		end
		-- Rogue
		if classIndex == 4 then
			match = string.match(_slot_item_NAME,"Lucid Shadewalker's")
		end
		-- Shaman
		if classIndex == 7 then
			match = string.match(_slot_item_NAME,"Greatwolf Outcast's")
		end
		-- Warlock
		if classIndex == 9 then
			match = string.match(_slot_item_NAME,"Devout Ashdevil's")
		end
		-- Warrior
		if classIndex == 1 then
			match = string.match(_slot_item_NAME,"Molten Vanguard's")
		end

		if match then count = count + 1 end
	end
    return count
end

function ConRO:PlayerSpeed()
	local speed  = (GetUnitSpeed("player") / 7) * 100;
	local moving = false;
		if speed > 0 then
			moving = true;
		else
			moving = false;
		end
	return moving;
end

ConRO.EnergyList = {
	[0]	= 'Mana',
	[1] = 'Rage',
	[2]	= 'Focus',
	[3] = 'Energy',
	[4]	= 'Combo',
	[6] = 'RunicPower',
	[7]	= 'SoulShards',
	[8] = 'LunarPower',
	[9] = 'HolyPower',
	[11] = 'Maelstrom',
	[12] = 'Chi',
	[13] = 'Insanity',
	[16] = 'ArcaneCharges',
	[17] = 'Fury',
	[19] = 'Essence',
}

function ConRO:PlayerPower(_EnergyType)
	local resource;

	for k, v in pairs(ConRO.EnergyList) do
		if v == _EnergyType then
			resource = k;
			break
		end
	end

	local _Resource = UnitPower('player', resource);
	local _Resource_Max	= UnitPowerMax('player', resource);
	local _Resource_Percent = math.max(0, _Resource) / math.max(1, _Resource_Max) * 100;

	return _Resource, _Resource_Max, _Resource_Percent;
end

	--[[local FriendItems  = {
    [5] = {
        37727, -- Ruby Acorn
    },
    [8] = {
        34368, -- Attuned Crystal Cores
        33278, -- Burning Torch
    },
    [10] = {
        32321, -- Sparrowhawk Net
    },
    [15] = {
        1251, -- Linen Bandage
        2581, -- Heavy Linen Bandage
        3530, -- Wool Bandage
        3531, -- Heavy Wool Bandage
        6450, -- Silk Bandage
        6451, -- Heavy Silk Bandage
        8544, -- Mageweave Bandage
        8545, -- Heavy Mageweave Bandage
        14529, -- Runecloth Bandage
        14530, -- Heavy Runecloth Bandage
        21990, -- Netherweave Bandage
        21991, -- Heavy Netherweave Bandage
        34721, -- Frostweave Bandage
        34722, -- Heavy Frostweave Bandage
--        38643, -- Thick Frostweave Bandage
--        38640, -- Dense Frostweave Bandage
    },
    [20] = {
        21519, -- Mistletoe
    },
    [25] = {
        31463, -- Zezzak's Shard
    },
    [30] = {
        1180, -- Scroll of Stamina
        1478, -- Scroll of Protection II
        3012, -- Scroll of Agility
        1712, -- Scroll of Spirit II
        2290, -- Scroll of Intellect II
        1711, -- Scroll of Stamina II
        34191, -- Handful of Snowflakes
    },
    [35] = {
        18904, -- Zorbin's Ultra-Shrinker
    },
    [40] = {
        34471, -- Vial of the Sunwell
    },
    [45] = {
        32698, -- Wrangling Rope
    },
    [60] = {
        32825, -- Soul Cannon
        37887, -- Seeds of Nature's Wrath
    },
    [80] = {
        35278, -- Reinforced Net
    },
}

local HarmItems = {
    [5] = {
        37727, -- Ruby Acorn
    },
    [8] = {
        34368, -- Attuned Crystal Cores
        33278, -- Burning Torch
    },
    [10] = {
        32321, -- Sparrowhawk Net
    },
    [15] = {
        33069, -- Sturdy Rope
    },
    [20] = {
        10645, -- Gnomish Death Ray
    },
    [25] = {
        24268, -- Netherweave Net
        41509, -- Frostweave Net
        31463, -- Zezzak's Shard
    },
    [30] = {
        835, -- Large Rope Net
        7734, -- Six Demon Bag
        34191, -- Handful of Snowflakes
    },
    [35] = {
        24269, -- Heavy Netherweave Net
        18904, -- Zorbin's Ultra-Shrinker
    },
    [40] = {
        28767, -- The Decapitator
    },
    [45] = {
        32698, -- Wrangling Rope
    },
    [60] = {
        32825, -- Soul Cannon
        37887, -- Seeds of Nature's Wrath
    },
    [80] = {
        35278, -- Reinforced Net
    },
}]]

function ConRO:Targets(spellID)
	local target_in_range = false;
	local number_in_range = 0;
		if spellID == "Melee" then
			if not UnitIsFriend("player", "target") and UnitExists("target") then
				if IsItemInRange(37727, "target") then
					target_in_range = true;
				end
			end

			for i = 1, 15 do
				if not UnitIsFriend("player", 'nameplate' .. i) then
					if UnitExists('nameplate' .. i) and IsItemInRange(37727, "nameplate"..i) == true and UnitName('nameplate' .. i) ~= "Explosive" and UnitName('nameplate' .. i) ~= "Incorporeal Being" then
						number_in_range = number_in_range + 1
					end
				end
			end
		elseif spellID == "10" then
			if not UnitIsFriend("player", "target") and UnitExists("target") then
				if IsItemInRange(32321, "target") then
					target_in_range = true;
				end
			end

			for i = 1, 15 do
				if not UnitIsFriend("player", 'nameplate' .. i) then
					if UnitExists('nameplate' .. i) and IsItemInRange(32321, "nameplate"..i) == true and UnitName('nameplate' .. i) ~= "Explosive" and UnitName('nameplate' .. i) ~= "Incorporeal Being" then
						number_in_range = number_in_range + 1
					end
				end
			end
		elseif spellID == "15" then
			if not UnitIsFriend("player", "target") and UnitExists("target") then
				if IsItemInRange(33069, "target") then
					target_in_range = true;
				end
			end

			for i = 1, 15 do
				if not UnitIsFriend("player", 'nameplate' .. i) then
					if UnitExists('nameplate' .. i) and IsItemInRange(33069, "nameplate"..i) == true and UnitName('nameplate' .. i) ~= "Explosive" and UnitName('nameplate' .. i) ~= "Incorporeal Being" then
						number_in_range = number_in_range + 1
					end
				end
			end
		elseif spellID == "25" then
			if not UnitIsFriend("player", "target") and UnitExists("target") then
				if IsItemInRange(24268, "target") then
					target_in_range = true;
				end
			end

			for i = 1, 15 do
				if not UnitIsFriend("player", 'nameplate' .. i) then
					if UnitExists('nameplate' .. i) and IsItemInRange(24268, "nameplate"..i) == true and UnitName('nameplate' .. i) ~= "Explosive" and UnitName('nameplate' .. i) ~= "Incorporeal Being" then
						number_in_range = number_in_range + 1
					end
				end
			end
		elseif spellID == "40" then
			if not UnitIsFriend("player", "target") and UnitExists("target") then
				if IsItemInRange(28767, "target") then
					target_in_range = true;
				end
			end

			for i = 1, 15 do
				if not UnitIsFriend("player", 'nameplate' .. i) then
					if UnitExists('nameplate' .. i) and IsItemInRange(28767, "nameplate"..i) == true and UnitName('nameplate' .. i) ~= "Explosive" and UnitName('nameplate' .. i) ~= "Incorporeal Being" then
						number_in_range = number_in_range + 1
					end
				end
			end
		else
			if ConRO:IsSpellInRange(spellID, "target") then
				target_in_range = true;
			end

			for i = 1, 15 do
				if UnitExists('nameplate' .. i) and ConRO:IsSpellInRange(spellID, 'nameplate' .. i) and UnitName('nameplate' .. i) ~= "Explosive" and UnitName('nameplate' .. i) ~= "Incorporeal Being" then
					number_in_range = number_in_range + 1
				end
			end
		end
	--print(number_in_range)
	return number_in_range, target_in_range;
end

function ConRO:UnitAura(spellID, timeShift, unit, filter, isWeapon)
	timeShift = timeShift or 0;
	if isWeapon == "Weapon" then
		local hasMainHandEnchant, mainHandExpiration, _, mainBuffId, hasOffHandEnchant, offHandExpiration, _, offBuffId = GetWeaponEnchantInfo()
		if hasMainHandEnchant and mainBuffId == spellID then
			if mainHandExpiration ~= nil and (mainHandExpiration/1000) > timeShift then
				local dur = (mainHandExpiration/1000) - (timeShift or 0);
				return true, count, dur;
			end
		elseif hasOffHandEnchant and offBuffId == spellID then
			if offHandExpiration ~= nil and (offHandExpiration/1000) > timeShift then
				local dur = (offHandExpiration/1000) - (timeShift or 0);
				return true, count, dur;
			end
		end
	else
		for i=1,40 do
			local _, _, count, _, _, expirationTime, _, _, _, spell = UnitAura(unit, i, filter);
			if spell == spellID then
				if expirationTime ~= nil and (expirationTime - GetTime()) > timeShift then
					local dur = expirationTime - GetTime() - (timeShift or 0);
					return true, count, dur;
				end
			end
		end
	end
	return false, 0, 0;
end

function ConRO:Form(spellID)
	for i=1,40 do
		local _, _, count, _, _, _, _, _, _, spell = UnitAura("player", i);
			if spell == spellID then
				return true, count;
			end
	end
	return false, 0;
end

function ConRO:PersistentDebuff(spellID)
	for i=1,40 do
		local _, _, count, _, _, _, _, _, _, spell = UnitAura("target", i, 'PLAYER|HARMFUL');
			if spell == spellID then
				return true, count;
			end

	end
	return false, 0;
end

function ConRO:Aura(spellID, timeShift, filter)
	return self:UnitAura(spellID, timeShift, 'player', filter);
end

function ConRO:TargetAura(spellID, timeShift)
	return self:UnitAura(spellID, timeShift, 'target', 'PLAYER|HARMFUL');
end

function ConRO:AnyTargetAura(spellID)
	local haveBuff = false;
	local count = 0;
	for i = 1, 15 do
		if UnitExists('nameplate' .. i) then
			for x=1, 40 do
				local spell = select(10, UnitAura('nameplate' .. i, x, 'PLAYER|HARMFUL'));
				if spell == spellID then
					haveBuff = true;
					count = count + 1;
					break;
				end
			end
		end
	end

	return haveBuff, count;
end

function ConRO:Purgable()
	local purgable = false;
	for i=1,40 do
	local _, _, _, _, _, _, _, isStealable = UnitAura('target', i, 'HELPFUL');
		if isStealable == true then
			purgable = true;
		end
	end
	return purgable;
end

function ConRO:Heroism()
	local _Bloodlust = 2825;
	local _TimeWarp	= 80353;
	local _Heroism = 32182;
	local _PrimalRage = 264667;
	local _AncientHysteria = 90355;
	local _Netherwinds = 160452;
	local _DrumsofFury = 120257;
	local _DrumsofFuryBuff = 178207;
	local _DrumsoftheMountain = 142406;
	local _DrumsoftheMountainBuff = 230935;
	local _FuryoftheAspects = 390386;

	local _Exhaustion = 57723;
	local _Sated = 57724;
	local _TemporalDisplacement = 80354;
	local _Insanity = 95809;
	local _Fatigued = 264689;
	local _Exhaustion2 = 390435;

	local buffed = false;
	local sated = false;

		local hasteBuff = {
			bl = ConRO:Aura(_Bloodlust, timeShift);
			tw = ConRO:Aura(_TimeWarp, timeShift);
			hero = ConRO:Aura(_Heroism, timeShift);
			pr = ConRO:Aura(_PrimalRage, timeShift);
			ah = ConRO:Aura(_AncientHysteria, timeShift);
			nw = ConRO:Aura(_Netherwinds, timeShift);
			dof = ConRO:Aura(_DrumsofFuryBuff, timeShift);
			dotm = ConRO:Aura(_DrumsoftheMountainBuff, timeShift);
			fota = ConRO:Aura(_FuryoftheAspects, timeShift);
		}
		local satedDebuff = {
			ex = UnitDebuff('player', _Exhaustion);
			sated = UnitDebuff('player', _Sated);
			td = UnitDebuff('player', _TemporalDisplacement);
			ins = UnitDebuff('player', _Insanity);
			fat = UnitDebuff('player', _Fatigued);
			ex2 = UnitDebuff('player', _Exhaustion2);
		}
		local hasteCount = 0;
			for k, v in pairs(hasteBuff) do
				if v then
					hasteCount = hasteCount + 1;
				end
			end

		if hasteCount > 0 then
			buffed = true;
		end

		local satedCount = 0;
			for k, v in pairs(satedDebuff) do
				if v then
					satedCount = satedCount + 1;
				end
			end

		if satedCount > 0 then
			sated = true;
		end

	return buffed, sated;
end

function ConRO:InRaid()
	local numGroupMembers = GetNumGroupMembers();
	if numGroupMembers >= 6 then
		return true;
	else
		return false;
	end
end

function ConRO:InParty()
	local numGroupMembers = GetNumGroupMembers();
	if numGroupMembers >= 2 and numGroupMembers <= 5 then
		return true;
	else
		return false;
	end
end

function ConRO:IsSolo()
	local numGroupMembers = GetNumGroupMembers();
	if numGroupMembers <= 1 then
		return true;
	else
		return false;
	end
end

function ConRO:RaidBuff(spellID)
	local selfhasBuff = false;
	local haveBuff = false;
	local buffedRaid = false;

	local numGroupMembers = GetNumGroupMembers();
		if numGroupMembers >= 6 then
			selfhasBuff = true;
			for i = 1, numGroupMembers do -- For each raid member
				local unit = "raid" .. i;
				if UnitExists(unit) then
					if not UnitIsDeadOrGhost(unit) and UnitInRange(unit) then
						for x=1, 40 do
							local spell = select(10, UnitAura(unit, x, 'HELPFUL'));
							if spell == spellID then
								haveBuff = true;
								break;
							end
						end
						if not haveBuff then
							break;
						end
					else
						haveBuff = true;
					end
				end
			end
		elseif numGroupMembers >= 2 and numGroupMembers <= 5 then
			for i = 1, 4 do -- For each party member
				local unit = "party" .. i;
				if UnitExists(unit) then
					if not UnitIsDeadOrGhost(unit) and UnitInRange(unit) then
						for x=1, 40 do
							local spell = select(10, UnitAura(unit, x, 'HELPFUL'));
							if spell == spellID then
								haveBuff = true;
								break;
							end
						end
						if not haveBuff then
							break;
						end
					else
						haveBuff = true;
					end
				end
			end
			for x=1, 40 do
				local spell = select(10, UnitAura('player', x, 'HELPFUL'));
				if spell == spellID then
					selfhasBuff = true;
					break;
				end
			end
		elseif numGroupMembers <= 1 then
			for x=1, 40 do
				local spell = select(10, UnitAura('player', x, 'HELPFUL'));
				if spell == spellID then
					selfhasBuff = true;
					haveBuff = true;
					break;
				end
			end
		end
		if selfhasBuff and haveBuff then
			buffedRaid = true;
		end
--	self:Print(self.Colors.Info .. numGroupMembers);
	return buffedRaid;
end

function ConRO:OneBuff(spellID)
	local selfhasBuff = false;
	local haveBuff = false;
	local someoneHas = false;

	local numGroupMembers = GetNumGroupMembers();
		if numGroupMembers >= 6 then
			for i = 1, numGroupMembers do -- For each raid member
				local unit = "raid" .. i;
				if UnitExists(unit) then
					for x=1, 40 do
						local spell = select(10, UnitAura(unit, x, 'PLAYER|HELPFUL'));
						if spell == spellID then
							haveBuff = true;
							break;
						end
					end
					if haveBuff then
						break;
					end
				end
			end
		elseif numGroupMembers >= 2 and numGroupMembers <= 5 then
			for x=1, 40 do
				local spell = select(10, UnitAura('player', x, 'PLAYER|HELPFUL'));
				if spell == spellID then
					selfhasBuff = true;
					break;
				end
			end
			if not selfhasBuff then
				for i = 1, 4 do -- For each party member
					local unit = "party" .. i;
					if UnitExists(unit) then
						for x=1, 40 do
							local spell = select(10, UnitAura(unit, x, 'PLAYER|HELPFUL'));
							if spell == spellID then
								haveBuff = true;
								break;
							end
						end
						if haveBuff then
							break;
						end
					end
				end
			end
		elseif numGroupMembers <= 1 then
			for x=1, 40 do
				local spell = select(10, UnitAura('player', x, 'PLAYER|HELPFUL'));
				if spell == spellID then
					selfhasBuff = true;
					break;
				end
			end
		end
		if selfhasBuff or haveBuff then
			someoneHas = true;
		end
--	self:Print(self.Colors.Info .. numGroupMembers);
	return someoneHas;
end

function ConRO:GroupBuffCount(spellID)
	local buffCount = 0;

	local numGroupMembers = GetNumGroupMembers();
		if numGroupMembers >= 6 then
			for i = 1, numGroupMembers do -- For each raid member
				local unit = "raid" .. i;
				if UnitExists(unit) then
					for x=1, 40 do
						local spell = select(10, UnitAura(unit, x, 'PLAYER|HELPFUL'));
						if spell == spellID then
							buffCount = buffCount + 1;
						end
					end
				end
			end
		elseif numGroupMembers >= 2 and numGroupMembers <= 5 then
			for i = 1, 4 do -- For each party member
				local unit = "party" .. i;
				if UnitExists(unit) then
					for x=1, 40 do
						local spell = select(10, UnitAura(unit, x, 'PLAYER|HELPFUL'));
						if spell == spellID then
							buffCount = buffCount + 1;
						end
					end
				end
			end
			for x=1, 40 do
				local spell = select(10, UnitAura('player', x, 'PLAYER|HELPFUL'));
				if spell == spellID then
					buffCount = buffCount + 1;
				end
			end
		elseif numGroupMembers <= 1 then
			for x=1, 40 do
				local spell = select(10, UnitAura('player', x, 'PLAYER|HELPFUL'));
				if spell == spellID then
					buffCount = buffCount + 1;
				end
			end
		end

--	self:Print(self.Colors.Info .. numGroupMembers);
	return buffCount;
end

function ConRO:EndCast(target)
	target = target or 'player';
	local t = GetTime();
	local c = t * 1000;
	local gcd = 0;
	local _, _, _, _, endTime, _, _, _, spellId = UnitCastingInfo(target or 'player');

	-- we can only check player global cooldown
	if target == 'player' then
		local gstart, gduration = GetSpellCooldown(61304);
		gcd = gduration - (t - gstart);

		if gcd < 0 then
			gcd = 0;
		end;
	end

	if not endTime then
		return gcd, nil, gcd;
	end

	local timeShift = (endTime - c) / 1000;
	if gcd > timeShift then
		timeShift = gcd;
	end

	return timeShift, spellId, gcd;
end

function ConRO:EndChannel(target)
	target = target or 'player';
	local t = GetTime();
	local c = t * 1000;
	local gcd = 0;
	local _, _, _, _, endTime, _, _, spellId = UnitChannelInfo(target or 'player');

	-- we can only check player global cooldown
	if target == 'player' then
		local gstart, gduration = GetSpellCooldown(61304);
		gcd = gduration - (t - gstart);

		if gcd < 0 then
			gcd = 0;
		end;
	end

	if not endTime then
		return gcd, nil, gcd;
	end

	local timeShift = (endTime - c) / 1000;
	if gcd > timeShift then
		timeShift = gcd;
	end

	return timeShift, spellId, gcd;
end

function ConRO:SameSpell(spell1, spell2)
	local spellName1 = GetSpellInfo(spell1);
	local spellName2 = GetSpellInfo(spell2);
	return spellName1 == spellName2;
end

function ConRO:TarYou()
	local targettarget = UnitName('targettarget');
	local targetplayer = UnitName('player');
	if targettarget == targetplayer then
		return 1;
	end
end

function ConRO:TarHostile()
	local isEnemy = UnitReaction("player","target");
	local isDead = UnitIsDead("target");
		if isEnemy ~= nil then
			if isEnemy <= 4 and not isDead then
				return true;
			else
				return false;
			end
		end
	return false;
end

function ConRO:PercentHealth(unit)
	local unit = unit or 'target';
	local health = UnitHealth(unit);
	local healthMax = UnitHealthMax(unit);
	if health <= 0 or healthMax <= 0 then
		return 101;
	end
	return (health/healthMax)*100;
end

ConRO.Spellbook = {};
function ConRO:FindSpellInSpellbook(spellID)
	local spellName = GetSpellInfo(spellID);
	if ConRO.Spellbook[spellName] then
		return ConRO.Spellbook[spellName];
	end

	local _, _, offset, numSpells = GetSpellTabInfo(2);
	local booktype = 'spell';

	for index = offset + 1, numSpells + offset do
		local spellID = select(2, GetSpellBookItemInfo(index, booktype));
		if spellID and spellName == GetSpellBookItemName(index, booktype) then
			ConRO.Spellbook[spellName] = index;
			return index;
		end
	end

	local _, _, offset, numSpells = GetSpellTabInfo(3);
	local booktype = 'spell';

	for index = offset + 1, numSpells + offset do
		local spellID = select(2, GetSpellBookItemInfo(index, booktype));
		if spellID and spellName == GetSpellBookItemName(index, booktype) then
			ConRO.Spellbook[spellName] = index;
			return index;
		end
	end

	return nil;
end

function ConRO:FindCurrentSpell(spellID)
	local spellName = GetSpellInfo(spellID);
	local _, _, offset, numSpells = GetSpellTabInfo(2);
	local booktype = 'spell';
	local hasSpell = false;

	for index = offset + 1, numSpells + offset do
		local spellID = select(2, GetSpellBookItemInfo(index, booktype));
		if spellID and spellName == GetSpellBookItemName(index, booktype) then
			hasSpell = true;
		end
	end

	local _, _, offset, numSpells = GetSpellTabInfo(3);
	local booktype = 'spell';

	for index = offset + 1, numSpells + offset do
		local spellID = select(2, GetSpellBookItemInfo(index, booktype));
		if spellID and spellName == GetSpellBookItemName(index, booktype) then
			hasSpell = true;
		end
	end

	return hasSpell;
end

function ConRO:IsSpellInRange(spellCheck, unit)
	local unit = unit or 'target';
	local range = false;
	local spellid = spellCheck.spellID;
	local talentID = spellCheck.talentID;
	local spell = GetSpellInfo(spellid);
	local have = ConRO:TalentChosen(talentID);
	local known = IsPlayerSpell(spellid);

	if have then
		known = true;
	end

	if known and ConRO:TarHostile() then
		local inRange = C_Spell.IsSpellInRange(spell, unit);
		if inRange == nil then
			local myIndex = nil;
			local name, texture, offset, numSpells, isGuild = GetSpellTabInfo(2);
			local booktype = "spell";
			for index = offset + 1, numSpells + offset do
				local spellID = select(2, GetSpellBookItemInfo(index, booktype));
				if spellID and spell == GetSpellBookItemName(index, booktype) then
					myIndex = index;
					break;
				end
			end

			local numPetSpells = C_SpellBook.HasPetSpells();
			if myIndex == 0 and numPetSpells then
				booktype = "pet";
				for index = 1, numPetSpells do
					local spellID = select(2, GetSpellBookItemInfo(index, booktype));
					if spellID and spell == GetSpellBookItemName(index, booktype) then
						myIndex = index;
						break;
					end
				end
			end

			if myIndex then
				inRange = C_Spell.IsSpellInRange(myIndex, booktype, unit);
			end

			if inRange == 1 then
				range = true;
			end

			return range;
		end

		if inRange == 1 then
			range = true;
		end
	end
  return range;
end

function ConRO:AbilityReady(spellCheck, timeShift, spelltype)
	local spellid = spellCheck.spellID;
	local entryID = spellCheck.talentID;
	local _CD, _MaxCD = ConRO:Cooldown(spellid, timeShift);
	local have = ConRO:TalentChosen(entryID);

	local known = IsPlayerSpell(spellid);
	local usable, notEnough = C_Spell.IsSpellUsable(spellid);
	local castTimeMilli = select(4, GetSpellInfo(spellid));
	local castTime;
	local rdy = false;
		if spelltype == 'pet' then
			have = IsSpellKnown(spellid, true);
		elseif spelltype == 'pvp' then
			have = ConRO:PvPTalentChosen(entryID);
		end
		if have then
			known = true;
		end
		if known and usable and _CD <= 0 and not notEnough then
			rdy = true;
		else
			rdy = false;
		end
		if castTimeMilli ~= nil then
			castTime = castTimeMilli/1000;
		end
	return spellid, rdy, _CD, _MaxCD, castTime;
end

function ConRO:ItemReady(_Item_ID, timeShift)
	local _CD, _MaxCD = ConRO:ItemCooldown(_Item_ID, timeShift);
	local _Item_COUNT = GetItemCount(_Item_ID, false, true);
	local _RDY = false;
		if _CD <= 0 and _Item_COUNT >= 1 then
			_RDY = true;
		else
			_RDY = false;
		end
	return _Item_ID, _RDY, _CD, _MaxCD, _Item_COUNT;
end

function ConRO:SpellCharges(spellid)
	local currentCharges, maxCharges, cooldownStart, maxCooldown = GetSpellCharges(spellid);
	local currentCooldown = 0;
		if currentCharges ~= nil and currentCharges < maxCharges then
			currentCooldown = (maxCooldown - (GetTime() - cooldownStart));
		end
	return currentCharges, maxCharges, currentCooldown, maxCooldown;
end

function ConRO:Raidmob()
	local tlvl = UnitLevel("target");
	local plvl = UnitLevel("player");
	local strong = false;
		if tlvl == -1 or tlvl > plvl then
			strong = true;
		end
	return strong;
end

function ConRO:ExtractTooltipDamage(_Spell_ID)
    _Spell_Description = GetSpellDescription(_Spell_ID);
    _Damage = _Spell_Description:match("%d+([%d%,]+)"); --Need to get correct digits here.
	if _Damage == nil then
		_Damage = _Spell_Description:match("(%d+)");
	end
	local _My_HP = tonumber("1560");
	local _Will_Kill = "false";
	local _Damage_Number = _Damage;

--	if _Damage_Number >= _My_HP then
--		_Will_Kill = "true";
--	end

	print(_Damage_Number .. " - " .. _My_HP .. " -- " .. _Will_Kill);
end

function ConRO:ExtractTooltip(spell, pattern)
	local _pattern = gsub(pattern, "%%s", "([%%d%.,]+)");

	if not TDSpellTooltip then
		CreateFrame('GameTooltip', 'TDSpellTooltip', UIParent, 'GameTooltipTemplate');
		TDSpellTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	end
	TDSpellTooltip:SetSpellByID(spell);

	for i = 2, 4 do
		local line = _G['TDSpellTooltipTextLeft' .. i];
		local text = line:GetText();

		if text then
			local cost = strmatch(text, _pattern);
			if cost then
				cost = cost and tonumber((gsub(cost, "%D", "")));
				return cost;
			end
		end
	end

	return 0;
end

function ConRO:GlobalCooldown()
	local _, duration, enabled = GetSpellCooldown(61304);
		return duration;
end

function ConRO:Cooldown(spellid, timeShift)
	local start, maxCooldown, enabled = GetSpellCooldown(spellid);
	local baseCooldownMS, gcdMS = GetSpellBaseCooldown(spellid);
	local baseCooldown = 0;

	if baseCooldownMS ~= nil then
		baseCooldown = (baseCooldownMS/1000) + (timeShift or 0);
	end

	if enabled and maxCooldown == 0 and start == 0 then
		return 0, maxCooldown, baseCooldown;
	elseif enabled then
		return (maxCooldown - (GetTime() - start) - (timeShift or 0)), maxCooldown, baseCooldown;
	else
		return 100000, maxCooldown, baseCooldown;
	end;
end

function ConRO:ItemCooldown(itemid, timeShift)
	local start, maxCooldown, enabled = GetItemCooldown(itemid);
	local baseCooldownMS, gcdMS = GetSpellBaseCooldown(itemid);
	local baseCooldown = 0;

	if baseCooldownMS ~= nil then
		baseCooldown = baseCooldownMS/1000;
	end

	if enabled and maxCooldown == 0 and start == 0 then
		return 0, maxCooldown, baseCooldown;
	elseif enabled then
		return (maxCooldown - (GetTime() - start) - (timeShift or 0)), maxCooldown, baseCooldown;
	else
		return 100000, maxCooldown, baseCooldown;
	end;
end

function ConRO:Interrupt()
	if UnitCanAttack ('player', 'target') then
		local tarchan, _, _, _, _, _, cnotInterruptible = UnitChannelInfo("target");
		local tarcast, _, _, _, _, _, _, notInterruptible = UnitCastingInfo("target");

		if tarcast and not notInterruptible then
			return true;
		elseif tarchan and not cnotInterruptible then
			return true;
		else
			return false;
		end
	end
end

function ConRO:BossCast()
	if UnitCanAttack ('player', 'target') then
		local tarchan, _, _, _, _, _, cnotInterruptible = UnitChannelInfo("target");
		local tarcast, _, _, _, _, _, _, notInterruptible = UnitCastingInfo("target");

		if tarcast and notInterruptible then
			return true;
		elseif tarchan and cnotInterruptible then
			return true;
		else
			return false;
		end
	end
end

function ConRO:CallPet()
	local petout = IsPetActive();
	local incombat = UnitAffectingCombat('player');
	local mounted = IsMounted();
	local inVehicle = UnitHasVehicleUI("player");
	local summoned = true;
		if not petout and not mounted and not inVehicle and incombat then
			summoned = false;
		end
	return summoned;
end

function ConRO:PetAssist()
	local incombat = UnitAffectingCombat('player');
	local mounted = IsMounted();
	local inVehicle = UnitHasVehicleUI("player");
	local affectingCombat = IsPetAttackActive();
	local attackstate = true;
	local assist = false;
	local petspell = select(9, UnitCastingInfo("pet"))
		for i = 1, 24 do
			local name, _, _, isActive = GetPetActionInfo(i)
			if name == 'PET_MODE_ASSIST' and isActive then
				assist = true;
			end
		end
		if not (affectingCombat or assist) and incombat and not mounted and not inVehicle then
			attackstate = false;
		end
	return attackstate, petspell;
end

function ConRO:Totem(spellID)
	local spellName = GetSpellInfo(spellID)
	for i=1,4 do
		local _, totemName, startTime, duration = GetTotemInfo(i);
		if spellName == totemName then
			local est_dur = startTime + duration - GetTime();
			return true, est_dur;
		end
	end
	return false, 0;
end

function ConRO:Dragonriding()
	local Is_Dragonriding = false;
	local Dragons = {
		CliffsideWylderdrake = 368901,
		HighlandDrake = 360954,
		RenewedProtoDrake = 368896,
		Soar = 369536,
		WindborneVelocidrake = 368899,
		WindingSlitherdrake = 368893,
	}

	for k, v in pairs(Dragons) do
		local Dragonriding_BUFF = ConRO:Form(v);
		if Dragonriding_BUFF then
			Is_Dragonriding = true;
			break
		end
	end
	return Is_Dragonriding;
end

function ConRO:FormatTime(left)
	local seconds = left >= 0        and math.floor((left % 60)    / 1   ) or 0;
	local minutes = left >= 60       and math.floor((left % 3600)  / 60  ) or 0;
	local hours   = left >= 3600     and math.floor((left % 86400) / 3600) or 0;
	local days    = left >= 86400    and math.floor((left % 31536000) / 86400) or 0;
	local years   = left >= 31536000 and math.floor( left / 31536000) or 0;

	if years > 0 then
		return string.format("%d [Y] %d [D] %d:%d:%d [H]", years, days, hours, minutes, seconds);
	elseif days > 0 then
		return string.format("%d [D] %d:%d:%d [H]", days, hours, minutes, seconds);
	elseif hours > 0 then
		return string.format("%d:%d:%d [H]", hours, minutes, seconds);
	elseif minutes > 0 then
		return string.format("%d:%d [M]", minutes, seconds);
	else
		return string.format("%d [S]", seconds);
	end
end

local GetTime = GetTime;
local UnitGUID = UnitGUID;
local UnitExists = UnitExists;
local TableInsert = tinsert;
local TableRemove = tremove;
local MathMin = math.min;
local wipe = wipe;

function ConRO:InitTTD(maxSamples, interval)
	interval = interval or 0.25;
	maxSamples = maxSamples or 50;

	if self.ttd and self.ttd.timer then
		self:CancelTimer(self.ttd.timer);
		self.ttd.timer = nil;
	end

	self.ttd = {
		interval   = interval,
		maxSamples = maxSamples,
		HPTable    = {},
	};

	self.ttd.timer = self:ScheduleRepeatingTimer('TimeToDie', interval);
end

function ConRO:DisableTTD()
	if self.ttd.timer then
		self:CancelTimer(self.ttd.timer);
	end
end

local HPTable = {};
local trackedGuid;
function ConRO:TimeToDie(trackedUnit)
	trackedUnit = trackedUnit or 'target';

	-- Query current time (throttle updating over time)
	local now = GetTime();

	-- Current data
	local ttd = self.ttd;
	local guid = UnitGUID(trackedUnit);

	if trackedGuid ~= guid then
		wipe(HPTable);
		trackedGuid = guid;
	end

	if guid and UnitExists(trackedUnit) then
		local hpPct = self:PercentHealth('target') * 100;
		TableInsert(HPTable, 1, { time = now, hp = hpPct});

		if #HPTable > ttd.maxSamples then
			TableRemove(HPTable);
		end
	else
		wipe(HPTable);
	end
end

function ConRO:GetTimeToDie()
	local seconds = 5*60;

	local n = #HPTable
	if n > 5 then
		local a, b = 0, 0;
		local Ex2, Ex, Exy, Ey = 0, 0, 0, 0;

		local hpPoint, x, y;
		for i = 1, n do
			hpPoint = HPTable[i]
			x, y = hpPoint.time, hpPoint.hp

			Ex2 = Ex2 + x * x
			Ex = Ex + x
			Exy = Exy + x * y
			Ey = Ey + y
		end

		-- Invariant to find matrix inverse
		local invariant = 1 / (Ex2 * n - Ex * Ex);

		-- Solve for a and b
		a = (-Ex * Exy * invariant) + (Ex2 * Ey * invariant);
		b = (n * Exy * invariant) - (Ex * Ey * invariant);

		if b ~= 0 then
			-- Use best fit line to calculate estimated time to reach target health
			seconds = (0 - a) / b;
			seconds = MathMin(5*60, seconds - (GetTime() - 0));

			if seconds < 0 then
				seconds = 5*60;
			end
		end
	end
	return seconds;
end
