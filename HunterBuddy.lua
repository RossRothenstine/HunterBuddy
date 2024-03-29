local _, HunterBuddy = ...
local HunterBuddy = LibStub("AceAddon-3.0"):NewAddon(HunterBuddy, "HunterBuddy", "AceConsole-3.0", "AceEvent-3.0")

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
        castTime = 2.5,
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
    ["Steady Shot"] = {
        castTime = 1.5,
        icon = 132213,
    },
};

local pushbackEvents = {
	["SWING_DAMAGE"] = true,
	["ENVIRONMENTAL_DAMAGE"] = true,
	["RANGE_DAMAGE"] = true,
	["SPELL_DAMAGE"] = true
};

function HunterBuddy:OnStartAutoRepeatSpell()
    state.shooting = true
end

function HunterBuddy:OnStopAutoRepeatSpell()
    state.shooting = false
end

local function SpellIsAutoShot(spellID)
    return spellID == 75
end

local function SpellIsFeignDeath(spellID)
    return spellID == 5384
end

local function SpellIsAimedShot(spellID)
    return spellID == 27065
        or spellID == 20904
        or spellID == 20903
        or spellID == 20902
        or spellID == 20901
        or spellID == 20900
        or spellID == 19434
end

local function SpellIsSteadyShot(spellID)
    return spellID == 34120
end

function HunterBuddy:OnUnitSpellCastSucceeded(event, unit, castGUID, spellID)
    if not UnitIsPlayer(unit) then return end
    
    if SpellIsAutoShot(spellID) or SpellIsFeignDeath(spellID) or SpellIsAimedShot(spellID) then
        local duration = UnitRangedDamage("player")
        state.next = GetTime() + duration
    end
end

function HunterBuddy:OnUnitSpellCastFailed(event, unit, castGUID, spellID)
    if not UnitIsPlayer(unit) then return end
    state.spell = nil
end

local function GUIDIsPlayer(guid)
    return UnitGUID("player") == guid
end

function HunterBuddy:OnCombatLogEventUnfiltered()
    local eventType, srcGUID, dstGUID, spellName
    local values = {CombatLogGetCurrentEventInfo()}
    eventType = values[2]
    srcGUID = values[4]
    dstGUID = values[8]
    spellName = values[13]

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

function HunterBuddy:LockBar()
    UI.frame:SetMovable(false)
    UI.frame:EnableMouse(false)
    db.locked = true
end

function HunterBuddy:UnlockBar()
    UI.frame:SetMovable(true)
    UI.frame:EnableMouse(true)
    db.locked = false
end

function HunterBuddy:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("HunterBuddyDB", defaults, true)
    db = self.db.profile
end

local function PlayerIsMoving()
    return GetUnitSpeed("player") > 0
end

function HunterBuddy:OnUpdate()
    HunterBuddy:UpdateShotTime()
    HunterBuddy:UpdateUI()
    HunterBuddy:UpdateFlashingSpells()
end

function HunterBuddy:UpdateShotTime()
    local timeLeft
    if state.next == nil then
        timeLeft = AUTO_SHOT_CAST_TIME
    else
        timeLeft = state.next - GetTime()
    end

    if timeLeft < 0 then
        timeLeft = 0.000001
    end

    local spell = state.spell or spellbook["Auto Shot"]
    if spell ~= spellbook["Steady Shot"] then
        if spell == spellbook["Aimed Shot"] then
            -- Don't update state.next during cast.
            local duration = UnitRangedDamage("player")
            state.next = GetTime() + duration
        elseif (not state.shooting or PlayerIsMoving() or spell ~= spellbook["Auto Shot"]) and timeLeft <= AUTO_SHOT_CAST_TIME then
            state.next = GetTime() + AUTO_SHOT_CAST_TIME
            timeLeft = AUTO_SHOT_CAST_TIME
        end
    end

    state.left = timeLeft
end

function HunterBuddy:UpdateUI()
    HunterBuddy:UpdateAlpha()
    HunterBuddy:UpdateProgressBar()
    HunterBuddy:UpdateSpark()
    HunterBuddy:UpdateMarker()
    HunterBuddy:UpdateFlash()
    HunterBuddy:UpdateIcon()
		HunterBuddy:UpdateLatency()
		HunterBuddy:UpdateClip()
end

function HunterBuddy:UpdateAlpha()
    local nextAlpha
    if PlayerIsMoving() and (not state.inCombat) then
        nextAlpha = db.movingAlpha
    else
        nextAlpha = 1.0
    end
    UI.frame:SetAlpha(nextAlpha)
end

local function GetRangedSpeed()
    return select(1, UnitRangedDamage("player"))
end

function HunterBuddy:UpdateFlash()
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
    [6150] = 1.15,    -- Quick Shots/ Imp Aspect of the Hawk (Aimed)
    [3045] = 1.4,    -- Rapid Fire (Aimed)
    [28866] = 1.2,   -- Kiss of the Spider (Increases your _attack speed_ by 20% for 15 sec.) -- For Aimed
}

local function GetTrollBerserkHaste()
    local perc = UnitHealth("player") / UnitHealthMax("player")
    local speed = min((1.3 - perc) / 3, .3) + 1
    return speed
end

local function GetSerpentSwiftness()
    -- TODO minify
    local _, _, _, _, ranks, _, _, known = GetTalentInfo(1, 20)
    if known == 1 then
        return (1.0 + (ranks * 0.04))
    end
    return 1.0
end

local quivers = {
    ["Ancient Sinew Wrapped Lamina"] = 1.15,
}

local function GetQuiverHaste()
    for i=1,4,1 do
        if quivers[GetBagName(i)] ~= nil then
            return quivers[GetBagName(i)]
        end
    end
    return 1.0
end

local function GetRangedHaste()
    local positiveMul = 1.0
    for i=1, 100 do
        local name, _, _, _, _, _, _, _, _, spellID = UnitAura("player", i, "HELPFUL")
        if not name then break end
        if attackTimeDecreases[spellID] or spellID == 26635 then
            positiveMul = positiveMul * (attackTimeDecreases[spellID] or GetTrollBerserkHaste(unit))
        end
    end
    
    positiveMul = positiveMul * GetQuiverHaste()
    positiveMul = positiveMul * GetSerpentSwiftness()

    return positiveMul
end

function HunterBuddy:UpdateSpark()
    local spell = state.spell or spellbook["Auto Shot"]

    local duration, coef, sparkLocation

    if spell == spellbook["Auto Shot"] then
        duration = GetRangedSpeed()
        coef = (duration - state.left) / ((duration ~= 0) and duration or 1)
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

function HunterBuddy:UpdateProgressBar()
    local spell = state.spell or spellbook["Auto Shot"]

    if spell == spellbook["Auto Shot"] then
        local duration = GetRangedSpeed()
        UI.frame.Text:SetFormattedText("%.1f", state.left)
        UI.frame:SetMinMaxValues(-duration, 0)
        UI.frame:SetValue(-state.left)

        UI.shotMarker:Show()
        UI.latency:Show()
    else
        local elapsed = GetTime() - state.start
        local castTime = (spell.castTime / (GetRangedHaste() or 1))

        UI.frame.Text:SetFormattedText("%.1f", castTime - elapsed)
        UI.frame:SetMinMaxValues(0, castTime)
        UI.frame:SetValue(elapsed)

        UI.shotMarker:Hide()
        UI.clip:Hide()
        UI.latency:Hide()
    end

end

function HunterBuddy:UpdateIcon()
    local spell = state.spell or spellbook["Auto Shot"]
    UI.frame.Icon:SetTexture(spell.icon)
end

local function GetShotMarkerLocation()
    local speed = GetRangedSpeed()
    speed = (speed ~= 0) and speed or 1
    return db.width * ((speed - AUTO_SHOT_CAST_TIME) / speed)
end

function HunterBuddy:UpdateLatency()
    local latency = UI.latency
    local speed = GetRangedSpeed()

    local right = (0.3 / speed) * db.width

    latency:SetPoint("RIGHT", UI.frame, "RIGHT", 0, 2)
    latency:SetWidth(right)
end

function HunterBuddy:UpdateMarker()
    local shotMarker = UI.shotMarker

    shotMarker:SetPoint("CENTER", UI.frame, "LEFT", GetShotMarkerLocation(), 2)
end

function HunterBuddy:UpdateClip()
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
    HunterBuddy:OnUpdate()
end

local function PlayerIsClass(cls)
    _, class, _ = UnitClass("player")
    return class == cls
end

function HunterBuddy:OnPlayerRegenEnabled()
    state.inCombat = false
end

function HunterBuddy:OnPlayerRegenDisabled()
    state.inCombat = true
end

function HunterBuddy:OnEnable()
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
        local frame = CreateFrame("StatusBar", "HunterBuddyWeaponSwingTimer", UIParent, "CastingBarFrameTemplate")
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
            HunterBuddy:LockBar()
        else
            HunterBuddy:UnlockBar()
        end
    end
end

function HunterBuddy:OnDisable()
    self:Print("OnDisable()")
end

function HunterBuddy:UpdateFlashingSpells()
    if not db.highlightSpells then return end

    local reasonableAimedDelay = 0.7
    local ab = HunterBuddy:GetModule('ActionBars')
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

function HunterBuddy:SetUpInterfaceOptions()
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
                        HunterBuddy:LockBar()
                    else
                        HunterBuddy:UnlockBar()
                    end
                end
            }
        },
    }

    LibStub("AceConfig-3.0"):RegisterOptionsTable("HunterBuddyWST", opts)
    blizOptionsPanel = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("HunterBuddyWST", "Weapon Swing Timer", "HunterBuddy")
end
