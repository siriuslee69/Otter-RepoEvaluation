## A small owlkettle menu with three views. Otter reads its text; the program does nothing.
##
##   view        what is shown                           who opens it
##   ----------  --------------------------------------  ---------------------------
##   vHome       the header row and the three columns     (the start)
##   vReport     a report, header row gone               the Report button (header)
##   vSettings   settings, columns gone                  the Settings button (a column)
##
## Wrong, both times: the button that opens a view lives in the thing the view
## replaces, so the user's finger loses its own button.
##
##   headerBar   [Report]   sets view = vReport   -> `bare` hides headerBar   TELEPORT
##   homeColumns [Settings] sets view = vSettings -> the case drops homeColumns TELEPORT
##   frameTabs   [Settings] sets view = vSettings -> frameTabs is never hidden  fine
##   settingsView [Back]    sets view = vHome     -> a return                   fine

## The real file starts with `import owlkettle`. Two lines stand in for the toolkit
## so that this example compiles without a window library; Otter reads the text.
import runePragmas

type
  Widget = object

template gui(body: untyped): Widget {.role: helper.} =
  Widget()

type
  View* = enum
    vHome, vReport, vSettings

  Memory* = ref object
    view*: View
    query*: string

proc toggleView*(M: Memory; v: View) {.role: actor.} =
  ## Pressing the same view again goes home.
  if M.view == v:
    M.view = vHome
  else:
    M.view = v

proc frameTabs(M: Memory): Widget {.role: helper.} =
  ## A strip that is on screen in every view.
  result = gui:
    Box:
      orient = OrientX
      Button:
        text = "Settings"
        style = [StyleClass("open-green")]
        proc clicked() =
          M.toggleView(vSettings)

proc headerBar(M: Memory): Widget {.role: helper.} =
  result = gui:
    Box:
      orient = OrientX
      Label:
        text = "Header"
      Button:
        text = "Report"
        proc clicked() =
          M.toggleView(vReport)
      Entry:
        text = M.query
      Label:
        text = "Mon"
      Label:
        text = "Tue"
      Label:
        text = "Wed"
      Label:
        text = "Thu"
      Label:
        text = "Fri"
      Label:
        text = "Sat"
      Label:
        text = "Sun"
      Label:
        text = "Today"

proc homeColumns(M: Memory): Widget {.role: helper.} =
  result = gui:
    Box:
      orient = OrientX
      Box:
        Label:
          text = "Targets"
        Label:
          text = "Energy"
        Label:
          text = "Water"
      Box:
        Label:
          text = "Tasks"
        Label:
          text = "Dentist"
        Label:
          text = "Tax"
      Box:
        Label:
          text = "Dishes"
        Button:
          text = "Settings"
          proc clicked() =
            M.view = vSettings

proc reportView(M: Memory): Widget {.role: helper.} =
  result = gui:
    Box:
      orient = OrientY
      Label:
        text = "Report"
      Box:
        orient = OrientX
        Label:
          text = "Week"
        LevelBar:
          value = 0.4
        Label:
          text = "Month"
        LevelBar:
          value = 0.7
      Box:
        orient = OrientX
        Label:
          text = "Year"
        LevelBar:
          value = 0.2
      Separator:
        orient = OrientX
      Label:
        text = "Sources"

proc settingsView(M: Memory): Widget {.role: helper.} =
  result = gui:
    ScrolledWindow:
      style = [StyleClass("pane-green")]
      Box:
        orient = OrientY
        spacing = 6
        Label:
          text = "Settings"
        Entry:
          placeholder = "Name"
        Switch:
          state = true
        Entry:
          placeholder = "Language"
        Switch:
          state = false
        DropDown:
          items = @["Light", "Dark"]
        Entry:
          placeholder = "Backup folder"
        Switch:
          state = true
        Entry:
          placeholder = "Alarm time"
        Button:
          text = "Back"
          proc clicked() =
            M.view = vHome

proc body(M: Memory): Widget {.role: orchestrator.} =
  ## One of three views fills the area under the header.
  case M.view
  of vReport:
    result = reportView(M)
  of vSettings:
    result = settingsView(M)
  else:
    result = homeColumns(M)

proc menu*(M: Memory): Widget {.role: orchestrator.} =
  var
    bare: bool = M.view in {vReport}
  result = gui:
    Box:
      orient = OrientY
      insert(frameTabs(M))
      insert(body(M))
      if not bare:
        insert(headerBar(M))
