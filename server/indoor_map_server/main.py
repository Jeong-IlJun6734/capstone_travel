import json
import math
import heapq
from pathlib import Path
from functools import lru_cache
import geopandas as gpd
from shapely.geometry import Point

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware


app = FastAPI(title="Station Mock Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


BASE_DIR = Path(__file__).resolve().parent

DATA_DIR = BASE_DIR / "data"

ENTRANCE_DIR = BASE_DIR / "entrance"
ENTRANCE_SHP_PATH = ENTRANCE_DIR / "entrance.shp"

# .prj 파일이 없으므로 직접 지정
# 현재 entrance.shp 좌표가 POINT (955000, 1952000) 형태라 EPSG:5179로 처리
ENTRANCE_SOURCE_CRS = "EPSG:5179"

# GPS 입력은 위도/경도
GPS_CRS = "EPSG:4326"

# 거리 계산용 좌표계
DISTANCE_CRS = "EPSG:5179"

DEFAULT_LINE_NO = "6"
DEFAULT_STATION_NAME = "석계"


def station_file_path(line_no: str, station_name: str) -> Path:
    safe_line = str(line_no).strip()
    safe_station = str(station_name).strip()

    return DATA_DIR / f"{safe_line}_{safe_station}.json"


def load_station_data(line_no: str, station_name: str):
    data_path = station_file_path(line_no, station_name)

    if not data_path.exists():
        raise HTTPException(
            status_code=404,
            detail=f"Station JSON file not found: {data_path}"
        )

    try:
        with open(data_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        raise HTTPException(
            status_code=500,
            detail=f"Invalid JSON file: {data_path}, error={str(e)}"
        )


def build_node_map(data):
    return {
        node["id"]: node
        for node in data.get("nodes", [])
        if "id" in node
    }


def distance_between_nodes(node_a, node_b):
    ax, ay = node_a["image_xy"]
    bx, by = node_b["image_xy"]

    floor_penalty = 0
    if node_a.get("floor") != node_b.get("floor"):
        floor_penalty = 500

    return math.sqrt((ax - bx) ** 2 + (ay - by) ** 2) + floor_penalty


def build_graph(data):
    node_map = build_node_map(data)

    graph = {
        node_id: []
        for node_id in node_map.keys()
    }

    for edge in data.get("edges", []):
        from_id = edge.get("from")
        to_id = edge.get("to")

        if from_id not in node_map or to_id not in node_map:
            continue

        cost = edge.get("cost")

        if cost is None:
            cost = distance_between_nodes(
                node_map[from_id],
                node_map[to_id]
            )

        graph[from_id].append({
            "to": to_id,
            "cost": cost,
            "kind": edge.get("kind", "walk")
        })

        graph[to_id].append({
            "to": from_id,
            "cost": cost,
            "kind": edge.get("kind", "walk")
        })

    return graph


def heuristic(node_a, node_b):
    ax, ay = node_a["image_xy"]
    bx, by = node_b["image_xy"]

    floor_penalty = 0
    if node_a.get("floor") != node_b.get("floor"):
        floor_penalty = 500

    return math.sqrt((ax - bx) ** 2 + (ay - by) ** 2) + floor_penalty


def reconstruct_path(came_from, current):
    path = [current]

    while current in came_from:
        current = came_from[current]
        path.append(current)

    path.reverse()
    return path


def find_path_astar(data, start_id, end_id):
    node_map = build_node_map(data)

    if start_id not in node_map:
        raise HTTPException(
            status_code=404,
            detail=f"Start node not found: {start_id}"
        )

    if end_id not in node_map:
        raise HTTPException(
            status_code=404,
            detail=f"End node not found: {end_id}"
        )

    graph = build_graph(data)

    open_heap = []
    heapq.heappush(open_heap, (0, start_id))

    came_from = {}

    g_score = {
        node_id: float("inf")
        for node_id in node_map.keys()
    }
    g_score[start_id] = 0

    visited = set()

    while open_heap:
        _, current = heapq.heappop(open_heap)

        if current in visited:
            continue

        visited.add(current)

        if current == end_id:
            return reconstruct_path(came_from, current)

        for neighbor in graph.get(current, []):
            neighbor_id = neighbor["to"]
            tentative_g_score = g_score[current] + neighbor["cost"]

            if tentative_g_score < g_score[neighbor_id]:
                came_from[neighbor_id] = current
                g_score[neighbor_id] = tentative_g_score

                priority = tentative_g_score + heuristic(
                    node_map[neighbor_id],
                    node_map[end_id]
                )

                heapq.heappush(open_heap, (priority, neighbor_id))

    raise HTTPException(
        status_code=404,
        detail=f"Path not found: {start_id} -> {end_id}"
    )


def make_station_summary(data):
    return {
        "station_name": data.get("station_name"),
        "line_no": data.get("line_no"),
        "source_image": data.get("source_image"),
        "image_width": data.get("image_width"),
        "image_height": data.get("image_height"),
        "node_count": len(data.get("nodes", [])),
        "edge_count": len(data.get("edges", [])),
    }


def make_route_response(data, start: str, end: str):
    node_map = build_node_map(data)

    path_ids = find_path_astar(data, start, end)

    path_nodes = []
    coordinates = []
    total_distance = 0

    for node_id in path_ids:
        node = node_map[node_id]

        path_nodes.append({
            "id": node.get("id"),
            "kind": node.get("kind"),
            "floor": node.get("floor"),
            "image_xy": node.get("image_xy"),
            "label": node.get("label"),
            "entrance_no": node.get("entrance_no"),
        })

        coordinates.append(node.get("image_xy"))

    for i in range(len(path_ids) - 1):
        node_a = node_map[path_ids[i]]
        node_b = node_map[path_ids[i + 1]]
        total_distance += distance_between_nodes(node_a, node_b)

    return {
        "station_name": data.get("station_name"),
        "line_no": data.get("line_no"),
        "start": start,
        "end": end,
        "path": path_ids,
        "path_nodes": path_nodes,
        "coordinates": coordinates,
        "total_distance": round(total_distance, 2),
        "node_count": len(path_ids),
    }

@lru_cache(maxsize=1)
def load_entrance_gdf():
    if not ENTRANCE_SHP_PATH.exists():
        raise HTTPException(
            status_code=404,
            detail=f"Entrance shapefile not found: {ENTRANCE_SHP_PATH}"
        )

    gdf = gpd.read_file(ENTRANCE_SHP_PATH)

    if gdf.empty:
        raise HTTPException(
            status_code=500,
            detail="Entrance shapefile is empty"
        )

    # entrance.prj가 없기 때문에 CRS를 직접 지정
    if gdf.crs is None:
        gdf = gdf.set_crs(ENTRANCE_SOURCE_CRS)

    return gdf


def find_nearest_entrance(lat: float, lon: float):
    entrance_gdf = load_entrance_gdf()

    point_gdf = gpd.GeoDataFrame(
        [{"lat": lat, "lon": lon}],
        geometry=[Point(lon, lat)],
        crs=GPS_CRS
    )

    entrance_projected = entrance_gdf.to_crs(DISTANCE_CRS)
    point_projected = point_gdf.to_crs(DISTANCE_CRS)

    point_geom = point_projected.geometry.iloc[0]

    distances = entrance_projected.geometry.distance(point_geom)

    nearest_index = distances.idxmin()
    nearest_distance = float(distances.loc[nearest_index])

    nearest_row = entrance_gdf.loc[nearest_index]

    return {
        "entrance_no": str(nearest_row.get("ENTRC_NO")),
        "sub_entrance_serial": str(nearest_row.get("SUB_ENT_SN")),
        "sig_cd": str(nearest_row.get("SIG_CD")),
        "distance_m": round(nearest_distance, 2),
        "input": {
            "lat": lat,
            "lon": lon
        }
    }

def is_qr_node(node):
    return node.get("kind") in ["qr", "qr_anchor"]


def find_qr_in_all_stations(qr_id: str):
    """
    data 폴더 안의 모든 역 JSON 파일을 확인해서 qr_id가 있는 QR 노드를 찾는다.
    파일명 규칙: {line_no}_{station_name}.json
    예: 7_숭실대입구.json
    """
    if not DATA_DIR.exists():
        raise HTTPException(
            status_code=500,
            detail=f"Data directory not found: {DATA_DIR}"
        )

    for json_path in DATA_DIR.glob("*.json"):
        try:
            with open(json_path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except json.JSONDecodeError:
            continue

        for node in data.get("nodes", []):
            if not is_qr_node(node):
                continue

            if node.get("qr_id") == qr_id:
                return data, node, json_path

    return None, None, None


def make_qr_verify_response(data, node, json_path):
    return {
        "valid": True,
        "station_name": data.get("station_name"),
        "line_no": data.get("line_no"),
        "qr_id": node.get("qr_id"),
        "node_id": node.get("id"),
        "kind": node.get("kind"),
        "floor": node.get("floor"),
        "image_xy": node.get("image_xy"),
        "click_index": node.get("click_index"),
        "label": node.get("label"),
        "nearest_node_id": node.get("nearest_node_id"),
        "source_file": json_path.name,
        "message": "QR verified"
    }

@app.get("/")
def root():
    return {
        "message": "Station mock server is running",
        "docs": "/docs"
    }


@app.get("/api/stations")
def get_station_list():
    stations = []

    if not DATA_DIR.exists():
        return {
            "count": 0,
            "stations": []
        }

    for path in DATA_DIR.glob("*.json"):
        stem = path.stem

        if "_" not in stem:
            continue

        line_no, station_name = stem.split("_", 1)

        stations.append({
            "line_no": line_no,
            "station_name": station_name,
            "file": path.name
        })

    stations.sort(key=lambda item: (item["line_no"], item["station_name"]))

    return {
        "count": len(stations),
        "stations": stations
    }


@app.get("/api/stations/{line_no}/{station_name}")
def get_station_by_name(line_no: str, station_name: str):
    data = load_station_data(line_no, station_name)
    return make_station_summary(data)


@app.get("/api/stations/{line_no}/{station_name}/nodes")
def get_nodes_by_station(line_no: str, station_name: str):
    data = load_station_data(line_no, station_name)
    return data.get("nodes", [])


@app.get("/api/stations/{line_no}/{station_name}/edges")
def get_edges_by_station(line_no: str, station_name: str):
    data = load_station_data(line_no, station_name)
    return data.get("edges", [])


@app.get("/api/stations/{line_no}/{station_name}/nodes/{node_id}")
def get_node_by_station(line_no: str, station_name: str, node_id: str):
    data = load_station_data(line_no, station_name)

    for node in data.get("nodes", []):
        if node.get("id") == node_id:
            return node

    raise HTTPException(
        status_code=404,
        detail=f"Node not found: {node_id}"
    )


@app.get("/api/stations/{line_no}/{station_name}/qr")
def get_qr_anchors_by_station(line_no: str, station_name: str):
    data = load_station_data(line_no, station_name)

    qr_nodes = [
        node for node in data.get("nodes", [])
        if node.get("kind") == "qr_anchor"
    ]

    return {
        "station_name": data.get("station_name"),
        "line_no": data.get("line_no"),
        "qr_count": len(qr_nodes),
        "qr_anchors": qr_nodes,
    }


@app.get("/api/stations/{line_no}/{station_name}/qr/{qr_id}")
def get_qr_anchor_by_station(line_no: str, station_name: str, qr_id: str):
    data = load_station_data(line_no, station_name)

    for node in data.get("nodes", []):
        if node.get("id") == qr_id and node.get("kind") == "qr_anchor":
            return {
                "qr_id": node.get("id"),
                "station_name": data.get("station_name"),
                "line_no": data.get("line_no"),
                "floor": node.get("floor"),
                "image_xy": node.get("image_xy"),
                "label": node.get("label"),
                "anchor_type": node.get("anchor_type"),
                "nearest_node_id": node.get("nearest_node_id"),
            }

    raise HTTPException(
        status_code=404,
        detail=f"QR anchor not found: {qr_id}"
    )


@app.get("/api/stations/{line_no}/{station_name}/route")
def get_route_by_station(line_no: str, station_name: str, start: str, end: str):
    data = load_station_data(line_no, station_name)
    return make_route_response(data, start, end)


# 기존 demo_request.py와 호환하기 위한 기본 API
# 기본 역은 6_석계.json으로 처리
@app.get("/api/station")
def get_station():
    data = load_station_data(DEFAULT_LINE_NO, DEFAULT_STATION_NAME)
    return make_station_summary(data)


@app.get("/api/nodes")
def get_nodes():
    data = load_station_data(DEFAULT_LINE_NO, DEFAULT_STATION_NAME)
    return data.get("nodes", [])


@app.get("/api/edges")
def get_edges():
    data = load_station_data(DEFAULT_LINE_NO, DEFAULT_STATION_NAME)
    return data.get("edges", [])


@app.get("/api/nodes/{node_id}")
def get_node(node_id: str):
    data = load_station_data(DEFAULT_LINE_NO, DEFAULT_STATION_NAME)

    for node in data.get("nodes", []):
        if node.get("id") == node_id:
            return node

    raise HTTPException(
        status_code=404,
        detail=f"Node not found: {node_id}"
    )


@app.get("/api/qr")
def get_qr_anchors():
    data = load_station_data(DEFAULT_LINE_NO, DEFAULT_STATION_NAME)

    qr_nodes = [
        node for node in data.get("nodes", [])
        if node.get("kind") == "qr_anchor"
    ]

    return {
        "station_name": data.get("station_name"),
        "line_no": data.get("line_no"),
        "qr_count": len(qr_nodes),
        "qr_anchors": qr_nodes,
    }


@app.get("/api/qr/{qr_id}")
def get_qr_anchor(qr_id: str):
    data = load_station_data(DEFAULT_LINE_NO, DEFAULT_STATION_NAME)

    for node in data.get("nodes", []):
        if node.get("id") == qr_id and node.get("kind") == "qr_anchor":
            return {
                "qr_id": node.get("id"),
                "station_name": data.get("station_name"),
                "line_no": data.get("line_no"),
                "floor": node.get("floor"),
                "image_xy": node.get("image_xy"),
                "label": node.get("label"),
                "anchor_type": node.get("anchor_type"),
                "nearest_node_id": node.get("nearest_node_id"),
            }

    raise HTTPException(
        status_code=404,
        detail=f"QR anchor not found: {qr_id}"
    )


@app.get("/api/route")
def get_route(start: str, end: str):
    data = load_station_data(DEFAULT_LINE_NO, DEFAULT_STATION_NAME)
    return make_route_response(data, start, end)

@app.get("/api/nearest-entrance")
def get_nearest_entrance(lat: float, lon: float):
    return find_nearest_entrance(lat, lon)

@app.get("/api/stations/{line_no}/{station_name}/nearest-entrance")
def get_nearest_entrance_by_station(
    line_no: str,
    station_name: str,
    lat: float,
    lon: float
):
    result = find_nearest_entrance(lat, lon)

    return {
        "requested_line_no": line_no,
        "requested_station_name": station_name,
        **result
    }

@app.get("/api/entrance/debug")
def debug_entrance():
    gdf = load_entrance_gdf()

    sample = []

    for idx, row in gdf.head(5).iterrows():
        geom = row.geometry

        sample.append({
            "index": int(idx),
            "SIG_CD": str(row.get("SIG_CD")),
            "SUB_ENT_SN": str(row.get("SUB_ENT_SN")),
            "ENTRC_NO": str(row.get("ENTRC_NO")),
            "geometry_type": geom.geom_type if geom is not None else None,
            "x": geom.x if geom is not None else None,
            "y": geom.y if geom is not None else None,
        })

    return {
        "crs": str(gdf.crs),
        "count": len(gdf),
        "bounds": [float(v) for v in gdf.total_bounds],
        "sample": sample
    }

@app.get("/api/station/qr_verify/{qr_id}")
def verify_qr_by_id(qr_id: str):
    qr_id = qr_id.strip()

    data, node, json_path = find_qr_in_all_stations(qr_id)

    if node is None:
        raise HTTPException(
            status_code=404,
            detail={
                "valid": False,
                "message": "QR not found",
                "qr_id": qr_id
            }
        )

    return make_qr_verify_response(data, node, json_path)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True
    )