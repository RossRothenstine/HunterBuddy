
local _, Huntify = ...
local HuntifyAuras = Huntify:NewModule('Auras', 'AceEvent-3.0', 'AceConsole-3.0')

local db
local defaults = {
    profile = {
        showTrueshot = true,
        showHuntersMark = true,
        showAspects = true,
    }
}

function HuntifyAuras:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("HuntifyAuraDB", defaults, true)
    db = self.db.profile

    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnPlayerRegenEnabled")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnPlayerRegenDisabled")

    local frame = CreateFrame("Frame", "HuntifyAurasFrame")
    frame:SetScript('OnUpdate', function()
        HuntifyAuras:OnUpdate()
    end)

    HuntifyAuras:SetUpInterfaceOptions()
end

function HuntifyAuras:OnUpdate()
    if db.showTrueshot and PlayerKnowsTrueshot() then
        if PlayerDoesNotHaveTrueshotActive() and PlayerIsAlive() then
            Huntify:GetModule('ActionBars'):FlashSpell('Trueshot Aura')
        else
            Huntify:GetModule('ActionBars'):StopFlashSpell('Trueshot Aura')
        end
    end
    if self:PlayerIsInCombat() then
        if db.showAspects and PlayerHasNoAspectsActive() then
            Huntify:GetModule('ActionBars'):FlashSpell('Aspect of the Hawk')
        else
            Huntify:GetModule('ActionBars'):StopFlashSpell('Aspect of the Hawk')
        end
        if db.showHuntersMark and TargetDoesNotHaveHuntersMark() then
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
            name == 'Aspect of the Wild' then
                return false
        end
    end
    return true
end

function PlayerKnowsTrueshot()
    return IsSpellKnown(19506)
end

function HuntifyAuras:SetUpInterfaceOptions()
    local opts = {
        type = 'group',
        args = {
            showAspects = {
                order = 1,
                type = "toggle",
                name = "Highlight Aspects",
                desc = "Highlight Aspect of the Hawk when engaged in combat without an aspect.",
                get = function()
                    return db.showAspects
                end,
                set = function(info, val)
                    db.showAspects = val
                    if not val then
                        Huntify:GetModule('ActionBars'):StopFlashSpell('Aspect of the Hawk')
                    end
                end
            },
            showHuntersMark = {
                order = 2,
                type = "toggle",
                name = "Highlight Hunter's Mark",
                desc = "Highlight Hunter's Mark when engaged in combat and Hunter's Mark isn't on the target.",
                get = function()
                    return db.showHuntersMark
                end,
                set = function(info, val)
                    db.showHuntersMark = val
                    if not val then
                        Huntify:GetModule('ActionBars'):StopFlashSpell('Hunter\'s Mark')
                    end
                end
            },
            showTrueshot = {
                order = 3,
                type = "toggle",
                name = "Highlight Trueshot Aura",
                desc = "Highlights Trueshot Aura if it is toggled off.",
                get = function()
                    return db.showTrueshot
                end,
                set = function(info, val)
                    db.showTrueshot = val
                    if not val then
                        Huntify:GetModule('ActionBars'):StopFlashSpell('Trueshot Aura')
                    end
                end
            },
        },
    }

    LibStub("AceConfig-3.0"):RegisterOptionsTable("HuntifyAuras", opts)
    blizOptionsPanel = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("HuntifyAuras", "Auras", "Huntify")
end