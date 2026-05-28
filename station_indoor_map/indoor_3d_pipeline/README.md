# Indoor 3D Routing Pipeline

이 폴더는 기존 `build_indoor_map_v3.py`의 방향을 바꿔, 사용자가 원하는 3단계 흐름으로 실내 길찾기 데이터를 만드는 파이프라인입니다.

목표는 다음과 같습니다.

1. SHP 파일에 있는 정보를 이용해서 2D 기준 엣지를 생성한다.
2. 2D 기준 그래프를 안내도 이미지와 매핑해서 이미지 상의 거리와 실제 거리 관계를 추정한다.
3. 2차원 안내도 이미지에서 계단 시작/종료, 엘리베이터 탑승 위치, 승강장 위치, 꺾이는 지점 등을 3차원 노드/엣지로 구성한다.

## 전체 구조

```text
station.shp + entrance.shp
  -> 01_build_shp_2d_graph.py
  -> *_shp_2d_graph.json
  -> *_shp_2d_nodes.geojson
  -> *_shp_2d_edges.geojson

*_shp_2d_graph.json + image control points
  -> 02_register_image_to_shp.py
  -> *_image_registration.json

*_image_registration.json + indoor structure JSON
  -> 03_build_indoor_3d_graph.py
  -> *_indoor_3d_graph.json
  -> *_indoor_3d_nodes.geojson
  -> *_indoor_3d_edges.geojson
```

## Step 1. SHP 기반 2D 기준 그래프 생성

### 역할

`station.shp`의 역사 polygon과 `entrance.shp`의 출입구 point를 이용해서 실제 지도 좌표계 위의 2D 기준 그래프를 만듭니다.

이 단계의 그래프는 최종 실내 길찾기 그래프가 아닙니다. 이미지 내부 구조를 얹기 위한 기준 골격입니다.

생성되는 노드:

- `station_centroid`
- `axis_start`
- `axis_end`
- `entrance_{번호}`
- `axis_projection_entrance_{번호}`

생성되는 엣지:

- 역사 장축 기준선
- 출입구에서 장축 기준선까지의 연결
- 장축 위 투영점 간 연결

### 실행 예시

```powershell
.\.venv\Scripts\python.exe indoor_3d_pipeline\01_build_shp_2d_graph.py `
  --station-shp ".\shp_file\station.shp" `
  --entrance-shp ".\shp_file\entrance.shp" `
  --architecture-csv ".\csv_file\서울교통공사_역사건축정보.csv" `
  --depth-csv ".\csv_file\서울교통공사_역사심도정보.csv" `
  --area-csv ".\csv_file\서울교통공사_역사면적정보.csv" `
  --guide-root ".\station_image" `
  --station-name "종각역" `
  --output-dir ".\indoor_3d_output\step1_shp_2d"
```

### 산출물

```text
indoor_3d_output/step1_shp_2d/종각역_shp_2d_graph.json
indoor_3d_output/step1_shp_2d/종각역_shp_2d_nodes.geojson
indoor_3d_output/step1_shp_2d/종각역_shp_2d_edges.geojson
```

QGIS에서는 `*_shp_2d_nodes.geojson`, `*_shp_2d_edges.geojson`, 기존 `stations_merged.geojson`, `entrances_mapped.geojson`를 같이 열어 확인합니다.

## Step 2. 이미지와 SHP 2D 그래프 정합

### 역할

안내도 이미지 위의 출구 번호 위치와 SHP의 실제 출구 좌표를 연결해서 이미지 좌표를 실제 좌표로 바꾸는 변환행렬을 계산합니다.

중요한 점:

- 출구 실제 좌표는 이미 SHP에 있습니다.
- 여기서의 control point는 출구를 새로 만드는 것이 아닙니다.
- control point는 안내도 이미지의 픽셀 좌표를 실제 지도 좌표로 맞추기 위한 앵커입니다.

### control point JSON 형식

기존 annotation draft의 `control_points`를 그대로 쓸 수 있습니다.

```json
{
  "station_name": "종각역",
  "control_points": [
    {"entrance_no": "1", "image_xy": [592, 1680]},
    {"entrance_no": "2", "image_xy": [623, 1395]},
    {"entrance_no": "3", "image_xy": [1952, 1152]},
    {"entrance_no": "4", "image_xy": [1799, 1758]},
    {"entrance_no": "5", "image_xy": [2378, 1455]},
    {"entrance_no": "6", "image_xy": [1365, 1892]}
  ]
}
```

최소 3개가 필요합니다. 가능하면 이미지 전체에 넓게 퍼진 출구 4개 이상을 쓰는 것이 좋습니다.

### 실행 예시

```powershell
.\.venv\Scripts\python.exe indoor_3d_pipeline\02_register_image_to_shp.py `
  --shp-2d-graph ".\indoor_3d_output\step1_shp_2d\종각역_shp_2d_graph.json" `
  --control-points ".\annotations\auto_draft\1_종각역_annotation_draft.json" `
  --image ".\station_image\1\종각.jpg" `
  --transform homography `
  --output ".\indoor_3d_output\step2_registration\종각역_image_registration.json"
```

### 산출물

```text
indoor_3d_output/step2_registration/종각역_image_registration.json
```

확인할 항목:

- `image_to_map_affine`
- `map_to_image_affine`
- `transform_type`
- `meters_per_pixel_estimate`
- `rmse_m`
- `residuals`

`rmse_m`가 너무 크면 control point가 잘못 찍힌 것입니다. 특히 안내도 상단 단면도나 범례의 출구 번호를 앵커로 쓰면 안 됩니다.

### 기울어진 안내도 정합 옵션

`02_register_image_to_shp.py`는 세 가지 정합 방식을 지원합니다.

```text
partial_affine: 회전, 이동, 균일 스케일 중심. 평면도에 가까운 이미지용.
affine: 축별 스케일 차이와 shear 허용. 살짝 기울어진 이미지용.
homography: 원근 왜곡 허용. 3D/사선 안내도용. 최소 4개 control point 필요.
```

기본값은 `homography`입니다. 기울어진 3D 안내도는 보통 `homography`가 더 잘 맞습니다. 다만 control point 바깥쪽은 과하게 왜곡될 수 있으므로 GeoJSON/HTML 뷰어로 결과를 확인해야 합니다.

## Step 3. 이미지 내부 구조를 3D 그래프로 구성

### 역할

안내도 이미지 위에서 내부 이동 지점을 정의하고, Step 2의 정합 결과를 이용해 실제 좌표계의 3D 노드/엣지로 변환합니다.

만들어야 하는 대표 노드:

- 계단 시작점
- 계단 종료점
- 엘리베이터 탑승 위치
- 엘리베이터 하차 위치
- 승강장 위치
- 대합실 위치
- 개찰구 위치
- 꺾이는 지점
- 환승통로 연결점

### indoor structure JSON 형식

예시는 `examples/jonggak_indoor_structure_example.json`에 있습니다.

핵심 구조:

```json
{
  "station_name": "종각역",
  "nodes": [
    {
      "id": "stairs_center_b1",
      "kind": "stairs_start",
      "floor": "B1",
      "image_xy": [1595, 1875]
    },
    {
      "id": "stairs_center_b2",
      "kind": "stairs_end",
      "floor": "B2",
      "image_xy": [1420, 2250]
    }
  ],
  "edges": [
    {
      "from": "stairs_center_b1",
      "to": "stairs_center_b2",
      "kind": "stairs"
    }
  ]
}
```

### z 좌표

3D 그래프에서는 각 노드에 `z_m`가 들어갑니다.

기본 추정:

```text
ground = 0
B1 = -4
B2 = -8
B3 = -12
B4 = -16
```

역사 심도 CSV에서 `depth_station_ref_m`, `depth_track_ref_m`가 있으면 승강장 깊이 추정에 사용합니다.

직접 지정할 수도 있습니다.

```powershell
--floor-depths "B1=-4,B2=-9.5,ground=0"
```

### 실행 예시

```powershell
.\.venv\Scripts\python.exe indoor_3d_pipeline\03_build_indoor_3d_graph.py `
  --registration ".\indoor_3d_output\step2_registration\종각역_image_registration.json" `
  --indoor-structure ".\indoor_3d_pipeline\examples\jonggak_indoor_structure_example.json" `
  --station-base ".\indoor_map\종각역_base.json" `
  --floor-depths "B1=-4,B2=-8.44,ground=0" `
  --output-dir ".\indoor_3d_output\step3_indoor_3d"
```

### 산출물

```text
indoor_3d_output/step3_indoor_3d/종각역_indoor_3d_graph.json
indoor_3d_output/step3_indoor_3d/종각역_indoor_3d_nodes.geojson
indoor_3d_output/step3_indoor_3d/종각역_indoor_3d_edges.geojson
```

각 edge에는 다음 거리값이 들어갑니다.

- `distance_2d_m`
- `distance_3d_m`

길찾기 비용은 보통 `distance_3d_m`를 기본값으로 쓰고, 계단/엘리베이터/에스컬레이터에는 별도 가중치를 추가하면 됩니다.

## 검수 방법

### 1차: SHP 2D 그래프 확인

QGIS에서 다음 파일을 같이 엽니다.

```text
indoor_3d_output/step1_shp_2d/*_shp_2d_nodes.geojson
indoor_3d_output/step1_shp_2d/*_shp_2d_edges.geojson
indoor_map/stations_merged.geojson
indoor_map/entrances_mapped.geojson
```

확인:

- 출입구가 역 polygon 주변에 있는가
- 장축 기준선이 역의 방향과 대략 맞는가
- 출입구에서 기준선까지 연결이 크게 튀지 않는가

### 2차: 이미지 정합 확인

`*_image_registration.json`에서 확인합니다.

```text
rmse_m
residuals[].error_m
meters_per_pixel_estimate
```

오차가 큰 control point는 제거하거나 수정해야 합니다.

### 3차: 3D 실내 그래프 확인

QGIS에서 다음 파일을 엽니다.

```text
indoor_3d_output/step3_indoor_3d/*_indoor_3d_nodes.geojson
indoor_3d_output/step3_indoor_3d/*_indoor_3d_edges.geojson
```

확인:

- 노드가 역 주변에 자연스럽게 놓이는가
- 엣지가 비정상적으로 멀리 튀지 않는가
- 계단 시작/종료 노드의 `z_m`가 다른가
- 승강장 노드가 B2 또는 실제 심도에 맞게 들어갔는가
- `distance_3d_m`가 0이거나 비정상적으로 크지 않은가

## 현재 한계

이 파이프라인은 사용자가 원하는 구조에 맞게 단계는 분리했지만, 아직 완전 자동 3D 실내 그래프 생성기는 아닙니다.

자동화 가능한 부분:

- SHP 기반 2D 기준 그래프
- 이미지-지도 정합
- z 좌표 부여
- 3D 거리 계산

검수 또는 반자동 입력이 필요한 부분:

- 이미지에서 계단 시작/종료점 찾기
- 엘리베이터 탑승/하차 위치 찾기
- 승강장 중심선 또는 승강장 노드 배치
- 내부 꺾임 지점 배치
- 실제 이동 가능한 edge 확정

안내도 이미지는 실제 3D 도면이 아니라 안내용 그림이므로, 이 단계는 완전 자동보다 `자동 후보 생성 + GeoJSON 검수` 방식이 안전합니다.

## 종각역 빠른 실행 순서

```powershell
.\.venv\Scripts\python.exe indoor_3d_pipeline\01_build_shp_2d_graph.py `
  --station-shp ".\shp_file\station.shp" `
  --entrance-shp ".\shp_file\entrance.shp" `
  --architecture-csv ".\csv_file\서울교통공사_역사건축정보.csv" `
  --depth-csv ".\csv_file\서울교통공사_역사심도정보.csv" `
  --area-csv ".\csv_file\서울교통공사_역사면적정보.csv" `
  --guide-root ".\station_image" `
  --station-name "종각역" `
  --output-dir ".\indoor_3d_output\step1_shp_2d"
```

```powershell
.\.venv\Scripts\python.exe indoor_3d_pipeline\02_register_image_to_shp.py `
  --shp-2d-graph ".\indoor_3d_output\step1_shp_2d\종각역_shp_2d_graph.json" `
  --control-points ".\annotations\auto_draft\1_종각역_annotation_draft.json" `
  --image ".\station_image\1\종각.jpg" `
  --output ".\indoor_3d_output\step2_registration\종각역_image_registration.json"
```

```powershell
.\.venv\Scripts\python.exe indoor_3d_pipeline\03_build_indoor_3d_graph.py `
  --registration ".\indoor_3d_output\step2_registration\종각역_image_registration.json" `
  --indoor-structure ".\indoor_3d_pipeline\examples\jonggak_indoor_structure_example.json" `
  --station-base ".\indoor_map\종각역_base.json" `
  --floor-depths "B1=-4,B2=-8.44,ground=0" `
  --output-dir ".\indoor_3d_output\step3_indoor_3d"
```
