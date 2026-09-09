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

## Pragma module, named for this repository so no other repo on the Nim
## path can capture it. See CONTRIBUTING in Proto-RepoTemplate.

## Shared pragma module: one file for the whole workspace, so there is no
## per-repository copy to drift or to collide on the Nim path.
if dirExists(thisDir() & "/../Rune-Pragmas/meta"):
  switch("path", thisDir() & "/../Rune-Pragmas/meta")
if dirExists(thisDir() & "/submodules/Rune-Pragmas/meta"):
  switch("path", thisDir() & "/submodules/Rune-Pragmas/meta")
