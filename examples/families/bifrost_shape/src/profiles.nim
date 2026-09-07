## A repository shaped like Bifrost before its link profiles were
## collapsed: one routine per named situation, every one built the
## same way, differing only in the numbers it fills in.
##
## The finished form is one routine and an enum:
##
##   proc linkDefaults(p: LinkProfile): LinkParams
##
## Otter should call this family `value` and say so.

type
  LinkParams* = object
    maxFrame*: int
    retries*: int
    backoffMs*: int
    repairShards*: int

proc cleanLanDefaults*(): LinkParams =
  var t: LinkParams = LinkParams()
  t.maxFrame = 1400
  t.retries = 2
  t.backoffMs = 20
  t.repairShards = 0
  result = t

proc mobileDefaults*(): LinkParams =
  var t: LinkParams = LinkParams()
  t.maxFrame = 1200
  t.retries = 4
  t.backoffMs = 60
  t.repairShards = 2
  result = t

proc meteredDefaults*(): LinkParams =
  var t: LinkParams = LinkParams()
  t.maxFrame = 900
  t.retries = 3
  t.backoffMs = 90
  t.repairShards = 1
  result = t

proc badSignalDefaults*(): LinkParams =
  var t: LinkParams = LinkParams()
  t.maxFrame = 600
  t.retries = 8
  t.backoffMs = 150
  t.repairShards = 4
  result = t

proc batterySaverDefaults*(): LinkParams =
  var t: LinkParams = LinkParams()
  t.maxFrame = 800
  t.retries = 1
  t.backoffMs = 200
  t.repairShards = 0
  result = t
