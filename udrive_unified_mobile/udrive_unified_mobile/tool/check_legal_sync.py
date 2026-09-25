#!/usr/bin/env python3
"""
Checks the legal documents bundled with the app against the ones the API serves.

The privacy policy exists twice on purpose: embedded in the API, so Google Play
has a public URL, and bundled in the app, so it can be read on a road in Neelum
with no signal. Two copies of a legal document drift, and the day they do, the
policy somebody agreed to in the app is not the policy on the website.

This is the check that stops that shipping. Run it before every release:

    python3 tool/check_legal_sync.py

It exits non-zero if a bundled document differs from the served one by a single
byte, if a contact placeholder was never filled in, or if a version number was
bumped in one place and not the other.

Offline, it still runs the local checks and tells you the comparison was
skipped — it will not pass silently by pretending a missing network is a match.
"""

from __future__ import annotations

import pathlib
import re
import sys
import urllib.error
import urllib.request

API = "https://udrive-api-production.up.railway.app"
ASSETS = pathlib.Path(__file__).resolve().parent.parent / "assets" / "legal"
DOCUMENTS = ["privacy-policy", "terms", "account-deletion"]
LANGUAGES = ["en", "ur"]

# Anything still carrying one of these has not been filled in. A policy that
# ships telling people to contact XXX is worse than no contact line at all.
PLACEHOLDERS = [
    "XXX",
    "TODO",
    "{{",
    "0300-0000000",
    "your-number-here",
    "example.com",
]

problems: list[str] = []
notes: list[str] = []


def front_matter(text: str) -> dict[str, str]:
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---", 3)
    if end < 0:
        return {}
    meta = {}
    for line in text[4:end].split("\n"):
        key, _, value = line.partition(":")
        if _:
            meta[key.strip()] = value.strip()
    return meta


def fetch(document: str, language: str) -> str | None:
    url = f"{API}/legal/{document}.{language}.md"
    try:
        with urllib.request.urlopen(url, timeout=20) as response:
            return response.read().decode("utf-8")
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        notes.append(f"could not reach {url}: {error}")
        return None


def main() -> int:
    if not ASSETS.is_dir():
        print(f"FAIL: {ASSETS} does not exist — the app has no bundled documents.")
        return 1

    reachable = True

    for document in DOCUMENTS:
        versions = {}

        for language in LANGUAGES:
            path = ASSETS / f"{document}.{language}.md"
            if not path.is_file():
                problems.append(f"{path.name} is missing from assets/legal/")
                continue

            local = path.read_text(encoding="utf-8")
            meta = front_matter(local)

            if not meta.get("title"):
                problems.append(f"{path.name}: no title in the front matter")
            if not meta.get("version"):
                problems.append(f"{path.name}: no version in the front matter")
            if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", meta.get("effective", "")):
                problems.append(
                    f"{path.name}: effective date must be YYYY-MM-DD, got "
                    f"{meta.get('effective')!r}"
                )
            versions[language] = meta.get("version")

            for placeholder in PLACEHOLDERS:
                if placeholder in local:
                    problems.append(
                        f"{path.name}: still contains the placeholder {placeholder!r}"
                    )

            # A contact must be reachable. Every document ends with one.
            if not re.search(r"\b03\d{2}[- ]?\d{7}\b", local):
                problems.append(
                    f"{path.name}: no contact number found — every document must "
                    f"carry one a person can actually use"
                )

            if reachable:
                served = fetch(document, language)
                if served is None:
                    reachable = False
                elif served != local:
                    problems.append(
                        f"{path.name}: the bundled copy DIFFERS from {API}"
                        f"/legal/{document}.{language}.md — republish the API or "
                        f"re-copy the file into assets/legal/"
                    )

        # Both languages of one document describe the same rules, so they are
        # revised together. A version that moved in one and not the other means
        # a change was made in English and never translated, or the reverse.
        distinct = {v for v in versions.values() if v}
        if len(distinct) > 1:
            problems.append(
                f"{document}: the two languages are at different versions "
                f"{versions} — they must be revised together"
            )

    exactly_one_governing_per_document(problems)

    for note in notes:
        print(f"note: {note}")

    if problems:
        print()
        for problem in problems:
            print(f"FAIL: {problem}")
        print(f"\n{len(problems)} problem(s). Do not release.")
        return 1

    if not reachable:
        print(
            "\nLocal checks passed, but the API could not be reached, so the "
            "bundled copies were NOT compared against the served ones.\n"
            "Run this again with a connection before releasing."
        )
        return 2

    print(f"Legal documents in sync with {API}. {len(DOCUMENTS)} documents, "
          f"{len(LANGUAGES)} languages each.")
    return 0


def exactly_one_governing_per_document(problems: list[str]) -> None:
    """The English copy governs; the translation must say that it does not."""
    for document in DOCUMENTS:
        governing = []
        for language in LANGUAGES:
            path = ASSETS / f"{document}.{language}.md"
            if not path.is_file():
                continue
            meta = front_matter(path.read_text(encoding="utf-8"))
            if meta.get("governing") == "true":
                governing.append(language)
        if governing != ["en"]:
            problems.append(
                f"{document}: exactly the English copy must be marked "
                f"governing: true, found {governing or 'none'}"
            )


if __name__ == "__main__":
    sys.exit(main())
