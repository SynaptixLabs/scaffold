# synaptix-scaffold

**A tool-agnostic template for running a team of AI coding agents — one brain, every CLI.**

Define your agents, roles, and rules **once**, and use them from Claude Code, Codex, Cursor, Gemini
CLI, Devin, Windsurf, and any other tool that reads the open [`AGENTS.md`](AGENTS.md) standard. No
more maintaining a separate config per tool and watching them drift apart.

> Distilled and open-sourced from SynaptixLabs' internal Nexus agent platform — the private IP
> stays private; this is the pattern, free to use. **License:** MIT.

---

## The idea in one picture

```
                    ┌──────────────────────────────────┐
                    │   .claude/   ← THE CANONICAL BRAIN │
                    │   roles/     class contracts       │   edit behavior HERE,
                    │   policies/  binding doctrine       │   once — every CLI inherits it
                    │   skills/    process procedures     │
                    │   00_INDEX   capability router      │
                    └───────────────┬──────────────────┘
       thin pointers (never restate)│
   ┌───────────┬───────────┬────────┼──────────┬──────────┐
 AGENTS.md   CLAUDE.md   .agents/   .cursor/   .gemini/
 (the open   + .claude   skills/    rules/     commands/
  standard —  native)    (Codex $,  (Cursor)   (Gemini)
  Codex/      Devin)
  Windsurf/…)
```
> `AGENTS.md` covers every tool that reads the open standard — **Codex, Windsurf, Amp, Aider, Zed,
> Jules, Copilot…** — with no dedicated dir. `.agents/skills/` adds `$name`-invokable skills for
> **Codex** (and is **Devin's** recommended skill path). No more `.codex/` or `.devin/` folders.

Every agent surface except `.claude/` is a **thin adapter**: a pointer plus a small local delta,
never a copy. Change a role once in `.claude/roles/`, and Claude, Codex, Cursor, Gemini, and Devin
all pick it up. A CI check (`scripts/check_adapters.py`) fails the build if any adapter drifts.

## What you get

- **3 example agents**, ready to use and copy:
  | Persona | Role (class) | Also answers to | Use for |
  |---|---|---|---|
  | **JANUS** | `cpto` | `janus-cpto` | Direction, scope, requirements, GBU review, ship / don't-ship |
  | **ARIA** | `ux-design` | `uiux`, `aria-uiux` | UI/UX direction, the design kit, accessibility, visual acceptance |
  | **CORE** | `dev` | `core-dev` | Implement features across the stack, reuse-first + test-first |

  Each is reachable by its persona, its class, and a `<persona>-<class>` compound alias (plus any
  functional keyword you add, like `uiux`) — on every CLI.
- **5 CLI adapters** wired to those agents: Claude Code, Codex, Cursor, Gemini CLI, Devin — plus
  every AGENTS.md-aware tool (Windsurf, Amp, Aider, Zed, Jules, Copilot…) for free.
- **A `policies/` doctrine** that encodes hard-won practices: reuse-first, "E2E = a real browser",
  "no gate closes on assertion", honest status, load-the-project's-own-context-first.
- **Process skills**: implement-feature, design-review-gbu (GBU), browser-e2e, qa-gate.
- **A `project-management/` template** for PRD, decisions, module registry, and sprints.
- **A consistency checker** so the adapters can never silently disagree.

## Quickstart

```bash
# 1. Get the template
git clone https://github.com/SynaptixLabs/synaptix-scaffold.git my-project
cd my-project && rm -rf .git && git init

# 2. Open it in your CLI of choice — the agents are already there:
#    Claude Code →  /janus            |  Codex   →  act as JANUS   (or  $janus)
#    Gemini CLI  →  /janus            |  Devin   →  janus skill (auto / @skills:janus)
#    Cursor      →  "act as JANUS …"  (rules route it)
#    The UI/UX agent answers to /aria, /ux-design, /uiux, or /aria-uiux.

# 3. Verify the agent layer is consistent
python3 scripts/check_adapters.py

# 4. Make it yours (see "Customize" below)
```

Try it: open the repo in any supported CLI and say **`act as JANUS: scope a v1 for <your idea>`**.
JANUS (the CPTO) will load its class contract and start turning the idea into testable requirements.

## Customize

1. Fill the `{{PLACEHOLDER}}` fields in [`CLAUDE.md`](CLAUDE.md), the start scripts
   (`start.sh` / `start.ps1`), `.env.example`, and the `project-management/` templates with your
   project's real identity, stack, and ports. (`AGENTS.md` and `GEMINI.md` carry no placeholders.)
2. Keep, prune, or extend the example agents. To add one, follow
   [`project-management/reference/ADDING_AN_AGENT.md`](project-management/reference/ADDING_AN_AGENT.md) — it's ~15 lines per agent, once.
3. Everything under `.claude/roles/` and `.claude/policies/` is meant to be **reused as-is** or
   lightly adapted. That's the point.

## How it works

- [`AGENTS.md`](AGENTS.md) — the constitution (read by every AGENTS.md-aware tool).
- [`project-management/reference/ADAPTERS.md`](project-management/reference/ADAPTERS.md) — how the canonical-brain + thin-adapter pattern works, per CLI.
- [`project-management/reference/ADDING_AN_AGENT.md`](project-management/reference/ADDING_AN_AGENT.md) — add a class + persona + adapters.
- [`.claude/00_INDEX.md`](.claude/00_INDEX.md) — the L1 router (task → who to activate).

## Supported CLIs

| CLI | Entry file | Invoke a role |
|---|---|---|
| Claude Code | `CLAUDE.md` + `.claude/` | `/janus`, `/aria` (or `/uiux` / `/aria-uiux`), `/core` |
| Codex | `AGENTS.md` + `.agents/skills/` | `act as JANUS` — or `$janus` |
| Cursor | `AGENTS.md` + `.cursor/rules/` | rules route `act as …` |
| Gemini CLI | `GEMINI.md` + `.gemini/` | `/janus`, `/aria` (or `/uiux` / `/aria-uiux`), `/core` |
| Devin | `AGENTS.md` + `.agents/skills/` | `janus` skill (auto / `@skills:janus`) |
| Windsurf · Amp · Aider · Zed · Jules · Copilot · … | `AGENTS.md` | `act as …` (free — one spine, no dedicated adapter) |

---

*This is a template. Once instantiated, replace this README with your project's real one.*
