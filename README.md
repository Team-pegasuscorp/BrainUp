# BrainUp

QuizUp-style trivia game built with **Godot 4.3**, with **French and English** support from day one.

## Features (MVP)

- Main menu with language settings (FR / EN)
- Category selection (Sport, Cinema, History)
- 7-question rounds with a 10-second timer
- Speed-based scoring with combo multiplier
- Local save: level, XP, per-category stats
- Bilingual question content (JSON) and UI strings (CSV)

## Requirements

- [Godot Engine 4.3+](https://godotengine.org/download)

## Run the project

1. Open Godot 4.3
2. Import/open this folder as a project
3. Press **F5** (main scene: `scenes/main_menu.tscn`)

Or from the command line:

```bash
godot --path . 
```

## Project structure

```
scenes/           # UI scenes (menu, categories, quiz, results)
scripts/
  autoload/       # SaveManager, LocaleManager, GameManager
  quiz/           # QuestionLoader, ScoringSystem
  ui/             # Scene scripts
data/
  categories.json
  questions/      # one JSON file per category id
locale/
  ui.csv          # UI translations (en + fr)
```

## Adding questions

Each question file follows this bilingual format:

```json
{
  "id": "sport_001",
  "category": "sport",
  "correct_index": 2,
  "locales": ["fr", "en"],
  "translations": {
    "en": { "text": "...", "choices": ["...", "...", "...", "..."], "explanation": "..." },
    "fr": { "text": "...", "choices": ["...", "...", "...", "..."], "explanation": "..." }
  }
}
```

## Roadmap

- [ ] Daily challenge mode
- [ ] Async 1v1 challenges
- [ ] Leaderboards
- [ ] More categories and questions
