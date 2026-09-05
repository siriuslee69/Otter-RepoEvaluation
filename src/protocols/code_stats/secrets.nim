## ==============================================================
## | secrets.nim  <-  things that should never have been typed  |
## |                  into a source file                        |
## |------------------------------------------------------------|
## | Two kinds of thing are looked for:                          |
## |                                                             |
## |   key material   passwords, tokens, private keys            |
## |   personal data  a home folder with a person's name in it,  |
## |                  an email address, a machine's address      |
## |                                                             |
## | Nothing here is certain, so nothing here says "this is a    |
## | key". Every find gets a percentage, and only finds above a  |
## | threshold are shown. That way a name that merely looks      |
## | suspicious can be seen and dismissed, instead of either     |
## | being hidden or being shouted about.                        |
## |                                                             |
## | How a percentage is arrived at, in words:                   |
## |                                                             |
## |   the name of the thing    "apiKey", "secret", "token"      |
## |   + the shape of the value long, and made of the letters    |
## |     and numbers a key is made of                            |
## |   + how jumbled it is      real keys look like noise; the   |
## |     word "configuration" does not                           |
## |   + a known opening        "-----BEGIN", "sk-", "AKIA"      |
## |   = how likely this is key material                         |
## |                                                             |
## | "How jumbled" is worth explaining, because it does most of  |
## | the work. Take a piece of text and count how unevenly its   |
## | characters are spread. English prose reuses `e` and `t`     |
## | constantly and scores low. A random key uses every          |
## | character about equally and scores high:                    |
## |                                                             |
## |   "aaaaaaaaaaaaaaaa"  -> 0.0   one character, no surprise   |
## |   "the quick brown"   -> ~3.3  ordinary words               |
## |   "kJ8x2Qm9Zp4Lw7Nv"  -> ~3.9  noise, and so probably a key |
## |                                                             |
## | History is read as well as the working folder. A key that   |
## | was committed once and deleted the next day is still a key  |
## | that was published, and it still has to be rotated.         |
## ==============================================================

import std/[algorithm, math, os, osproc, strutils, tables]

import ../../../.iron/metaPragmas

const
  secretFloor*: float = 0.55
    ## Under this a find is not reported. Set so that an obvious
    ## `apiKey = "sk-live-..."` clears it easily and a variable merely
    ## called `key` holding the word "name" does not.
  secretsShown*: int = 60
    ## How many finds travel to a window. The rest are counted.
  historyCommits*: int = 400
    ## How far back the history is read for keys that were committed
    ## and later removed.
  minValueLen*: int = 12
    ## Shorter than this is not worth weighing. Nothing that short is
    ## a key, and everything that short is a false alarm.
  maxValueLen*: int = 512
    ## Longer than this is a data blob, not a typed-in secret.
  nameWords*: array[14, string] = [
    "key", "secret", "token", "password", "passwd", "pwd",
    "apikey", "api_key", "privkey", "private_key", "credential",
    "auth", "signature", "salt"
  ]
    ## Words in the *name* of a thing that suggest what it holds.
  shortNameWords*: array[4, string] = ["sk", "pk", "iv", "pw"]
    ## Very short names that count only when they stand alone, so that
    ## `pk` matches and `speaker` does not.
  keyOpeners*: array[10, string] = [
    "-----begin", "sk-", "sk_live", "pk_live", "ghp_", "gho_",
    "akia", "aiza", "xoxb-", "eyj"
  ]
    ## Openings that name themselves. `eyj` is how every JSON web
    ## token starts once it has been encoded.
  safeWords*: array[10, string] = [
    "example", "sample", "dummy", "placeholder", "changeme",
    "your_", "xxxx", "test_key", "lorem", "todo"
  ]
    ## Words that say "this is not real". They pull a score down
    ## rather than clearing it, because a value labelled `example`
    ## occasionally turns out to be anything but.

type
  SecretKind* {.role: other, metaTags: {tagStats}.} = enum
    ## What sort of thing was found.
    ##
    ##   skKey       key material: a token, password, or private key
    ##   skUserPath  a folder path with a person's name in it
    ##   skEmail     an email address
    ##   skAddress   a machine address typed into the source
    skKey, skUserPath, skEmail, skAddress

  SecretFind* {.role: preparedData, metaTags: {tagStats}.} = object
    ## One thing found, and how likely it is to be what it looks like.
    ##
    ##   preview  the value with its middle removed. The whole point
    ##            of this file is to stop secrets being copied about,
    ##            so it never repeats one back in full.
    ##   reasons  every signal that fired, so the number can be argued
    ##            with rather than believed.
    ##   commit   empty when found in the folder as it stands, or the
    ##            commit that introduced it when found in history.
    kind*: string
    name*: string
    preview*: string
    path*: string
    commit*: string
    reasons*: seq[string]
    line*: int
    length*: int
    score*: float
    entropy*: float
    inHistory*: bool

  SecretReport* {.role: truthState, metaTags: {tagStats}.} = object
    ## Everything found in one repository.
    items*: seq[SecretFind]
    total*: int
    keyCount*: int
    userDataCount*: int
    historyCount*: int
    commitsRead*: int
    error*: string

proc entropyOf*(s: string): float {.role: MetaRole.math, metaTags: {tagStats}.} =
  ## s <- any piece of text. How jumbled it is, in bits per character.
  ##
  ## Each character's share of the text is worked out, and the shares
  ## are added up as `-share * log2(share)`. That sum is largest when
  ## every character is equally common, which is what noise looks
  ## like, and smallest when one character dominates.
  ##
  ## Roughly: under 3.0 is ordinary words, over 3.5 is probably a key.
  var
    counts: CountTable[char] = initCountTable[char]()
    share: float = 0.0
  result = 0.0
  if s.len == 0:
    return
  for ch in s:
    counts.inc(ch)
  for _, n in counts.pairs:
    share = n.float / s.len.float
    result = result - share * log2(share)

proc keyCharsOnly*(s: string): bool {.role: parser,
    metaTags: {tagStats}.} =
  ## s <- a value. Whether it is made only of the characters keys are
  ## made of: letters, digits, and the handful of marks that base64
  ## and hex use. A sentence with spaces in it is not a key.
  result = true
  for ch in s:
    if not (ch.isAlphaNumeric() or ch == '+' or ch == '/' or
        ch == '=' or ch == '-' or ch == '_' or ch == '.'):
      return false

proc nameLooksSecret*(name: string): bool {.role: parser,
    metaTags: {tagStats}.} =
  ## name <- what the value was called in the source.
  ##
  ## Long words are matched anywhere inside the name; the two-letter
  ## ones only when they stand on their own, or `sk` would match
  ## `taskList` and every repository would look full of secrets.
  var
    t: string = name.toLowerAscii()
    parts: seq[string] = @[]
    word: string = ""
  result = false
  for row in nameWords:
    if row in t:
      return true
  for ch in name:
    if ch == '_' or ch == '-' or ch.isUpperAscii():
      if word.len > 0:
        parts.add(word.toLowerAscii())
      word = ""
    if ch != '_' and ch != '-':
      word.add(ch)
  if word.len > 0:
    parts.add(word.toLowerAscii())
  for row in shortNameWords:
    if row in parts:
      return true

proc maskOf*(s: string): string {.role: sanitizer, metaTags: {tagStats}.} =
  ## s <- a value that may be a real secret.
  ##
  ## Keeps just enough at each end for a person to recognise which
  ## value is meant, and throws the middle away:
  ##
  ##   "sk-live-4f9a2b8c7d6e5f0a"  ->  "sk-l…20…f0a"
  result = s
  if s.len <= 8:
    result = "…" & $s.len & " chars…"
    return
  result = s[0 ..< 4] & "…" & $s.len & "…" & s[^3 .. ^1]

proc userPathOf*(s: string): tuple[hit: bool, who: string]
    {.role: parser, metaTags: {tagStats}.} =
  ## s <- one line of source. Whether it holds somebody's home folder,
  ## and whose:
  ##
  ##   /home/anna/keys      -> anna
  ##   C:\Users\Anna\keys   -> Anna
  ##   /Users/anna/keys     -> anna
  var
    t: string = s.replace('\\', '/')
    at: int = 0
    rest: string = ""
    who: string = ""
  result = (hit: false, who: "")
  # A Windows path written inside Nim source has its slashes doubled
  # (`"C:\\Users\\anna"`), and turning those into forward slashes
  # leaves `C://Users//anna`. Collapse the doubles or nothing matches.
  while "//" in t:
    t = t.replace("//", "/")
  for head in ["/home/", "/Users/", "/users/", "C:/Users/"]:
    at = t.find(head)
    if at < 0:
      continue
    rest = t[at + head.len .. ^1]
    who = ""
    for ch in rest:
      if ch == '/' or ch == '"' or ch == '\'' or ch == ' ':
        break
      who.add(ch)
    # `/home/` on its own, or a placeholder, names nobody.
    if who.len > 0 and who notin ["user", "username", "you", "runner",
        "root", "nixbld"]:
      return (hit: true, who: who)

proc looksLikeEmail*(s: string): string {.role: parser,
    metaTags: {tagStats}.} =
  ## s <- one line of source. The first email address in it, or "".
  var
    at: int = 0
    a: int = 0
    b: int = 0
    got: string = ""
  result = ""
  at = s.find('@')
  if at <= 0 or at + 1 >= s.len:
    return
  a = at
  while a > 0 and (s[a - 1].isAlphaNumeric() or s[a - 1] in {'.', '_',
      '-', '+'}):
    a = a - 1
  b = at
  while b + 1 < s.len and (s[b + 1].isAlphaNumeric() or s[b + 1] in
      {'.', '-'}):
    b = b + 1
  got = s[a .. b]
  if '.' notin got[at - a .. ^1] or got.len < 6:
    return
  if got.startsWith("@") or got.endsWith("@"):
    return
  result = got

proc looksLikePath*(s: string): bool {.role: parser,
    metaTags: {tagStats}.} =
  ## s <- a value. Whether it is plainly a location on a disk rather
  ## than key material.
  ##
  ## This matters because a long path scores well on every test a key
  ## scores on: it is long, it is made of the allowed characters, and
  ## it is reasonably jumbled. `/home/anna/.config/state.json` was
  ## being reported as a probable key. It is a path, and it is already
  ## reported as one by `userPathOf`, so it must not be counted twice.
  var
    t: string = s.replace('\\', '/')
  result = false
  if t.startsWith("/") or t.startsWith("./") or t.startsWith("../") or
      t.startsWith("~/"):
    return true
  if t.len > 2 and t[1] == ':' and t[0].isAlphaAscii():
    return true
  if "://" in t:
    return true
  # A path written from where the program stands rather than from the
  # root of the disk, such as `src/clients/web/js/app.js`. Recognised
  # by having folders and a file ending on the end. Base64, which is
  # the thing this must not swallow, has no dot near its end.
  if '/' in t:
    var
      tail: string = t.rsplit('/', maxsplit = 1)[^1]
      at: int = tail.rfind('.')
    if at > 0 and tail.len - at <= 6 and at < tail.len - 1:
      return true

proc scoreValue*(name, value: string):
    tuple[score: float, entropy: float, reasons: seq[string]]
    {.role: truthBuilder, metaTags: {tagStats}.} =
  ## name <- what it was called   value <- what it was set to
  ##
  ## The four signals are added, not multiplied, so that a very
  ## jumbled value with an innocent name still scores, and so does a
  ## short value with a damning name.
  var
    score: float = 0.0
    ent: float = 0.0
    reasons: seq[string] = @[]
    low: string = value.toLowerAscii()
    opener: bool = false
  result = (score: 0.0, entropy: 0.0, reasons: @[])
  if value.len < minValueLen or value.len > maxValueLen:
    return
  if looksLikePath(value) and not nameLooksSecret(name):
    return
  ent = entropyOf(value)
  for row in keyOpeners:
    if low.startsWith(row) or (row == "-----begin" and row in low):
      opener = true
  if opener:
    score = score + 0.6
    reasons.add("it starts the way a known kind of key starts")
  if nameLooksSecret(name):
    score = score + 0.35
    reasons.add("the name says it holds a secret")
  if keyCharsOnly(value):
    score = score + 0.15
    reasons.add("made only of the characters keys are made of")
    if value.len >= 32:
      score = score + 0.1
      reasons.add("long enough to be a real key")
  if ent >= 3.5:
    score = score + 0.3
    reasons.add("jumbled like noise rather than like words")
  elif ent >= 3.0:
    score = score + 0.12
    reasons.add("somewhat jumbled")
  for row in safeWords:
    if row in low:
      score = score - 0.45
      reasons.add("but it reads like an example rather than a real one")
      break
  if score < 0.0:
    score = 0.0
  if score > 0.99:
    score = 0.99
  result = (score: score, entropy: ent, reasons: reasons)

proc splitAssignment*(line: string): tuple[name: string, value: string]
    {.role: parser, metaTags: {tagStats}.} =
  ## line <- one line of source.
  ##
  ## Pulls apart `apiKey = "sk-live-..."` into the name and the text
  ## it was set to. Only quoted text counts as a value: a name set
  ## from another name is not a typed-in secret.
  var
    at: int = 0
    head: string = ""
    tail: string = ""
    a: int = 0
    b: int = 0
    t: string = line.strip()
  result = (name: "", value: "")
  at = t.find('=')
  if at <= 0:
    at = t.find(':')
    if at <= 0:
      return
  head = t[0 ..< at]
  tail = t[at + 1 .. ^1]
  a = tail.find('"')
  if a < 0:
    return
  b = tail.find('"', a + 1)
  if b <= a + 1:
    return
  head = head.replace("const", " ").replace("var", " ")
  head = head.replace("let", " ").replace("*", " ")
  # `apiKey: string` names the thing on the left of the colon. Without
  # this the type is taken for the name and every such line is
  # reported as a value called "string".
  if ':' in head:
    head = head[0 ..< head.find(':')]
  head = head.strip(chars = {' ', '\t', ',', ':', '"', '\''})
  if ' ' in head:
    head = head.splitWhitespace()[^1]
  result = (name: head, value: tail[a + 1 ..< b])

proc scanLine*(line, path, commit: string, n: int,
    S: var seq[SecretFind]) {.role: actor, metaTags: {tagStats}.} =
  ## line <- one line of source   path <- where it lives
  ## commit <- "" for the working folder, or which commit added it
  ## n <- which line   S <- the list being grown
  ##
  ## One line can hold more than one kind of find, so every test is
  ## run rather than stopping at the first.
  var
    pair: tuple[name: string, value: string]
    got: tuple[score: float, entropy: float, reasons: seq[string]]
    who: tuple[hit: bool, who: string]
    mail: string = ""
  if line.len > 4000:
    return
  # A line that is only a comment is left alone. Documentation is
  # where people write examples of exactly the things looked for here
  # — this very file explains itself with `/home/anna/...` — and a
  # tool that reports its own examples buries every real find under
  # its own prose. A secret written in a comment beside live code is
  # still caught, because that line holds code as well.
  if line.strip().startsWith("#"):
    return
  pair = splitAssignment(line)
  if pair.value.len > 0:
    got = scoreValue(pair.name, pair.value)
    if got.score >= secretFloor:
      S.add(SecretFind(kind: "key", name: pair.name,
        preview: maskOf(pair.value), path: path, commit: commit,
        reasons: got.reasons, line: n, length: pair.value.len,
        score: got.score, entropy: got.entropy,
        inHistory: commit.len > 0))
  who = userPathOf(line)
  if who.hit:
    S.add(SecretFind(kind: "user path", name: who.who,
      preview: maskOf(who.who), path: path, commit: commit,
      reasons: @["a home folder with somebody's name in it"],
      line: n, length: who.who.len, score: 0.8, entropy: 0.0,
      inHistory: commit.len > 0))
  mail = looksLikeEmail(line)
  if mail.len > 0:
    S.add(SecretFind(kind: "email", name: "email", preview: maskOf(mail),
      path: path, commit: commit,
      reasons: @["an email address written into the source"],
      line: n, length: mail.len, score: 0.7, entropy: 0.0,
      inHistory: commit.len > 0))

proc byScore(a, b: SecretFind): int {.role: helper,
    metaTags: {tagStats}.} =
  ## a, b <- two finds, most likely first, and the folder before the
  ## history, because something still in the tree matters more.
  result = cmp(b.score, a.score)
  if result == 0:
    result = cmp(a.inHistory, b.inHistory)
  if result == 0:
    result = cmp(a.path, b.path)

proc scanWorking*(dir: string, files: seq[string],
    S: var seq[SecretFind]) {.role: orchestrator, input: thirdParty,
    metaTags: {tagStats}.} =
  ## dir <- the repository   files <- every source file in it
  ## S <- the list being grown
  var
    rel: string = ""
    n: int = 0
    text: string = ""
  for path in files:
    rel = path.replace('\\', '/')
    if dir.len > 0 and rel.startsWith(dir.replace('\\', '/')):
      rel = rel[dir.len .. ^1]
    if rel.startsWith("/"):
      rel = rel[1 .. ^1]
    try:
      text = readFile(path)
    except OSError, IOError:
      continue
    n = 0
    for line in text.splitLines():
      n = n + 1
      scanLine(line, rel, "", n, S)

proc scanHistory*(dir: string, S: var seq[SecretFind]): int
    {.role: orchestrator, input: thirdParty, risk: low, speed: long,
    metaTags: {tagStats}.} =
  ## dir <- the repository   S <- the list being grown
  ##
  ## Reads what every commit *added*, rather than what each commit
  ## left behind. That is the difference that matters here: a key
  ## added on Monday and deleted on Tuesday is invisible in every
  ## snapshot of the tree, and plainly visible in the patch.
  ##
  ##   git log -p  ─►  lines beginning `+`  ─►  the same tests
  ##
  ## Returns how many commits were read.
  var
    got: tuple[output: string, exitCode: int]
    commit: string = ""
    path: string = ""
    n: int = 0
    body: string = ""
  result = 0
  try:
    got = execCmdEx("git -C " & quoteShell(dir) &
      " log --first-parent -p -U0 --no-color --no-renames" &
      " --max-count=" & $historyCommits &
      " --format=%x01%H --diff-filter=AM -- .")
  except OSError, IOError:
    return
  if got.exitCode != 0:
    return
  for line in got.output.splitLines():
    if line.len > 0 and line[0] == '\x01':
      commit = line[1 .. ^1].strip()
      result = result + 1
      continue
    if line.startsWith("+++ b/"):
      path = line[6 .. ^1].strip()
      n = 0
      continue
    if line.startsWith("@@"):
      # `@@ -1,0 +42,3 @@` says the added lines start at 42.
      body = line
      n = 0
      var
        at: int = body.find('+')
        num: string = ""
      if at > 0:
        for ch in body[at + 1 .. ^1]:
          if ch.isDigit():
            num.add(ch)
          else:
            break
        try:
          n = parseInt(num) - 1
        except ValueError:
          n = 0
      continue
    if line.startsWith("+") and not line.startsWith("+++"):
      n = n + 1
      scanLine(line[1 .. ^1], path, commit, n, S)

proc dedupe*(A: seq[SecretFind]): seq[SecretFind] {.role: sanitizer,
    metaTags: {tagStats}.} =
  ## A <- every find, working folder and history together.
  ##
  ## The same key sits in the tree *and* in the commit that added it.
  ## Reporting both would double every count, so a find already seen
  ## in the folder is not repeated from the history. The folder copy
  ## is the one kept, because it is the one still to be dealt with.
  var
    seen: Table[string, int] = initTable[string, int]()
    tag: string = ""
  result = @[]
  for row in A:
    tag = row.kind & "|" & row.preview & "|" & row.name
    if seen.hasKey(tag):
      continue
    seen[tag] = 1
    result.add(row)

proc secretsOf*(dir: string, files: seq[string],
    withHistory: bool = true): SecretReport {.role: metaOrchestrator,
    input: thirdParty, risk: low, speed: long, metaTags: {tagStats}.} =
  ## dir <- the repository   files <- every source file in it
  ## withHistory <- whether to read the commits as well as the folder
  var
    found: seq[SecretFind] = @[]
  result = SecretReport(items: @[], total: 0, keyCount: 0,
    userDataCount: 0, historyCount: 0, commitsRead: 0, error: "")
  if dir.len == 0 or not dirExists(dir):
    result.error = "no such folder: " & dir
    return
  scanWorking(dir, files, found)
  if withHistory and (dirExists(dir / ".git") or fileExists(dir / ".git")):
    result.commitsRead = scanHistory(dir, found)
  found = dedupe(found)
  found.sort(byScore)
  result.total = found.len
  for row in found:
    if row.kind == "key":
      result.keyCount = result.keyCount + 1
    else:
      result.userDataCount = result.userDataCount + 1
    if row.inHistory:
      result.historyCount = result.historyCount + 1
  if found.len > secretsShown:
    found.setLen(secretsShown)
  result.items = found
