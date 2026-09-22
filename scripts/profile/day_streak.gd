class_name DayStreak
extends RefCounted

const DailyQuestsScript = preload("res://scripts/profile/daily_quests.gd")

## Consecutive days with at least one finished round (any mode), on the phone's
## local calendar like the daily quests. Missing a whole day resets it to 1.

## Bonus XP for keeping the streak alive: grows each day up to a cap.
const DAILY_XP_STEP := 5
const DAILY_XP_CAP := 50
## One-off bonus when the streak reaches these lengths.
const MILESTONES := {3: 50, 7: 150, 14: 250, 30: 500, 60: 800, 100: 1500}


static func today_key() -> String:
	return DailyQuestsScript.today_key()


static func yesterday_key() -> String:
	## Date arithmetic on the calendar string itself: no time zone involved.
	var midnight := Time.get_unix_time_from_datetime_string(today_key())
	return Time.get_date_string_from_unix_time(midnight - 86400)


## Streak as the player should see it right now: 0 once a full day was missed.
static func current() -> int:
	var last := SaveManager.last_play_day
	if last == today_key() or last == yesterday_key():
		return SaveManager.day_streak
	return 0


static func played_today() -> bool:
	return SaveManager.last_play_day == today_key()


## True when the streak is alive but today's round is still missing.
static func at_risk() -> bool:
	return current() > 0 and not played_today()


## Call once per finished round. Returns what changed:
## { streak, extended, xp, milestone } (extended false on later rounds of the day).
static func record_play() -> Dictionary:
	var today := today_key()
	if SaveManager.last_play_day == today:
		return {"streak": SaveManager.day_streak, "extended": false, "xp": 0, "milestone": 0}

	var streak := SaveManager.day_streak + 1 if SaveManager.last_play_day == yesterday_key() else 1
	SaveManager.day_streak = streak
	SaveManager.best_day_streak = maxi(SaveManager.best_day_streak, streak)
	SaveManager.last_play_day = today

	## Day 1 gives nothing: the bonus rewards coming back.
	var xp := 0 if streak <= 1 else mini((streak - 1) * DAILY_XP_STEP, DAILY_XP_CAP)
	var milestone := 0
	if MILESTONES.has(streak):
		milestone = streak
		xp += int(MILESTONES[streak])
	return {"streak": streak, "extended": true, "xp": xp, "milestone": milestone}


## Next milestone above the current streak (0 when all are reached).
static func next_milestone(streak: int) -> int:
	for days in MILESTONES.keys():
		if int(days) > streak:
			return int(days)
	return 0
