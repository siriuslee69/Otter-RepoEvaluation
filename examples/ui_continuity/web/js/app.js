// The presses of the example page: one teleports, the rest do not.
//
//   press            hides        shows        button inside what is hidden?
//   ---------------  -----------  -----------  -----------------------------
//   open-settings    #overview    #settings    YES  -> TELEPORT
//   tab-reports      #overview    #reports     no   (the frame stays)
//   back             #settings    #overview    yes, but it starts hidden: a return
//   dismiss-note     #note        nothing      yes, but small and replaced by nothing
//   close-about      #about-box   nothing      a floating box
//   open-b           #col-a, #col-c  #detail-b   no (button stays): green, next to it, a fade

const overview = document.getElementById('overview');
const settings = document.getElementById('settings');
const reports = document.getElementById('reports');
const aboutBox = document.getElementById('about-box');

document.getElementById('open-settings').addEventListener('click', () => {
  overview.hidden = true;
  settings.hidden = false;
});

document.getElementById('tab-reports').addEventListener('click', () => {
  overview.hidden = true;
  reports.hidden = false;
});

document.getElementById('tab-overview').addEventListener('click', () => {
  reports.hidden = true;
  overview.hidden = false;
});

document.getElementById('back').addEventListener('click', () => {
  settings.hidden = true;
  overview.hidden = false;
});

document.getElementById('dismiss-note').addEventListener('click', () => {
  document.getElementById('note').hidden = true;
});

document.getElementById('close-about').addEventListener('click', () => {
  aboutBox.hidden = true;
  overview.hidden = false;
});

// The button of column b stays; the other columns go and its details open beside it.
document.getElementById('open-b').addEventListener('click', () => {
  document.getElementById('col-a').hidden = true;
  document.getElementById('col-c').hidden = true;
  document.getElementById('detail-b').hidden = false;
});
