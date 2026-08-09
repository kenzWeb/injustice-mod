# InjusticeMod — Theos tweak (.deb) for Injustice 2 Mobile 6.7.1

Injects into `com.wb.Injustice.Brawler2017`, hooks
`ACombatCharacter::SetCurrentHealth` (RVA `0x1B50954`) and draws a draggable
overlay menu with a live HP readout.

## Build

Use `./build.sh` — `-c` for a clean build, `-p` to `git pull` first. Theos
refuses to build from a path containing spaces and this repo usually lives
under `.../injustice 2/`, so the script mirrors the tree into a scratch
directory, builds there and copies the `.deb` back into `packages/`.

With the `rootless` scheme the package is named `..._iphoneos-arm64.deb`.
Identify a build by its `Version`, not by the architecture suffix.

The Makefile ships set to `THEOS_PACKAGE_SCHEME := rootless`.

### Rootless

Stock Theos is enough — the `rootless` scheme is built in:

```bash
git clone --recursive https://github.com/theos/theos ~/theos
export THEOS=~/theos
```

### Other jailbreaks

| Jailbreak | `THEOS_PACKAGE_SCHEME` | Theos |
|---|---|---|
| RootHide | `roothide` | roothide fork |
| Dopamine / palera1n rootless | `rootless` | stock |
| checkra1n / unc0ver (rootful) | delete the line | stock |

`.deb` lands in `./packages/`. Install with your package manager or `dpkg -i`,
or `make do` with `THEOS_DEVICE_IP` set.

`Depends: ellekit | mobilesubstrate` is deliberately permissive — `MSHookFunction`
is the same API on ElleKit, libhooker and legacy Substrate. If your bootstrap
provides a differently-named hooking package, pin it there.

## Files

| File | Role |
|---|---|
| `Tweak.xm` | hook + overlay menu |
| `offsets.h` | all RVAs, with a comment on where each came from |
| `InjusticeMod.plist` | bundle filter |
| `Makefile`, `control` | packaging |

## How the hook works

`SetCurrentHealth(this, newHP)` is the only place `CurrentHealth` (`+0x4E4`) is
written — damage, healing and match init all funnel through it, so one hook sees
every change. `MaxHealth` sits next to it at `+0x4E8`.

Player and opponent are told apart with `ABaseGameCharacter::IsPlayerCharacter()`,
a virtual at vtable byte offset `0x9A0`. It is called through the object's own
vptr, so it keeps working even if the function itself moves — only the slot index
is version-locked. (`CharacterTeam` at `+0x118C` is *not* usable for this: it is
the roster faction — JusticeLeague, SuicideSquad, …)

Live values are copied out of the hook into atomics; the UI never dereferences a
character pointer, so it cannot crash on a stale object after a match ends. The
readout blanks out after 3 s without a hook hit.

## Version lock

The tweak reads `CFBundleVersion` at load and refuses to hook unless it is
`1438123` / `6.7.1`. Any game update moves every offset — regenerate with
`../dump/tools/emit.py`, then re-derive the two code addresses:

* `SetCurrentHealth` — scan `__text` for `str w, [x, #<CurrentHealth>]` inside a
  function that also loads `+<MaxHealth>` and clamps with two `csel`.
* `IsPlayerCharacter` slot — disassemble `execIsPlayerCharacter`
  (`ue_functions.csv` → `ABaseGameCharacter::IsPlayerCharacter`) and read the
  `ldr x8, [x8, #...]` displacement.

`../dump/tools/find_hp_sites2.py` automates the first one.

## Notes

* The menu window sits at `UIWindowLevelAlert + 100`; only its own subviews take
  touches, the game keeps everything else.
* `Freeze HP (все)` stops the write for *every* character, so nobody dies and the
  match will not end — it is there for inspection, not for playing.
* Offsets are for the arm64 slice; the app has no arm64e slice, so the tweak's
  arm64e build is only there to satisfy the loader on newer devices.
