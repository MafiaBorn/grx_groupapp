local identifier = 'grx_groups'

local function sendCustomAppMessage(action, data)
    exports['lb-phone']:SendCustomAppMessage(identifier, {
        action = action,
        data = data,
    })
end

local function sendNotification(message, title)
    exports['lb-phone']:SendNotification({
        app = identifier,
        title = title or 'Groups',
        content = message,
    })
end

local function getNearbyPlayers(maxDistance)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local nearbyPlayers = {}

    for _, player in ipairs(GetActivePlayers()) do
        local targetPed = GetPlayerPed(player)
        if targetPed ~= playerPed then
            local targetCoords = GetEntityCoords(targetPed)
            local distance = #(playerCoords - targetCoords)
            if distance <= (maxDistance or 6.0) then
                nearbyPlayers[#nearbyPlayers + 1] = {
                    playerId = GetPlayerServerId(player),
                    name = GetPlayerName(player) or ('Player ' .. tostring(GetPlayerServerId(player))),
                    distance = distance,
                }
            end
        end
    end

    table.sort(nearbyPlayers, function(a, b)
        return a.distance < b.distance
    end)

    return nearbyPlayers
end

local function refreshAppState(openJobPage)
    local setupAppData = lib.callback.await('grx_groups:server:getSetupAppData', false)
    setupAppData = setupAppData or {}

    sendCustomAppMessage('setupApp', setupAppData)

    if openJobPage and setupAppData.groupStatus == 'IN_PROGRESS' then
        sendCustomAppMessage('startJob', {})
    end
end

CreateThread(function()
    while GetResourceState('lb-phone') ~= 'started' do
        Wait(500)
    end

    local function AddApp()
        local added, errorMessage = exports['lb-phone']:AddCustomApp({
            identifier = identifier,
            name = 'Groups',
            description = 'Group management and invites',
            developer = 'solareon',
            defaultApp = true,
            ui = GetCurrentResourceName() .. '/ui/dist/index.html',
            icon = 'https://cfx-nui-' .. GetCurrentResourceName() .. '/ui/dist/icon.svg',
            fixBlur = true,
            onUse = function()
                Wait(100)
                refreshAppState(true)
            end,
            images = {
                'https://cfx-nui-' .. GetCurrentResourceName() .. '/ui/dist/screenshot-light.png',
                'https://cfx-nui-' .. GetCurrentResourceName() .. '/ui/dist/screenshot-dark.png'
            },
        })

        if not added then
            print('Could not add app:', errorMessage)
        end
    end

    AddApp()

    AddEventHandler('onResourceStart', function(resource)
        if resource == 'lb-phone' or resource == GetCurrentResourceName() then
            AddApp()
        end
    end)
end)

RegisterNuiCallback('getPlayerData', function(_, cb)
    cb({ source = cache.serverId })
end)

RegisterNuiCallback('refreshApp', function(_, cb)
    refreshAppState(false)
    cb({ ok = true })
end)

RegisterNuiCallback('getNearbyPlayers', function(data, cb)
    cb({
        players = getNearbyPlayers(data and data.maxDistance or 6.0)
    })
end)

RegisterNuiCallback('getGroupJobSteps', function(_, cb)
    cb(lib.callback.await('grx_groups:server:getGroupJobSteps') or {})
end)

RegisterNuiCallback('createGroup', function(data, cb)
    data = data or {}

    local ok, message = lib.callback.await('grx_groups:server:createGroup', false, {
        name = data.name or data.groupName,
        pass = data.pass or data.password,
    })

    if ok then
        refreshAppState(false)
    end

    if message then
        sendNotification(message)
    end

    cb({ ok = ok == true, message = message })
end)

RegisterNuiCallback('joinGroup', function(data, cb)
    data = data or {}

    local message = lib.callback.await('grx_groups:server:joinGroup', false, {
        id = data.id or data.groupId,
        pass = data.pass or data.password,
    })

    refreshAppState(false)

    if message then
        sendNotification(message)
    end

    cb({ ok = true, message = message })
end)

RegisterNuiCallback('leaveGroup', function(_, cb)
    local message = lib.callback.await('grx_groups:server:leaveGroup')
    refreshAppState(false)
    if message then
        sendNotification(message)
    end
    cb({ ok = true, message = message })
end)

RegisterNuiCallback('deleteGroup', function(_, cb)
    local message = lib.callback.await('grx_groups:server:deleteGroup')
    refreshAppState(false)
    if message then
        sendNotification(message)
    end
    cb({ ok = true, message = message })
end)

RegisterNuiCallback('getMemberList', function(_, cb)
    cb(lib.callback.await('grx_groups:server:getGroupMembersNames') or {})
end)

RegisterNuiCallback('removeGroupMember', function(data, cb)
    local message = lib.callback.await('grx_groups:server:removeGroupMember', false, data and data.playerId or data)
    refreshAppState(false)
    if message then
        sendNotification(message)
    end
    cb({ ok = true, message = message })
end)

RegisterNuiCallback('promoteGroupMember', function(data, cb)
    local message = lib.callback.await('grx_groups:server:promoteGroupMember', false, data and data.playerId or data)
    refreshAppState(false)
    if message then
        sendNotification(message)
    end
    cb({ ok = true, message = message })
end)

RegisterNuiCallback('toggleGroupInviting', function(_, cb)
    local ok, state, message = lib.callback.await('grx_groups:server:toggleGroupsInviting', false)
    refreshAppState(false)
    if message then
        sendNotification(message)
    end
    cb({ ok = ok == true, inviting = state == true, message = message })
end)

RegisterNuiCallback('setGroupLocked', function(data, cb)
    local ok, state, message = lib.callback.await('grx_groups:server:setGroupLocked', false, data and data.locked == true)
    refreshAppState(false)
    if message then
        sendNotification(message)
    end
    cb({ ok = ok == true, locked = state == true, message = message })
end)

RegisterNuiCallback('inviteNearbyPlayer', function(data, cb)
    local targetSrc = data and tonumber(data.playerId)
    if not targetSrc then
        cb({ ok = false, message = 'Invalid player' })
        return
    end

    local ok, message = lib.callback.await('grx_groups:server:inviteToGroup', false, targetSrc)
    refreshAppState(false)
    if message then
        sendNotification(message)
    end
    cb({ ok = ok == true, message = message })
end)

RegisterNuiCallback('acceptGroupInvite', function(data, cb)
    local ok, message = lib.callback.await('grx_groups:server:acceptGroupInvite', false, data)
    refreshAppState(false)
    if message then
        sendNotification(message)
    end
    cb({ ok = ok == true, message = message })
end)

RegisterNuiCallback('declineGroupInvite', function(data, cb)
    local ok, message = lib.callback.await('grx_groups:server:declineGroupInvite', false, data)
    refreshAppState(false)
    if message then
        sendNotification(message)
    end
    cb({ ok = ok == true, message = message })
end)


RegisterNuiCallback('AnsweredNotify', function(data, cb)
    data = data or {}

    local pendingInvites = lib.callback.await('grx_groups:server:getSetupAppData', false)
    pendingInvites = pendingInvites and pendingInvites.pendingInvites or {}
    local latestInvite = pendingInvites and pendingInvites[1] or nil

    if latestInvite then
        if data.type == 'success' then
            lib.callback.await('grx_groups:server:acceptGroupInvite', false, {
                inviteUuid = latestInvite.inviteUuid,
                inviterSrc = latestInvite.inviterSrc,
            })
        else
            lib.callback.await('grx_groups:server:declineGroupInvite', false, {
                inviteUuid = latestInvite.inviteUuid,
                inviterSrc = latestInvite.inviterSrc,
            })
        end
        refreshAppState(false)
    end

    cb({ ok = true })
end)

RegisterNetEvent('grx_groups:client:refreshGroups', function(_)
    refreshAppState(false)
end)

RegisterNetEvent('grx_groups:client:updateGroupStage', function(_, stage)
    sendCustomAppMessage('setGroupJobSteps', stage)
end)

RegisterNetEvent('grx_groups:client:CustomNotification', function(header, msg)
    sendNotification(msg, header)
end)

RegisterNetEvent('grx_groups:client:toggleGroupInviting', function(invitingState)
    refreshAppState(false)
    sendNotification(invitingState and 'Group inviting enabled.' or 'Group inviting disabled.', 'Groups')
end)

RegisterNetEvent('prp-bridge:client:toggleGroupInviting', function(invitingState)
    TriggerEvent('grx_groups:client:toggleGroupInviting', invitingState)
end)

RegisterNetEvent('grx_groups:client:receiveGroupInvite', function(inviteData)
    refreshAppState(false)

    local inviterName = inviteData and inviteData.inviterName or 'Unknown'
    local groupName = inviteData and inviteData.groupName or 'a group'
    sendNotification(('%s invited you to join %s. Open Groups to respond.'):format(inviterName, groupName), 'Group Invite')
end)

RegisterNetEvent('prp-bridge:client:receiveGroupInvite', function(inviteData)
    TriggerEvent('grx_groups:client:receiveGroupInvite', inviteData)
end)
