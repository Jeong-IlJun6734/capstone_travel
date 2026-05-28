# Auto Draft Annotation Results

`tools/generate_annotation_drafts.py`로 `station_image` 전체 이미지를 처리해 생성한 annotation 초안입니다.

더 정교화된 최신 결과는 `annotations/auto_draft_refined`에 있습니다.

## 결과

- 처리 이미지: 269장
- 생성 JSON: 269개
- 리포트: `_annotation_draft_report.json`
- `control_points`가 3개 이상 잡힌 이미지: 154장

정교화 버전 결과:

- 폴더: `annotations/auto_draft_refined`
- 처리 이미지: 269장
- 생성 JSON: 269개
- `control_points`가 3개 이상 잡힌 이미지: 228장

## 중요한 주의사항

이 폴더의 JSON은 **자동 초안**입니다.

현재 환경에는 Tesseract OCR이나 `pytesseract`가 설치되어 있지 않아, 출구 번호는 OpenCV 템플릿 매칭으로 추정했습니다.

정교화 버전은 다음을 추가로 사용합니다.

- 역명 괄호 별칭 매칭: 예 `숭실대입구역` -> `숭실대입구(살피재)역`
- SHP에 있는 실제 출입구 번호 목록과 비교
- 중복 후보가 있으면 SHP 출입구 좌표와 가장 일관적인 affine 조합 선택
- OCR이 약하고 출구 번호가 1..N 연속이면 이미지상 각도 순서로 번호 fallback 배정

그래도 다음 오류가 섞일 수 있습니다.

- 노란 범례 박스를 출구 번호로 오인식
- 안내도 상단의 단면도 출구 번호를 실제 길찾기 도면 좌표로 오인식
- `1`, `7`, `11`처럼 모양이 비슷한 숫자 오인식
- 환승역 이미지에서 다른 호선/다른 층의 번호를 같은 역 출구로 오인식

따라서 이 파일들은 바로 실서비스 길찾기에 쓰기보다, 사람이 검수해서 `control_points`, `nodes`, `edges`를 확정하는 기준 자료로 사용해야 합니다.

## 파일 구조

각 JSON에는 다음 항목이 있습니다.

- `station_name`: 파일명 기준 정규화한 역명
- `line_no`: 이미지 폴더명 기준 호선
- `source_image`: 원본 이미지 경로
- `control_points`: 역 출입구 번호와 매칭된 것으로 추정한 좌표
- `nodes`: `control_points`에서 만든 출구 노드
- `edges`: 자동 생성하지 않음
- `detected_exit_labels`: 이미지에서 발견한 노란 번호 박스 후보 전체

## 다음 작업

길찾기에 사용하려면 역별로 다음을 검수해야 합니다.

1. `detected_exit_labels`에서 실제 출입구 번호 위치만 남깁니다.
2. `control_points`가 원본 이미지의 실제 출입구 위치와 맞는지 확인합니다.
3. 대합실, 승강장, 계단, 엘리베이터, 환승통로를 `nodes`로 추가합니다.
4. 실제 이동 가능한 연결만 `edges`로 작성합니다.
5. `build_indoor_map_v3.py --guide-annotations`로 그래프를 생성합니다.
