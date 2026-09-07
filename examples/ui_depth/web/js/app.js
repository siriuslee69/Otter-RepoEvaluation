// The command box is never shown by anything on screen. Only this
// handler reveals it, so a person who does not know the key cannot
// reach it at any number of clicks.
document.addEventListener("keydown", function (e) {
  if (e.ctrlKey && e.key === "k") {
    document.querySelector("#palette").classList.add("open");
  }
});
