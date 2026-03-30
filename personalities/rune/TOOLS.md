# TOOLS.md — Environment Notes

## Personality Repo

- **GitHub:** `madping-cloud/personalities` (private)
- **Your files:** `agents/rune/`
- **All agent files:** `agents/<name>/`
- **Style guide:** `STYLE-GUIDE.md` at repo root
- **Templates:** `templates/` for new agents

## GitHub Workflow

Use `gh` CLI for repo operations. Standard flow:

```bash
# 1. Create a branch
git checkout -b rune/update-atlas-soul

# 2. Edit files
# 3. Commit
git add agents/atlas/SOUL.md
git commit -m "Atlas: sharpen voice, cut filler from section 2"

# 4. Push and open PR
gh pr create --title "Atlas: sharpen voice" --body "What changed and why"
```

PR description must explain: what changed, why, and what behavior difference it produces.
Marc reviews. Cole merges and runs `scripts/sync.sh`.

Branch naming: `<agent>/<short-description>` (e.g. `rune/memory-init`, `atlas/voice-sharpening`)

## OpenClaw Agent Runtime

Bootstrap files loaded each session (from workspace):
- `AGENTS.md` — operating instructions
- `SOUL.md` — persona, tone, boundaries
- `TOOLS.md` — this file
- `IDENTITY.md` — name, emoji, vibe
- `USER.md` — user profile
- `MEMORY.md` — long-term context (searched via memory_search tool)

Session logs: `~/.openclaw/agents/<agentId>/sessions/<SessionId>.jsonl`

Memory tools:
- `memory_search` — semantic search across MEMORY.md and memory/*.md
- `memory_get` — read specific lines from a memory file

## Working Surface

Primary interface: Discord DM from Marc (mister.rev).
This is not a user-facing agent — conversations are internal work sessions.

## Notes

- Cole runs `scripts/sync.sh` to push personality files to containers after a merge
- MEMORY.md and memory/ are NOT in the personalities repo — those are local to each container
- Skills are NOT in the personalities repo — they live in the infra repo or are installed via OpenClaw config
- Never push directly to main in `madping-cloud/personalities`
