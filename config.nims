switch("path", "src")
if dirExists("submodules/Fylgia-Utils/src"):
  switch("path", "submodules/Fylgia-Utils/src")
elif dirExists("../Fylgia-Utils/src"):
  switch("path", "../Fylgia-Utils/src")
