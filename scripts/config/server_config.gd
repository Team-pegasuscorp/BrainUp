class_name ServerConfig
extends RefCounted
## Backend endpoint used by NetworkManager.
##
## Debug builds talk to the local docker compose stack; production builds point
## to the Hetzner deployment. Keep the http**s** scheme for release: the Google
## sign-in and AdMob work fine over http on a USB-reversed device, but a real
## account link should not leave the local network on plain http.

const DEV_BASE_URL: String = "http://127.0.0.1:8000"
const PROD_BASE_URL: String = "https://api.philia-interactive.com"


static func base_url() -> String:
	if OS.is_debug_build():
		return DEV_BASE_URL
	return PROD_BASE_URL
