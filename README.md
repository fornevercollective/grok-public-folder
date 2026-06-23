<img width="1359" height="946" alt="Screenshot 2026-06-22 at 5 22 10 PM" src="https://github.com/user-attachments/assets/3af1668d-b485-4018-9b6c-b0b4605dfd6d" />
<img width="1359" height="946" alt="Screenshot 2026-06-22 at 5 22 19 PM" src="https://github.com/user-attachments/assets/48847d43-f1c6-4d36-a5dc-29beca6a84f5" />
<img width="1359" height="946" alt="Screenshot 2026-06-22 at 5 22 29 PM" src="https://github.com/user-attachments/assets/2cc04363-67ae-4233-a87d-2412f15fe190" />
<img width="1359" height="946" alt="Screenshot 2026-06-22 at 5 22 37 PM" src="https://github.com/user-attachments/assets/c3d20d27-c86f-41fc-a949-146c8825ff57" />
<img width="1359" height="946" alt="Screenshot 2026-06-22 at 5 22 33 PM" src="https://github.com/user-attachments/assets/d34ed81e-2525-42d6-91a4-444f3307567c" />
<img width="1359" height="946" alt="Screenshot 2026-06-22 at 5 22 41 PM" src="https://github.com/user-attachments/assets/90e16f9b-5470-4ca0-9a46-8d32df346c15" />
<img width="1359" height="946" alt="Screenshot 2026-06-22 at 5 22 46 PM" src="https://github.com/user-attachments/assets/4c78ef0d-8d38-46e3-8fdc-30f7928b5645" />
<img width="1359" height="946" alt="Screenshot 2026-06-22 at 5 22 49 PM" src="https://github.com/user-attachments/assets/b1f015b7-8633-4a73-a678-d54de66cd07f" />
<img width="1359" height="946" alt="Screenshot 2026-06-22 at 5 22 53 PM" src="https://github.com/user-attachments/assets/679b5f73-3753-4188-8b6b-4a1c196a245f" />
<img width="1359" height="946" alt="Screenshot 2026-06-22 at 5 22 56 PM" src="https://github.com/user-attachments/assets/a816e7b4-2cf0-481e-b65b-6c4b85e87cee" />

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

Resolve: **Workspace → Scripts → Grok** (Lua menu — works on Resolve Free)

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
| Grok | Scripts → Grok → pick action (bootstrap, scan, import, generate) |
| Bridge | `bin/bridge` |
| Scan Downloads | `bin/scan` |

Optional: clone imagine for offline presets

```bash
git clone https://github.com/fornevercollective/imagine.git ~/film/imagine
export IMAGINE_REPO=~/film/imagine
```
