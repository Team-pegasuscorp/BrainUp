## Stand-in opponents for ranked live matches when no human is found in time.
## Bots are hidden from the client (normal pseudo, no flag): they are never stored in
## the database, and a match against one settles only half the usual trophy change.
import random
import uuid

## How long a player waits in the queue before a bot takes the seat.
BOT_AFTER_SECONDS = 20.0
## Share of the match delta applied against a bot (streak bonuses still count in full).
BOT_TROPHY_FACTOR = 0.5
## The bot sits a few trophies away from the player, like a close human match.
TROPHY_JITTER = 30

PSEUDOS = (
    "Lucas", "Emma", "Nathan", "Léa", "Hugo", "Chloé", "Louis", "Manon", "Jules", "Camille",
    "Théo", "Inès", "Arthur", "Jade", "Raphaël", "Lina", "Tom", "Zoé", "Noah", "Sarah",
    "Maxime", "Clara", "Enzo", "Lou", "Mathis", "Alice", "Axel", "Anna", "Sacha", "Eva",
    "QuizMaster", "Cerveau42", "LeSavant", "Mimi_B", "TonyQuiz", "Nova", "Pixel", "Kiwi",
    "Brainy", "Moustique", "LaFouine", "Zébulon", "Capitaine", "Ninja_Q", "Pépite", "Rico",
)


## Looks a bot may wear. Must stay in sync with the game's data/shop/catalog.json and
## GameAssets.DEMO_AVATAR_SLUGS; unknown ids just fall back to defaults in the game.
STARTER_AVATARS = (
    "lucas", "emma", "theo", "hugo", "noah", "lea", "chloe",
    "adam", "sarah", "maya", "yanis", "jade", "louis", "ines",
)
## "" (default) is listed several times: most players keep the free look.
BOT_FRAMES = ("", "", "", "frame_ocean", "frame_forest", "frame_sunset", "frame_frost", "frame_prism", "frame_royal")
BOT_BANNERS = ("", "", "", "banner_ocean", "banner_forest", "banner_sunset", "banner_candy", "banner_galaxy", "banner_gold")


def cosmetics_for(seed: str) -> dict:
    """Stable random look for a bot: the same seed always gives the same outfit."""
    rng = random.Random(seed)
    return {
        "avatar": rng.choice(STARTER_AVATARS),
        "frame": rng.choice(BOT_FRAMES),
        "banner": rng.choice(BOT_BANNERS),
    }


def new_identity(player_trophies: int) -> tuple[str, str, int]:
    """(player_id, display_name, trophies) for a fresh bot close to the player's level."""
    trophies = max(0, player_trophies + random.randint(-TROPHY_JITTER, TROPHY_JITTER))
    return str(uuid.uuid4()), random.choice(PSEUDOS), trophies


def accuracy(trophies: int, difficulty: int) -> float:
    """Chance of answering right: stronger bots know more, harder questions trip them up."""
    base = 0.45 + min(trophies, 3000) / 3000 * 0.35  # 45 % at 0 trophies, 80 % at 3000+
    return max(0.2, min(0.9, base - (difficulty - 2) * 0.1))


def plan_answer(trophies: int, question: dict, time_limit: float) -> tuple[float, int]:
    """(delay in seconds, chosen index) for one question. Sometimes the bot runs out of time."""
    if random.random() < 0.05:
        return time_limit + 1.0, -1
    difficulty = int(question.get("difficulty", 2))
    correct = question["correct_index"]
    if random.random() < accuracy(trophies, difficulty):
        choice = correct
    else:
        choice = random.choice([i for i in range(len(question["choices"])) if i != correct])
    ## Humans take 2 to 8 s; stronger bots lean faster, hard questions slower.
    speed = min(trophies, 3000) / 3000
    delay = random.uniform(2.0, 8.0) * (1.0 - 0.3 * speed) + (difficulty - 2) * 0.7
    return max(1.2, min(delay, time_limit - 0.3)), choice


def scaled_delta(match_delta: int) -> int:
    """Half the change, rounded toward zero but never erasing a win or loss entirely."""
    if match_delta == 0:
        return 0
    scaled = int(match_delta * BOT_TROPHY_FACTOR)
    if scaled == 0:
        return 1 if match_delta > 0 else -1
    return scaled
