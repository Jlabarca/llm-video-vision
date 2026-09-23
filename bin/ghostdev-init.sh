#!/usr/bin/env bash
# ghostdev init -- one-command first-time methodology install into a target project.
# POSIX twin of ghostdev-init.ps1 (same flags, semantics, output contract, exit codes).
#
# Seeds the methodology tree SKIP-EXISTING (never overwrites), copies
# .claude/settings.example.json -> .claude/settings.json when absent, warns if the
# target's .gitignore swallows root bin/ (suggests '!/bin/'), stamps the
# .ghostdev/version.json adopter marker. DRY-RUN by default; --execute to apply.
#
# Usage:
#   bash template/bin/ghostdev-init.sh --target <project> --execute   # from a checkout
#   bash bin/ghostdev-init.sh --execute                               # post-degit, in-place
# Flags: --target <path> --execute --version <str> --ghostdev-repo <path> --quiet
set -u

script_dir="$(cd "$(dirname "$0")" && pwd)"
template_root="$(cd "$script_dir/.." && pwd)"

target=""
execute=0
version=""
ghostdev_repo="${GHOSTDEV_HOME:-}"
quiet=0

while [ $# -gt 0 ]; do
    case "$1" in
        --target)        target="$2"; shift 2 ;;
        --execute)       execute=1; shift ;;
        --version)       version="$2"; shift 2 ;;
        --ghostdev-repo) ghostdev_repo="$2"; shift 2 ;;
        --quiet)         quiet=1; shift ;;
        *) echo "unknown flag: $1" >&2; exit 1 ;;
    esac
done

[ -n "$target" ] || target="$template_root"
if [ ! -d "$target" ]; then
    echo "target not found: $target" >&2
    exit 1
fi
target="$(cd "$target" && pwd)"

mode="dry-run"; [ "$execute" -eq 1 ] && mode="execute"
echo "ghostdev-init: $mode target=$target"

# ---- seed (skip-existing; never overwrite) ----
seeded=0; skipped=0
while IFS= read -r f; do
    rel="${f#"$template_root"/}"
    out="$target/$rel"
    if [ -e "$out" ]; then
        skipped=$((skipped + 1))
        [ "$quiet" -eq 0 ] && echo "  ~ skip    $rel (exists)"
        continue
    fi
    seeded=$((seeded + 1))
    if [ "$execute" -eq 1 ]; then
        mkdir -p "$(dirname "$out")"
        cp "$f" "$out"
    fi
    [ "$quiet" -eq 0 ] && echo "  + seeded  $rel"
done < <(find "$template_root" -type f | LC_ALL=C sort)
echo "seed:    $seeded seeded, $skipped skipped"

# ---- settings: example -> settings.json iff absent ----
example=""
if [ -f "$target/.claude/settings.example.json" ]; then
    example="$target/.claude/settings.example.json"
elif [ -f "$template_root/.claude/settings.example.json" ]; then
    example="$template_root/.claude/settings.example.json"
fi
settings_dst="$target/.claude/settings.json"
if [ -z "$example" ]; then
    settings_outcome="no-example"
elif [ -e "$settings_dst" ]; then
    settings_outcome="already-present"
else
    settings_outcome="copied"
    if [ "$execute" -eq 1 ]; then
        mkdir -p "$(dirname "$settings_dst")"
        cp "$example" "$settings_dst"
    fi
fi
echo "settings: $settings_outcome"

# ---- gitignore guard: does root bin/ get swallowed? ----
gi_path="$target/.gitignore"
gi_line="gitignore: ok"
if [ -f "$gi_path" ]; then
    last_swallow=0; last_negate=0; n=0
    while IFS= read -r raw; do
        n=$((n + 1))
        line="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [ -z "$line" ] && continue
        case "$line" in '#'*) continue ;; esac
        norm="$(printf '%s' "$line" | sed 's/^!//' | sed 's:^/*::;s:/*$::' | tr '[:upper:]' '[:lower:]')"
        [ "$norm" = "bin" ] || continue
        case "$line" in
            '!'*) last_negate=$n ;;
            *)    last_swallow=$n ;;
        esac
    done < "$gi_path"
    if [ "$last_swallow" -gt 0 ] && { [ "$last_negate" -eq 0 ] || [ "$last_negate" -lt "$last_swallow" ]; }; then
        gi_line="gitignore: WARN bin/ swallowed (line $last_swallow) - add '!/bin/' to $gi_path"
    fi
fi
echo "$gi_line"

# ---- marker: delegate to ghostdev-mark.ps1 when available, else inline schema-v1 ----
mark_tool=""
for cand in "${ghostdev_repo:+$ghostdev_repo/tools/ghostdev-mark.ps1}" "$template_root/../tools/ghostdev-mark.ps1"; do
    [ -n "$cand" ] && [ -f "$cand" ] && { mark_tool="$cand"; break; }
done

if [ -z "$version" ]; then
    version="degit-unknown"
    if command -v git >/dev/null 2>&1; then
        d="$(git -C "$template_root" describe --tags --always 2>/dev/null || true)"
        [ -n "$d" ] && version="$d"
    fi
fi

marker_verb="would-write"; [ "$execute" -eq 1 ] && marker_verb="written"
if [ "$execute" -eq 1 ]; then
    if [ -n "$mark_tool" ] && command -v pwsh >/dev/null 2>&1; then
        pwsh -NoProfile -File "$mark_tool" -Target "$target" -Quiet || {
            echo "ghostdev-mark failed" >&2
            exit 1
        }
    else
        marker_dir="$target/.ghostdev"
        marker_path="$marker_dir/version.json"
        today="$(date +%Y-%m-%d)"
        adopted="$today"
        if [ -f "$marker_path" ]; then
            prev="$(sed -n 's/.*"adopted"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$marker_path" | head -n1)"
            [ -n "$prev" ] && adopted="$prev"
        fi
        mkdir -p "$marker_dir"
        cat > "$marker_path" <<EOF
{
  "schema": 1,
  "methodology": "$version",
  "source": "waremoto/ghostdev@degit",
  "adopted": "$adopted",
  "updated": "$today",
  "components": { "rules": 0, "skills": 0, "hooks": 0, "statusline": false },
  "surface": ["docs/DOCS-PROTOCOL.md", ".claude/skills/", ".claude/settings.example.json", "bin/"]
}
EOF
    fi
fi
echo "marker:  $marker_verb .ghostdev/version.json [$version]"

if [ "$execute" -eq 1 ]; then
    echo "done"
else
    echo "done (dry-run - re-run with --execute to apply)"
fi
exit 0
