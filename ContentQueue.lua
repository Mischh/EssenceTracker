require "Window"
require "GameLib"

local ContentQueue = {}

function ContentQueue:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
	
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
	end
end

function ContentQueue:OnRestore(eType, tSavedData)
	if eType == GameLib.CodeEnumAddonSaveLevel.Character then
	end
end

function ContentQueue:OnDocumentReady()
	if self.xmlDoc == nil or not self.xmlDoc:IsLoaded() then
		Apollo.AddAddonErrorText(self, "Could not load the main window document for some reason.")
		return
	end
	
end

---------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------



---------------------------------------------------------------------------------------------------
-- Game Events
---------------------------------------------------------------------------------------------------



---------------------------------------------------------------------------------------------------
-- Controls Events
---------------------------------------------------------------------------------------------------



---------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------



local ContentQueueInst = ContentQueue:new()
ContentQueueInst:Init()
