# Sounder

A fishing audio aid addon for **World of Warcraft**.

## The Problem

Midnight no longer exposes bobber splash events to addons, so fishing helpers that listened for the bobber sound stopped working. If your game volume is low, it's easy to miss the splash.

## How Sounder helps

Sounder watches for your fishing channel cast (spell 131476 by default). The moment the cast begins, it automatically applies your desired fishing sound settings so you can hear the bobber splash. When the cast ends, your original audio settings are automatically restored. If you enter combat while in the middle of fishing, Sounder will automatically restore your audio settings to try to save your hearing. If you are in combat when you start fishing, Sounder will not modify your sound settings.

Sounder can also play a sound whenever you're invited to a group or raid — whether from a direct invite or from being invited to a premade group via the Group Finder — so you don't miss one while alt-tabbed or AFK. It plays on the Master channel, so it's audible even with Music/Ambience/SFX disabled, the same way boss-mod alert sounds are. It cannot play if your overall sound is muted (`Sound_EnableAllSound` off or Master Volume at 0) — no addon can produce audio through that, since it's the actual gain applied to everything, not a per-category toggle.

## Settings

Open **Game Menu → Interface → AddOns → Sounder** to configure:

| Setting | Description |
|---|---|
| **Fishing Spell IDs (comma separated)** | Spell IDs to watch for (default: `131476`) |
| **Fishing Master Volume (0–100)** | Master Volume level applied while a cast is in progress |
| **Fishing SFX Volume (0–100)** | SFX Volume level applied while a cast is in progress |
| **Disable Music while fishing** | Disable music while a cast is in progress |
| **Disable Ambient Sounds while fishing** | Disable ambient sounds while a cast is in progress |
| **Play sound when invited to a group or raid** | Enable/disable the invite sound alert (default: on); triggers on a direct invite or on joining via Group Finder |
| **Invite Sound (Sound ID or file path)** | A numeric SoundKit ID (default: `8960`, the ready check sound) or a path to a sound file. Use the **Test** button to preview it. |

Settings persist across sessions via the `SounderDB` saved variable.

## Installation

1. Download or clone this repository.
2. Copy the `Sounder` folder into your `World of Warcraft/_retail_/Interface/AddOns/` directory.
3. Reload the UI or start WoW

## Source

https://github.com/weishiuchang/sounder
