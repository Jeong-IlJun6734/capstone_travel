import json
from pathlib import Path


# 숭실대입구 역 지도 JSON
STATION_JSON = Path("data/7_숭실대입구.json")

# qr_id가 추가된 결과 저장 파일
OUTPUT_JSON = Path("data/7_숭실대입구_with_qr.json")


SOONGSIL_QR_IDS = [
    "a32a1b4f714e1497a22f9d7de7e686d9ade18e43aafd733343b08e22fe3bafc7",
    "fdb4353543a8411430030883a48a6338d9b2f13f028ea213852bd468cf32ec05",
    "029d7d94fd69b1623619499f9fb5168294fe3d6f8492ad6d309e042a0fe0b905",
    "e37ab1f64f1774bc3cfcc8346d2c01a182a1ea94f5cd293d990845f74f3d6dfd",
    "64b55a95bdd490e19a422bdb2c60e728826637f429475095e361b51a515e2d6f",
    "0781406e18f3fe3dc35ab95bbc0e099532097f0fbf6d806d193dd5f1e153b187",
    "1a84cdce4fe7e873b370caf18a63b6c22177518d1e9aaa799e8c9c9598423c3a",
    "13d776a3b2ab267476978eb7d8afba34ecf08f81b53594ba371fe12f81dfff37",
    "f2b1d73c35b08b34e50a286f449d95c9f992df4c94cd9206297662606c711463",
    "af04785e9f039072356136dd986d04f71eda53055492d2b2ed3b924af622113d",
]


def main():
    with open(STATION_JSON, "r", encoding="utf-8") as f:
        station_data = json.load(f)

    qr_nodes = [
        node for node in station_data.get("nodes", [])
        if node.get("kind") == "qr"
    ]

    if len(qr_nodes) != len(SOONGSIL_QR_IDS):
        raise ValueError(
            f"QR 노드 개수와 QR ID 개수가 다릅니다. "
            f"qr_nodes={len(qr_nodes)}, qr_ids={len(SOONGSIL_QR_IDS)}"
        )

    for node, qr_id in zip(qr_nodes, SOONGSIL_QR_IDS):
        node["qr_id"] = qr_id
        node["qr_payload"] = {
            "station": station_data["station_name"],
            "line": station_data["line_no"],
            "qr_id": qr_id,
        }

    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(station_data, f, ensure_ascii=False, indent=2)

    print(f"저장 완료: {OUTPUT_JSON}")
    print(f"QR ID 추가 개수: {len(qr_nodes)}")

    for node in qr_nodes:
        print(node["id"], node["floor"], node["qr_id"])


if __name__ == "__main__":
    main()