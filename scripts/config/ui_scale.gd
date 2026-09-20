class_name UiScale
extends RefCounted
## One place to tune text size. Small text grows the most (it was the hardest to
## read on a phone), large titles only a little so they do not overflow.
## scripts/... calls UiScale.font(size); scenes and the theme were scaled with the
## same formula when this was introduced.

const SMALL_FACTOR := 1.22
const LARGE_FACTOR := 1.08
## Tighter pair for screens with fixed-width multi-column layouts (the profile).
const COMPACT_SMALL_FACTOR := 1.10
const COMPACT_LARGE_FACTOR := 1.04

## While true, font() uses the compact factors. Set around a synchronous UI build.
static var compact: bool = false
## While true, font() returns sizes unchanged (mock-tuned components that must not grow).
static var identity: bool = false


static func font(size: int) -> int:
	if identity:
		return size
	var t := clampf((float(size) - 12.0) / 24.0, 0.0, 1.0)
	var small := COMPACT_SMALL_FACTOR if compact else SMALL_FACTOR
	var large := COMPACT_LARGE_FACTOR if compact else LARGE_FACTOR
	return int(round(float(size) * lerpf(small, large, t)))
