import json
import re
import secrets
from pathlib import Path

import qrcode


# 역 목록 JSON 파일
INPUT_JSON = "subway_stations_1_8.json"

# QR 이미지 저장 폴더
OUTPUT_DIR = Path("qr_output")

# 생성된 QR ID 저장 파일
OUTPUT_JSON = "qr_ids_by_station.json"

# 역마다 생성할 QR 개수
QR_COUNT_PER_STATION = 10


def make_qr_id():
    """
    32바이트 랜덤 ID 생성.
    token_hex(32)는 32바이트를 16진수 문자열로 표현하므로 길이는 64자.
    """
    return secrets.token_hex(32)


def normalize_line_no(line_name: str) -> str:
    """
    '1호선' -> '1'
    '7호선' -> '7'
    """
    line_name = str(line_name).strip()
    return line_name.replace("호선", "")


def safe_filename(text: str) -> str:
    """
    Windows 파일명에 사용할 수 없는 문자를 제거.
    역 이름은 대부분 그대로 유지된다.
    """
    text = str(text).strip()
    text = re.sub(r'[\\/:*?"<>|]', "_", text)
    return text


def make_qr_payload(station_name: str, line_no: str, qr_id: str):
    return {
        "station": station_name,
        "line": line_no,
        "qr_id": qr_id,
    }


def main():
    input_path = Path(INPUT_JSON)

    if not input_path.exists():
        raise FileNotFoundError(f"입력 JSON 파일을 찾을 수 없습니다: {input_path}")

    OUTPUT_DIR.mkdir(exist_ok=True)

    with open(input_path, "r", encoding="utf-8") as f:
        station_data = json.load(f)

    result = {
        "qr_count_per_station": QR_COUNT_PER_STATION,
        "lines": [],
        "total_station_count": 0,
        "total_qr_count": 0,
    }

    for line_info in station_data.get("lines", []):
        line_name = line_info["line"]          # 예: "7호선"
        line_no = normalize_line_no(line_name) # 예: "7"
        stations = line_info.get("stations", [])

        line_dir = OUTPUT_DIR / f"{line_no}호선"
        line_dir.mkdir(exist_ok=True)

        line_result = {
            "line": line_no,
            "line_name": line_name,
            "station_count": len(stations),
            "stations": [],
        }

        for station_name in stations:
            station_dir = line_dir / safe_filename(station_name)
            station_dir.mkdir(exist_ok=True)

            station_result = {
                "station": station_name,
                "line": line_no,
                "qr_count": QR_COUNT_PER_STATION,
                "qrs": [],
            }

            for qr_index in range(1, QR_COUNT_PER_STATION + 1):
                qr_id = make_qr_id()

                qr_payload = make_qr_payload(
                    station_name=station_name,
                    line_no=line_no,
                    qr_id=qr_id,
                )

                qr_text = json.dumps(qr_payload, ensure_ascii=False)

                img = qrcode.make(qr_text)

                filename = f"{safe_filename(station_name)}_qr_{qr_index:02d}.png"
                save_path = station_dir / filename

                img.save(save_path)

                station_result["qrs"].append({
                    "qr_index": qr_index,
                    "station": station_name,
                    "line": line_no,
                    "qr_id": qr_id,
                    "qr_image": str(save_path).replace("\\", "/"),
                    "payload": qr_payload,
                })

                result["total_qr_count"] += 1

            line_result["stations"].append(station_result)
            result["total_station_count"] += 1

        result["lines"].append(line_result)

    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    print(f"QR 생성 완료: {OUTPUT_DIR}")
    print(f"QR ID JSON 저장 완료: {OUTPUT_JSON}")
    print(f"총 역 개수: {result['total_station_count']}")
    print(f"총 QR 개수: {result['total_qr_count']}")


if __name__ == "__main__":
    main()