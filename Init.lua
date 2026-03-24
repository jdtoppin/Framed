local addonName, Framed = ...

-- Version
Framed.version = "0.1.0-alpha"

-- oUF reference (populated after oUF loads via TOC order)
Framed.oUF = oUF

-- Addon namespace is globally accessible for debugging
_G["Framed"] = Framed

-- Event frame for addon lifecycle
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        Framed.Config:Initialize()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        Framed.EventBus:Fire("PLAYER_LOGIN")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-- Slash commands
SLASH_FRAMED1 = "/framed"
SLASH_FRAMED2 = "/fr"

SlashCmdList["FRAMED"] = function(msg)
    local cmd = msg:lower():trim()

    if cmd == "version" or cmd == "v" then
        print("|cff00ccff Framed|r v" .. Framed.version)
    elseif cmd == "config" then
        Framed.Config:PrintDebug()
    elseif cmd == "events" then
        Framed.EventBus:PrintDebug()
    else
        print("|cff00ccff Framed|r v" .. Framed.version .. " — Commands:")
        print("  /framed version — Show version")
        print("  /framed config — Print config debug info")
        print("  /framed events — Print registered events")
    end
end
