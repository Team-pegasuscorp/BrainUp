## Live matchmaking: match on trophies first, then widen the window.
## Client sends `trophies` + `trophy_range`; server should prefer opponents within
## ±trophy_range, then accept wider bands as the client widens.
class_name LiveMatchmaking
extends RefCounted

## Expanding ±trophy windows (cups). Last step ≈ unrestricted.
const RANGE_STEPS: Array[int] = [50, 100, 200, 400, 800, 100000]
## Seconds spent in a band before widening.
const STEP_SECONDS: float = 8.0


static func initial_range() -> int:
	return RANGE_STEPS[0]


static func next_range(current_range: int) -> int:
	for step in RANGE_STEPS:
		if step > current_range:
			return step
	return RANGE_STEPS[RANGE_STEPS.size() - 1]


static func is_max_range(trophy_range: int) -> bool:
	return trophy_range >= RANGE_STEPS[RANGE_STEPS.size() - 1]
