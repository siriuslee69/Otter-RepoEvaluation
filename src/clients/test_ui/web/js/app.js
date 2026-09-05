const $ = (selector, root = document) => root.querySelector(selector);
let catalog = [];
let groups = [];
let selectedMenu = "all";
let selectedFilter = "all";
const states = new Map();
const selections = new Map();
const sequences = new Map();
const selectedGroups = new Set();
let resultsPath = "";
let pollBusy = false;
let selectionAnchor = -1;
let currentFailure = null;
let availableFlags = [];
let selectedFlags = [];
let flagsConfirmed = false;
let heartbeatTimer = 0;

function binding(name, value) {
  if (typeof window[name] === "function") return window[name](value);
  if (typeof window.webui?.[name] === "function") return window.webui[name](value);
  if (typeof window.webui?.call === "function") return window.webui.call(name, value);
  throw new Error(`WebUI binding unavailable: ${name}`);
}

async function request(payload) {
  const response = JSON.parse(await binding("otterUiAction", JSON.stringify(payload)));
  if (!response.ok) throw new Error(response.error || "Otter test action failed");
  return response;
}

async function heartbeat() {
  const response = JSON.parse(await binding("otterUiHeartbeat", "{}"));
  if (!response.ok) throw new Error("Otter Test UI heartbeat failed");
}

function startHeartbeat() {
  if (heartbeatTimer) return;
  heartbeatTimer = window.setInterval(() => {
    heartbeat().catch(error => setStatus(error.message));
  }, 500);
}

function setStatus(message) { $("[data-status]").textContent = message; }
function setPathStatus(message, failed = false) {
  const state = $("[data-path-state]");
  state.textContent = message;
  state.style.color = failed ? "var(--bad)" : "";
}
function updateFlagCount() {
  $(`[data-flag-count]`).textContent = String(selectedFlags.length);
}
function groupKey(entry) { return `${entry.menu}\u0000${entry.testName}`; }
function selectedEntries(group) {
  if (!group.tabbed) return group.entries;
  return [group.entries.find(entry => entry.id === selections.get(group.key)) || group.entries[0]];
}
function selectedEntry(group) { return selectedEntries(group)[0]; }
function active(state) { return ["queued", "running"].includes(state?.status); }
function visibleGroups() { return groups.filter(group => !group.panel.hidden); }
function matches(group) {
  const entry = selectedEntry(group);
  const menuMatch = selectedMenu === "all" || group.menu === selectedMenu;
  const filterMatch = selectedFilter === "all" || group.entries.some(item => item.filters.includes(selectedFilter));
  return menuMatch && filterMatch && Boolean(entry);
}

function buildGroups() {
  const map = new Map();
  catalog.forEach(entry => {
    const key = groupKey(entry);
    if (!map.has(key)) map.set(key, { key, menu: entry.menu, testName: entry.testName, entries: [] });
    map.get(key).entries.push(entry);
  });
  groups = [...map.values()];
  groups.forEach(group => {
    group.tabbed = group.entries.length > 1 && group.entries.every(entry => entry.version.trim().length > 0);
    selections.set(group.key, group.entries[0].id);
  });
}

function createChoiceButton(label, value, selected, action) {
  const button = document.createElement("button");
  button.type = "button";
  button.textContent = label;
  button.dataset.value = value;
  button.classList.toggle("is-active", selected);
  button.addEventListener("click", action);
  return button;
}

function updateSelectionControls() {
  const selectedCount = selectedGroups.size;
  $("[data-deselect]").hidden = selectedCount === 0;
  $("[data-run-label]").textContent = selectedCount > 0 ? `Run selected (${selectedCount})` : "Run visible";
  groups.forEach(group => {
    const selected = selectedGroups.has(group.key);
    group.panel.classList.toggle("is-selected", selected);
    $("[data-card-select]", group.panel).checked = selected;
  });
}

function selectRange(group, additive) {
  const visible = visibleGroups();
  const current = visible.indexOf(group);
  let start = selectionAnchor;
  let i = 0;
  if (current < 0) return;
  if (start < 0 || start >= visible.length) start = current;
  if (!additive) selectedGroups.clear();
  i = Math.min(start, current);
  while (i <= Math.max(start, current)) {
    selectedGroups.add(visible[i].key);
    i += 1;
  }
}

function selectGroup(group, event) {
  const visible = visibleGroups();
  const current = visible.indexOf(group);
  const additive = event.ctrlKey || event.metaKey;
  if (event.shiftKey) selectRange(group, additive);
  else if (additive) {
    if (selectedGroups.has(group.key)) selectedGroups.delete(group.key);
    else selectedGroups.add(group.key);
    selectionAnchor = current;
  } else {
    const alreadySelected = selectedGroups.size === 1 && selectedGroups.has(group.key);
    selectedGroups.clear();
    if (!alreadySelected) selectedGroups.add(group.key);
    selectionAnchor = alreadySelected ? -1 : current;
  }
  updateSelectionControls();
}

function deselectAll() {
  selectedGroups.clear();
  selectionAnchor = -1;
  updateSelectionControls();
}

async function copyCardValue(button, value) {
  await writeClipboard(value, "Value");
  button.classList.add("is-copied");
  window.setTimeout(() => button.classList.remove("is-copied"), 900);
}

function createNavigation() {
  const menus = ["all", ...new Set(catalog.map(entry => entry.menu))];
  const filters = ["all", ...new Set(catalog.flatMap(entry => entry.filters))];
  menus.forEach(menu => $("[data-menus]").append(createChoiceButton(menu === "all" ? "All tests" : menu, menu, menu === "all", () => {
    selectedMenu = menu; refresh();
  })));
  filters.forEach(filter => $("[data-filters]").append(createChoiceButton(filter === "all" ? "All filters" : filter, filter, filter === "all", () => {
    selectedFilter = filter; refresh();
  })));
}

function stateLabel(state) {
  if (!state) return "not run";
  const labels = { queued: "waiting for worker", running: "compiling or running", pass: "test passed", fail: `failed with exit ${state.exitCode}`, stopped: "test stopped" };
  return labels[state.status] || state.status;
}

function groupState(group) {
  const entries = selectedEntries(group);
  const values = entries.map(entry => states.get(entry.id)).filter(Boolean);
  if (values.length === 0) return null;
  let status = values[0].status;
  if (values.some(active)) status = values.some(state => state.status === "running") ? "running" : "queued";
  else if (values.every(state => state.status === "pass")) status = "pass";
  else if (values.some(state => state.status === "fail")) status = "fail";
  else if (values.some(state => state.status === "stopped")) status = "stopped";
  return {
    status,
    exitCode: values.find(state => state.exitCode)?.exitCode || 0,
    durationMs: values.reduce((sum, state) => sum + (state.durationMs || 0), 0),
    compileDurationMs: values.reduce((sum, state) => sum + (state.compileDurationMs || 0), 0),
    runDurationMs: values.reduce((sum, state) => sum + (state.runDurationMs || 0), 0),
    logPath: values.map(state => state.logPath).filter(Boolean).join(" | "),
  };
}

function durationLabel(state) {
  if (!state) return "-- ms";
  return `${state.runDurationMs || 0} ms run · ${state.compileDurationMs || 0} ms compile`;
}

function versionGlyph(state) {
  const glyphs = { queued: "•", running: "●", pass: "✓", fail: "×", stopped: "■" };
  return glyphs[state?.status] || "◇";
}

function updateVersionTabs(group) {
  if (!group.tabbed) return;
  group.entries.forEach(entry => {
    const button = group.panel.querySelector(`[data-value="${entry.id}"]`);
    const state = states.get(entry.id);
    button.className = `${button.dataset.value === selections.get(group.key) ? "is-active " : ""}is-${state?.status || "idle"}`;
    $(".version-glyph", button).textContent = versionGlyph(state);
  });
}

function updatePanel(group) {
  const panel = group.panel;
  const entries = selectedEntries(group);
  const entry = entries[0];
  const state = groupState(group);
  panel.className = `panel glass is-${state?.status || "idle"}${selectedGroups.has(group.key) ? " is-selected" : ""}`;
  panel.dataset.entryId = entry.id;
  $(".badge", panel).textContent = (state?.status || "idle").toUpperCase();
  $("[data-source]", panel).textContent = [...new Set(entries.map(item => item.sourcePath))].join(" + ");
  $("[data-routine]", panel).textContent = entries.map(item => item.routine).join(" + ");
  $("[data-result]", panel).textContent = stateLabel(state);
  $("[data-duration]", panel).textContent = durationLabel(state);
  $("[data-log]", panel).textContent = state?.logPath || "";
  const tags = $("[data-tags]", panel);
  tags.replaceChildren();
  [...new Set(entries.flatMap(item => item.filters))].forEach(filter => { const tag = document.createElement("span"); tag.textContent = filter; tags.append(tag); });
  const run = $("[data-panel-run]", panel);
  const sequenceActive = sequences.has(group.key);
  run.innerHTML = active(state) || sequenceActive ? "<span>&#9632;</span> Stop" : "<span>&#9655;</span> Run";
  const failure = selectedEntries(group).map(item => states.get(item.id)).find(item => item?.status === "fail") ||
    group.entries.map(item => states.get(item.id)).find(item => item?.status === "fail");
  const failureLink = $("[data-failure-link]", panel);
  failureLink.hidden = !failure;
  if (failure) $("b", failureLink).textContent = failure.failureMessage || `Test failed with exit ${failure.exitCode}`;
  failureLink.onclick = failure ? event => { event.stopPropagation(); openFailure(group, failure); } : null;
  updateVersionTabs(group);
}

function createPanels() {
  const host = $("[data-catalog]");
  const template = $("[data-panel-template]");
  groups.forEach(group => {
    const panel = template.content.firstElementChild.cloneNode(true);
    group.panel = panel;
    $(".menu-name", panel).textContent = group.menu;
    $("h2", panel).textContent = group.testName;
    if (group.tabbed) {
      group.entries.forEach((entry, index) => {
        const label = entry.version || `Version ${index + 1}`;
        const button = createChoiceButton("", entry.id, index === 0, () => {
          selections.set(group.key, entry.id);
          updatePanel(group);
        });
        const glyph = document.createElement("span");
        const text = document.createElement("span");
        glyph.className = "version-glyph";
        glyph.textContent = "◇";
        text.textContent = label;
        button.append(glyph, text);
        $("[data-versions]", panel).append(button);
      });
    }
    $("[data-panel-run]", panel).addEventListener("click", event => { event.stopPropagation(); toggle(group); });
    $("[data-copy-name]", panel).addEventListener("click", event => {
      event.stopPropagation(); copyCardValue(event.currentTarget, group.testName);
    });
    $("[data-copy-path]", panel).addEventListener("click", event => {
      event.stopPropagation(); copyCardValue(event.currentTarget, selectedEntries(group).map(entry => entry.sourcePath).join(" + "));
    });
    $(".card-select", panel).addEventListener("click", event => {
      event.preventDefault();
      event.stopPropagation();
      if (event.shiftKey) window.getSelection()?.removeAllRanges();
      selectGroup(group, event);
    });
    panel.addEventListener("click", event => {
      if (event.target.closest(".versions, [data-panel-run], [data-failure-link], .card-select, .tiny-copy")) return;
      if (event.shiftKey) {
        event.preventDefault();
        window.getSelection()?.removeAllRanges();
      }
      selectGroup(group, event);
    });
    panel.addEventListener("mousedown", event => { if (event.shiftKey) event.preventDefault(); });
    host.append(panel);
    updatePanel(group);
  });
  updateSelectionControls();
}

function refresh() {
  document.querySelectorAll("[data-menus] button").forEach(button => button.classList.toggle("is-active", button.dataset.value === selectedMenu));
  document.querySelectorAll("[data-filters] button").forEach(button => button.classList.toggle("is-active", button.dataset.value === selectedFilter));
  let visible = 0;
  groups.forEach(group => {
    const show = matches(group);
    group.panel.hidden = !show;
    if (show) visible += 1;
  });
  $("[data-visible-count]").textContent = String(visible);
  $("[data-menu-label]").textContent = (selectedMenu === "all" ? "ALL TESTS" : selectedMenu).toUpperCase();
  updateSelectionControls();
}

async function toggle(group) {
  const running = group.entries.filter(entry => active(states.get(entry.id)));
  if (running.length > 0 || sequences.has(group.key)) {
    sequences.delete(group.key);
    await Promise.all(running.map(entry => request({ action: "stop", id: entry.id })));
    updatePanel(group);
    return;
  }
  await startSequence(group);
}

async function startSequence(group) {
  group.entries.forEach(entry => states.delete(entry.id));
  sequences.set(group.key, { group, index: 0 });
  await startSequenceEntry(sequences.get(group.key));
  updatePanel(group);
}

async function startSequenceEntry(sequence) {
  const entry = sequence.group.entries[sequence.index];
  await request({ action: "start", id: entry.id, resultsPath, flags: selectedFlags });
  states.set(entry.id, { id: entry.id, status: "queued" });
}

async function advanceSequences() {
  for (const [key, sequence] of [...sequences]) {
    const entry = sequence.group.entries[sequence.index];
    const state = states.get(entry.id);
    if (!state || active(state)) continue;
    sequence.index += 1;
    if (sequence.index >= sequence.group.entries.length) {
      sequences.delete(key);
      continue;
    }
    await startSequenceEntry(sequence);
  }
}

function isPendingSequenceState(state) {
  for (const sequence of sequences.values()) {
    const pendingIndex = sequence.group.entries.findIndex(entry => entry.id === state.id);
    if (pendingIndex > sequence.index) return true;
  }
  return false;
}

async function runVisible() {
  const targets = (selectedGroups.size > 0 ? groups.filter(group => selectedGroups.has(group.key)) : groups.filter(matches))
    .filter(group => !sequences.has(group.key));
  await Promise.all(targets.map(startSequence));
  setStatus(`${targets.length} panel sequences launched`);
}

async function poll() {
  if (pollBusy) return;
  pollBusy = true;
  try {
    const response = await request({ action: "poll" });
    response.jobs.forEach(state => {
      if (!isPendingSequenceState(state)) states.set(state.id, state);
    });
    await advanceSequences();
    groups.forEach(updatePanel);
    const activeCount = response.jobs.filter(active).length;
    const passed = response.jobs.filter(state => state.status === "pass").length;
    $("[data-stop-all]").disabled = activeCount === 0 && sequences.size === 0;
    setStatus(activeCount || sequences.size ? `${activeCount} jobs running / ${sequences.size} panel sequences active` : `${passed} tests passed / ready`);
  } catch (error) { setStatus(error.message); }
  finally { pollBusy = false; }
}

async function applyResultsPath(path) {
  const response = await request({ action: "setResultsPath", path });
  resultsPath = response.path;
  $("[data-output-path]").value = resultsPath;
  setPathStatus("logs will be written here");
}

async function chooseResultsPath() {
  setPathStatus("waiting for folder selection");
  const response = await request({ action: "chooseResultsPath" });
  resultsPath = response.path;
  $("[data-output-path]").value = resultsPath;
  setPathStatus("logs will be written here");
}

function bindOutputControls() {
  const input = $("[data-output-path]");
  input.addEventListener("change", () => applyResultsPath(input.value).catch(error => setPathStatus(error.message, true)));
  input.addEventListener("keydown", event => {
    if (event.key === "Enter") { event.preventDefault(); input.blur(); }
  });
  $("[data-pick-output]").addEventListener("click", () => chooseResultsPath().catch(error => setPathStatus(error.message, true)));
}

function failurePayload(group, state) {
  const entry = group.entries.find(item => item.id === state.id) || selectedEntry(group);
  return {
    testName: group.testName,
    menu: group.menu,
    version: entry.version,
    routine: entry.routine,
    message: state.failureMessage || `Test failed with exit ${state.exitCode}`,
    path: state.failurePath || entry.sourcePath,
    line: state.failureLine || entry.line || 0,
    code: state.failureCode || "",
    exitCode: state.exitCode,
    logPath: state.logPath || "",
  };
}

function openFailure(group, state) {
  const dialog = $("[data-failure-dialog]");
  currentFailure = failurePayload(group, state);
  $("[data-failure-title]").textContent = currentFailure.version ? `${currentFailure.testName} / ${currentFailure.version}` : currentFailure.testName;
  $("[data-failure-path]").textContent = currentFailure.path;
  $("[data-failure-line]").textContent = currentFailure.line ? `line ${currentFailure.line}` : "line unavailable";
  $("[data-failure-message]").textContent = currentFailure.message;
  $("[data-failure-code]").textContent = currentFailure.code || "Source context unavailable.";
  $("[data-copy-state]").textContent = "Ready to copy";
  dialog.showModal();
}

function closeFailure() {
  const dialog = $("[data-failure-dialog]");
  if (dialog.open) dialog.close();
}

function plainFailureText(failure) {
  return [
    `Test: ${failure.testName}`,
    `Menu: ${failure.menu}`,
    `Version: ${failure.version || "none"}`,
    `Routine: ${failure.routine}`,
    `Failure: ${failure.message}`,
    `Source: ${failure.path}:${failure.line || "unknown"}`,
    `Exit code: ${failure.exitCode}`,
    `Log: ${failure.logPath || "none"}`,
    "",
    failure.code || "Source context unavailable.",
  ].join("\n");
}

async function writeClipboard(content, label) {
  const state = $("[data-copy-state]");
  try {
    await navigator.clipboard.writeText(content);
    state.textContent = `${label} copied`;
  } catch (error) {
    const input = document.createElement("textarea");
    input.value = content;
    input.style.position = "fixed";
    input.style.opacity = "0";
    document.body.append(input);
    input.select();
    const copied = document.execCommand("copy");
    input.remove();
    state.textContent = copied ? `${label} copied` : `Copy failed: ${error.message}`;
  }
}

function bindFailureDialog() {
  const dialog = $("[data-failure-dialog]");
  $("[data-failure-close]").addEventListener("click", closeFailure);
  $("[data-copy-text]").addEventListener("click", () => {
    if (currentFailure) writeClipboard(plainFailureText(currentFailure), "Plain text");
  });
  $("[data-copy-json]").addEventListener("click", () => {
    if (currentFailure) writeClipboard(JSON.stringify(currentFailure, null, 2), "JSON");
  });
  dialog.addEventListener("click", event => { if (event.target === dialog) closeFailure(); });
  dialog.addEventListener("cancel", () => { currentFailure = null; });
  dialog.addEventListener("close", () => { currentFailure = null; });
}

function selectedFlagValues() {
  return [...document.querySelectorAll(`[data-flag-options] input:checked`)].map(input => input.value);
}

function updateFlagSummary() {
  const pending = selectedFlagValues();
  $(`[data-flag-summary]`).textContent = pending.length === 0 ? "No optional flags" :
    pending.length <= 3 ? pending.join(", ") : `${pending.length} flags selected`;
}

function openFlagDialog() {
  document.querySelectorAll(`[data-flag-options] input`).forEach(input => {
    input.checked = selectedFlags.includes(input.value);
  });
  updateFlagSummary();
  $(`[data-flag-dialog]`).showModal();
}

function bindFlagDialog() {
  const dialog = $(`[data-flag-dialog]`);
  const options = $(`[data-flag-options]`);
  availableFlags.forEach(flag => {
    const label = document.createElement("label");
    const input = document.createElement("input");
    const marker = document.createElement("span");
    const text = document.createElement("b");
    input.type = "checkbox";
    input.value = flag;
    text.textContent = flag;
    input.addEventListener("change", () => {
      if (input.checked && input.value === "gcArc") {
        const other = $(`[data-flag-options] input[value="gcOrc"]`);
        if (other) other.checked = false;
      } else if (input.checked && input.value === "gcOrc") {
        const other = $(`[data-flag-options] input[value="gcArc"]`);
        if (other) other.checked = false;
      }
      updateFlagSummary();
    });
    label.append(input, marker, text);
    options.append(label);
  });
  $(`[data-open-flags]`).addEventListener("click", openFlagDialog);
  $(`[data-clear-flags]`).addEventListener("click", () => {
    document.querySelectorAll(`[data-flag-options] input`).forEach(input => { input.checked = false; });
    updateFlagSummary();
  });
  $(`[data-apply-flags]`).addEventListener("click", () => {
    selectedFlags = selectedFlagValues();
    flagsConfirmed = true;
    updateFlagCount();
    $(`[data-flag-dropdown]`).open = false;
  });
  dialog.addEventListener("cancel", event => {
    if (!flagsConfirmed && availableFlags.length > 0) event.preventDefault();
  });
  updateFlagCount();
  if (availableFlags.length === 0) $(`[data-open-flags]`).disabled = true;
  else openFlagDialog();
}

async function boot() {
  await heartbeat();
  startHeartbeat();
  const payload = JSON.parse(await binding("otterUiBootstrap", "{}"));
  if (!payload.ok) throw new Error(payload.error || "test discovery failed");
  catalog = payload.entries;
  availableFlags = payload.availableFlags || [];
  selectedFlags = payload.defaultFlags || [];
  document.title = `${payload.config.title} / Otter Test UI`;
  $("[data-title]").textContent = payload.config.title;
  $("[data-banner]").textContent = payload.config.banner;
  resultsPath = payload.config.outputPath;
  $("[data-output-path]").value = resultsPath;
  setPathStatus("logs will be written here");
  if (payload.config.customCss) {
    const style = document.createElement("style");
    style.dataset.otterConfig = "";
    style.textContent = payload.config.customCss;
    document.head.append(style);
  }
  buildGroups(); createNavigation(); createPanels(); bindOutputControls(); bindFailureDialog(); bindFlagDialog(); refresh();
  $("[data-run-all]").addEventListener("click", () => runVisible().catch(error => setStatus(error.message)));
  $("[data-deselect]").addEventListener("click", deselectAll);
  $("[data-stop-all]").addEventListener("click", () => {
    sequences.clear();
    request({ action: "stopAll" }).catch(error => setStatus(error.message));
  });
  setStatus(`${catalog.length} pragma tests discovered`);
  await poll();
  setInterval(poll, 500);
}

async function bootWhenWebUiReady() {
  let lastError;
  for (let attempt = 0; attempt < 100; attempt += 1) {
    try {
      await boot();
      return;
    } catch (error) {
      lastError = error;
      await new Promise(resolve => setTimeout(resolve, 50));
    }
  }
  throw lastError || new Error("WebUI bindings did not become ready");
}

bootWhenWebUiReady().catch(error => setStatus(`startup failed: ${error.message}`));
