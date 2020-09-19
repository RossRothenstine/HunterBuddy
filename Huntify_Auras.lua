
local _, Huntify = ...
local HuntifyAuras = Huntify:NewModule('Auras', 'AceEvent-3.0', 'AceConsole-3.0')

function HuntifyAuras:OnInitialize()
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnPlayerRegenEnabled")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnPlayerRegenDisabled")

    local frame = CreateFrame("Frame", "HuntifyAurasFrame")
    frame:SetScript('OnUpdate', function()
        HuntifyAuras:OnUpdate()
    end)
end

function HuntifyAuras:OnUpdate()
    if PlayerKnowsTrueshot() then
        if PlayerDoesNotHaveTrueshotActive() and PlayerIsAlive() then
            Huntify:GetModule('ActionBars'):FlashSpell('Trueshot Aura')
        else
            Huntify:GetModule('ActionBars'):StopFlashSpell('Trueshot Aura')
        end
    end
    if self:PlayerIsInCombat() then
        if PlayerHasNoAspectsActive() then
            Huntify:GetModule('ActionBars'):FlashSpell('Aspect of the Hawk')
        else
            Huntify:GetModule('ActionBars'):StopFlashSpell('Aspect of the Hawk')
        end
        if TargetDoesNotHaveHuntersMark() then
            Huntify:GetModule('ActionBars'):FlashSpell('Hunter\'s Mark')
        else
            Huntify:GetModule('ActionBars'):StopFlashSpell('Hunter\'s Mark')
        end
    end
end

function HuntifyAuras:OnPlayerRegenEnabled()
    self.playerInCombat = false
end

function HuntifyAuras:OnPlayerRegenDisabled()
    self.playerInCombat = true
end

function HuntifyAuras:PlayerIsInCombat()
    return self.playerInCombat
end

function PlayerIsAlive()
    return not UnitIsDeadOrGhost('player')
end

function TargetDoesNotHaveHuntersMark()
    if UnitIsEnemy('player', 'target') then
        for i=1, 100 do
            local name = UnitAura("target", i, "HARMFUL")
            if not name then return true end
            if name == 'Hunter\'s Mark' then return false end
        end
    end
    return false
end


function PlayerDoesNotHaveTrueshotActive()
    for i=1, 100 do
        local name = UnitAura("player", i, "HELPFUL")
        if not name then return true end
        if name == 'Trueshot Aura' then return false end
    end
    return true
end

function PlayerHasNoAspectsActive()
    for i=1, 100 do
        local name = UnitAura("player", i, "HELPFUL")
        if not name then return true end
        if name == 'Aspect of the Hawk' or
            name == 'Aspect of the Monkey' or
            name == 'Aspect of the Cheetah' or
            name == 'Aspect of the Pack' or
            name == 'Aspect of the Beast' or
            name == 'Aspect of the Hawk' then
                return false
        end
    end
    return true
end

function PlayerKnowsTrueshot()
    return IsSpellKnown(19506)
end