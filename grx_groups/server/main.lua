if not lib then return end

lib.versionCheck('solareon/grx_groups')

if GetCurrentResourceName() ~= 'grx_groups' then
    lib.print.error('The resource needs to be named ^grx_groups^7.')
    return
end

local api = require 'server.api'

lib.callback.register('grx_groups:server:removeGroupMember', function(source, targetId)
    local groupId = api.GetGroupByMembers(source)
    if not groupId then
        return 'You are not in a group'
    end

    if not api.isGroupLeader(source, groupId) then
        return 'Only the leader can remove members'
    end

    if tonumber(targetId) == tonumber(source) then
        return 'You cannot remove yourself from here'
    end

    if api.RemovePlayerFromGroup(targetId, groupId) then
        return ('Removed %s from the group'):format(GetPlayerName(targetId) or ('Player ' .. tostring(targetId)))
    end

    return 'Error removing player'
end)

lib.callback.register('grx_groups:server:promoteGroupMember', function(source, targetId)
    local groupId = api.GetGroupByMembers(source)
    if not groupId then
        return 'You are not in a group'
    end

    if not api.isGroupLeader(source, groupId) then
        return 'Only the leader can promote members'
    end

    if api.ChangeGroupLeader(groupId, targetId) then
        return ('Promoted %s to leader'):format(GetPlayerName(targetId) or ('Player ' .. tostring(targetId)))
    end

    return 'Error promoting player'
end)

lib.callback.register('grx_groups:server:deleteGroup', function(source)
    local groupId = api.GetGroupByMembers(source)
    if not groupId then
        return 'You are not in a group'
    end

    if api.isGroupLeader(source, groupId) then
        api.DestroyGroup(groupId)
        return 'Group deleted'
    end

    if api.RemovePlayerFromGroup(source, groupId) then
        return 'Left group'
    end

    return 'Error leaving group'
end)

lib.callback.register('grx_groups:server:joinGroup', function(source, data)
    local groupId = data and data.id
    if not groupId then
        return 'Invalid group'
    end

    if api.GetGroupByMembers(source) then
        return 'You are already in a group'
    end

    local group = api.getGroupObjectById(groupId)
    if not group then
        return 'Group not found'
    end

    if group.isLocked and group.isLocked() then
        return 'Group is locked'
    end

    if not api.isPasswordCorrect(groupId, data.pass) then
        return 'Invalid password'
    end

    if not api.AddMember(groupId, source) then
        return 'Could not join group'
    end

    api.pNotifyGroup(groupId, 'Groups', ('%s has joined the group!'):format(GetPlayerName(source) or ('Player ' .. tostring(source))))
    return 'You joined the group'
end)

lib.callback.register('grx_groups:server:leaveGroup', function(source)
    local groupId = api.GetGroupByMembers(source)
    if not groupId then
        return 'You are not in a group'
    end

    if api.isGroupLeader(source, groupId) then
        api.DestroyGroup(groupId)
        return 'Group deleted'
    end

    if api.RemovePlayerFromGroup(source, groupId) then
        return 'Left group'
    end

    return 'Error leaving group'
end)

lib.callback.register('grx_groups:server:createGroup', function(source, data)
    data = data or {}

    local existing = api.GetGroupByMembers(source)
    if existing then
        return false, 'You are already in a group'
    end

    local groupId = api.CreateGroup(source, data.name, data.pass)
    if not groupId then
        return false, 'Could not create group'
    end

    return true, 'Group created'
end)

RegisterNetEvent('grx_groups:server:createGroup', function(data)
    data = data or {}

    local existing = api.GetGroupByMembers(source)
    if existing then
        lib.notify(source, {
            description = 'You are already in a group',
            type = 'error'
        })
        return
    end

    local groupId = api.CreateGroup(source, data.name, data.pass)
    if not groupId then
        lib.notify(source, {
            description = 'Could not create group',
            type = 'error'
        })
        return
    end
end)

lib.callback.register('grx_groups:server:getGroupMembers', function(source)
    local groupId = api.GetGroupByMembers(source)
    if groupId then
        return api.getGroupMembers(groupId)
    end
end)

lib.callback.register('grx_groups:server:getGroupMembersNames', function(source)
    local groupId = api.GetGroupByMembers(source)
    if groupId then
        local members = api.GetGroupMembersNames(groupId)
        return members, groupId
    end

    return {}, false
end)

lib.callback.register('grx_groups:server:getSetupAppData', function(source)
    local groupId = api.GetGroupByMembers(source)

    return {
        playerData = {
            source = source,
        },
        groups = api.GetAllGroups() or {},
        inGroup = groupId or false,
        groupId = groupId or false,
        groupData = groupId and api.GetGroupMembersNames(groupId) or {},
        groupMeta = groupId and api.GetPhoneGroupMeta(groupId) or nil,
        groupStages = groupId and api.GetGroupStages(groupId) or {},
        groupJobSteps = groupId and api.GetGroupStages(groupId) or {},
        groupStatus = groupId and api.getJobStatus(groupId) or false,
        pendingInvites = api.getPendingInvites(source) or {},
    }
end)

lib.callback.register('grx_groups:server:getGroupJobSteps', function(source)
    local groupId = api.GetGroupByMembers(source)
    if groupId then
        return api.GetGroupStages(groupId)
    end
    return {}
end)


lib.callback.register('grx_groups:server:toggleGroupsInviting', function(source)
    local ok, stateOrMessage = api.toggleGroupInviting(source)
    if ok then
        return true, stateOrMessage == true, stateOrMessage and 'Group inviting enabled' or 'Group inviting disabled'
    end

    return false, false, stateOrMessage
end)

lib.callback.register('grx_groups:server:setGroupLocked', function(source, lockedState)
    local groupId = api.GetGroupByMembers(source)
    if not groupId then
        return false, false, 'You are not in a group'
    end

    local ok, stateOrMessage = api.setGroupLocked(source, groupId, lockedState == true)
    if not ok then
        return false, false, stateOrMessage
    end

    return true, stateOrMessage == true, stateOrMessage and ('Group is now ' .. (stateOrMessage and 'locked' or 'unlocked')) or nil
end)

lib.callback.register('grx_groups:server:inviteToGroup', function(source, targetSrc)
    local ok, result = api.inviteToGroup(source, targetSrc)
    if not ok then
        return false, result
    end

    return true, ('Invite sent to %s'):format(GetPlayerName(tonumber(targetSrc)) or ('Player ' .. tostring(targetSrc)))
end)

lib.callback.register('grx_groups:server:acceptGroupInvite', function(source, inviteData)
    inviteData = inviteData or {}

    local ok, result = api.acceptGroupInvite(source, inviteData.inviteUuid, inviteData.inviterSrc)
    if not ok then
        return false, result
    end

    local leaderGroup = api.getGroupObjectFromMember(source)
    if leaderGroup then
        local leader = leaderGroup.getLeader()
        if leader and leader.src and leader.src ~= source then
            lib.notify(leader.src, {
                description = ('%s joined your group'):format(GetPlayerName(source) or ('Player ' .. tostring(source))),
                type = 'success'
            })
        end
    end

    return true, 'You joined the group'
end)

lib.callback.register('grx_groups:server:declineGroupInvite', function(source, inviteData)
    inviteData = inviteData or {}

    local ok, result = api.declineGroupInvite(source, inviteData.inviteUuid, inviteData.inviterSrc)
    if not ok then
        if result == 'Group no longer exists' or result == 'Invalid group invite' then
            return false, nil
        end
        return false, result
    end

    local leaderSrc = inviteData.inviterSrc and tonumber(inviteData.inviterSrc) or nil
    if leaderSrc and GetPlayerName(leaderSrc) then
        lib.notify(leaderSrc, {
            description = ('%s declined the group invite'):format(GetPlayerName(source) or ('Player ' .. tostring(source))),
            type = 'error'
        })
    end

    return true, 'Invite declined'
end)

RegisterNetEvent('grx_groups:server:toggleGroupsInviting', function()
    local ok, stateOrMessage = api.toggleGroupInviting(source)
    if not ok then
        lib.notify(source, {
            description = stateOrMessage,
            type = 'error'
        })
        return
    end

    lib.notify(source, {
        description = stateOrMessage and 'Group inviting enabled' or 'Group inviting disabled',
        type = 'success'
    })
end)

RegisterNetEvent('grx_groups:server:inviteToGroup', function(targetSrc)
    local ok, result = api.inviteToGroup(source, targetSrc)
    if not ok then
        lib.notify(source, {
            description = result,
            type = 'error'
        })
        return
    end

    lib.notify(source, {
        description = ('Invite sent to %s'):format(GetPlayerName(tonumber(targetSrc)) or ('Player ' .. tostring(targetSrc))),
        type = 'success'
    })
end)

RegisterNetEvent('grx_groups:server:acceptGroupInvite', function(inviteUuid, leaderSrc)
    local ok, result = api.acceptGroupInvite(source, inviteUuid, leaderSrc)
    if not ok then
        lib.notify(source, {
            description = result,
            type = 'error'
        })
        return
    end

    lib.notify(source, {
        description = 'You joined the group',
        type = 'success'
    })

    local leaderGroup = api.getGroupObjectFromMember(source)
    if leaderGroup then
        local leader = leaderGroup.getLeader()
        if leader and leader.src and leader.src ~= source then
            lib.notify(leader.src, {
                description = ('%s joined your group'):format(GetPlayerName(source) or ('Player ' .. tostring(source))),
                type = 'success'
            })
        end
    end
end)

RegisterNetEvent('grx_groups:server:declineGroupInvite', function(inviteUuid, leaderSrc)
    local ok, result = api.declineGroupInvite(source, inviteUuid, leaderSrc)
    if not ok then
        if result and result ~= 'Group no longer exists' and result ~= 'Invalid group invite' then
            lib.notify(source, {
                description = result,
                type = 'error'
            })
        end
        return
    end

    if leaderSrc and GetPlayerName(tonumber(leaderSrc)) then
        lib.notify(tonumber(leaderSrc), {
            description = ('%s declined the group invite'):format(GetPlayerName(source) or ('Player ' .. tostring(source))),
            type = 'error'
        })
    end
end)

-- PRP bridge compatibility aliases
RegisterNetEvent('prp-bridge:server:toggleGroupsInviting', function()
    local src = source
    local ok, stateOrMessage = api.toggleGroupInviting(src)
    if not ok then
        lib.notify(src, {
            description = stateOrMessage,
            type = 'error'
        })
        return
    end

    lib.notify(src, {
        description = stateOrMessage and 'Group inviting enabled' or 'Group inviting disabled',
        type = 'success'
    })
end)

RegisterNetEvent('prp-bridge:server:inviteToGroup', function(targetSrc)
    local src = source
    local ok, result = api.inviteToGroup(src, targetSrc)
    if not ok then
        lib.notify(src, {
            description = result,
            type = 'error'
        })
        return
    end

    lib.notify(src, {
        description = ('Invite sent to %s'):format(GetPlayerName(tonumber(targetSrc)) or ('Player ' .. tostring(targetSrc))),
        type = 'success'
    })
end)

RegisterNetEvent('prp-bridge:server:acceptGroupInvite', function(inviteUuid, leaderSrc)
    local src = source
    local ok, result = api.acceptGroupInvite(src, inviteUuid, leaderSrc)
    if not ok then
        lib.notify(src, {
            description = result,
            type = 'error'
        })
        return
    end

    lib.notify(src, {
        description = 'You joined the group',
        type = 'success'
    })
end)

RegisterNetEvent('prp-bridge:server:declineGroupInvite', function(inviteUuid, leaderSrc)
    api.declineGroupInvite(source, inviteUuid, leaderSrc)
    if leaderSrc and GetPlayerName(tonumber(leaderSrc)) then
        lib.notify(tonumber(leaderSrc), {
            description = ('%s declined the group invite'):format(GetPlayerName(source) or ('Player ' .. tostring(source))),
            type = 'error'
        })
    end
end)

AddEventHandler('playerDropped', function()
    api.unloadPlayer(source)
end)
