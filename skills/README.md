# agent skills — single source of truth

統一 **Claude Code / Codex / OpenCode** 的 global skills。這個目錄(`~/.agents/skills`)是
唯一的真實檔案,用 git 在多台 Mac 之間同步。

## 為什麼是這個目錄

| 工具 | 讀取方式 |
|------|----------|
| **Codex** | 原生掃 `$HOME/.agents/skills`(官方 personal skills root)→ 直接讀本目錄,零接線。`~/.codex/skills/.system/` 的系統 skill 留在原地、互不干擾。 |
| **OpenCode** | 原生掃 `~/.agents/skills`(也掃 `~/.claude/skills`,按 skill 名稱去重)→ 零接線。 |
| **Claude Code** | 只讀 `~/.claude/skills` → 由 `bin/agent-skills.sh link` 把它 symlink 到這裡。 |

每個 skill 是一個含 `SKILL.md` 的子目錄。`bin/` 與本 README 不是 skill(無 `SKILL.md`),會被各工具忽略。

## 用法

```bash
# 第一台 Mac(已建立完成):
bin/agent-skills.sh init      # 建目錄 + git init
bin/agent-skills.sh import    # 把散落各處的既有 skill 併進來(新者勝、非破壞)
bin/agent-skills.sh link      # 接線:Claude → symlink;Codex/OpenCode 原生免動
bin/agent-skills.sh status    # 看現況

# 推上遠端後,其他 Mac:
git clone <repo> ~/.agents/skills
~/.agents/skills/bin/agent-skills.sh link
```

`SKILLS_SOT=/path` 可覆寫本目錄位置。

## 日後新增 / 修改 skill

直接編輯 `~/.agents/skills/<name>/` → `git commit && git push`。三個工具全部自動生效
(Codex / OpenCode 原生掃、Claude 經 symlink);**Codex 需重啟**才會載入新 skill。

## harvest:把官方 plugin 的能力餵給 OpenCode

Claude / Codex 各自會從官方 plugin 渠道拿到一批高品質的 **skills / agents / commands**,但
**OpenCode 三者都讀不到**(它不掃 Claude plugin marketplace,也不掃 Codex plugin cache)。
`harvest` 把這兩個「上游」的能力**各歸各位**抽進 OpenCode **專屬**目錄(只有 OpenCode 讀 →
Claude/Codex 不會重複看到自己的東西):

| 上游組件 | → OpenCode sink |
|---------|-----------------|
| `*/skills/*/SKILL.md` | `~/.config/opencode/skills/<name>/` |
| `*/agents/*.md`       | `~/.config/opencode/agents/<plugin-name>.md`(加 `mode: subagent`) |
| `*/commands/*.md`     | `~/.config/opencode/commands/<plugin-name>.md` |

```bash
bin/agent-skills.sh harvest --dry-run   # 預覽會抽/跳過什麼
bin/agent-skills.sh harvest             # 寫進三個 sink
```

- 上游 = `~/.claude/plugins/marketplaces/claude-plugins-official/plugins` +
  `~/.codex/plugins/cache/openai-curated`(腳本頂部 `HARVEST_SOURCES` 可加,如 claude-code-workflows)。
- **skills**:dest 目錄名 = frontmatter `name:`、mtime 新者優先、撞到本 SOT 手寫 skill 則跳過、
  帶 `.harvested-from` breadcrumb;**agents/commands**:命名 `<plugin>-<base>`(同名折疊)避免撞名,
  frontmatter 只留 `description`(agent 加 `mode: subagent`),body 原樣(佔位符 `$ARGUMENTS` 與 Claude 相同),
  每個 sink 用 `.harvested` 清單記錄、重跑只清前次、保留手寫的。
- **永不 symlink/手改上游 cache**(會被官方重建,且無 Claude-compat);要更新就重跑 `harvest`。
- agents/commands 為**可重生**(各 Mac 跑 `harvest` 即可);skills sink 可選擇性當獨立 repo commit
  (`cd ~/.config/opencode/skills && git add -A && git commit`)給沒裝 plugin 的 Mac。
