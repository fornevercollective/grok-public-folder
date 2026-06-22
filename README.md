# grok-public-folder

Public folder for Grok media prompts and DaVinci Resolve workflow.

Repo: https://github.com/fornevercollective/grok-public-folder

Local path: `/Users/tref/film/grok-public-folder`

## Folders

```text
video/     generated and moved video clips
image/     generated and moved stills
bridge/    resolve console <-> terminal handoff
bin/       launchers
resolve/   lua and utility scripts for resolve
```

## Quick start

```bash
export XAI_API_KEY=your-key
/Users/tref/film/grok-public-folder/bin/bridge
```

Resolve

```text
Workspace -> Scripts -> Utility -> Grok Panel
```

Install resolve scripts after clone

```bash
/Users/tref/film/grok-public-folder/install-resolve.sh
```

## Lua console

```lua
dofile("/Users/tref/film/grok-public-folder/resolve/lua/grok_bridge.lua")
g()
ping()
g("write a mars landing prompt")
import()
```

## Python console

```python
exec(open("/Users/tref/film/grok-public-folder/grok_load.py").read(), globals())
```

## Downloads scan

```bash
/Users/tref/film/grok-public-folder/bin/scan
```

Detects grok.com download metadata and asks before moving into `video/` or `image/`.

## Metadata

Moved and generated files get a sidecar

```text
clip.mp4
clip.mp4.grok.json
```