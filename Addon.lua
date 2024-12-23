-- Addon.lua
-- @Author : Dencer (tdaddon@163.com)
-- @Link   : https://dengsir.github.io
-- @Date   : 12/23/2024, 1:31:34 PM
--
local Addon = CreateFrame('Frame', nil, UIParent)

local DEV = false

local SAFE_TEAM = 5
local AURA_FILTER = 'HARMFUL'
local AURA_ID = 66013

if DEV then
    AURA_FILTER = 'HELPFUL'
    AURA_ID = 48932
end

local tremove = table.remove
local tinsert = table.insert
local print = print
local select = select

local GetRaidRosterInfo = GetRaidRosterInfo
local UnitExists = UnitExists
local UnitIsGroupAssistant = UnitIsGroupAssistant
local SwapRaidSubgroup = SwapRaidSubgroup
local SetRaidSubgroup = SetRaidSubgroup
local FindAura = AuraUtil.FindAura

function Addon:OnLoad()
    local Label = self:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    Label:SetText('自动刺骨工作中')
    Label:SetPoint('CENTER')

    self:Hide()
    self:SetPoint('CENTER')
    self:SetSize(200, 100)
    self:SetScript('OnEvent', self.OnEvent)
    self:SetScript('OnShow', self.OnShow)
    self:SetScript('OnHide', self.OnHide)

    self:RegisterEvent('GROUP_ROSTER_UPDATE')
    self:GROUP_ROSTER_UPDATE()
end

function Addon:GROUP_ROSTER_UPDATE()
    return self:SetShown(UnitIsGroupAssistant('player') or UnitIsGroupLeader('player'))
end

function Addon:OnShow()
    if self.timer then
        self.timer:Cancel()
    end

    self.timer = C_Timer.NewTicker(0.1, function()
        self:OnTimer()
    end)
end

function Addon:OnHide()
    if self.timer then
        self.timer:Cancel()
        self.timer = nil
    end
end

local function IdPredicate(search, _, _, _, _, _, _, _, _, _, _, _, spellId)
    return spellId == search
end

local function IsDraenei(i)
    return select(2, UnitRace('raid' .. i)) == 'Draenei'
end

local function Name(i)
    return UnitName('raid' .. i)
end

local function SubGroup(i)
    return select(3, GetRaidRosterInfo(i))
end

---@class PlayerInfo
---@field id number
---@field team number
---@field draenei boolean

function Addon:OnTimer()
    if InCombatLockdown() then
        return
    end
    local emptySlot = 5
    ---@type PlayerInfo[]
    local safePlayers = {}
    ---@type PlayerInfo[]
    local unsafePlayers = {}
    local safeTeam = SAFE_TEAM
    local draeneiTeams = {}

    for i = 1, 40 do
        local unit = 'raid' .. i
        if UnitExists(unit) then
            local subgroup = SubGroup(i)
            local draenei = IsDraenei(i)
            if subgroup == safeTeam then
                emptySlot = emptySlot - 1
                tinsert(safePlayers, {id = i, team = subgroup, draenei = draenei})
            end
            if subgroup < safeTeam then
                if FindAura(IdPredicate, unit, AURA_FILTER, AURA_ID) then
                    tinsert(unsafePlayers, {id = i, team = subgroup, draenei = draenei})
                elseif IsDraenei(i) then
                    draeneiTeams[subgroup] = (draeneiTeams[subgroup] or 0) + 1
                end
            end
        end
    end

    ---@param source PlayerInfo
    local function PickSafePlayer(source)
        if draeneiTeams[source.team] then
            -- 给有德莱尼的队伍优先非德莱尼
            for i, target in ipairs(safePlayers) do
                if not target.draenei then
                    return tremove(safePlayers, i)
                end
            end
        else
            -- 给没有德莱尼的队伍优先德莱尼
            for i, info in ipairs(safePlayers) do
                if info.draenei then
                    return tremove(safePlayers, i)
                end
            end
        end
        return tremove(safePlayers)
    end

    for _, source in pairs(unsafePlayers) do
        local target = PickSafePlayer(source)
        if target then
            print(format('Swap %s -> %s', Name(source.id), Name(target.id)))
            SwapRaidSubgroup(source.id, target.id)
        elseif emptySlot > 0 then
            print(format('Move %s to empty slot', Name(source.id)))
            emptySlot = emptySlot - 1
            SetRaidSubgroup(source.id, safeTeam)
        else
            print(format('No empty slot for %s', Name(source.id)))
        end
    end
end

function Addon:OnEvent(event, ...)
    return self[event](self, ...)
end

Addon:OnLoad()
