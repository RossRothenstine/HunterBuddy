local frame = CreateFrame("Frame", "HunterBuddyInterfaceOptionsParent", UIParent)
frame.name = "HunterBuddy"
InterfaceOptions_AddCategory(frame)

SLASH_HUNTERBUDDY1 = "/hb"
SlashCmdList["HUNTERBUDDY"] = function(msg)
    InterfaceOptionsFrame_OpenToCategory(frame)
    InterfaceOptionsFrame_OpenToCategory(frame)
end
