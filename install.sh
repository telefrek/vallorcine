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

# ── Slash commands ────────────────────────────────────────────────────────────

echo ""
echo "── Slash commands ───────────────────────────────"
for f in "$SCRIPT_DIR"/commands/*.md; do
    install_file "$f" "$TARGET/.claude/commands/$(basename "$f")"
done

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

# ── KB seed files ─────────────────────────────────────────────────────────────

echo ""
echo "── KB seed files ────────────────────────────────"
install_file "$SCRIPT_DIR/kb/CLAUDE.md"                              "$TARGET/.kb/CLAUDE.md"
install_file "$SCRIPT_DIR/kb/_refs/complexity-notation.md"           "$TARGET/.kb/_refs/complexity-notation.md"
install_file "$SCRIPT_DIR/kb/_refs/benchmarking-methodology.md"      "$TARGET/.kb/_refs/benchmarking-methodology.md"

# ── Decisions seed files ──────────────────────────────────────────────────────

echo ""
echo "── Decisions seed files ─────────────────────────"
install_file "$SCRIPT_DIR/decisions/CLAUDE.md" "$TARGET/.decisions/CLAUDE.md"

# ── Scripts ───────────────────────────────────────────────────────────────────

echo ""
echo "── Scripts ──────────────────────────────────────"
install_file "$SCRIPT_DIR/scripts/token-usage.sh" "$TARGET/.claude/scripts/token-usage.sh"
install_file "$SCRIPT_DIR/scripts/version-check.sh" "$TARGET/.claude/scripts/version-check.sh"
install_file "$SCRIPT_DIR/scripts/merge-driver-index.sh" "$TARGET/.claude/scripts/merge-driver-index.sh"
install_file "$SCRIPT_DIR/scripts/ensure-merge-driver.sh" "$TARGET/.claude/scripts/ensure-merge-driver.sh"
install_file "$SCRIPT_DIR/scripts/kb-freshness-check.sh" "$TARGET/.claude/scripts/kb-freshness-check.sh"
install_file "$SCRIPT_DIR/scripts/adr-validate.sh" "$TARGET/.claude/scripts/adr-validate.sh"

# ── Upgrade script ───────────────────────────────────────────────────────────

echo ""
echo "── Upgrade script ───────────────────────────────"
install_file "$SCRIPT_DIR/upgrade.sh" "$TARGET/.claude/upgrade.sh"
chmod +x "$TARGET/.claude/upgrade.sh" 2>/dev/null || true

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
GITATTR
    echo -e "  ${GREEN}write${NC} .gitattributes  (merge driver entries)"
else
    echo -e "  ${YELLOW}skip${NC}  .gitattributes already has merge driver entries"
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

echo ""
echo "Add this block to your root CLAUDE.md:"
echo ""
cat << 'CLAUDEMD'
## Feature Development
`.feature/<slug>/` — on-demand only. Profile: `.feature/project-config.md`
Quick: `/feature-quick "<description>"` — Full: `/feature "<description>"`
Resume: `/feature-resume "<slug>"` — Status: `/feature-resume "<slug>" --status`
Setup: `/feature-init` (first time only) — Entry point: `/vallorcine-help`

## Knowledge Base & Decisions
`.kb/<topic>/<category>/<subject>.md` and `.decisions/<slug>/adr.md` — on-demand only.
Commands: `/research` `/architect` `/kb lookup` `/decisions review`
Setup: `/setup-vallorcine` (first time only)
CLAUDEMD
echo ""
