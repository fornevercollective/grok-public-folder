#!/usr/bin/env python3
"""Chat with Grok and generate images/videos into Resolve artifacts."""

from __future__ import annotations

import readline  # noqa: F401 - enables arrow keys in REPL
import sys

from grok_api import (
    ARTIFACTS_ROOT,
    CHAT_MODEL,
    SYSTEM_PROMPT,
    VIDEO_DIR,
    IMAGE_DIR,
    chat,
    clear_chat_history,
    generate_image,
    generate_video,
    import_all_artifacts,
    import_paths,
    load_chat_history,
    require_api_key,
    save_chat_history,
)


def import_latest() -> int:
    media = []
    for folder in (VIDEO_DIR, IMAGE_DIR):
        if not folder.exists():
            continue
        for path in sorted(folder.iterdir()):
            if path.is_file() and not path.name.startswith("."):
                media.append(str(path))
    if not media:
        print("no files yet")
        return 0
    latest = media[-1]
    imported, bin_name = import_paths([latest])
    print(f"imported {len(imported)} into {bin_name}")
    return len(imported)


def print_help() -> None:
    print(
        """
Commands:
  /help                         show this help
  /image <prompt>               generate image -> artifacts/image/
  /video <prompt>               generate video -> artifacts/video/
  /video <prompt> --duration 10 optional flags: --duration, --ratio 16:9, --res 720p
  /import                       import latest artifact into Resolve media pool
  /import /full/path/file.mp4   import a specific file
  /clear                        reset chat history
  /quit or /exit                leave

Plain text without a slash is sent to Grok chat.
"""
    )


def parse_generation_args(parts: list[str]) -> tuple[str, dict]:
    if not parts:
        raise ValueError("Add a prompt after the command.")
    duration = 8
    aspect_ratio = "16:9"
    resolution = "720p"
    prompt_parts: list[str] = []
    idx = 0
    while idx < len(parts):
        token = parts[idx]
        if token == "--duration" and idx + 1 < len(parts):
            duration = int(parts[idx + 1])
            idx += 2
            continue
        if token == "--ratio" and idx + 1 < len(parts):
            aspect_ratio = parts[idx + 1]
            idx += 2
            continue
        if token == "--res" and idx + 1 < len(parts):
            resolution = parts[idx + 1]
            idx += 2
            continue
        prompt_parts.append(token)
        idx += 1
    prompt = " ".join(prompt_parts).strip()
    if not prompt:
        raise ValueError("Add a prompt after the command.")
    return prompt, {
        "duration": duration,
        "aspect_ratio": aspect_ratio,
        "resolution": resolution,
    }


def handle_command(api_key: str, line: str, messages: list[dict]) -> bool:
    parts = line.strip().split()
    cmd = parts[0].lower()
    args = parts[1:]

    if cmd in {"/quit", "/exit", "/q"}:
        return False
    if cmd == "/help":
        print_help()
        return True
    if cmd == "/clear":
        clear_chat_history()
        messages[:] = load_chat_history()
        print("Chat history cleared.")
        return True
    if cmd == "/import":
        if args:
            try:
                imported, bin_name = import_paths([" ".join(args)])
                print(f"imported {len(imported)} into {bin_name}")
            except Exception as exc:
                print(exc)
        else:
            try:
                count, _, bin_name = import_all_artifacts()
                if count == 0:
                    print("no files yet")
                else:
                    print(f"imported {count} into {bin_name}")
            except Exception as exc:
                print(exc)
        return True
    if cmd == "/image":
        try:
            prompt, _ = parse_generation_args(args)
            print("Generating image...")
            path = generate_image(api_key, prompt)
            print(f"Saved: {path}")
            messages.append({"role": "assistant", "content": f"Generated image at {path}"})
        except Exception as exc:
            print(f"Image generation failed: {exc}")
        return True
    if cmd == "/video":
        try:
            prompt, opts = parse_generation_args(args)
            print("Generating video (this can take a few minutes)...")
            path = generate_video(
                api_key,
                prompt,
                duration=opts["duration"],
                aspect_ratio=opts["aspect_ratio"],
                resolution=opts["resolution"],
                on_status=lambda status: print(f"  video status: {status}..."),
            )
            print(f"Saved: {path}")
            messages.append({"role": "assistant", "content": f"Generated video at {path}"})
        except Exception as exc:
            print(f"Video generation failed: {exc}")
        return True

    print(f"Unknown command: {cmd}. Type /help")
    return True


def repl() -> None:
    api_key = require_api_key()
    VIDEO_DIR.mkdir(parents=True, exist_ok=True)
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    messages = load_chat_history()

    print("Grok Resolve Console")
    print(f"Artifacts: {ARTIFACTS_ROOT}")
    print(f"Chat model: {CHAT_MODEL}")
    print("Type /help for commands. Ctrl+C or /quit to exit.\n")

    while True:
        try:
            line = input("grok> ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nBye.")
            break
        if not line:
            continue
        if line.startswith("/"):
            if not handle_command(api_key, line, messages):
                break
            continue

        messages.append({"role": "user", "content": line})
        try:
            reply = chat(api_key, messages)
        except Exception as exc:
            print(f"Chat failed: {exc}")
            messages.pop()
            continue
        messages.append({"role": "assistant", "content": reply})
        save_chat_history(messages)
        print(f"\n{reply}\n")


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] in {"-h", "--help"}:
        print_help()
        return 0
    repl()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())