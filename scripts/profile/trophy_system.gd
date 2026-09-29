## Clash-of-Clans-inspired trophies for 1v1 quiz matches.
## Win → gain, loss → lose; amount scales with the trophy gap.
## Win streaks at 3 / 5 / 10 grant extra trophy bonuses.
class_name TrophySystem
extends RefCounted

## Equal-trophy baseline (winner gains more than loser loses — CoC asymmetry).
const BASE_WIN: int = 30
const BASE_LOSS: int = 20
## Every N trophy gap ≈ ±1 on the delta.
const DIFF_DIVISOR: float = 20.0
const MIN_WIN: int = 5
const MAX_WIN: int = 60
const MIN_LOSS: int = 5
const MAX_LOSS: int = 50
## Score blowout tweak (± per this many points of margin).
const MARGIN_PER_BONUS: float = 250.0
const MARGIN_BONUS_CAP: int = 5

## Extra cups when the versus win streak hits these exact milestones.
const STREAK_BONUS_3: int = 10
const STREAK_BONUS_5: int = 25
const STREAK_BONUS_10: int = 50
## Consolation after a long versus loss streak — soft landing to keep playing.
const LOSS_STREAK_CONSOLATION_AT: int = 5
const LOSS_STREAK_CONSOLATION: int = 10


## Solo / daily / practice → no trophies. Versus matches only.
static func awards_trophies(is_versus: bool) -> bool:
	return is_versus


## Signed match delta (before streak bonus): positive = gain, negative = loss, 0 = draw.
static func calculate_delta(
	my_trophies: int,
	opponent_trophies: int,
	my_score: int,
	opponent_score: int
) -> int:
	var diff := opponent_trophies - my_trophies
	var gap_term := int(round(float(diff) / DIFF_DIVISOR))
	var margin := my_score - opponent_score
	var margin_bonus := clampi(
		int(round(float(margin) / MARGIN_PER_BONUS)),
		-MARGIN_BONUS_CAP,
		MARGIN_BONUS_CAP
	)

	if my_score > opponent_score:
		## Upset vs stronger opponent → bigger win; vs weaker → smaller win.
		var gain := BASE_WIN + gap_term + margin_bonus
		return clampi(gain, MIN_WIN, MAX_WIN)
	if my_score < opponent_score:
		## Upset loss vs weaker opponent → bigger loss; vs stronger → smaller loss.
		var loss := BASE_LOSS - gap_term - margin_bonus
		return -clampi(loss, MIN_LOSS, MAX_LOSS)
	## Draw — no trophy movement (keeps ladder stable).
	return 0


## Bonus only on exact streak milestones (3, 5, 10) — not every win after.
static func streak_bonus(versus_win_streak: int) -> int:
	match versus_win_streak:
		3:
			return STREAK_BONUS_3
		5:
			return STREAK_BONUS_5
		10:
			return STREAK_BONUS_10
		_:
			return 0


## +10 cups when the player hits exactly 5 versus losses in a row.
static func loss_streak_consolation(versus_loss_streak: int) -> int:
	if versus_loss_streak == LOSS_STREAK_CONSOLATION_AT:
		return LOSS_STREAK_CONSOLATION
	return 0
