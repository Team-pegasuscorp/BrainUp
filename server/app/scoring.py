## Mirrors scripts/quiz/scoring_system.gd in the Godot client, so solo, async and
## live scores stay comparable on the same leaderboard.
BASE_POINTS = 100
MIN_SPEED_MULTIPLIER = 0.5


def calculate_points(elapsed_seconds: float, time_limit: float, combo: int) -> int:
    clamped_elapsed = max(0.0, min(elapsed_seconds, time_limit))
    speed_ratio = 1.0 - (clamped_elapsed / time_limit)
    speed_multiplier = max(MIN_SPEED_MULTIPLIER, speed_ratio)
    combo_multiplier = 1.0 + max(combo - 1, 0) * 0.1
    return round(BASE_POINTS * speed_multiplier * combo_multiplier)
