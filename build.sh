#!/bin/bash
# Build InjusticeMod into a .deb.
#
#   ./build.sh              incremental build
#   ./build.sh -c           clean build (wipes .theos)
#   ./build.sh -p           git pull --ff-only first, then build
#   ./build.sh -s rootless  build for a different packaging scheme
#   ./build.sh --rootless   shorthand for -s rootless
#
# Without -s the scheme from the Makefile is used (rootless). Schemes differ
# only in packaging: roothide installs under the randomised jbroot and labels
# the deb iphoneos-arm64e, rootless installs under /var/jb and labels it
# iphoneos-arm64. Each scheme gets its own scratch dir, so switching between
# them does not force a rebuild.
#
# Theos refuses to build from a path containing spaces, and this repo usually
# lives under ".../injustice 2/". So when the path has a space the sources are
# mirrored to a scratch dir first and the .deb is copied back here.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DO_CLEAN=0
DO_PULL=0
SCHEME=""
while [ $# -gt 0 ]; do
    case "$1" in
        -c|--clean) DO_CLEAN=1 ;;
        -p|--pull)  DO_PULL=1 ;;
        --rootless) SCHEME="rootless" ;;
        --roothide) SCHEME="roothide" ;;
        -s|--scheme)
            shift
            [ $# -gt 0 ] || { echo "-s needs a scheme name (rootless, roothide, rootful)" >&2; exit 2; }
            SCHEME="$1" ;;
        -h|--help)  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1 (try -h)" >&2; exit 2 ;;
    esac
    shift
done

# 'rootful' is the absence of a scheme, not a scheme Theos knows about
MAKE_ARGS=()
if [ -n "$SCHEME" ]; then
    if [ "$SCHEME" = "rootful" ]; then
        MAKE_ARGS+=("THEOS_PACKAGE_SCHEME=")
    else
        MAKE_ARGS+=("THEOS_PACKAGE_SCHEME=$SCHEME")
    fi
fi

red()  { printf '\033[1;31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
ylw()  { printf '\033[1;33m%s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- locate Theos
# Rootless needs stock Theos; a roothide fork works too, but the scheme in the
# Makefile decides the layout. Trusting $THEOS alone is unreliable because a
# stale export can point at a directory that no longer exists.
is_theos() { [ -f "$1/makefiles/common.mk" ]; }

CHOSEN=""
for cand in "${THEOS:-}" "$HOME/theos" "$HOME/theos-roothide"; do
    [ -n "$cand" ] || continue
    if is_theos "$cand"; then CHOSEN="$cand"; break; fi
done

if [ -n "${THEOS:-}" ] && [ -n "$CHOSEN" ] && [ "$CHOSEN" != "$THEOS" ]; then
    ylw "note: \$THEOS points at $THEOS, which is not a Theos install — using $CHOSEN"
fi

missing=0
if [ -z "$CHOSEN" ]; then
    red "No Theos found (checked \$THEOS, ~/theos, ~/theos-roothide)"
    cat <<EOF

Install it:

  brew install ldid xz
  git clone --recursive https://github.com/theos/theos ~/theos

If ~/theos already exists but is incomplete:

  git -C ~/theos submodule update --init --recursive

EOF
    missing=1
fi

THEOS="$CHOSEN"
export THEOS

if [ -n "$THEOS" ] && [ ! -f "$THEOS/vendor/include/substrate.h" ]; then
    red "substrate.h missing — Theos submodules are not checked out"
    echo "  git -C $THEOS submodule update --init --recursive"
    missing=1
fi
command -v ldid >/dev/null || { red "ldid not found — brew install ldid"; missing=1; }
xcode-select -p >/dev/null 2>&1 || { red "Xcode command line tools missing — xcode-select --install"; missing=1; }
[ "$missing" -eq 0 ] || exit 1

# ---------------------------------------------------------------- pull
if [ "$DO_PULL" -eq 1 ]; then
    ylw "==> git pull"
    git -C "$REPO" pull --ff-only || { red "pull failed"; exit 1; }
fi
echo "    commit: $(git -C "$REPO" log --oneline -1 2>/dev/null || echo 'not a git repo')"
echo "    version: $(grep -i '^Version:' "$REPO/control" | cut -d' ' -f2-)"
echo "    scheme:  ${SCHEME:-$(grep -E '^THEOS_PACKAGE_SCHEME' "$REPO/Makefile" | cut -d= -f2- | tr -d ' ')}"

# ---------------------------------------------------------------- work dir
case "$REPO" in
    *\ *)
        WORK="${TMPDIR:-/tmp}/injustice-mod-build${SCHEME:+-$SCHEME}"
        ylw "==> path has a space; mirroring to $WORK"
        mkdir -p "$WORK"
        # .theos stays behind so incremental builds keep working
        rsync -a --delete \
              --exclude '.git' --exclude '.theos' --exclude 'packages' \
              "$REPO/" "$WORK/"
        ;;
    *)
        WORK="$REPO"
        ;;
esac

# ---------------------------------------------------------------- build
cd "$WORK" || exit 1
if [ "$DO_CLEAN" -eq 1 ]; then
    ylw "==> clean"
    rm -rf .theos packages
    make clean "${MAKE_ARGS[@]+"${MAKE_ARGS[@]}"}" >/dev/null 2>&1
fi

LOG="$WORK/build.log"
ylw "==> make package"
set -o pipefail
make package FINALPACKAGE=1 "${MAKE_ARGS[@]+"${MAKE_ARGS[@]}"}" 2>&1 | tee "$LOG"
STATUS=$?
set +o pipefail

# ---------------------------------------------------------------- report
if [ "$STATUS" -ne 0 ]; then
    echo
    red "BUILD FAILED"
    echo
    # strip ANSI colour so grep matches, then show only the diagnostics
    if sed $'s/\033\[[0-9;]*m//g' "$LOG" | grep -E ' (error|fatal error):' >/dev/null; then
        echo "Errors:"
        sed $'s/\033\[[0-9;]*m//g' "$LOG" | grep -E ' (error|fatal error):'
    else
        echo "No compiler diagnostics — last 20 lines of the log:"
        tail -20 "$LOG"
    fi
    echo
    echo "full log: $LOG"
    exit 1
fi

DEB="$(ls -t "$WORK"/packages/*.deb 2>/dev/null | head -1)"
if [ -z "$DEB" ]; then
    red "make succeeded but no .deb in $WORK/packages"
    exit 1
fi

mkdir -p "$REPO/packages"
[ "$WORK" != "$REPO" ] && cp "$DEB" "$REPO/packages/"
OUT="$REPO/packages/$(basename "$DEB")"

# warnings are worth seeing even on success, minus the one Theos always emits
WARN=$(sed $'s/\033\[[0-9;]*m//g' "$LOG" \
       | grep -E ' warning:' \
       | grep -v 'multiply_defined is obsolete')
if [ -n "$WARN" ]; then
    echo
    ylw "Warnings:"
    echo "$WARN"
fi

echo
grn "OK  $OUT"
echo "    $(stat -f %z "$OUT") bytes"
echo
echo "Install: AirDrop the .deb to the device and open it in Sileo,"
echo "or from a Mac on the same network:"
echo "    scp \"$OUT\" root@<device-ip>:/tmp/ && ssh root@<device-ip> 'dpkg -i /tmp/$(basename "$OUT") && killall -9 Injustice2Mobile'"
