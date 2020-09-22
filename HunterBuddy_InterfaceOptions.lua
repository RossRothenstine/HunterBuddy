local frame = CreateFrame("Frame", "HuntifyInterfaceOptionsParent", UIParent)
frame.name = "Huntify"
InterfaceOptions_AddCategory(frame)

SLASH_HUNTERBUDDY1 = "/hb"
SlashCmdList["HUNTERBUDDY"] = function(msg)
    InterfaceOptionsFrame_OpenToCategory(frame)
    InterfaceOptionsFrame_OpenToCategory(frame)
end