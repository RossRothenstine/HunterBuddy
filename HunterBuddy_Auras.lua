
local _, HunterBuddy = ...
local HunterBuddyAuras = HunterBuddy:NewModule('Auras', 'AceEvent-3.0', 'AceConsole-3.0')

local db
local defaults = {
    profile = {
        showTrueshot = true,
        showHuntersMark = true,
        showAspects = true,
    }
}

function HunterBuddyAuras:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("HunterBuddyAuraDB", defaults, true)
    db = self.db.profile

    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnPlayerRegenEnabled")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnPlayerRegenDisabled")

    local frame = CreateFrame("Frame", "HunterBuddyAurasFrame")
    frame:SetScript('OnUpdate', function()
        HunterBuddyAuras:OnUpdate()
    end)

    HunterBuddyAuras:SetUpInterfaceOptions()
end

function HunterBuddyAuras:OnUpdate()
    local ab = HunterBuddy:GetModule('ActionBars')
    if db.showTrueshot and PlayerKnowsTrueshot() then
        if PlayerDoesNotHaveTrueshotActive() and PlayerIsAlive() then
            ab:FlashSpell('Trueshot Aura')
        else
            ab:StopFlashSpell('Trueshot Aura')
        end
    end
    if self:PlayerIsInCombat() then
        if db.showAspects and PlayerHasNoAspectsActive() then
            ab:FlashSpell('Aspect of the Hawk')
        else
            ab:StopFlashSpell('Aspect of the Hawk')
        end
        if db.showHuntersMark and TargetDoesNotHaveHuntersMark() then
            ab:FlashSpell('Hunter\'s Mark')
        else
            ab:StopFlashSpell('Hunter\'s Mark')
        end
    else
        ab:StopFlashSpell('Aspect of the Hawk')
        ab:StopFlashSpell('Hunter\'s Mark')
    end
end

function HunterBuddyAuras:OnPlayerRegenEnabled()
    self.playerInCombat = false
end

function HunterBuddyAuras:OnPlayerRegenDisabled()
    self.playerInCombat = true
end

function HunterBuddyAuras:PlayerIsInCombat()
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

function HunterBuddyAuras:SetUpInterfaceOptions()
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
                        HunterBuddy:GetModule('ActionBars'):StopFlashSpell('Aspect of the Hawk')
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
                        HunterBuddy:GetModule('ActionBars'):StopFlashSpell('Hunter\'s Mark')
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
                        HunterBuddy:GetModule('ActionBars'):StopFlashSpell('Trueshot Aura')
                    end
                end
            },
        },
    }

    LibStub("AceConfig-3.0"):RegisterOptionsTable("HunterBuddyAuras", opts)
    blizOptionsPanel = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("HunterBuddyAuras", "Auras", "HunterBuddy")
end
