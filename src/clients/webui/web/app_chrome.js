window.OtterWebuiChrome = (() => {
  function closeAllMenus() {
    document.querySelectorAll('details[open]').forEach((menu) => {
      menu.open = false;
    });
  }

  function installHoverDropdowns() {
    document.querySelectorAll('.menu-dropdown').forEach((menu) => {
      let closeTimer = 0;
      const openMenu = () => {
        if (closeTimer) window.clearTimeout(closeTimer);
        closeTimer = 0;
        menu.open = true;
      };
      const closeMenu = () => {
        if (closeTimer) window.clearTimeout(closeTimer);
        closeTimer = window.setTimeout(() => {
          if (menu.matches(':hover') || menu.contains(document.activeElement)) return;
          menu.open = false;
        }, 160);
      };
      menu.addEventListener('mouseenter', openMenu);
      menu.addEventListener('mouseleave', closeMenu);
      menu.addEventListener('focusin', openMenu);
      menu.addEventListener('focusout', closeMenu);
    });
  }

  function wheelZoomFactor(event) {
    return Math.exp(-event.deltaY * 0.0012);
  }

  return {
    closeAllMenus,
    installHoverDropdowns,
    wheelZoomFactor
  };
})();
