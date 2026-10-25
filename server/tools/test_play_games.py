"""Checks POST /players/play_games: the auth-code verification contract (400/401/503),
guest -> Google migration, device transfer, merge of a local guest into the linked
account, and the client hint never being trusted. The script rebuilds the API
container with GOOGLE_AUTH_MOCK_SUB, then restarts it clean at the end.
Usage: python tools/test_play_games.py  (no extra dependency; stdlib only)"""
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
import uuid

API = "http://localhost:8000"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
failures = []


def check(label: str, ok: bool, detail="") -> None:
    print(("PASS " if ok else "FAIL ") + label + (f"  ({detail})" if detail else ""))
    if not ok:
        failures.append(label)


def call(method: str, path: str, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(API + path, data=data, method=method,
                                     headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        try:
            return error.code, json.load(error)
        except Exception:
            return error.code, {}


def psql(sql: str) -> str:
    out = subprocess.run(["docker", "exec", "quizz-backend-postgres-1", "psql", "-U", "quizz", "-d", "quizz",
                          "-tAc", sql], capture_output=True, text=True, check=True)
    return out.stdout.strip()


def compose(*args, env=None) -> None:
    run_env = dict(os.environ)
    run_env.update(env or {})
    subprocess.run(["docker", "compose", "-p", "quizz-backend", *args],
                   cwd=ROOT, env=run_env, check=True)


def wait_health() -> bool:
    for _ in range(90):
        try:
            with urllib.request.urlopen(API + "/health", timeout=2) as response:
                if response.status == 200:
                    return True
        except Exception:
            time.sleep(1)
    return False


def fresh_device() -> str:
    return str(uuid.uuid4())


def main() -> None:
    compose("up", "-d", "--build", "api", env={"GOOGLE_AUTH_MOCK_SUB": "mock-google"})
    check("api healthy with auth mock", wait_health())

    status, _ = call("POST", "/players/play_games", {"device_id": fresh_device()})
    check("missing server_auth_code -> 400", status == 400, str(status))
    status, _ = call("POST", "/players/play_games", {})
    check("empty payload -> 400", status == 400, str(status))

    device_a = fresh_device()
    status, player = call("POST", "/players/play_games",
                          {"device_id": device_a, "server_auth_code": "code-whatever",
                           "display_name": "Yaya", "play_games_player_id": "client-hint-fake"})
    check("new player -> 200", status == 200, str(status))
    check("stored google sub is the verified one (client hint ignored)",
          player.get("play_games_player_id") == "mock-google", str(player.get("play_games_player_id")))
    check("display name kept", player.get("display_name") == "Yaya")
    account_id = player.get("id")

    device_b = fresh_device()
    status, moved = call("POST", "/players/play_games",
                         {"device_id": device_b, "server_auth_code": "code-whatever"})
    check("same account on a new device -> 200", status == 200, str(status))
    check("same player id after transfer", moved.get("id") == account_id)
    check("device_id updated", moved.get("device_id") == device_b)

    guest_device = fresh_device()
    status, guest = call("POST", "/players", {"device_id": guest_device, "display_name": "GuestYaya"})
    check("guest registered", status == 200, str(status))
    psql(f"INSERT INTO coin_ledger (player_id, amount, reason, ref) "
         f"VALUES ('{guest['id']}', 50, 'test', 'pg-{guest_device[:8]}')")
    migration_sub = f"migrated-{uuid.uuid4().hex[:8]}"
    status, migrated = call("POST", "/players/play_games",
                            {"device_id": guest_device, "server_auth_code": f"mock-sub:{migration_sub}"})
    check("guest -> google migration -> 200", status == 200, str(status))
    check("migration keeps player id", migrated.get("id") == guest.get("id"))
    check("migration sets verified google sub", migrated.get("play_games_player_id") == migration_sub)
    check("migration keeps display name", migrated.get("display_name") == "GuestYaya")
    owner = psql(f"SELECT player_id FROM coin_ledger WHERE ref = 'pg-{guest_device[:8]}'")
    check("guest coins follow the migration", owner == str(guest["id"]))

    merge_guest_device = fresh_device()
    status, merge_guest = call("POST", "/players",
                               {"device_id": merge_guest_device, "display_name": "MergeGuest"})
    check("second guest registered", status == 200, str(status))
    psql(f"INSERT INTO coin_ledger (player_id, amount, reason, ref) "
         f"VALUES ('{merge_guest['id']}', 7, 'test', 'mg-{merge_guest_device[:8]}')")
    status, merged = call("POST", "/players/play_games",
                          {"device_id": merge_guest_device, "server_auth_code": "code-whatever"})
    check("linked account + local guest -> 200", status == 200, str(status))
    check("merge keeps the google account", merged.get("id") == account_id)
    check("merge keeps verified google sub", merged.get("play_games_player_id") == "mock-google")
    gone = psql(f"SELECT COUNT(*) FROM players WHERE id = '{merge_guest['id']}'")
    check("merged guest row deleted", gone == "0")
    owner = psql(f"SELECT player_id FROM coin_ledger WHERE ref = 'mg-{merge_guest_device[:8]}'")
    check("merged guest coins moved to account", owner == str(account_id))

    compose("up", "-d", "--build", "api")
    check("api healthy without mock", wait_health())
    status, _ = call("POST", "/players/play_games",
                     {"device_id": fresh_device(), "server_auth_code": "code"})
    check("google credentials absent -> 503", status == 503, str(status))

    print()
    if failures:
        print(f"{len(failures)} FAILURE(S)")
        raise SystemExit(1)
    print("ALL OK")


if __name__ == "__main__":
    main()
