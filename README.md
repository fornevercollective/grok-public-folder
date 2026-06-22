# grok-public-folder

Fastest pipe: **Imagine presets → Grok generation → Resolve 4K edit → Colossus/Dojo training**

**Docs:** https://fornevercollective.github.io/grok-public-folder/

Repos: [grok-public-folder](https://github.com/fornevercollective/grok-public-folder) · [imagine](https://github.com/fornevercollective/imagine) · [grok-repo-template](https://github.com/fornevercollective/grok-repo-template)

## Pipe

```text
imagine preset slug → grok-public-folder/video|image → Resolve Media Pool (4K timeline)
                                                              ↓
                                              exports → Colossus / Dojo (grok-repo-template)
```

## Quick start

```bash
git clone https://github.com/fornevercollective/grok-public-folder.git
cd grok-public-folder
chmod +x install-resolve.sh bin/*
./install-resolve.sh
export XAI_API_KEY=your-key
./bin/startup --create-project   # 4K bins + timeline (Resolve open)
```

Resolve: **Workspace → Scripts → Utility → Grok Menu**

## Startup project

| Setting | Value |
|---------|-------|
| Timeline | 3840×2160 @ 23.976 fps |
| Generation | 720p 16:9 (xAI max → upscale in post) |
| Presets | 70+ Imagine slugs from `project/presets-manifest.json` |
| Story | `project/stories/dusk-to-neon.json` |

Media Pool bins created on bootstrap:

```text
01_inputs  02_stills  03_clips/grok_generated  04_story_beats  05_resolve_edit  06_exports
```

## Generate with preset slugs

Terminal:

```bash
./bin/grok
/slug neo-noir woman in rain on empty street
```

Resolve Lua (bridge running):

```lua
g("/slug neo-noir woman in rain")
import()
```

Story beat:

```bash
python3 grok_story.py --plan
python3 grok_story.py --beat act2_rising
```

## Other scripts

| Script | Path |
|--------|------|
| Grok Menu | Utility → Grok Menu (bootstrap, scan, import, generate) |
| Quick bootstrap | Utility → Grok Bootstrap |
| Bridge | `bin/bridge` |
| Scan Downloads | `bin/scan` |

Optional: clone imagine for offline presets

```bash
git clone https://github.com/fornevercollective/imagine.git ~/film/imagine
export IMAGINE_REPO=~/film/imagine
```