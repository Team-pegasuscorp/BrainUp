from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


COSMETIC_ID = r"^[a-z0-9_]{0,40}$"


class Cosmetics(BaseModel):
    """Ids from the game's data/shop/catalog.json ("" = default look)."""
    avatar: str = Field("", pattern=COSMETIC_ID)
    frame: str = Field("", pattern=COSMETIC_ID)
    banner: str = Field("", pattern=COSMETIC_ID)


class PlayerRegister(BaseModel):
    device_id: str = Field(min_length=1, max_length=128)
    display_name: str = Field(min_length=1, max_length=40)
    ## Omitted by older clients: the stored look is then kept.
    cosmetics: Cosmetics | None = None


class Player(BaseModel):
    id: UUID
    device_id: str
    display_name: str
    created_at: datetime
    cosmetics: Cosmetics = Cosmetics()


class MatchSubmit(BaseModel):
    player_id: UUID
    category: str = Field(min_length=1, max_length=40)
    score: int = Field(ge=0)
    correct_count: int = Field(ge=0)
    total_count: int = Field(ge=0)
    max_combo: int = Field(ge=0)
    won: bool


class Match(BaseModel):
    id: UUID
    player_id: UUID
    category: str
    score: int
    correct_count: int
    total_count: int
    max_combo: int
    won: bool
    played_at: datetime


class LeaderboardEntry(BaseModel):
    rank: int
    player_id: UUID
    display_name: str
    score: int
    cosmetics: Cosmetics = Cosmetics()


class DailyChallenge(BaseModel):
    date: str
    category_id: str
    seed: str


class DailyResultSubmit(BaseModel):
    player_id: UUID
    score: int = Field(ge=0)
    correct_count: int = Field(ge=0)
    total_count: int = Field(ge=0)
    max_combo: int = Field(ge=0)


class PassClaim(BaseModel):
    device_id: str = Field(min_length=1, max_length=128)
    tier: int = Field(ge=1, le=200)
    track: str = Field(pattern=r"^(free|premium)$")


class PassQuest(BaseModel):
    device_id: str = Field(min_length=1, max_length=128)
    quest_id: str = Field(min_length=1, max_length=40)


class PassPremium(BaseModel):
    device_id: str = Field(min_length=1, max_length=128)
    ## Google Play purchase token once billing is wired; "dev" on a development server.
    receipt: str = Field(min_length=1, max_length=4096)


class DailyResult(BaseModel):
    date: str
    category_id: str
    score: int
    correct_count: int
    total_count: int
    rank: int
    # True when a result for today already existed: the first play is the one kept.
    already_played: bool
    ## Battle pass XP earned by this result (0 when already played or no season).
    pass_xp: int = 0


class DailyLeaderboardEntry(BaseModel):
    rank: int
    player_id: UUID
    display_name: str
    score: int
    correct_count: int
    cosmetics: Cosmetics = Cosmetics()


class DailyLeaderboard(BaseModel):
    date: str
    category_id: str
    total_players: int
    # Rank of the requesting player (when player_id is given and has played today).
    player_rank: int | None
    entries: list[DailyLeaderboardEntry]


class ChallengeCreate(BaseModel):
    challenger_id: UUID
    category: str = Field(min_length=1, max_length=40)


class ChallengeJoin(BaseModel):
    player_id: UUID


class ChallengeResult(BaseModel):
    player_id: UUID
    score: int = Field(ge=0)
    correct_count: int = Field(ge=0)


class Challenge(BaseModel):
    id: UUID
    code: str
    category: str
    challenger_id: UUID
    opponent_id: UUID | None
    challenger_score: int | None
    challenger_correct_count: int | None
    opponent_score: int | None
    opponent_correct_count: int | None
    status: str
    created_at: datetime
