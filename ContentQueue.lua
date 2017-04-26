require "Window"
local Apollo = require "Apollo"
local GameLib = require "GameLib"
local MatchMakingLib = require "MatchMakingLib"
local MatchingGameLib = require "MatchingGameLib"
local XmlDoc = require "XmlDoc"
local GroupLib = require "GroupLib"
local ApolloTimer = require "ApolloTimer"
local ChatSystemLib = require "ChatSystemLib"

--to initiate a queue: Event_FireGenericEvent("ContentQueueStart", nContentId, strTitle)
local ContentQueue = {}

local knSaveVersion = 1

local ktContent; do
	local dngNormal = MatchMakingLib.MatchType.Dungeon
	local dngPrime = MatchMakingLib.MatchType.PrimeLevelDungeon
	local expPrime = MatchMakingLib.MatchType.PrimeLevelExpedition
	local battleground = MatchMakingLib.MatchType.RatedBattleground

	ktContent = {
		[46] = { --Random Normal
			eMatchType = dngNormal,		bPrime = false,
		},
		[12] = { --"Stormtalon's Lair",
			eMatchType = dngPrime,		bPrime = true,
		},
		[13] = { --Skullcano
			eMatchType = dngPrime,		bPrime = true,
		},
		[14] = { --"Sanctuary of the Swordmaiden",
			eMatchType = dngPrime,		bPrime = true,
		},
		[15] = { --"Ruins of Kel Voreth"
			eMatchType = dngPrime,		bPrime = true,
		},
		[16] = { --"Ultimate Protogames",
			eMatchType = dngPrime,		bPrime = true,
		},
		[17] = { --"Academy",
			eMatchType = dngPrime,		bPrime = true,
		},
		[45] = { --"Citadel",
			eMatchType = dngPrime,		bPrime = true,
		},
		[18] = { --"Infestation",
			eMatchType = expPrime,		bPrime = true,
		},
		[19] = { --"Outpost M-13",
			eMatchType = expPrime,		bPrime = true,
		},
		[20] = { --"Rage Logic",
			eMatchType = expPrime,		bPrime = true,
		},
		[21] = { --"Space Madness",
			eMatchType = expPrime,		bPrime = true,
		},
		[22] = { --"Gauntlet",
			eMatchType = expPrime,		bPrime = true,
		},
		[23] = { --"Deepd Space Exploration",
			eMatchType = expPrime,		bPrime = true,
		},
		[24] = { --"Fragment Zero",
			eMatchType = expPrime,		bPrime = true,
		},
		[25] = { --"Ether",
			eMatchType = expPrime,		bPrime = true,
		},
		[38] = { --"Walatiki Temple"
			eMatchType = battleground,	bPrime = false,
		},
		[39] = { --"Halls of the Bloodsworn"
			eMatchType = battleground,	bPrime = false,
		},
		[40] = { --"Daggerstone Pass"
			eMatchType = battleground,	bPrime = false,
		},
	}
end

function ContentQueue:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

		o.tSavedQueueSettings = {}

    return o
end

function ContentQueue:Init()
	Apollo.GetAddon("MischhEssenceTracker").ContentQueue = self
  Apollo.RegisterAddon(self)
end

function ContentQueue:OnLoad()
	self.xmlDoc = XmlDoc.CreateFromFile("ContentQueue.xml")
	self.xmlDoc:RegisterCallback("OnDocumentReady", self)
end

function ContentQueue:OnSave(eType)
	if eType == GameLib.CodeEnumAddonSaveLevel.Character then
		return {
			_version = knSaveVersion,
			tSavedQueueSettings = self.tSavedQueueSettings,
		}
	end
end

function ContentQueue:OnRestore(eType, tSavedData)
	if eType == GameLib.CodeEnumAddonSaveLevel.Character then
		if tSavedData._version ~= knSaveVersion then return end
		self.tSavedQueueSettings = tSavedData.tSavedQueueSettings
	end
end

function ContentQueue:OnDocumentReady()
	if self.xmlDoc == nil or not self.xmlDoc:IsLoaded() then
		Apollo.AddAddonErrorText(self, "Could not load the main window document for some reason.")
		return
	end

	Apollo.RegisterEventHandler("ContentQueueStart", "OnSetupRequested", self)

	--Updates
	Apollo.RegisterEventHandler("Group_Join",							"OnUpdateGroup", self)
	Apollo.RegisterEventHandler("Group_Left",							"OnUpdateGroup", self)
	Apollo.RegisterEventHandler("Group_Add",							"OnUpdateGroup", self)
	Apollo.RegisterEventHandler("Group_Remove",							"OnUpdateGroup", self)
	Apollo.RegisterEventHandler("UnitLevelChanged",						"OnUnitLevelChanged", self)
	Apollo.RegisterEventHandler("MatchingJoinQueue", 					"OnJoinQueue", self)
	Apollo.RegisterEventHandler("MatchingLeaveQueue", 					"OnLeaveQueue", self)
end

---------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------

function ContentQueue:CreateNew(key, tMatch, tRoles, nPrime, strTitle)
	if self.wndMain and self.wndMain:IsValid() then
		self.wndMain:Destroy()
	end

	local tInfo = tMatch:GetInfo()
	local bPrime = tMatch:IsVeteran()
	local nInitialMax = GameLib.GetPrimeLevelAchieved(tInfo.nGameId)
	if nInitialMax>0 and GroupLib.AmILeader() then
		nInitialMax = GroupLib.GetPrimeLevelAchieved(tInfo.nGameId)
	end
	local bLockd = not bPrime or nInitialMax==0

	tRoles = tRoles or {}
	nPrime = math.min(nPrime or 0, nInitialMax)

	self.tRunningSettings = {
		key = key,
		strTitle = strTitle,
		tMatch = tMatch,
		tRoles = tRoles,
		nPrime = nPrime,
	}

	self.wndMain = Apollo.LoadForm(self.xmlDoc, "QueueConfirm", nil, self)
	self.wndDifficultyLabel = self.wndMain:FindChild("DifficultyLabel")
	self.wndGroupQueue = self.wndMain:FindChild("QueueButtons:GroupJoin")
	self.wndSoloQueue = self.wndMain:FindChild("QueueButtons:SoloQueue")

	self.wndMain:FindChild("Title"):SetText(strTitle or "<strTitle>")

	if bPrime then
		self.wndDifficultyLabel:SetText(String_GetWeaselString(Apollo.GetString("MatchMaker_Veteran"), tostring(nPrime)))
	else
		self.wndDifficultyLabel:SetText(Apollo.GetString("Storefront_VipNormal"))
	end
	if bLockd then
		self.wndDifficultyLabel:FindChild("LeftButton"):Destroy()
		self.wndDifficultyLabel:FindChild("RightButton"):Destroy()
	else
		self.wndPrimeLeft = self.wndDifficultyLabel:FindChild("LeftButton")
		self.wndPrimeRight = self.wndDifficultyLabel:FindChild("RightButton")
	end

	local wndRoleDPSBlock = self.wndMain:FindChild("RoleSelection:DPSBlock")
	local wndRoleDPS = self.wndMain:FindChild("RoleSelection:DPSBlock:DPS")
	local wndRoleHealerBlock = self.wndMain:FindChild("RoleSelection:HealerBlock")
	local wndRoleHealer = self.wndMain:FindChild("RoleSelection:HealerBlock:Healer")
	local wndRoleTankBlock = self.wndMain:FindChild("RoleSelection:TankBlock")
	local wndRoleTank = self.wndMain:FindChild("RoleSelection:TankBlock:Tank")

	self.tWndRoles = {
		[MatchMakingLib.Roles.DPS] = wndRoleDPS,
		[MatchMakingLib.Roles.Healer] = wndRoleHealer,
		[MatchMakingLib.Roles.Tank] = wndRoleTank,
	}

	local tValidRoles = {}
	for _, eRole in pairs(MatchMakingLib.GetEligibleRoles()) do
		tValidRoles[eRole] = true
	end

	wndRoleDPS:SetData(MatchMakingLib.Roles.DPS)
	if tValidRoles[MatchMakingLib.Roles.DPS] then
		wndRoleDPS:Enable(true)
	else
		wndRoleDPS:Enable(false)
		wndRoleDPS:SetTooltip(Apollo.GetString("MatchMaker_RoleClassReq"))
		wndRoleDPSBlock:FindChild("RoleIcon"):SetBGColor("UI_AlphaPercent30")
		wndRoleDPSBlock:FindChild("RoleLabel"):SetTextColor("UI_BtnTextGrayDisabled")
	end

	wndRoleTank:SetData(MatchMakingLib.Roles.Tank)
	if tValidRoles[MatchMakingLib.Roles.Tank] then
		wndRoleTank:Enable(true)
	else
		wndRoleTank:Enable(false)
		wndRoleTank:SetTooltip(Apollo.GetString("MatchMaker_RoleClassReq"))
		wndRoleTankBlock:FindChild("RoleIcon"):SetBGColor("UI_AlphaPercent30")
		wndRoleTankBlock:FindChild("RoleLabel"):SetTextColor("UI_BtnTextGrayDisabled")
	end

	wndRoleHealer:SetData(MatchMakingLib.Roles.Healer)
	if tValidRoles[MatchMakingLib.Roles.Healer] then
		wndRoleHealer:Enable(true)
	else
		wndRoleHealer:Enable(false)
		wndRoleHealer:SetTooltip(Apollo.GetString("MatchMaker_RoleClassReq"))
		wndRoleHealerBlock:FindChild("RoleIcon"):SetBGColor("UI_AlphaPercent30")
		wndRoleHealerBlock:FindChild("RoleLabel"):SetTextColor("UI_BtnTextGrayDisabled")
	end

	self:UpdateDisplay()
end

function ContentQueue:UpdateDisplay()
	if not self.wndMain or not self.tRunningSettings then return end

	local tRoles = self.tRunningSettings.tRoles
	local nPrime = self.tRunningSettings.nPrime
	local tInfo = self.tRunningSettings.tMatch:GetInfo()
	local bPrime = self.tRunningSettings.tMatch:IsVeteran()

	local nPrimeMax = GameLib.GetPrimeLevelAchieved(tInfo.nGameId)
	local bArrows = bPrime and nPrimeMax > 0

	if bArrows then
		self.wndDifficultyLabel:SetText(String_GetWeaselString(Apollo.GetString("MatchMaker_Veteran"), tostring(nPrime)))
		self.wndPrimeLeft:Enable(nPrime > 0)
		self.wndPrimeRight:Enable(nPrime < nPrimeMax)
	end

	for _, eRole in pairs(MatchMakingLib.GetEligibleRoles()) do
		self.tWndRoles[eRole]:SetCheck(tRoles[eRole] or false)
	end

	self:UpdateEnableQueueButtons()
end

function ContentQueue:UpdateEnableQueueButtons()
	if not self.wndMain then return end
	local tMatch = self.tRunningSettings.tMatch
	local tInfo = tMatch:GetInfo()
	local nPrime = self.tRunningSettings.nPrime

	local eSolo = tMatch:CanQueue()
	local eGroup = tMatch:CanQueueAsGroup()

	local bSolo = eSolo == MatchMakingLib.MatchQueueResult.Success
	local bGroup = eGroup == MatchMakingLib.MatchQueueResult.Success

	local strSoloTip = bSolo and "" or MatchMakingLib.GetMatchQueueResultString(eSolo)
	local strGroupTip = bGroup and "" or MatchMakingLib.GetMatchQueueResultString(eGroup)

	if GroupLib.InGroup() then
		local nGroupPrime = GroupLib.GetPrimeLevelAchieved(tInfo.nGameId)
		if not GroupLib.AmILeader() then
			bGroup = false
			strGroupTip = String_GetWeaselString(Apollo.GetString("GroupNoPermission"))
		elseif nGroupPrime < nPrime then
			bGroup = false
			local strFixedPattern = Apollo.GetString("MatchMaker_PrimeMaxLevel"):gsub("$%d([nc])", {n = "$1n", c = "$2c"})
			strGroupTip = String_GetWeaselString(strFixedPattern, self.tRunningSettings.strTitle, nGroupPrime)
		end
	end
	if MatchingGameLib.GetQueueEntry() and not MatchingGameLib.IsFinished() then
		bSolo = false
		bGroup = false
		strSoloTip = Apollo.GetString("MatchMaker_CantQueueInInstance")
		strGroupTip = Apollo.GetString("MatchMaker_CantQueueInInstance")
	end
	if tMatch:GetInfo().nTeamSize <= 1 and not tMatch:IsRandom() then
		bGroup = false
		--strGroupTip = "Cant Queue for this as group?"
	end
	if eSolo == MatchMakingLib.MatchQueueResult.NotInGroup then
		bSolo = false
		strSoloTip = MatchMakingLib.GetMatchQueueResultString(MatchMakingLib.MatchQueueResult.RequiresFullGroup)
	end
	if MatchMakingLib.IsQueuedAsGroupForMatching() then
		bSolo = false
		strSoloTip = Apollo.GetString("MatchMaker_CantSoloQueueWhileGrouped")
	end

	self.wndSoloQueue:Enable(bSolo)
	self.wndSoloQueue:SetTooltip(strSoloTip)
	self.wndGroupQueue:Enable(bGroup)
	self.wndGroupQueue:SetTooltip(strGroupTip)
end

function ContentQueue:ShowError(str)
	if not self.wndMain then return end
	self.wndMain:FindChild("WarningWindow:Label"):SetText(str)
	self.wndMain:FindChild("WarningWindow"):Show(true, true)

	if self.timerErrorDisplay then self.timerErrorDisplay:Stop() end
	self.timerErrorDisplay = ApolloTimer.Create(5, false, "OnErrorTimer", self)
end

function ContentQueue:OnErrorTimer()
	if not self.wndMain then return end
	if self.timerErrorDisplay then self.timerErrorDisplay:Stop() end
	self.timerErrorDisplay = nil

	self.wndMain:FindChild("WarningWindow"):Show(false, false)
end

function ContentQueue:SaveState()
	self.tSavedQueueSettings[self.tRunningSettings.key] = {
		tRoles = self.tRunningSettings.tRoles,
		nPrime = self.tRunningSettings.nPrime,
	}
end

function ContentQueue:SetupByContentId(nContentId, strTitle)
	if not ktContent[nContentId] then return end

	local tMatch = self:HelperFindMatch(nContentId)

	if not tMatch then return end

	local tSaves = self.tSavedQueueSettings[nContentId]
	if not tSaves then tSaves = {tRoles = {}, nPrime = 0} end

	self:CreateNew(nContentId, tMatch, tSaves.tRoles, tSaves.nPrime, strTitle)
end

---------------------------------------------------------------------------------------------------
-- Game Events
---------------------------------------------------------------------------------------------------

function ContentQueue:OnSetupRequested(nContentId, strTitle)
	assert(type(nContentId) == "number")
	assert(type(strTitle) == "string")

	self:SetupByContentId(nContentId, strTitle)
end

function ContentQueue:OnUpdateGroup()
	self:UpdateEnableQueueButtons()
end
function ContentQueue:OnUnitLevelChanged()
	self:UpdateEnableQueueButtons()
end
function ContentQueue:OnJoinQueue()
	self:UpdateEnableQueueButtons()
end
function ContentQueue:OnLeaveQueue()
	self:UpdateEnableQueueButtons()
end

---------------------------------------------------------------------------------------------------
-- Queue Success Check
---------------------------------------------------------------------------------------------------

function ContentQueue:StartQueueSuccessCheck()
	if self.timerQueueSuccess then
		self.timerQueueSuccess:Stop()
		self.timerQueueSuccess = nil
	end
	self.tRunningSettings.bSuccessCheck = true
	self.timerQueueSuccess = ApolloTimer.Create(0.5, false, "OnQueueSuccessTimer", self)
	Apollo.RegisterEventHandler("ChatMessage", "OnChatMessage", self)
end

function ContentQueue:OnChatMessage(tChatChannel, tMessage)
	if not tChatChannel or tChatChannel:GetType() ~= ChatSystemLib.ChatChannel_System then return end

	local strMessage = ""
	for _, tSegment in ipairs(tMessage.arMessageSegments) do
		strMessage = strMessage .. tSegment.strText
	end
	if strMessage ~= Apollo.GetString("MatchingFailure_UnableToQueue") then return end
	--we failed to queue -> inform the UI, stop the success-timer.
	Apollo.RemoveEventHandler("ChatMessage", self)
	self.timerQueueSuccess:Stop()
	self.timerQueueSuccess = nil
	self.tRunningSettings.bSuccessCheck = nil
	self:ShowError(strMessage)
end

function ContentQueue:OnQueueSuccessTimer()
	-- we see this as 'passing' scince no error occured in the specified timespan.
	Apollo.RemoveEventHandler("ChatMessage", self)
	self.tRunningSettings.bSuccessCheck = nil
	self.timerQueueSuccess = nil
	self:OnCancel()
end

---------------------------------------------------------------------------------------------------
-- Controls Events
---------------------------------------------------------------------------------------------------

function ContentQueue:OnGroupQueue()
	if self.tRunningSettings.bSuccessCheck then return end -- currently checking the success of another attempt.
	local tRoles = self.tRunningSettings.tRoles
	local options = {
		arRoles = {
			tRoles[MatchMakingLib.Roles.Tank] and MatchMakingLib.Roles.Tank or nil,
			tRoles[MatchMakingLib.Roles.Healer] and MatchMakingLib.Roles.Healer or nil,
			tRoles[MatchMakingLib.Roles.DPS] and MatchMakingLib.Roles.DPS or nil,
		},
		bFindOthers = true,
		bVeteran = self.tRunningSettings.tMatch:IsVeteran(),
		nPrimeLevel = self.tRunningSettings.nPrime,
	}
	local eResult = MatchMakingLib.QueueAsGroup({self.tRunningSettings.tMatch}, options)
	if eResult ~= MatchMakingLib.MatchQueueResult.Success then
		self:ShowError(MatchMakingLib.GetMatchQueueResultString(eResult))
	else
		self:SaveState()
		self:StartQueueSuccessCheck()
	end
end

function ContentQueue:OnSoloQueue()
	if self.tRunningSettings.bSuccessCheck then return end -- currently checking the success of another attempt.
	local tRoles = self.tRunningSettings.tRoles
	local options = {
		arRoles = {
			tRoles[MatchMakingLib.Roles.Tank] and MatchMakingLib.Roles.Tank or nil,
			tRoles[MatchMakingLib.Roles.Healer] and MatchMakingLib.Roles.Healer or nil,
			tRoles[MatchMakingLib.Roles.DPS] and MatchMakingLib.Roles.DPS or nil,
		},
		bFindOthers = true,
		bVeteran = self.tRunningSettings.tMatch:IsVeteran(),
		nPrimeLevel = self.tRunningSettings.nPrime,
	}
	local eResult = MatchMakingLib.Queue({self.tRunningSettings.tMatch}, options)
	if eResult ~= MatchMakingLib.MatchQueueResult.Success then
		self:ShowError(MatchMakingLib.GetMatchQueueResultString(eResult))
	else
		self:SaveState()
		self:StartQueueSuccessCheck()
	end
end

function ContentQueue:OnDecreasePrimeLevel()
	if not self.tRunningSettings then return end
	self.tRunningSettings.nPrime = math.max(0, self.tRunningSettings.nPrime-1)
	self:UpdateDisplay()
end

function ContentQueue:OnIncreasePrimeLevel()
	if not self.tRunningSettings then return end

	local tInfo = self.tRunningSettings.tMatch:GetInfo()
	local nPrimeMax = GameLib.GetPrimeLevelAchieved(tInfo.nGameId)

	self.tRunningSettings.nPrime = math.min(nPrimeMax, self.tRunningSettings.nPrime+1)
	self:UpdateDisplay()
end

function ContentQueue:OnToggleCombatRole(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end
	local eRole = wndHandler:GetData()
	local bSet = wndHandler:IsChecked()

	local tNewRoles = {}
	for role in pairs(self.tRunningSettings.tRoles) do
		if role ~= eRole then
			tNewRoles[role] = true
		end
	end

	if bSet then
		tNewRoles[eRole] = true
	end

	self.tRunningSettings.tRoles = tNewRoles
end

function ContentQueue:OnCancel()
	if self.wndMain then
		self.wndMain:Destroy()
		self.wndMain = nil
	end
end

---------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------

function ContentQueue:HelperFindMatch(nContentId)
	local tContent = ktContent[nContentId]
	if not tContent then return nil end

	if tContent.eMatchType == MatchMakingLib.MatchType.Dungeon then
		for i, tMatch in ipairs(MatchMakingLib.GetMatchMakingEntries(tContent.eMatchType, tContent.bPrime, true)) do
			if tMatch:IsRandom() then
				return tMatch
			end
		end
	elseif tContent.eMatchType == MatchMakingLib.MatchType.Battleground then
		for i, tMatch in ipairs(MatchMakingLib.GetMatchMakingEntries(tContent.eMatchType, tContent.bPrime, true)) do
			if tMatch:GetInfo().nRewardRotationContentId == nContentId then
				return tMatch
			end
		end
	else --PrimeLevelDungeon PrimeLevelExpedition
		for i, tMatch in ipairs(MatchMakingLib.GetMatchMakingEntries(tContent.eMatchType, tContent.bPrime, true)) do
			if tMatch:GetInfo().nRewardRotationContentId == nContentId then
				return tMatch
			end
		end
	end
	return nil
end

local ContentQueueInst = ContentQueue:new()
ContentQueueInst:Init()
