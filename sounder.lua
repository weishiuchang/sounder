local frame = CreateFrame("Frame", "SounderFrame", UIParent)

local savedSFXEnabled, savedSFXVolume, savedMasterVolume
local savedMusicEnabled, savedAmbientEnabled
local savedSoundEnabled

-- True from the moment sounds are modified for fishing until they have been
-- *verifiably* restored. Distinct from the savedXxx locals above, which hold
-- the actual pre-fishing values and must survive across failed restore
-- attempts (see restoreAudio/attemptRestore).
local soundsModified = false
local retryTicker

local RETRY_INTERVAL = 2

local defaults = {
    masterVolume   = 1.0,
    volume         = 1.0,
    spellIDs       = {131476},
    disableMusic   = true,
    disableAmbient = true,
}

local function DB()
    return SounderDB or defaults
end

local function spellMatches(spellID)
    for _, id in ipairs(DB().spellIDs) do
        if id == spellID then return true end
    end
    return false
end

local function parseSpellIDs(text)
    local ids = {}
    for part in text:gmatch("[^,]+") do
        local id = tonumber(part:match("^%s*(.-)%s*$"))
        if id and id > 0 then ids[#ids + 1] = id end
    end
    return ids
end

local function formatSpellIDs(ids)
    local parts = {}
    for _, id in ipairs(ids) do parts[#parts + 1] = tostring(id) end
    return table.concat(parts, ", ")
end

-- SetCVar gives no success/failure signal, and during combat lockdown it can
-- either throw (protected-function error) or silently no-op depending on the
-- CVar, so the only reliable way to know a write took effect is to read it
-- back afterwards.
local function trySetCVar(name, value)
    local ok = pcall(C_CVar.SetCVar, name, value)
    return ok and C_CVar.GetCVar(name) == value
end

-- Attempts to restore every group of saved CVars. Only clears a group's saved
-- values once that group is verified restored, so unrestored groups survive
-- to be retried later. Returns true only if everything was restored.
local function restoreAudio()
    local allRestored = true

    if savedSFXEnabled then
        local masterOk = trySetCVar("Sound_MasterVolume", savedMasterVolume)
        local sfxOk     = trySetCVar("Sound_EnableSFX",    savedSFXEnabled)
        local volOk     = trySetCVar("Sound_SFXVolume",    savedSFXVolume)
        if masterOk and sfxOk and volOk then
            savedMasterVolume = nil; savedSFXEnabled = nil; savedSFXVolume = nil
        else
            allRestored = false
        end
    end
    if savedSoundEnabled then
        if trySetCVar("Sound_EnableAllSound", savedSoundEnabled) then
            savedSoundEnabled = nil
        else
            allRestored = false
        end
    end
    if savedMusicEnabled then
        if trySetCVar("Sound_EnableMusic", savedMusicEnabled) then
            savedMusicEnabled = nil
        else
            allRestored = false
        end
    end
    if savedAmbientEnabled then
        if trySetCVar("Sound_EnableAmbience", savedAmbientEnabled) then
            savedAmbientEnabled = nil
        else
            allRestored = false
        end
    end

    return allRestored
end

-- Tries to restore now; if that fails (most commonly because combat lockdown
-- is blocking CVar writes), keeps retrying every RETRY_INTERVAL seconds until
-- it succeeds. A fishing restart cancels the retry (see
-- UNIT_SPELLCAST_CHANNEL_START below) rather than this function.
local function attemptRestore()
    if restoreAudio() then
        soundsModified = false
        if retryTicker then
            retryTicker:Cancel()
            retryTicker = nil
        end
    elseif not retryTicker then
        retryTicker = C_Timer.NewTicker(RETRY_INTERVAL, attemptRestore)
    end
end

frame:RegisterEvent("ADDON_LOADED")
-- Registered for the player only: fishing is always a player cast, and since
-- Midnight (12.0) spellIDs from other units' cast events can be "secret"
-- values that error when compared.  Player casts are never secret.
frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP",  "player")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if string.lower((...)) ~= "sounder" then return end

        SounderDB = SounderDB or {}
        if SounderDB.masterVolume   == nil then SounderDB.masterVolume   = defaults.masterVolume   end
        if SounderDB.volume         == nil then SounderDB.volume         = defaults.volume         end
        if SounderDB.spellIDs       == nil then SounderDB.spellIDs       = defaults.spellIDs       end
        if SounderDB.disableMusic   == nil then SounderDB.disableMusic   = defaults.disableMusic   end
        if SounderDB.disableAmbient == nil then SounderDB.disableAmbient = defaults.disableAmbient end
        SounderDB.alerts = nil  -- drop saved data from the removed alerts feature

        local function makeRow(parent, labelText, yOffset, width, numeric)
            local lbl = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            lbl:SetPoint("TOPLEFT", 16, yOffset)
            lbl:SetText(labelText)
            local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
            box:SetSize(width, 20)
            box:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
            box:SetAutoFocus(false)
            box:SetNumeric(numeric)
            return box
        end

        local function makeCheckbox(parent, labelText, yOffset)
            local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
            cb:SetPoint("TOPLEFT", 16, yOffset)
            local lbl = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            lbl:SetPoint("LEFT", cb, "RIGHT", 0, 0)
            lbl:SetText(labelText)
            return cb
        end

        -- A bare, unparented frame is required here: the Settings system owns
        -- parenting, sizing, and anchoring of registered panels.  Passing a
        -- parent (e.g. UIParent) or a template conflicts with that protected
        -- layout management and causes panels to render incorrectly or error.
        local panel = CreateFrame("Frame")

        local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("Sounder")

        local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", 16, -48)
        desc:SetPoint("TOPRIGHT", -16, -48)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(true)
        desc:SetText("Sounder watches for the fishing channel cast and adjusts sound settings so you can hear the bobber splash. Because Midnight no longer exposes splash events to addons, your chosen volume settings are applied while the cast is in progress (spell 131476 by default) and restored when it ends.")

        local hosted = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        hosted:SetPoint("BOTTOMLEFT", 16, 16)
        hosted:SetText("https://github.com/weishiuchang/sounder")

        local spellBox     = makeRow(panel, "Fishing Spell IDs (comma separated):",      -140, 300, false)
        local masterBox    = makeRow(panel, "Fishing Master Volume (0-100):",            -180,  60,  true)
        local volumeBox    = makeRow(panel, "Fishing SFX Volume (0-100):",               -220,  60,  true)
        local musicCheck   = makeCheckbox(panel, "Disable Music while fishing",          -260)
        local ambientCheck = makeCheckbox(panel, "Disable Ambient Sounds while fishing", -300)

        local function saveMasterVolume()
            local v = math.max(0, math.min(100, tonumber(masterBox:GetText()) or 100))
            DB().masterVolume = v / 100
            masterBox:SetText(tostring(v))
        end

        local function saveVolume()
            local v = math.max(0, math.min(100, tonumber(volumeBox:GetText()) or 100))
            DB().volume = v / 100
            volumeBox:SetText(tostring(v))
        end

        local function saveSpells()
            local ids = parseSpellIDs(spellBox:GetText())
            if #ids == 0 then ids = {131476} end
            DB().spellIDs = ids
            spellBox:SetText(formatSpellIDs(ids))
        end

        masterBox:SetScript("OnEnterPressed", function(self) saveMasterVolume(); self:ClearFocus() end)
        masterBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        masterBox:SetScript("OnEditFocusLost", function(self) self:ClearHighlightText(); saveMasterVolume() end)

        volumeBox:SetScript("OnEnterPressed", function(self) saveVolume(); self:ClearFocus() end)
        volumeBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        volumeBox:SetScript("OnEditFocusLost", function(self) self:ClearHighlightText(); saveVolume() end)

        spellBox:SetScript("OnEnterPressed", function(self) saveSpells(); self:ClearFocus() end)
        spellBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        spellBox:SetScript("OnEditFocusLost", function(self) self:ClearHighlightText(); saveSpells() end)

        musicCheck:SetScript("OnClick",   function(self) DB().disableMusic   = self:GetChecked() end)
        ambientCheck:SetScript("OnClick", function(self) DB().disableAmbient = self:GetChecked() end)

        panel:SetScript("OnShow", function()
            -- Deferred one frame: OnShow fires before the Settings system
            -- finishes reparenting and sizing the panel, so widget state set
            -- synchronously here can be silently discarded.  The next tick is
            -- after layout has settled and the widgets are fully interactive.
            C_Timer.After(0, function()
                spellBox:SetText(formatSpellIDs(DB().spellIDs))
                masterBox:SetText(tostring(math.floor(DB().masterVolume * 100 + 0.5)))
                volumeBox:SetText(tostring(math.floor(DB().volume * 100 + 0.5)))
                musicCheck:SetChecked(DB().disableMusic)
                ambientCheck:SetChecked(DB().disableAmbient)
            end)
        end)

        local category = Settings.RegisterCanvasLayoutCategory(panel, "Sounder")
        Settings.RegisterAddOnCategory(category)

    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local _, _, spellID = ...
        if not spellMatches(spellID) then
            -- not a fishing cast, nothing to do

        elseif soundsModified then
            -- Sounds are already modified, most likely because a previous
            -- restore attempt is still stuck retrying (e.g. we never left
            -- combat). Fishing again means we want the modified sounds for
            -- this cast too, so just cancel the pending retry and leave
            -- everything as-is; restore will be attempted fresh when this
            -- cast ends.
            if retryTicker then
                retryTicker:Cancel()
                retryTicker = nil
            end

        -- C_CVar.SetCVar for sound CVars is blocked during combat: the secure
        -- frame system protects them from tainted (addon) callers once combat
        -- starts.  Skip the volume boost entirely if already in combat.
        elseif not UnitAffectingCombat("player") then
            savedSoundEnabled = C_CVar.GetCVar("Sound_EnableAllSound")
            C_CVar.SetCVar("Sound_EnableAllSound", "1")
            savedMasterVolume = C_CVar.GetCVar("Sound_MasterVolume")
            savedSFXEnabled   = C_CVar.GetCVar("Sound_EnableSFX")
            savedSFXVolume    = C_CVar.GetCVar("Sound_SFXVolume")
            C_CVar.SetCVar("Sound_MasterVolume", tostring(DB().masterVolume))
            C_CVar.SetCVar("Sound_EnableSFX",    "1")
            C_CVar.SetCVar("Sound_SFXVolume",    tostring(DB().volume))
            if DB().disableMusic then
                savedMusicEnabled = C_CVar.GetCVar("Sound_EnableMusic")
                C_CVar.SetCVar("Sound_EnableMusic", "0")
            end
            if DB().disableAmbient then
                savedAmbientEnabled = C_CVar.GetCVar("Sound_EnableAmbience")
                C_CVar.SetCVar("Sound_EnableAmbience", "0")
            end
            soundsModified = true
        end

    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local _, _, spellID = ...
        if not spellMatches(spellID) then return end
        attemptRestore()

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Fires the moment the player enters combat.  C_CVar.SetCVar is
        -- protected once the combat lock is active, so try to restore audio
        -- here — before the lock takes effect — to avoid the changes being
        -- stuck for the duration of combat. If the lock has already engaged,
        -- attemptRestore falls back to retrying every RETRY_INTERVAL seconds.
        attemptRestore()

    end
end)
