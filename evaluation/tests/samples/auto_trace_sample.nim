# ============================================================
# | Auto Trace Sample                                       |
# | -> Plain Nim file used by the otter-nim smoke test      |
# ============================================================

proc autoLeaf*(a: int): int =
  ## a: input value.
  var
    t: int = 0
  t = a + 4
  result = t


proc autoBranch*(a: int): int =
  ## a: input value.
  var
    t: int = 0
  t = autoLeaf(a)
  result = t * 2


when isMainModule:
  doAssert autoBranch(3) == 14
