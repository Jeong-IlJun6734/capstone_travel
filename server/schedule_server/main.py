import sqlite3
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field


BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "schedule.db"

app = FastAPI(title="RouteIn Schedule Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class UserCreate(BaseModel):
    display_name: str = Field(min_length=1, max_length=80)


class UserOut(BaseModel):
    id: int
    display_name: str


class TripCreate(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    area: str = Field(default="", max_length=160)


class TripOut(BaseModel):
    id: int
    user_id: int
    title: str
    area: str


class TripDayCreate(BaseModel):
    label: str = Field(min_length=1, max_length=40)
    title: str = Field(min_length=1, max_length=120)
    area: str = Field(default="", max_length=160)
    total_time: str = Field(default="", max_length=80)
    walking_distance: str = Field(default="", max_length=80)


class TripDayOut(BaseModel):
    id: int
    trip_id: int
    label: str
    title: str
    area: str
    total_time: str
    walking_distance: str
    sort_order: int


class PlaceCreate(BaseModel):
    category: str = Field(min_length=1, max_length=80)
    name: str = Field(min_length=1, max_length=120)
    note: str = Field(default="", max_length=600)
    move: Optional[str] = Field(default=None, max_length=120)
    address: Optional[str] = Field(default=None, max_length=240)
    link: Optional[str] = Field(default=None, max_length=500)
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    thumbnail_url: Optional[str] = Field(default=None, max_length=500)
    image_url: Optional[str] = Field(default=None, max_length=500)


class PlaceOut(PlaceCreate):
    id: int
    day_id: int
    sort_order: int


class UserDestinationOut(PlaceOut):
    trip_id: int
    trip_title: str
    day_label: str


class TripDayDetail(TripDayOut):
    places: list[PlaceOut]


class TripDetail(TripOut):
    days: list[TripDayDetail]


def connect() -> sqlite3.Connection:
    connection = sqlite3.connect(DB_PATH)
    connection.row_factory = sqlite3.Row
    return connection


def init_db() -> None:
    with connect() as db:
        db.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              display_name TEXT NOT NULL,
              created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS trips (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id INTEGER NOT NULL,
              title TEXT NOT NULL,
              area TEXT NOT NULL DEFAULT '',
              created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
              FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS trip_days (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              trip_id INTEGER NOT NULL,
              label TEXT NOT NULL,
              title TEXT NOT NULL,
              area TEXT NOT NULL DEFAULT '',
              total_time TEXT NOT NULL DEFAULT '',
              walking_distance TEXT NOT NULL DEFAULT '',
              sort_order INTEGER NOT NULL,
              FOREIGN KEY (trip_id) REFERENCES trips(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS places (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              day_id INTEGER NOT NULL,
              category TEXT NOT NULL,
              name TEXT NOT NULL,
              note TEXT NOT NULL DEFAULT '',
              move TEXT,
              address TEXT,
              link TEXT,
              latitude REAL,
              longitude REAL,
              thumbnail_url TEXT,
              image_url TEXT,
              sort_order INTEGER NOT NULL,
              FOREIGN KEY (day_id) REFERENCES trip_days(id) ON DELETE CASCADE
            );
            """
        )


@app.on_event("startup")
def on_startup() -> None:
    init_db()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/users", response_model=UserOut)
def create_user(payload: UserCreate) -> UserOut:
    with connect() as db:
        cursor = db.execute(
            "INSERT INTO users (display_name) VALUES (?)",
            (payload.display_name,),
        )
        user_id = cursor.lastrowid
        row = db.execute(
            "SELECT id, display_name FROM users WHERE id = ?",
            (user_id,),
        ).fetchone()
    return UserOut(**dict(row))


@app.get("/users/{user_id}/trips", response_model=list[TripOut])
def list_user_trips(user_id: int) -> list[TripOut]:
    ensure_user_exists(user_id)
    with connect() as db:
        rows = db.execute(
            """
            SELECT id, user_id, title, area
            FROM trips
            WHERE user_id = ?
            ORDER BY id DESC
            """,
            (user_id,),
        ).fetchall()
    return [TripOut(**dict(row)) for row in rows]


@app.get("/users/{user_id}/destinations", response_model=list[UserDestinationOut])
def list_user_destinations(user_id: int) -> list[UserDestinationOut]:
    if not user_exists(user_id):
        return []
    with connect() as db:
        rows = db.execute(
            """
            SELECT
              places.id,
              places.day_id,
              places.category,
              places.name,
              places.note,
              places.move,
              places.address,
              places.link,
              places.latitude,
              places.longitude,
              places.thumbnail_url,
              places.image_url,
              places.sort_order,
              trips.id AS trip_id,
              trips.title AS trip_title,
              trip_days.label AS day_label
            FROM places
            JOIN trip_days ON trip_days.id = places.day_id
            JOIN trips ON trips.id = trip_days.trip_id
            WHERE trips.user_id = ?
              AND places.latitude IS NOT NULL
              AND places.longitude IS NOT NULL
            ORDER BY trips.id DESC, trip_days.sort_order, places.sort_order, places.id
            """,
            (user_id,),
        ).fetchall()
    return [UserDestinationOut(**dict(row)) for row in rows]


@app.post("/users/{user_id}/destinations", response_model=UserDestinationOut)
def create_user_destination(user_id: int, payload: PlaceCreate) -> UserDestinationOut:
    with connect() as db:
        ensure_user_exists_or_create(db, user_id)
        trip_id = ensure_default_trip(db, user_id)
        day_id = ensure_default_day(db, trip_id)
        sort_order = next_sort_order(db, "places", "day_id", day_id)
        cursor = db.execute(
            """
            INSERT INTO places (
              day_id, category, name, note, move, address, link,
              latitude, longitude, thumbnail_url, image_url, sort_order
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                day_id,
                payload.category,
                payload.name,
                payload.note,
                payload.move,
                payload.address,
                payload.link,
                payload.latitude,
                payload.longitude,
                payload.thumbnail_url,
                payload.image_url,
                sort_order,
            ),
        )
        place_id = cursor.lastrowid
        row = db.execute(
            """
            SELECT
              places.id,
              places.day_id,
              places.category,
              places.name,
              places.note,
              places.move,
              places.address,
              places.link,
              places.latitude,
              places.longitude,
              places.thumbnail_url,
              places.image_url,
              places.sort_order,
              trips.id AS trip_id,
              trips.title AS trip_title,
              trip_days.label AS day_label
            FROM places
            JOIN trip_days ON trip_days.id = places.day_id
            JOIN trips ON trips.id = trip_days.trip_id
            WHERE places.id = ?
            """,
            (place_id,),
        ).fetchone()
    return UserDestinationOut(**dict(row))


@app.post("/users/{user_id}/trips", response_model=TripOut)
def create_trip(user_id: int, payload: TripCreate) -> TripOut:
    ensure_user_exists(user_id)
    with connect() as db:
        cursor = db.execute(
            "INSERT INTO trips (user_id, title, area) VALUES (?, ?, ?)",
            (user_id, payload.title, payload.area),
        )
        trip_id = cursor.lastrowid
        row = db.execute(
            "SELECT id, user_id, title, area FROM trips WHERE id = ?",
            (trip_id,),
        ).fetchone()
    return TripOut(**dict(row))


@app.get("/trips/{trip_id}", response_model=TripDetail)
def get_trip(trip_id: int) -> TripDetail:
    with connect() as db:
        trip = db.execute(
            "SELECT id, user_id, title, area FROM trips WHERE id = ?",
            (trip_id,),
        ).fetchone()
        if trip is None:
            raise HTTPException(status_code=404, detail="Trip not found")

        days = db.execute(
            """
            SELECT id, trip_id, label, title, area, total_time, walking_distance, sort_order
            FROM trip_days
            WHERE trip_id = ?
            ORDER BY sort_order, id
            """,
            (trip_id,),
        ).fetchall()

        day_models = []
        for day in days:
            places = db.execute(
                """
                SELECT id, day_id, category, name, note, move, address, link,
                       latitude, longitude, thumbnail_url, image_url, sort_order
                FROM places
                WHERE day_id = ?
                ORDER BY sort_order, id
                """,
                (day["id"],),
            ).fetchall()
            day_models.append(
                TripDayDetail(
                    **dict(day),
                    places=[PlaceOut(**dict(place)) for place in places],
                )
            )

    return TripDetail(**dict(trip), days=day_models)


@app.post("/trips/{trip_id}/days", response_model=TripDayOut)
def create_day(trip_id: int, payload: TripDayCreate) -> TripDayOut:
    ensure_trip_exists(trip_id)
    with connect() as db:
        sort_order = next_sort_order(db, "trip_days", "trip_id", trip_id)
        cursor = db.execute(
            """
            INSERT INTO trip_days (
              trip_id, label, title, area, total_time, walking_distance, sort_order
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                trip_id,
                payload.label,
                payload.title,
                payload.area,
                payload.total_time,
                payload.walking_distance,
                sort_order,
            ),
        )
        day_id = cursor.lastrowid
        row = db.execute(
            """
            SELECT id, trip_id, label, title, area, total_time, walking_distance, sort_order
            FROM trip_days
            WHERE id = ?
            """,
            (day_id,),
        ).fetchone()
    return TripDayOut(**dict(row))


@app.post("/days/{day_id}/places", response_model=PlaceOut)
def create_place(day_id: int, payload: PlaceCreate) -> PlaceOut:
    ensure_day_exists(day_id)
    with connect() as db:
        sort_order = next_sort_order(db, "places", "day_id", day_id)
        cursor = db.execute(
            """
            INSERT INTO places (
              day_id, category, name, note, move, address, link,
              latitude, longitude, thumbnail_url, image_url, sort_order
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                day_id,
                payload.category,
                payload.name,
                payload.note,
                payload.move,
                payload.address,
                payload.link,
                payload.latitude,
                payload.longitude,
                payload.thumbnail_url,
                payload.image_url,
                sort_order,
            ),
        )
        place_id = cursor.lastrowid
        row = db.execute(
            """
            SELECT id, day_id, category, name, note, move, address, link,
                   latitude, longitude, thumbnail_url, image_url, sort_order
            FROM places
            WHERE id = ?
            """,
            (place_id,),
        ).fetchone()
    return PlaceOut(**dict(row))


@app.delete("/places/{place_id}")
def delete_place(place_id: int) -> dict[str, bool]:
    with connect() as db:
        cursor = db.execute("DELETE FROM places WHERE id = ?", (place_id,))
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Place not found")
    return {"deleted": True}


def ensure_user_exists(user_id: int) -> None:
    if not user_exists(user_id):
        raise HTTPException(status_code=404, detail="User not found")


def user_exists(user_id: int) -> bool:
    with connect() as db:
        row = db.execute("SELECT id FROM users WHERE id = ?", (user_id,)).fetchone()
    return row is not None


def ensure_user_exists_or_create(db: sqlite3.Connection, user_id: int) -> None:
    row = db.execute("SELECT id FROM users WHERE id = ?", (user_id,)).fetchone()
    if row is not None:
        return

    db.execute(
        "INSERT INTO users (id, display_name) VALUES (?, ?)",
        (user_id, f"User {user_id}"),
    )


def ensure_default_trip(db: sqlite3.Connection, user_id: int) -> int:
    row = db.execute(
        """
        SELECT id FROM trips
        WHERE user_id = ? AND title = ?
        ORDER BY id
        LIMIT 1
        """,
        (user_id, "내 여행 일정"),
    ).fetchone()
    if row is not None:
        return int(row["id"])

    cursor = db.execute(
        "INSERT INTO trips (user_id, title, area) VALUES (?, ?, ?)",
        (user_id, "내 여행 일정", "사용자 추가 장소"),
    )
    return int(cursor.lastrowid)


def ensure_default_day(db: sqlite3.Connection, trip_id: int) -> int:
    row = db.execute(
        """
        SELECT id FROM trip_days
        WHERE trip_id = ? AND label = ?
        ORDER BY id
        LIMIT 1
        """,
        (trip_id, "DAY 1"),
    ).fetchone()
    if row is not None:
        return int(row["id"])

    cursor = db.execute(
        """
        INSERT INTO trip_days (
          trip_id, label, title, area, total_time, walking_distance, sort_order
        )
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (trip_id, "DAY 1", "내가 추가한 장소", "사용자 일정", "", "", 0),
    )
    return int(cursor.lastrowid)


def ensure_trip_exists(trip_id: int) -> None:
    with connect() as db:
        row = db.execute("SELECT id FROM trips WHERE id = ?", (trip_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Trip not found")


def ensure_day_exists(day_id: int) -> None:
    with connect() as db:
        row = db.execute("SELECT id FROM trip_days WHERE id = ?", (day_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Trip day not found")


def next_sort_order(
    db: sqlite3.Connection,
    table: str,
    owner_column: str,
    owner_id: int,
) -> int:
    row = db.execute(
        f"SELECT COALESCE(MAX(sort_order), -1) + 1 AS next_order FROM {table} WHERE {owner_column} = ?",
        (owner_id,),
    ).fetchone()
    return int(row["next_order"])


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8010)
