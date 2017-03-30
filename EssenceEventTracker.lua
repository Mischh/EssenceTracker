require "Window"
require "GameLib"

local EssenceEventTracker = {}

local kstrAddon = "EssenceTracker"
local lstrAddon = "Essence Tracker"

local ktShortContentTypes = {
	[1] = "Dng",
	[2] = "Day",
	[3] = "Exp",
	[4] = "WB",
	[5] = "PvP",
	[6] = "Que",
}
local knExtraSortBaseValue = 100
local keFeaturedSort = {
	ContentType = 1,
	TimeRemaining = 2,
	Multiplier = knExtraSortBaseValue + 0,
	Color = knExtraSortBaseValue + 1,
}
local ktRewardTypes = {
	Multiplier = 2,
	Addition = 1,
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
local kstrColors = {
	kstrRed 	= "ffff4c4c",
	kstrGreen 	= "ff2fdc02",
	kstrYellow 	= "fffffc00",
	kstrLightGrey = "ffb4b4b4",
	kstrHighlight = "ffffe153",
}

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
		bDoneRoot = false,
		tQuests = {},
	}
	o.tEventsDone = {}
	o.tEventsAttending = {}
	o.tCustomSortFunctions = {
		[keFeaturedSort.ContentType] = self.SortByContentType,
		[keFeaturedSort.TimeRemaining] = self.SortByTimeRemaining,
		[keFeaturedSort.Multiplier] = self.SortByMultiplier,
		[keFeaturedSort.Color] = self.SortByColor
	}
	o.eSort = keFeaturedSort.ContentType

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
	self:HookHelperCreateFeaturedSort()
	self:HookGetSortedRewardList()
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

function EssenceEventTracker:HookHelperCreateFeaturedSort()
	local originalHelperCreateFeaturedSort = self.addonMatchMaker.HelperCreateFeaturedSort
	self.addonMatchMaker.HelperCreateFeaturedSort = function(...)
		originalHelperCreateFeaturedSort(...)
		self:AddAdditionalSortOptions()
	end
end

function EssenceEventTracker:HookGetSortedRewardList()
	local originalGetSortedRewardList = self.addonMatchMaker.GetSortedRewardList
	self.addonMatchMaker.GetSortedRewardList = function(ref, arRewardList, ...)
		self:UpdateSortType(self.addonMatchMaker.tWndRefs.wndFeaturedSort:GetData())
		return self:GetSortedRewardList(self.eSort, arRewardList, originalGetSortedRewardList, ref, ...)
	end
end

function EssenceEventTracker:AddAdditionalSortOptions()
	local wndSort = self:GetSortWindow()
	if not wndSort then return end
	local wndSortDropdown = wndSort:FindChild("FeaturedFilterDropdown")
	if not wndSortDropdown then return end
	local wndSortContainer = wndSortDropdown:FindChild("Container")

	local refXmlDoc = self.addonMatchMaker.xmlDoc
	local strSortOptionForm = "FeaturedContentFilterBtn"

	local wndSortMultiplier = Apollo.LoadForm(refXmlDoc, strSortOptionForm, wndSortContainer, self.addonMatchMaker)
	wndSortMultiplier:SetData(keFeaturedSort.Multiplier)
	wndSortMultiplier:SetText(Apollo.GetString("Protogames_Bonus")) --"Multiplier"
	if wndSort:GetData() == keFeaturedSort.Multiplier then
		wndSortMultiplier:SetCheck(true)
	end

	local wndSortColor = Apollo.LoadForm(refXmlDoc, strSortOptionForm, wndSortContainer, self.addonMatchMaker)
	wndSortColor:SetData(keFeaturedSort.Color)
	wndSortColor:SetText(Apollo.GetString("AccountInventory_Essence").." "..Apollo.GetString("CRB_Color")) --"Essence Color"

	local sortContainerChildren = wndSortContainer:GetChildren()
	local nLeft, nTop, nRight = wndSortDropdown:GetOriginalLocation():GetOffsets()
	local nBottom = nTop + (#sortContainerChildren * wndSortMultiplier:GetHeight()) + 11
	wndSortDropdown:SetAnchorOffsets(nLeft, nTop, nRight, nBottom)
	wndSortContainer:ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop)

	for i = 1, #sortContainerChildren do
		local sortButton = sortContainerChildren[i]
		if self.eSort == sortButton:GetData() then
			wndSort:SetData(sortButton:GetData())
			wndSort:SetText(sortButton:GetText())
			sortButton:SetCheck(true)
		else
			sortButton:SetCheck(false)
		end
	end
end

function EssenceEventTracker:GetSortWindow()
	--self.addonMatchMaker.tWndRefs.wndFeaturedSort
	local wndSort = self.addonMatchMaker
	wndSort = wndSort and wndSort.tWndRefs
	wndSort = wndSort and wndSort.wndFeaturedSort
	return wndSort
end

function EssenceEventTracker:UpdateSortType(eSort)
	local old_eSort = self.eSort
	self.eSort = eSort
	if eSort ~= old_eSort then
		self:UpdateAll()
	end
end

function EssenceEventTracker:GetSortedRewardList(eSort, arRewardList, funcOrig, ref, ...)
	if self.tCustomSortFunctions[eSort] then
		table.sort(arRewardList,
			function (tData1, tData2)
				local rTbl1 = self:GetRotationForFeaturedReward(tData1)
				local rTbl2 = self:GetRotationForFeaturedReward(tData2)
				if not rTbl1 or not rTbl2 then
					return self:CompareNil(rTbl1, rTbl2) > 0
				end
				return self.tCustomSortFunctions[eSort](self, rTbl1, rTbl2)
			end
		)
	else
		funcOrig(ref, arRewardList, ...)
	end

	return arRewardList
end

function EssenceEventTracker:CompareNil(rTbl1, rTbl2)
	if not rTbl1 and not rTbl2 then
		return 0
	elseif not rTbl1 then
		return 1
	elseif not rTbl2 then
		return -1
	end
	return 0
end

function EssenceEventTracker:CompareCompletedStatus(rTbl1, rTbl2)
	local bIsDone1 = self:IsDone(rTbl1) and not self:IsAttended(rTbl1)
	local bIsDone2 = self:IsDone(rTbl2) and not self:IsAttended(rTbl2)
	if bIsDone1 and not bIsDone2 then return 1 end
	if not bIsDone1 and bIsDone2 then return -1 end
	return 0
end

function EssenceEventTracker:SortByContentType(rTbl1, rTbl2)
	local nCompare = self:CompareCompletedStatus(rTbl1, rTbl2)
	if nCompare ~= 0 then return nCompare < 0 end
	nCompare = self:CompareByContentType(rTbl1, rTbl2)
	if nCompare ~= 0 then return nCompare < 0 end
	nCompare = self:CompareByMultiplier(rTbl1, rTbl2)
	if nCompare ~= 0 then return nCompare < 0 end
	return self:CompareByContentId(rTbl1, rTbl2) < 0
end

function EssenceEventTracker:SortByTimeRemaining(rTbl1, rTbl2)
	local nCompare = self:CompareCompletedStatus(rTbl1, rTbl2)
	if nCompare ~= 0 then return nCompare < 0 end
	nCompare = self:CompareByTimeRemaining(rTbl1, rTbl2)
	if nCompare ~= 0 then return nCompare < 0 end
	nCompare = self:CompareByMultiplier(rTbl1, rTbl2)
	if nCompare ~= 0 then return nCompare < 0 end
	nCompare = self:CompareByContentType(rTbl1, rTbl2)
	if nCompare ~= 0 then return nCompare < 0 end
	return self:CompareByContentId(rTbl1, rTbl2) < 0
end

function EssenceEventTracker:SortByMultiplier(rTbl1, rTbl2)
	local nCompare = self:CompareCompletedStatus(rTbl1, rTbl2)
	if nCompare ~= 0 then return nCompare < 0 end
	nCompare = self:CompareByMultiplier(rTbl1, rTbl2)
	if nCompare ~= 0 then return nCompare < 0 end
	nCompare = self:CompareByTimeRemaining(rTbl1, rTbl2)
	if nCompare ~= 0 then return nCompare < 0 end
	nCompare = self:CompareByContentType(rTbl1, rTbl2)
	if nCompare ~= 0 then return nCompare < 0 end
	return self:CompareByContentId(rTbl1, rTbl2) < 0
end

function EssenceEventTracker:SortByColor(rTbl1, rTbl2)
	local nCompare = self:CompareCompletedStatus(rTbl1, rTbl2)
	if nCompare ~= 0 then return nCompare < 0 end
	nCompare = self:CompareByColor(rTbl1, rTbl2)
	if nCompare ~= 0 then return nCompare < 0 end
	nCompare = self:CompareByMultiplier(rTbl1, rTbl2)
	if nCompare ~= 0 then return nCompare < 0 end
	nCompare = self:CompareByContentType(rTbl1, rTbl2)
	if nCompare ~= 0 then return nCompare < 0 end
	return self:CompareByContentId(rTbl1, rTbl2) < 0
end

function EssenceEventTracker:CompareByContentType(rTbl1, rTbl2)
	local nA = rTbl1.src.nContentType or 0
	local nB = rTbl2.src.nContentType or 0
	return nA - nB
end

function EssenceEventTracker:CompareByTimeRemaining(rTbl1, rTbl2)
	local nA = rTbl1.fEndTime or 0
	local nB = rTbl2.fEndTime or 0
	local nAB = nA - nB
	return math.abs(nAB)<5 and 0 or nAB
end

function EssenceEventTracker:CompareByMultiplier(rTbl1, rTbl2)
	local nA = rTbl1.tReward and rTbl1.tReward.nMultiplier or 0
	local nB = rTbl2.tReward and rTbl2.tReward.nMultiplier or 0
	return nB - nA
end

function EssenceEventTracker:CompareByColor(rTbl1, rTbl2)
	local nA = rTbl1.tReward and rTbl1.tReward.monReward and rTbl1.tReward.monReward:GetAccountCurrencyType() or 0
	local nB = rTbl2.tReward and rTbl2.tReward.monReward and rTbl2.tReward.monReward:GetAccountCurrencyType() or 0
	return nB - nA
end

function EssenceEventTracker:CompareByContentId(rTbl1, rTbl2)
	local nA = rTbl1.src.nContentId or 0
	local nB = rTbl2.src.nContentId or 0
	return nB - nA
end

function EssenceEventTracker:PlaceOverlays()
	local wndFeaturedEntries = self:GetFeaturedEntries()
	for i = 1, #wndFeaturedEntries do
		local wndFeaturedEntry = wndFeaturedEntries[i]
		local rTbl = self:GetRotationForBonusRewardTabEntry(wndFeaturedEntry)
		if rTbl then
			self:BuildOverlay(wndFeaturedEntry, rTbl)
		end
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
	return self:GetRotationForFeaturedReward(tData)
end

function EssenceEventTracker:GetRotationForFeaturedReward(tData)
	local rTbl = tData and self.tContentIds
	rTbl = rTbl and rTbl[tData.nContentId]
	rTbl = rTbl and rTbl[tData.tRewardInfo.nRewardType] or nil
	return rTbl
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
			eSort = self.eSort,
		}
	elseif eType == GameLib.CodeEnumAddonSaveLevel.Realm then
		return {
			_version = 2,
			tEventsDone = self.tEventsDone,
			tEventsAttending = self.tEventsAttending,
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

		if tSavedData.eSort ~= nil then
			self.eSort = tSavedData.eSort
		end
	elseif eType == GameLib.CodeEnumAddonSaveLevel.Realm then
		if not tSavedData._version then --_version=1
			local fNow = GameLib.GetGameTime()
			local tNow = GameLib.GetServerTime()
			local offset = self:CompareDateTables(tSavedData.tDate, tNow)

			self.tEventsDone = {}
			for i, tRewardEnds in pairs(tSavedData.tEventsDone or {}) do
				self.tEventsDone[i] = {}
				for j, v in pairs(tRewardEnds) do
					self.tEventsDone[i][j] = self:BuildDateTable(v-offset, fNow, tNow)
				end
			end
		elseif tSavedData._version == 2 then
			local a,b --passthrough for :AdjustDateTable

			self.tEventsDone = {}
			for i, tRewardEnds in pairs(tSavedData.tEventsDone or {}) do
				self.tEventsDone[i] = {}
				for j, v in pairs(tRewardEnds) do
					self.tEventsDone[i][j],a,b = self:AdjustDateTable(v, a, b)
				end
			end

			self.tEventsAttending = tSavedData.tEventsAttending or {}
			self:CheckRestoredAttendingEvents()
		end
	end
end

function EssenceEventTracker:OnDocumentReady()
	if self.xmlDoc == nil or not self.xmlDoc:IsLoaded() then
		Apollo.AddAddonErrorText(self, "Could not load the main window document for some reason.")
		return
	end
	Apollo.RegisterEventHandler("ChannelUpdate_Loot", "OnItemGained", self)
	Apollo.RegisterEventHandler("MatchEntered", "OnMatchEntered", self)
	Apollo.RegisterEventHandler("MatchFinished", "OnMatchFinished", self)
	Apollo.RegisterEventHandler("PlayerLevelChange", "OnPlayerLevelChange", self)
	Apollo.RegisterEventHandler("CharacterCreated", "OnCharacterCreated", self)

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
	self.wndContainerAvailable = self.wndMain:FindChild("EventContainerAvailable")
	self.wndContainerDone = self.wndMain:FindChild("EventContainerDone")

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

function EssenceEventTracker:OnPlayerLevelChange()
	self:Setup()
end

function EssenceEventTracker:OnCharacterCreated()
	self:Setup()
end

---------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------

function EssenceEventTracker:IsInterestingRotation(rot)
	-- rotation = { arRewards = {...}, bIsVeteran = true/false, nContentId = "number", nContentType = Daily/WB/Queues/... , strWorld = "LocalizedName" }
	-- rotation.arRewards = {monReward = userdata, nMultiplier=1/./nil, nRewardItemType=3/nil, nRewardType=1/2, nSecondsRemaining=0, strIcon = ""}
		--nRewardType = 1=Additive, 2=Multiplicative
		--nRewardItemType = 3=Violet, nil=uninteresting?
	return not(#rot.arRewards < 1 or #rot.arRewards <= 1 and rot.arRewards[1].nRewardType == ktRewardTypes.Multiplier and rot.arRewards[1].nMultiplier <= 1)
end

function EssenceEventTracker:BuildRotationTable( rot )
	local redo = false
	for _, reward in ipairs(rot.arRewards) do
		if reward.nRewardType == ktRewardTypes.Addition or reward.nRewardType == ktRewardTypes.Multiplier and reward.nMultiplier > 1 then
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

function EssenceEventTracker:UpdateAll()
	self.timerUpdateDelay:Stop()
	self.tRotations = {}
	self.tContentIds = {}

	for idx, nContentType in pairs(GameLib.CodeEnumRewardRotationContentType) do
		GameLib.RequestRewardUpdate(nContentType)
	end

	local redo = false --do we need to :UpdateAll() again, because nSecondsLeft <= 0

	local arRewardRotations = GameLib.GetRewardRotations()
	for _, rotation in ipairs(arRewardRotations or {}) do
		if self:IsInterestingRotation(rotation) then --filter all (only) 1x Multiplicators, aka. all thats 'default'
			if self:BuildRotationTable(rotation) then
				redo = true
			end
		end
	end

	local player = GameLib.GetPlayerUnit()
	if not player or GameLib.GetPlayerLevel(true)~=50 then
		self.bAllowShow = false
	else
		self.bAllowShow = true
	end
	
	if redo or not player or self.bAllowShow and #self.tRotations == 0 then
		self.updateTimer = self.updateTimer or ApolloTimer.Create(0, false, "UpdateAll", self)
		self.updateTimer:Start()
	else
		self.updateTimer = nil
	end

	self:RedrawAll()
end

function EssenceEventTracker:UpdateFeaturedList()
	if next(self:GetFeaturedEntries{}) ~= nil then
		self.addonMatchMaker:BuildFeaturedList()
	end
end

function EssenceEventTracker:RedrawAll()
	if not self.wndMain then return end
	local nStartingHeight = self.wndMain:GetHeight()
	local bStartingShown = self.wndMain:IsShown()

	local nAvailable, nDone = 0,0

	for i, rTbl in ipairs(self.tRotations) do
		nAvailable, nDone = self:DrawRotation(rTbl, nAvailable, nDone)
	end

	local tAvailableChildren = self.wndContainerAvailable:GetChildren()
	for i = nAvailable+1, #tAvailableChildren, 1 do
		tAvailableChildren[i]:Destroy()
	end

	local tDoneChildren = self.wndContainerDone:GetChildren()
	for i = nDone+1, #tDoneChildren, 1 do
		tDoneChildren[i]:Destroy()
	end

	local bShow = self.bAllowShow and self.bShow or false
	
	if bShow then
		if self.tMinimized.bRoot then
			self.wndContainerAvailable:Show(false)
			self.wndContainerDone:Show(false)

			local nLeft, nOffset, nRight = self.wndMain:GetAnchorOffsets() --current location
			local _, nTop, _, nBottom = self.wndMain:GetOriginalLocation():GetOffsets()
			self.wndMain:SetAnchorOffsets(nLeft, nOffset, nRight, nOffset + nBottom - nTop)
		else
			-- Resize quests
			local nAvailableHeight = self.wndContainerAvailable:ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop, function(wndA, wndB)
				return self.tCustomSortFunctions[self.eSort](self, wndA:GetData(), wndB:GetData())
			end)
			self.wndContainerAvailable:SetAnchorOffsets(0,0,0,nAvailableHeight)

			if self.tMinimized.bDoneRoot then
				self.wndContainerDone:SetAnchorOffsets(0,0,0,0)
			else
				local nDoneHeight = self.wndContainerDone:ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop, function(wndA, wndB)
					return self.tCustomSortFunctions[self.eSort](self, wndA:GetData(), wndB:GetData())
				end)
				self.wndContainerDone:SetAnchorOffsets(0,0,0,nDoneHeight)
			end

			self.wndContainerAvailable:Show(true)
			self.wndContainerDone:Show(true)

			local nHeight = self.wndMain:ArrangeChildrenVert()

			local nLeft, nTop, nRight, _ = self.wndMain:GetAnchorOffsets()
			self.wndMain:SetAnchorOffsets(nLeft, nTop, nRight, nTop+nHeight)
		end
	end
	self.wndMain:Show(bShow)
	self.wndMain:FindChild("HeadlineBtn:MinimizeBtn"):SetCheck(self.tMinimized.bRoot)
	self.wndMain:FindChild("DoneHeadline:DoneHeadlineBtn:MinimizeBtn"):SetCheck(self.tMinimized.bDoneRoot)

	if nStartingHeight ~= self.wndMain:GetHeight() or self.nAvailableCounting ~= nAvailable or self.nDoneCounting ~= nDone or bShow ~= bStartingShown then
		local tData =
		{
			["strAddon"] = lstrAddon,
			["strText"] = nAvailable,
			["bChecked"] = bShow,
		}
		Event_FireGenericEvent("ObjectiveTracker_UpdateAddOn", tData)
	end

	if bShow and not self.tMinimized.bRoot then
		self.timerRealTimeUpdate:Start()
	end

	self.nAvailableCounting = nAvailable
	self.nDoneCounting = nDone
end

function EssenceEventTracker:DrawRotation(rTbl, nAvailable, nDone)
	local bDone = self:IsDone(rTbl) and not self:IsAttended(rTbl)
	local wndContainer = bDone and self.wndContainerDone or self.wndContainerAvailable
	local idx = bDone and nDone+1 or nAvailable+1
	while not wndContainer:GetChildren()[idx] do
		Apollo.LoadForm(self.xmlDoc, "EssenceItem", wndContainer, self)
	end
	local wndForm = wndContainer:GetChildren()[idx]
	wndForm:FindChild("EssenceIcon"):SetSprite(rTbl.strIcon)
	wndForm:FindChild("EssenceIcon"):SetText(rTbl.strMult)
	if rTbl.tReward.nRewardType == ktRewardTypes.Addition then -- example: 400 Purple Essence
		wndForm:FindChild("EssenceIcon"):SetTooltip(rTbl.tReward.monReward:GetMoneyString())
	elseif rTbl.tReward.nRewardType == ktRewardTypes.Multiplier then --example: 4x Green Essence
		wndForm:FindChild("EssenceIcon"):SetTooltip(rTbl.tReward.nMultiplier.."x "..rTbl.tReward.monReward:GetTypeString())
	else --remove
		wndForm:FindChild("EssenceIcon"):SetTooltip("")
	end
	wndForm:FindChild("ControlBackerBtn:TimeText"):SetText(self:HelperTimeString(rTbl.fEndTime-GameLib.GetGameTime()))
	if self:IsAttended(rTbl) then
		wndForm:FindChild("ControlBackerBtn:TitleText"):SetText(self:HelperColorize(rTbl.strText, kstrColors.kstrYellow))
	else
		wndForm:FindChild("ControlBackerBtn:TitleText"):SetText(self:HelperColorizeIf(rTbl.strText, kstrColors.kstrRed, bDone))
	end
	wndForm:SetData(rTbl)

	--returns nAvailable, nDone (incremented accordingly)
	return (bDone and nAvailable or idx), (bDone and idx or nDone)
end

function EssenceEventTracker:RedrawTimers()
	local update = false
	for _, wndForm in ipairs(self.wndContainerAvailable:GetChildren()) do
		local rTbl = wndForm:GetData()
		local fTimeLeft = rTbl.fEndTime-GameLib.GetGameTime()
		wndForm:FindChild("ControlBackerBtn:TimeText"):SetText(self:HelperTimeString(fTimeLeft))
		if fTimeLeft < 0 then update = true end
	end
	for _, wndForm in ipairs(self.wndContainerDone:GetChildren()) do
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

	local instances = {
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

	function EssenceEventTracker:GetCurrentInstance()
		local zone = GameLib.GetCurrentZoneMap()
		if not zone then return nil, true end --return nil, bNoZone
		if not instances[zone.continentId] then return nil end

		if #instances[zone.continentId] > 0 then
			for _, instance in ipairs(instances[zone.continentId]) do
				if (not instance.parentZoneId or instance.parentZoneId==zone.parentZoneId) and (not instance.id or instance.id==zone.id) then
					return instance
				end
			end
		else
			local instance = instances[zone.continentId]
			if (not instance.parentZoneId or instance.parentZoneId==zone.parentZoneId) and (not instance.id or instance.id==zone.id) then
				return instance
			end
		end
		return nil
	end

	function EssenceEventTracker:OnMatchEntered() --no args
		Apollo.RegisterEventHandler("SubZoneChanged", "OnEnteredMatchZone", self)
	end

	function EssenceEventTracker:OnEnteredMatchZone() --OnSubZoneChanged
		Apollo.RemoveEventHandler("SubZoneChanged", self)

		local inst = self:GetCurrentInstance()
		if not inst then
			return self:ClearAttendings()
		end
		
		local tmp = self.tEventsAttending
		self.tEventsAttending = {}
		if tmp and next(tmp) then
			for cId, tEnd in pairs(tmp) do
				for rId, tDate in pairs(tEnd) do
					if tDate.nInstanceContentId == inst.nContentId then
						self.tEventsAttending[cId] = self.tEventsAttending[cId] or {}
						self.tEventsAttending[cId][rId] = tDate
					end
				end
			end
		end
		
		--check normal instances
		for nRewardType, rTbl in pairs(self.tContentIds[inst.nContentId] or {}) do
			if not self:IsDone(rTbl) and self:CheckVeteran(rTbl.src.bIsVeteran) then
				if nRewardType == ktRewardTypes.Multiplier then
					self:MarkAsDone(rTbl)
				end
				self:MarkAsAttended(rTbl, inst.nContentId)
			end
		end

		--check queues
		for nRewardType, rTbl in pairs(self.tContentIds[46] or {}) do --46 = Random Queue - usually normal dungeon with rewardType 1 (100 purples)
			if not self:IsDone(rTbl) and self:CheckVeteran(rTbl.src.bIsVeteran) and rTbl.src.eMatchType == inst.nContentType then
				if nRewardType == ktRewardTypes.Multiplier then --include this, even if it was not yet a thing
					self:MarkAsDone(rTbl)
				end
				self:MarkAsAttended(rTbl, inst.nContentId)
			end
		end
		
		self:UpdateAll()
		self:UpdateFeaturedList()
	end

	function EssenceEventTracker:OnMatchFinished()
		self.afterMatchFinishedTimer = ApolloTimer.Create(1, false, "AfterMatchFinished", self)
	end

	function EssenceEventTracker:AfterMatchFinished()
		self.afterMatchFinishedTimer = nil
		self:ClearAttendings()
	end

	function EssenceEventTracker:GainedEssence(tMoney)
		if GroupLib.InInstance() then--Expedition? Dungeon? (Queued Normal Dungeon?)
			local inst = self:GetCurrentInstance()
			if not inst then return end

			--we ARE in inst! Pass to other function, because we only wanna detect in this function
			self:EssenceInInstance(tMoney, inst.nContentId, inst.nBase)
			self:EssenceInQueue(tMoney, inst.nContentType, inst.nBase)
		end
	end

	local function closeEnough(approx, exact)
		if approx*1.05 > exact and approx*0.95 < exact then
			return true
		else
			return false
		end
	end


	function EssenceEventTracker:CheckVeteran(bVet)
		local tInstanceSettingsInfo = GameLib.GetInstanceSettings()
		if bVet then
			return tInstanceSettingsInfo.eWorldDifficulty == GroupLib.Difficulty.Veteran
		else
			return tInstanceSettingsInfo.eWorldDifficulty == GroupLib.Difficulty.Normal
		end
	end

	function EssenceEventTracker:EssenceInInstance(tMoney, nContentId, nBase)
		local nRewardType = validCurrencies[tMoney:GetAccountCurrencyType()]
		if nRewardType ~= ktRewardTypes.Addition then return end --all the multipliers are already done on attending.

		local rTbl = self.tContentIds[nContentId] and self.tContentIds[nContentId][nRewardType]
		if not rTbl or not self:CheckVeteran(rTbl.src.bIsVeteran) or not self:IsAttended(rTbl) then return end

		if tMoney:GetAccountCurrencyType() ~= rTbl.tReward.monReward:GetAccountCurrencyType() then return end

		local fSignature = AccountItemLib.GetPremiumTier() > 0 and 1.5 or 1
		local approx = rTbl.tReward.monReward:GetAmount() * fSignature

		if closeEnough(approx, tMoney:GetAmount()) then
			self:MarkAsDone(rTbl)
		end
	end

	function EssenceEventTracker:EssenceInQueue(tMoney, nContentType, nBase)
		local nRewardType = validCurrencies[tMoney:GetAccountCurrencyType()]
		if nRewardType ~= ktRewardTypes.Addition then return end --all the multipliers are already done on attending.

		local rTbl = self.tContentIds[46] and self.tContentIds[46][nRewardType] --46 = Random Queue - usually normal dungeon with rewardType 1 (100 purples)
		if not rTbl or rTbl.src.eMatchType ~= nContentType or not self:CheckVeteran(rTbl.src.bIsVeteran) or not self:IsAttended(rTbl) then return end

		if tMoney:GetAccountCurrencyType() ~= rTbl.tReward.monReward:GetAccountCurrencyType() then return end

		local fSignature = AccountItemLib.GetPremiumTier() > 0 and 1.5 or 1
		local approx = rTbl.tReward.monReward:GetAmount() * fSignature

		if closeEnough(approx, tMoney:GetAmount()) then
			self:MarkAsDone(rTbl)
		end
	end
end

function EssenceEventTracker:MarkAsDone(rTbl, bToggle)
	local cId, rId = rTbl.src.nContentId, rTbl.tReward.nRewardType

	if bToggle and self:IsDone(rTbl) then
		if self.tEventsDone[cId] then --should always be true, but... make sure.
			self.tEventsDone[cId][rId] = nil
			if not next(self.tEventsDone[cId]) then
				self.tEventsDone[cId] = nil
			end
		end
	else
		self.tEventsDone[cId] = self.tEventsDone[cId] or {}
		self.tEventsDone[cId][rId] = self:BuildDateTable(rTbl.fEndTime)
	end

	self:UpdateAll()
	self:UpdateFeaturedList()
end


function EssenceEventTracker:IsDone(rTbl)
	local tRewardEnds = self.tEventsDone[rTbl.src.nContentId]
	if not tRewardEnds then return false end

	local tEnd = tRewardEnds[rTbl.tReward.nRewardType]
	if not tEnd then return false end

	local fEnd = tEnd.nGameTime
	if not fEnd then return false end

	return math.abs(fEnd - rTbl.fEndTime) < 60
end

function EssenceEventTracker:ClearAttendings()
	self.tEventsAttending = {}
	self:UpdateAll()
	self:UpdateFeaturedList()
end

function EssenceEventTracker:MarkAsAttended(rTbl, nContentId)
	local cId, rId = rTbl.src.nContentId, rTbl.tReward.nRewardType

	self.tEventsAttending[cId] = self.tEventsAttending[cId] or {}
	self.tEventsAttending[cId][rId] = self:BuildDateTable(rTbl.fEndTime)

	self.tEventsAttending[cId][rId].nInstanceContentId = nContentId

	self:UpdateAll()
	self:UpdateFeaturedList()
end

function EssenceEventTracker:IsAttended(rTbl)
	local tAttendEndings = self.tEventsAttending[rTbl.src.nContentId]
	if not tAttendEndings then return false end

	local tEnd = tAttendEndings[rTbl.tReward.nRewardType]
	if not tEnd then return false end

	local fEnd = tEnd.nGameTime
	if not fEnd then return false end

	return math.abs(fEnd - rTbl.fEndTime) < 60
end

function EssenceEventTracker:CheckRestoredAttendingEvents()
	local inst, bFailed = self:GetCurrentInstance()
	if bFailed then
		self.checkRestoredAttendingEventsTimer = self.checkRestoredAttendingEventsTimer or ApolloTimer.Create(0.1, true, "CheckRestoredAttendingEvents", self)
		return
	else
		self.checkRestoredAttendingEventsTimer = self.checkRestoredAttendingEventsTimer and self.checkRestoredAttendingEventsTimer:Stop() and nil
		if not inst then
			return self:ClearAttendings()
		end
	end
	
	if not self.tEventsAttending or not next(self.tEventsAttending) then return end
	local temp,a,b = self.tEventsAttending,nil,nil --a,b just passthrough for AdjustDateTable
	self.tEventsAttending = {}
	for cId, tEnd in pairs(temp) do
		for rId, tDate in pairs(tEnd) do
			if tDate.nInstanceContentId == inst.nContentId then
				self.tEventsAttending[cId] = self.tEventsAttending[cId] or {}
				self.tEventsAttending[cId][rId],a,b = self:AdjustDateTable(tDate,a,b)
				self.tEventsAttending[cId][rId].nInstanceContentId = inst.nContentId
			end
		end
	end

	self:UpdateAll()
	self:UpdateFeaturedList()
end

---------------------------------------------------------------------------------------------------
-- Controls Events
---------------------------------------------------------------------------------------------------

function EssenceEventTracker:OnHeadlineBtnMouseEnter(wndHandler, wndControl)
	if wndHandler == wndControl then
		wndHandler:FindChild("MinimizeBtn"):Show(true)
	end
end

function EssenceEventTracker:OnHeadlineBtnMouseExit(wndHandler, wndControl)
	if wndHandler == wndControl then
		local wndBtn = wndHandler:FindChild("MinimizeBtn")
		wndBtn:Show(wndBtn:IsChecked())
	end
end

function EssenceEventTracker:OnHeadlineMinimizeBtnChecked(wndHandler, wndControl, eMouseButton)
	self.tMinimized.bRoot = true
	self:UpdateAll()
end

function EssenceEventTracker:OnHeadlineMinimizeBtnUnChecked(wndHandler, wndControl, eMouseButton)
	self.tMinimized.bRoot = false
	self:UpdateAll()
end

function EssenceEventTracker:OnDoneHeadlineBtnMouseEnter(wndHandler, wndControl)
	if wndHandler == wndControl then
		wndHandler:FindChild("MinimizeBtn"):Show(true)
	end
end

function EssenceEventTracker:OnDoneHeadlineBtnMouseExit(wndHandler, wndControl)
	if wndHandler == wndControl then
		wndHandler:FindChild("MinimizeBtn"):Show(false)
	end
end

function EssenceEventTracker:OnDoneHeadlineMinimizeBtnChecked(wndHandler, wndControl, eMouseButton)
	self.tMinimized.bDoneRoot = true
	self:UpdateAll()
end

function EssenceEventTracker:OnDoneHeadlineMinimizeBtnUnChecked(wndHandler, wndControl, eMouseButton)
	self.tMinimized.bDoneRoot = false
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
function EssenceEventTracker:HelperTimeString(fTime, strColorOverride)
	local fSeconds = fTime % 60
	local fMinutes = (fTime / 60)%60
	local fHours = (fTime / 3600)%24
	local fDays = (fTime / 86400)
	local strColor = kstrColors.kstrYellow
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

function EssenceEventTracker:HelperColorize(str, strColor)
	return string.format("<T TextColor=\"%s\">%s</T>", strColor, str)
end

function EssenceEventTracker:HelperColorizeIf(str, strColor, bIf)
	if bIf then
		return self:HelperColorize(str, strColor)
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
		return tTime, fNow, tNow
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
