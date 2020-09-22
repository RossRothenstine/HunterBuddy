local _, Huntify = ...
local Huntify = LibStub("AceAddon-3.0"):NewAddon(Huntify, "Huntify", "AceConsole-3.0", "AceEvent-3.0")

-- Time in seconds to cast Auto Shot
local AUTO_SHOT_CAST_TIME = 0.7001

local EVENT_TYPE_CAST_SUCCESS = "SPELL_CAST_SUCCESS"
local EVENT_TYPE_CAST_START = "SPELL_CAST_START"
local EVENT_TYPE_CAST_FAILED = "SPELL_CAST_FAILED"
local EVENT_TYPE_INTERRUPTED = "SPELL_INTERRUPTED"

local FULL_ROTATION = 'FULL_ROTATION'
local CLIPPED_ROTATION = 'CLIPPED_ROTATION'

local PUSHBACK_BASE = 1.0
local PUSHBACK_INCREMENT = 0.2

local db

local defaults = {
    profile = {
        width = 195,
        height = 13,
        cooldownRGBA = {1, 1, 1, 0.7},
        autoShotRGBA = {1, 0, 0, 0.7},
        alpha = 1.0,
        movingAlpha = 0.5,
        mode = FULL_ROTATION,
        highlightSpells = true,
    },
}

-- State keeps track of variables important for shot calculation
local state = {
    -- flag to keep track of if we are currently shooting or not.
    ["shooting"] = false,
    -- the start of our spell cast.
    ["start"] = nil,
    -- The next time an auto shot is available.
    ["next"] = nil,
    -- How much time in seconds until the next shot can be fired.
    ["left"] = nil,
    -- Spell that is currently being casted.
    ["spell"] = nil,
    -- While casting a spell, this keeps track of the pushback occured.
    -- Pushback starts off at 1 second base, decreasing by 0.2s to a minimum of 0.2.
    -- There is no cap to how many times you can be pushed back.
    ["pushback"] = nil,
    -- Player is in combat or not.
    ["inCombat"] = nil,
};

local UI = {
    -- Parent frame for all widgets.
    frame = nil,
    -- Latency indicator. Shows an area where it's safe to cast Aimed Shot and Multi Shot without clipping next
    -- Auto Shot
    latency = nil,
    -- Marker indicator to show where the next auto shot will be available at.
    shotMarker = nil,
    -- Zone indicating when casting an ability like Aimed Shot will clip the next auto shot.
    clip = nil,
};

local spellbook = {
    ["Aimed Shot"] = {
        castTime = 3.0,
        icon = 135130,
    },
    ["Multi-Shot"] = {
        castTime = 0.5,
        icon = 132330,
    },
    ["Auto Shot"] = {
        castTime = nil,
        icon = 135489,
    },
};

local pushbackEvents = {
	["SWING_DAMAGE"] = true,
	["ENVIRONMENTAL_DAMAGE"] = true,
	["RANGE_DAMAGE"] = true,
	["SPELL_DAMAGE"] = true
};

function Huntify:OnStartAutoRepeatSpell()
    state.shooting = true
end

function Huntify:OnStopAutoRepeatSpell()
    state.shooting = false
end

local function SpellIsAutoShot(spellID)
    return spellID == 75
end

local function SpellIsFeignDeath(spellID)
    return spellID == 5384
end

function Huntify:OnUnitSpellCastSucceeded(event, unit, castGUID, spellID)
    if not UnitIsPlayer(unit) then return end
    if SpellIsAutoShot(spellID) or SpellIsFeignDeath(spellID) then
        local duration = UnitRangedDamage("player")
        state.next = GetTime() + duration
    end
end

function Huntify:OnUnitSpellCastFailed(event, unit, castGUID, spellID)
    if not UnitIsPlayer(unit) then return end
    state.spell = nil
end

local function GUIDIsPlayer(guid)
    return UnitGUID("player") == guid
end

function Huntify:OnCombatLogEventUnfiltered()
    local timestamp, eventType, hideCaster,
    srcGUID, srcName, srcFlags, srcFlags2,
    dstGUID, dstName, dstFlags, dstFlags2,
    spellID, spellName, arg3, arg4, arg5 = CombatLogGetCurrentEventInfo()

    if pushbackEvents[eventType] and GUIDIsPlayer(dstGUID) and state.spell ~= nil then
        -- A very simple way to do pushback is to increment the time the cast started to be later.
        -- Of course we don't want future casts so we clamp to the current time
        state.start = math.min(GetTime(), state.start + state.pushback)
        state.pushback = math.max(state.pushback - PUSHBACK_INCREMENT, PUSHBACK_INCREMENT)
        return
    end

    if not GUIDIsPlayer(srcGUID) then return end

    if eventType == EVENT_TYPE_CAST_START then
        if state.spell == nil and spellbook[spellName] ~= nil then
            state.spell = spellbook[spellName]
            state.start = GetTime()
            state.pushback = 1.0
        end
    elseif eventType == EVENT_TYPE_CAST_SUCCESS
        or eventType == EVENT_TYPE_CAST_FAILED
        or eventType == EVENT_TYPE_INTERRUPTED then
        state.spell = nil
    end
end

function Huntify:LockBar()
    UI.frame:SetMovable(false)
    UI.frame:EnableMouse(false)
    db.locked = true
end

function Huntify:UnlockBar()
    UI.frame:SetMovable(true)
    UI.frame:EnableMouse(true)
    db.locked = false
end

function Huntify:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("HuntifyDB", defaults, true)
    db = self.db.profile
end

local function PlayerIsMoving()
    return GetUnitSpeed("player") > 0
end

function Huntify:OnUpdate()
    Huntify:UpdateShotTime()
    Huntify:UpdateUI()
    Huntify:UpdateFlashingSpells()
end

function Huntify:UpdateShotTime()
    local timeLeft
    if state.next == nil then
        timeLeft = AUTO_SHOT_CAST_TIME
    else
        timeLeft = state.next - GetTime()
    end

    if timeLeft < 0 then
        timeLeft = 0
    end

    local spell = state.spell or spellbook["Auto Shot"]
    if (not state.shooting or PlayerIsMoving() or spell ~= spellbook["Auto Shot"]) and timeLeft <= AUTO_SHOT_CAST_TIME then
        state.next = GetTime() + AUTO_SHOT_CAST_TIME
        timeLeft = AUTO_SHOT_CAST_TIME
    end

    state.left = timeLeft
end

function Huntify:UpdateUI()
    Huntify:UpdateAlpha()
    Huntify:UpdateProgressBar()
    Huntify:UpdateLatency()
    Huntify:UpdateClip()
    Huntify:UpdateSpark()
    Huntify:UpdateMarker()
    Huntify:UpdateFlash()
    Huntify:UpdateIcon()
end

function Huntify:UpdateAlpha()
    local nextAlpha
    if PlayerIsMoving() and (not state.inCombat) then
        nextAlpha = db.movingAlpha
    else
        nextAlpha = 1.0
    end
    UI.frame:SetAlpha(nextAlpha)
end

local function GetRangedSpeed()
    return UnitRangedDamage("player")
end

function Huntify:UpdateFlash()
    if state.inCombat and not state.shooting then
        UI.frame.Flash:SetVertexColor(1.0, 0.0, 0.0, 0.7)
        UI.frame.Flash:Show()
    elseif state.left >= 0.3 then
        UI.frame.Flash:Hide()
    else
        UI.frame.Flash:SetVertexColor(1.0, 1.0, 1.0, 1.0)
        UI.frame.Flash:Show()
    end
end

local attackTimeDecreases = {
    [6150] = 1.3,    -- Quick Shots/ Imp Aspect of the Hawk (Aimed)
    [3045] = 1.4,    -- Rapid Fire (Aimed)
    [28866] = 1.2,   -- Kiss of the Spider (Increases your _attack speed_ by 20% for 15 sec.) -- For Aimed
}

local function GetTrollBerserkHaste()
    local perc = UnitHealth("player") / UnitHealthMax("player")
    local speed = min((1.3 - perc) / 3, .3) + 1
    return speed
end

local function GetRangedHaste()
    local positiveMul = 1.0
    for i=1, 100 do
        local name, _, _, _, _, _, _, _, _, spellID = UnitAura("player", i, "HELPFUL")
        if not name then return positiveMul end
        if attackTimeDecreases[spellID] or spellID == 26635 then
            positiveMul = positiveMul * (attackTimeDecreases[spellID] or GetTrollBerserkHaste(unit))
        end
    end
    return positiveMul
end

function Huntify:UpdateSpark()
    local spell = state.spell or spellbook["Auto Shot"]

    local duration, coef, sparkLocation

    if spell == spellbook["Auto Shot"] then
        duration = GetRangedSpeed()
        coef = (duration - state.left) / duration
        sparkLocation = db.width * coef
        UI.frame.Spark:SetPoint("CENTER", UI.frame, "LEFT", sparkLocation, UI.frame.Spark.offsetY or 2);
    else
        local elapsed = GetTime() - state.start
        duration = spell.castTime / (GetRangedHaste() or 1)
        coef = elapsed / duration
        sparkLocation = db.width * coef
        UI.frame.Spark:SetPoint("CENTER", UI.frame, "LEFT", sparkLocation, UI.frame.Spark.offsetY or 2);
    end
end

function Huntify:UpdateProgressBar()
    local spell = state.spell or spellbook["Auto Shot"]

    if spell == spellbook["Auto Shot"] then
        local duration = GetRangedSpeed()
        UI.frame.Text:SetFormattedText("%.1f", state.left)
        UI.frame:SetMinMaxValues(-duration, 0)
        UI.frame:SetValue(-state.left)

        UI.shotMarker:Show()
        UI.clip:Show()
        UI.latency:Show()

        local color = db.cooldownRGBA
        -- UI.frame:SetStatusBarColor(unpack(color))
    else
        local elapsed = GetTime() - state.start
        local castTime = (spell.castTime / GetRangedHaste())

        UI.frame.Text:SetFormattedText("%.1f", castTime - elapsed)
        UI.frame:SetMinMaxValues(0, castTime)
        UI.frame:SetValue(elapsed)

        UI.shotMarker:Hide()
        UI.clip:Hide()
        UI.latency:Hide()
    end

end

function Huntify:UpdateIcon()
    local spell = state.spell or spellbook["Auto Shot"]
    UI.frame.Icon:SetTexture(spell.icon)
end

local function GetShotMarkerLocation()
    local speed = GetRangedSpeed()
    return db.width * ((speed - AUTO_SHOT_CAST_TIME) / speed)
end

function Huntify:UpdateLatency()
    local latency = UI.latency
    local speed = GetRangedSpeed()

    local right = (0.3 / speed) * db.width

    latency:SetPoint("RIGHT", UI.frame, "RIGHT", 0, 2)
    latency:SetWidth(right)
end

function Huntify:UpdateMarker()
    local shotMarker = UI.shotMarker

    shotMarker:SetPoint("CENTER", UI.frame, "LEFT", GetShotMarkerLocation(), 2)
end

function Huntify:UpdateClip()
    local clip = UI.clip
    local speed = GetRangedSpeed()
    local width = (0.9 / speed) * db.width
    local left = GetShotMarkerLocation() - ((0.5 / speed) * db.width)

    if left < 0 then
        width = width - math.abs(left)
        left = 0
    end

    clip:SetPoint("LEFT", UI.frame, "LEFT", left, 2)
    clip:SetWidth(width)
end

function OnUpdate()
    Huntify:OnUpdate()
end

local function PlayerIsClass(cls)
    _, class, _ = UnitClass("player")
    return class == cls
end

function Huntify:OnPlayerRegenEnabled()
    state.inCombat = false
end

function Huntify:OnPlayerRegenDisabled()
    state.inCombat = true
end

function Huntify:OnEnable()
    if not PlayerIsClass("HUNTER") then return end

    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnPlayerRegenEnabled")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnPlayerRegenDisabled")
    self:RegisterEvent("START_AUTOREPEAT_SPELL", "OnStartAutoRepeatSpell")
    self:RegisterEvent("STOP_AUTOREPEAT_SPELL", "OnStopAutoRepeatSpell")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnUnitSpellCastSucceeded")
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCombatLogEventUnfiltered")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnUnitSpellCastFailed")
    self:SetUpInterfaceOptions()

    if not UI.frame then
        local frame = CreateFrame("StatusBar", "HuntifyWeaponSwingTimer", UIParent, "CastingBarFrameTemplate")
        frame:SetWidth(db.width)
        frame:SetHeight(db.height)
        frame:SetScript("OnUpdate", OnUpdate)
        frame:SetScript("OnDragStart", function()
            frame:StartMoving()
        end)
        frame:SetScript("OnDragStop", function()
            db.x = frame:GetLeft()
            db.y = frame:GetBottom()
            frame:StopMovingOrSizing()
        end)
        frame:RegisterForDrag("LeftButton")

        if db.x ~= nil or db.y ~= nil then
            frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
        else
            frame:SetPoint("CENTER", 0, 0)
        end

        local shotMarker = frame:CreateTexture(nil, "BACKGROUND")
        shotMarker:SetBlendMode("ADD")
        shotMarker:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        shotMarker:SetWidth(2)
        shotMarker:SetHeight(db.height)
        shotMarker:SetVertexColor(1.0, 1.0, 1.0, 1.0)

        local latency = frame:CreateTexture(nil, "BACKGROUND")
        latency:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        latency:SetWidth(2)
        latency:SetHeight(db.height)
        latency:SetVertexColor(0, 1.0, 0, 1.0)

        local clip = frame:CreateTexture(nil, "BACKGROUND")
        clip:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        clip:SetWidth(2)
        clip:SetHeight(db.height)
        clip:SetVertexColor(1.0, 0, 0, 1.0)

        frame.Flash:SetVertexColor(1, 1, 1, 0.7)

        frame.Text:ClearAllPoints()
        frame.Text:SetPoint("CENTER", frame, "LEFT", 16, 2)
        frame.Flash:Hide()

        frame.Icon:SetHeight(2 * db.height)
        frame.Icon:SetWidth(2 * db.height)
        frame.Icon:SetTexture("Interface\\Icons\\Temp")

        UI.frame = frame
        UI.latency = latency
        UI.shotMarker = shotMarker
        UI.clip = clip

        if db.locked then
            Huntify:LockBar()
        else
            Huntify:UnlockBar()
        end
    end
end

function Huntify:OnDisable()
    self:Print("OnDisable()")
end

function Huntify:UpdateFlashingSpells()
    if not db.highlightSpells then return end

    local reasonableAimedDelay = 0.7
    local ab = Huntify:GetModule('ActionBars')
    local canAimed = false
    local canMulti = false

    if db.mode == FULL_ROTATION then
        if GetRangedSpeed() - state.left < reasonableAimedDelay or state.left <= 0.3 then
            canAimed = select(2, GetSpellCooldown('Aimed Shot')) == 0
        end
    else
        canAimed = select(2, GetSpellCooldown('Aimed Shot')) == 0
    end

    if (state.left > AUTO_SHOT_CAST_TIME and state.left - AUTO_SHOT_CAST_TIME > 0.5) or state.left <= 0.3 then
        canMulti = select(2, GetSpellCooldown('Multi-Shot')) == 0
    end

    if canAimed then
        ab:StopFlashSpell('Multi-Shot')
        ab:FlashSpell('Aimed Shot')
    else
        ab:StopFlashSpell('Aimed Shot')
        if canMulti then
            ab:FlashSpell('Multi-Shot')
        else
            ab:StopFlashSpell('Multi-Shot')
        end
    end
end

function Huntify:SetUpInterfaceOptions()
    local opts = {
        type = 'group',
        args = {
            mode = {
                order = 0,
                type = "select",
                name = "Rotation Selection",
                desc = "Sets your desired rotation type.",
                values = {FULL_ROTATION = "Full", CLIPPED_ROTATION = "Clipped"},
                get = function()
                    return db.mode
                end,
                set = function(info, val)
                    db.mode = val
                end
            },
            highlightSpells = {
                order = 1,
                type = "toggle",
                name = "Highlight Spells",
                desc = "Highlight the next spell to cast based on your rotation.",
                get = function()
                    return db.highlightSpells
                end,
                set = function(info, val)
                    db.highlightSpells = val
                end
            },
            lock = {
                order = 1,
                type = "toggle",
                name = "Lock Frame",
                desc = "Locks the frame",
                get = function()
                    return db.locked
                end,
                set = function(info, val)
                    if val then
                        Huntify:LockBar()
                    else
                        Huntify:UnlockBar()
                    end
                end
            }
        },
    }

    LibStub("AceConfig-3.0"):RegisterOptionsTable("HuntifyWST", opts)
    blizOptionsPanel = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("HuntifyWST", "Weapon Swing Timer", "Huntify")
end