import json
import re
from pathlib import Path

import pandas as pd


INPUT_XLSX = "전체_도시철도역사정보_20260228.xlsx"
OUTPUT_JSON = "subway_stations_1_8.json"


TARGET_LINES = {
    "1호선",
    "2호선",
    "3호선",
    "4호선",
    "5호선",
    "6호선",
    "7호선",
    "8호선",
}


def clean_station_name(name: str) -> str:
    """
    역 이름에서 괄호와 괄호 안 내용을 제거한다.
    예:
      '서울역(경부선)' -> '서울역'
      '총신대입구(이수)' -> '총신대입구'
    """
    name = str(name).strip()

    # 일반 괄호 (), 전각 괄호 （） 제거
    name = re.sub(r"\s*\([^)]*\)", "", name)
    name = re.sub(r"\s*（[^）]*）", "", name)

    return name.strip()


def normalize_line_name(line: str) -> str:
    """
    노선명 공백 정리.
    예:
      ' 1호선 ' -> '1호선'
    """
    return str(line).strip()


def main():
    xlsx_path = Path(INPUT_XLSX)

    if not xlsx_path.exists():
        raise FileNotFoundError(f"엑셀 파일을 찾을 수 없습니다: {xlsx_path}")

    # 첫 번째 시트 읽기
    df = pd.read_excel(xlsx_path, engine="openpyxl")

    required_columns = ["역사명", "노선명"]

    for col in required_columns:
        if col not in df.columns:
            raise ValueError(f"필수 컬럼이 없습니다: {col}")

    # 필요한 컬럼만 추출
    df = df[["역사명", "노선명"]].copy()

    # 결측값 제거
    df = df.dropna(subset=["역사명", "노선명"])

    # 값 정리
    df["역사명"] = df["역사명"].apply(clean_station_name)
    df["노선명"] = df["노선명"].apply(normalize_line_name)

    # 1~8호선만 필터링
    df = df[df["노선명"].isin(TARGET_LINES)]

    # 중복 제거
    df = df.drop_duplicates(subset=["노선명", "역사명"])

    # 노선 순서 정렬
    line_order = {f"{i}호선": i for i in range(1, 9)}
    df["line_order"] = df["노선명"].map(line_order)
    df = df.sort_values(["line_order", "역사명"])

    result = {
        "lines": []
    }

    total_station_count = 0

    for line_name, group in df.groupby("노선명", sort=False):
        stations = group["역사명"].tolist()

        result["lines"].append({
            "line": line_name,
            "station_count": len(stations),
            "stations": stations
        })

        total_station_count += len(stations)

    result["total_station_count"] = total_station_count

    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    print(f"저장 완료: {OUTPUT_JSON}")
    print(f"총 역 개수: {total_station_count}")

    for line in result["lines"]:
        print(f"{line['line']}: {line['station_count']}개")


if __name__ == "__main__":
    main()