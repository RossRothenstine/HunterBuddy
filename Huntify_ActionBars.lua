local _, Huntify = ...
local HuntifyActionBars = Huntify:NewModule('ActionBars', 'AceEvent-3.0', 'AceConsole-3.0')

function HuntifyActionBars:OnEnable()
    -- self:RegisterEvent('ACTIONBAR_SLOT_CHANGED', 'OnActionBarSlotChanged')
    self:ScanActionBars()
end

function HuntifyActionBars:ScanActionBars()
    self.abilities = {
        ['Aimed Shot'] = {},
        ['Multi-Shot'] = {},
        ['Aspect of the Hawk'] = {},
        ['Trueshot Aura'] = {},
        ['Hunter\'s Mark'] =  {},
    }

    local bt4 = _G['Bartender4']

    local numSlots
    if bt4 then
        numSlots = 120
    else
        numSlots = 72
    end

    for slot = 1, numSlots do
        local spell = GetSpellFromSlot(slot)
        if self.abilities[spell] ~= nil then
            local btn = GetButtonForSlot(slot)
            if btn ~= nil then
                table.insert(self.abilities[spell], btn)
            end
        end
    end
end

function GetSpellFromSlot(slot)
    local actionType, id = GetActionInfo(slot)
    if actionType == 'macro' then
        local macroSpellID = GetMacroSpell(id)
        if macroSpellID then
            return select(1, GetSpellInfo(macroSpellID))
        end
    end
    if actionType == 'spell' then
        return select(1, GetSpellInfo(id))
    end
    return nil
end

function GetButtonForSlot(slot)
    local bt4 = _G['Bartender4']
    if bt4 then
        return _G['BT4Button' .. slot]
    end
    return BlizzardButtonForSlot(slot)
end

function BlizzardButtonForSlot(slot)
    local i
    if slot >= 1 and slot <= 12 then
        i = slot
        bar = 'Action'
    -- TODO support on page 2, maybe implement listeners for current page.
    elseif slot >= 13 and slot <= 24 then return nil
    --    i = slot - 12
    --    bar = 'Action'
    elseif slot >= 25 and slot <= 36 then
        i = slot - 24
        bar = 'MultiBarRight'
    elseif slot >= 37 and slot <= 48 then
        i = slot - 36
        bar = 'MultiBarLeft'
    elseif slot >= 49 and slot <= 60 then
        i = slot - 48
        bar = 'MultiBarBottomRight'
    elseif slot >= 61 and slot <= 72 then
        i = slot - 60
        bar = 'MultiBarBottomLeft'
    end
    return _G[bar .. 'Button' .. i]
end

function HuntifyActionBars:FlashSpell(spellName)
    if self.abilities[spellName] ~= nil then
        for _, btn in pairs(self.abilities[spellName]) do
            ActionButton_ShowOverlayGlow(btn)
        end
    end
end

function HuntifyActionBars:StopFlashSpell(spellName)
    if self.abilities[spellName] ~= nil then
        for _, btn in pairs(self.abilities[spellName]) do
            ActionButton_HideOverlayGlow(btn)
        end
    end
end

