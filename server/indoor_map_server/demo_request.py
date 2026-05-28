import requests
import json

# 같은 컴퓨터에서 테스트할 때
BASE_URL = "http://localhost:8000"

# 휴대폰/다른 기기에서 테스트할 때는 컴퓨터 IP로 변경
#BASE_URL = "http://192.168.0.15:8000"


def print_json(title, data):
    print(f"\n=== {title} ===")
    print(json.dumps(data, ensure_ascii=False, indent=2))


def request_station_info(line, station):
    url = f"{BASE_URL}/api/station/{line}/{station}"
    response = requests.get(url)
    response.raise_for_status()

    print_json("역 기본 정보", response.json())


def request_nodes():
    url = f"{BASE_URL}/api/nodes"
    response = requests.get(url)
    response.raise_for_status()

    nodes = response.json()

    print("\n=== 노드 목록 일부 ===")
    print(f"전체 노드 수: {len(nodes)}")

    for node in nodes[:5]:
        print_json(node["id"], node)


def request_edges():
    url = f"{BASE_URL}/api/edges"
    response = requests.get(url)
    response.raise_for_status()

    edges = response.json()

    print("\n=== 간선 목록 일부 ===")
    print(f"전체 간선 수: {len(edges)}")

    for edge in edges[:5]:
        print_json("edge", edge)


def request_node(node_id):
    url = f"{BASE_URL}/api/nodes/{node_id}"
    response = requests.get(url)
    response.raise_for_status()

    print_json(f"노드 조회: {node_id}", response.json())


def request_qr_list():
    url = f"{BASE_URL}/api/qr"
    response = requests.get(url)
    response.raise_for_status()

    print_json("QR 고정점 목록", response.json())


def request_qr_anchor(qr_id):
    url = f"{BASE_URL}/api/qr/{qr_id}"
    response = requests.get(url)
    response.raise_for_status()

    print_json(f"QR 조회: {qr_id}", response.json())


def request_route(start_node_id, end_node_id):
    url = f"{BASE_URL}/api/route"
    params = {
        "start": start_node_id,
        "end": end_node_id,
    }

    response = requests.get(url, params=params)
    response.raise_for_status()

    print_json(f"경로 검색: {start_node_id} -> {end_node_id}", response.json())

def request_nearest_entrance(lat, lon):
    url = f"{BASE_URL}/api/nearest-entrance"

    params = {
        "lat": lat,
        "lon": lon,
    }

    response = requests.get(url, params=params)
    response.raise_for_status()

    print_json("가장 가까운 출구", response.json())

def request_qr(qr_id):
    url = f"{BASE_URL}/api/station/qr_verify/{qr_id}"

    response = requests.get(url)
    response.raise_for_status()

    data = response.json()
    print_json("QR 검증 결과", data)

    return data
    

def main():
    try:
        #request_station_info(7,"숭실대입구")
        #request_nodes()
        #request_edges()

        # 특정 노드 조회
        #request_node("node_001")

        # QR 노드를 JSON에 추가했다면 사용
        # request_qr_list()
        # request_qr_anchor("qr_hall_001")

        # 경로 검색
        #request_route("node_001", "node_064")

        #request_nearest_entrance(37.614805, 127.065628)
        request_qr("a32a1b4f714e1497a22f9d7de7e686d9ade18e43aafd733343b08e22fe3bafc7")

    except requests.exceptions.ConnectionError:
        print("서버에 연결할 수 없습니다.")
        print("FastAPI 서버가 실행 중인지 확인하세요.")
        print("예: uvicorn main:app --reload --host 0.0.0.0 --port 8000")

    except requests.exceptions.HTTPError as e:
        print("HTTP 오류가 발생했습니다.")
        print(e)
        print("응답 내용:")
        print(e.response.text)

    except Exception as e:
        print("예상하지 못한 오류가 발생했습니다.")
        print(e)


if __name__ == "__main__":
    main()