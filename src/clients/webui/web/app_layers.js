  const layerUi = {
    panel: document.getElementById('layer-panel'),
    toggle: document.getElementById('layer-panel-toggle'),
    tree: document.getElementById('layer-tree'),
    dropzone: document.getElementById('layer-dropzone'),
    addSelectedBtn: document.getElementById('layer-add-selected-btn'),
    addGroupBtn: document.getElementById('layer-add-group-btn'),
    infoBtn: document.getElementById('layer-info-btn'),
    runBtn: document.getElementById('layer-run-btn'),
    notesBtn: document.getElementById('layer-notes-btn'),
    resizeHandle: document.getElementById('layer-resize-handle'),
    selectionFloat: document.getElementById('selection-float'),
    selectionFloatMeta: document.getElementById('selection-float-meta'),
    selectionFloatAddRefBtn: document.getElementById('selection-float-add-ref-btn'),
    selectionFloatNoteBtn: document.getElementById('selection-float-note-btn'),
    selectionFloatRunBtn: document.getElementById('selection-float-run-btn'),
    runFloat: document.getElementById('run-float'),
    runFloatOutput: document.getElementById('run-float-output'),
    notesFloat: document.getElementById('notes-float'),
    notesFloatList: document.getElementById('notes-float-list'),
    notesFloatSendBtn: document.getElementById('notes-float-send-btn'),
    notesFloatClearBtn: document.getElementById('notes-float-clear-btn'),
    annotationEditor: document.getElementById('annotation-editor'),
    annotationEditorTitle: document.getElementById('annotation-editor-title'),
    annotationEditorInput: document.getElementById('annotation-editor-input'),
    annotationEditorSaveBtn: document.getElementById('annotation-editor-save-btn'),
    annotationEditorCancelBtn: document.getElementById('annotation-editor-cancel-btn'),
    annotationPreview: document.getElementById('annotation-preview')
  };

  state.tabPathIds = state.tabPathIds || [];
  state.activeScopeIds = null;
  state.layerItems = state.layerItems || [];
  state.layerSeq = state.layerSeq || 0;
  state.layerSelectedItemId = state.layerSelectedItemId || '';
  state.layerPanelOpen = !!state.layerPanelOpen;
  state.layerPanelWidth = state.layerPanelWidth || 296;
  state.layerPanelHeight = state.layerPanelHeight || 420;
  state.layerAnnotationTarget = null;
  state.annotationPreviewLock = false;
  state.floatingPanels = state.floatingPanels || { selection: false, run: false, notes: false };
  state.nestedCallCache = new Map();

  function nextLayerId(prefix = 'layer') {
    state.layerSeq += 1;
    return `${prefix}-${state.layerSeq}`;
  }

  function prefixGroupKey(name) {
    const text = String(name || '');
    for (let i = 1; i < text.length; i += 1) {
      const c = text[i];
      if (c >= 'A' && c <= 'Z') return text.slice(0, i).toLowerCase();
    }
    return text.toLowerCase() || 'misc';
  }

  function descendantIdsFrom(nodeId) {
    const seen = new Set();
    const queue = [nodeId];
    while (queue.length) {
      const currentId = queue.shift();
      if (seen.has(currentId)) continue;
      seen.add(currentId);
      directCalleeIds(currentId).forEach((childId) => queue.push(childId));
    }
    return seen;
  }

  function pathWithin(startId, targetId) {
    if (startId === targetId) return [startId];
    const queue = [{ id: startId, path: [startId] }];
    const seen = new Set([startId]);
    while (queue.length) {
      const item = queue.shift();
      const children = directCalleeIds(item.id);
      for (let i = 0; i < children.length; i += 1) {
        const childId = children[i];
        if (seen.has(childId)) continue;
        const nextPath = [...item.path, childId];
        if (childId === targetId) return nextPath;
        seen.add(childId);
        queue.push({ id: childId, path: nextPath });
      }
    }
    return null;
  }

  function nestedCallCount(nodeId) {
    if (state.nestedCallCache.has(nodeId)) return state.nestedCallCache.get(nodeId);
    const ids = descendantIdsFrom(nodeId);
    ids.delete(nodeId);
    directCalleeIds(nodeId).forEach((childId) => ids.delete(childId));
    const count = ids.size;
    state.nestedCallCache.set(nodeId, count);
    return count;
  }

  function nodeDisplaySize(node) {
    const inputs = inputSockets(node).length;
    const outputs = outputSockets(node).length;
    const rows = Math.max(inputs, outputs, 1);
    const direct = directCalleeIds(node.id).length;
    const nested = nestedCallCount(node.id);
    const callWeight = direct * 10 + nested * 5;
    return {
      width: NODE_WIDTH + Math.min(128, callWeight),
      height: 68 + rows * 12 + Math.min(96, direct * 8 + nested * 5),
      direct,
      nested
    };
  }

  function nodeHeight(node) {
    return nodeDisplaySize(node).height;
  }

  async function computeLayout(nodes, token) {
    const groups = new Map();
    for (let i = 0; i < nodes.length; i += 1) {
      if (token !== state.renderToken) return null;
      const node = nodes[i];
      const key = prefixGroupKey(node.name) || node.modulePath || node.sourcePath || 'misc';
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(node);
      if ((i + 1) % 350 === 0) await nextFrame();
    }

    const groupItems = [...groups.entries()].sort((a, b) => a[0].localeCompare(b[0]));
    const positions = new Map();
    const groupGapX = 110;
    const groupGapY = 92;
    const nodeGapX = 22;
    const nodeGapY = 20;
    const columns = Math.max(1, Math.ceil(Math.sqrt(groupItems.length || 1)));
    let cursorX = 80;
    let cursorY = 80;
    let rowHeight = 0;

    for (let groupIndex = 0; groupIndex < groupItems.length; groupIndex += 1) {
      if (token !== state.renderToken) return null;
      const [groupKey, groupNodes] = groupItems[groupIndex];
      const sorted = groupNodes.sort(compareNodes);
      const sizes = sorted.map((node) => nodeDisplaySize(node));
      const nodeCols = Math.max(1, Math.ceil(Math.sqrt(sorted.length)));
      const nodeRows = Math.max(1, Math.ceil(sorted.length / nodeCols));
      const maxNodeWidth = sizes.reduce((max, size) => Math.max(max, size.width), NODE_WIDTH);
      const maxNodeHeight = sizes.reduce((max, size) => Math.max(max, size.height), 66);
      const clusterWidth = nodeCols * maxNodeWidth + Math.max(0, nodeCols - 1) * nodeGapX;
      const clusterHeight = nodeRows * maxNodeHeight + Math.max(0, nodeRows - 1) * nodeGapY;

      if (groupIndex > 0 && groupIndex % columns === 0) {
        cursorX = 80;
        cursorY += rowHeight + groupGapY;
        rowHeight = 0;
      }

      for (let nodeIndex = 0; nodeIndex < sorted.length; nodeIndex += 1) {
        if (token !== state.renderToken) return null;
        const node = sorted[nodeIndex];
        const size = sizes[nodeIndex];
        const col = nodeIndex % nodeCols;
        const row = Math.floor(nodeIndex / nodeCols);
        positions.set(node.id, {
          x: cursorX + col * (maxNodeWidth + nodeGapX),
          y: cursorY + row * (maxNodeHeight + nodeGapY),
          width: size.width,
          height: size.height,
          modulePath: groupKey
        });
        if ((nodeIndex + 1) % 350 === 0) await nextFrame();
      }

      cursorX += clusterWidth + groupGapX;
      rowHeight = Math.max(rowHeight, clusterHeight);
      await nextFrame();
    }

    return positions;
  }

  function activePathText() {
    if (state.tabPathIds.length) {
      const names = state.tabPathIds
        .map((id) => state.functionById.get(id)?.name)
        .filter(Boolean);
      if (names.length) return `active: ${names.join('/')}/`;
    }
    const node = selectedNode();
    return node ? `active: ${node.name}` : 'active: none';
  }

  function renderBreadcrumbs() {
    if (!els.breadcrumbs) return;
    els.breadcrumbs.textContent = activePathText();
  }

  function updateActiveScope() {
    state.activeScopeIds = null;
    if (!state.tabPathIds.length) return;
    const rootId = state.tabPathIds[state.tabPathIds.length - 1];
    state.activeScopeIds = descendantIdsFrom(rootId);
  }

  function createLayerNodeRef(nodeId) {
    return {
      id: nextLayerId('node'),
      kind: 'node',
      nodeId,
      annotation: ''
    };
  }

  function createLayerGroup(name = 'Group') {
    return {
      id: nextLayerId('group'),
      kind: 'group',
      name,
      annotation: '',
      items: []
    };
  }

  function findLayerItem(items, itemId, parent = null, parentList = state.layerItems) {
    for (let i = 0; i < items.length; i += 1) {
      const item = items[i];
      if (item.id === itemId) return { item, index: i, parent, parentList };
      if (item.kind === 'group') {
        const nested = findLayerItem(item.items || [], itemId, item, item.items);
        if (nested) return nested;
      }
    }
    return null;
  }

  function moveLayerItem(itemId, targetGroupId = '') {
    const located = findLayerItem(state.layerItems, itemId);
    if (!located) return;
    located.parentList.splice(located.index, 1);
    if (!targetGroupId) {
      state.layerItems.push(located.item);
      return;
    }
    const target = findLayerItem(state.layerItems, targetGroupId);
    if (!target || target.item.kind !== 'group') {
      state.layerItems.push(located.item);
      return;
    }
    target.item.items.push(located.item);
  }

  function pushLayerNode(nodeId, targetGroupId = '') {
    const entry = createLayerNodeRef(nodeId);
    if (!targetGroupId) {
      state.layerItems.push(entry);
      return;
    }
    const target = findLayerItem(state.layerItems, targetGroupId);
    if (!target || target.item.kind !== 'group') {
      state.layerItems.push(entry);
      return;
    }
    target.item.items.push(entry);
  }

  function showAnnotationPreview(text) {
    if (!layerUi.annotationPreview || !text) return;
    layerUi.annotationPreview.textContent = text;
    layerUi.annotationPreview.classList.remove('hidden');
  }

  function hideAnnotationPreview() {
    if (!layerUi.annotationPreview || state.annotationPreviewLock) return;
    layerUi.annotationPreview.classList.add('hidden');
  }

  function openAnnotationEditor(target) {
    state.layerAnnotationTarget = target;
    if (!layerUi.annotationEditor || !layerUi.annotationEditorInput) return;
    let text = '';
    let title = 'Annotation';
    if (target.kind === 'selected-node') {
      const existing = state.notes.find((note) => note.functionId === target.nodeId);
      text = existing?.note || '';
      title = `Annotation: ${state.functionById.get(target.nodeId)?.name || 'node'}`;
    } else {
      const located = findLayerItem(state.layerItems, target.itemId);
      text = located?.item?.annotation || '';
      title = located?.item?.kind === 'group'
        ? `Group: ${located.item.name || 'group'}`
        : `Reference: ${state.functionById.get(located?.item?.nodeId)?.name || 'node'}`;
    }
    layerUi.annotationEditorTitle.textContent = title;
    layerUi.annotationEditorInput.value = text;
    layerUi.annotationEditor.classList.remove('hidden');
    layerUi.annotationEditorInput.focus();
  }

  function saveAnnotationEditor() {
    if (!state.layerAnnotationTarget || !layerUi.annotationEditorInput) return;
    const text = layerUi.annotationEditorInput.value.trim();
    const target = state.layerAnnotationTarget;
    if (target.kind === 'selected-node') {
      const node = state.functionById.get(target.nodeId);
      if (!node) return;
      const existing = state.notes.find((note) => note.functionId === target.nodeId);
      if (existing) {
        existing.note = text;
      } else if (text) {
        state.notes.push({
          functionId: node.id,
          name: node.name,
          sourcePath: node.sourcePath,
          lineStart: node.lineStart,
          note: text
        });
      }
      if (existing && !text) {
        state.notes = state.notes.filter((note) => note.functionId !== target.nodeId);
      }
      renderNotes();
    } else {
      const located = findLayerItem(state.layerItems, target.itemId);
      if (located?.item) {
        located.item.annotation = text;
        renderLayerPanel();
      }
    }
    layerUi.annotationEditor.classList.add('hidden');
    state.layerAnnotationTarget = null;
  }

  function syncFloatingPanels() {
    if (layerUi.selectionFloat) layerUi.selectionFloat.classList.toggle('hidden', !state.floatingPanels.selection);
    if (layerUi.runFloat) layerUi.runFloat.classList.toggle('hidden', !state.floatingPanels.run);
    if (layerUi.notesFloat) layerUi.notesFloat.classList.toggle('hidden', !state.floatingPanels.notes);
  }

  function toggleFloatingPanel(key) {
    state.floatingPanels[key] = !state.floatingPanels[key];
    syncFloatingPanels();
  }

  function applyLayerPanelState() {
    if (!layerUi.panel) return;
    layerUi.panel.classList.toggle('is-open', !!state.layerPanelOpen);
    layerUi.panel.style.setProperty('--layer-panel-width', `${state.layerPanelWidth}px`);
    layerUi.panel.style.setProperty('--layer-panel-height', `${state.layerPanelHeight}px`);
  }

  function renderLayerEntries(items, target) {
    items.forEach((item) => {
      if (item.kind === 'group') {
        const wrap = document.createElement('div');
        wrap.className = `layer-group${state.layerSelectedItemId === item.id ? ' is-selected' : ''}`;
        wrap.innerHTML = `
          <div class="layer-group-header">
            <input type="text" value="${escapeHtml(item.name || 'Group')}" aria-label="Group name">
            <div class="layer-entry-actions">
              <button class="action tiny" type="button" data-layer-note="${item.id}">Note</button>
              <button class="action tiny" type="button" data-layer-remove="${item.id}">x</button>
            </div>
          </div>
          <div class="layer-group-body" data-layer-group="${item.id}"></div>
        `;
        const input = wrap.querySelector('input');
        input.addEventListener('input', () => {
          item.name = input.value;
        });
        input.addEventListener('focus', () => {
          state.layerSelectedItemId = item.id;
        });
        const noteBtn = wrap.querySelector(`[data-layer-note="${item.id}"]`);
        const removeBtn = wrap.querySelector(`[data-layer-remove="${item.id}"]`);
        noteBtn.addEventListener('click', () => openAnnotationEditor({ kind: 'layer-item', itemId: item.id }));
        removeBtn.addEventListener('click', () => {
          const found = findLayerItem(state.layerItems, item.id);
          if (!found) return;
          found.parentList.splice(found.index, 1);
          renderLayerPanel();
        });
        if (item.annotation) {
          wrap.addEventListener('mouseenter', () => showAnnotationPreview(item.annotation));
          wrap.addEventListener('mouseleave', hideAnnotationPreview);
        }
        const body = wrap.querySelector('.layer-group-body');
        body.addEventListener('dragover', (event) => {
          event.preventDefault();
          body.classList.add('drag-over');
        });
        body.addEventListener('dragleave', () => body.classList.remove('drag-over'));
        body.addEventListener('drop', (event) => {
          event.preventDefault();
          body.classList.remove('drag-over');
          const raw = event.dataTransfer.getData('text/plain');
          if (!raw) return;
          try {
            const payload = JSON.parse(raw);
            if (payload.kind === 'canvas-node') pushLayerNode(payload.nodeId, item.id);
            if (payload.kind === 'layer-item') moveLayerItem(payload.itemId, item.id);
            renderLayerPanel();
          } catch {
            return;
          }
        });
        renderLayerEntries(item.items || [], body);
        target.appendChild(wrap);
        return;
      }

      const node = state.functionById.get(item.nodeId);
      if (!node) return;
      const row = document.createElement('div');
      row.className = `layer-entry${state.layerSelectedItemId === item.id ? ' is-selected' : ''}`;
      row.draggable = true;
      row.innerHTML = `
        <div class="layer-entry-row">
          <div class="layer-entry-meta">
            <div class="layer-entry-title">${escapeHtml(node.name)}</div>
            <div class="layer-entry-path">${escapeHtml(node.modulePath)}:${escapeHtml(node.lineStart)}</div>
            ${item.annotation ? '<span class="layer-note-badge">note</span>' : ''}
          </div>
          <div class="layer-entry-actions">
            <button class="action tiny" type="button" data-layer-note="${item.id}">Note</button>
            <button class="action tiny" type="button" data-layer-remove="${item.id}">x</button>
          </div>
        </div>
      `;
      row.addEventListener('dragstart', (event) => {
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData('text/plain', JSON.stringify({ kind: 'layer-item', itemId: item.id }));
      });
      row.addEventListener('click', (event) => {
        state.layerSelectedItemId = item.id;
        state.selectedNodeId = node.id;
        renderSelectedMeta();
        renderLayerPanel();
        if (event.ctrlKey) focusLayerNode(node.id);
      });
      row.addEventListener('dblclick', () => openAnnotationEditor({ kind: 'layer-item', itemId: item.id }));
      if (item.annotation) {
        row.addEventListener('mouseenter', () => showAnnotationPreview(item.annotation));
        row.addEventListener('mouseleave', hideAnnotationPreview);
      }
      const noteBtn = row.querySelector(`[data-layer-note="${item.id}"]`);
      const removeBtn = row.querySelector(`[data-layer-remove="${item.id}"]`);
      noteBtn.addEventListener('click', (event) => {
        event.stopPropagation();
        openAnnotationEditor({ kind: 'layer-item', itemId: item.id });
      });
      removeBtn.addEventListener('click', (event) => {
        event.stopPropagation();
        const found = findLayerItem(state.layerItems, item.id);
        if (!found) return;
        found.parentList.splice(found.index, 1);
        renderLayerPanel();
      });
      target.appendChild(row);
    });
  }

  function renderLayerPanel() {
    applyLayerPanelState();
    if (!layerUi.tree) return;
    layerUi.tree.innerHTML = '';
    if (!state.layerItems.length) {
      const empty = document.createElement('div');
      empty.className = 'layer-empty';
      empty.textContent = 'Drag nodes here or add the selected node as a reference.';
      layerUi.tree.appendChild(empty);
      return;
    }
    renderLayerEntries(state.layerItems, layerUi.tree);
  }

  function appendNotesList(target) {
    if (!target) return;
    target.innerHTML = '';
    if (!state.notes.length) {
      const empty = document.createElement('div');
      empty.className = 'layer-empty';
      empty.textContent = 'No queued notes.';
      target.appendChild(empty);
      return;
    }
    state.notes.forEach((note) => {
      const row = document.createElement('div');
      row.className = 'layer-entry';
      row.innerHTML = `
        <div class="layer-entry-row">
          <div class="layer-entry-meta">
            <div class="layer-entry-title">${escapeHtml(note.name)}</div>
            <div class="layer-entry-path">${escapeHtml(note.sourcePath)}:${escapeHtml(note.lineStart)}</div>
            <div class="queued-note-text">${escapeHtml(note.note)}</div>
          </div>
        </div>
      `;
      row.addEventListener('click', (event) => {
        if (event.ctrlKey) {
          focusLayerNode(note.functionId);
          return;
        }
        void revealNode(note.functionId);
      });
      target.appendChild(row);
    });
  }

  function renderNotes() {
    if (els.noteCount) els.noteCount.textContent = String(state.notes.length);
    if (els.queuedNotes) appendNotesList(els.queuedNotes);
    if (layerUi.notesFloatList) appendNotesList(layerUi.notesFloatList);
  }

  function renderRunOutput() {
    let text = 'No function run yet.';
    if (state.lastRun) {
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
      text = lines.join('\n');
    }
    if (els.runOutput) els.runOutput.textContent = text;
    if (layerUi.runFloatOutput) layerUi.runFloatOutput.textContent = text;
  }

  function renderSelectedMeta() {
    const node = selectedNode();
    let text = 'Select a node to inspect its signature, comments, and notes.';
    if (els.selectedRole) els.selectedRole.textContent = 'none';
    if (node) {
      const direct = directCalleeIds(node.id).length;
      const nested = nestedCallCount(node.id);
      const lines = [
        `${node.name} :: ${node.modulePath}`,
        `lines ${node.lineStart}-${node.lineEnd}`,
        node.signature || '',
        '',
        `direct calls: ${direct}`,
        `nested calls: ${nested}`,
        `tags: ${(node.pragmaTags || []).join(', ') || 'none'}`,
        `user input: ${node.handlesUserInput ? node.userInputReason || 'yes' : 'no'}`
      ];
      if ((node.docCommentLines || []).length) {
        lines.push('', 'docs:');
        node.docCommentLines.forEach((line) => lines.push(`  ${line}`));
      }
      text = lines.join('\n');
      if (els.selectedRole) els.selectedRole.textContent = node.role || 'unknown';
    }
    if (els.selectedMeta) els.selectedMeta.textContent = text;
    if (layerUi.selectionFloatMeta) layerUi.selectionFloatMeta.textContent = text;
    renderBreadcrumbs();
    renderLayerPanel();
  }

  function openSelectedNodeAnnotation() {
    const node = selectedNode();
    if (!node) {
      logStatus('select a node first');
      return;
    }
    openAnnotationEditor({ kind: 'selected-node', nodeId: node.id });
  }

  function addSelectedNodeToLayer() {
    const node = selectedNode();
    if (!node) {
      logStatus('select a node first');
      return;
    }
    pushLayerNode(node.id);
    state.layerPanelOpen = true;
    renderLayerPanel();
    logStatus(`added ${node.name} to refs`);
  }

  function revealNode(nodeId) {
    const path = pathToNode(nodeId);
    if (path) path.slice(0, -1).forEach((id) => state.expandedNodes.add(id));
    state.selectedNodeId = nodeId;
    renderSelectedMeta();
    return renderGraph().then(() => scrollToNode(nodeId));
  }

  function focusLayerNode(nodeId) {
    const absolutePath = pathToNode(nodeId) || [nodeId];
    if (absolutePath.length) {
      absolutePath.slice(0, -1).forEach((id) => state.expandedNodes.add(id));
      const currentRootId = state.tabPathIds[state.tabPathIds.length - 1];
      const relativePath = currentRootId ? pathWithin(currentRootId, nodeId) : null;
      state.tabPathIds = relativePath ? [...state.tabPathIds, ...relativePath.slice(1)] : [...absolutePath];
    }
    state.selectedNodeId = nodeId;
    renderSelectedMeta();
    void renderGraph().then(() => scrollToNode(nodeId));
  }

  function enterSelectedGroup(nodeId = state.selectedNodeId) {
    const node = state.functionById.get(nodeId);
    if (!node) return false;
    const absolutePath = pathToNode(nodeId);
    if (absolutePath?.length) absolutePath.slice(0, -1).forEach((id) => state.expandedNodes.add(id));
    if (state.tabPathIds.length) {
      const currentRootId = state.tabPathIds[state.tabPathIds.length - 1];
      const relativePath = pathWithin(currentRootId, nodeId);
      state.tabPathIds = relativePath ? [...state.tabPathIds, ...relativePath.slice(1)] : [nodeId];
    } else {
      state.tabPathIds = [nodeId];
    }
    state.selectedNodeId = nodeId;
    renderSelectedMeta();
    void renderGraph();
    logStatus(`entered ${node.name}`);
    return true;
  }

  function exitGroup() {
    if (state.tabPathIds.length) {
      if (state.tabPathIds.length === 1) {
        state.selectedNodeId = state.tabPathIds[0];
        state.tabPathIds = [];
      } else {
        state.tabPathIds.pop();
        state.selectedNodeId = state.tabPathIds[state.tabPathIds.length - 1];
      }
      renderSelectedMeta();
      void renderGraph();
      return true;
    }
    if (!state.expandedNodes.size) return false;
    state.expandedNodes = new Set();
    void renderGraph();
    logStatus('collapsed all expanded calls');
    return true;
  }

  function clearFocus() {
    state.focusedNodeId = null;
    state.tabPathIds = [];
    renderSelectedMeta();
    void renderGraph();
    closeMenus();
    logStatus('cleared focus');
  }

  function focusSelectedNode() {
    const node = selectedNode();
    if (!node) {
      logStatus('select a node before focusing');
      return;
    }
    enterSelectedGroup(node.id);
  }

  async function tabVisibleGraph(token) {
    const visibleIds = new Set(uniqueSortedNodeIds((state.graph?.functions || []).map((node) => node.id)));
    const edges = [];
    const edgeKeys = new Set();
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

  function visibleGraph(token) {
    if (!state.graph) {
      return Promise.resolve({ nodes: [], edges: [], positions: new Map(), bounds: { minX: 0, minY: 0, maxRight: 0, maxBottom: 0 } });
    }
    if (state.tabPathIds.length) return tabVisibleGraph(token);
    if (state.focusedNodeId) return focusedVisibleGraph(token);
    return rootVisibleGraph(token);
  }

  async function renderEdges(view) {
    const token = ++state.edgeRenderToken;
    els.graphEdges.innerHTML = '';
    const scope = state.activeScopeIds;
    let fragment = document.createDocumentFragment();
    for (let i = 0; i < view.edges.length; i += 1) {
      if (token !== state.edgeRenderToken) return;
      const edge = view.edges[i];
      if (scope && (!scope.has(edge.callerId) || !scope.has(edge.calleeId))) continue;
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
    els.graphEdges.appendChild(fragment);
  }

  function renderNode(node, pos) {
    const card = document.createElement('div');
    const childIds = directCalleeIds(node.id);
    const heldOpen = state.openNodes.has(node.id);
    const nodeKind = nodeKindFor(node.id);
    const stats = nodeDisplaySize(node);
    const ghosted = !!(state.activeScopeIds && !state.activeScopeIds.has(node.id));
    const kindBadge = nodeKind === 'api'
      ? '<span class="node-kind api" data-tooltip="API or endpoint entry point.">API</span>'
      : (nodeKind === 'init'
        ? '<span class="node-kind init" data-tooltip="Initializer visible because an API or endpoint needs its returned state/object.">INIT</span>'
        : '');
    card.className = `node${nodeKind ? ` node-${nodeKind}` : ''}${state.selectedNodeId === node.id ? ' selected' : ''}${heldOpen ? ' open' : ''}${ghosted ? ' node-ghosted' : ''}`;
    card.dataset.nodeId = node.id;
    card.draggable = false;
    card.style.left = `${pos.x}px`;
    card.style.top = `${pos.y}px`;
    card.style.setProperty('--node-width-current', `${pos.width}px`);
    card.style.setProperty('--node-height', `${pos.height}px`);
    card.style.setProperty('--cluster-color', moduleColor(node.modulePath || node.sourcePath || 'unknown'));
    const inputs = inputSockets(node);
    const outputs = outputSockets(node);
    const expanded = state.expandedNodes.has(node.id);
    card.innerHTML = `
      <div class="node-header">
        <div class="node-title-wrap">
          <div class="node-title" data-tooltip="${escapeHtml(`${node.name}\n${node.signature || ''}\nrole: ${node.role || 'unknown'}`)}">${escapeHtml(node.name)}</div>
          <div class="node-subtitle" data-tooltip="${escapeHtml(`${node.sourcePath || node.modulePath}\nlines ${node.lineStart}-${node.lineEnd}`)}">${escapeHtml(node.modulePath)}:${escapeHtml(node.lineStart)}</div>
        </div>
        <div class="node-controls">
          <span class="node-btn node-ref" draggable="true" title="Reference" data-tooltip="${escapeHtml(`Drag ${node.name} into the refs panel.`)}">Ref</span>
          <button class="node-btn node-open" title="${heldOpen ? 'Close node' : 'Keep node open'}" data-tooltip="${heldOpen ? 'Close this pinned-open node.' : 'Keep this node expanded after hover.'}">${heldOpen ? '&minus;' : '&#9633;'}</button>
          <button class="node-btn node-run" title="Run" data-tooltip="${escapeHtml(`Run ${node.name} with generated sample arguments.`)}">&#9654;</button>
          ${childIds.length ? `<button class="node-btn node-expand" title="${expanded ? 'Collapse direct calls' : 'Expand direct calls'}" data-tooltip="${escapeHtml(`${expanded ? 'Collapse' : 'Expand'} ${childIds.length} direct calls.`)}">${expanded ? '&minus;' : '+'}</button>` : ''}
        </div>
      </div>
      <div class="node-body">
        <div class="socket-column inputs">${inputs.map((socket) => socketHtml(socket)).join('')}</div>
        <div class="node-center">
          ${kindBadge}
          <span class="role-badge" data-tooltip="${escapeHtml(`Role: ${node.role || 'unknown'}\nconfidence: ${node.roleConfidence || 'n/a'}`)}">${escapeHtml(node.role || 'unknown')}</span>
          <div class="node-stat-stack">
            <span class="node-stat-chip">${stats.direct} direct calls</span>
            <span class="node-stat-chip">${stats.nested} nested calls</span>
          </div>
        </div>
        <div class="socket-column outputs">${outputs.map((socket) => socketHtml(socket, true)).join('')}</div>
      </div>
      <div class="node-resize"></div>
    `;
    card.addEventListener('mousedown', (event) => startNodeDrag(event, node, card));
    card.addEventListener('mouseenter', (event) => showTooltipText(tooltipFromEvent(event, node), event.clientX, event.clientY));
    card.addEventListener('mousemove', (event) => showTooltipText(tooltipFromEvent(event, node), event.clientX, event.clientY));
    card.addEventListener('mouseleave', hideTooltip);
    card.addEventListener('click', (event) => {
      if (state.suppressNodeClick) return;
      if (event.target.closest('.node-btn')) return;
      state.selectedNodeId = node.id;
      renderSelectedMeta();
      if (event.ctrlKey) focusLayerNode(node.id);
    });
    card.addEventListener('dblclick', () => enterSelectedGroup(node.id));
    const refBtn = card.querySelector('.node-ref');
    if (refBtn) {
      refBtn.addEventListener('dragstart', (event) => {
        event.dataTransfer.effectAllowed = 'copy';
        event.dataTransfer.setData('text/plain', JSON.stringify({ kind: 'canvas-node', nodeId: node.id }));
      });
      refBtn.addEventListener('mousedown', (event) => event.stopPropagation());
    }
    const openBtn = card.querySelector('.node-open');
    if (openBtn) openBtn.addEventListener('click', (event) => {
      event.stopPropagation();
      toggleNodeOpen(node.id, card);
    });
    const runBtn = card.querySelector('.node-run');
    if (runBtn) runBtn.addEventListener('click', (event) => {
      event.stopPropagation();
      state.selectedNodeId = node.id;
      renderSelectedMeta();
      void runSelectedNode();
    });
    const expandBtn = card.querySelector('.node-expand');
    if (expandBtn) expandBtn.addEventListener('click', (event) => {
      event.stopPropagation();
      toggleExpand(node.id);
    });
    const resizeHandle = card.querySelector('.node-resize');
    if (resizeHandle) resizeHandle.addEventListener('mousedown', (event) => startNodeResize(event, node, card));
    return card;
  }

  async function renderGraph(options = {}) {
    const token = ++state.renderToken;
    els.graphCanvas.innerHTML = '';
    els.graphEdges.innerHTML = '';
    updateActiveScope();
    renderBreadcrumbs();
    renderLayerPanel();
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
      if (pos) fragment.appendChild(renderNode(node, pos));
      if ((i + 1) % chunkSize === 0) {
        els.graphCanvas.appendChild(fragment);
        fragment = document.createDocumentFragment();
        await nextFrame();
      }
    }
    els.graphCanvas.appendChild(fragment);
    if (options.fit) fitView(false);
  }

  function installKeyboard() {
    window.addEventListener('keydown', (event) => {
      const targetTag = document.activeElement && document.activeElement.tagName;
      const editing = targetTag === 'TEXTAREA' || targetTag === 'INPUT' || targetTag === 'SELECT';
      if (event.key === 'Escape') {
        if (editing) {
          document.activeElement.blur();
          state.layerAnnotationTarget = null;
          if (layerUi.annotationEditor) layerUi.annotationEditor.classList.add('hidden');
          return;
        }
        if (!exitGroup()) void renderGraph();
        return;
      }
      if (editing) return;
      if (event.key === 'Tab') {
        event.preventDefault();
        if (event.shiftKey) {
          exitGroup();
          return;
        }
        enterSelectedGroup();
        return;
      }
      if (event.key === 'Enter') {
        const node = selectedNode();
        if (!node) return;
        if (directCalleeIds(node.id).length) {
          toggleExpand(node.id);
          return;
        }
        void runSelectedNode();
      }
    });
  }

  function initLayerPanelUi() {
    applyLayerPanelState();
    syncFloatingPanels();
    if (layerUi.toggle) {
      layerUi.toggle.addEventListener('click', () => {
        state.layerPanelOpen = !state.layerPanelOpen;
        applyLayerPanelState();
      });
    }
    if (layerUi.addSelectedBtn) layerUi.addSelectedBtn.addEventListener('click', addSelectedNodeToLayer);
    if (layerUi.addGroupBtn) layerUi.addGroupBtn.addEventListener('click', () => {
      state.layerItems.push(createLayerGroup(`Group ${state.layerItems.length + 1}`));
      state.layerPanelOpen = true;
      renderLayerPanel();
    });
    if (layerUi.infoBtn) layerUi.infoBtn.addEventListener('click', () => toggleFloatingPanel('selection'));
    if (layerUi.runBtn) layerUi.runBtn.addEventListener('click', () => toggleFloatingPanel('run'));
    if (layerUi.notesBtn) layerUi.notesBtn.addEventListener('click', () => toggleFloatingPanel('notes'));
    if (layerUi.selectionFloatAddRefBtn) layerUi.selectionFloatAddRefBtn.addEventListener('click', addSelectedNodeToLayer);
    if (layerUi.selectionFloatNoteBtn) layerUi.selectionFloatNoteBtn.addEventListener('click', openSelectedNodeAnnotation);
    if (layerUi.selectionFloatRunBtn) layerUi.selectionFloatRunBtn.addEventListener('click', () => void runSelectedNode());
    if (layerUi.notesFloatSendBtn) layerUi.notesFloatSendBtn.addEventListener('click', sendNotes);
    if (layerUi.notesFloatClearBtn) layerUi.notesFloatClearBtn.addEventListener('click', () => {
      state.notes = [];
      renderNotes();
    });
    if (layerUi.annotationEditorSaveBtn) layerUi.annotationEditorSaveBtn.addEventListener('click', saveAnnotationEditor);
    if (layerUi.annotationEditorCancelBtn) layerUi.annotationEditorCancelBtn.addEventListener('click', () => {
      state.layerAnnotationTarget = null;
      if (layerUi.annotationEditor) layerUi.annotationEditor.classList.add('hidden');
    });
    if (layerUi.dropzone) {
      layerUi.dropzone.addEventListener('dragover', (event) => {
        event.preventDefault();
        layerUi.dropzone.classList.add('drag-over');
      });
      layerUi.dropzone.addEventListener('dragleave', () => layerUi.dropzone.classList.remove('drag-over'));
      layerUi.dropzone.addEventListener('drop', (event) => {
        event.preventDefault();
        layerUi.dropzone.classList.remove('drag-over');
        const raw = event.dataTransfer.getData('text/plain');
        if (!raw) return;
        try {
          const payload = JSON.parse(raw);
          if (payload.kind === 'canvas-node') pushLayerNode(payload.nodeId);
          if (payload.kind === 'layer-item') moveLayerItem(payload.itemId);
          state.layerPanelOpen = true;
          renderLayerPanel();
        } catch {
          return;
        }
      });
    }
    if (layerUi.resizeHandle && layerUi.panel) {
      layerUi.resizeHandle.addEventListener('mousedown', (event) => {
        event.preventDefault();
        const startWidth = state.layerPanelWidth;
        const startHeight = state.layerPanelHeight;
        const startX = event.clientX;
        const startY = event.clientY;
        const onMove = (moveEvent) => {
          state.layerPanelWidth = Math.max(220, Math.min(420, startWidth - (moveEvent.clientX - startX)));
          state.layerPanelHeight = Math.max(220, Math.min(680, startHeight + (moveEvent.clientY - startY)));
          applyLayerPanelState();
        };
        const onUp = () => {
          window.removeEventListener('mousemove', onMove);
          window.removeEventListener('mouseup', onUp);
        };
        window.addEventListener('mousemove', onMove);
        window.addEventListener('mouseup', onUp);
      });
    }
  }
