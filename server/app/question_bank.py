import json
import random
from pathlib import Path

DATA_DIR = Path(__file__).parent / "data"
## Same as the client's QuestionLoader.MIXED_CATEGORY_ID: "Culture générale" plays every category.
MIXED_CATEGORY_ID = "general"


def _load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as file:
        return json.load(file)


def _localize_question(raw: dict, locale: str) -> dict | None:
    allowed_locales = raw.get("locales", ["fr", "en"])
    if locale not in allowed_locales:
        return None

    translations = raw.get("translations", {})
    block = translations.get(locale)
    if not block:
        for fallback in ("fr", "en"):
            if fallback in translations:
                block = translations[fallback]
                break
    if not block:
        return None

    choices = block.get("choices", [])
    if len(choices) != 4:
        return None

    ## Old imported questions only say "the correct answer is: X": nothing to learn there.
    explanation = str(block.get("explanation", "")).strip()
    if explanation.startswith(("The correct answer is", "La bonne réponse est")):
        explanation = ""

    return {
        "id": raw.get("id", ""),
        "category": raw.get("category", ""),
        "difficulty": int(raw.get("difficulty", 2)),
        "text": block.get("text", ""),
        "choices": choices,
        "correct_index": int(raw.get("correct_index", -1)),
        "explanation": explanation,
    }


def _category_files(category: str) -> list[Path]:
    if category == MIXED_CATEGORY_ID:
        return sorted((DATA_DIR / "questions").glob("*.json"))
    path = DATA_DIR / "questions" / f"{category}.json"
    return [path] if path.exists() else []


def get_questions(category: str, locale: str, count: int) -> list[dict]:
    candidates: list[dict] = []
    for path in _category_files(category):
        for entry in _load_json(path).get("questions", []):
            localized = _localize_question(entry, locale)
            if localized is not None:
                candidates.append(localized)

    if len(candidates) <= count:
        return candidates
    return random.sample(candidates, count)


def draft_choices(count: int) -> list[str]:
    """Categories offered in the pre-match draft (any file in data/questions)."""
    categories = sorted(path.stem for path in (DATA_DIR / "questions").glob("*.json"))
    return random.sample(categories, min(count, len(categories)))
