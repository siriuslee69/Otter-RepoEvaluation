  initLayerPanelUi();
  renderLayerPanel();
  renderNotes();
  renderRunOutput();
  renderSelectedMeta();

  bootstrap().then(async () => {
    await loadWorkspaceSettings(state.repoRoot);
    await analyzeRepo({ skipWorkspaceLoad: true });
  });
