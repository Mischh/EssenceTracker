require "Window"
require "GameLib"

local EssenceEventTracker = {}

local kstrAddon = "EssenceTracker"
local lstrAddon = "Essence Tracker"

local ktRotationContentTypes = {
	Dungeon = 1,
	Dailies = 2,
	Expedition = 3,
	WorldBoss = 4,
	PvP = 5,
	Queues = 6,
	[1] = "Dungeon",
	[2] = "Dailies",
	[3] = "Expedition",
	[4] = "WorldBoss",
	[5] = "PvP",
	[6] = "Queues",
}
local ktShortContentTypes = {
	[1] = "Dng",
	[2] = "Day",
	[3] = "Exp",
	[4] = "WB",
	[5] = "PvP",
	[6] = "Que",
}
local ktMatchTypeNames = {
	[MatchMakingLib.MatchType.Shiphand] 		= Apollo.GetString("MatchMaker_Shiphands"),
	[MatchMakingLib.MatchType.Adventure] 		= Apollo.GetString("MatchMaker_Adventures"),
	[MatchMakingLib.MatchType.Dungeon] 			= Apollo.GetString("CRB_Dungeons"), -- <- ACTUALLY USED!
	[MatchMakingLib.MatchType.Battleground]		= Apollo.GetString("MatchMaker_Battlegrounds"),
	[MatchMakingLib.MatchType.RatedBattleground]= Apollo.GetString("MatchMaker_Battlegrounds"),
	[MatchMakingLib.MatchType.Warplot] 			= Apollo.GetString("MatchMaker_Warplots"),
	[MatchMakingLib.MatchType.OpenArena] 		= Apollo.GetString("MatchMaker_Arenas"),
	[MatchMakingLib.MatchType.Arena] 			= Apollo.GetString("MatchMaker_Arenas"),
	[MatchMakingLib.MatchType.WorldStory]		= Apollo.GetString("QuestLog_WorldStory"),
	[MatchMakingLib.MatchType.PrimeLevelDungeon] = Apollo.GetString("MatchMaker_PrimeLevelDungeon"),
	[MatchMakingLib.MatchType.PrimeLevelExpedition] = Apollo.GetString("MatchMaker_PrimeLevelExpedition"),
	[MatchMakingLib.MatchType.PrimeLevelAdventure] = Apollo.GetString("MatchMaker_PrimeLevelAdventure"),
	[MatchMakingLib.MatchType.ScaledPrimeLevelDungeon] = Apollo.GetString("MatchMaker_PrimeLevelDungeon"),
	[MatchMakingLib.MatchType.ScaledPrimeLevelExpedition] = Apollo.GetString("MatchMaker_PrimeLevelExpedition"),
	[MatchMakingLib.MatchType.ScaledPrimeLevelAdventure] = Apollo.GetString("MatchMaker_PrimeLevelAdventure"),
}

--Interesting:
-- GameLib.GetWorldPrimeLevel

local kstrRed 		= "ffff4c4c"
local kstrGreen 	= "ff2fdc02"
local kstrYellow 	= "fffffc00"
local kstrLightGrey = "ffb4b4b4"
local kstrHighlight = "ffffe153"

function EssenceEventTracker:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

	-- Data
	o.nTrackerCounting = -1 -- Start at -1 so that loading up with 0 quests will still trigger a resize
	o.bSetup = false
	o.tRotations = {}
	o.tContentIds = {}

	-- Saved data
	o.bShow = true
	o.tMinimized =
	{
		bRoot = false,
		tQuests = {},
	}
	o.tEventsDone =
	{
		--[nContentId] = fTimeEndTime
	}

    return o
end

function EssenceEventTracker:Init()
    Apollo.RegisterAddon(self)
end

function EssenceEventTracker:OnLoad()
	self.bIsLoaded = false
	self.xmlDoc = XmlDoc.CreateFromFile("EssenceEventTracker.xml")
	self.xmlDoc:RegisterCallback("OnDocumentReady", self)
	Apollo.LoadSprites("EssenceTrackerSprites.xml")

	self.timerUpdateDelay = ApolloTimer.Create(0.1, false, "UpdateAll", self)
	self.timerUpdateDelay:Stop()

	self.timerRealTimeUpdate = ApolloTimer.Create(1.0, true, "RedrawTimers", self)
	self.timerRealTimeUpdate:Stop()
	self:HookMatchMaker()
end

function EssenceEventTracker:HookMatchMaker()
	self.addonMatchMaker = Apollo.GetAddon("MatchMaker")
	if not self.addonMatchMaker then return end
	self:HookBuildFeaturedList()
	self:HookBuildRewardsList()
end

function EssenceEventTracker:HookBuildFeaturedList()
	local originalBuildFeaturedList = self.addonMatchMaker.BuildFeaturedList
	self.addonMatchMaker.BuildFeaturedList = function(...)
		originalBuildFeaturedList(...)
		if self.bIsLoaded then
			self:PlaceOverlays()
		end
	end
end

function EssenceEventTracker:HookBuildRewardsList()
	local originalBuildRewardsList = self.addonMatchMaker.BuildRewardsList
	-- Add missing nContentId to bonus tab data
	self.addonMatchMaker.BuildRewardsList = function (ref, tRewardRotation, ...)
		local arRewardList = originalBuildRewardsList(ref, tRewardRotation, ...)
		for i=1, #arRewardList do
			arRewardList[i].nContentId = tRewardRotation.nContentId
		end
		return arRewardList
	end
end

function EssenceEventTracker:PlaceOverlays()
	local wndFeaturedEntries = self:GetFeaturedEntries()
	for i = 1, #wndFeaturedEntries do
		local wndFeaturedEntry = wndFeaturedEntries[i]
		local rTbl = self:GetRotationForBonusRewardTabEntry(wndFeaturedEntry)
		self:BuildOverlay(wndFeaturedEntry, rTbl)
	end
end

function EssenceEventTracker:GetFeaturedEntries()
  --self.addonMatchMaker.tWndRefs.wndMain:FindChild("TabContent:RewardContent"):GetChildren()
  local wndFeaturedEntries = self.addonMatchMaker
  wndFeaturedEntries = wndFeaturedEntries and wndFeaturedEntries.tWndRefs
  wndFeaturedEntries = wndFeaturedEntries and wndFeaturedEntries.wndMain
  wndFeaturedEntries = wndFeaturedEntries and wndFeaturedEntries:FindChild("TabContent:RewardContent")
  wndFeaturedEntries = wndFeaturedEntries and wndFeaturedEntries:GetChildren() or {}
  return wndFeaturedEntries
end

function EssenceEventTracker:GetRotationForBonusRewardTabEntry(wndFeaturedEntry)
	local tData = wndFeaturedEntry:FindChild("InfoButton"):GetData()
	return self.tContentIds[tData.nContentId][tData.tRewardInfo.nRewardType]
end

function EssenceEventTracker:BuildOverlay(wndFeaturedEntry, rTbl)
  local overlay = Apollo.LoadForm(self.xmlDoc, "Overlay", wndFeaturedEntry, self)
  overlay:FindChild("Completed"):SetData(rTbl)
  if self:IsDone(rTbl) then
		overlay:FindChild("Completed"):SetCheck(true)
  else
		overlay:FindChild("Shader"):Show(false)
  end
end

function EssenceEventTracker:OnSave(eType)
	if eType == GameLib.CodeEnumAddonSaveLevel.Character then
		return {
			tMinimized = self.tMinimized,
			bShow = self.bShow,
		}
	elseif eType == GameLib.CodeEnumAddonSaveLevel.Realm then
		return {
			_version = 2,
			tDate = GameLib.GetServerTime(),
			tEventsDone = self.tEventsDone,
		}
	end
end

function EssenceEventTracker:OnRestore(eType, tSavedData)
	if eType == GameLib.CodeEnumAddonSaveLevel.Character then
		if tSavedData.tMinimized ~= nil then
			self.tMinimized = tSavedData.tMinimized
		end

		if tSavedData.bShow ~= nil then
			self.bShow = tSavedData.bShow
		end
	elseif eType == GameLib.CodeEnumAddonSaveLevel.Realm then
		if not tSavedData._version then --_version=1
			local fNow = GameLib.GetGameTime()
			local tNow = GameLib.GetServerTime()
			local offset = self:CompareDateTables(tSavedData.tDate, tNow)

			self.tEventsDone = {}
			for i, tRewardEnds in pairs(tSavedData.tEventsDone) do
				self.tEventsDone[i] = {}
				for j, v in pairs(tRewardEnds) do
					self.tEventsDone[i][j] = self:BuildDateTable(v-offset, fNow, tNow)
				end
			end
		elseif tSavedData._version == 2 then
			local fNow = GameLib.GetGameTime()
			local tNow = GameLib.GetServerTime()

			self.tEventsDone = {}
			for i, tRewardEnds in pairs(tSavedData.tEventsDone) do
				self.tEventsDone[i] = {}
				for j, v in pairs(tRewardEnds) do
					self.tEventsDone[i][j] = self:AdjustDateTable(v, fNow, tNow)
				end
			end
		end
	end
end

function EssenceEventTracker:OnDocumentReady()
	if self.xmlDoc == nil or not self.xmlDoc:IsLoaded() then
		Apollo.AddAddonErrorText(self, "Could not load the main window document for some reason.")
		return
	end
	Apollo.RegisterEventHandler("ChannelUpdate_Loot", "OnItemGained", self)

	Apollo.RegisterEventHandler("ObjectiveTrackerLoaded", "OnObjectiveTrackerLoaded", self)
	Event_FireGenericEvent("ObjectiveTracker_RequestParent")
	self.bIsLoaded = true
end

function EssenceEventTracker:OnObjectiveTrackerLoaded(wndForm)
	if not wndForm or not wndForm:IsValid() then
		return
	end

	Apollo.RemoveEventHandler("ObjectiveTrackerLoaded", self)

	Apollo.RegisterEventHandler("QuestInit", "OnQuestInit", self)
	Apollo.RegisterEventHandler("PlayerLevelChange", "OnPlayerLevelChange", self)
	Apollo.RegisterEventHandler("CharacterCreated", "OnCharacterCreated", self)

	self.wndMain = Apollo.LoadForm(self.xmlDoc, "ContentGroupItem", wndForm, self)
	self.wndContainer = self.wndMain:FindChild("EpisodeGroupContainer")

	self:Setup()
end

function EssenceEventTracker:Setup()

	if GameLib.GetPlayerUnit() == nil or GameLib.GetPlayerLevel(true) < 50 then
		self.wndMain:Show(false)
		return
	end

	if self.bSetup then
		return
	end
	Apollo.RegisterEventHandler("ToggleShowEssenceTracker", "ToggleShowEssenceTracker", self)

	local tContractData =
	{
		["strAddon"] = lstrAddon,
		["strEventMouseLeft"] = "ToggleShowEssenceTracker",
		["strEventMouseRight"] = "",
		["strIcon"] = "EssenceTracker_Icon",
		["strDefaultSort"] = kstrAddon,
	}
	Event_FireGenericEvent("ObjectiveTracker_NewAddOn", tContractData)

	self:UpdateAll()

	self.bSetup = true
end

function EssenceEventTracker:ToggleShowEssenceTracker()
	self.bShow = not self.bShow

	self:UpdateAll()
end

---------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------

function EssenceEventTracker:IsInterestingRotation(rot)
	-- rotation = { arRewards = {...}, bIsVeteran = true/false, nContentId = "number", nContentType = Daily/WB/Queues/... , strWorld = "LocalizedName" }
	-- rotation.arRewards = {monReward = userdata, nMultiplier=1/./nil, nRewardItemType=3/nil, nRewardType=1/2, nSecondsRemaining=0, strIcon = ""}
		--nRewardType = 1=Additive, 2=Multiplicative
		--nRewardItemType = 3=Violet, nil=uninteresting?
	return not(#rot.arRewards < 1 or #rot.arRewards <= 1 and rot.arRewards[1].nRewardType == 2 and rot.arRewards[1].nMultiplier <= 1)
end

function EssenceEventTracker:BuildRotationTable( rot )
	local redo = false
	for _, reward in ipairs(rot.arRewards) do
		if reward.nRewardType == 1 or reward.nRewardType == 2 and reward.nMultiplier > 1 then
			local rTbl = { --usually called 'rTbl'
				strText = "["..ktShortContentTypes[rot.nContentType].."] "..self:GetTitle(rot),
				fEndTime = (reward and reward.nSecondsRemaining or 0) + GameLib.GetGameTime(),
				src = rot,
				strIcon = reward and reward.strIcon or "",
				strMult = tostring(reward and reward.nMultiplier and reward.nMultiplier>1 and reward.nMultiplier or ""),
				tReward = reward,
			}
			table.insert(self.tRotations, rTbl)
			self.tContentIds[rot.nContentId] = self.tContentIds[rot.nContentId] or {}
			self.tContentIds[rot.nContentId][reward.nRewardType] = rTbl
			if reward.nSecondsRemaining <= 0 then
				redo = true
			end
		end
	end
	return redo
end

do
	--[[
		what i want:

		Ready > NotReady
			V
		Expeditions > Dungeon > Queues > PvP > WB > Dailies
			V
		Purple > Red > Green > Blue
			V
		arbetiary differences (nContentId)
	]]
	local contentDigit = {[1] = 5, [2] = 1, [3] = 6, [4] = 2, [5] = 3, [6] = 4} --rTbl.src.nContentType = 1-6; Dungeon - Dailies - Expeditions - WB - PVP - Queues
	local colorDigit = {
		[AccountItemLib.CodeEnumAccountCurrency.PurpleEssence] = 4,
		[AccountItemLib.CodeEnumAccountCurrency.RedEssence] = 3,
		[AccountItemLib.CodeEnumAccountCurrency.GreenEssence] = 2,
		[AccountItemLib.CodeEnumAccountCurrency.BlueEssence] = 1,
	}
	function EssenceEventTracker:Compare_rTbl(rTbl1, rTbl2)
		local done1, done2 = self:IsDone(rTbl1), self:IsDone(rTbl2)
		if done1 and not done2 then
			return false
		elseif done2 and not done1 then
			return true
		end

		local content1, content2 = contentDigit[rTbl1.src.nContentType], contentDigit[rTbl2.src.nContentType]
		if content1 ~= content2 then
			return content1 > content2
		end

		local color1, color2 = colorDigit[rTbl1.tReward.monReward:GetAccountCurrencyType()], colorDigit[rTbl2.tReward.monReward:GetAccountCurrencyType()]
		if color1 ~= color2 then
			return color1 > color2
		end
		return rTbl1.src.nContentId < rTbl2.src.nContentId
	end
end

function EssenceEventTracker:GetTitle(rot)--[[
nContentType: (1-6)
	1,3,5 - strWorld
	2 - strZoneName
	4 - peWorldBoss:GetName()
	6 - ktMatchTypeNames[eMatchType]		]]
	if rot.nContentType%2 == 1 then
		return rot.strWorld
	elseif rot.nContentType == 2 then
		return rot.strZoneName
	elseif rot.nContentType == 4 then
		return rot.peWorldBoss:GetName()
	elseif rot.nContentType == 6 then
		return ktMatchTypeNames[rot.eMatchType]
	end
end

local insert = table.insert
function EssenceEventTracker:UpdateAll()
	self.timerUpdateDelay:Stop()
	self.tRotations = {}
	self.tContentIds = {}

	for idx, nContentType in pairs(GameLib.CodeEnumRewardRotationContentType) do
		GameLib.RequestRewardUpdate(nContentType)
	end

	local redo = false --do we need to :UpdateAll() again, because nSecondsLeft <= 0

	local arRewardRotations = GameLib.GetRewardRotations()
	for _, rotation in ipairs(arRewardRotations) do
		if self:IsInterestingRotation(rotation) then --filter all (only) 1x Multiplicators, aka. all thats 'default'
			if self:BuildRotationTable(rotation) then
				redo = true
			end
		end
	end

	if redo or #self.tRotations == 0 then
		self.updateTimer = self.updateTimer or ApolloTimer.Create(0, false, "UpdateAll", self)
		self.updateTimer:Start()
	else
		self.updateTimer = nil
	end

	self:ResizeAll(#self.tRotations)
end

function EssenceEventTracker:UpdateFeaturedList()
	if next(self:GetFeaturedEntries{}) ~= nil then
		self.addonMatchMaker:BuildFeaturedList()
	end
end

function EssenceEventTracker:ResizeAll(nCount)
	local nStartingHeight = self.wndMain:GetHeight()
	local bStartingShown = self.wndMain:IsShown()

	for i, rTbl in ipairs(self.tRotations) do
		self:DrawRotation(i, rTbl)
	end

	local tChildren = self.wndContainer:GetChildren()
	for i = nCount+1, #tChildren, 1 do
		tChildren[i]:Destroy()
	end

	if self.bShow then
		if self.tMinimized.bRoot then
			self.wndContainer:Show(false)

			local nLeft, nTop, nRight, nBottom = self.wndMain:GetOriginalLocation():GetOffsets()
			self.wndMain:SetAnchorOffsets(nLeft, nTop, nRight, nBottom)
		else
			-- Resize quests
			local nChildHeight = self.wndContainer:ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop, function(wndA, wndB)
				return self:Compare_rTbl(wndA:GetData(), wndB:GetData())
			end)

			local nHeightChange = nChildHeight - self.wndContainer:GetHeight()
			self.wndContainer:Show(true)

			local nLeft, nTop, nRight, nBottom = self.wndMain:GetAnchorOffsets()
			self.wndMain:SetAnchorOffsets(nLeft, nTop, nRight, nBottom + nHeightChange)
		end
	end
	local bShow = self.bShow and nCount > 0
	self.wndMain:Show(bShow)

	if nStartingHeight ~= self.wndMain:GetHeight() or self.nTrackerCounting ~= nCount or bShow ~= bStartingShown then
		local tData =
		{
			["strAddon"] = lstrAddon,
			["strText"] = nCount,
			["bChecked"] = self.bShow,
		}
		Event_FireGenericEvent("ObjectiveTracker_UpdateAddOn", tData)
	end

	if self.bShow and not self.tMinimized.bRoot then
		self.timerRealTimeUpdate:Start()
	end

	self.nTrackerCounting = nCount
end

function EssenceEventTracker:IsDone(rTbl)
	local tRewardEnds = self.tEventsDone[rTbl.src.nContentId]
	if not tRewardEnds then return false end

	local tEnd = tRewardEnds[rTbl.tReward.nRewardType]
	if not tEnd then return false end

	local fEnd = tEnd.nGameTime
	if not fEnd then return false end

	local fNow = GameLib.GetGameTime()
	if fNow < fEnd then return true end

	tRewardEnds[rTbl.tReward.nRewardType] = nil
	if not next(tRewardEnds) then
		self.tEventsDone[rTbl.src.nContentId] = nil
	end
	return false --we are past the 'target-time'
end

function EssenceEventTracker:DrawRotation(idx, rTbl)
	while not self.wndContainer:GetChildren()[idx] do
		Apollo.LoadForm(self.xmlDoc, "EssenceItem", self.wndContainer, self)
	end
	local wndForm = self.wndContainer:GetChildren()[idx]
	wndForm:FindChild("EssenceIcon"):SetSprite(rTbl.strIcon)
	wndForm:FindChild("EssenceIcon"):SetText(rTbl.strMult)
	if rTbl.tReward.nRewardType == 1 then -- example: 400 Purple Essence
		wndForm:FindChild("EssenceIcon"):SetTooltip(rTbl.tReward.monReward:GetMoneyString())
	elseif rTbl.tReward.nRewardType == 2 then --example: 4x Green Essence
		wndForm:FindChild("EssenceIcon"):SetTooltip(rTbl.tReward.nMultiplier.."x "..rTbl.tReward.monReward:GetTypeString())
	else --remove
		wndForm:FindChild("EssenceIcon"):SetTooltip("")
	end
	wndForm:FindChild("ControlBackerBtn:TimeText"):SetText(self:HelperTimeString(rTbl.fEndTime-GameLib.GetGameTime()))
	wndForm:FindChild("ControlBackerBtn:TitleText"):SetText(self:HelperColorizeIf(rTbl.strText, kstrRed, self:IsDone(rTbl)))
	wndForm:SetData(rTbl)
end

function EssenceEventTracker:RedrawTimers()
	local update = false
	for _, wndForm in ipairs(self.wndContainer:GetChildren()) do
		local rTbl = wndForm:GetData()
		local fTimeLeft = rTbl.fEndTime-GameLib.GetGameTime()
		wndForm:FindChild("ControlBackerBtn:TimeText"):SetText(self:HelperTimeString(fTimeLeft))
		if fTimeLeft < 0 then update = true end
	end
	if update then
		self:UpdateAll()
	end
end

---------------------------------------------------------------------------------------------------
-- Game Events
---------------------------------------------------------------------------------------------------

function EssenceEventTracker:OnQuestInit()
	self:Setup()

	if self.bSetup then
		self.timerUpdateDelay:Start()
	end
end

function EssenceEventTracker:OnPlayerLevelChange()
	self:Setup()
end

function EssenceEventTracker:OnCharacterCreated()
	self:Setup()
end

do
	local validCurrencies = {
		[AccountItemLib.CodeEnumAccountCurrency.PurpleEssence] = 1,
		[AccountItemLib.CodeEnumAccountCurrency.BlueEssence] = 2,
		[AccountItemLib.CodeEnumAccountCurrency.RedEssence] = 2,
		[AccountItemLib.CodeEnumAccountCurrency.GreenEssence] = 2,
	}
	function EssenceEventTracker:OnItemGained(type, args)
		if type == GameLib.ChannelUpdateLootType.Currency and args.monNew then
			if validCurrencies[args.monNew:GetAccountCurrencyType()] then
				self:GainedEssence(args.monNew)
			end
		end
	end

	instances = {
		[13] = {--"Stormtalon's Lair",
			parentZoneId = nil,	id = 19,	nContentId = 12,	nContentType = 1,	nBase = 65,
		},
		[14] = {--"Skullcano",
			{parentZoneId = 0,	id = 20,	nContentId = 13,	nContentType = 1,	nBase = 65},
			{parentZoneId = 20,	id = 73,	nContentId = 13,	nContentType = 1,	nBase = 65},
		},
		[48] = {--"Sanctuary of the Swordmaiden",
			parentZoneId = nil,	id = 85,	nContentId = 14,	nContentType = 1,	nBase = 70,
		},
		[15] = { --"Ruins of Kel Voreth"
			parentZoneId = nil,	id = 21,	nContentId = 15,	nContentType = 1,	nBase = 65,
		},
		[69] = {--"Ultimate Protogames",
			parentZoneId = 154,	id = nil,	nContentId = 16,	nContentType = 1,	nBase = 70, --?
		},
		[90] = { --"Academy",
			parentZoneId = 469,	id = nil,	nContentId = 17,	nContentType = 1,	nBase = 70,
		},
		[105] = { --"Citadel",
			parentZoneId = nil,	id = 560,	nContentId = 45,	nContentType = 1,	nBase = 70,
		},
		[18] = {--"Infestation",
			parentZoneId = nil,	id = 25,	nContentId = 18,	nContentType = 3,	nBase = 45,
		},
		[38] = {--"Outpost M-13",
			parentZoneId = 63,	id = nil,	nContentId = 19,	nContentType = 3,	nBase = 50,
		},
		[51] = {--"Rage Logic",
			parentZoneId = 93,	id = nil,	nContentId = 20,	nContentType = 3,	nBase = 45,
		},
		[58] = {--"Space Madness",
			parentZoneId = nil,	id = 121,	nContentId = 21,	nContentType = 3,	nBase = 45,
		},
		[62] = {--"Gauntlet",
			parentZoneId = 132,	id = nil,	nContentId = 22,	nContentType = 3,	nBase = 45,
		},
		[60] = {--"Deepd Space Exploration",
			parentZoneId = 140,	id = nil,	nContentId = 23,	nContentType = 3,	nBase = 50,
		},
		[83] = {--"Fragment Zero",
			{parentZoneId = nil,id = 277,	nContentId = 24,	nContentType = 3,	nBase = 50,},
			{parentZoneId = 277,id = nil,	nContentId = 24,	nContentType = 3,	nBase = 50,},
		},
		[107] = { --"Ether",
			parentZoneId = 562,	id = nil,	nContentId = 25,	nContentType = 3,	nBase = 50,
		},
		[40] = { --"Walatiki Temple"
			parentZoneId = nil,	id = 69,	nContentId = 38,	nContentType = 5,	nBase = 150, --?
		},
		[53] = { --"Halls of the Bloodsworn"
			parentZoneId = nil,	id = 99,	nContentId = 39,	nContentType = 5,	nBase = 80,
		},
		[57] = { --"Daggerstone Pass"
			parentZoneId = nil,	id = 103,	nContentId = 40,	nContentType = 5,	nBase = 300,
		},
	}

	function EssenceEventTracker:GainedEssence(tMoney)
		if GroupLib.InInstance() then--Expedition? Dungeon? (Queued Normal Dungeon?)
			local zone = GameLib.GetCurrentZoneMap()
			if not instances[zone.continentId] then return end

			local inst;
			if #instances[zone.continentId] > 0 then
				for _, instance in ipairs(instances[zone.continentId]) do
					if (not instance.parentZoneId or instance.parentZoneId==zone.parentZoneId) and (not instance.id or instance.id==zone.id) then
						inst = instance
						break;
					end
				end
			else
				local instance = instances[zone.continentId]
				if (not instance.parentZoneId or instance.parentZoneId==zone.parentZoneId) and (not instance.id or instance.id==zone.id) then
					inst = instance
				end
			end
			if not inst then return end


			--we ARE in inst! Pass to other function, because we only wanna detect in this function
			self:EssenceInInstance(tMoney, inst.nContentId, inst.nBase)
			self:EssenceInQueue(tMoney, inst.nContentType, inst.nBase)
		end
	end

	local function closeEnough(approx, exact)
		print("approx:", approx, exact)
		if approx*1.05 > exact and approx*0.95 < exact then
			return true
		else
			return false
		end
	end

	function EssenceEventTracker:EssenceInInstance(tMoney, nContentId, nBase)
		local nRewardType = validCurrencies[tMoney:GetAccountCurrencyType()]
		local rTbl = self.tContentIds[nContentId] and self.tContentIds[nContentId][nRewardType]
		if not rTbl then return end

		if tMoney:GetAccountCurrencyType() ~= rTbl.tReward.monReward:GetAccountCurrencyType() then return end

		if nRewardType == 1 then --no multiplicator (purple essences)
			local fSignature = AccountItemLib.GetPremiumTier() > 0 and 1.5 or 1
			local approx = rTbl.tReward.monReward:GetAmount() * fSignature

			if closeEnough(approx, tMoney:GetAmount()) then
				self:MarkAsDone(rTbl)
			end
		else --nRewardType == 2
			local nMultiplier = rTbl.tReward.nMultiplier
			local fPrime = 1+0.1*GameLib.GetWorldPrimeLevel()
			local fSignature = AccountItemLib.GetPremiumTier() > 0 and 1.5 or 1

			local approx = nBase * nMultiplier * fPrime * fSignature

			if closeEnough(approx, tMoney:GetAmount()) or closeEnough(2*approx, tMoney:GetAmount()) then -- last event grants double points
				self:MarkAsDone(rTbl)
			end
		end
	end

	function EssenceEventTracker:EssenceInQueue(tMoney, nContentType, nBase)
		local nRewardType = validCurrencies[tMoney:GetAccountCurrencyType()]
		local rTbl = self.tContentIds[46] and self.tContentIds[46][nRewardType] --46 = Random Queue - usually normal dungeon with rewardType 1 (100 purples)
		if not rTbl or rTbl.src.eMatchType ~= nContentType then return end

		if tMoney:GetAccountCurrencyType() ~= rTbl.tReward.monReward:GetAccountCurrencyType() then return end

		if nRewardType == 1 then --no multiplicator (purple essences)
			local fSignature = AccountItemLib.GetPremiumTier() > 0 and 1.5 or 1
			local approx = rTbl.tReward.monReward:GetAmount()

			if closeEnough(approx, tMoney:GetAmount()) then
				self:MarkAsDone(rTbl)
			end
		else --nRewardType == 2
			local nMultiplier = rTbl.tReward.nMultiplier
			local fPrime = 1+0.1*GameLib.GetWorldPrimeLevel()
			local fSignature = AccountItemLib.GetPremiumTier() > 0 and 1.5 or 1

			local approx = nBase * nMultiplier * fPrime * fSignature

			if closeEnough(approx, tMoney:GetAmount()) or closeEnough(2*approx, tMoney:GetAmount()) then -- last event grants double points
				self:MarkAsDone(rTbl)
			end
		end
	end
end

function EssenceEventTracker:MarkAsDone(rTbl, bToggle)
	local cId, rId = rTbl.src.nContentId, rTbl.tReward.nRewardType

	if bToggle then
		if not self.tEventsDone[cId] or not self.tEventsDone[cId][rId] then
			self.tEventsDone[cId] = self.tEventsDone[cId] or {}
			self.tEventsDone[cId][rId] = self:BuildDateTable(rTbl.fEndTime-10)
		else
			self.tEventsDone[cId][rId] = nil
			if not next(self.tEventsDone[cId]) then
				self.tEventsDone[cId] = nil
			end
		end
	else
		self.tEventsDone[cId] = self.tEventsDone[cId] or {}
		self.tEventsDone[cId][rId] = self:BuildDateTable(rTbl.fEndTime-10)
	end

	self:UpdateAll()
	self:UpdateFeaturedList()
end

---------------------------------------------------------------------------------------------------
-- Controls Events
---------------------------------------------------------------------------------------------------

function EssenceEventTracker:OnEpisodeGroupControlBackerMouseEnter(wndHandler, wndControl)
	if wndHandler == wndControl then
		wndHandler:FindChild("EpisodeGroupMinimizeBtn"):Show(true)
	end
end

function EssenceEventTracker:OnEpisodeGroupControlBackerMouseExit(wndHandler, wndControl)
	if wndHandler == wndControl then
		local wndBtn = wndHandler:FindChild("EpisodeGroupMinimizeBtn")
		wndBtn:Show(wndBtn:IsChecked())
	end
end

function EssenceEventTracker:OnContentGroupMinimizedBtnChecked(wndHandler, wndControl, eMouseButton)
	self.tMinimized.bRoot = true
	self:UpdateAll()
end

function EssenceEventTracker:OnContentGroupMinimizedBtnUnChecked(wndHandler, wndControl, eMouseButton)
	self.tMinimized.bRoot = false
	self:UpdateAll()
end

function EssenceEventTracker:OnGenerateTooltip(wndControl, wndHandler, eType, arg1, arg2)

end

function EssenceEventTracker:OnEssenceItemClick(wndHandler, wndControl, eMouseButton, bDoubleClick)
	if not bDoubleClick or wndHandler~=wndControl then return end
	local rTbl = wndHandler:GetParent():GetData() --Button -> EssenceItem
	self:MarkAsDone(rTbl, true)
	self:UpdateAll()
end

function EssenceEventTracker:OnRewardTabCompletedCheck(wndHandler, wndControl)
	wndControl:GetParent():FindChild("Shader"):Show(true)
	local rTbl = wndHandler:GetData()
	self:MarkAsDone(rTbl, true)
end

function EssenceEventTracker:OnRewardTabCompletedUncheck(wndHandler, wndControl)
	wndControl:GetParent():FindChild("Shader"):Show(false)
	local rTbl = wndHandler:GetData()
	self:MarkAsDone(rTbl, true)
end

---------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------
local floor = math.floor
function EssenceEventTracker:HelperTimeString(fTime, strColorOverride)
	local fSeconds = fTime % 60
	local fMinutes = (fTime / 60)%60
	local fHours = (fTime / 3600)%24
	local fDays = (fTime / 86400)
	local strColor = kstrYellow
	if strColorOverride then
		strColor = strColorOverride
	end

	local strTime;

	if fDays >= 1 then
		strTime = ("%dd"):format(fDays)
	elseif fHours >= 1 then
		strTime = ("%dh"):format(fHours)
	else
		strTime = ("%d:%.02d"):format(fMinutes, fSeconds)
	end

	return string.format("<T Font=\"CRB_InterfaceMedium_B\" TextColor=\"%s\">(%s)</T>", strColor, strTime)
end

function EssenceEventTracker:HelperColorizeIf(str, strColor, bIf)
	if bIf then
		return string.format("<T TextColor=\"%s\">%s</T>", strColor, str)
	else
		return str
	end
end

do
	local constants = {
		[1] = 31 * 86400,
		[2] = 28 * 86400,
		[3] = 31 * 86400,
		[4] = 30 * 86400,
		[5] = 31 * 86400,
		[6] = 30 * 86400,
		[7] = 31 * 86400,
		[8] = 31 * 86400,
		[9] = 30 * 86400,
		[10]= 31 * 86400,
		[11]= 30 * 86400,
		[12]= 31 * 86400,
	}

	--this is no readable date-table. But its fine to compare with others.
	function EssenceEventTracker:BuildDateTable(fTime, fNow, tNow)
		fNow = fNow or GameLib.GetGameTime()
		tNow = tNow or GameLib.GetServerTime()

		local dT = fTime-fNow

		return {
			nYear = tNow.nYear,
			nMonth = tNow.nMonth,
			nDay = tNow.nDay,
			nHour = tNow.nHour,
			nMinute = tNow.nMinute,
			nSecond = tNow.nSecond + dT,
			nGameTime = fTime,
		}
	end

	function EssenceEventTracker:AdjustDateTable(tTime, fNow, tNow)
		fNow = fNow or GameLib.GetGameTime()
		tNow = tNow or GameLib.GetServerTime()

		tTime.nGameTime = fNow+self:CompareDateTables(tNow, tTime)
		return tTime
	end

	function EssenceEventTracker:CompareDateTables(date1, date2) --returns seconds between date1 and date2
		local nTotal = 0
		local nYear = 0

		if date1.nYear < date2.nYear then
			local diff = date2.nYear-date1.nYear
			nTotal = nTotal + diff * 31536000
			nTotal = nTotal + math.floor(((date1.nYear-1)%4+diff)/4) * 86400
			nYear = date1.nYear
		elseif date1.nYear > date2.nYear then
			local diff = date1.nYear-date2.nYear
			nTotal = nTotal - diff * 31536000
			nTotal = nTotal - math.floor(((date2.nYear-1)%4+diff)/4) * 86400
			nYear = date2.nYear
		end

		if date1.nMonth < date2.nMonth then
			for i = date1.nMonth, date2.nMonth-1, 1 do
				nTotal = nTotal + constants[i]
			end
			if nYear%4 == 0 and date1.nMonth <= 2 and date2.nMonth > 2 then
				nTotal = nTotal + 86400 --+1 day
			end
		elseif date1.nMonth > date2.nMonth then
			for i = date2.nMonth, date1.nMonth-1, 1 do
				nTotal = nTotal - constants[i]
			end
			if nYear%4 == 0 and date2.nMonth <= 2 and date1.nMonth > 2 then
				nTotal = nTotal - 86400
			end
		end

		if date1.nDay ~= date2.nDay then
			nTotal = nTotal + (date2.nDay-date1.nDay)*86400
		end

		if date1.nHour ~= date2.nHour then
			nTotal = nTotal + (date2.nHour-date1.nHour)*3600
		end

		if date1.nMinute ~= date2.nMinute then
			nTotal = nTotal + (date2.nMinute-date1.nMinute)*60
		end

		nTotal = nTotal + date2.nSecond - date1.nSecond

		return nTotal
	end
end

local EssenceEventTrackerInst = EssenceEventTracker:new()
EssenceEventTrackerInst:Init()
