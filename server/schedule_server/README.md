# RouteIn Schedule Server

FastAPI + SQLite server for account-scoped trips, days, and places.

## Run

```powershell
cd server/schedule_server
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8010
```

The SQLite database is created at `server/schedule_server/schedule.db`.

## Minimal Flow

```http
POST /users
POST /users/{user_id}/trips
POST /trips/{trip_id}/days
POST /days/{day_id}/places
GET  /trips/{trip_id}
```

The first version uses `user_id` as the account boundary. Authentication can be
added later by mapping a login provider ID to `users`.
