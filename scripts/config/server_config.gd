class_name ServerConfig
extends RefCounted
## Backend endpoint used by NetworkManager.
##
## Debug builds talk to the local docker compose stack; production builds point
## to the Hetzner deployment. Keep the http**s** scheme for release: the Google
## sign-in and AdMob work fine over http on a USB-reversed device, but a real
## account link should not leave the local network on plain http.

const DEV_BASE_URL: String = "http://127.0.0.1:8000"
## Android emulator loopback to the host machine (PC), not the guest itself.
const DEV_BASE_URL_ANDROID_EMU: String = "http://10.0.2.2:8000"
const PROD_BASE_URL: String = "https://api.philia-interactive.com"
## Debug APK: hit Hetzner when local docker isn't running on :8000.
## Flip to false once `docker compose up` is available on this machine.
const USE_PROD_IN_DEBUG: bool = true


static func base_url() -> String:
	if OS.is_debug_build() and not USE_PROD_IN_DEBUG:
		## Debug APK on the emulator: 127.0.0.1 is the emulator, not docker on the PC.
		if OS.get_name() == "Android":
			return DEV_BASE_URL_ANDROID_EMU
		return DEV_BASE_URL
	return PROD_BASE_URL
