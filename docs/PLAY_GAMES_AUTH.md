# Google Play Games — auth (app + contrat API)

> Statut : **app en cours**. Ne **pas** publier en store tant que Yaya n’a pas livré la vérif serveur.
> Demander à Yaya : le projet Play Games Console existe-t-il déjà (Game ID, OAuth Android + Web) ?

## Flux

1. Joueur tape **Continuer avec Google** (popup auth).
2. L’app signe via **Play Games Services** (Android).
3. L’app demande un **server auth code** (OAuth web client ID).
4. L’app appelle `POST /players/play_games` avec `device_id` + `server_auth_code`.
5. Le **serveur** vérifie le code auprès de Google et relie le compte au `device_id`.

Guest / email restent locaux ; Google est le chemin compte relié au backend.

## Prérequis Play Console (Yaya)

1. App type **Game** + **Play Games Services** activés.
2. Credential **OAuth Android** : package name Godot + SHA-1 (debug + release + Play App Signing).
3. Credential **OAuth Web** (type *Web application*) : c’est le **server client ID** utilisé par `request_server_side_access`.
4. Noter le **Game ID** Play Games → export Android Godot → `godot_play_game_services/game_id`.
5. Export Android = **custom Gradle build** + template Android installé.
6. Compte testeur listé si le projet Games n’est pas publié.

Configurer côté app :

| Clé | Où |
|-----|-----|
| Game ID | Project > Export > Android > `godot_play_game_services/game_id` |
| Web OAuth client ID | [`scripts/config/play_games_config.gd`](../scripts/config/play_games_config.gd) → `SERVER_CLIENT_ID` |

Plugin : [`addons/GodotPlayGameServices`](../addons/GodotPlayGameServices) (v3.4.0).

## Contrat API — pour Yaya

### `POST /players/play_games`

**Request**

```json
{
  "device_id": "<uuid from user://device_id.txt>",
  "server_auth_code": "<Play Games server auth code>",
  "display_name": "<optional UI hint>",
  "play_games_player_id": "<optional client hint>"
}
```

**Règles serveur**

1. Vérifier `server_auth_code` auprès de Google (source de vérité ; ne pas faire confiance au `play_games_player_id` client seul).
2. Lier le compte Google vérifié au `device_id` (migration guest → Google si besoin).
3. Réponse alignée sur `POST /players` actuel (`id` = `player_id`, etc.).
4. Erreurs : code invalide / expiré → **401** ; payload incomplet → **400**.

Tant que la route n’existe pas, le client peut sauver l’auth en local et loguer un warning réseau — **pas de release** avant que ce endpoint soit live.

## Fichiers app

| Fichier | Rôle |
|---------|------|
| `scripts/autoload/play_games_auth.gd` | Sign-in + server auth code |
| `scripts/config/play_games_config.gd` | `SERVER_CLIENT_ID` |
| `scripts/autoload/save_manager.gd` | `auth_mode`, `play_games_player_id` |
| `scripts/autoload/network_manager.gd` | `link_play_games(...)` |
| `scripts/ui/app_shell.gd` | Bouton Google → `PlayGamesAuth` |

## Tests

1. Build APK signé avec le SHA-1 enregistré dans Cloud Console.
2. Device Android avec compte Google testeur.
3. Continuer avec Google → popup Play → pseudo mis à jour.
4. Quand l’API existe : vérifier en base que `device_id` est lié au compte Play Games.
