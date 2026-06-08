(() => {
  const vscode = typeof acquireVsCodeApi === 'function' ? acquireVsCodeApi() : null;
  const pending = new Map();
  const NODE_WIDTH = 170;
  const VIEW_STORE_KEY = 'otter.repoGraph.views.v1';
  const WORKSPACE_STORE_KEY = 'otter.repoGraph.workspace.v1';
  const PANEL_IDS = ['topbar', 'graph', 'bottom'];
  let requestId = 0;

  const els = {
    repoRoot: document.getElementById('repo-root'),
    includeTests: document.getElementById('include-tests'),
    analyzeBtn: document.getElementById('analyze-btn'),
    chooseBtn: document.getElementById('choose-btn'),
    resetBtn: document.getElementById('reset-btn'),
    fileMenu: document.getElementById('file-menu'),
    viewMenu: document.getElementById('view-menu'),
    selectionMenu: document.getElementById('selection-menu'),
    openRepoBtn: document.getElementById('open-repo-btn'),
    saveViewBtn: document.getElementById('save-view-btn'),
    loadViewSelect: document.getElementById('load-view-select'),
    loadViewBtn: document.getElementById('load-view-btn'),
    deleteViewBtn: document.getElementById('delete-view-btn'),
    exportGraphBtn: document.getElementById('export-graph-btn'),
    exportViewBtn: document.getElementById('export-view-btn'),
    autoLayoutBtn: document.getElementById('auto-layout-btn'),
    toggleGridBtn: document.getElementById('toggle-grid-btn'),
    toggleMinimapBtn: document.getElementById('toggle-minimap-btn'),
    focusSelectedBtn: document.getElementById('focus-selected-btn'),
    clearFocusBtn: document.getElementById('clear-focus-btn'),
    pinSelectedBtn: document.getElementById('pin-selected-btn'),
    unpinAllBtn: document.getElementById('unpin-all-btn'),
    nodeSearch: document.getElementById('node-search'),
    canvasSearch: document.getElementById('canvas-search'),
    canvasSearchFilter: document.getElementById('canvas-search-filter'),
    zoomOutBtn: document.getElementById('zoom-out-btn'),
    zoomLabel: document.getElementById('zoom-label'),
    zoomInBtn: document.getElementById('zoom-in-btn'),
    fitBtn: document.getElementById('fit-btn'),
    clearExpandBtn: document.getElementById('clear-expand-btn'),
    hostPill: document.getElementById('host-pill'),
    summaryPill: document.getElementById('summary-pill'),
    breadcrumbs: document.getElementById('breadcrumbs'),
    graphShell: document.getElementById('graph-shell'),
    mainGrid: document.getElementById('main-grid'),
    canvasPanel: document.querySelector('.canvas-panel'),
    workspaceMenu: document.getElementById('workspace-menu'),
    newWindowBtn: document.getElementById('new-window-btn'),
    newVerticalPanelBtn: document.getElementById('new-vertical-panel-btn'),
    newHorizontalPanelBtn: document.getElementById('new-horizontal-panel-btn'),
    closePanelBtn: document.getElementById('close-panel-btn'),
    graphSurface: document.getElementById('graph-surface'),
    graphCanvas: document.getElementById('graph-canvas'),
    graphEdges: document.getElementById('graph-edges'),
    minimap: document.getElementById('minimap'),
    minimapContent: document.getElementById('minimap-content'),
    minimapViewport: document.getElementById('minimap-viewport'),
    selectedRole: document.getElementById('selected-role'),
    selectedMeta: document.getElementById('selected-meta'),
    annotationNote: document.getElementById('annotation-note'),
    queueNoteBtn: document.getElementById('queue-note-btn'),
    runBtn: document.getElementById('run-btn'),
    noteCount: document.getElementById('note-count'),
    queuedNotes: document.getElementById('queued-notes'),
    sendNotesBtn: document.getElementById('send-notes-btn'),
    clearNotesBtn: document.getElementById('clear-notes-btn'),
    bottomToggleBtn: document.getElementById('bottom-toggle-btn'),
    summaryLines: document.getElementById('summary-lines'),
    runOutput: document.getElementById('run-output'),
    statusLog: document.getElementById('status-log'),
    tooltip: document.getElementById('tooltip')
  };

  const state = {
    host: 'browser',
    supportsFolderPicker: false,
    supportsCodexSend: false,
    repoRoot: '',
    includeTests: false,
    graph: null,
    summary: [],
    functionById: new Map(),
    inboundById: new Map(),
    outboundById: new Map(),
    functionsByReturnType: new Map(),
    rootNodeIdsCache: [],
    endpointNodeIdsCache: new Set(),
    initializerNodeIdsCache: new Set(),
    initializerIdsByEntry: new Map(),
    manualPositions: new Map(),
    manualSizes: new Map(),
    currentView: null,
    suppressNodeClick: false,
    selectedNodeId: null,
    focusedNodeId: null,
    expandedNodes: new Set(),
    openNodes: new Set(),
    bottomCollapsed: false,
    activePanelId: 'graph',
    workspaceOrientation: 'stacked',
    panelVisibility: { topbar: true, graph: true, bottom: true },
    panelWindows: new Map(),
    workspaceSaveTimer: null,
    showGrid: true,
    showMinimap: true,
    zoom: 1,
    surfaceWidth: 800,
    surfaceHeight: 600,
    statusMessages: [],
    notes: [],
    lastRun: null,
    renderToken: 0,
    edgeRenderToken: 0,
    minimapRenderToken: 0,
    geometryRefreshFrame: 0,
    minimapFrame: 0
  };

  function logStatus(message) {
    const stamp = new Date().toLocaleTimeString();
    state.statusMessages.unshift(`[${stamp}] ${message}`);
    state.statusMessages = state.statusMessages.slice(0, 20);
    if (els.statusLog) {
      els.statusLog.textContent = state.statusMessages.join('\n');
    }
  }

  function escapeHtml(value) {
    return String(value ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function safeParseJson(text) {
    if (typeof text !== 'string') return text;
    try {
      return JSON.parse(text);
    } catch {
      return { ok: false, error: text };
    }
  }

  function nextFrame() {
    return new Promise((resolve) => {
      window.requestAnimationFrame(() => resolve());
    });
  }

  function safeFileStem(value, fallback = 'otter-graph') {
    const stem = String(value || fallback)
      .split(/[\\/]/)
      .filter(Boolean)
      .pop() || fallback;
    return stem.replace(/[^a-z0-9._-]+/gi, '-').replace(/^-+|-+$/g, '') || fallback;
  }

  function downloadJson(filename, data) {
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  }

  function closeMenus() {
    [els.fileMenu, els.viewMenu, els.selectionMenu, els.workspaceMenu].forEach((menu) => {
      if (menu) menu.open = false;
    });
  }

  function bindOptionalClick(id, handler) {
    const el = document.getElementById(id);
    if (el) el.addEventListener('click', handler);
  }

  function setOptionalMenuText(id, text) {
    const el = document.getElementById(id);
    if (!el) return;
    const label = el.querySelector('.menu-text');
    if (label) {
      label.textContent = text;
      return;
    }
    el.textContent = text;
  }

  function panelElement(panelId) {
    return document.querySelector(`[data-panel-id="${panelId}"]`);
  }

  function visiblePanelIds() {
    return PANEL_IDS.filter((panelId) => state.panelVisibility[panelId] && !state.panelWindows.has(panelId));
  }

  function setActivePanel(panelId) {
    if (!PANEL_IDS.includes(panelId)) return;
    state.activePanelId = panelId;
    document.querySelectorAll('[data-panel-id]').forEach((panel) => {
      panel.classList.toggle('active-panel', panel.getAttribute('data-panel-id') === panelId);
    });
    if (els.mainGrid) {
      els.mainGrid.setAttribute('data-active-panel', panelId);
    }
  }

  function workspaceSettingsPayload() {
    return {
      version: 1,
      orientation: state.workspaceOrientation,
      visiblePanels: { ...state.panelVisibility },
      detachedPanels: [...state.panelWindows.keys()],
      activePanelId: state.activePanelId,
      bottomCollapsed: state.bottomCollapsed,
      showGrid: state.showGrid,
      showMinimap: state.showMinimap
    };
  }

  function localWorkspaceSettingsKey(rootDir = state.repoRoot) {
    return `${WORKSPACE_STORE_KEY}:${String(rootDir || 'default')}`;
  }

  function saveWorkspaceSettingsLocal(payload = workspaceSettingsPayload()) {
    try {
      window.localStorage.setItem(localWorkspaceSettingsKey(), JSON.stringify(payload));
    } catch {
      return;
    }
  }

  function loadWorkspaceSettingsLocal(rootDir = state.repoRoot) {
    try {
      const raw = window.localStorage.getItem(localWorkspaceSettingsKey(rootDir));
      return raw ? JSON.parse(raw) : null;
    } catch {
      return null;
    }
  }

  function scheduleWorkspaceSettingsSave() {
    if (state.workspaceSaveTimer) {
      window.clearTimeout(state.workspaceSaveTimer);
    }
    state.workspaceSaveTimer = window.setTimeout(() => {
      state.workspaceSaveTimer = null;
      void saveWorkspaceSettings();
    }, 300);
  }

  async function saveWorkspaceSettings() {
    const payload = workspaceSettingsPayload();
    saveWorkspaceSettingsLocal(payload);
    if (!state.repoRoot) return;
    const resp = await hostCall('otterSaveViewSettings', {
      repoRoot: state.repoRoot,
      settings: payload
    });
    if (resp && resp.ok === false && resp.error !== 'no host bridge available') {
      logStatus(resp.error || 'unable to save view settings');
    }
  }

  function applyWorkspaceSettings(settings, options = {}) {
    if (!settings || typeof settings !== 'object') return;
    const visiblePanels = settings.visiblePanels || {};
    state.workspaceOrientation = settings.orientation === 'vertical' ? 'vertical' : 'stacked';
    PANEL_IDS.forEach((panelId) => {
      if (typeof visiblePanels[panelId] === 'boolean') {
        state.panelVisibility[panelId] = visiblePanels[panelId];
      }
    });
    if (!visiblePanelIds().length) {
      state.panelVisibility.graph = true;
    }
    state.activePanelId = PANEL_IDS.includes(settings.activePanelId) ? settings.activePanelId : 'graph';
    state.showGrid = typeof settings.showGrid === 'boolean' ? settings.showGrid : state.showGrid;
    state.showMinimap = typeof settings.showMinimap === 'boolean' ? settings.showMinimap : state.showMinimap;
    state.bottomCollapsed = typeof settings.bottomCollapsed === 'boolean' ? settings.bottomCollapsed : state.bottomCollapsed;
    applyWorkspaceLayout({ save: options.save !== false });
    setBottomCollapsed(state.bottomCollapsed, { save: false });
    updateViewToggles();
  }

  async function loadWorkspaceSettings(rootDir = state.repoRoot) {
    let settings = null;
    if (rootDir) {
      const resp = await hostCall('otterLoadViewSettings', { repoRoot: rootDir });
      if (resp && resp.ok && resp.settings) {
        settings = resp.settings;
      }
    }
    if (!settings) {
      settings = loadWorkspaceSettingsLocal(rootDir);
    }
    if (settings) {
      applyWorkspaceSettings(settings, { save: false });
      logStatus('loaded project view settings');
    } else {
      applyWorkspaceLayout({ save: false });
      updateViewToggles();
    }
  }

  function applyWorkspaceLayout(options = {}) {
    if (!els.mainGrid) return;
    els.mainGrid.classList.toggle('layout-vertical', state.workspaceOrientation === 'vertical');
    els.mainGrid.classList.toggle('layout-stacked', state.workspaceOrientation !== 'vertical');
    PANEL_IDS.forEach((panelId) => {
      const panel = panelElement(panelId);
      if (!panel) return;
      const hidden = !state.panelVisibility[panelId] || state.panelWindows.has(panelId);
      panel.classList.toggle('panel-hidden', hidden);
    });
    if (!visiblePanelIds().includes(state.activePanelId)) {
      const fallback = visiblePanelIds()[0] || 'graph';
      state.activePanelId = fallback;
    }
    setActivePanel(state.activePanelId);
    window.requestAnimationFrame(() => {
      if (state.currentView) {
        syncGraphSurface(state.currentView);
        fitView(false);
      }
    });
    if (options.save !== false) {
      scheduleWorkspaceSettingsSave();
    }
  }

  function setWorkspaceOrientation(orientation) {
    state.workspaceOrientation = orientation === 'vertical' ? 'vertical' : 'stacked';
    PANEL_IDS.forEach((panelId) => {
      if (!state.panelWindows.has(panelId)) {
        state.panelVisibility[panelId] = true;
      }
    });
    applyWorkspaceLayout();
    closeMenus();
    logStatus(state.workspaceOrientation === 'vertical' ? 'new vertical panel layout' : 'new horizontal panel layout');
  }

  function popupShell(panelId, panelTitle) {
    return `
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>${escapeHtml(panelTitle)}</title>
        <link rel="stylesheet" href="app.css">
      </head>
      <body class="workspace-window">
        <div id="main-grid" class="main-grid layout-stacked" data-active-panel="${escapeHtml(panelId)}"></div>
        <details class="workspace-menu">
          <summary class="action tiny">Views</summary>
          <div class="menu-popover workspace-popover">
            <button id="popup-new-window-btn" class="action primary">New Window</button>
            <button id="popup-new-vertical-panel-btn" class="action muted">New Vertical Panel</button>
            <button id="popup-new-horizontal-panel-btn" class="action muted">New Horizontal Panel</button>
            <button id="popup-close-panel-btn" class="action muted">Close This Panel</button>
          </div>
        </details>
      </body>
      </html>
    `;
  }

  function panelTitle(panelId) {
    if (panelId === 'topbar') return 'Otter Toolbar';
    if (panelId === 'bottom') return 'Otter Inspector';
    return 'Otter Graph';
  }

  function returnPanelFromWindow(panelId) {
    const record = state.panelWindows.get(panelId);
    if (!record) return;
    state.panelWindows.delete(panelId);
    state.panelVisibility[panelId] = true;
    record.placeholder.replaceWith(record.panel);
    applyWorkspaceLayout();
    logStatus(`returned ${panelTitle(panelId).toLowerCase()} to main window`);
  }

  function openActivePanelWindow() {
    const panelId = state.activePanelId;
    const panel = panelElement(panelId);
    if (!panel || state.panelWindows.has(panelId)) {
      logStatus('select an attached panel first');
      return;
    }
    const popup = window.open('', `otter-${panelId}`, 'popup=yes,width=980,height=720');
    if (!popup) {
      logStatus('popup blocked; allow popups for panel windows');
      return;
    }
    const placeholder = document.createComment(`otter-${panelId}-window-placeholder`);
    panel.replaceWith(placeholder);
    state.panelWindows.set(panelId, { win: popup, panel, placeholder });
    popup.document.open();
    popup.document.write(popupShell(panelId, panelTitle(panelId)));
    popup.document.close();
    let attached = false;
    const attachPopupPanel = () => {
      if (attached) return;
      const target = popup.document.getElementById('main-grid');
      if (!target) return;
      attached = true;
      if (target) target.appendChild(panel);
      panel.classList.remove('panel-hidden');
      panel.classList.add('active-panel');
      const closeBtn = popup.document.getElementById('popup-close-panel-btn');
      const verticalBtn = popup.document.getElementById('popup-new-vertical-panel-btn');
      const horizontalBtn = popup.document.getElementById('popup-new-horizontal-panel-btn');
      const windowBtn = popup.document.getElementById('popup-new-window-btn');
      const popupGrid = popup.document.getElementById('main-grid');
      if (closeBtn) {
        closeBtn.addEventListener('click', () => {
          popup.close();
        });
      }
      if (verticalBtn && popupGrid) {
        verticalBtn.addEventListener('click', () => {
          popupGrid.classList.add('layout-vertical');
          popupGrid.classList.remove('layout-stacked');
        });
      }
      if (horizontalBtn && popupGrid) {
        horizontalBtn.addEventListener('click', () => {
          popupGrid.classList.remove('layout-vertical');
          popupGrid.classList.add('layout-stacked');
        });
      }
      if (windowBtn) {
        windowBtn.addEventListener('click', () => popup.focus());
      }
      if (state.currentView) {
        syncGraphSurface(state.currentView);
        fitView(false);
      }
    };
    attachPopupPanel();
    popup.addEventListener('load', attachPopupPanel);
    popup.addEventListener('beforeunload', () => {
      returnPanelFromWindow(panelId);
    });
    applyWorkspaceLayout();
    closeMenus();
    logStatus(`opened ${panelTitle(panelId).toLowerCase()} in a new window`);
  }

  function closeActivePanel() {
    const panelId = state.activePanelId;
    if (state.panelWindows.has(panelId)) {
      const record = state.panelWindows.get(panelId);
      record.win.close();
      return;
    }
    if (visiblePanelIds().length <= 1) {
      logStatus('cannot close the last visible panel');
      return;
    }
    state.panelVisibility[panelId] = false;
    applyWorkspaceLayout();
    closeMenus();
    logStatus(`closed ${panelTitle(panelId).toLowerCase()}`);
  }

  function hostCall(method, payload = {}) {
    if (window.webui && typeof window.webui.call === 'function') {
      return window.webui.call(method, JSON.stringify(payload)).then(safeParseJson);
    }
    if (!vscode) {
      return Promise.resolve({ ok: false, error: 'no host bridge available' });
    }
    const id = String(++requestId);
    return new Promise((resolve) => {
      pending.set(id, resolve);
      vscode.postMessage({ type: 'hostCall', id, method, payload });
    });
  }

  window.addEventListener('message', (event) => {
    const msg = event.data;
    if (!msg || msg.type !== 'hostResponse') return;
    const resolve = pending.get(msg.id);
    if (!resolve) return;
    pending.delete(msg.id);
    resolve(msg.body);
  });

  function resetIndexes() {
    state.functionById = new Map();
    state.inboundById = new Map();
    state.outboundById = new Map();
    state.functionsByReturnType = new Map();
    state.rootNodeIdsCache = [];
    state.endpointNodeIdsCache = new Set();
    state.initializerNodeIdsCache = new Set();
    state.initializerIdsByEntry = new Map();
  }

  async function indexGraph(graph) {
    resetIndexes();
    const functions = graph.functions || [];
    const edges = graph.edges || [];
    for (let i = 0; i < functions.length; i += 1) {
      const fn = functions[i];
      const returnType = cleanTypeName(fn.returnType);
      state.functionById.set(fn.id, fn);
      state.inboundById.set(fn.id, []);
      state.outboundById.set(fn.id, []);
      if (returnType) {
        if (!state.functionsByReturnType.has(returnType)) {
          state.functionsByReturnType.set(returnType, []);
        }
        state.functionsByReturnType.get(returnType).push(fn);
      }
      if ((i + 1) % 600 === 0) await nextFrame();
    }
    for (let i = 0; i < edges.length; i += 1) {
      const edge = edges[i];
      if (!state.functionById.has(edge.callerId) || !state.functionById.has(edge.calleeId)) continue;
      state.outboundById.get(edge.callerId).push(edge.calleeId);
      state.inboundById.get(edge.calleeId).push(edge.callerId);
      if ((i + 1) % 1200 === 0) await nextFrame();
    }
    await rebuildNodeKindCaches();
  }

  function selectedNode() {
    if (!state.selectedNodeId) return null;
    return state.functionById.get(state.selectedNodeId) || null;
  }

  function roleColor(role) {
    if (role === 'orchestrator' || role === 'meta_orchestrator') return 'var(--accent)';
    if (role === 'state_controller') return 'var(--warn)';
    if (role === 'helper' || role === 'wrapper') return 'var(--active)';
    return 'var(--ok)';
  }

  function hashString(text) {
    let hash = 2166136261;
    for (let i = 0; i < text.length; i += 1) {
      hash ^= text.charCodeAt(i);
      hash = Math.imul(hash, 16777619);
    }
    return hash >>> 0;
  }

  function socketColor(socket, outputs = false) {
    const key = `${outputs ? 'out' : 'in'}:${socket.name || ''}:${socket.typeName || ''}`;
    const hash = hashString(key);
    const hue = hash % 360;
    const saturation = 58 + (hash % 18);
    const lightness = 54 + ((hash >>> 8) % 12);
    return `hsl(${hue} ${saturation}% ${lightness}%)`;
  }

  function moduleColor(modulePath) {
    const hash = hashString(String(modulePath || 'root'));
    const hue = hash % 360;
    return `hsl(${hue} 68% 58%)`;
  }

  function inputSockets(node) {
    return (node.sockets || []).filter((socket) => socket.direction !== 'output' && socket.name !== 'result');
  }

  function outputSockets(node) {
    return (node.sockets || []).filter((socket) => socket.direction === 'output' || socket.name === 'result');
  }

  function cleanTypeName(typeName) {
    return String(typeName || '')
      .replace(/\b(var|sink|lent|ref|ptr|owned)\b/g, '')
      .replace(/\s+/g, '')
      .replace(/\[.*\]$/g, '')
      .toLowerCase();
  }

  function isPrimitiveType(typeName) {
    const t = cleanTypeName(typeName);
    return !t || ['int', 'int8', 'int16', 'int32', 'int64', 'uint', 'uint8', 'uint16', 'uint32', 'uint64', 'float', 'float32', 'float64', 'bool', 'char', 'string', 'cstring', 'void'].includes(t);
  }

  function initializerNameScore(name) {
    const t = String(name || '').toLowerCase();
    if (/^(init|new|make|create|build|default)/.test(t)) return 2;
    if (/(state|config|context|ctx|options|client|api)/.test(t)) return 1;
    return 0;
  }

  function compareNodes(a, b) {
    const moduleCmp = String(a.modulePath || '').localeCompare(String(b.modulePath || ''));
    if (moduleCmp !== 0) return moduleCmp;
    if ((a.lineStart || 0) !== (b.lineStart || 0)) return (a.lineStart || 0) - (b.lineStart || 0);
    return String(a.name || '').localeCompare(String(b.name || ''));
  }

  function uniqueSortedNodeIds(ids) {
    const seen = new Set();
    return ids
      .filter((id) => {
        if (!state.functionById.has(id) || seen.has(id)) return false;
        seen.add(id);
        return true;
      })
      .sort((a, b) => compareNodes(state.functionById.get(a), state.functionById.get(b)));
  }

  function directCalleeIds(nodeId) {
    return uniqueSortedNodeIds(state.outboundById.get(nodeId) || []);
  }

  function computeRootNodeIds() {
    const roots = (state.graph?.functions || [])
      .filter((node) => (state.inboundById.get(node.id) || []).length === 0)
      .map((node) => node.id);
    if (roots.length) return uniqueSortedNodeIds(roots);
    return uniqueSortedNodeIds((state.graph?.functions || []).map((node) => node.id));
  }

  function rootNodeIds() {
    if (state.rootNodeIdsCache.length) return [...state.rootNodeIdsCache];
    return computeRootNodeIds();
  }

  function initializerIdsForEntry(entryId) {
    const entry = state.functionById.get(entryId);
    if (!entry) return [];
    const neededTypes = inputSockets(entry)
      .map((socket) => cleanTypeName(socket.typeName))
      .filter((typeName) => typeName && !isPrimitiveType(typeName));
    if (!neededTypes.length) return [];
    const matches = [];
    const candidatesById = new Map();
    if (state.functionsByReturnType.size) {
      neededTypes.forEach((typeName) => {
        (state.functionsByReturnType.get(typeName) || []).forEach((node) => {
          candidatesById.set(node.id, node);
        });
      });
    } else {
      (state.graph?.functions || []).forEach((node) => {
        candidatesById.set(node.id, node);
      });
    }
    candidatesById.forEach((node) => {
      if (node.id === entryId || !node.returnType) return;
      const returnType = cleanTypeName(node.returnType);
      if (!neededTypes.includes(returnType)) return;
      const score = initializerNameScore(node.name);
      if (score <= 0 && !returnType.includes('state')) return;
      matches.push({ id: node.id, score });
    });
    matches.sort((a, b) => b.score - a.score || compareNodes(state.functionById.get(a.id), state.functionById.get(b.id)));
    return uniqueSortedNodeIds(matches.map((item) => item.id));
  }

  function endpointNodeIds() {
    if (state.endpointNodeIdsCache.size) return new Set(state.endpointNodeIdsCache);
    return new Set(rootNodeIds());
  }

  function initializerNodeIdsForEndpoints() {
    if (state.initializerNodeIdsCache.size) return new Set(state.initializerNodeIdsCache);
    const ids = new Set();
    rootNodeIds().forEach((entryId) => {
      initializerIdsForEntry(entryId).forEach((initId) => ids.add(initId));
    });
    return ids;
  }

  function initializerIdsForVisibleEntry(entryId) {
    return state.initializerIdsByEntry.get(entryId) || initializerIdsForEntry(entryId);
  }

  async function rebuildNodeKindCaches() {
    const roots = computeRootNodeIds();
    const initIds = new Set();
    const initByEntry = new Map();
    for (let i = 0; i < roots.length; i += 1) {
      const entryId = roots[i];
      const ids = initializerIdsForEntry(entryId);
      initByEntry.set(entryId, ids);
      ids.forEach((initId) => initIds.add(initId));
      if ((i + 1) % 120 === 0) await nextFrame();
    }
    state.rootNodeIdsCache = roots;
    state.endpointNodeIdsCache = new Set(roots);
    state.initializerNodeIdsCache = initIds;
    state.initializerIdsByEntry = initByEntry;
  }

  function nodeKindFor(nodeId) {
    if (state.initializerNodeIdsCache.has(nodeId)) return 'init';
    if (state.endpointNodeIdsCache.has(nodeId)) return 'api';
    return '';
  }

  function nodeSearchText(node, filter = 'functions') {
    const inputs = inputSockets(node);
    const outputs = outputSockets(node);
    const typeNames = [
      node.returnType,
      ...inputs.map((socket) => socket.typeName),
      ...outputs.map((socket) => socket.typeName)
    ];
    let values = [];
    if (filter === 'parameters') {
      values = [
        ...(node.params || []),
        ...inputs.map((socket) => `${socket.name} ${socket.typeName} ${socket.sampleExpr || ''}`)
      ];
    } else if (filter === 'tags') {
      values = [
        node.role,
        node.roleReason,
        ...(node.pragmaTags || []),
        ...(node.riskTags || []).map((tag) => `${tag.key} ${tag.value}`)
      ];
    } else if (filter === 'results') {
      values = [
        node.returnType,
        ...outputs.map((socket) => `${socket.name} ${socket.typeName} ${socket.sampleExpr || ''}`)
      ];
    } else if (filter === 'types') {
      values = typeNames;
    } else {
      values = [
        node.name,
        node.modulePath,
        node.sourcePath,
        node.signature,
        node.role
      ];
    }
    return values.filter(Boolean).join(' ').toLowerCase();
  }

  function findNodeMatch(query, filter = 'functions') {
    const q = query.trim().toLowerCase();
    if (!q || !state.graph) return null;
    const visibleIds = new Set(state.currentView ? [...state.currentView.positions.keys()] : []);
    const functions = uniqueSortedNodeIds((state.graph.functions || []).map((node) => node.id))
      .map((id) => state.functionById.get(id))
      .filter(Boolean);
    const visibleMatch = functions.find((node) => visibleIds.has(node.id) && nodeSearchText(node, filter).includes(q));
    if (visibleMatch) return visibleMatch;
    return functions.find((node) => nodeSearchText(node, filter).includes(q)) || null;
  }

  function pathToNode(targetId) {
    const roots = rootNodeIds();
    const queue = roots.map((id) => ({ id, path: [id] }));
    const seen = new Set(roots);
    while (queue.length) {
      const item = queue.shift();
      if (item.id === targetId) return item.path;
      directCalleeIds(item.id).forEach((childId) => {
        if (seen.has(childId)) return;
        seen.add(childId);
        queue.push({ id: childId, path: [...item.path, childId] });
      });
    }
    return null;
  }

  function scrollToNode(nodeId) {
    window.requestAnimationFrame(() => {
      const pos = state.currentView?.positions.get(nodeId);
      if (!pos) return;
      els.graphShell.scrollTo({
        left: Math.max(0, (pos.x + pos.width / 2) * state.zoom - els.graphShell.clientWidth / 2),
        top: Math.max(0, (pos.y + pos.height / 2) * state.zoom - els.graphShell.clientHeight / 2),
        behavior: 'smooth'
      });
    });
  }

  async function revealNode(nodeId) {
    const path = pathToNode(nodeId);
    if (path) {
      path.slice(0, -1).forEach((id) => state.expandedNodes.add(id));
    }
    state.selectedNodeId = nodeId;
    renderSelectedMeta();
    await renderGraph();
    scrollToNode(nodeId);
  }

  function searchNodes(options = {}) {
    const input = options.input || els.nodeSearch;
    const filter = options.filter || 'functions';
    const query = input?.value || '';
    const match = findNodeMatch(query, filter);
    if (!match) {
      logStatus(`no ${filter} match for "${query}"`);
      return;
    }
    void revealNode(match.id);
    logStatus(`selected ${match.name}`);
  }

  function collapseNodeAndDescendants(nodeId) {
    const queue = [nodeId];
    const seen = new Set();
    while (queue.length) {
      const currentId = queue.shift();
      if (seen.has(currentId)) continue;
      seen.add(currentId);
      state.expandedNodes.delete(currentId);
      directCalleeIds(currentId).forEach((childId) => queue.push(childId));
    }
  }

  function nodeHeight(node) {
    const inputs = inputSockets(node).length;
    const outputs = outputSockets(node).length;
    const rows = Math.max(inputs, outputs, 1);
    return 66 + rows * 12;
  }

  function graphCounts(graph) {
    const counts = { functions: 0, edges: 0, groups: 0, orchestrators: 0 };
    if (!graph) return counts;
    counts.functions = (graph.functions || []).length;
    counts.edges = (graph.edges || []).length;
    counts.groups = (graph.groups || []).length;
    counts.orchestrators = (graph.functions || []).filter((fn) => fn.role === 'orchestrator' || fn.role === 'meta_orchestrator').length;
    return counts;
  }

  function renderSummary() {
    const lines = state.summary.length ? state.summary : [];
    if (els.summaryLines) {
      els.summaryLines.textContent = lines.join('\n');
    }
    const counts = graphCounts(state.graph);
    els.summaryPill.textContent = state.graph ? `${counts.functions} fn / ${counts.edges} edges` : 'idle';
  }

  function renderSelectedMeta() {
    const node = selectedNode();
    if (!node) {
      els.selectedMeta.textContent = 'Select a node to inspect its signature, comments, and notes.';
      els.selectedRole.textContent = 'none';
      return;
    }
    els.selectedRole.textContent = node.role || 'unknown';
    const lines = [
      `${node.name} :: ${node.modulePath}`,
      `lines ${node.lineStart}-${node.lineEnd}`,
      node.signature || '',
      '',
      `tags: ${(node.pragmaTags || []).join(', ') || 'none'}`,
      `user input: ${node.handlesUserInput ? node.userInputReason || 'yes' : 'no'}`
    ];
    if ((node.docCommentLines || []).length) {
      lines.push('', 'docs:');
      node.docCommentLines.forEach((line) => lines.push(`  ${line}`));
    }
    els.selectedMeta.textContent = lines.join('\n');
  }

  function renderNotes() {
    els.noteCount.textContent = String(state.notes.length);
    if (!state.notes.length) {
      els.queuedNotes.textContent = 'No queued notes.';
      return;
    }
    els.queuedNotes.innerHTML = '';
    state.notes.forEach((note, index) => {
      const wrap = document.createElement('div');
      wrap.className = 'queued-note';
      wrap.innerHTML = `
        <div class="queued-note-name">${note.name}</div>
        <div class="queued-note-text">${note.note}</div>
        <div class="node-subtitle">${note.sourcePath}:${note.lineStart}</div>
      `;
      wrap.addEventListener('click', () => {
        void revealNode(note.functionId);
        logStatus(`selected queued note ${index + 1}`);
      });
      els.queuedNotes.appendChild(wrap);
    });
  }

  function renderRunOutput() {
    if (!state.lastRun) {
      els.runOutput.textContent = 'No function run yet.';
      return;
    }
    const lines = [];
    lines.push(`ok: ${state.lastRun.ok}`);
    if (state.lastRun.mode) lines.push(`mode: ${state.lastRun.mode}`);
    if (state.lastRun.resultText) lines.push(`result: ${state.lastRun.resultText}`);
    if ((state.lastRun.generatedArgs || []).length) {
      lines.push('', 'generated args:');
      state.lastRun.generatedArgs.forEach((arg) => lines.push(`  ${arg}`));
    }
    if ((state.lastRun.mutatedArgs || []).length) {
      lines.push('', 'mutated args:');
      state.lastRun.mutatedArgs.forEach((arg) => lines.push(`  ${arg}`));
    }
    if (state.lastRun.stdout) lines.push('', 'stdout:', state.lastRun.stdout);
    if (state.lastRun.error) lines.push('', 'error:', state.lastRun.error);
    els.runOutput.textContent = lines.join('\n');
  }

  function showTooltip(node, x, y) {
    showTooltipText(node?.tooltipText || '', x, y);
  }

  function showTooltipText(text, x, y) {
    if (!text) {
      hideTooltip();
      return;
    }
    els.tooltip.textContent = text;
    els.tooltip.classList.remove('hidden');
    const left = Math.min(window.innerWidth - 440, x + 18);
    const top = Math.min(window.innerHeight - 260, y + 18);
    els.tooltip.style.left = `${Math.max(16, left)}px`;
    els.tooltip.style.top = `${Math.max(16, top)}px`;
  }

  function hideTooltip() {
    els.tooltip.classList.add('hidden');
  }

  function tooltipFromEvent(event, fallbackNode) {
    const target = event.target.closest('[data-tooltip]');
    return target ? target.getAttribute('data-tooltip') : fallbackNode?.tooltipText || '';
  }

  async function computeLayout(nodes, token) {
    const groups = new Map();
    for (let i = 0; i < nodes.length; i += 1) {
      if (token !== state.renderToken) return null;
      const node = nodes[i];
      const key = node.modulePath || node.sourcePath || 'unknown';
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(node);
      if ((i + 1) % 350 === 0) await nextFrame();
    }

    const groupItems = [...groups.entries()].sort((a, b) => a[0].localeCompare(b[0]));
    const positions = new Map();
    const groupGapX = 120;
    const groupGapY = 96;
    const nodeGapX = 26;
    const nodeGapY = 22;
    const columns = Math.max(1, Math.ceil(Math.sqrt(groupItems.length || 1)));
    let cursorX = 80;
    let cursorY = 80;
    let rowHeight = 0;

    for (let groupIndex = 0; groupIndex < groupItems.length; groupIndex += 1) {
      if (token !== state.renderToken) return null;
      const [modulePath, groupNodes] = groupItems[groupIndex];
      const sorted = groupNodes.sort(compareNodes);
      const nodeCols = Math.max(1, Math.ceil(Math.sqrt(sorted.length)));
      const nodeRows = Math.ceil(sorted.length / nodeCols);
      let maxNodeHeight = 0;
      for (let nodeIndex = 0; nodeIndex < sorted.length; nodeIndex += 1) {
        if (token !== state.renderToken) return null;
        maxNodeHeight = Math.max(maxNodeHeight, nodeHeight(sorted[nodeIndex]));
        if ((nodeIndex + 1) % 350 === 0) await nextFrame();
      }
      const clusterWidth = nodeCols * NODE_WIDTH + Math.max(0, nodeCols - 1) * nodeGapX;
      const clusterHeight = nodeRows * maxNodeHeight + Math.max(0, nodeRows - 1) * nodeGapY;

      if (groupIndex > 0 && groupIndex % columns === 0) {
        cursorX = 80;
        cursorY += rowHeight + groupGapY;
        rowHeight = 0;
      }

      for (let nodeIndex = 0; nodeIndex < sorted.length; nodeIndex += 1) {
        if (token !== state.renderToken) return null;
        const node = sorted[nodeIndex];
        const col = nodeIndex % nodeCols;
        const row = Math.floor(nodeIndex / nodeCols);
        positions.set(node.id, {
          x: cursorX + col * (NODE_WIDTH + nodeGapX),
          y: cursorY + row * (maxNodeHeight + nodeGapY),
          width: NODE_WIDTH,
          height: nodeHeight(node),
          modulePath
        });
        if ((nodeIndex + 1) % 350 === 0) await nextFrame();
      }

      cursorX += clusterWidth + groupGapX;
      rowHeight = Math.max(rowHeight, clusterHeight);
      await nextFrame();
    }
    return positions;
  }

  async function centerAutoPositions(positions, token) {
    if (!positions.size || !els.graphShell) return;
    let minX = Infinity;
    let minY = Infinity;
    let maxX = 0;
    let maxY = 0;
    let index = 0;
    for (const pos of positions.values()) {
      if (token !== state.renderToken) return;
      minX = Math.min(minX, pos.x);
      minY = Math.min(minY, pos.y);
      maxX = Math.max(maxX, pos.x + pos.width);
      maxY = Math.max(maxY, pos.y + pos.height);
      index += 1;
      if (index % 450 === 0) await nextFrame();
    }
    const graphWidth = maxX - minX;
    const graphHeight = maxY - minY;
    const targetX = Math.max(80, (els.graphShell.clientWidth / Math.max(state.zoom, 0.01) - graphWidth) / 2);
    const targetY = Math.max(80, (els.graphShell.clientHeight / Math.max(state.zoom, 0.01) - graphHeight) / 2);
    const dx = targetX - minX;
    const dy = targetY - minY;
    index = 0;
    for (const pos of positions.values()) {
      if (token !== state.renderToken) return;
      pos.x += dx;
      pos.y += dy;
      index += 1;
      if (index % 450 === 0) await nextFrame();
    }
  }

  async function viewFromVisibleIds(visibleIds, edges, token) {
    const nodes = uniqueSortedNodeIds([...visibleIds]).map((id) => state.functionById.get(id));
    const positions = await computeLayout(nodes, token);
    if (!positions || token !== state.renderToken) return null;
    await centerAutoPositions(positions, token);
    if (token !== state.renderToken) return null;
    let index = 0;
    let maxRight = 0;
    let maxBottom = 0;
    for (const [nodeId, pos] of positions.entries()) {
      const manualSize = state.manualSizes.get(nodeId);
      if (manualSize) {
        pos.width = manualSize.width;
        pos.height = manualSize.height;
      }
      const manual = state.manualPositions.get(nodeId);
      if (manual) {
        pos.x = manual.x;
        pos.y = manual.y;
      }
      maxRight = Math.max(maxRight, pos.x + pos.width);
      maxBottom = Math.max(maxBottom, pos.y + pos.height);
      index += 1;
      if (index % 450 === 0) await nextFrame();
    }
    return { nodes, edges, positions, bounds: { maxRight, maxBottom } };
  }

  function addVisibleEdge(edges, edgeKeys, callerId, calleeId, extra = {}) {
    const key = `${callerId}->${calleeId}${extra.kind ? `:${extra.kind}` : ''}`;
    if (edgeKeys.has(key)) return;
    edgeKeys.add(key);
    edges.push({ callerId, calleeId, ...extra });
  }

  async function rootVisibleGraph(token) {
    const roots = rootNodeIds();
    const visibleIds = new Set(roots);
    const edges = [];
    const edgeKeys = new Set();
    for (let i = 0; i < roots.length; i += 1) {
      if (token !== state.renderToken) return null;
      const entryId = roots[i];
      initializerIdsForVisibleEntry(entryId).forEach((initId) => {
        visibleIds.add(initId);
        addVisibleEdge(edges, edgeKeys, initId, entryId, { synthetic: true, kind: 'init' });
      });
      if ((i + 1) % 100 === 0) await nextFrame();
    }
    const queue = [...visibleIds];
    const queuedIds = new Set(queue);
    let index = 0;
    while (index < queue.length) {
      if (token !== state.renderToken) return null;
      const callerId = queue[index];
      index += 1;
      if (!state.expandedNodes.has(callerId)) continue;
      directCalleeIds(callerId).forEach((calleeId) => {
        visibleIds.add(calleeId);
        addVisibleEdge(edges, edgeKeys, callerId, calleeId);
        if (!queuedIds.has(calleeId)) {
          queuedIds.add(calleeId);
          queue.push(calleeId);
        }
      });
      if (index % 160 === 0) await nextFrame();
    }
    return viewFromVisibleIds(visibleIds, edges, token);
  }

  async function focusedVisibleGraph(token) {
    const focusId = state.focusedNodeId;
    if (!focusId || !state.functionById.has(focusId)) return rootVisibleGraph(token);
    const visibleIds = new Set([focusId]);
    const edges = [];
    const edgeKeys = new Set();
    directCalleeIds(focusId).forEach((calleeId) => visibleIds.add(calleeId));
    (state.inboundById.get(focusId) || []).forEach((callerId) => visibleIds.add(callerId));
    initializerIdsForVisibleEntry(focusId).forEach((initId) => {
      visibleIds.add(initId);
      addVisibleEdge(edges, edgeKeys, initId, focusId, { synthetic: true, kind: 'init' });
    });
    const graphEdges = state.graph?.edges || [];
    for (let i = 0; i < graphEdges.length; i += 1) {
      if (token !== state.renderToken) return null;
      const edge = graphEdges[i];
      if (!visibleIds.has(edge.callerId) || !visibleIds.has(edge.calleeId)) continue;
      addVisibleEdge(edges, edgeKeys, edge.callerId, edge.calleeId);
      if ((i + 1) % 450 === 0) await nextFrame();
    }
    return viewFromVisibleIds(visibleIds, edges, token);
  }

  async function visibleGraph(token) {
    if (!state.graph) return { nodes: [], edges: [], positions: new Map() };
    if (state.focusedNodeId) return focusedVisibleGraph(token);
    return rootVisibleGraph(token);
  }

  function edgePath(edge, from, to) {
    const fromOpen = state.openNodes.has(edge.callerId);
    const toOpen = state.openNodes.has(edge.calleeId);
    const fromWidth = from.width * (fromOpen ? 2 : 1);
    const fromHeight = from.height * (fromOpen ? 2 : 1);
    const toHeight = to.height * (toOpen ? 2 : 1);
    const x1 = from.x + fromWidth;
    const y1 = from.y + fromHeight / 2;
    const x2 = to.x;
    const y2 = to.y + toHeight / 2;
    const dx = Math.max(40, (x2 - x1) / 2);
    return `M ${x1} ${y1} C ${x1 + dx} ${y1}, ${x2 - dx} ${y2}, ${x2} ${y2}`;
  }

  async function renderEdges(view) {
    const token = ++state.edgeRenderToken;
    els.graphEdges.innerHTML = '';
    let fragment = document.createDocumentFragment();
    for (let i = 0; i < view.edges.length; i += 1) {
      if (token !== state.edgeRenderToken) return;
      const edge = view.edges[i];
      const from = view.positions.get(edge.callerId);
      const to = view.positions.get(edge.calleeId);
      if (!from || !to) continue;
      const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      path.setAttribute('d', edgePath(edge, from, to));
      path.setAttribute('class', `edge-line${edge.synthetic ? ' expand' : ''}`);
      fragment.appendChild(path);
      if ((i + 1) % 140 === 0) {
        els.graphEdges.appendChild(fragment);
        fragment = document.createDocumentFragment();
        await nextFrame();
      }
    }
    if (token !== state.edgeRenderToken) return;
    els.graphEdges.appendChild(fragment);
  }

  function renderMinimap(view = state.currentView) {
    const token = ++state.minimapRenderToken;
    if (!state.showMinimap) {
      if (els.minimap) els.minimap.classList.add('hidden');
      return;
    }
    if (!view || !els.minimapContent || !els.minimapViewport) {
      if (els.minimap) els.minimap.classList.add('hidden');
      return;
    }
    if (!view.positions.size) {
      els.minimap.classList.add('hidden');
      els.minimapContent.innerHTML = '';
      return;
    }
    if (state.minimapFrame) {
      window.cancelAnimationFrame(state.minimapFrame);
    }
    state.minimapFrame = window.requestAnimationFrame(() => {
      state.minimapFrame = 0;
      void renderMinimapNow(view, token);
    });
  }

  function updateMinimapViewport(view = state.currentView) {
    if (!state.showMinimap || !view || !els.minimapViewport || !els.minimap || els.minimap.classList.contains('hidden')) return;
    const width = els.minimap.clientWidth || 178;
    const height = els.minimap.clientHeight || 120;
    const scaleX = width / Math.max(1, state.surfaceWidth);
    const scaleY = height / Math.max(1, state.surfaceHeight);
    els.minimapViewport.style.left = `${(els.graphShell.scrollLeft / Math.max(state.zoom, 0.01)) * scaleX}px`;
    els.minimapViewport.style.top = `${(els.graphShell.scrollTop / Math.max(state.zoom, 0.01)) * scaleY}px`;
    els.minimapViewport.style.width = `${(els.graphShell.clientWidth / Math.max(state.zoom, 0.01)) * scaleX}px`;
    els.minimapViewport.style.height = `${(els.graphShell.clientHeight / Math.max(state.zoom, 0.01)) * scaleY}px`;
  }

  async function renderMinimapNow(view, token) {
    if (token !== state.minimapRenderToken) return;
    els.minimap.classList.remove('hidden');
    const width = els.minimap.clientWidth || 178;
    const height = els.minimap.clientHeight || 120;
    const scaleX = width / Math.max(1, state.surfaceWidth);
    const scaleY = height / Math.max(1, state.surfaceHeight);
    els.minimapContent.innerHTML = '';
    let fragment = document.createDocumentFragment();
    let index = 0;
    for (const [nodeId, pos] of view.positions.entries()) {
      if (token !== state.minimapRenderToken) return;
      const node = state.functionById.get(nodeId);
      const scale = state.openNodes.has(nodeId) ? 2 : 1;
      const item = document.createElement('div');
      item.className = 'minimap-node';
      item.style.left = `${pos.x * scaleX}px`;
      item.style.top = `${pos.y * scaleY}px`;
      item.style.width = `${Math.max(2, pos.width * scale * scaleX)}px`;
      item.style.height = `${Math.max(2, pos.height * scale * scaleY)}px`;
      item.style.setProperty('--cluster-color', moduleColor(node?.modulePath || node?.sourcePath || 'unknown'));
      fragment.appendChild(item);
      index += 1;
      if (index % 140 === 0) {
        els.minimapContent.appendChild(fragment);
        fragment = document.createDocumentFragment();
        await nextFrame();
      }
    }
    if (token !== state.minimapRenderToken) return;
    els.minimapContent.appendChild(fragment);
    updateMinimapViewport(view);
  }

  function syncGraphSurface(view) {
    let maxRight = view.bounds?.maxRight || 0;
    let maxBottom = view.bounds?.maxBottom || 0;
    state.openNodes.forEach((nodeId) => {
      const pos = view.positions.get(nodeId);
      if (!pos) return;
      maxRight = Math.max(maxRight, pos.x + pos.width * 2);
      maxBottom = Math.max(maxBottom, pos.y + pos.height * 2);
    });
    const width = Math.max(els.graphShell.clientWidth, maxRight + 160, 800);
    const height = Math.max(els.graphShell.clientHeight, maxBottom + 160, 600);
    state.surfaceWidth = width;
    state.surfaceHeight = height;
    els.graphCanvas.style.width = `${width}px`;
    els.graphCanvas.style.height = `${height}px`;
    els.graphCanvas.style.minHeight = `${height}px`;
    els.graphEdges.setAttribute('width', String(width));
    els.graphEdges.setAttribute('height', String(height));
    els.graphEdges.style.width = `${width}px`;
    els.graphEdges.style.height = `${height}px`;
    applyZoom();
    renderMinimap(view);
  }

  function clampZoom(value) {
    return Math.min(2.5, Math.max(0.12, value));
  }

  function applyZoom() {
    const scaledWidth = state.surfaceWidth * state.zoom;
    const scaledHeight = state.surfaceHeight * state.zoom;
    els.graphSurface.style.width = `${scaledWidth}px`;
    els.graphSurface.style.height = `${scaledHeight}px`;
    els.graphCanvas.style.transform = `scale(${state.zoom})`;
    els.graphEdges.style.transform = `scale(${state.zoom})`;
    els.zoomLabel.textContent = `${Math.round(state.zoom * 100)}%`;
    updateMinimapViewport();
  }

  function setZoom(nextZoom, anchor = null) {
    const previousZoom = state.zoom;
    const zoom = clampZoom(nextZoom);
    if (Math.abs(zoom - previousZoom) < 0.001) return;
    const rect = els.graphShell.getBoundingClientRect();
    const anchorX = anchor ? anchor.clientX - rect.left : rect.width / 2;
    const anchorY = anchor ? anchor.clientY - rect.top : rect.height / 2;
    const contentX = (els.graphShell.scrollLeft + anchorX) / previousZoom;
    const contentY = (els.graphShell.scrollTop + anchorY) / previousZoom;
    state.zoom = zoom;
    applyZoom();
    els.graphShell.scrollLeft = contentX * zoom - anchorX;
    els.graphShell.scrollTop = contentY * zoom - anchorY;
  }

  function socketHtml(socket, outputs = false) {
    const direction = outputs ? 'output' : (socket.direction === 'var_input' ? 'mutable input' : 'input');
    const tooltip = [
      `${direction}: ${socket.name || 'param'}`,
      `type: ${socket.typeName || 'void'}`,
      socket.sampleExpr ? `sample: ${socket.sampleExpr}` : '',
      outputs ? 'Return value socket.' : 'Function parameter socket.'
    ].filter(Boolean).join('\n');
    return `
      <div class="socket-row ${outputs ? 'outputs' : ''}" style="--socket-color: ${socketColor(socket, outputs)}" data-tooltip="${escapeHtml(tooltip)}">
        <span class="socket-dot"></span>
        <span class="socket-type">${escapeHtml(socket.name)}: ${escapeHtml(socket.typeName || 'void')}</span>
      </div>
    `;
  }

  function extendViewBoundsForPos(view, pos) {
    if (!view || !pos) return;
    if (!view.bounds) {
      view.bounds = { maxRight: 0, maxBottom: 0 };
    }
    view.bounds.maxRight = Math.max(view.bounds.maxRight, pos.x + pos.width);
    view.bounds.maxBottom = Math.max(view.bounds.maxBottom, pos.y + pos.height);
  }

  function refreshGraphGeometrySoon(view = state.currentView) {
    if (!view) return;
    if (state.geometryRefreshFrame) {
      window.cancelAnimationFrame(state.geometryRefreshFrame);
    }
    state.geometryRefreshFrame = window.requestAnimationFrame(() => {
      state.geometryRefreshFrame = 0;
      if (view !== state.currentView) return;
      syncGraphSurface(view);
      void renderEdges(view);
    });
  }

  function selectNodeLocally(nodeId, card, pinOpen = true) {
    state.selectedNodeId = nodeId;
    els.graphCanvas.querySelectorAll('.node.selected').forEach((nodeEl) => {
      nodeEl.classList.remove('selected');
    });
    if (card) {
      card.classList.add('selected');
      if (pinOpen) {
        card.classList.add('open');
      }
    }
    if (pinOpen) {
      state.openNodes.add(nodeId);
      const openBtn = card?.querySelector('.node-open');
      if (openBtn) {
        openBtn.innerHTML = '&minus;';
        openBtn.title = 'Close node';
        openBtn.setAttribute('data-tooltip', 'Close this pinned-open node.');
      }
    }
    renderSelectedMeta();
    refreshGraphGeometrySoon();
  }

  function startNodeResize(event, node, card) {
    if (event.button !== 0) return;
    const view = state.currentView;
    const pos = view?.positions.get(node.id);
    if (!view || !pos) return;
    event.preventDefault();
    event.stopPropagation();
    const startX = event.clientX;
    const startY = event.clientY;
    const startSize = { width: pos.width, height: pos.height };
    const onMove = (moveEvent) => {
      pos.width = Math.max(110, startSize.width + (moveEvent.clientX - startX) / state.zoom);
      pos.height = Math.max(58, startSize.height + (moveEvent.clientY - startY) / state.zoom);
      state.manualSizes.set(node.id, { width: pos.width, height: pos.height });
      card.style.setProperty('--node-width-current', `${pos.width}px`);
      card.style.setProperty('--node-height', `${pos.height}px`);
      extendViewBoundsForPos(view, pos);
      refreshGraphGeometrySoon(view);
      moveEvent.preventDefault();
    };
    const onUp = () => {
      window.removeEventListener('mousemove', onMove);
      window.removeEventListener('mouseup', onUp);
    };
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
  }

  function startNodeDrag(event, node, card) {
    if (event.button !== 0 || event.target.closest('.node-btn')) return;
    const view = state.currentView;
    const pos = view?.positions.get(node.id);
    if (!view || !pos) return;
    event.preventDefault();
    event.stopPropagation();

    const startX = event.clientX;
    const startY = event.clientY;
    const startPos = { x: pos.x, y: pos.y };
    let moved = false;
    els.graphShell.classList.add('dragging-node');

    const onMove = (moveEvent) => {
      const rawDx = moveEvent.clientX - startX;
      const rawDy = moveEvent.clientY - startY;
      if (!moved && Math.hypot(rawDx, rawDy) < 3) return;
      moved = true;
      pos.x = Math.max(0, startPos.x + rawDx / state.zoom);
      pos.y = Math.max(0, startPos.y + rawDy / state.zoom);
      state.manualPositions.set(node.id, { x: pos.x, y: pos.y });
      card.style.left = `${pos.x}px`;
      card.style.top = `${pos.y}px`;
      extendViewBoundsForPos(view, pos);
      refreshGraphGeometrySoon(view);
      moveEvent.preventDefault();
    };

    const onUp = () => {
      window.removeEventListener('mousemove', onMove);
      window.removeEventListener('mouseup', onUp);
      els.graphShell.classList.remove('dragging-node');
      if (moved) {
        state.suppressNodeClick = true;
        setTimeout(() => {
          state.suppressNodeClick = false;
        }, 0);
      }
    };

    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
  }

  function renderNode(node, pos) {
    const card = document.createElement('div');
    const childIds = directCalleeIds(node.id);
    const heldOpen = state.openNodes.has(node.id);
    const nodeKind = nodeKindFor(node.id);
    card.className = `node${nodeKind ? ` node-${nodeKind}` : ''}${state.selectedNodeId === node.id ? ' selected' : ''}${heldOpen ? ' open' : ''}`;
    card.style.left = `${pos.x}px`;
    card.style.top = `${pos.y}px`;
    card.style.setProperty('--node-width-current', `${pos.width}px`);
    card.style.setProperty('--node-height', `${pos.height}px`);
    card.style.setProperty('--cluster-color', moduleColor(node.modulePath || node.sourcePath || 'unknown'));
    const inputs = inputSockets(node);
    const outputs = outputSockets(node);
    const childCount = childIds.length;
    const expanded = state.expandedNodes.has(node.id);
    const kindBadge = nodeKind === 'api'
      ? '<span class="node-kind api" data-tooltip="API or endpoint entry point. This function is not called by another parsed function.">API</span>'
      : (nodeKind === 'init'
        ? '<span class="node-kind init" data-tooltip="Initializer visible because an API or endpoint needs its returned state/object.">INIT</span>'
        : '');
    card.innerHTML = `
      <div class="node-header">
        <div class="node-title-wrap">
          <div class="node-title" data-tooltip="${escapeHtml(`${node.name}\n${node.signature || ''}\nrole: ${node.role || 'unknown'}`)}">${escapeHtml(node.name)}</div>
          <div class="node-subtitle" data-tooltip="${escapeHtml(`${node.sourcePath || node.modulePath}\nlines ${node.lineStart}-${node.lineEnd}`)}">${escapeHtml(node.modulePath)}:${escapeHtml(node.lineStart)}</div>
        </div>
        <div class="node-controls">
          <button class="node-btn node-open" title="${heldOpen ? 'Close node' : 'Keep node open'}" data-tooltip="${heldOpen ? 'Close this pinned-open node.' : 'Keep this node expanded after hover.'}">${heldOpen ? '&minus;' : '&#9633;'}</button>
          <button class="node-btn node-run" title="Run" data-tooltip="${escapeHtml(`Run ${node.name} with generated sample arguments.`)}">&#9654;</button>
          ${childCount ? `<button class="node-btn node-expand" title="${expanded ? 'Collapse callees' : 'Expand callees'}" data-tooltip="${escapeHtml(`${expanded ? 'Collapse' : 'Expand'} ${childCount} direct callees.`)}">${expanded ? '-' : '+'}</button>` : ''}
        </div>
      </div>
      <div class="node-body">
        <div class="socket-column inputs">${inputs.map((socket) => socketHtml(socket)).join('')}</div>
        <div class="node-center">
          ${kindBadge}
          <span class="role-badge" data-tooltip="${escapeHtml(`Role: ${node.role || 'unknown'}\nConfidence: ${node.roleConfidence ?? 'n/a'}\nReason: ${node.roleReason || 'n/a'}`)}">${escapeHtml(node.role || 'unknown')}</span>
          ${childCount ? `<span class="mini-tag" data-tooltip="${escapeHtml(`${childCount} direct function calls from this node.`)}">${childCount} calls</span>` : ''}
        </div>
        <div class="socket-column outputs">${outputs.map((socket) => socketHtml(socket, true)).join('')}</div>
      </div>
      <span class="node-resize" data-tooltip="Drag to manually resize this node."></span>
    `;
    card.addEventListener('mousedown', (event) => startNodeDrag(event, node, card));
    card.addEventListener('mouseenter', (event) => showTooltipText(tooltipFromEvent(event, node), event.clientX, event.clientY));
    card.addEventListener('mousemove', (event) => showTooltipText(tooltipFromEvent(event, node), event.clientX, event.clientY));
    card.addEventListener('mouseleave', hideTooltip);
    card.addEventListener('click', (event) => {
      if (state.suppressNodeClick) return;
      if (event.target.closest('.node-btn')) return;
      selectNodeLocally(node.id, card, true);
    });
    card.addEventListener('dblclick', () => toggleExpand(node.id));
    const runBtn = card.querySelector('.node-run');
    runBtn.addEventListener('click', (event) => {
      event.stopPropagation();
      state.selectedNodeId = node.id;
      renderSelectedMeta();
      runSelectedNode();
    });
    const openBtn = card.querySelector('.node-open');
    openBtn.addEventListener('click', (event) => {
      event.stopPropagation();
      toggleNodeOpen(node.id, card);
    });
    const expandBtn = card.querySelector('.node-expand');
    if (expandBtn) {
      expandBtn.addEventListener('click', (event) => {
        event.stopPropagation();
        toggleExpand(node.id);
      });
    }
    const resizeHandle = card.querySelector('.node-resize');
    resizeHandle.addEventListener('mousedown', (event) => startNodeResize(event, node, card));
    return card;
  }

  async function renderGraph(options = {}) {
    const token = ++state.renderToken;
    els.graphCanvas.innerHTML = '';
    els.graphEdges.innerHTML = '';
    renderBreadcrumbs();
    await nextFrame();
    if (token !== state.renderToken) return;
    const view = await visibleGraph(token);
    if (!view || token !== state.renderToken) return;
    state.currentView = view;
    if (token !== state.renderToken) return;
    syncGraphSurface(view);
    void renderEdges(view);
    const chunkSize = 36;
    let fragment = document.createDocumentFragment();
    for (let i = 0; i < view.nodes.length; i += 1) {
      if (token !== state.renderToken) return;
      const node = view.nodes[i];
      const pos = view.positions.get(node.id);
      if (pos) {
        fragment.appendChild(renderNode(node, pos));
      }
      if ((i + 1) % chunkSize === 0) {
        els.graphCanvas.appendChild(fragment);
        fragment = document.createDocumentFragment();
        await nextFrame();
      }
    }
    els.graphCanvas.appendChild(fragment);
    if (options.fit) {
      fitView(false);
    }
  }

  function renderBreadcrumbs() {
    if (!els.breadcrumbs) return;
    const focus = state.focusedNodeId ? state.functionById.get(state.focusedNodeId) : null;
    const parts = [focus ? `focus: ${focus.name}` : 'root callers'];
    if (state.expandedNodes.size) {
      parts.push(`${state.expandedNodes.size} expanded`);
    }
    els.breadcrumbs.textContent = parts.join(' / ');
  }

  function toggleExpand(nodeId) {
    const children = directCalleeIds(nodeId);
    if (!children.length) return;
    const node = state.functionById.get(nodeId);
    if (state.expandedNodes.has(nodeId)) {
      collapseNodeAndDescendants(nodeId);
      logStatus(`collapsed calls from ${node ? node.name : nodeId}`);
    } else {
      state.expandedNodes.add(nodeId);
      logStatus(`expanded ${children.length} calls from ${node ? node.name : nodeId}`);
    }
    void renderGraph();
  }

  function toggleNodeOpen(nodeId, card = null) {
    const willOpen = !state.openNodes.has(nodeId);
    if (state.openNodes.has(nodeId)) {
      state.openNodes.delete(nodeId);
    } else {
      state.openNodes.add(nodeId);
    }
    if (card) {
      card.classList.toggle('open', willOpen);
      const openBtn = card.querySelector('.node-open');
      if (openBtn) {
        openBtn.innerHTML = willOpen ? '&minus;' : '&#9633;';
        openBtn.title = willOpen ? 'Close node' : 'Keep node open';
        openBtn.setAttribute('data-tooltip', willOpen ? 'Close this pinned-open node.' : 'Keep this node expanded after hover.');
      }
      refreshGraphGeometrySoon();
    } else {
      void renderGraph();
    }
  }

  function enterSelectedGroup(nodeId = state.selectedNodeId) {
    toggleExpand(nodeId);
  }

  function exitGroup() {
    if (!state.expandedNodes.size) return false;
    state.expandedNodes = new Set();
    void renderGraph();
    logStatus('collapsed all expanded calls');
    return true;
  }

  async function analyzeRepo(options = {}) {
    const repoRoot = (els.repoRoot.value || '').trim();
    const includeTests = !!els.includeTests.checked;
    const repoChanged = repoRoot !== state.repoRoot;
    state.repoRoot = repoRoot;
    state.includeTests = includeTests;
    if (repoChanged && !options.skipWorkspaceLoad) {
      await loadWorkspaceSettings(repoRoot);
    }
    logStatus(`analyzing ${repoRoot}`);
    els.summaryPill.textContent = 'analyzing...';
    els.analyzeBtn.disabled = true;
    await nextFrame();
    const resp = await hostCall('otterAnalyze', { repoRoot, includeTests });
    els.analyzeBtn.disabled = false;
    if (!resp || !resp.ok) {
      logStatus(resp?.error || 'analyze failed');
      renderSummary();
      return;
    }
    state.graph = resp.graph;
    state.summary = resp.summary || [];
    if (!options.preserveView) {
      state.expandedNodes = new Set();
      state.openNodes = new Set();
      state.manualPositions = new Map();
      state.manualSizes = new Map();
      state.focusedNodeId = null;
    }
    await indexGraph(state.graph);
    const firstRootId = rootNodeIds()[0];
    const first = firstRootId ? state.functionById.get(firstRootId) : (state.graph.functions || [])[0];
    state.selectedNodeId = first ? first.id : null;
    renderSummary();
    await nextFrame();
    renderSelectedMeta();
    await renderGraph({ fit: options.fit !== false });
    logStatus(`analysis ready: ${(state.graph.functions || []).length} functions`);
  }

  async function runSelectedNode() {
    const node = selectedNode();
    if (!node) {
      logStatus('select a node first');
      return;
    }
    logStatus(`running ${node.name}`);
    const resp = await hostCall('otterRunFunction', {
      repoRoot: state.repoRoot,
      functionId: node.id,
      includeTests: true
    });
    state.lastRun = resp;
    renderRunOutput();
    logStatus(resp.ok ? `run finished for ${node.name}` : `run failed for ${node.name}`);
  }

  function queueNote() {
    const node = selectedNode();
    const note = (els.annotationNote.value || '').trim();
    if (!node || !note) {
      logStatus('select a node and enter a note');
      return;
    }
    state.notes.push({
      functionId: node.id,
      name: node.name,
      sourcePath: node.sourcePath,
      lineStart: node.lineStart,
      note
    });
    els.annotationNote.value = '';
    renderNotes();
    logStatus(`queued note for ${node.name}`);
  }

  async function sendNotes() {
    if (!state.notes.length) {
      logStatus('no notes queued');
      return;
    }
    const resp = await hostCall('otterSendAnnotations', {
      repoRoot: state.repoRoot,
      annotations: state.notes
    });
    if (resp && resp.ok) {
      logStatus(resp.message || 'notes sent');
      if (resp.path && els.statusLog) {
        els.statusLog.textContent = `Codex payload: ${resp.path}\n${els.statusLog.textContent}`;
      }
    } else {
      logStatus(resp?.error || 'unable to send notes');
    }
  }

  function readSavedViews() {
    try {
      const parsed = JSON.parse(window.localStorage.getItem(VIEW_STORE_KEY) || '[]');
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }

  function writeSavedViews(views) {
    window.localStorage.setItem(VIEW_STORE_KEY, JSON.stringify(views));
  }

  function refreshViewSelect() {
    const views = readSavedViews();
    els.loadViewSelect.innerHTML = '';
    if (!views.length) {
      const option = document.createElement('option');
      option.value = '';
      option.textContent = 'No saved views';
      els.loadViewSelect.appendChild(option);
      return;
    }
    views.forEach((view) => {
      const option = document.createElement('option');
      option.value = view.name;
      option.textContent = view.name;
      els.loadViewSelect.appendChild(option);
    });
  }

  function setBottomCollapsed(collapsed, options = {}) {
    state.bottomCollapsed = collapsed;
    const root = els.mainGrid || document.querySelector('.main-grid');
    root.classList.toggle('bottom-collapsed', collapsed);
    els.bottomToggleBtn.textContent = collapsed ? '^' : 'v';
    els.bottomToggleBtn.title = collapsed ? 'Expand bottom panel' : 'Collapse bottom panel';
    window.requestAnimationFrame(() => {
      if (state.currentView) {
        syncGraphSurface(state.currentView);
      }
    });
    if (options.save !== false) {
      scheduleWorkspaceSettingsSave();
    }
  }

  function currentViewPositions() {
    const positions = {};
    if (state.currentView) {
      state.currentView.positions.forEach((pos, nodeId) => {
        positions[nodeId] = { x: pos.x, y: pos.y };
      });
    }
    state.manualPositions.forEach((pos, nodeId) => {
      positions[nodeId] = { x: pos.x, y: pos.y };
    });
    return positions;
  }

  function currentViewSizes() {
    const sizes = {};
    if (state.currentView) {
      state.currentView.positions.forEach((pos, nodeId) => {
        sizes[nodeId] = { width: pos.width, height: pos.height };
      });
    }
    state.manualSizes.forEach((size, nodeId) => {
      sizes[nodeId] = { width: size.width, height: size.height };
    });
    return sizes;
  }

  function currentViewPayload() {
    return {
      repoRoot: state.repoRoot,
      includeTests: state.includeTests,
      positions: currentViewPositions(),
      sizes: currentViewSizes(),
      expandedNodes: [...state.expandedNodes],
      openNodes: [...state.openNodes],
      selectedNodeId: state.selectedNodeId,
      focusedNodeId: state.focusedNodeId,
      zoom: state.zoom,
      scrollLeft: els.graphShell.scrollLeft,
      scrollTop: els.graphShell.scrollTop
    };
  }

  function exportGraphJson() {
    if (!state.graph) {
      logStatus('analyze a repo before exporting graph JSON');
      return;
    }
    const stem = safeFileStem(state.repoRoot);
    downloadJson(`${stem}-graph.json`, {
      exportedAt: new Date().toISOString(),
      repoRoot: state.repoRoot,
      includeTests: state.includeTests,
      graph: state.graph
    });
    closeMenus();
    logStatus('exported graph JSON');
  }

  function exportViewJson() {
    if (!state.currentView) {
      logStatus('analyze a repo before exporting view JSON');
      return;
    }
    const stem = safeFileStem(state.repoRoot);
    downloadJson(`${stem}-view.json`, {
      exportedAt: new Date().toISOString(),
      view: currentViewPayload(),
      visibleNodeIds: state.currentView.nodes.map((node) => node.id),
      visibleEdges: state.currentView.edges
    });
    closeMenus();
    logStatus('exported view JSON');
  }

  function saveGraphView() {
    if (!state.graph) {
      logStatus('analyze a repo before saving a view');
      return;
    }
    const fallback = state.repoRoot ? state.repoRoot.split('/').filter(Boolean).pop() : 'graph-view';
    const name = window.prompt('Graph view name', fallback || 'graph-view');
    if (!name) return;
    const views = readSavedViews().filter((view) => view.name !== name);
    views.push({
      name,
      ...currentViewPayload(),
      savedAt: new Date().toISOString()
    });
    views.sort((a, b) => a.name.localeCompare(b.name));
    writeSavedViews(views);
    refreshViewSelect();
    els.loadViewSelect.value = name;
    els.fileMenu.open = false;
    logStatus(`saved view ${name}`);
  }

  async function applyGraphView(view) {
    state.manualPositions = new Map(Object.entries(view.positions || {}).map(([nodeId, pos]) => [
      nodeId,
      { x: Number(pos.x) || 0, y: Number(pos.y) || 0 }
    ]));
    state.manualSizes = new Map(Object.entries(view.sizes || {}).map(([nodeId, size]) => [
      nodeId,
      { width: Math.max(110, Number(size.width) || NODE_WIDTH), height: Math.max(58, Number(size.height) || 66) }
    ]));
    state.expandedNodes = new Set(view.expandedNodes || []);
    state.openNodes = new Set(view.openNodes || []);
    state.selectedNodeId = view.selectedNodeId || state.selectedNodeId;
    state.focusedNodeId = view.focusedNodeId || null;
    state.zoom = clampZoom(Number(view.zoom) || 1);
    renderSelectedMeta();
    await renderGraph();
    applyZoom();
    window.requestAnimationFrame(() => {
      els.graphShell.scrollLeft = Number(view.scrollLeft) || 0;
      els.graphShell.scrollTop = Number(view.scrollTop) || 0;
    });
  }

  async function loadSelectedGraphView() {
    const name = els.loadViewSelect.value;
    const view = readSavedViews().find((item) => item.name === name);
    if (!view) return;
    els.repoRoot.value = view.repoRoot || '';
    els.includeTests.checked = !!view.includeTests;
    await analyzeRepo({ fit: false, preserveView: true });
    await applyGraphView(view);
    els.fileMenu.open = false;
    logStatus(`loaded view ${name}`);
  }

  function deleteSelectedGraphView() {
    const name = els.loadViewSelect.value;
    if (!name) return;
    writeSavedViews(readSavedViews().filter((view) => view.name !== name));
    refreshViewSelect();
    logStatus(`deleted view ${name}`);
  }

  function promptRepoRoot() {
    const current = (els.repoRoot.value || state.repoRoot || '').trim();
    const repoRoot = window.prompt('Repo root path', current);
    if (!repoRoot || !repoRoot.trim()) return false;
    state.repoRoot = repoRoot.trim();
    els.repoRoot.value = state.repoRoot;
    logStatus(`selected ${state.repoRoot}`);
    return true;
  }

  async function chooseFolder(options = {}) {
    let selected = false;
    if (state.supportsFolderPicker) {
      const resp = await hostCall('otterChooseFolder', {});
      if (resp && resp.ok && resp.repoRoot) {
        state.repoRoot = resp.repoRoot;
        els.repoRoot.value = resp.repoRoot;
        selected = true;
        logStatus(`selected ${resp.repoRoot}`);
      } else if (resp?.error && resp.error !== 'no folder selected') {
        logStatus(resp.error);
      }
    } else {
      selected = promptRepoRoot();
    }
    if (!selected) return;
    await loadWorkspaceSettings(state.repoRoot);
    closeMenus();
    if (options.analyze) {
      await analyzeRepo({ skipWorkspaceLoad: true });
    }
  }

  function resetView() {
    state.expandedNodes = new Set();
    state.openNodes = new Set();
    state.manualPositions = new Map();
    state.manualSizes = new Map();
    state.focusedNodeId = null;
    void renderGraph({ fit: true });
    closeMenus();
    logStatus('view reset');
  }

  function autoArrangeView() {
    state.manualPositions = new Map();
    void renderGraph({ fit: true });
    closeMenus();
    logStatus('auto-arranged visible graph');
  }

  function updateViewToggles() {
    const panel = els.canvasPanel;
    if (panel) panel.classList.toggle('grid-hidden', !state.showGrid);
    if (els.toggleGridBtn) els.toggleGridBtn.textContent = `Grid: ${state.showGrid ? 'On' : 'Off'}`;
    if (els.toggleMinimapBtn) els.toggleMinimapBtn.textContent = `Minimap: ${state.showMinimap ? 'On' : 'Off'}`;
    setOptionalMenuText('toggle-grid-rail-btn', `Grid: ${state.showGrid ? 'On' : 'Off'}`);
    setOptionalMenuText('toggle-minimap-rail-btn', `Minimap: ${state.showMinimap ? 'On' : 'Off'}`);
    renderMinimap();
  }

  function toggleGrid() {
    state.showGrid = !state.showGrid;
    updateViewToggles();
    closeMenus();
    logStatus(`grid ${state.showGrid ? 'shown' : 'hidden'}`);
  }

  function toggleMinimap() {
    state.showMinimap = !state.showMinimap;
    updateViewToggles();
    closeMenus();
    logStatus(`minimap ${state.showMinimap ? 'shown' : 'hidden'}`);
  }

  function focusSelectedNode() {
    const node = selectedNode();
    if (!node) {
      logStatus('select a node before focusing');
      return;
    }
    state.focusedNodeId = node.id;
    void renderGraph({ fit: true });
    closeMenus();
    logStatus(`focused ${node.name}`);
  }

  function clearFocus() {
    state.focusedNodeId = null;
    void renderGraph({ fit: true });
    closeMenus();
    logStatus('cleared focus');
  }

  function pinSelectedNode() {
    const node = selectedNode();
    if (!node) {
      logStatus('select a node before pinning');
      return;
    }
    state.openNodes.add(node.id);
    void renderGraph();
    closeMenus();
    logStatus(`pinned ${node.name}`);
  }

  function unpinAllNodes() {
    state.openNodes = new Set();
    void renderGraph();
    closeMenus();
    logStatus('unpinned all nodes');
  }

  function collapseAllNodes() {
    state.expandedNodes = new Set();
    void renderGraph();
    closeMenus();
    logStatus('collapsed all calls');
  }

  function fitView() {
    if (!els.graphShell.clientWidth || !els.graphShell.clientHeight) return;
    const scaleX = els.graphShell.clientWidth / Math.max(1, state.surfaceWidth);
    const scaleY = els.graphShell.clientHeight / Math.max(1, state.surfaceHeight);
    state.zoom = clampZoom(Math.min(1, scaleX, scaleY));
    applyZoom();
    els.graphShell.scrollTo({
      left: Math.max(0, (state.surfaceWidth * state.zoom - els.graphShell.clientWidth) / 2),
      top: Math.max(0, (state.surfaceHeight * state.zoom - els.graphShell.clientHeight) / 2),
      behavior: 'smooth'
    });
    updateMinimapViewport();
  }

  function installDragPan() {
    let dragging = false;
    let startX = 0;
    let startY = 0;
    let scrollLeft = 0;
    let scrollTop = 0;
    els.graphShell.addEventListener('mousedown', (event) => {
      if (event.target.closest('.node')) return;
      dragging = true;
      startX = event.clientX;
      startY = event.clientY;
      scrollLeft = els.graphShell.scrollLeft;
      scrollTop = els.graphShell.scrollTop;
    });
    window.addEventListener('mousemove', (event) => {
      if (!dragging) return;
      els.graphShell.scrollLeft = scrollLeft - (event.clientX - startX);
      els.graphShell.scrollTop = scrollTop - (event.clientY - startY);
    });
    window.addEventListener('mouseup', () => {
      dragging = false;
    });
    els.graphShell.addEventListener('wheel', (event) => {
      if (!event.ctrlKey && !event.metaKey && !event.altKey) return;
      event.preventDefault();
      const factor = Math.exp(-event.deltaY * 0.0012);
      setZoom(state.zoom * factor, event);
    }, { passive: false });
    els.graphShell.addEventListener('scroll', () => updateMinimapViewport());
  }

  function installKeyboard() {
    window.addEventListener('keydown', (event) => {
      const targetTag = document.activeElement && document.activeElement.tagName;
      const editing = targetTag === 'TEXTAREA' || targetTag === 'INPUT' || targetTag === 'SELECT';
      if (event.key === 'Escape') {
        if (editing) {
          document.activeElement.blur();
        } else if (!exitGroup()) {
          void renderGraph();
        }
        return;
      }
      if (editing) return;
      if (event.key === 'Tab') {
        event.preventDefault();
        enterSelectedGroup();
      } else if (event.key === 'Enter') {
        const node = selectedNode();
        if (node && directCalleeIds(node.id).length) {
          toggleExpand(node.id);
        }
      }
    });
  }

  function installWorkspacePanels() {
    PANEL_IDS.forEach((panelId) => {
      const panel = panelElement(panelId);
      if (!panel) return;
      panel.addEventListener('mousedown', () => setActivePanel(panelId));
      panel.addEventListener('focusin', () => setActivePanel(panelId));
    });
    setActivePanel(state.activePanelId);
  }

  async function bootstrap() {
    const resp = await hostCall('otterBootstrap', {});
    state.host = resp.host || 'web';
    state.supportsFolderPicker = !!resp.supportsFolderPicker;
    state.supportsCodexSend = !!resp.supportsCodexSend;
    state.repoRoot = resp.defaultRepoRoot || '';
    els.repoRoot.value = state.repoRoot;
    els.chooseBtn.style.display = state.supportsFolderPicker ? 'inline-flex' : 'none';
    els.hostPill.textContent = state.host;
    logStatus(`host ready: ${state.host}`);
  }

  els.analyzeBtn.addEventListener('click', analyzeRepo);
  els.chooseBtn.addEventListener('click', chooseFolder);
  els.openRepoBtn.addEventListener('click', () => {
    void chooseFolder({ analyze: true });
  });
  els.resetBtn.addEventListener('click', resetView);
  els.autoLayoutBtn.addEventListener('click', autoArrangeView);
  els.toggleGridBtn.addEventListener('click', toggleGrid);
  els.toggleMinimapBtn.addEventListener('click', toggleMinimap);
  els.focusSelectedBtn.addEventListener('click', focusSelectedNode);
  els.clearFocusBtn.addEventListener('click', clearFocus);
  els.pinSelectedBtn.addEventListener('click', pinSelectedNode);
  els.unpinAllBtn.addEventListener('click', unpinAllNodes);
  els.saveViewBtn.addEventListener('click', saveGraphView);
  els.loadViewBtn.addEventListener('click', () => {
    void loadSelectedGraphView();
  });
  els.deleteViewBtn.addEventListener('click', deleteSelectedGraphView);
  els.exportGraphBtn.addEventListener('click', exportGraphJson);
  els.exportViewBtn.addEventListener('click', exportViewJson);
  els.nodeSearch.addEventListener('keydown', (event) => {
    if (event.key !== 'Enter') return;
    event.preventDefault();
    searchNodes();
  });
  if (els.canvasSearch) {
    els.canvasSearch.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter') return;
      event.preventDefault();
      searchNodes({
        input: els.canvasSearch,
        filter: els.canvasSearchFilter?.value || 'functions'
      });
    });
  }
  if (els.canvasSearchFilter) {
    els.canvasSearchFilter.addEventListener('change', () => {
      if (!els.canvasSearch?.value.trim()) return;
      searchNodes({
        input: els.canvasSearch,
        filter: els.canvasSearchFilter.value || 'functions'
      });
    });
  }
  els.zoomOutBtn.addEventListener('click', () => setZoom(state.zoom / 1.2));
  els.zoomInBtn.addEventListener('click', () => setZoom(state.zoom * 1.2));
  els.fitBtn.addEventListener('click', () => {
    fitView();
    closeMenus();
  });
  els.clearExpandBtn.addEventListener('click', collapseAllNodes);
  bindOptionalClick('fit-rail-btn', () => {
    fitView();
    closeMenus();
  });
  bindOptionalClick('auto-layout-rail-btn', autoArrangeView);
  bindOptionalClick('reset-rail-btn', resetView);
  bindOptionalClick('toggle-grid-rail-btn', toggleGrid);
  bindOptionalClick('toggle-minimap-rail-btn', toggleMinimap);
  bindOptionalClick('focus-selected-rail-btn', focusSelectedNode);
  bindOptionalClick('clear-focus-rail-btn', clearFocus);
  bindOptionalClick('pin-selected-rail-btn', pinSelectedNode);
  bindOptionalClick('unpin-all-rail-btn', unpinAllNodes);
  bindOptionalClick('clear-expand-rail-btn', collapseAllNodes);
  els.queueNoteBtn.addEventListener('click', queueNote);
  els.runBtn.addEventListener('click', runSelectedNode);
  els.sendNotesBtn.addEventListener('click', sendNotes);
  els.clearNotesBtn.addEventListener('click', () => {
    state.notes = [];
    renderNotes();
  });
  els.bottomToggleBtn.addEventListener('click', () => {
    setBottomCollapsed(!state.bottomCollapsed);
  });
  els.newWindowBtn.addEventListener('click', openActivePanelWindow);
  els.newVerticalPanelBtn.addEventListener('click', () => setWorkspaceOrientation('vertical'));
  els.newHorizontalPanelBtn.addEventListener('click', () => setWorkspaceOrientation('stacked'));
  els.closePanelBtn.addEventListener('click', closeActivePanel);

  installWorkspacePanels();
  refreshViewSelect();
  updateViewToggles();
  installDragPan();
  installKeyboard();
  renderSummary();
  renderSelectedMeta();
  renderNotes();
  renderRunOutput();

  function graphViewportInsets() {
    const compact = window.matchMedia('(max-width: 1180px)').matches;
    const narrow = window.matchMedia('(max-width: 860px)').matches;
    if (narrow) {
      return { left: 72, top: 154, right: 28, bottom: 32 };
    }
    if (compact) {
      return { left: 68, top: 112, right: 36, bottom: 32 };
    }
    return { left: 92, top: 124, right: 52, bottom: 36 };
  }

  function graphViewBounds(view = state.currentView) {
    if (!view?.positions?.size) return null;
    let minX = Infinity;
    let minY = Infinity;
    let maxRight = 0;
    let maxBottom = 0;
    for (const [nodeId, pos] of view.positions.entries()) {
      const scale = state.openNodes.has(nodeId) ? 2 : 1;
      minX = Math.min(minX, pos.x);
      minY = Math.min(minY, pos.y);
      maxRight = Math.max(maxRight, pos.x + pos.width * scale);
      maxBottom = Math.max(maxBottom, pos.y + pos.height * scale);
    }
    if (!Number.isFinite(minX) || !Number.isFinite(minY)) return null;
    return {
      minX,
      minY,
      maxRight,
      maxBottom,
      width: Math.max(0, maxRight - minX),
      height: Math.max(0, maxBottom - minY)
    };
  }

  async function centerAutoPositions(positions, token) {
    if (!positions.size || !els.graphShell) return;
    let minX = Infinity;
    let minY = Infinity;
    let maxX = 0;
    let maxY = 0;
    let index = 0;
    for (const pos of positions.values()) {
      if (token !== state.renderToken) return;
      minX = Math.min(minX, pos.x);
      minY = Math.min(minY, pos.y);
      maxX = Math.max(maxX, pos.x + pos.width);
      maxY = Math.max(maxY, pos.y + pos.height);
      index += 1;
      if (index % 450 === 0) await nextFrame();
    }
    const graphWidth = maxX - minX;
    const graphHeight = maxY - minY;
    const scale = Math.max(state.zoom, 0.01);
    const insets = graphViewportInsets();
    const availableWidth = Math.max(0, els.graphShell.clientWidth / scale - insets.left - insets.right);
    const availableHeight = Math.max(0, els.graphShell.clientHeight / scale - insets.top - insets.bottom);
    const targetX = Math.max(insets.left, insets.left + (availableWidth - graphWidth) / 2);
    const targetY = Math.max(insets.top, insets.top + (availableHeight - graphHeight) / 2);
    const dx = targetX - minX;
    const dy = targetY - minY;
    index = 0;
    for (const pos of positions.values()) {
      if (token !== state.renderToken) return;
      pos.x += dx;
      pos.y += dy;
      index += 1;
      if (index % 450 === 0) await nextFrame();
    }
  }

  function syncGraphSurface(view) {
    const bounds = graphViewBounds(view) || view.bounds || { maxRight: 0, maxBottom: 0 };
    view.bounds = bounds;
    const width = Math.max(els.graphShell.clientWidth, (bounds.maxRight || 0) + 160, 800);
    const height = Math.max(els.graphShell.clientHeight, (bounds.maxBottom || 0) + 160, 600);
    state.surfaceWidth = width;
    state.surfaceHeight = height;
    els.graphCanvas.style.width = `${width}px`;
    els.graphCanvas.style.height = `${height}px`;
    els.graphCanvas.style.minHeight = `${height}px`;
    els.graphEdges.setAttribute('width', String(width));
    els.graphEdges.setAttribute('height', String(height));
    els.graphEdges.style.width = `${width}px`;
    els.graphEdges.style.height = `${height}px`;
    applyZoom();
    renderMinimap(view);
  }

  function fitView() {
    if (!els.graphShell.clientWidth || !els.graphShell.clientHeight) return;
    const scaleX = els.graphShell.clientWidth / Math.max(1, state.surfaceWidth);
    const scaleY = els.graphShell.clientHeight / Math.max(1, state.surfaceHeight);
    state.zoom = clampZoom(Math.min(1, scaleX, scaleY));
    applyZoom();
    const bounds = graphViewBounds();
    let left = Math.max(0, (state.surfaceWidth * state.zoom - els.graphShell.clientWidth) / 2);
    let top = Math.max(0, (state.surfaceHeight * state.zoom - els.graphShell.clientHeight) / 2);
    if (bounds) {
      left = Math.max(0, ((bounds.minX + bounds.maxRight) * state.zoom) / 2 - els.graphShell.clientWidth / 2);
      top = Math.max(0, ((bounds.minY + bounds.maxBottom) * state.zoom) / 2 - els.graphShell.clientHeight / 2);
    }
    els.graphShell.scrollTo({
      left,
      top,
      behavior: 'smooth'
    });
    updateMinimapViewport();
  }

  bootstrap().then(async () => {
    await loadWorkspaceSettings(state.repoRoot);
    await analyzeRepo({ skipWorkspaceLoad: true });
  });
})();
