# 🧽 KeyboardCleaner

**English** | [简体中文](README.zh-CN.md)

A tiny macOS menu bar app that **locks your keyboard and trackpad while you clean them**, then unlocks instantly with a hotkey combo — default `⌥ Option + ⌘ Command + ⎋ Esc`.

![Locked screen](docs/screenshot-lock.png)

## The problem it solves

Wiping your keyboard while the Mac is awake always ends badly: random keystrokes launch apps, rename files, send half-finished chat messages. KeyboardCleaner swallows **every input event at the system level** — keyboard, trackpad, mouse, scroll wheel, gestures, even brightness/volume/media keys — and dims the screen with a friendly reminder. Wipe away, then press the unlock combo and you're back.

## Features

- 🔒 **Blocks everything**: keyboard, trackpad, mouse, scroll, gestures, media/brightness keys (session-level `CGEventTap`, nothing reaches any app)
- 🔓 **Combo unlock**: hold `⌥ ⌘` then tap `⎋ Esc` — three simultaneous keys, so an accidental wipe across the keyboard can never unlock it. Fully customizable.
- 🖥 **Dimmed overlay on every display** showing the current unlock combo
- 🧯 **Safety-first by design**:
  - the overlay itself never intercepts clicks — even if the blocker somehow dies, your Mac stays fully usable
  - the event tap auto re-arms if macOS disables it (timeout)
  - optional auto-unlock timer (`--unlock-in`) as a fail-safe
  - quitting the app always releases the lock
  - the power button is hardware and always works as the last resort
- 🔏 **Zero telemetry, zero network access** — one ~500-line Swift file, no dependencies, and Accessibility is the only permission it ever asks for

## Getting started

**Option A · Download** (Apple Silicon): grab the latest `KeyboardCleaner-x.y.z-arm64.dmg` from [Releases](https://github.com/zhxnix/KeyboardCleaner/releases), open it, drag **KeyboardCleaner** into the **Applications** folder. On first launch, right-click the app → **Open** (the app is ad-hoc signed, so Gatekeeper asks once).

**Option B · Build from source** — requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`):

```bash
git clone https://github.com/zhxnix/KeyboardCleaner.git
cd KeyboardCleaner
./build.sh          # builds KeyboardCleaner.app, ad-hoc signed
open KeyboardCleaner.app
```

1. Launch the app — a bubble appears top-right and the 🎹 icon sits in your menu bar. (No Dock icon, no window: it lives in the menu bar.)
2. Click **🔒 锁定键盘 Lock Keyboard**. The first time, macOS asks for **Accessibility** permission: *System Settings → Privacy & Security → Accessibility* → enable **Keyboard Cleaner**, then click lock again.
3. Clean away. 🧽
4. Unlock: press `⌥ + ⌘ + Esc` together.

> Tip: the first time you try it, run `open KeyboardCleaner.app --args --lock --unlock-in 60` for a 60-second auto-unlock safety net.

## Customizing the unlock combo

Persist via `defaults` (restart the app to apply):

```bash
defaults write local.zhao.keyboardcleaner unlockKey q
defaults write local.zhao.keyboardcleaner unlockMods "ctrl,shift"
```

- **Key**: `a-z` `0-9` `esc` `return` `space` `tab` `delete` `f1-f12`
- **Modifiers**: any combination of `cmd` `alt` `ctrl` `shift` `fn` (comma-separated; at least one recommended so a stray wipe can't unlock)

Or per-launch: `KeyboardCleaner --key q --mods ctrl,shift`

## Command line

```
KeyboardCleaner                          run normally (menu bar)
KeyboardCleaner --lock                   lock immediately on launch
KeyboardCleaner --lock --unlock-in 300   lock, auto-unlock after 5 minutes
KeyboardCleaner --check                  self-test: permission & interception health
KeyboardCleaner --help
KC_DEBUG=1 KeyboardCleaner ...           verbose logging to stderr
```

## Known limitations

- If a password field is focused, macOS enables **Secure Input** and keyboard events cannot be intercepted — the app detects this and asks you to click elsewhere first, instead of pretending to be locked.
- Hardware actions (holding the power button, closing the lid) are below the reach of any event tap — which conveniently doubles as an escape hatch.
- `./build.sh` automatically signs with a local self-signed identity named **KeyboardCleaner Dev** when it exists in your login keychain — this keeps the code identity (and your Accessibility grant) stable across rebuilds. Otherwise it falls back to an ad-hoc signature, which changes on every build and requires re-granting Accessibility.

## How it works

A session-scoped `CGEventTap` in *default* (intercepting) mode subscribes to keyboard, mouse, scroll, gesture and system-defined events and returns `nil` for all of them — they simply cease to exist for the rest of the system. The unlock combo is detected inside the tap callback before the event is dropped. That's the entire trick; the rest is UI and safety rails. See [KeyboardCleaner.swift](KeyboardCleaner.swift).

## License

[MIT](LICENSE) © 2026 zhxnix
