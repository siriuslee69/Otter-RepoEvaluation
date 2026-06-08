window.OtterWebuiCore = (() => {
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

  function bindOptionalClick(id, handler) {
    const el = document.getElementById(id);
    if (el) el.addEventListener('click', handler);
  }

  function setOptionalMenuText(id, text) {
    const el = document.getElementById(id);
    if (!el) return;
    const label = el.querySelector('.menu-text');
    if (label) label.textContent = text;
    else el.textContent = text;
  }

  return {
    bindOptionalClick,
    downloadJson,
    nextFrame,
    safeFileStem,
    safeParseJson,
    setOptionalMenuText
  };
})();
