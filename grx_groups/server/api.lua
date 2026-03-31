local utils = require 'server.utils'

local api = {}
local groups = {}                 ---@type table<string, table>
local orderedGroups = {}          ---@type string[]
local memberToGroupMap = {}       ---@type table<string, string>
local cachedPlayerIdentifiers = {}---@type table<string, string>
local pendingInvitesByTarget = {}  ---@type table<string, table<string, table>>
local inviteIndex = {}             ---@type table<string, {targetIdentifier: string, groupId: string}>
local inviteLifetimeSeconds = 300
local createdCount = 0

local qbCore
local esx

local function isQbox()
    return GetResourceState('qbx_core') == 'started'
end

local function isQb()
    return GetResourceState('qb-core') == 'started' and not isQbox()
end

local function isEsx()
    return GetResourceState('es_extended') == 'started'
end

local function getQBCore()
    if qbCore then return qbCore end
    if isQb() then
        qbCore = exports['qb-core']:GetCoreObject()
    end
    return qbCore
end

local function getESX()
    if esx then return esx end
    if isEsx() then
        esx = exports.es_extended:getSharedObject()
    end
    return esx
end

local function sourceExists(src)
    src = tonumber(src)
    if not src then return false end

    local ok, ping = pcall(GetPlayerPing, src)
    if ok and ping and ping >= 0 then
        local ids = GetPlayerIdentifiers(src)
        return ids and #ids > 0
    end

    return false
end

local function getFallbackIdentifier(src)
    src = tonumber(src)
    if not src then return nil end

    local license = GetPlayerIdentifierByType(src, 'license')
    if license and license ~= '' then
        return license
    end

    local ids = GetPlayerIdentifiers(src)
    return ids and ids[1] or nil
end

local function getPlayerIdentifier(src)
    src = tonumber(src)
    if not src then return nil end

    if isQbox() then
        local player = exports.qbx_core:GetPlayer(src)
        return player and player.PlayerData and player.PlayerData.citizenid or nil
    end

    if isQb() then
        local core = getQBCore()
        local player = core and core.Functions.GetPlayer(src)
        return player and player.PlayerData and player.PlayerData.citizenid or nil
    end

    if isEsx() then
        local ESX = getESX()
        local xPlayer = ESX and ESX.GetPlayerFromId(src)
        if not xPlayer then return getFallbackIdentifier(src) end
        if type(xPlayer.getIdentifier) == 'function' then
            return xPlayer.getIdentifier()
        end
        return xPlayer.identifier or getFallbackIdentifier(src)
    end

    if GetResourceState('ox_core') == 'started' then
        local ok, Ox = pcall(require, '@ox_core.lib.init')
        if ok and Ox then
            local player = Ox.GetPlayer(src)
            if player then
                return player.charId or player.stateId or getFallbackIdentifier(src)
            end
        end
    end

    if GetResourceState('ND_Core') == 'started' and NDCore and NDCore.getPlayer then
        local player = NDCore.getPlayer(src)
        if player then
            return player.charId or player.citizenid or player.identifier or getFallbackIdentifier(src)
        end
    end

    return getFallbackIdentifier(src)
end

local function getSourceFromIdentifier(identifier)
    if not identifier then return nil end

    if isQbox() then
        local player = exports.qbx_core:GetPlayerByCitizenId(identifier)
        return player and player.PlayerData and player.PlayerData.source or nil
    end

    if isQb() then
        local core = getQBCore()
        local player = core and core.Functions.GetPlayerByCitizenId(identifier)
        return player and player.PlayerData and player.PlayerData.source or nil
    end

    if isEsx() then
        local ESX = getESX()
        if ESX and type(ESX.GetPlayerFromIdentifier) == 'function' then
            local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
            if xPlayer then
                return xPlayer.source
            end
        end
    end

    local players = GetPlayers()
    for i = 1, #players do
        local src = tonumber(players[i])
        if getPlayerIdentifier(src) == identifier then
            return src
        end
    end

    return nil
end

local function getCharacterNameFromSource(src)
    src = tonumber(src)
    if not src then return nil end

    local ok, name = pcall(GetPlayerName, src)
    if ok and name and name ~= '' then
        return name
    end

    return ('Player %s'):format(src)
end

local function getCharacterNameFromIdentifier(identifier)
    local src = getSourceFromIdentifier(identifier)
    if not src then return nil end
    return getCharacterNameFromSource(src)
end

local function generateUUID()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return template:gsub('[xy]', function(c)
        local v = (c == 'x') and math.random(0, 15) or math.random(8, 11)
        return string.format('%x', v)
    end)
end

local function removeOrderedGroup(uuid)
    for i = 1, #orderedGroups do
        if orderedGroups[i] == uuid then
            table.remove(orderedGroups, i)
            return
        end
    end
end

local function getGroupByUuid(uuid)
    return uuid and groups[tostring(uuid)] or nil
end

local function removeInviteRecord(inviteUuid)
    local inviteKey = tostring(inviteUuid)
    local inviteData = inviteIndex[inviteKey]
    if not inviteData then return end

    local targetInvites = pendingInvitesByTarget[inviteData.targetIdentifier]
    if targetInvites then
        targetInvites[inviteKey] = nil
        if not next(targetInvites) then
            pendingInvitesByTarget[inviteData.targetIdentifier] = nil
        end
    end

    inviteIndex[inviteKey] = nil
end

local function addInviteRecord(groupId, inviteUuid, targetIdentifier, inviterName, inviterSrc, groupName)
    local inviteKey = tostring(inviteUuid)
    local targetKey = tostring(targetIdentifier)

    pendingInvitesByTarget[targetKey] = pendingInvitesByTarget[targetKey] or {}
    pendingInvitesByTarget[targetKey][inviteKey] = {
        inviteUuid = inviteKey,
        inviterName = inviterName,
        inviterSrc = tonumber(inviterSrc),
        groupId = tostring(groupId),
        groupName = tostring(groupName or 'Group'),
        createdAt = os.time(),
    }

    inviteIndex[inviteKey] = {
        targetIdentifier = targetKey,
        groupId = tostring(groupId),
    }
end

local function clearGroupInviteRecords(groupId)
    local targetRemovals = {}
    groupId = tostring(groupId)

    for inviteUuid, inviteData in pairs(inviteIndex) do
        if inviteData.groupId == groupId then
            local targetIdentifier = inviteData.targetIdentifier
            targetRemovals[#targetRemovals + 1] = { inviteUuid = inviteUuid, targetIdentifier = targetIdentifier }
        end
    end

    for i = 1, #targetRemovals do
        removeInviteRecord(targetRemovals[i].inviteUuid)
    end
end

local function getPendingInvitesForIdentifier(identifier)
    local targetKey = tostring(identifier)
    local invites = pendingInvitesByTarget[targetKey]
    if not invites then return {} end

    local now = os.time()
    local data = {}

    for inviteUuid, inviteData in pairs(invites) do
        if (now - (inviteData.createdAt or now)) > inviteLifetimeSeconds then
            removeInviteRecord(inviteUuid)
        else
            local group = getGroupByUuid(inviteData.groupId)
            if not group then
                removeInviteRecord(inviteUuid)
            else
                data[#data + 1] = {
                    inviteUuid = inviteData.inviteUuid,
                    inviterName = inviteData.inviterName,
                    inviterSrc = inviteData.inviterSrc,
                    groupId = inviteData.groupId,
                    groupName = inviteData.groupName,
                    createdAt = inviteData.createdAt,
                }
            end
        end
    end

    table.sort(data, function(a, b)
        return (a.createdAt or 0) > (b.createdAt or 0)
    end)

    return data
end

local refreshAllClients

local function initGroupObject(data)
    local public = {}
    local private = {
        uuid = tostring(data.uuid),
        name = tostring(data.name or ('Group ' .. tostring(createdCount))),
        password = data.password and tostring(data.password) or nil,
        createdByScript = data.createdByScript == true,
        members = {},
        leader = nil,
        activity = nil,
        isInviting = false,
        invites = {},
        partyUuid = nil,
        isLocked = false,
        status = 'WAITING',
        stages = {},
        displayIndex = data.displayIndex or createdCount,
    }

    public.getUuid = function()
        return private.uuid
    end

    public.getPartyUuid = function()
        return private.partyUuid
    end

    public.clearPartyUuid = function()
        private.partyUuid = nil
    end

    public.getName = function()
        return private.name
    end

    public.getPassword = function()
        return private.password
    end

    public.isTemp = function()
        return private.createdByScript
    end

    public.setLeader = function(srcOrIdentifier)
        local src = tonumber(srcOrIdentifier)
        local identifier = src and getPlayerIdentifier(src) or tostring(srcOrIdentifier)
        if not identifier then return false end

        local existingMember = private.members[identifier]
        if existingMember then
            private.leader = {
                identifier = identifier,
                src = existingMember.src,
                characterName = existingMember.characterName,
            }
            refreshAllClients()
            return true
        end

        local leaderSrc = src or getSourceFromIdentifier(identifier)
        local characterName = getCharacterNameFromIdentifier(identifier)
        if not leaderSrc or not characterName then return false end

        private.leader = {
            identifier = identifier,
            src = leaderSrc,
            characterName = characterName,
        }

        refreshAllClients()
        return true
    end

    public.getLeader = function()
        if not private.leader then return nil end

        local currentSrc = getSourceFromIdentifier(private.leader.identifier) or private.leader.src
        if currentSrc then
            private.leader.src = currentSrc
        end

        local currentName = getCharacterNameFromIdentifier(private.leader.identifier)
        if currentName then
            private.leader.characterName = currentName
        end

        return {
            identifier = private.leader.identifier,
            src = private.leader.src,
            characterName = private.leader.characterName,
        }
    end

    public.isSrcALeader = function(src)
        local leader = public.getLeader()
        if not leader then return false end
        local identifier = getPlayerIdentifier(src)
        return identifier and leader.identifier == identifier or false
    end

    public.addMember = function(src)
        src = tonumber(src)
        if not src or not sourceExists(src) then return false end

        local identifier = getPlayerIdentifier(src)
        if not identifier then return false end

        local existingGroupUuid = memberToGroupMap[identifier]
        if existingGroupUuid and existingGroupUuid ~= private.uuid then
            return false
        end

        local characterName = getCharacterNameFromSource(src)
        if not characterName then return false end

        private.members[identifier] = {
            identifier = identifier,
            src = src,
            characterName = characterName,
            online = true,
        }

        memberToGroupMap[identifier] = private.uuid
        cachedPlayerIdentifiers[tostring(src)] = identifier

        if not private.leader then
            private.leader = {
                identifier = identifier,
                src = src,
                characterName = characterName,
            }
        end

        TriggerEvent('grx_groups:server:groupMemberAdded', src, private.uuid)
        refreshAllClients()
        return true
    end

    public.removeMember = function(srcOrIdentifier)
        local src = tonumber(srcOrIdentifier)
        local identifier = src and (cachedPlayerIdentifiers[tostring(src)] or getPlayerIdentifier(src)) or tostring(srcOrIdentifier)
        if not identifier then return false end

        local member = private.members[identifier]
        if not member then return false end

        private.members[identifier] = nil
        memberToGroupMap[identifier] = nil
        if member.src then
            cachedPlayerIdentifiers[tostring(member.src)] = nil
        end

        if private.leader and private.leader.identifier == identifier then
            private.leader = nil
            for nextIdentifier, nextMember in pairs(private.members) do
                private.leader = {
                    identifier = nextIdentifier,
                    src = nextMember.src,
                    characterName = nextMember.characterName,
                }
                break
            end
        end

        TriggerEvent('grx_groups:server:groupMemberRemoved', member.src or src, private.uuid)

        local remaining = 0
        for _ in pairs(private.members) do
            remaining = remaining + 1
        end

        if remaining == 0 then
            public.disband()
            return true
        end

        refreshAllClients()
        return true
    end

    public.getMembers = function()
        local members = {}
        for identifier, memberData in pairs(private.members) do
            local currentSrc = getSourceFromIdentifier(identifier) or memberData.src
            if currentSrc then
                memberData.src = currentSrc
            end

            local currentName = getCharacterNameFromIdentifier(identifier)
            if currentName then
                memberData.characterName = currentName
            end

            members[identifier] = {
                identifier = identifier,
                src = memberData.src,
                characterName = memberData.characterName,
                isLeader = private.leader and private.leader.identifier == identifier or false,
                online = memberData.src and sourceExists(memberData.src) or false,
            }
        end
        return members
    end

    public.getMembersIdentifiers = function()
        local identifiers = {}
        for identifier in pairs(private.members) do
            identifiers[#identifiers + 1] = identifier
        end
        return identifiers
    end

    public.getMembersPlayerIds = function()
        local playerIds = {}
        for identifier, memberData in pairs(private.members) do
            local currentSrc = getSourceFromIdentifier(identifier) or memberData.src
            if currentSrc and sourceExists(currentSrc) then
                playerIds[#playerIds + 1] = currentSrc
            end
        end
        return playerIds
    end

    public.isSrcAMember = function(src)
        local identifier = getPlayerIdentifier(src)
        return identifier and private.members[identifier] ~= nil or false
    end

    public.getMembersCount = function()
        local count = 0
        for _ in pairs(private.members) do
            count = count + 1
        end
        return count
    end

    public.setActivity = function(activity)
        private.activity = activity
    end

    public.getActivity = function()
        return private.activity
    end

    public.clearActivity = function()
        private.activity = nil
    end

    public.setJobStatus = function(status, stages)
        private.status = status or 'WAITING'
        private.stages = stages or {}
        public.triggerEvent('grx_groups:client:updateGroupStage', private.status, private.stages)
        refreshAllClients()
    end

    public.getJobStatus = function()
        return private.status
    end

    public.getStages = function()
        return private.stages
    end

    public.resetJobStatus = function()
        private.status = 'WAITING'
        private.stages = {}
        public.triggerEvent('grx_groups:client:updateGroupStage', private.status, private.stages)
        refreshAllClients()
    end

    public.triggerEvent = function(eventName, ...)
        local payload = msgpack.pack_args(...)
        local len = payload:len()
        for _, memberData in pairs(public.getMembers()) do
            if memberData.src and sourceExists(memberData.src) then
                TriggerClientEventInternal(eventName, tonumber(memberData.src), payload, len)
            end
        end
    end

    public.isAnyoneOnline = function()
        for _, memberData in pairs(public.getMembers()) do
            if memberData.online then
                return true
            end
        end
        return false
    end

    public.disband = function()
        local playerIds = public.getMembersPlayerIds()
        for identifier, memberData in pairs(private.members) do
            memberToGroupMap[identifier] = nil
            if memberData.src then
                cachedPlayerIdentifiers[tostring(memberData.src)] = nil
            end
        end

        groups[private.uuid] = nil
        removeOrderedGroup(private.uuid)
        clearGroupInviteRecords(private.uuid)

        TriggerEvent('grx_groups:server:GroupDeleted', private.uuid, playerIds)
        TriggerEvent('grx_groups:server:groupDisbanded', private.uuid)

        private.members = {}
        private.leader = nil
        private.activity = nil

        refreshAllClients()
    end

    public.isInviting = function()
        return private.isInviting
    end

    public.toggleInviting = function()
        private.isInviting = not private.isInviting
        refreshAllClients()
    end

    public.addPendingInvite = function(inviteUuid, targetSrcOrIdentifier)
        local src = tonumber(targetSrcOrIdentifier)
        local identifier = src and getPlayerIdentifier(src) or tostring(targetSrcOrIdentifier)
        if not identifier then return false end
        private.invites[tostring(inviteUuid)] = tostring(identifier)
        return true
    end

    public.removePendingInvite = function(inviteUuid)
        private.invites[tostring(inviteUuid)] = nil
        removeInviteRecord(inviteUuid)
    end

    public.isPendingInviteValid = function(inviteUuid, targetSrcOrIdentifier)
        local storedTarget = private.invites[tostring(inviteUuid)]
        if not storedTarget then return false end
        local src = tonumber(targetSrcOrIdentifier)
        local identifier = src and getPlayerIdentifier(src) or tostring(targetSrcOrIdentifier)
        if not identifier then return false end
        return tostring(storedTarget) == tostring(identifier)
    end

    public.createUniqueueParty = function(_)
        return false
    end

    public.enterUniqueue = function(_)
        return {
            success = false,
            error = 'UniQueue is not available in this resource',
        }
    end

    public.setLocked = function(lockedState)
        if type(lockedState) ~= 'boolean' then return end
        if private.isLocked == lockedState then return end
        private.isLocked = lockedState
        refreshAllClients()
    end

    public.isLocked = function()
        return private.isLocked
    end

    public.getClientData = function()
        local leader = public.getLeader()
        return {
            id = private.uuid,
            name = private.name,
            memberCount = public.getMembersCount(),
            isInviting = private.isInviting,
            isLocked = private.isLocked,
            leader = leader and leader.characterName or nil,
        }
    end

    public.getPhoneMembers = function()
        local members = {}
        for _, memberData in pairs(public.getMembers()) do
            if memberData.src and sourceExists(memberData.src) then
                members[#members + 1] = {
                    name = memberData.characterName,
                    playerId = memberData.src,
                    isLeader = memberData.isLeader,
                }
            end
        end

        table.sort(members, function(a, b)
            if a.isLeader ~= b.isLeader then
                return a.isLeader
            end
            return a.name < b.name
        end)

        return members
    end

    public.getPhoneMeta = function()
        local leader = public.getLeader()

        return {
            id = private.uuid,
            name = private.name,
            memberCount = public.getMembersCount(),
            isInviting = private.isInviting,
            isLocked = private.isLocked,
            leader = leader and {
                identifier = leader.identifier,
                src = leader.src,
                name = leader.characterName,
            } or nil,
        }
    end

    groups[private.uuid] = public
    orderedGroups[#orderedGroups + 1] = private.uuid

    return public
end

refreshAllClients = function()
    if type(lib) ~= 'table' then return end
    lib.triggerClientEvent('grx_groups:client:refreshGroups', -1, api.GetAllGroups())
end

Groups = {}

function Groups.GetFromMember(src)
    local identifier = getPlayerIdentifier(src)
    if not identifier then return nil end

    local groupUuid = memberToGroupMap[identifier]
    if not groupUuid then return nil end

    return getGroupByUuid(groupUuid)
end

function Groups.GetFromMemberByIdentifier(identifier)
    local groupUuid = memberToGroupMap[tostring(identifier)]
    if not groupUuid then return nil end

    return getGroupByUuid(groupUuid)
end

function Groups.Create(leaderSrc, data)
    local currentGroup = Groups.GetFromMember(leaderSrc)
    if currentGroup then
        return {
            success = false,
            error = 'Already in a group',
        }
    end

    createdCount = createdCount + 1

    data = data or {}
    data.uuid = data.uuid or generateUUID()
    data.name = data.name or ('Group ' .. tostring(createdCount))
    data.displayIndex = createdCount

    local groupObject = initGroupObject(data)
    groupObject.addMember(leaderSrc)
    groupObject.setLeader(leaderSrc)

    return {
        success = true,
        group = groupObject,
    }
end

function Groups.GetGroupByPartyUuid(partyUuid)
    for _, uuid in ipairs(orderedGroups) do
        local group = groups[uuid]
        if group and group.getPartyUuid and group.getPartyUuid() == partyUuid then
            return group
        end
    end
    return nil
end

function api.findGroupById(id)
    return getGroupByUuid(id)
end

function api.NotifyGroup(groupId, msg, notifyType)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('NotifyGroup was sent an invalid groupId :' .. tostring(groupId))
    end

    local members = group.getMembersPlayerIds()
    for i = 1, #members do
        utils.notify(members[i], msg, notifyType)
    end
end
utils.exportHandler('NotifyGroup', api.NotifyGroup)

function api.pNotifyGroup(groupId, header, msg)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('pNotifyGroup was sent an invalid groupId :' .. tostring(groupId))
    end

    group.triggerEvent('grx_groups:client:CustomNotification', header or 'NO HEADER', msg or 'NO MSG')
end
utils.exportHandler('pNotifyGroup', api.pNotifyGroup)

function api.triggerGroupEvent(eventName, groupId, ...)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('triggerGroupEvent was sent an invalid groupId :' .. tostring(groupId))
    end

    group.triggerEvent(eventName, ...)
end
utils.exportHandler('triggerGroupEvent', api.triggerGroupEvent)

function api.CreateBlipForGroup(groupId, name, data)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('CreateBlipForGroup was sent an invalid groupId :' .. tostring(groupId))
    end

    group.triggerEvent('groups:createBlip', name, data)
end
utils.exportHandler('CreateBlipForGroup', api.CreateBlipForGroup)

function api.RemoveBlipForGroup(groupId, name)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('RemoveBlipForGroup was sent an invalid groupId :' .. tostring(groupId))
    end

    group.triggerEvent('groups:removeBlip', name)
end
utils.exportHandler('RemoveBlipForGroup', api.RemoveBlipForGroup)

function api.GetGroupByMembers(src)
    local group = Groups.GetFromMember(src)
    return group and group.getUuid() or nil
end
utils.exportHandler('GetGroupByMembers', api.GetGroupByMembers)

function api.getGroupMembers(groupId)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('getGroupMembers was sent an invalid groupId :' .. tostring(groupId))
    end

    return group.getMembersPlayerIds()
end
utils.exportHandler('getGroupMembers', api.getGroupMembers)

function api.getGroupSize(groupId)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('getGroupSize was sent an invalid groupId :' .. tostring(groupId))
    end

    return group.getMembersCount()
end
utils.exportHandler('getGroupSize', api.getGroupSize)

function api.GetGroupLeader(groupId)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('GetGroupLeader was sent an invalid groupId :' .. tostring(groupId))
    end

    local leader = group.getLeader()
    return leader and leader.src or nil
end
utils.exportHandler('GetGroupLeader', api.GetGroupLeader)

function api.DestroyGroup(groupId)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('DestroyGroup was sent an invalid groupId :' .. tostring(groupId))
    end

    local members = group.getMembersPlayerIds()
    local leaderSrc = api.GetGroupLeader(groupId)
    for i = 1, #members do
        if members[i] ~= leaderSrc then
            utils.notify(members[i], 'The group has been disbanded', 'error')
        end
    end

    group.disband()
end
utils.exportHandler('DestroyGroup', api.DestroyGroup)

function api.AddMember(groupId, source)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('AddMember was sent an invalid groupId :' .. tostring(groupId))
    end

    return group.addMember(source)
end
utils.exportHandler('AddMember', api.AddMember)

function api.isPasswordCorrect(groupId, password)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('isPasswordCorrect was sent an invalid groupId :' .. tostring(groupId))
    end

    local groupPassword = group.getPassword()
    if not groupPassword or groupPassword == '' then
        return true
    end

    return groupPassword == password
end

function api.isGroupLeader(src, groupId)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('isGroupLeader was sent an invalid groupId :' .. tostring(groupId))
    end

    return group.isSrcALeader(src)
end
utils.exportHandler('isGroupLeader', api.isGroupLeader)

function api.RemovePlayerFromGroup(source, groupId)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('RemovePlayerFromGroup was sent an invalid groupId :' .. tostring(groupId))
    end

    return group.removeMember(source)
end
utils.exportHandler('RemovePlayerFromGroup', api.RemovePlayerFromGroup)

function api.setJobStatus(groupId, status, stages)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('setJobStatus was sent an invalid groupId :' .. tostring(groupId))
    end

    group.setJobStatus(status, stages)
end
utils.exportHandler('setJobStatus', api.setJobStatus)

function api.getJobStatus(groupId)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('getJobStatus was sent an invalid groupId :' .. tostring(groupId))
    end

    return group.getJobStatus()
end
utils.exportHandler('getJobStatus', api.getJobStatus)

function api.resetJobStatus(groupId)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('resetJobStatus was sent an invalid groupId :' .. tostring(groupId))
    end

    group.resetJobStatus()
end
utils.exportHandler('resetJobStatus', api.resetJobStatus)

function api.GetGroupStages(groupId)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('GetGroupStages was sent an invalid groupId :' .. tostring(groupId))
    end

    return group.getStages()
end
utils.exportHandler('GetGroupStages', api.GetGroupStages)

function api.isGroupTemp(groupId)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('isGroupTemp was sent an invalid groupId :' .. tostring(groupId))
    end

    return group.isTemp()
end
utils.exportHandler('isGroupTemp', api.isGroupTemp)

function api.GetAllGroups()
    local data = {}
    for i = 1, #orderedGroups do
        local group = groups[orderedGroups[i]]
        if group then
            data[#data + 1] = group.getClientData()
        end
    end
    return data
end
utils.exportHandler('getAllGroups', api.GetAllGroups)

function api.GetGroupMembersNames(groupId)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('GetGroupMembersNames was sent an invalid groupId :' .. tostring(groupId))
    end

    return group.getPhoneMembers()
end
utils.exportHandler('GetGroupMembersNames', api.GetGroupMembersNames)

function api.GetPhoneGroupMeta(groupId)
    local group = getGroupByUuid(groupId)
    if not group then
        return nil
    end

    return group.getPhoneMeta and group.getPhoneMeta() or nil
end

function api.getPendingInvites(src)
    local identifier = getPlayerIdentifier(src)
    if not identifier then
        return {}
    end

    return getPendingInvitesForIdentifier(identifier)
end

function api.ChangeGroupLeader(groupId, targetId)
    local group = getGroupByUuid(groupId)
    if not group then
        return lib.print.error('ChangeGroupLeader was sent an invalid groupId :' .. tostring(groupId))
    end

    if targetId then
        if not group.isSrcAMember(targetId) then
            return false
        end
        return group.setLeader(targetId)
    end

    local members = group.getMembersPlayerIds()
    local leader = api.GetGroupLeader(groupId)
    for i = 1, #members do
        if members[i] ~= leader then
            return group.setLeader(members[i])
        end
    end

    return false
end
utils.exportHandler('ChangeGroupLeader', api.ChangeGroupLeader)


function api.setGroupLocked(src, groupId, lockedState)
    local group = getGroupByUuid(groupId)
    if not group then
        return false, 'Invalid group'
    end

    if src and not group.isSrcALeader(src) then
        return false, 'Only the leader can change group privacy'
    end

    group.setLocked(lockedState == true)
    return true, group.isLocked()
end
utils.exportHandler('SetGroupLocked', api.setGroupLocked)

function api.isGroupInviting(groupId)
    local group = getGroupByUuid(groupId)
    if not group then
        return false
    end

    return group.isInviting and group.isInviting() or false
end
utils.exportHandler('isGroupInviting', api.isGroupInviting)

function api.toggleGroupInviting(src, groupId)
    local group = groupId and getGroupByUuid(groupId) or Groups.GetFromMember(src)
    if not group then
        return false, 'You are not in a group'
    end

    if src and not group.isSrcALeader(src) then
        return false, 'Only the leader can toggle inviting'
    end

    group.toggleInviting()

    local leader = group.getLeader()
    if leader and leader.src and sourceExists(leader.src) then
        TriggerClientEvent('grx_groups:client:toggleGroupInviting', leader.src, group.isInviting())
    end

    return true, group.isInviting()
end
utils.exportHandler('ToggleGroupInviting', api.toggleGroupInviting)

function api.inviteToGroup(src, targetSrc)
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not sourceExists(targetSrc) then
        return false, 'Invalid target player'
    end

    local group = Groups.GetFromMember(src)
    if not group then
        return false, 'You are not in a group'
    end

    if not group.isInviting() then
        return false, 'Your group is not open for invites'
    end

    if not group.isSrcALeader(src) then
        return false, 'Only the leader can invite players'
    end

    local targetGroup = Groups.GetFromMember(targetSrc)
    if targetGroup then
        return false, 'That player is already in a group'
    end

    if tonumber(targetSrc) == tonumber(src) then
        return false, 'You cannot invite yourself'
    end

    local targetIdentifier = getPlayerIdentifier(targetSrc)
    if not targetIdentifier then
        return false, 'Invalid target player'
    end

    local inviteUuid = generateUUID()
    local inviter = group.getLeader()
    local inviterName = inviter and inviter.characterName or (GetPlayerName(src) or ('Player ' .. tostring(src)))

    if not group.addPendingInvite(inviteUuid, targetIdentifier) then
        return false, 'Failed to create invite'
    end

    addInviteRecord(group.getUuid(), inviteUuid, targetIdentifier, inviterName, src, group.getName and group.getName() or 'Group')

    TriggerClientEvent('grx_groups:client:receiveGroupInvite', targetSrc, {
        inviteUuid = inviteUuid,
        inviterName = inviterName,
        inviteSrc = src,
        groupId = group.getUuid(),
        groupName = group.getName and group.getName() or 'Group',
    })

    return true, inviteUuid
end
utils.exportHandler('InviteToGroup', api.inviteToGroup)

function api.acceptGroupInvite(src, inviteUuid, leaderSrc)
    if Groups.GetFromMember(src) then
        return false, 'You are already in a group'
    end

    local group = Groups.GetFromMember(leaderSrc)
    if not group then
        local inviteData = inviteIndex[tostring(inviteUuid)]
        group = inviteData and getGroupByUuid(inviteData.groupId) or nil
    end
    if not group then
        removeInviteRecord(inviteUuid)
        return false, 'Group no longer exists'
    end

    if not group.isPendingInviteValid(inviteUuid, src) then
        removeInviteRecord(inviteUuid)
        return false, 'Invalid group invite'
    end

    group.removePendingInvite(inviteUuid)

    if group.isLocked() then
        return false, 'Group is locked'
    end

    local leader = group.getLeader()
    if not leader or not leader.src or not sourceExists(leader.src) then
        return false, 'Group leader is no longer online'
    end

    local sourcePed = GetPlayerPed(src)
    local leaderPed = GetPlayerPed(leader.src)
    if sourcePed > 0 and leaderPed > 0 and DoesEntityExist(sourcePed) and DoesEntityExist(leaderPed) then
        local sourceCoords = GetEntityCoords(sourcePed)
        local leaderCoords = GetEntityCoords(leaderPed)
        local distance = #(sourceCoords - leaderCoords)
        if distance > 25.0 then
            return false, 'You are too far from the group leader to join'
        end
    end

    local result = group.addMember(src)
    if not result then
        return false, 'Failed to join the group'
    end

    return true, group.getUuid()
end
utils.exportHandler('AcceptGroupInvite', api.acceptGroupInvite)

function api.declineGroupInvite(src, inviteUuid, leaderSrc)
    local group = Groups.GetFromMember(leaderSrc)
    if not group then
        local inviteData = inviteIndex[tostring(inviteUuid)]
        group = inviteData and getGroupByUuid(inviteData.groupId) or nil
    end
    if not group then
        removeInviteRecord(inviteUuid)
        return false, 'Group no longer exists'
    end

    if not group.isPendingInviteValid(inviteUuid, src) then
        removeInviteRecord(inviteUuid)
        return false, 'Invalid group invite'
    end

    group.removePendingInvite(inviteUuid)
    return true
end
utils.exportHandler('DeclineGroupInvite', api.declineGroupInvite)

function api.CreateGroup(src, name, password)
    if (name == nil and password == nil) or type(name) == 'table' then
        local data = type(name) == 'table' and name or {}
        data.createdByScript = data.createdByScript ~= false
        return Groups.Create(src, data)
    end

    local result = Groups.Create(src, {
        name = name,
        password = password,
        createdByScript = true,
    })

    if not result.success or not result.group then
        return nil
    end

    return result.group.getUuid()
end
utils.exportHandler('CreateGroup', api.CreateGroup)

exports('GetGroupFromMember', function(src)
    return Groups.GetFromMember(src)
end)

exports('GetGroupFromMemberByIdentifier', function(identifier)
    return Groups.GetFromMemberByIdentifier(identifier)
end)

exports('GetGroupByUuid', function(uuid)
    return getGroupByUuid(uuid)
end)

exports('GetGroupByPartyUuid', function(partyUuid)
    return Groups.GetGroupByPartyUuid(partyUuid)
end)

exports('GetGroupIdFromMember', function(src)
    return api.GetGroupByMembers(src)
end)

exports('GetGroupIdFromMemberByIdentifier', function(identifier)
    local group = Groups.GetFromMemberByIdentifier(identifier)
    return group and group.getUuid() or nil
end)

exports('GetGroupPlayerIds', function(uuid)
    local group = getGroupByUuid(uuid)
    return group and group.getMembersPlayerIds() or nil
end)

exports('CreatePrpGroup', function(leaderSrc, data)
    return Groups.Create(leaderSrc, data or {})
end)

function api.getGroupObjectFromMember(src)
    return Groups.GetFromMember(src)
end

function api.getGroupObjectByIdentifier(identifier)
    return Groups.GetFromMemberByIdentifier(identifier)
end

function api.getGroupObjectById(groupId)
    return getGroupByUuid(groupId)
end

function api.unloadPlayer(src)
    src = tonumber(src)
    if not src then return end

    local cachedIdentifier = cachedPlayerIdentifiers[tostring(src)] or getPlayerIdentifier(src)
    if not cachedIdentifier then return end

    cachedPlayerIdentifiers[tostring(src)] = nil

    local group = Groups.GetFromMemberByIdentifier(cachedIdentifier)
    if not group then return end

    local groupId = group.getUuid()
    local wasLeader = group.isSrcALeader(src)
    group.removeMember(cachedIdentifier)

    if wasLeader then
        local updatedGroup = getGroupByUuid(groupId)
        if updatedGroup and updatedGroup.getMembersCount() == 0 then
            updatedGroup.disband()
        end
    end
end

return api
