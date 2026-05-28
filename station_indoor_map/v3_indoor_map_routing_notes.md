# build_indoor_map_v3 기준 정리

이 문서는 `build_indoor_map_v3.py`가 현재 폴더의 데이터를 어떻게 처리하는지, 그리고 이 결과를 이용해 실내 길찾기를 하려면 무엇을 준비해야 하는지 정리한 내용입니다.

## 1. v3 스크립트의 역할

`build_indoor_map_v3.py`는 서울교통공사 역 실내지도용 기초 데이터를 만드는 스크립트입니다.

주요 역할은 다음과 같습니다.

1. 역사 polygon SHP와 출입구 point SHP를 읽습니다.
2. 서울교통공사 CSV 3종을 읽어서 역별 메타데이터로 병합합니다.
3. 역별 중심점, 면적, 장축/단축 길이, 장축 방향을 계산합니다.
4. 출입구를 가장 가까운 역에 매칭합니다.
5. `station_image` 폴더에서 역이용안내도 이미지를 찾아 역 정보에 연결합니다.
6. 특정 역에 annotation JSON이 있으면 이미지 좌표를 실제 지도 좌표로 정합하고 실내 그래프를 생성합니다.

즉, v3는 "길찾기 자체"를 수행하는 스크립트라기보다, 길찾기에 필요한 역별 기반 데이터와 실내 그래프 데이터를 생성하는 준비 도구입니다.

## 2. 입력 데이터

현재 폴더 기준 주요 입력은 다음과 같습니다.

| 구분 | 경로 | 설명 |
| --- | --- | --- |
| 역사 SHP | `shp_file/station.shp` | 역사의 공간 polygon |
| 출입구 SHP | `shp_file/entrance.shp` | 지하철 출입구 point |
| 건축 CSV | `csv_file/서울교통공사_역사건축정보.csv` | 호선, 승강장 유형, 역사 길이, 층수, 면적 |
| 심도 CSV | `csv_file/서울교통공사_역사심도정보.csv` | 층수, 형식, 선로/정거장 깊이 |
| 면적 CSV | `csv_file/서울교통공사_역사면적정보.csv` | 대합실 면적, 승강장 면적 |
| 안내도 이미지 | `station_image/` | 호선별 역이용안내도 이미지 |
| annotation JSON | 별도 작성 필요 | 이미지 위의 출입구/노드/엣지 좌표 |

## 3. 처리 흐름

### 3.1 공간 데이터 읽기

`station.shp`, `entrance.shp`를 읽고 좌표계를 `EPSG:5179`로 맞춥니다.

`EPSG:5179`는 미터 단위의 한국 좌표계이므로, 이후 거리 계산에 바로 사용할 수 있습니다.

### 3.2 역 이름 정규화

역 이름은 `normalize_station_name()`에서 정리됩니다.

예:

- `신설동` -> `신설동역`
- `종로3가역` -> `종로3가역`

공백도 제거합니다.

### 3.3 역사 geometry 지표 계산

각 역 polygon에서 다음 값을 계산합니다.

- `centroid_x`, `centroid_y`: 역사 중심점
- `geometry_area_m2`: polygon 면적
- `major_axis_m`: 최소 회전 사각형 기준 장축 길이
- `minor_axis_m`: 최소 회전 사각형 기준 단축 길이
- `major_axis_angle_deg`: 장축 방향 각도

이 값들은 역의 대략적인 크기, 방향, 배치를 파악하는 데 사용됩니다.

### 3.4 공식 CSV 메타데이터 병합

CSV 3종을 역 이름 기준으로 병합합니다.

생성되는 주요 필드는 다음과 같습니다.

- `line_no`
- `platform_type`
- `station_length_m`
- `floor_text`
- `station_area_m2`
- `depth_track_ref_m`
- `depth_station_ref_m`
- `hall_area_m2`
- `platform_area_m2`

### 3.5 출입구 매칭

출입구 point를 각 역 중심점에 대해 최근접 매칭합니다.

기본 최대 거리는 `120m`입니다.

```text
출입구 point -> 가장 가까운 역 중심점 -> 120m 이내면 해당 역 출입구로 연결
```

이 결과는 `entrances_mapped.geojson`와 `station_base_summary.json` 안에 들어갑니다.

### 3.6 안내도 이미지 연결

`station_image` 폴더 아래의 이미지 파일을 순회하면서 파일명 기준으로 역 이름을 찾습니다.

예:

```text
station_image/1/신설동.jpg -> 신설동역 안내도 후보
station_image/2/신설동.jpg -> 신설동역 안내도 후보
```

현재 v3의 `_extract_line_no_from_path()`는 `1호선`, `2호선` 같은 폴더명을 기대합니다. 하지만 현재 폴더는 `1`, `2`, `3`처럼 숫자만 사용하고 있어서 `guide_image.line_no`가 대부분 `null`로 들어갑니다.

## 4. 생성되는 산출물

현재 v3 실행 결과는 `indoor_map` 폴더에 저장됩니다.

| 파일 | 설명 |
| --- | --- |
| `indoor_map/stations_merged.geojson` | 역 polygon + 메타데이터 병합 결과 |
| `indoor_map/entrances_mapped.geojson` | 출입구 point + 역 매칭 결과 |
| `indoor_map/station_base_summary.json` | 전체 역별 기초 정보 요약 |
| `indoor_map/신설동역_base.json` | 특정 역 단일 기초 정보 |

현재 확인된 상태:

- 전체 역 수: `306`
- 안내도 이미지가 연결된 역: `167`
- 출입구가 매칭된 역: `302`
- 공식 CSV 메타데이터가 모두 연결된 역: `167`
- 아직 생성되지 않은 파일:
  - `*_indoor_graph.json`
  - `*_indoor_nodes.geojson`
  - `*_indoor_edges.geojson`

즉, 현재는 "실내 길찾기 그래프 생성 전 단계"입니다.

## 5. 실행 예시

기초 데이터만 생성하는 실행 예시입니다.

```powershell
py build_indoor_map_v3.py `
  --station-shp ".\shp_file\station.shp" `
  --entrance-shp ".\shp_file\entrance.shp" `
  --architecture-csv ".\csv_file\서울교통공사_역사건축정보.csv" `
  --depth-csv ".\csv_file\서울교통공사_역사심도정보.csv" `
  --area-csv ".\csv_file\서울교통공사_역사면적정보.csv" `
  --guide-root ".\station_image" `
  --station-name "신설동역" `
  --output-dir ".\indoor_map"
```

annotation JSON까지 사용해서 실내 그래프를 생성하는 실행 예시입니다.

```powershell
py build_indoor_map_v3.py `
  --station-shp ".\shp_file\station.shp" `
  --entrance-shp ".\shp_file\entrance.shp" `
  --architecture-csv ".\csv_file\서울교통공사_역사건축정보.csv" `
  --depth-csv ".\csv_file\서울교통공사_역사심도정보.csv" `
  --area-csv ".\csv_file\서울교통공사_역사면적정보.csv" `
  --guide-root ".\station_image" `
  --station-name "신설동역" `
  --guide-annotations ".\sinseldong_annotations.json" `
  --output-dir ".\indoor_map"
```

## 6. 길찾기를 위한 핵심 준비물

길찾기를 하려면 "그래프"가 필요합니다.

그래프는 다음 요소로 구성됩니다.

- 노드: 출입구, 대합실, 승강장, 계단, 엘리베이터, 에스컬레이터, 환승통로, 개찰구 등
- 엣지: 노드와 노드 사이의 이동 가능 연결
- 가중치: 거리, 시간, 계단/엘리베이터 비용, 교통약자 이동 비용 등

현재 v3는 annotation JSON을 통해 이 그래프를 생성할 수 있습니다.

## 7. annotation JSON 구조

annotation JSON은 사람이 안내도 이미지를 보고 직접 찍어야 하는 데이터입니다.

최소 구조는 다음과 같습니다.

```json
{
  "station_name": "신설동역",
  "image_width": 2480,
  "image_height": 3508,
  "control_points": [
    {"entrance_no": "2", "image_xy": [1200, 300]},
    {"entrance_no": "5", "image_xy": [1500, 700]},
    {"entrance_no": "6", "image_xy": [800, 900]}
  ],
  "nodes": [
    {"id": "exit_2", "kind": "exit", "floor": "B1", "image_xy": [1200, 300]},
    {"id": "hall_center", "kind": "hall", "floor": "B1", "image_xy": [1000, 700]},
    {"id": "platform_1", "kind": "platform", "floor": "B2", "image_xy": [900, 1100]}
  ],
  "edges": [
    {"from": "exit_2", "to": "hall_center"},
    {"from": "hall_center", "to": "platform_1"}
  ]
}
```

### 7.1 control_points

`control_points`는 안내도 이미지 좌표와 실제 출입구 좌표를 맞추기 위한 기준점입니다.

v3는 이 값을 사용해서 OpenCV의 affine transform을 추정합니다.

필수 조건:

- 최소 3개 이상의 출입구 대응점이 필요합니다.
- `entrance_no`는 해당 역의 `entrances` 목록에 존재해야 합니다.
- 이미지 위에서 찍은 좌표는 `[x, y]` 픽셀 좌표입니다.

### 7.2 nodes

`nodes`는 길찾기 그래프의 지점입니다.

권장 노드 종류:

- `exit`: 출입구
- `gate`: 개찰구
- `hall`: 대합실 주요 지점
- `platform`: 승강장 주요 지점
- `stairs`: 계단
- `escalator`: 에스컬레이터
- `elevator`: 엘리베이터
- `transfer`: 환승 연결 지점

### 7.3 edges

`edges`는 노드 사이의 연결입니다.

v3는 각 엣지의 양 끝 노드 좌표를 실제 좌표로 변환한 뒤 직선거리 `distance_m`를 계산합니다.

주의할 점:

- 벽을 통과하는 엣지를 만들면 실제 길찾기 결과도 벽을 통과하게 됩니다.
- 굽은 통로는 중간 노드를 추가해서 여러 엣지로 나누는 것이 좋습니다.
- 층 이동은 계단/엘리베이터/에스컬레이터 노드로 표현하는 것이 좋습니다.

## 8. v3가 생성하는 실내 그래프 산출물

annotation JSON을 넣고 실행하면 다음 파일이 생성됩니다.

| 파일 | 설명 |
| --- | --- |
| `{역명}_indoor_graph.json` | 실내 길찾기용 그래프 JSON |
| `{역명}_indoor_nodes.geojson` | 노드 point GeoJSON |
| `{역명}_indoor_edges.geojson` | 엣지 line GeoJSON |

`*_indoor_graph.json`에는 다음 정보가 들어갑니다.

- `station_name`
- `transform_image_to_map`
- `nodes`
- `edges`
- `control_points`

각 노드에는 이미지 좌표와 실제 지도 좌표가 함께 들어갑니다.

각 엣지에는 `distance_m`가 들어갑니다.

## 9. 실제 길찾기 구현에 필요한 것

v3가 만든 그래프 파일을 사용해 길찾기를 하려면 별도의 탐색 로직이 필요합니다.

가장 기본적인 방식:

1. `{역명}_indoor_graph.json`을 읽습니다.
2. `nodes`를 id 기준 dictionary로 만듭니다.
3. `edges`를 adjacency list로 변환합니다.
4. `distance_m`를 비용으로 사용합니다.
5. Dijkstra 또는 A*로 최단 경로를 찾습니다.

추가로 고려할 수 있는 비용:

- 계단 회피
- 엘리베이터 우선
- 에스컬레이터 방향
- 환승 최소화
- 개찰구 통과 여부
- 층 이동 비용
- 보행 약자 경로

## 10. 현재 데이터에서 주의할 점

### 10.1 출입구 번호 중복

현재 일부 역에는 같은 출입구 번호가 중복으로 매칭되어 있습니다.

예:

- `신설동역`: `10`, `6`번 출입구 중복
- 전체적으로 출입구 번호 중복이 있는 역: `28`개

annotation에서 `entrance_no`를 사용할 때 같은 번호가 중복되어 있으면 affine 정합 기준점이 애매해질 수 있습니다.

### 10.2 안내도 호선 매칭

현재 `station_image` 폴더 구조가 `1`, `2`, `3`처럼 숫자 폴더입니다.

v3는 `1호선`, `2호선` 같은 폴더명을 기대하고 있어서 이미지의 `line_no`가 대부분 `null`입니다.

개선 방법:

- 폴더명을 `1호선`, `2호선`처럼 바꾸거나
- `_extract_line_no_from_path()`가 숫자 폴더도 인식하도록 수정합니다.

### 10.3 환승역 이름 불일치

일부 환승역은 SHP, CSV, 이미지 파일명에서 이름 표현이 다를 수 있습니다.

예상 이슈:

- `총신대입구(이수)역`
- `이수역(7호선)역`
- `사당역`
- `사당역(2호선)역`
- `사당역(4호선)역`

길찾기, 특히 환승 경로를 만들려면 역 이름/호선/역 id 기준을 명확히 정리해야 합니다.

## 11. 추천 작업 순서

1. 대상 역을 하나 정합니다. 예: `신설동역`.
2. 해당 역의 `*_base.json`에서 출입구 목록과 안내도 후보를 확인합니다.
3. 안내도 이미지 위에서 출입구 위치를 최소 3개 이상 찍어 `control_points`를 만듭니다.
4. 대합실, 승강장, 계단, 엘리베이터, 환승통로 등 주요 지점을 `nodes`로 찍습니다.
5. 실제 이동 가능한 연결만 `edges`로 작성합니다.
6. v3를 `--guide-annotations`와 함께 실행해 실내 그래프를 생성합니다.
7. 생성된 `*_indoor_nodes.geojson`, `*_indoor_edges.geojson`를 GIS 또는 지도 뷰어에서 확인합니다.
8. 그래프가 실제 안내도와 맞으면 Dijkstra/A* 길찾기 코드를 추가합니다.

## 12. 결론

현재 v3 기준으로는 역별 공간 정보, 출입구, 공식 메타데이터, 안내도 이미지 연결까지는 준비되어 있습니다.

하지만 실내 길찾기를 하려면 아직 역별 annotation JSON이 필요합니다. annotation JSON을 만들면 v3가 이미지 좌표를 실제 좌표로 변환하고, 노드/엣지 기반의 실내 그래프 파일을 생성합니다.

따라서 다음 단계는 "신설동역 같은 대상 역 하나를 골라 annotation JSON을 작성하고, `*_indoor_graph.json`을 생성해보는 것"입니다.
