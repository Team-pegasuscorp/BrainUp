extends Node

## Rewarded ads (AdMob, Poing Studios plugin in addons/admob). Only rewarded ads: the
## player chooses to watch one for Neurones, there are no forced ads (decision 2026-10-19).
## Flow: GDPR consent (UMP) -> MobileAds.initialize -> preload one ad -> show on demand ->
## the reward is claimed on the server (NetworkManager.claim_ad_reward, capped per day).
## Off Android (desktop, editor) everything stays disabled.

## An ad is loaded and can be shown right now.
signal availability_changed(ready: bool)
## The watched ad paid `coins` (0 = daily cap reached or server unreachable).
signal reward_finished(coins: int)

## Google's official test unit. TODO(launch): replace with BrainUp's own rewarded unit
## from the AdMob console, and set admob/general/android/app_id in the project settings.
const REWARDED_UNIT_ANDROID := "ca-app-pub-3940256099942544/5224354917"
## Wait before loading again after a failure (no fill, offline).
const RETRY_SECONDS := 30.0

var _enabled: bool = false
var _rewarded_ad: RewardedAd
var _loading: bool = false
var _earned: bool = false
var _load_callback := RewardedAdLoadCallback.new()
var _content_callback := FullScreenContentCallback.new()
var _reward_listener := OnUserEarnedRewardListener.new()


func _ready() -> void:
	_enabled = OS.get_name() == "Android" and Engine.has_singleton("PoingGodotAdMob")
	if not _enabled:
		return
	_load_callback.on_ad_loaded = _on_ad_loaded
	_load_callback.on_ad_failed_to_load = func(_error: LoadAdError) -> void:
		_loading = false
		_retry_later()
	_content_callback.on_ad_dismissed_full_screen_content = _on_ad_closed
	_content_callback.on_ad_failed_to_show_full_screen_content = func(_error: AdError) -> void:
		_on_ad_closed()
	_reward_listener.on_user_earned_reward = func(_item: RewardedItem) -> void:
		_earned = true
	_request_consent()


func is_available() -> bool:
	return _enabled


func is_ready() -> bool:
	return _rewarded_ad != null


## Shows the preloaded ad; reward_finished fires once it is closed.
func show_rewarded() -> bool:
	if _rewarded_ad == null:
		return false
	_earned = false
	_rewarded_ad.show(_reward_listener)
	return true


# --- Consent (GDPR) then SDK start ---------------------------------------------

func _request_consent() -> void:
	var request := ConsentRequestParameters.new()
	UserMessagingPlatform.consent_information.update(request, _on_consent_info_updated,
		func(_error: FormError) -> void: _start_ads())


func _on_consent_info_updated() -> void:
	var info := UserMessagingPlatform.consent_information
	if info.get_is_consent_form_available() and info.get_consent_status() == info.ConsentStatus.REQUIRED:
		UserMessagingPlatform.load_consent_form(
			func(form: ConsentForm) -> void: form.show(func(_error: FormError) -> void: _start_ads()),
			func(_error: FormError) -> void: _start_ads())
	else:
		_start_ads()


func _start_ads() -> void:
	var config := RequestConfiguration.new()
	config.max_ad_content_rating = RequestConfiguration.MAX_AD_CONTENT_RATING_T
	MobileAds.set_request_configuration(config)
	var on_init := OnInitializationCompleteListener.new()
	on_init.on_initialization_complete = func(_status: InitializationStatus) -> void:
		_load_ad()
	MobileAds.initialize(on_init)


# --- Loading and showing ---------------------------------------------------------

func _load_ad() -> void:
	if _loading or _rewarded_ad != null:
		return
	_loading = true
	RewardedAdLoader.new().load(REWARDED_UNIT_ANDROID, AdRequest.new(), _load_callback)


func _on_ad_loaded(ad: RewardedAd) -> void:
	_loading = false
	_rewarded_ad = ad
	_rewarded_ad.full_screen_content_callback = _content_callback
	availability_changed.emit(true)


func _retry_later() -> void:
	get_tree().create_timer(RETRY_SECONDS).timeout.connect(_load_ad)


func _on_ad_closed() -> void:
	if _rewarded_ad != null:
		_rewarded_ad.destroy()
		_rewarded_ad = null
	availability_changed.emit(false)
	var coins := 0
	if _earned:
		coins = await NetworkManager.claim_ad_reward()
	_earned = false
	reward_finished.emit(coins)
	_load_ad()
