(function () {
  const RESOURCE_NAME = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'grx_groups';
  const state = {
    playerData: null,
    groups: [],
    inGroup: false,
    groupId: null,
    groupData: [],
    groupMeta: null,
    groupStages: [],
    groupStatus: null,
    pendingInvites: [],
    nearbyPlayers: [],
    open: false,
    mounted: false,
  };

  function escapeHtml(value) {
    return String(value ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#039;');
  }

  async function nui(action, data) {
    const payload = data || {};

    if (typeof window.fetchNui === 'function') {
      try {
        return await window.fetchNui(action, payload);
      } catch (_) {
        return {};
      }
    }

    try {
      const response = await fetch(`https://${RESOURCE_NAME}/${action}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });

      try {
        return await response.json();
      } catch (_) {
        return {};
      }
    } catch (_) {
      return {};
    }
  }

  function getIsLeader() {
    return Array.isArray(state.groupData) && state.groupData.some((member) => Number(member.playerId) === Number(state.playerData?.source) && member.isLeader);
  }

  async function refreshNearbyPlayers() {
    if (!state.inGroup) {
      state.nearbyPlayers = [];
      render();
      return;
    }

    const result = await nui('getNearbyPlayers', { maxDistance: 6.0 });
    state.nearbyPlayers = Array.isArray(result?.players) ? result.players : [];
    render();
  }

  async function refreshAppState() {
    await nui('refreshApp', {});
    if (state.open && state.inGroup) {
      await refreshNearbyPlayers();
    }
  }

  function applySetupData(data) {
    state.playerData = data?.playerData || null;
    state.groups = Array.isArray(data?.groups) ? data.groups : [];
    state.inGroup = !!data?.inGroup;
    state.groupId = data?.groupId || data?.inGroup || null;
    state.groupData = Array.isArray(data?.groupData) ? data.groupData : [];
    state.groupMeta = data?.groupMeta || null;
    state.groupStages = Array.isArray(data?.groupJobSteps) ? data.groupJobSteps : (Array.isArray(data?.groupStages) ? data.groupStages : []);
    state.groupStatus = data?.groupStatus || null;
    state.pendingInvites = Array.isArray(data?.pendingInvites) ? data.pendingInvites : [];
  }

  function handleMessage(event) {
    const payload = event.data;
    if (!payload || typeof payload !== 'object') return;

    const action = payload.action;
    const data = payload.data;

    if (action === 'setupApp') {
      applySetupData(data || {});
      render();
      if (state.open && state.inGroup) {
        refreshNearbyPlayers();
      }
      return;
    }

    if (action === 'setGroups') {
      state.groups = Array.isArray(data) ? data : [];
      render();
      return;
    }

    if (action === 'setCurrentGroup') {
      state.groupData = Array.isArray(data) ? data : [];
      render();
      return;
    }

    if (action === 'setInGroup') {
      state.inGroup = !!data;
      state.groupId = data || null;
      render();
      return;
    }

    if (action === 'setGroupJobSteps') {
      state.groupStages = Array.isArray(data) ? data : [];
      render();
    }
  }

  function ensureRoot() {
    if (state.mounted) return;

    const root = document.createElement('div');
    root.id = 'group_system-root';
    document.body.appendChild(root);
    state.mounted = true;
    render();
  }

  function bindEvents(root) {
    root.querySelector('[data-enhancer="toggle"]')?.addEventListener('click', async () => {
      state.open = !state.open;
      render();
      if (state.open && state.inGroup) {
        await refreshNearbyPlayers();
      }
    });

    root.querySelector('[data-enhancer="close"]')?.addEventListener('click', () => {
      state.open = false;
      render();
    });

    root.querySelector('[data-enhancer="refresh"]')?.addEventListener('click', async () => {
      await refreshAppState();
    });

    root.querySelector('[data-enhancer="refresh-nearby"]')?.addEventListener('click', async () => {
      await refreshNearbyPlayers();
    });

    root.querySelectorAll('[data-enhancer-action="toggle-inviting"]').forEach((button) => {
      button.addEventListener('click', async () => {
        await nui('toggleGroupInviting', {});
        setTimeout(refreshAppState, 100);
      });
    });

    root.querySelectorAll('[data-enhancer-action="toggle-lock"]').forEach((button) => {
      button.addEventListener('click', async () => {
        const locked = button.dataset.locked === 'true';
        await nui('setGroupLocked', { locked: !locked });
        setTimeout(refreshAppState, 100);
      });
    });

    root.querySelectorAll('[data-enhancer-action="invite-player"]').forEach((button) => {
      button.addEventListener('click', async () => {
        await nui('inviteNearbyPlayer', { playerId: Number(button.dataset.playerId) });
        setTimeout(refreshAppState, 100);
      });
    });

    root.querySelectorAll('[data-enhancer-action="promote-member"]').forEach((button) => {
      button.addEventListener('click', async () => {
        await nui('promoteGroupMember', { playerId: Number(button.dataset.playerId) });
        setTimeout(refreshAppState, 100);
      });
    });

    root.querySelectorAll('[data-enhancer-action="remove-member"]').forEach((button) => {
      button.addEventListener('click', async () => {
        await nui('removeGroupMember', { playerId: Number(button.dataset.playerId) });
        setTimeout(refreshAppState, 100);
      });
    });

    root.querySelectorAll('[data-enhancer-action="accept-invite"]').forEach((button) => {
      button.addEventListener('click', async () => {
        await nui('acceptGroupInvite', {
          inviteUuid: button.dataset.inviteUuid,
          inviterSrc: Number(button.dataset.inviterSrc),
        });
        setTimeout(refreshAppState, 100);
      });
    });

    root.querySelectorAll('[data-enhancer-action="decline-invite"]').forEach((button) => {
      button.addEventListener('click', async () => {
        await nui('declineGroupInvite', {
          inviteUuid: button.dataset.inviteUuid,
          inviterSrc: Number(button.dataset.inviterSrc),
        });
        setTimeout(refreshAppState, 100);
      });
    });
  }

  function renderInvites() {
    if (state.inGroup) {
      return '';
    }

    if (!state.pendingInvites.length) {
      return '<div class="group_system-empty">No pending invites right now.</div>';
    }

    return `
      <div class="group_system-list">
        ${state.pendingInvites.map((invite) => `
          <div class="group_system-item">
            <div class="group_system-main">
              <strong>${escapeHtml(invite.groupName || 'Group')}</strong>
              <span class="group_system-subtle">Invited by ${escapeHtml(invite.inviterName || 'Unknown')}</span>
            </div>
            <div class="group_system-actions">
              <button class="group_system-btn group_system-btn-success" data-enhancer-action="accept-invite" data-invite-uuid="${escapeHtml(invite.inviteUuid)}" data-inviter-src="${Number(invite.inviterSrc || 0)}">Accept</button>
              <button class="group_system-btn" data-enhancer-action="decline-invite" data-invite-uuid="${escapeHtml(invite.inviteUuid)}" data-inviter-src="${Number(invite.inviterSrc || 0)}">Decline</button>
            </div>
          </div>
        `).join('')}
      </div>
    `;
  }

  function renderMembers() {
    if (!state.inGroup || !state.groupData.length) {
      return '<div class="group_system-empty">Create a group from the main page, or wait for an invite.</div>';
    }

    const isLeader = getIsLeader();

    return `
      <div class="group_system-list">
        ${state.groupData.map((member) => {
          const isSelf = Number(member.playerId) === Number(state.playerData?.source);
          return `
            <div class="group_system-item">
              <div class="group_system-main">
                <strong>${escapeHtml(member.name || 'Unknown')}</strong>
                <div class="group_system-pills">
                  ${member.isLeader ? '<span class="group_system-pill group_system-pill-accent">Leader</span>' : ''}
                  ${isSelf ? '<span class="group_system-pill">You</span>' : ''}
                </div>
              </div>
              ${isLeader && !isSelf ? `
                <div class="group_system-actions">
                  <button class="group_system-btn" data-enhancer-action="promote-member" data-player-id="${Number(member.playerId)}">Promote</button>
                  <button class="group_system-btn group_system-btn-danger" data-enhancer-action="remove-member" data-player-id="${Number(member.playerId)}">Remove</button>
                </div>
              ` : ''}
            </div>
          `;
        }).join('')}
      </div>
    `;
  }

  function renderNearbyPlayers() {
    if (!state.inGroup) {
      return '<div class="group_system-empty">You need a group before you can invite nearby players.</div>';
    }

    const isLeader = getIsLeader();
    const inviting = !!state.groupMeta?.isInviting;
    const members = new Set((state.groupData || []).map((member) => Number(member.playerId)));
    const players = (state.nearbyPlayers || []).filter((player) => !members.has(Number(player.playerId)));

    if (!players.length) {
      return '<div class="group_system-empty">No nearby players found.</div>';
    }

    return `
      <div class="group_system-list">
        ${players.map((player) => `
          <div class="group_system-item">
            <div class="group_system-main">
              <strong>${escapeHtml(player.name || `Player ${player.playerId}`)}</strong>
              <span class="group_system-subtle">${Number(player.playerId)} • ${Number(player.distance || 0).toFixed(1)}m away</span>
            </div>
            <div class="group_system-actions">
              ${isLeader ? `<button class="group_system-btn ${inviting ? 'group_system-btn-accent' : ''}" data-enhancer-action="invite-player" data-player-id="${Number(player.playerId)}" ${inviting ? '' : 'disabled'}>${inviting ? 'Invite' : 'Invites Off'}</button>` : '<span class="group_system-pill">Leader only</span>'}
            </div>
          </div>
        `).join('')}
      </div>
    `;
  }

  function renderOpenGroups() {
    if (state.inGroup || !state.groups.length) {
      return '';
    }

    return `
      <div class="group_system-section">
        <h4>Active Groups</h4>
        <div class="group_system-list">
          ${state.groups.slice(0, 5).map((group) => `
            <div class="group_system-item">
              <div class="group_system-main">
                <strong>${escapeHtml(group.name || 'Group')}</strong>
                <span class="group_system-subtle">${Number(group.memberCount || 0)} members${group.leader ? ` • ${escapeHtml(group.leader)}` : ''}</span>
              </div>
              <div class="group_system-pills">
                <span class="group_system-pill ${group.isInviting ? 'group_system-pill-success' : ''}">${group.isInviting ? 'Invites On' : 'Invites Off'}</span>
                <span class="group_system-pill ${group.isLocked ? 'group_system-pill-danger' : ''}">${group.isLocked ? 'Locked' : 'Unlocked'}</span>
              </div>
            </div>
          `).join('')}
        </div>
      </div>
    `;
  }

  function render() {
    const root = document.getElementById('group_system-root');
    if (!root) return;

    const inviteCount = state.pendingInvites.length;
    const isLeader = getIsLeader();
    const groupName = state.groupMeta?.name || 'Group Tools';
    const groupLeader = state.groupMeta?.leader?.name || state.groupMeta?.leader || null;
    const inviting = !!state.groupMeta?.isInviting;
    const locked = !!state.groupMeta?.isLocked;

    root.innerHTML = `
      <button class="group_system-toggle ${inviteCount > 0 ? 'has-badge' : ''}" data-badge="${inviteCount}" data-enhancer="toggle">${state.open ? 'Hide Tools' : 'Group Tools'}</button>
      <div class="group_system-panel ${state.open ? '' : 'group_system-hidden'}">
        <div class="group_system-header">
          <div class="group_system-title">
            <strong>${escapeHtml(state.inGroup ? groupName : 'Group Tools')}</strong>
            <span>${state.inGroup ? `${escapeHtml(groupLeader || 'Unknown')} • ${Number(state.groupMeta?.memberCount || 0)} members` : 'Extra invite and leader controls inside the phone app.'}</span>
          </div>
          <div class="group_system-actions">
            <button class="group_system-btn" data-enhancer="refresh">Refresh</button>
            <button class="group_system-close" data-enhancer="close">×</button>
          </div>
        </div>
        <div class="group_system-content">
          ${state.inGroup ? `
            <div class="group_system-section">
              <h4>Group Controls</h4>
              <div class="group_system-card">
                <div class="group_system-row">
                  <div class="group_system-pills">
                    <span class="group_system-pill group_system-pill-accent">${Number(state.groupMeta?.memberCount || 0)} members</span>
                    <span class="group_system-pill ${inviting ? 'group_system-pill-success' : ''}">${inviting ? 'Invites On' : 'Invites Off'}</span>
                    <span class="group_system-pill ${locked ? 'group_system-pill-danger' : ''}">${locked ? 'Locked' : 'Unlocked'}</span>
                  </div>
                </div>
                ${isLeader ? `
                  <div class="group_system-buttons" style="margin-top:10px;">
                    <button class="group_system-btn group_system-btn-primary" data-enhancer-action="toggle-inviting">${inviting ? 'Disable Invites' : 'Enable Invites'}</button>
                    <button class="group_system-btn" data-enhancer-action="toggle-lock" data-locked="${locked}">${locked ? 'Unlock Group' : 'Lock Group'}</button>
                  </div>
                ` : `<div class="group_system-subtle" style="margin-top:10px;">Only the leader can change invite and lock settings.</div>`}
              </div>
            </div>
          ` : `
            <div class="group_system-section">
              <h4>Invites</h4>
              ${renderInvites()}
            </div>
          `}

          <div class="group_system-section">
            <h4>${state.inGroup ? 'Member Management' : 'Group Help'}</h4>
            ${state.inGroup ? renderMembers() : '<div class="group_system-empty">Use the main page to create a new group. Incoming invites will show up here.</div>'}
          </div>

          <div class="group_system-section">
            <div class="group_system-row">
              <h4>Nearby Players</h4>
              <button class="group_system-btn" data-enhancer="refresh-nearby">Refresh Nearby</button>
            </div>
            ${renderNearbyPlayers()}
          </div>

          ${renderOpenGroups()}
        </div>
      </div>
    `;

    bindEvents(root);
  }

  function start() {
    ensureRoot();
    window.addEventListener('message', handleMessage);
    setTimeout(refreshAppState, 350);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  } else {
    start();
  }
})();
