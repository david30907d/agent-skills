#!/usr/bin/env bash
# agent-skills.sh — 統一 Claude / Codex / OpenCode 的 skills/agents/commands,
# 收進「一個」git repo(~/.agents),各工具路徑用 symlink 指進來,git 跨 Mac 同步。
#
# repo 佈局:
#   ~/.agents/
#   ├── bin/agent-skills.sh        ← 本腳本(其實在 skills/bin,見下)
#   ├── skills/                    ← 手寫 skills(三工具共用);bin/ 在這
#   └── opencode/{skills,agents,commands}  ← harvested,OpenCode 專屬
#
# symlink(由 `link` 建立):
#   ~/.claude/skills            -> ~/.agents/skills
#   ~/.config/opencode/skills   -> ~/.agents/opencode/skills
#   ~/.config/opencode/agents   -> ~/.agents/opencode/agents
#   ~/.config/opencode/commands -> ~/.agents/opencode/commands
#
#   init    建立 repo(git init + .gitignore allowlist)
#   import  把散落各處的既有 skill 併入 skills/(新者勝,非破壞)
#   link    建立上述所有 symlink(冪等、可重跑、新 Mac 用)
#   harvest 從官方 plugin 抽 skills/agents/commands 進 opencode/(--dry-run 預覽)
#   status  顯示現況
#   unlink  移除所有 symlink(repo 不動)
# 覆寫:AGENT_SKILLS_REPO=/path(repo root)、SKILLS_SOT=/path(手寫 skills 目錄)
set -euo pipefail

REPO="${AGENT_SKILLS_REPO:-$HOME/.agents}"
SOT="${SKILLS_SOT:-$REPO/skills}"            # 手寫 skills(= Codex/OpenCode 原生 root、Claude symlink 目標)
OC_SKILLS="$REPO/opencode/skills"            # harvested skills(repo 內真實檔)
OC_AGENTS="$REPO/opencode/agents"            # harvested agents
OC_COMMANDS="$REPO/opencode/commands"        # harvested commands
CLAUDE_DIR="$HOME/.claude/skills"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}/skills"
OC_LIVE="$HOME/.config/opencode"             # OpenCode 實際讀的位置(symlink 指回 repo)
TS="$(date +%Y%m%d-%H%M%S)"

# harvest 上游:官方 plugin 路徑(Claude/Codex 各自原生已有,只有 OpenCode 缺)。
# 可加別的 marketplace(如 claude-code-workflows)。
HARVEST_SOURCES=(
  "$HOME/.claude/plugins/marketplaces/claude-plugins-official/plugins"
  "$HOME/.codex/plugins/cache/openai-curated"
)
# 排除(對 skill/agent/command base 名與 plugin 名都比對)
HARVEST_EXCLUDE=" example-skill example-command playground cardputer-buddy m5-onboard example-plugin "

log()    { printf '  %s\n' "$*"; }
section(){ printf '\n== %s ==\n' "$*"; }
is_skill_dir() { [ -f "$1/SKILL.md" ]; }

cmd_init() {
  mkdir -p "$SOT/bin" "$OC_SKILLS" "$OC_AGENTS" "$OC_COMMANDS"
  if [ ! -f "$REPO/.gitignore" ]; then
    printf '/*\n!.gitignore\n!README.md\n!skills\n!opencode\n.DS_Store\n' > "$REPO/.gitignore"
    log "wrote allowlist .gitignore: $REPO/.gitignore"
  fi
  if [ ! -d "$REPO/.git" ]; then ( cd "$REPO" && git init -q ); log "git initialised: $REPO"
  else log "git repo already present: $REPO"; fi
  log "repo ready: $REPO"
}

# 非破壞:只把 src 的 skill 複製進 SOT(新者勝);不動 src;跳過 harvested。
import_from() {
  local src="$1" name found=0
  [ -d "$src" ] || { log "skip (不存在): $src"; return 0; }
  [ -L "$src" ] && { log "skip (已是 symlink): $src"; return 0; }
  for d in "$src"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    case "$name" in .*) continue;; esac
    is_skill_dir "$d" || continue
    [ -f "$d/.harvested-from" ] && continue
    rsync -a --update "$d" "$SOT/$name/"
    found=1; log "imported: $name  (from $src)"
  done
  [ "$found" -eq 0 ] && log "（無可併入的 skill）: $src" || true
}

cmd_import() {
  mkdir -p "$SOT"
  section "import 既有 skill -> $SOT(新者勝、非破壞)"
  import_from "$CLAUDE_DIR"
  import_from "$CODEX_DIR"
  import_from "$OC_SKILLS"
  log "完成。檢視:ls -1 $SOT"
}

# 把 $2 接成指向 $1 的 symlink;真目錄先備份。
relink() {
  local src="$1" tgt="$2" label="$3"
  [ -d "$src" ] || { log "$label: 來源不存在($src),跳過"; return 0; }
  mkdir -p "$(dirname "$tgt")"
  if [ -L "$tgt" ]; then ln -sfn "$src" "$tgt"; log "$label: symlink 刷新 -> $src"
  elif [ -d "$tgt" ]; then mv "$tgt" "$tgt.backup.$TS"; ln -sfn "$src" "$tgt"; log "$label: 真目錄備份 -> $tgt.backup.$TS,改 symlink"
  else ln -sfn "$src" "$tgt"; log "$label: 建立 symlink -> $src"; fi
}

cmd_link() {
  section "link Claude" ; relink "$SOT" "$CLAUDE_DIR" "claude/skills"
  section "link OpenCode"
  relink "$OC_SKILLS"   "$OC_LIVE/skills"   "opencode/skills"
  relink "$OC_AGENTS"   "$OC_LIVE/agents"   "opencode/agents"
  relink "$OC_COMMANDS" "$OC_LIVE/commands" "opencode/commands"
  section "Codex" ; log "原生掃 $SOT,免接線(.system 留在 $CODEX_DIR 不動)"
  log "完成。Codex / OpenCode 需重啟才會載入新內容。"
}

frontmatter_name() {   # $1=SKILL.md → name: 值,fallback 父目錄名
  local n
  n=$(grep -m1 -E '^name:[[:space:]]*' "$1" 2>/dev/null \
        | sed -E 's/^name:[[:space:]]*//; s/^["'\'']//; s/["'\'']$//; s/[[:space:]]*$//')
  [ -n "$n" ] && printf '%s' "$n" || basename "$(dirname "$1")"
}
plugin_of() {   # 從路徑抽 plugin 名(claude marketplace / codex curated 兩種佈局)
  case "$1" in
    */claude-plugins-official/plugins/*) printf '%s' "$1" | sed -E 's|.*/plugins/([^/]+)/.*|\1|';;
    */openai-curated/*)                  printf '%s' "$1" | sed -E 's|.*/openai-curated/([^/]+)/.*|\1|';;
    *) basename "$(dirname "$(dirname "$1")")";;
  esac
}
ns_name() { [ "$1" = "$2" ] && printf '%s' "$2" || printf '%s-%s' "$1" "$2"; }  # $1=plugin $2=base
md_desc() {     # 抽 description(單行),double-quote escape
  awk 'NR>1&&/^---[[:space:]]*$/{exit} /^description:[[:space:]]*/{sub(/^description:[[:space:]]*/,"");print;exit}' "$1" \
    | sed -E 's/^["'\'']//; s/["'\''][[:space:]]*$//; s/[[:space:]]*$//; s/"/\\"/g'
}
md_body() { awk 'f>=2{print} /^---[[:space:]]*$/{f++}' "$1"; }   # 第二個 --- 之後

# agents/commands → OpenCode 原生格式。命名 <plugin>-<base>(同名折疊),frontmatter
# 只留 description(agent 加 mode: subagent),body 原樣。type=agent|command。
harvest_md() {
  local type="$1" sink="$2" glob="$3" dry="$4" f plug base name desc imp=0
  mkdir -p "$sink"
  section "harvest ${type}s -> $sink$([ "$dry" -eq 1 ] && echo '（dry-run)')"
  if [ "$dry" -eq 0 ] && [ -f "$sink/.harvested" ]; then
    while IFS= read -r h; do [ -n "$h" ] && rm -f "$sink/$h"; done < "$sink/.harvested"
    : > "$sink/.harvested"
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    plug="$(plugin_of "$f")"; base="$(basename "$f" .md)"
    case "$HARVEST_EXCLUDE" in *" $base "*|*" $plug "*) continue;; esac
    name="$(ns_name "$plug" "$base")"; desc="$(md_desc "$f")"; [ -n "$desc" ] || desc="imported $type"
    if [ "$dry" -eq 1 ]; then
      log "would $type: $name"
    else
      { printf -- '---\ndescription: "%s"\n' "$desc"
        [ "$type" = agent ] && printf 'mode: subagent\n'
        printf -- '---\n'; md_body "$f"; } > "$sink/$name.md"
      printf '%s\n' "$name.md" >> "$sink/.harvested"
      log "$type: $name"
    fi
    imp=$((imp+1))
  done < <(find "${HARVEST_SOURCES[@]}" -path "$glob" -type f 2>/dev/null | sort)
  log "${type}s imported=$imp"
}

# skills → opencode/skills(dest 目錄名=frontmatter name,mtime 新者優先,撞手寫則跳過)
cmd_harvest() {
  local dry=0; [ "${1:-}" = "--dry-run" ] && dry=1
  mkdir -p "$OC_SKILLS"
  if [ "$dry" -eq 0 ]; then
    for d in "$OC_SKILLS"/*/; do [ -f "$d/.harvested-from" ] && rm -rf "$d"; done
  fi
  section "harvest skills -> $OC_SKILLS$([ "$dry" -eq 1 ] && echo '（dry-run)')"
  local seen=" " f name skilldir imp=0 skp=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    skilldir="$(dirname "$f")"; name="$(frontmatter_name "$f")"
    case "$HARVEST_EXCLUDE" in *" $name "*) log "skip 範例:   $name"; skp=$((skp+1)); continue;; esac
    case "$seen"            in *" $name "*) log "skip 重複:   $name"; skp=$((skp+1)); continue;; esac
    [ -d "$SOT/$name" ] && { log "skip 手寫優先: $name"; skp=$((skp+1)); continue; }
    seen="$seen$name "
    if [ "$dry" -eq 1 ]; then
      log "would skill: $name"
    else
      rsync -a "$skilldir/" "$OC_SKILLS/$name/"
      printf '%s\n' "$skilldir" | sed "s|$HOME|~|" > "$OC_SKILLS/$name/.harvested-from"
      log "skill: $name"
    fi
    imp=$((imp+1))
  done < <(find "${HARVEST_SOURCES[@]}" -path '*/skills/*/SKILL.md' -type f -exec stat -f '%m %N' {} + 2>/dev/null | sort -rn | cut -d' ' -f2-)
  log "skills imported=$imp  skipped=$skp"
  harvest_md agent   "$OC_AGENTS"   '*/agents/*.md'   "$dry"
  harvest_md command "$OC_COMMANDS" '*/commands/*.md' "$dry"
  if [ "$dry" -eq 0 ]; then
    log "完成。OpenCode 重啟生效;commit:cd $REPO && git add -A && git commit && git push"
  fi
}

show_one() {
  local label="$1" path="$2"
  if [ -L "$path" ]; then printf '  %-20s %s -> %s\n' "$label" "$path" "$(readlink "$path")"
  elif [ -d "$path" ]; then printf '  %-20s %s (真目錄)\n' "$label" "$path"
  else printf '  %-20s %s (不存在)\n' "$label" "$path"; fi
}
count_dir() { ls -d "$1"/*/ 2>/dev/null | wc -l | tr -d ' '; }
count_md()  { find "$1" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' '; }

cmd_status() {
  section "repo: $REPO"
  printf '  skills(手寫)   %s 個\n' "$(find "$SOT" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')"
  printf '  opencode/skills   %s 個\n' "$(find "$OC_SKILLS" -name .harvested-from 2>/dev/null | wc -l | tr -d ' ')"
  printf '  opencode/agents   %s 個\n' "$(count_md "$OC_AGENTS")"
  printf '  opencode/commands %s 個\n' "$(count_md "$OC_COMMANDS")"
  section "symlink 接線"
  show_one Claude   "$CLAUDE_DIR"
  show_one "OpenCode skills"   "$OC_LIVE/skills"
  show_one "OpenCode agents"   "$OC_LIVE/agents"
  show_one "OpenCode commands" "$OC_LIVE/commands"
  show_one Codex    "$CODEX_DIR"
}

cmd_unlink() {
  section "unlink(只移除 symlink,repo 不動)"
  for t in "$CLAUDE_DIR" "$OC_LIVE/skills" "$OC_LIVE/agents" "$OC_LIVE/commands"; do
    [ -L "$t" ] && { rm "$t"; log "移除 symlink: $t"; } || log "非 symlink,跳過: $t"
  done
}

case "${1:-}" in
  init) cmd_init;; import) cmd_import;; link) cmd_link;;
  harvest) cmd_harvest "${2:-}";;
  status) cmd_status;; unlink) cmd_unlink;;
  *) echo "usage: $0 {init|import|link|harvest [--dry-run]|status|unlink}"; exit 1;;
esac
