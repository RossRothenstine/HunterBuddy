local Huntify = LibStub("AceAddon-3.0"):NewAddon("Huntify", "AceConsole-3.0", "AceEvent-3.0")

--[[
    Modes that will determine the next ability to cast.
    In clip mode, auto shots are pushed down to cast Aimed Shot.
    In full mode, auto shots are prioritized.
]]
local FULL_MODE, CLIP_MODE = 0, 1
-- Time in seconds to cast Auto Shot
local AUTO_SHOT_CAST_TIME = 0.7001

local mode = FULL_MODE

local EVENT_TYPE_CAST_SUCCESS = "SPELL_CAST_SUCCESS"
local EVENT_TYPE_CAST_START = "SPELL_CAST_START"
local EVENT_TYPE_CAST_FAILED = "SPELL_CAST_FAILED"
local EVENT_TYPE_INTERRUPTED = "SPELL_INTERRUPTED"

local PUSHBACK_BASE = 1.0
local PUSHBACK_INCREMENT = 0.2

local settings = {
    ["width"] = 195,
    ["height"] = 13,
    ["cooldownRGBA"] = {1, 1, 1, 0.7},
    ["autoShotRGBA"] = {1, 0, 0, 0.7},
    ["alpha"] = 1.0,
};

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

local frame, text, bar

function Huntify:OnStartAutoRepeatSpell()
    state.shooting = true
end

function Huntify:OnStopAutoRepeatSpell()
    state.shooting = false
end

local function SpellIsAutoShot(spellID)
    return spellID == 75
end

function Huntify:OnUnitSpellCastSucceeded(event, unit, castGUID, spellID)
    if not UnitIsPlayer(unit) then return end
    if SpellIsAutoShot(spellID) then
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

function Huntify:OnInitialize()
end

local function PlayerIsMoving()
    return GetUnitSpeed("player") > 0
end

function Huntify:OnUpdate()
    Huntify:UpdateShotTime()
    Huntify:UpdateUI()
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
    Huntify:UpdateProgressBar()
    Huntify:UpdateLatency()
    Huntify:UpdateClip()
    Huntify:UpdateSpark()
    Huntify:UpdateMarker()
    Huntify:UpdateFlash()
    Huntify:UpdateIcon()
end

local function GetRangedSpeed()
    return UnitRangedDamage("player")
end

function Huntify:UpdateFlash()
    if state.left >= 0.3 then
        UI.frame.Flash:Hide()
    else
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
        sparkLocation = settings.width * coef
        UI.frame.Spark:SetPoint("CENTER", UI.frame, "LEFT", sparkLocation, UI.frame.Spark.offsetY or 2);
    else
        local elapsed = GetTime() - state.start
        duration = spell.castTime / (GetRangedHaste() or 1)
        coef = elapsed / duration
        sparkLocation = settings.width * coef
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

        local color = settings.cooldownRGBA
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
    return settings.width * ((speed - AUTO_SHOT_CAST_TIME) / speed)
end

function Huntify:UpdateLatency()
    local latency = UI.latency
    local speed = GetRangedSpeed()

    local right = (0.3 / speed) * settings.width

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
    local width = (0.9 / speed) * settings.width
    local left = (0.5 / speed) * settings.width

    clip:SetPoint("LEFT", UI.frame, "LEFT", GetShotMarkerLocation() - left, 2)
    clip:SetWidth(width)
end

function OnUpdate()
    Huntify:OnUpdate()
end

local function PlayerIsClass(cls)
    _, class, _ = UnitClass("player")
    return class == cls
end

function Huntify:OnEnable()
    self:Print("OnEnable()")

    if not PlayerIsClass("HUNTER") then return end

    self:RegisterEvent("START_AUTOREPEAT_SPELL", "OnStartAutoRepeatSpell")
    self:RegisterEvent("STOP_AUTOREPEAT_SPELL", "OnStopAutoRepeatSpell")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnUnitSpellCastSucceeded")
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCombatLogEventUnfiltered")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnUnitSpellCastFailed")

    if not UI.frame then
        local frame = CreateFrame("StatusBar", "HuntifyWeaponSwingTimer", UIParent, "CastingBarFrameTemplate")
        frame:SetWidth(settings.width)
        frame:SetHeight(settings.height)
        frame:SetPoint("CENTER", 0, 0)
        frame:SetScript("OnUpdate", OnUpdate)
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")

        local shotMarker = frame:CreateTexture(nil, "BACKGROUND")
        shotMarker:SetBlendMode("ADD")
        shotMarker:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        shotMarker:SetWidth(2)
        shotMarker:SetHeight(settings.height)
        shotMarker:SetVertexColor(1.0, 1.0, 1.0, 1.0)

        local latency = frame:CreateTexture(nil, "BACKGROUND")
        latency:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        latency:SetWidth(2)
        latency:SetHeight(settings.height)
        latency:SetVertexColor(0, 1.0, 0, 1.0)

        local clip = frame:CreateTexture(nil, "BACKGROUND")
        clip:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        clip:SetWidth(2)
        clip:SetHeight(settings.height)
        clip:SetVertexColor(1.0, 0, 0, 1.0)

        frame.Flash:SetVertexColor(1, 1, 1, 0.7)

        frame.Text:ClearAllPoints()
        frame.Text:SetPoint("CENTER", frame, "LEFT", 16, 2)
        frame.Flash:Hide()

        frame.Icon:SetHeight(2 * settings.height)
        frame.Icon:SetWidth(2 * settings.height)
        frame.Icon:SetTexture("Interface\\Icons\\Temp")

        UI.frame = frame
        UI.latency = latency
        UI.shotMarker = shotMarker
        UI.clip = clip
    end
end

function Huntify:OnDisable()
    self:Print("OnDisable()")
end
