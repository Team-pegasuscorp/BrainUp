extends RefCounted
## Shared daily challenge: same category and same 7 questions for every player.
## The server decides the category and seed; this mirrors its rotation only as an
## offline fallback so the mode still works without a connection.

const ROTATION: Array[String] = ["sport", "cinema", "history"]
const BONUS_XP := 50
## Python's date.toordinal() for 1970-01-01, used to mirror the server rotation.
const EPOCH_ORDINAL := 719163


static func offline_today() -> Dictionary:
	var unix_days := int(floor(Time.get_unix_time_from_system() / 86400.0))
	var date := Time.get_date_dict_from_unix_time(unix_days * 86400)
	var iso := "%04d-%02d-%02d" % [int(date["year"]), int(date["month"]), int(date["day"])]
	return {
		"date": iso,
		"category_id": ROTATION[(unix_days + EPOCH_ORDINAL) % ROTATION.size()],
		"seed": iso,
		"offline": true,
	}


## Result stored for `date`, or {} if the player has not played that day yet.
static func result_for(date: String) -> Dictionary:
	var result: Dictionary = SaveManager.daily_challenge_result
	return result if str(result.get("date", "")) == date else {}


## The server rolls over at UTC midnight.
static func seconds_until_reset() -> int:
	var now := Time.get_time_dict_from_system(true)
	var elapsed := int(now["hour"]) * 3600 + int(now["minute"]) * 60 + int(now["second"])
	return maxi(86400 - elapsed, 0)
