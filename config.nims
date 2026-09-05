switch("path", "src")
if dirExists("submodules/Fylgia-Utils/src"):
  switch("path", "submodules/Fylgia-Utils/src")
elif dirExists("../Fylgia-Utils/src"):
  switch("path", "../Fylgia-Utils/src")

# Fylgia is imported by a path relative to the importing file (see
# src/protocols/code_stats/shape.nim). This define only says which of
# the two places Fylgia is sitting in, and is set only when the pinned
# copy is actually there and carries the module that is wanted.
if fileExists("submodules/Fylgia-Utils/src/protocols/math/vector_space.nim"):
  switch("define", "otterFylgiaSubmodule")
