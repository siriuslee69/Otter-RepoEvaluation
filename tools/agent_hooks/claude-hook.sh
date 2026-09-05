#!/usr/bin/env bash
# Claude Code adapter for the Otter agent hooks.
#
# Wire it as a PostToolUse hook on `Write|Edit` and on `Bash(git commit *)`:
#
#   { "type": "command",
#     "command": "<OTTER_HOME>/tools/agent_hooks/claude-hook.sh",
#     "timeout": 300 }
#
# It reads the hook payload on stdin, runs the two checks, and hands anything
# they report back as `additionalContext`. Never blocks a tool call: a check
# that finds nothing, or fails outright, is silent.
#
# Other agents and CLIs should skip this file and call `nim-check.sh` and
# `otter-gate.sh` directly — both print plain text and use exit code 1 to mean
# "there is something to report".
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

payload=$(cat 2>/dev/null || true)
file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="${file:+$(dirname "$file")}"
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"

context=""
sysmsg=""

# --- the file that was just written ---
if [ -n "$file" ] && [ -f "$file" ]; then
  if out=$("$here/nim-check.sh" "$file" 2>/dev/null); then :; else
    if [ $? -eq 1 ] && [ -n "$out" ]; then
      context="Convention check on the file just written:
$(printf '%s' "$out" | sed 's/^/  /')

Apply these fixes now — they are CONVENTIONS.md rules, not suggestions."
    fi
  fi
fi

# --- the repo, once enough lines have moved ---
if out=$("$here/otter-gate.sh" "$cwd" 2>/dev/null); then :; else
  if [ $? -eq 1 ] && [ -n "$out" ]; then
    context="${context:+$context

}$out"
    sysmsg="Otter: line-change threshold crossed — statistics injected for cleanup."
  fi
fi

[ -n "${context//[[:space:]]/}" ] || exit 0

jq -nc --arg c "$context" --arg m "$sysmsg" '
  { hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: $c } }
  + (if $m == "" then {} else { systemMessage: $m } end)
'
