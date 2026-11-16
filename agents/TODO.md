# To do

What is still to do in this repo. Rules: Agent-Conventions/WORKFLOW.md, section 8.
An item that is done is removed here and named in PROGRESS.md.

- [ ] Otter does not pass its own done-check: 199 triple and 33 deeper nesting sites.
  why: the tool that tells agents "no nesting" shows nesting; agents copy what they see.
  start: tools/agent_hooks/otter-gate.sh --force . | grep -A12 NESTING
  done when: done-check.sh prints `otter ok`.
  needs: nobody
  plan: deepest first (depth 4 and more: config_touch.nim mapTouches, taint.nim summarize, nim_parser.nim detectUserInputSignals, blast.nim feedersOf, test_ui/app.nim runSupervisor). Pull each inner block into an inline proc. docs/self-review.md lists which sites are misreadings of the parser; fix the parser for those instead.

- [ ] SECRETS reports 7 candidates; six are fixtures in evaluation/tests, one is in src/protocols/machine_code/taint.nim:134 and was not looked at.
  why: a real key hides among false alarms.
  start: tools/agent_hooks/otter-gate.sh --force . | grep -A9 SECRETS
  done when: the section is gone.
  needs: nobody
  plan: look at taint.nim:134 first. For the fixtures: build the sample values at run time (join two halves) so no file holds a key-shaped text, or teach the scorer that evaluation/tests fixtures marked `# otter: sample` are not keys.

- [ ] Four test files are in no task: test_child_enabled, test_ui_crash_example, test_ui_examples, test_ui_failure_example.
  why: a test nobody runs proves nothing; three of them fail on purpose (they are samples for the test UI) and sit in the wrong folder.
  start: tools/agent_hooks/repo-check.sh . | grep -A5 "ORPHAN TESTS"
  done when: repo-check prints no ORPHAN TESTS.
  needs: nobody
  plan: move the three samples that fail on purpose to examples/test_ui/ (they are input for the UI, not tests); add test_child_enabled and test_ui_examples to the test task.

- [ ] The web UI has 144 colours typed in src/clients/webui/web/app.css and no docs/ui-plan.md.
  why: a typed colour does not switch with the theme.
  start: tools/agent_hooks/ui-check.sh .
  done when: ui-check prints nothing.
  needs: nobody
  plan: name each colour once as a CSS variable at the top (glue, separator, recommendation, tiny, active: UI.md), then use the names. Write the press budget for the graph UI (UI.md, "Planning a UI").

- [ ] src/ holds 23 000 lines and three jobs.
  why: see WORKFLOW.md 2, Def. 4.
  start: grep "planned cut" agents/BORDERS.md
  done when: the line holds no "Open" and the cut is made.
  needs: user
  plan: src/protocols/machine_code and the statistical tests on binary streams each become a repo; Otter keeps repository measurements and the agent hooks.

- [ ] Five routine bodies are written out twice, five also stand in a neighbour repo.
  start: tools/agent_hooks/dup-check.sh --workspace .
  done when: it prints nothing.
  needs: nobody
  plan: keep one of each; what a neighbour holds too goes to Fylgia-Utils.

- [ ] dup-check.sh, repo-check.sh and ui-check.sh are shell and awk; Otter's own FAMILIES section finds near-twins in Nim, with the real parser.
  why: two finders for one question drift. The shell one is fast and runs without a build; the Nim one knows what a parameter is.
  start: read tools/agent_hooks/dup-check.sh and the FAMILIES part of `otter stats . --json`
  done when: one finder, called by both the gate and repo-check.
  needs: nobody
  plan: move TWINS / SAME SHAPE / ELSEWHERE into Otter's code_stats beside FAMILIES (it already has routine bodies and names), print them from `otter stats`, and let dup-check.sh become a three-line caller. Keep the headings and the test in evaluation/tests/test_repo_checks.sh unchanged.

- [ ] ui-check cannot see whether rows share an edge or whether a sheet should be a page.
  why: UI.md "Shared edges" and "Popup or full page" are checked by reading only.
  start: read Agent-Conventions/UI.md, "Planning a UI"
  done when: ui-check reports rows of data that are centred (CSS: text-align/justify-content center inside a list row; GTK: halign center on a label in a row).
  needs: nobody
  plan: start with the CSS case; count only selectors that also appear inside a repeated row (li, .row, .entry, listbox row). Report a file only above five hits, as COLOURS does.

- [ ] Atlas-Taskbar holds a contrast test that knows which rule wins (src/protocols/level1/contrastcheck.nim, `nimble checkContrast`); ui-hints.sh CONTRAST is a rough copy in awk.
  why: every UI repo needs the real test, and two contrast checkers drift.
  start: read Atlas-Taskbar/docs/menus.md, "Readable text, checked by itself"
  done when: the check lives in one shared place (Otter or Maya-Themes), the taskbar imports it, and ui-hints calls it.
  needs: nobody
  plan: move contrast.nim / contrastcheck.nim into Maya-Themes (it owns the colours), keep the taskbar's test as its first caller, let `otter` expose it as a command.

- [ ] The README names the test-window catalog `evaluation/tests/test_otter_catalog.nim`, and repo-check lists exactly that name under ORPHAN TESTS in every repo that follows it.
  why: the catalog is not a test (it starts `nimble test` itself), so adding it to the test task would make the suite start itself; the finding stays a FIX line in every repo.
  start: ../Otter-RepoEvaluation/tools/agent_hooks/repo-check.sh ../Bifrost-ExchangeProtocols  (before 2026-11-12 it printed the line; Bifrost renamed the file) and read README.md lines 212 and 232
  done when: the README names a file that repo-check does not call a test, and the repos that still use the old name (grep -rl test_otter_catalog ../*/evaluation/tests) are renamed.
  needs: nobody
  plan: the test window walks the whole evaluation/tests folder for the `otterUiTest` marker (src/protocols/test_ui/catalog.nim, discoverOtterUiTests), so any file name there works. Write `evaluation/tests/otter_catalog.nim` in the README (not outside evaluation/tests: the window would find nothing). Bifrost did this on 2026-11-12: `discoverOtterUiTests` still finds all five entries of its catalog at the new name (checked by calling it; the window itself was not opened).

- [ ] `continuity` cannot see boxes a script builds (createElement, innerHTML), so Eris-Messenger's web UI shows 37 click handlers and no finding.
  why: a teleport in a script-built UI is not reported; "no finding" reads as "fine".
  start: tools/agent_hooks/otter-build.sh, then `$(...) continuity ../Eris-Messenger`
  done when: a test page whose view is built with innerHTML / createElement gives the same verdicts as the static example in examples/ui_continuity/web.
  needs: nobody
  plan: in continuity_page.nim also read template strings (`innerHTML = `<section id="x">...``) and `createElement` chains into elements, then resolve ids against them.
