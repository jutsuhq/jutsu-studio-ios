#!/usr/bin/env python3
"""Checks fastlane/metadata against App Store Connect's limits in every locale.

Usage: scripts/check-store-metadata.py [metadata dir]. Exits 1 on the first run with any problem.
"""

import re
import sys
from pathlib import Path

LIMITS = {
    "name.txt": 30,
    "subtitle.txt": 30,
    "promotional_text.txt": 170,
    "description.txt": 4000,
    "keywords.txt": 100,
    "release_notes.txt": 4000,
    "support_url.txt": 255,
    "marketing_url.txt": 255,
    "privacy_url.txt": 255,
}
REQUIRED = {"name.txt", "subtitle.txt", "description.txt", "keywords.txt", "support_url.txt", "privacy_url.txt"}
# Apple rejects a name or subtitle that uses another company's mark (Guidelines 4.1 and 5.2.1).
FORBIDDEN_IN_TITLE = re.compile(r"higgsfield", re.IGNORECASE)
CJK = re.compile(r"[぀-ヿ㐀-鿿]")


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8").strip()


def check_locale(folder: Path) -> list[str]:
    problems = []
    for name in sorted(REQUIRED):
        if not (folder / name).is_file() or not read(folder / name):
            problems.append(f"{name} is missing or empty")
    for name, limit in LIMITS.items():
        path = folder / name
        if path.is_file() and len(read(path)) > limit:
            problems.append(f"{name} is {len(read(path))} characters, over {limit}")
    for name in ("support_url.txt", "marketing_url.txt", "privacy_url.txt"):
        path = folder / name
        if path.is_file() and not read(path).startswith("https://"):
            problems.append(f"{name} is not an https URL")

    title = " ".join(read(folder / n) for n in ("name.txt", "subtitle.txt") if (folder / n).is_file())
    if FORBIDDEN_IN_TITLE.search(title):
        problems.append("the name or subtitle uses the Higgsfield trademark")

    keywords_path = folder / "keywords.txt"
    if keywords_path.is_file():
        keywords = read(keywords_path)
        if ", " in keywords or " ," in keywords:
            problems.append("keywords have a space next to a comma")
        words = [k for k in keywords.split(",")]
        if any(not k for k in words):
            problems.append("keywords have an empty entry")
        if len({k.lower() for k in words}) != len(words):
            problems.append("keywords repeat a word")
        if FORBIDDEN_IN_TITLE.search(keywords):
            problems.append("keywords use the Higgsfield trademark")
        title_words = {w.lower() for w in re.findall(r"\w+", title)}
        for keyword in words:
            # Spaced scripts compare whole words; Chinese and Japanese titles have no spaces, so compare substrings.
            if keyword.lower() in title_words or (CJK.search(keyword) and keyword in title):
                problems.append(f"keyword '{keyword}' is already in the name or subtitle")
    return problems


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "fastlane/metadata")
    locales = sorted(p for p in root.iterdir() if p.is_dir() and p.name != "review_information")
    if not locales:
        print(f"No locales in {root}")
        return 1
    failed = False
    for folder in locales:
        problems = check_locale(folder)
        sizes = ", ".join(
            f"{n.removesuffix('.txt')} {len(read(folder / n))}/{LIMITS[n]}"
            for n in ("name.txt", "subtitle.txt", "promotional_text.txt", "keywords.txt", "description.txt")
            if (folder / n).is_file()
        )
        print(f"{'FAIL' if problems else 'ok  '} {folder.name}: {sizes}")
        for problem in problems:
            print(f"     - {problem}")
        failed = failed or bool(problems)
    notes = root / "review_information/notes.txt"
    if notes.is_file() and len(read(notes)) > 4000:
        print(f"FAIL review notes are {len(read(notes))} characters, over 4000")
        failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
