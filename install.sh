#!/usr/bin/env bash
# vallorcine install script
# Installs TDD pipeline + KB/Decisions agents into a Claude Code project.
#
# Usage:
#   bash install.sh                    # install into current directory
#   bash install.sh /path/to/project   # install into target path
#   bash install.sh --dev              # install to a temp directory (for local testing)
#   bash install.sh --diff /path       # show what would change without writing
#
# Options:
#   FORCE_UPDATE=1 bash install.sh     # overwrite all existing files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "unknown")"

# ── Argument handling ─────────────────────────────────────────────────────────

DEV_MODE=0
DIFF_MODE=0
TARGET=""

for arg in "$@"; do
    case "$arg" in
        --dev)  DEV_MODE=1 ;;
        --diff) DIFF_MODE=1 ;;
        *)      TARGET="$arg" ;;
    esac
done

if [[ "$DEV_MODE" == "1" ]]; then
    TARGET="$(mktemp -d)"
    echo "Dev mode: installing to temp directory $TARGET"
elif [[ -z "$TARGET" ]]; then
    TARGET="$(pwd)"
fi

FORCE="${FORCE_UPDATE:-0}"

# ── Colour helpers ────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

skipped=0
created=0
changed=0
unchanged=0

# ── Safety guard: prevent installing into the vallorcine repo itself ─────────

if [[ "$DEV_MODE" != "1" && -f "$TARGET/install.sh" && -f "$TARGET/VERSION" ]]; then
    RESOLVED_TARGET="$(cd "$TARGET" && pwd)"
    if [[ "$RESOLVED_TARGET" == "$SCRIPT_DIR" ]]; then
        echo ""
        echo -e "${YELLOW}⚠  Target directory is the vallorcine repo itself.${NC}"
        echo "   This would overwrite source files in .claude/commands/."
        echo ""
        echo "   Use --dev for local testing (installs to a temp directory):"
        echo "     bash install.sh --dev"
        echo ""
        echo "   Or specify a different target project:"
        echo "     bash install.sh /path/to/your/project"
        echo ""
        exit 1
    fi
fi

# ── Install helper ────────────────────────────────────────────────────────────

install_file() {
    local src="$1"
    local dst="$2"
    mkdir -p "$(dirname "$dst")"

    if [[ "$DIFF_MODE" == "1" ]]; then
        # Diff mode: show what would change, don't write
        if [[ ! -f "$dst" ]]; then
            echo -e "  ${GREEN}new${NC}    $dst"
            ((changed++)) || true
        elif diff -q "$src" "$dst" >/dev/null 2>&1; then
            ((unchanged++)) || true
        else
            echo -e "  ${YELLOW}changed${NC} $dst"
            diff --unified=3 "$dst" "$src" 2>/dev/null | head -30 || true
            echo ""
            ((changed++)) || true
        fi
        return
    fi

    if [[ -f "$dst" && "$FORCE" != "1" ]]; then
        echo -e "  ${YELLOW}skip${NC}  $dst"
        ((skipped++)) || true
    else
        cp "$src" "$dst"
        echo -e "  ${GREEN}write${NC} $dst"
        ((created++)) || true
    fi
}

# ── Header ────────────────────────────────────────────────────────────────────

echo ""
if [[ "$DIFF_MODE" == "1" ]]; then
    echo -e "${BLUE}vallorcine v${VERSION} — diff mode (showing changes for: $TARGET)${NC}"
elif [[ "$DEV_MODE" == "1" ]]; then
    echo -e "${BLUE}vallorcine v${VERSION} — dev mode (installing into temp directory)${NC}"
else
    echo -e "${BLUE}vallorcine v${VERSION} — installing into: $TARGET${NC}"
fi
echo "────────────────────────────────────────────────"

# ── Version mismatch warning ──────────────────────────────────────────────────

INSTALLED_VERSION_FILE="$TARGET/.claude/.vallorcine-version"
if [[ -f "$INSTALLED_VERSION_FILE" ]]; then
    INSTALLED_VERSION="$(cat "$INSTALLED_VERSION_FILE")"
    if [[ "$INSTALLED_VERSION" != "$VERSION" ]]; then
        echo ""
        echo -e "  ${YELLOW}⚠  Existing install detected: v${INSTALLED_VERSION} → v${VERSION}${NC}"
        echo -e "     Version mismatch — forcing update of all kit files."
        FORCE=1
    fi
fi

# ── Skills (slash commands) ───────────────────────────────────────────────────

echo ""
echo "── Skills ───────────────────────────────────────"
for d in "$SCRIPT_DIR"/skills/*/; do
    skill_name="$(basename "$d")"
    install_file "$d/SKILL.md" "$TARGET/.claude/skills/$skill_name/SKILL.md"

    # Install additional files in the skill directory (e.g., extraction-mode.md)
    for extra_file in "$d"*.md; do
        [[ "$(basename "$extra_file")" == "SKILL.md" ]] && continue
        install_file "$extra_file" "$TARGET/.claude/skills/$skill_name/$(basename "$extra_file")"
    done

    # Clean up pre-migration command file if it exists (commands/ → skills/ migration)
    old_cmd="$TARGET/.claude/commands/$skill_name.md"
    if [[ -f "$old_cmd" && "$DIFF_MODE" != "1" ]]; then
        rm "$old_cmd"
        echo -e "  ${YELLOW}migrate${NC} removed stale .claude/commands/$skill_name.md"
    fi
done

# Remove empty commands/ directory after migration cleanup
if [[ -d "$TARGET/.claude/commands" && "$DIFF_MODE" != "1" ]]; then
    if [[ -z "$(ls -A "$TARGET/.claude/commands" 2>/dev/null)" ]]; then
        rmdir "$TARGET/.claude/commands"
        echo -e "  ${YELLOW}migrate${NC} removed empty .claude/commands/"
    fi
fi

# ── Agent definitions ─────────────────────────────────────────────────────────

echo ""
echo "── Agent definitions ────────────────────────────"
for f in "$SCRIPT_DIR"/agents/*.md; do
    install_file "$f" "$TARGET/.claude/agents/$(basename "$f")"
done

# ── Rules ─────────────────────────────────────────────────────────────────────

echo ""
echo "── Rules ────────────────────────────────────────"
for f in "$SCRIPT_DIR"/rules/*.md; do
    install_file "$f" "$TARGET/.claude/rules/$(basename "$f")"
done

# ── KB seed files (never overwrite — these are user-populated data) ───────────
#
# FORCE_UPDATE must not overwrite seed files. Users populate these indexes
# with research and decisions. Overwriting with empty seeds destroys data.
# Only write if the file does not exist (first install).

echo ""
echo "── KB seed files ────────────────────────────────"

_install_seed() {
    local src="$1"
    local dst="$2"
    mkdir -p "$(dirname "$dst")"

    if [[ "$DIFF_MODE" == "1" ]]; then
        if [[ ! -f "$dst" ]]; then
            echo -e "  ${GREEN}new${NC}    $dst"
            ((changed++)) || true
        else
            ((unchanged++)) || true
        fi
        return
    fi

    if [[ -f "$dst" ]]; then
        echo -e "  ${YELLOW}skip${NC}  $dst  (user data — never overwritten)"
        ((skipped++)) || true
    else
        cp "$src" "$dst"
        echo -e "  ${GREEN}write${NC} $dst"
        ((created++)) || true
    fi
}

_install_seed "$SCRIPT_DIR/kb/CLAUDE.md"                              "$TARGET/.kb/CLAUDE.md"
_install_seed "$SCRIPT_DIR/kb/_refs/complexity-notation.md"           "$TARGET/.kb/_refs/complexity-notation.md"
_install_seed "$SCRIPT_DIR/kb/_refs/benchmarking-methodology.md"      "$TARGET/.kb/_refs/benchmarking-methodology.md"
_install_seed "$SCRIPT_DIR/kb/_refs/adversarial-finding-template.md"  "$TARGET/.kb/_refs/adversarial-finding-template.md"
_install_seed "$SCRIPT_DIR/kb/_refs/feature-footprint-template.md"    "$TARGET/.kb/_refs/feature-footprint-template.md"

# ── Decisions seed files (never overwrite — same as KB) ──────────────────────

echo ""
echo "── Decisions seed files ─────────────────────────"
_install_seed "$SCRIPT_DIR/decisions/CLAUDE.md" "$TARGET/.decisions/CLAUDE.md"

# ── Spec seed files (never overwrite — same as KB / Decisions) ────────────

echo ""
echo "── Spec seed files ──────────────────────────────"
_install_seed "$SCRIPT_DIR/spec/CLAUDE.md" "$TARGET/.spec/CLAUDE.md"

# ── Work seed files (never overwrite — same as KB / Decisions / Spec) ─────

echo ""
echo "── Work seed files ──────────────────────────────"
_install_seed "$SCRIPT_DIR/work/CLAUDE.md" "$TARGET/.work/CLAUDE.md"

# ── Curation directory ────────────────────────────────────────────────────

echo ""
echo "── Curation ─────────────────────────────────"
if [[ "$DIFF_MODE" != "1" ]]; then
    mkdir -p "$TARGET/.curate"
    echo -e "  ${GREEN}ready${NC} .curate/ directory"
else
    if [[ ! -d "$TARGET/.curate" ]]; then
        echo -e "  ${GREEN}new${NC}    .curate/"
        ((changed++)) || true
    else
        ((unchanged++)) || true
    fi
fi

# ── Audit prompts ─────────────────────────────────────────────────────────────

echo ""
echo "── Audit prompts ──────────────────────────────────"
mkdir -p "$TARGET/.claude/prompts/audit"
for f in "$SCRIPT_DIR"/prompts/audit/*.md "$SCRIPT_DIR"/prompts/audit/*.py "$SCRIPT_DIR"/prompts/audit/*.sh "$SCRIPT_DIR"/prompts/audit/*.js; do
    [[ -f "$f" ]] || continue
    install_file "$f" "$TARGET/.claude/prompts/audit/$(basename "$f")"
done

# ── Scripts ───────────────────────────────────────────────────────────────────

echo ""
echo "── Scripts ──────────────────────────────────────"
install_file "$SCRIPT_DIR/scripts/token-usage.sh" "$TARGET/.claude/scripts/token-usage.sh"
install_file "$SCRIPT_DIR/scripts/version-check.sh" "$TARGET/.claude/scripts/version-check.sh"
install_file "$SCRIPT_DIR/scripts/merge-driver-index.sh" "$TARGET/.claude/scripts/merge-driver-index.sh"
install_file "$SCRIPT_DIR/scripts/ensure-merge-driver.sh" "$TARGET/.claude/scripts/ensure-merge-driver.sh"
install_file "$SCRIPT_DIR/scripts/kb-freshness-check.sh" "$TARGET/.claude/scripts/kb-freshness-check.sh"
install_file "$SCRIPT_DIR/scripts/kb-search.sh" "$TARGET/.claude/scripts/kb-search.sh"
install_file "$SCRIPT_DIR/scripts/kb-search.py" "$TARGET/.claude/scripts/kb-search.py"
install_file "$SCRIPT_DIR/scripts/kb-search.js" "$TARGET/.claude/scripts/kb-search.js"
install_file "$SCRIPT_DIR/scripts/adr-validate.sh" "$TARGET/.claude/scripts/adr-validate.sh"
install_file "$SCRIPT_DIR/scripts/token-stop-hook.sh" "$TARGET/.claude/scripts/token-stop-hook.sh"
install_file "$SCRIPT_DIR/scripts/curate-scan.sh" "$TARGET/.claude/scripts/curate-scan.sh"
install_file "$SCRIPT_DIR/scripts/curate-review-log.sh" "$TARGET/.claude/scripts/curate-review-log.sh"
install_file "$SCRIPT_DIR/scripts/lens-registry.txt" "$TARGET/.claude/scripts/lens-registry.txt"
install_file "$SCRIPT_DIR/scripts/decisions-scan.sh" "$TARGET/.claude/scripts/decisions-scan.sh"
install_file "$SCRIPT_DIR/scripts/audit-budget.sh" "$TARGET/.claude/scripts/audit-budget.sh"
install_file "$SCRIPT_DIR/scripts/extract-findings.sh" "$TARGET/.claude/scripts/extract-findings.sh"
install_file "$SCRIPT_DIR/scripts/index-verify.sh" "$TARGET/.claude/scripts/index-verify.sh"
install_file "$SCRIPT_DIR/scripts/statusline.sh" "$TARGET/.claude/scripts/statusline.sh"
install_file "$SCRIPT_DIR/scripts/statusline.py" "$TARGET/.claude/scripts/statusline.py"
install_file "$SCRIPT_DIR/scripts/statusline.js" "$TARGET/.claude/scripts/statusline.js"
install_file "$SCRIPT_DIR/scripts/statusline-wrapper.sh" "$TARGET/.claude/scripts/statusline-wrapper.sh"
install_file "$SCRIPT_DIR/scripts/token-stop-hook.py" "$TARGET/.claude/scripts/token-stop-hook.py"
install_file "$SCRIPT_DIR/scripts/token-stop-hook.js" "$TARGET/.claude/scripts/token-stop-hook.js"
install_file "$SCRIPT_DIR/scripts/token-hook-wrapper.sh" "$TARGET/.claude/scripts/token-hook-wrapper.sh"
install_file "$SCRIPT_DIR/scripts/subagent-hook.sh" "$TARGET/.claude/scripts/subagent-hook.sh"
install_file "$SCRIPT_DIR/scripts/subagent-hook.py" "$TARGET/.claude/scripts/subagent-hook.py"
install_file "$SCRIPT_DIR/scripts/subagent-hook.js" "$TARGET/.claude/scripts/subagent-hook.js"
install_file "$SCRIPT_DIR/scripts/subagent-hook-wrapper.sh" "$TARGET/.claude/scripts/subagent-hook-wrapper.sh"
install_file "$SCRIPT_DIR/scripts/precompact-hook.sh" "$TARGET/.claude/scripts/precompact-hook.sh"
install_file "$SCRIPT_DIR/scripts/uninstall.sh" "$TARGET/.claude/scripts/uninstall.sh"
install_file "$SCRIPT_DIR/scripts/spec-lib.sh" "$TARGET/.claude/scripts/spec-lib.sh"
install_file "$SCRIPT_DIR/scripts/audit-state-gate.sh" "$TARGET/.claude/scripts/audit-state-gate.sh"
install_file "$SCRIPT_DIR/scripts/spec-validate.sh" "$TARGET/.claude/scripts/spec-validate.sh"
install_file "$SCRIPT_DIR/scripts/spec-ambiguity-score.sh" "$TARGET/.claude/scripts/spec-ambiguity-score.sh"
install_file "$SCRIPT_DIR/scripts/spec-stats.sh" "$TARGET/.claude/scripts/spec-stats.sh"
install_file "$SCRIPT_DIR/scripts/spec-resolve.sh" "$TARGET/.claude/scripts/spec-resolve.sh"
install_file "$SCRIPT_DIR/scripts/spec-obligations-gc.sh" "$TARGET/.claude/scripts/spec-obligations-gc.sh"
install_file "$SCRIPT_DIR/scripts/spec-trace.sh" "$TARGET/.claude/scripts/spec-trace.sh"
install_file "$SCRIPT_DIR/scripts/spec-split.sh" "$TARGET/.claude/scripts/spec-split.sh"
install_file "$SCRIPT_DIR/scripts/spec-coverage.sh" "$TARGET/.claude/scripts/spec-coverage.sh"
install_file "$SCRIPT_DIR/scripts/spec-backfill-candidates.sh" "$TARGET/.claude/scripts/spec-backfill-candidates.sh"
install_file "$SCRIPT_DIR/scripts/spec-backfill-log.sh" "$TARGET/.claude/scripts/spec-backfill-log.sh"
install_file "$SCRIPT_DIR/scripts/work-lib.sh" "$TARGET/.claude/scripts/work-lib.sh"
install_file "$SCRIPT_DIR/scripts/work-resolve.sh" "$TARGET/.claude/scripts/work-resolve.sh"
install_file "$SCRIPT_DIR/scripts/work-validate.sh" "$TARGET/.claude/scripts/work-validate.sh"
install_file "$SCRIPT_DIR/scripts/work-context.sh" "$TARGET/.claude/scripts/work-context.sh"
install_file "$SCRIPT_DIR/scripts/work-finalize.sh" "$TARGET/.claude/scripts/work-finalize.sh"
install_file "$SCRIPT_DIR/scripts/narrative-wrapper.sh" "$TARGET/.claude/scripts/narrative-wrapper.sh"
chmod +x "$TARGET/.claude/scripts/narrative-wrapper.sh" 2>/dev/null || true
mkdir -p "$TARGET/.claude/scripts/narrative"
# Install all narrative pipeline files (Python + JS)
for f in "$SCRIPT_DIR"/scripts/narrative/*.py "$SCRIPT_DIR"/scripts/narrative/*.js; do
    [[ -f "$f" ]] || continue
    install_file "$f" "$TARGET/.claude/scripts/narrative/$(basename "$f")"
done

# ── Upgrade script ───────────────────────────────────────────────────────────

echo ""
echo "── Upgrade script ───────────────────────────────"
install_file "$SCRIPT_DIR/upgrade.sh" "$TARGET/.claude/upgrade.sh"
chmod +x "$TARGET/.claude/upgrade.sh" 2>/dev/null || true
chmod +x "$TARGET/.claude/scripts/uninstall.sh" 2>/dev/null || true
chmod +x "$TARGET/.claude/scripts/audit-state-gate.sh" 2>/dev/null || true
chmod +x "$TARGET/.claude/scripts/spec-validate.sh" 2>/dev/null || true
chmod +x "$TARGET/.claude/scripts/spec-ambiguity-score.sh" 2>/dev/null || true
chmod +x "$TARGET/.claude/scripts/spec-stats.sh" 2>/dev/null || true
chmod +x "$TARGET/.claude/scripts/spec-resolve.sh" 2>/dev/null || true
chmod +x "$TARGET/.claude/scripts/spec-obligations-gc.sh" 2>/dev/null || true
chmod +x "$TARGET/.claude/scripts/spec-trace.sh" 2>/dev/null || true
chmod +x "$TARGET/.claude/scripts/spec-split.sh" 2>/dev/null || true
chmod +x "$TARGET/.claude/scripts/spec-coverage.sh" 2>/dev/null || true
chmod +x "$TARGET/.claude/scripts/spec-backfill-candidates.sh" 2>/dev/null || true
chmod +x "$TARGET/.claude/scripts/spec-backfill-log.sh" 2>/dev/null || true
chmod +x "$TARGET/.claude/scripts/work-resolve.sh" 2>/dev/null || true
chmod +x "$TARGET/.claude/scripts/work-validate.sh" 2>/dev/null || true
chmod +x "$TARGET/.claude/scripts/work-context.sh" 2>/dev/null || true
chmod +x "$TARGET/.claude/scripts/work-finalize.sh" 2>/dev/null || true

# ── Merge driver for index files ──────────────────────────────────────────────

echo ""
echo "── Merge driver ─────────────────────────────────"

# Register the merge driver in the project's git config (local, not global)
if git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
    DRIVER_PATH=".claude/scripts/merge-driver-index.sh"
    git -C "$TARGET" config merge.vallorcine-index.name "vallorcine index merge (keep all rows)"
    git -C "$TARGET" config merge.vallorcine-index.driver "bash $DRIVER_PATH %O %A %B"
    echo -e "  ${GREEN}config${NC} merge.vallorcine-index.driver registered"
else
    echo -e "  ${YELLOW}skip${NC}  not a git repo — merge driver not registered"
fi

# Add .gitattributes entries if not already present
GITATTRIBUTES="$TARGET/.gitattributes"
MARKER="# vallorcine merge driver"

if ! grep -qF "$MARKER" "$GITATTRIBUTES" 2>/dev/null; then
    cat >> "$GITATTRIBUTES" << 'GITATTR'

# vallorcine merge driver — scoped to managed index files only
# Auto-resolves concurrent table row additions by keeping all rows.
.kb/CLAUDE.md           merge=vallorcine-index
.kb/*/CLAUDE.md         merge=vallorcine-index
.kb/*/*/CLAUDE.md       merge=vallorcine-index
.decisions/CLAUDE.md    merge=vallorcine-index
.work/CLAUDE.md         merge=vallorcine-index
GITATTR
    echo -e "  ${GREEN}write${NC} .gitattributes  (merge driver entries)"
else
    echo -e "  ${YELLOW}skip${NC}  .gitattributes already has merge driver entries"
fi

# ── Token tracking Stop hook in settings.json ─────────────────────────────────

echo ""
echo "── Token tracking hook ──────────────────────────"

SETTINGS_FILE="$TARGET/.claude/settings.json"
HOOK_MARKER="token-stop-hook"
STATUSLINE_MARKER="statusline"
SUBAGENT_MARKER="subagent-hook"

if [[ "$DIFF_MODE" != "1" ]]; then
    # ── Stop hook for token tracking ──────────────────────────────────────
    if [[ -f "$SETTINGS_FILE" ]] && grep -qF "$HOOK_MARKER" "$SETTINGS_FILE" 2>/dev/null; then
        echo -e "  ${YELLOW}skip${NC}  Stop hook already registered"
    else
        if [[ -f "$SETTINGS_FILE" ]] && command -v jq &>/dev/null; then
            jq '.hooks.Stop = ((.hooks.Stop // []) + [{
                "hooks": [{
                    "type": "command",
                    "command": "bash .claude/scripts/token-hook-wrapper.sh"
                }]
            }])' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
            echo -e "  ${GREEN}merge${NC} Stop hook added to settings.json"
        elif [[ ! -f "$SETTINGS_FILE" ]]; then
            cat > "$SETTINGS_FILE" << 'HOOKJSON'
{
  "permissions": {
    "allow": [
      "Bash(bash .claude/scripts/curate-scan.sh:*)",
      "Bash(bash .claude/scripts/curate-review-log.sh:*)",
      "Bash(bash .claude/scripts/kb-freshness-check.sh:*)",
      "Bash(bash .claude/scripts/version-check.sh:*)",
      "Bash(bash .claude/scripts/ensure-merge-driver.sh:*)",
      "Bash(bash .claude/scripts/adr-validate.sh:*)",
      "Bash(bash .claude/scripts/index-verify.sh:*)",
      "Bash(bash .claude/scripts/narrative-wrapper.sh:*)",
      "Bash(bash .claude/scripts/spec-validate.sh:*)",
      "Bash(bash .claude/scripts/spec-ambiguity-score.sh:*)",
      "Bash(bash .claude/scripts/audit-state-gate.sh:*)",
      "Bash(bash .claude/scripts/spec-stats.sh:*)",
      "Bash(bash .claude/scripts/spec-resolve.sh:*)",
      "Bash(bash .claude/scripts/spec-obligations-gc.sh:*)",
      "Bash(bash .claude/scripts/spec-trace.sh:*)",
      "Bash(bash .claude/scripts/spec-split.sh:*)",
      "Bash(bash .claude/scripts/spec-coverage.sh:*)",
      "Bash(bash .claude/scripts/spec-backfill-candidates.sh:*)",
      "Bash(bash .claude/scripts/spec-backfill-log.sh:*)",
      "Bash(bash .claude/scripts/work-resolve.sh:*)",
      "Bash(bash .claude/scripts/work-validate.sh:*)",
      "Bash(bash .claude/scripts/work-context.sh:*)",
      "Bash(bash .claude/scripts/work-finalize.sh:*)"
    ]
  },
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/scripts/token-stop-hook.sh"
          }
        ]
      }
    ]
  }
}
HOOKJSON
            echo -e "  ${GREEN}write${NC} settings.json with Stop hook"
        else
            echo -e "  ${YELLOW}skip${NC}  settings.json exists but jq not available — add hooks manually"
        fi
    fi

    # ── Status line ───────────────────────────────────────────────────────
    if [[ -f "$SETTINGS_FILE" ]] && grep -qF "$STATUSLINE_MARKER" "$SETTINGS_FILE" 2>/dev/null; then
        echo -e "  ${YELLOW}skip${NC}  Status line already configured"
    elif [[ -f "$SETTINGS_FILE" ]] && command -v jq &>/dev/null; then
        jq '.statusLine = {
            "type": "command",
            "command": "bash .claude/scripts/statusline-wrapper.sh"
        }' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        echo -e "  ${GREEN}merge${NC} Status line added to settings.json"
    elif [[ -f "$SETTINGS_FILE" ]]; then
        echo -e "  ${YELLOW}skip${NC}  settings.json exists but jq not available — add statusLine manually"
    fi

    # ── SubagentStart/SubagentStop hooks ─────────────────────────────
    if [[ -f "$SETTINGS_FILE" ]] && grep -qF "$SUBAGENT_MARKER" "$SETTINGS_FILE" 2>/dev/null; then
        echo -e "  ${YELLOW}skip${NC}  Subagent hooks already registered"
    elif [[ -f "$SETTINGS_FILE" ]] && command -v jq &>/dev/null; then
        jq '.hooks.SubagentStart = ((.hooks.SubagentStart // []) + [{
            "hooks": [{
                "type": "command",
                "command": "bash .claude/scripts/subagent-hook-wrapper.sh"
            }]
        }]) | .hooks.SubagentStop = ((.hooks.SubagentStop // []) + [{
            "hooks": [{
                "type": "command",
                "command": "bash .claude/scripts/subagent-hook-wrapper.sh"
            }]
        }])' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        echo -e "  ${GREEN}merge${NC} SubagentStart/SubagentStop hooks added to settings.json"
    elif [[ -f "$SETTINGS_FILE" ]]; then
        echo -e "  ${YELLOW}skip${NC}  settings.json exists but jq not available — add subagent hooks manually"
    fi

    # ── PreCompact hook for crash recovery ───────────────────────────
    PRECOMPACT_MARKER="precompact-hook"
    if [[ -f "$SETTINGS_FILE" ]] && grep -qF "$PRECOMPACT_MARKER" "$SETTINGS_FILE" 2>/dev/null; then
        echo -e "  ${YELLOW}skip${NC}  PreCompact hook already registered"
    elif [[ -f "$SETTINGS_FILE" ]] && command -v jq &>/dev/null; then
        jq '.hooks.PreCompact = ((.hooks.PreCompact // []) + [{
            "hooks": [{
                "type": "command",
                "command": "bash .claude/scripts/precompact-hook.sh"
            }]
        }])' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        echo -e "  ${GREEN}merge${NC} PreCompact hook added to settings.json"
    elif [[ -f "$SETTINGS_FILE" ]]; then
        echo -e "  ${YELLOW}skip${NC}  settings.json exists but jq not available — add PreCompact hook manually"
    fi

    # ── Migrate old direct script references to wrappers ─────────────
    if [[ -f "$SETTINGS_FILE" ]] && command -v jq &>/dev/null; then
        # Migrate token-stop-hook.sh → token-hook-wrapper.sh
        if grep -qF "token-stop-hook.sh" "$SETTINGS_FILE" 2>/dev/null; then
            sed -i 's|token-stop-hook\.sh|token-hook-wrapper.sh|g' "$SETTINGS_FILE"
            echo -e "  ${GREEN}migrate${NC} Stop hook → wrapper"
        fi
        # Migrate statusline.sh → statusline-wrapper.sh (but not statusline-wrapper.sh)
        if grep -q 'statusline\.sh[^a-z]' "$SETTINGS_FILE" 2>/dev/null && \
           ! grep -qF "statusline-wrapper.sh" "$SETTINGS_FILE" 2>/dev/null; then
            sed -i 's|scripts/statusline\.sh|scripts/statusline-wrapper.sh|g' "$SETTINGS_FILE"
            echo -e "  ${GREEN}migrate${NC} Status line → wrapper"
        fi
    fi

    # ── Script permissions (explicit per-script, not wildcard) ─────────
    SCRIPT_PERM_MARKER="curate-scan.sh"
    if [[ -f "$SETTINGS_FILE" ]] && grep -qF "$SCRIPT_PERM_MARKER" "$SETTINGS_FILE" 2>/dev/null; then
        echo -e "  ${YELLOW}skip${NC}  Script permissions already configured"
    elif [[ -f "$SETTINGS_FILE" ]] && command -v jq &>/dev/null; then
        jq '.permissions.allow = ((.permissions.allow // []) + [
            "Bash(bash .claude/scripts/curate-scan.sh:*)",
      "Bash(bash .claude/scripts/curate-review-log.sh:*)",
            "Bash(bash .claude/scripts/kb-freshness-check.sh:*)",
            "Bash(bash .claude/scripts/version-check.sh:*)",
            "Bash(bash .claude/scripts/ensure-merge-driver.sh:*)",
            "Bash(bash .claude/scripts/adr-validate.sh:*)",
            "Bash(bash .claude/scripts/index-verify.sh:*)",
            "Bash(bash .claude/scripts/narrative-wrapper.sh:*)",
      "Bash(bash .claude/scripts/spec-validate.sh:*)",
      "Bash(bash .claude/scripts/spec-ambiguity-score.sh:*)",
      "Bash(bash .claude/scripts/audit-state-gate.sh:*)",
      "Bash(bash .claude/scripts/spec-stats.sh:*)",
      "Bash(bash .claude/scripts/spec-resolve.sh:*)",
      "Bash(bash .claude/scripts/spec-obligations-gc.sh:*)",
      "Bash(bash .claude/scripts/spec-trace.sh:*)",
      "Bash(bash .claude/scripts/spec-split.sh:*)",
      "Bash(bash .claude/scripts/spec-coverage.sh:*)",
      "Bash(bash .claude/scripts/spec-backfill-candidates.sh:*)",
      "Bash(bash .claude/scripts/spec-backfill-log.sh:*)",
      "Bash(bash .claude/scripts/work-resolve.sh:*)",
      "Bash(bash .claude/scripts/work-validate.sh:*)",
      "Bash(bash .claude/scripts/work-context.sh:*)",
      "Bash(bash .claude/scripts/work-finalize.sh:*)"
        ] | unique)' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        echo -e "  ${GREEN}merge${NC} Script permissions added to settings.json"
    elif [[ -f "$SETTINGS_FILE" ]]; then
        echo -e "  ${YELLOW}skip${NC}  settings.json exists but jq not available — add permissions manually"
    fi
else
    if [[ -f "$SETTINGS_FILE" ]] && grep -qF "$HOOK_MARKER" "$SETTINGS_FILE" 2>/dev/null; then
        ((unchanged++)) || true
    else
        echo -e "  ${GREEN}new${NC}    Stop hook + status line in settings.json"
        ((changed++)) || true
    fi
fi

# ── Gitignore for runtime files ───────────────────────────────────────────────

echo ""
echo "── Gitignore (runtime files) ────────────────────"

GITIGNORE="$TARGET/.gitignore"
IGNORE_MARKER="# vallorcine runtime files"

# Entries added in newer releases that an existing install (with the runtime
# block already in place) would otherwise miss. Listed here so the upgrade
# path can append any that are not already present.
NEW_GITIGNORE_ENTRIES=(
    ".spec/.split-log/"
    ".spec/.split-plan.json"
)

if [[ "$DIFF_MODE" != "1" ]]; then
    if ! grep -qF "$IGNORE_MARKER" "$GITIGNORE" 2>/dev/null; then
        cat >> "$GITIGNORE" << 'GITIGNOREBLOCK'

# vallorcine runtime files — generated at runtime, not committed
.claude/.statusline-baseline
.claude/.token-state
.claude/.token-checkpoint
.claude/.subagent-state
.feature/
.curate/
.spec/.split-log/
.spec/.split-plan.json
__pycache__/
GITIGNOREBLOCK
        echo -e "  ${GREEN}write${NC} .gitignore  (runtime file entries)"
    else
        # Existing install: append any newly-introduced entries that aren't
        # already listed. Without this, users who installed before v0.16.x
        # would never pick up the spec-split runtime artifacts and would
        # commit per-machine logs/plans.
        added=()
        for entry in "${NEW_GITIGNORE_ENTRIES[@]}"; do
            if ! grep -qxF "$entry" "$GITIGNORE" 2>/dev/null; then
                echo "$entry" >> "$GITIGNORE"
                added+=("$entry")
            fi
        done
        if (( ${#added[@]} > 0 )); then
            echo -e "  ${GREEN}update${NC} .gitignore  (added ${#added[@]} new entries: ${added[*]})"
        else
            echo -e "  ${YELLOW}skip${NC}  .gitignore already has runtime file entries"
        fi
    fi
else
    if ! grep -qF "$IGNORE_MARKER" "$GITIGNORE" 2>/dev/null; then
        echo -e "  ${GREEN}new${NC}    .gitignore runtime file entries"
        ((changed++)) || true
    else
        # Diff mode: count missing entries as a "would-add" signal.
        missing_count=0
        for entry in "${NEW_GITIGNORE_ENTRIES[@]}"; do
            grep -qxF "$entry" "$GITIGNORE" 2>/dev/null || ((missing_count++)) || true
        done
        if (( missing_count > 0 )); then
            echo -e "  ${GREEN}update${NC} .gitignore  ($missing_count new entries to add)"
            ((changed++)) || true
        else
            ((unchanged++)) || true
        fi
    fi
fi

# ── Diff mode exit ──────────────────────────────────────────────────────────

if [[ "$DIFF_MODE" == "1" ]]; then
    echo ""
    echo "────────────────────────────────────────────────"
    echo -e "${BLUE}Diff complete.${NC}  v${VERSION}  ·  Changed: $changed  Unchanged: $unchanged"
    echo ""
    echo "No files were modified. To apply these changes:"
    echo "  bash install.sh $TARGET"
    echo ""
    exit 0
fi

# ── Write version stamp, manifest, and source file ───────────────────────────

mkdir -p "$TARGET/.claude"
echo "$VERSION" > "$INSTALLED_VERSION_FILE"
echo -e "  ${GREEN}write${NC} $INSTALLED_VERSION_FILE  (v${VERSION})"

# Copy manifest so upgrade can detect stale files
if [[ -f "$SCRIPT_DIR/MANIFEST" ]]; then
    cp "$SCRIPT_DIR/MANIFEST" "$TARGET/.claude/.vallorcine-manifest"
    echo -e "  ${GREEN}write${NC} $TARGET/.claude/.vallorcine-manifest"
fi

# Copy source file so /upgrade knows where to check for new releases
SOURCE_FILE="$SCRIPT_DIR/.vallorcine-source"
if [[ -f "$SOURCE_FILE" ]]; then
    cp "$SOURCE_FILE" "$TARGET/.claude/.vallorcine-source"
    echo -e "  ${GREEN}write${NC} $TARGET/.claude/.vallorcine-source"
else
    echo -e "  ${YELLOW}skip${NC}  .vallorcine-source not found (run /release to generate it)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────"
echo -e "${GREEN}Done.${NC}  v${VERSION}  ·  Created: $created  Skipped: $skipped"

if [[ "$DEV_MODE" == "1" ]]; then
    echo ""
    echo -e "  Dev mode: installed to temp directory"
    echo -e "  Test with Claude Code opened in: ${GREEN}$TARGET${NC}"
    echo -e "  Clean up when done: rm -rf $TARGET"
    echo ""
    exit 0
fi

# ── CLAUDE.md block ───────────────────────────────────────────────────────────

CLAUDE_MD="$TARGET/CLAUDE.md"
CLAUDE_BLOCK='## Feature Development
`.feature/<slug>/` — on-demand only. Profile: `.feature/project-config.md`
Quick: `/feature-quick "<description>"` — Full: `/feature "<description>"`
Resume: `/feature-resume "<slug>"` — Status: `/feature-resume "<slug>" --status`
Entry point: `/vallorcine-help`

## Knowledge Base & Decisions
`.kb/<topic>/<category>/<subject>.md` and `.decisions/<slug>/adr.md` — on-demand only.
Commands: `/research` `/architect` `/kb lookup` `/decisions revisit`

Setup: `/setup-vallorcine` (first time only — initializes everything)

## Codebase Quality
`/curate` — review quality signals, find stale decisions, knowledge gaps, and implicit dependencies.
`/curate --init` — first-time scan on existing codebase.'

if [[ -f "$CLAUDE_MD" ]] && grep -q "vallorcine-help" "$CLAUDE_MD" 2>/dev/null; then
    # Already has vallorcine block — replace it in place
    # Find the Feature Development header and replace through Codebase Quality section
    tmpfile="$(mktemp)"
    awk '
        /^## Feature Development$/ { skip=1; next }
        skip && /^## / && !/^## (Knowledge Base|Codebase Quality)/ { skip=0 }
        skip && /^## (Knowledge Base|Codebase Quality)/ { next }
        skip { next }
        { print }
    ' "$CLAUDE_MD" > "$tmpfile"
    # Remove trailing blank lines then append the fresh block
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmpfile" 2>/dev/null || true
    printf '\n%s\n' "$CLAUDE_BLOCK" >> "$tmpfile"
    mv "$tmpfile" "$CLAUDE_MD"
    echo -e "  ${GREEN}update${NC} $CLAUDE_MD  (vallorcine block refreshed)"
else
    # No existing block — append or create
    if [[ -f "$CLAUDE_MD" ]]; then
        printf '\n%s\n' "$CLAUDE_BLOCK" >> "$CLAUDE_MD"
        echo -e "  ${GREEN}append${NC} $CLAUDE_MD  (vallorcine block added)"
    else
        printf '%s\n' "$CLAUDE_BLOCK" > "$CLAUDE_MD"
        echo -e "  ${GREEN}write${NC} $CLAUDE_MD"
    fi
fi
