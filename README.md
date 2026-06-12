# agent-skills — 一個 repo 統一 Claude / Codex / OpenCode

把三個 AI coding agent 的 **skills / agents / commands** 收進**單一 git repo**,用 symlink 接到
各工具,git 跨多台 Mac 同步。

## 佈局

```
~/.agents/                         ← 這個 repo
├── skills/                        手寫 skills(三工具共用);bin/ 腳本在這
│   └── bin/agent-skills.sh
└── opencode/                      OpenCode 專屬(從官方 plugin harvest 而來)
    ├── skills/    agents/    commands/
```

symlink(由 `agent-skills.sh link` 建立):

| 工具路徑 | → |
|----------|---|
| `~/.claude/skills` | `~/.agents/skills` |
| `~/.config/opencode/skills` | `~/.agents/opencode/skills` |
| `~/.config/opencode/agents` | `~/.agents/opencode/agents` |
| `~/.config/opencode/commands` | `~/.agents/opencode/commands` |

- **Codex** 原生掃 `~/.agents/skills`(免 symlink);`~/.codex/skills/.system/` 不碰。
- **手寫 skills**(`skills/`)三工具共用;**OpenCode 專屬的官方 harvest**(`opencode/`)只有 OpenCode 經 symlink 讀,不污染 Claude/Codex。

## 新 Mac 設定

```bash
git clone <this-repo> ~/.agents
~/.agents/skills/bin/agent-skills.sh link     # 建立所有 symlink
# Codex / OpenCode 重啟即生效
```

## 日常

```bash
# 更新官方 harvest(在任一台跑,然後 push)
~/.agents/skills/bin/agent-skills.sh harvest
cd ~/.agents && git add -A && git commit -m "update" && git push
# 另一台:git -C ~/.agents pull

~/.agents/skills/bin/agent-skills.sh status   # 看現況
```

腳本細節見 [`skills/README.md`](skills/README.md)。
