import sqlite3
from pathlib import Path

DB_PATH = Path(r"C:\Users\user\Desktop\workspace\2026 SS\travel\server\schedule_server\schedule.db")


def create_one_schedule():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    try:
        conn.execute("BEGIN")

        # 1. 사용자 생성
        cur.execute(
            """
            INSERT INTO users (display_name)
            VALUES (?)
            """,
            ("테스트 사용자",)
        )
        user_id = cur.lastrowid

        # 2. 여행 일정 생성
        cur.execute(
            """
            INSERT INTO trips (user_id, title, area)
            VALUES (?, ?, ?)
            """,
            (
                user_id,
                "서울 하루 여행",
                "서울"
            )
        )
        trip_id = cur.lastrowid

        # 3. 여행 날짜 생성
        cur.execute(
            """
            INSERT INTO trip_days (
                trip_id,
                label,
                title,
                area,
                total_time,
                walking_distance,
                sort_order
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                trip_id,
                "Day 1",
                "서울 주요 관광지 코스",
                "서울",
                "약 5시간",
                "약 3.2km",
                1
            )
        )
        day_id = cur.lastrowid

        # 4. 장소 생성
        places = [
            {
                "category": "관광지",
                "name": "경복궁",
                "note": "서울의 대표적인 궁궐",
                "move": "도보 이동",
                "address": "서울특별시 종로구 사직로 161",
                "link": "https://www.royalpalace.go.kr",
                "latitude": 37.579617,
                "longitude": 126.977041,
                "thumbnail_url": "",
                "image_url": "",
                "sort_order": 1,
            },
            {
                "category": "관광지",
                "name": "북촌한옥마을",
                "note": "전통 한옥 거리 관람",
                "move": "도보 약 15분",
                "address": "서울특별시 종로구 계동길 37",
                "link": "",
                "latitude": 37.582604,
                "longitude": 126.983998,
                "thumbnail_url": "",
                "image_url": "",
                "sort_order": 2,
            },
            {
                "category": "음식점",
                "name": "인사동 식당",
                "note": "점심 식사",
                "move": "도보 약 20분",
                "address": "서울특별시 종로구 인사동",
                "link": "",
                "latitude": 37.574383,
                "longitude": 126.985313,
                "thumbnail_url": "",
                "image_url": "",
                "sort_order": 3,
            },
        ]

        for place in places:
            cur.execute(
                """
                INSERT INTO places (
                    day_id,
                    category,
                    name,
                    note,
                    move,
                    address,
                    link,
                    latitude,
                    longitude,
                    thumbnail_url,
                    image_url,
                    sort_order
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    day_id,
                    place["category"],
                    place["name"],
                    place["note"],
                    place["move"],
                    place["address"],
                    place["link"],
                    place["latitude"],
                    place["longitude"],
                    place["thumbnail_url"],
                    place["image_url"],
                    place["sort_order"],
                )
            )

        conn.commit()

        print("일정 생성 완료")
        print(f"user_id: {user_id}")
        print(f"trip_id: {trip_id}")
        print(f"day_id: {day_id}")

    except Exception as e:
        conn.rollback()
        print("일정 생성 실패:", e)

    finally:
        conn.close()


if __name__ == "__main__":
    create_one_schedule()