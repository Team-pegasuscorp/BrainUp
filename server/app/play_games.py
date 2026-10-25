"""Google Play Games server auth code verification.

The Godot client obtains a server auth code through Play Games
(``SignInClient.request_server_side_access``); the backend exchanges it at
Google's OAuth token endpoint with the WEB client credentials, then reads the
verified Google account id from the returned id_token (``sub``). The
client-provided ``play_games_player_id`` is only a display hint — the token
response is the source of truth.
"""
import base64
import json
import os
import urllib.error
import urllib.parse
import urllib.request

TOKEN_ENDPOINT = os.environ.get("GOOGLE_TOKEN_ENDPOINT", "https://oauth2.googleapis.com/token")
WEB_CLIENT_ID = os.environ.get("GOOGLE_PLAY_WEB_CLIENT_ID", "")
WEB_CLIENT_SECRET = os.environ.get("GOOGLE_PLAY_WEB_CLIENT_SECRET", "")

## Test hook: when set, the Google exchange is skipped and any auth code is
## accepted as belonging to this Google account id (local tests only).
MOCK_SUB = os.environ.get("GOOGLE_AUTH_MOCK_SUB", "")


class AuthCodeError(Exception):
    """Google rejected the server auth code (or the token response is unusable)."""


class AuthNotConfiguredError(Exception):
    """The web client credentials are missing: /players/play_games must answer 503."""


def _decode_id_token_payload(id_token: str) -> dict:
    parts = id_token.split(".")
    if len(parts) != 3:
        raise AuthCodeError("malformed id_token")
    padded = parts[1] + "=" * (-len(parts[1]) % 4)
    try:
        return json.loads(base64.urlsafe_b64decode(padded.encode()))
    except Exception:
        raise AuthCodeError("malformed id_token payload")


def _fetch_play_games_player_id(access_token: str) -> str:
    """Who owns this access token, according to the Play Games web API (verified)."""
    request = urllib.request.Request(
        "https://www.googleapis.com/games/v1/players/me",
        headers={"Authorization": "Bearer %s" % access_token})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        raise AuthCodeError(f"games api rejected the access token (HTTP {error.code})")
    player_id = str(payload.get("playerId", "")) or str(payload.get("id", ""))
    if not player_id:
        raise AuthCodeError("games api response without player id")
    return player_id


def verify_server_auth_code(code: str) -> dict:
    """Exchange a Play Games server auth code for the verified Google account id."""
    if MOCK_SUB:
        ## Test convenience: "mock-sub:<id>" selects the Google account id, so a
        ## single test stack can exercise several accounts.
        prefix = "mock-sub:"
        if code.startswith(prefix):
            return {"google_sub": code[len(prefix):]}
        return {"google_sub": MOCK_SUB}
    if not WEB_CLIENT_ID or not WEB_CLIENT_SECRET:
        raise AuthNotConfiguredError(
            "GOOGLE_PLAY_WEB_CLIENT_ID / GOOGLE_PLAY_WEB_CLIENT_SECRET not set")
    body = urllib.parse.urlencode({
        "grant_type": "authorization_code",
        "code": code,
        "client_id": WEB_CLIENT_ID,
        "client_secret": WEB_CLIENT_SECRET,
    }).encode()
    request = urllib.request.Request(
        TOKEN_ENDPOINT, data=body, method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            token_payload = json.load(response)
    except urllib.error.HTTPError as error:
        detail = ""
        try:
            detail = str(json.loads(error.read()).get("error_description", ""))[:300]
        except Exception:
            detail = ""
        raise AuthCodeError(
            f"google rejected the auth code (HTTP {error.code})"
            + (f": {detail}" if detail else ""))
    except urllib.error.URLError as error:
        raise AuthCodeError(f"google token endpoint unreachable: {error.reason}")
    id_token = str(token_payload.get("id_token", ""))
    if id_token:
        claims = _decode_id_token_payload(id_token)
        if claims.get("aud") != WEB_CLIENT_ID:
            raise AuthCodeError("id_token audience mismatch")
        google_sub = str(claims.get("sub", ""))
        if not google_sub:
            raise AuthCodeError("id_token without sub")
        return {"google_sub": google_sub}
    ## With force_refresh_token=true the exchange may omit the id_token: fall back
    ## to the Play Games web API, which answers with the verified player id.
    access_token = str(token_payload.get("access_token", ""))
    if access_token:
        return {"google_sub": _fetch_play_games_player_id(access_token)}
    raise AuthCodeError("token response without id_token nor access_token")
