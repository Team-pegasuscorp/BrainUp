## Server-side trophy ladder for ranked live matches.
## The server settles every live match itself and stores the result in players.trophies,
## the value it trusts for matchmaking; the client may keep its own copy for display.
## Mirrors the client's TrophySystem and SaveManager.settle_versus_trophies
## (scripts/profile/trophy_system.gd), streak bonuses included.

## Client search windows (LiveMatchmaking.RANGE_STEPS); anything else is snapped to these.
RANGE_STEPS = (50, 100, 200, 400, 800, 100_000)
LEGACY_RANGE = RANGE_STEPS[-1]

## A player's first ranked join may bring trophies earned before the server tracked
## them; that first value is accepted once, capped here, then the server takes over.
SEED_CAP = 1500
MAX_TROPHIES = 100_000

## Extra cups on exact versus win-streak milestones, and a consolation at exactly 5 losses.
STREAK_BONUSES = {3: 10, 5: 25, 10: 50}
LOSS_STREAK_CONSOLATION_AT = 5
LOSS_STREAK_CONSOLATION = 10


def sanitize_int(value, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def snap_range(value) -> int:
    """Smallest allowed step >= the requested range (legacy clients get no limit)."""
    if value is None:
        return LEGACY_RANGE
    requested = sanitize_int(value, LEGACY_RANGE)
    for step in RANGE_STEPS:
        if requested <= step:
            return step
    return LEGACY_RANGE


def seed_value(claimed) -> int:
    return max(0, min(sanitize_int(claimed), SEED_CAP))


def compatible(a_trophies: int, a_range: int, b_trophies: int, b_range: int) -> bool:
    return abs(a_trophies - b_trophies) <= min(a_range, b_range)


def _outcome(my_score: int, opponent_score: int, outcome) -> int:
    """1 win, -1 loss, 0 draw. `outcome` overrides the score comparison (survival:
    the last player standing wins even with fewer points)."""
    if outcome is not None:
        return outcome
    return (my_score > opponent_score) - (my_score < opponent_score)


def calculate_delta(my_trophies: int, opponent_trophies: int, my_score: int, opponent_score: int,
                    outcome=None) -> int:
    result = _outcome(my_score, opponent_score, outcome)
    if result == 0:
        return 0
    gap_term = round((opponent_trophies - my_trophies) / 20)
    margin_bonus = max(-5, min(5, round((my_score - opponent_score) / 250)))
    ## Survival can be won on fewer points: then the point margin says nothing, ignore it.
    if (result > 0) != (my_score > opponent_score):
        margin_bonus = 0
    if result > 0:
        return max(5, min(60, 30 + gap_term + margin_bonus))
    return -max(5, min(50, 20 - gap_term - margin_bonus))


def apply_delta(trophies: int, delta: int) -> int:
    return max(0, min(MAX_TROPHIES, trophies + delta))


def settle(trophies: int, win_streak: int, loss_streak: int,
           opponent_trophies: int, my_score: int, opponent_score: int,
           scale_match_delta=None, outcome=None) -> dict:
    """Same order as the client: streaks are updated first, then the bonus is read.
    A draw resets both streaks. scale_match_delta (e.g. against a bot) only touches
    the match part, not the streak bonuses."""
    result = _outcome(my_score, opponent_score, outcome)
    match_delta = calculate_delta(trophies, opponent_trophies, my_score, opponent_score, result)
    if scale_match_delta is not None:
        match_delta = scale_match_delta(match_delta)
    streak_bonus = 0
    consolation = 0
    if result > 0:
        win_streak, loss_streak = win_streak + 1, 0
        streak_bonus = STREAK_BONUSES.get(win_streak, 0)
    elif result < 0:
        win_streak, loss_streak = 0, loss_streak + 1
        if loss_streak == LOSS_STREAK_CONSOLATION_AT:
            consolation = LOSS_STREAK_CONSOLATION
    else:
        win_streak, loss_streak = 0, 0
    total = match_delta + streak_bonus + consolation
    return {
        "match_delta": match_delta,
        "streak_bonus": streak_bonus,
        "loss_consolation": consolation,
        "delta": total,
        "trophies": apply_delta(trophies, total),
        "win_streak": win_streak,
        "loss_streak": loss_streak,
    }
