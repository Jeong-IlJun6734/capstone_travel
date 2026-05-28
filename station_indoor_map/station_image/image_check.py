import argparse
import ctypes
import json
import sys
from datetime import datetime
from pathlib import Path

import cv2
import numpy as np


NODE_KIND_SHORTCUTS = {
    "1": "hall",
    "2": "stairs_start",
    "3": "stairs_end",
    "4": "elevator",
    "5": "platform",
    "6": "entrance_connection",
    "7": "information",
}

FLOOR_SHORTCUTS = {
    "1": "ground",
    "2": "B1",
    "3": "B2",
    "4": "B3",
    "5": "B4",
}

COLORS = {
    "entrance_connection": (30, 170, 60),
    "hall": (30, 90, 220),
    "stairs_start": (20, 120, 220),
    "stairs_end": (20, 80, 180),
    "elevator": (180, 80, 30),
    "platform": (170, 40, 150),
    "information": (80, 80, 80),
}


def read_image(path: Path):
    img_array = np.fromfile(str(path), np.uint8)
    img = cv2.imdecode(img_array, cv2.IMREAD_COLOR)
    if img is None:
        raise FileNotFoundError(f"이미지를 읽을 수 없습니다: {path}")
    return img


def infer_line_and_station(image_path: Path):
    line_no = image_path.parent.name
    station_name = image_path.stem
    return line_no, station_name


def default_output_path(image_path: Path, output_dir: Path) -> Path:
    line_no, station_name = infer_line_and_station(image_path)
    return output_dir / f"{line_no}_{station_name}.json"


def is_key_down_windows(vk_code: int) -> bool:
    if sys.platform != "win32":
        return False
    return bool(ctypes.windll.user32.GetAsyncKeyState(vk_code) & 0x8000)


def point_xy(point):
    return point["image_xy"]


def make_annotation(image_path: Path, img, points, edges):
    line_no, station_name = infer_line_and_station(image_path)
    nodes = []
    for idx, point in enumerate(points, start=1):
        node = {
            "id": f"node_{idx:03d}",
            "kind": point["kind"],
            "click_index": idx,
            "image_xy": [int(point_xy(point)[0]), int(point_xy(point)[1])],
        }
        if point.get("floor"):
            node["floor"] = point["floor"]
        if point.get("entrance_no"):
            node["entrance_no"] = point["entrance_no"]
        nodes.append(node)

    annotation_edges = []
    for from_idx, to_idx in edges:
        if 0 <= from_idx < len(nodes) and 0 <= to_idx < len(nodes):
            annotation_edges.append({
                "from": nodes[from_idx]["id"],
                "to": nodes[to_idx]["id"],
                "kind": "walk",
            })

    return {
        "station_name": station_name,
        "line_no": line_no,
        "source_image": str(image_path.as_posix()),
        "image_width": int(img.shape[1]),
        "image_height": int(img.shape[0]),
        "annotation_status": "clicked_draft",
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "note": "Created from clicked image coordinates using station_image/image_check.py. Review node labels, floors, and edges before routing.",
        "nodes": nodes,
        "edges": annotation_edges,
    }


def save_annotation(output_path: Path, annotation: dict):
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(annotation, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def nearest_point_index(points, original_x, original_y, max_distance_px=35):
    if not points:
        return None
    distances = [
        ((px - original_x) ** 2 + (py - original_y) ** 2, idx)
        for idx, point in enumerate(points)
        for px, py in [point_xy(point)]
    ]
    dist_sq, idx = min(distances)
    if dist_sq <= max_distance_px * max_distance_px:
        return idx
    return None


def point_to_segment_distance_sq(px, py, ax, ay, bx, by):
    segment_dx = bx - ax
    segment_dy = by - ay
    segment_length_sq = segment_dx * segment_dx + segment_dy * segment_dy
    if segment_length_sq == 0:
        return (px - ax) ** 2 + (py - ay) ** 2

    offset_ratio = ((px - ax) * segment_dx + (py - ay) * segment_dy) / segment_length_sq
    offset_ratio = min(max(offset_ratio, 0.0), 1.0)
    nearest_x = ax + offset_ratio * segment_dx
    nearest_y = ay + offset_ratio * segment_dy
    return (px - nearest_x) ** 2 + (py - nearest_y) ** 2


def nearest_edge_index(points, edges, original_x, original_y, max_distance_px=24):
    candidates = []
    for idx, (from_idx, to_idx) in enumerate(edges):
        if from_idx >= len(points) or to_idx >= len(points):
            continue
        start_x, start_y = point_xy(points[from_idx])
        end_x, end_y = point_xy(points[to_idx])
        candidates.append(
            (
                point_to_segment_distance_sq(
                    original_x,
                    original_y,
                    start_x,
                    start_y,
                    end_x,
                    end_y,
                ),
                idx,
            )
        )
    if not candidates:
        return None

    dist_sq, idx = min(candidates)
    if dist_sq <= max_distance_px * max_distance_px:
        return idx
    return None


def remove_point_and_edges(points, edges, removed_idx):
    removed = points.pop(removed_idx)
    remaining_edges = []
    removed_edge_count = 0
    for from_idx, to_idx in edges:
        if from_idx == removed_idx or to_idx == removed_idx:
            removed_edge_count += 1
            continue
        remaining_edges.append(
            (
                from_idx - 1 if from_idx > removed_idx else from_idx,
                to_idx - 1 if to_idx > removed_idx else to_idx,
            )
        )
    edges[:] = remaining_edges
    return removed, removed_edge_count


MIN_ZOOM = 1.0
MAX_ZOOM = 12.0
ZOOM_FACTOR = 1.25


def clamp_view_origin(origin_x, origin_y, view_w, view_h, image_w, image_h):
    max_x = max(float(image_w) - view_w, 0.0)
    max_y = max(float(image_h) - view_h, 0.0)
    return min(max(origin_x, 0.0), max_x), min(max(origin_y, 0.0), max_y)


def view_size(display_w, display_h, scale):
    return display_w / scale, display_h / scale


def mouse_wheel_delta(flags):
    if hasattr(cv2, "getMouseWheelDelta"):
        return cv2.getMouseWheelDelta(flags)

    delta = (flags >> 16) & 0xFFFF
    return delta - 0x10000 if delta & 0x8000 else delta


def render_view(img, display_w, display_h, scale, origin_x, origin_y):
    image_h, image_w = img.shape[:2]
    crop_w, crop_h = view_size(display_w, display_h, scale)
    end_x = min(int(np.ceil(origin_x + crop_w)), image_w)
    end_y = min(int(np.ceil(origin_y + crop_h)), image_h)
    crop = img[int(origin_y):end_y, int(origin_x):end_x]
    interpolation = cv2.INTER_LINEAR if scale > 1.0 else cv2.INTER_AREA
    return cv2.resize(crop, (display_w, display_h), interpolation=interpolation)


def draw_overlay(
    display_img,
    points,
    edges,
    scale,
    origin_x=0.0,
    origin_y=0.0,
    edge_mode=False,
    delete_mode=False,
    selected_idx=None,
    current_kind="hall",
    current_floor=None,
    floor_shortcut_pending=False,
):
    canvas = display_img.copy()
    for from_idx, to_idx in edges:
        if from_idx >= len(points) or to_idx >= len(points):
            continue
        start_x, start_y = point_xy(points[from_idx])
        end_x, end_y = point_xy(points[to_idx])
        x1 = int((start_x - origin_x) * scale)
        y1 = int((start_y - origin_y) * scale)
        x2 = int((end_x - origin_x) * scale)
        y2 = int((end_y - origin_y) * scale)
        cv2.line(canvas, (x1, y1), (x2, y2), (255, 0, 0), 2, cv2.LINE_AA)

    for idx, point in enumerate(points, start=1):
        original_x, original_y = point_xy(point)
        x = int((original_x - origin_x) * scale)
        y = int((original_y - origin_y) * scale)
        color = COLORS.get(point["kind"], (0, 0, 255))
        cv2.circle(canvas, (x, y), 6, color, -1, cv2.LINE_AA)
        cv2.circle(canvas, (x, y), 8, (255, 255, 255), 1, cv2.LINE_AA)
        label = f"{idx}:{point['kind']}"
        if point.get("entrance_no"):
            label = f"{label} exit {point['entrance_no']}"
        cv2.putText(
            canvas,
            label,
            (x + 7, y - 7),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.45,
            color,
            2,
            cv2.LINE_AA,
        )
    if delete_mode:
        mode_text = "DELETE MODE"
        click_text = "L-click:delete node/edge"
    elif edge_mode:
        mode_text = "EDGE MODE"
        click_text = "L-click:select"
    else:
        mode_text = "NODE MODE"
        click_text = "L-click:add"
    help_text = f"{mode_text}  {click_text}  +/-:zoom  arrows/IJKL:pan  0:reset  S:save"
    floor_text = current_floor or "-"
    select_text = "FLOOR HOTKEY: press 1-5" if floor_shortcut_pending else f"TYPE {current_kind}  FLOOR {floor_text}"
    cv2.rectangle(canvas, (10, 10), (960, 72), (255, 255, 255), -1)
    cv2.putText(
        canvas,
        help_text,
        (18, 33),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.65,
        (20, 20, 20),
        2,
        cv2.LINE_AA,
    )
    cv2.putText(
        canvas,
        select_text,
        (18, 60),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.58,
        COLORS.get(current_kind, (20, 20, 20)),
        2,
        cv2.LINE_AA,
    )
    if selected_idx is not None and selected_idx < len(points):
        selected_x, selected_y = point_xy(points[selected_idx])
        x = int((selected_x - origin_x) * scale)
        y = int((selected_y - origin_y) * scale)
        cv2.circle(canvas, (x, y), 11, (0, 255, 255), 3, cv2.LINE_AA)
    return canvas


def main():
    parser = argparse.ArgumentParser(description="Click image coordinates and save them as an annotation JSON.")
    parser.add_argument("--image", required=True, help="Image path to open, e.g. station_image/7/장승배기.jpg")
    parser.add_argument("--output-dir", default="annotations/clicked", help="Directory for auto-named annotation JSON.")
    parser.add_argument("--output", help="Optional explicit output JSON path.")
    parser.add_argument("--floor", help="Optional initial floor for clicked nodes, e.g. B2.")
    parser.add_argument("--max-width", type=int, default=1960)
    parser.add_argument("--max-height", type=int, default=1080)
    args = parser.parse_args()

    image_path = Path(args.image)
    output_path = Path(args.output) if args.output else default_output_path(image_path, Path(args.output_dir))

    img = read_image(image_path)
    h, w = img.shape[:2]
    base_scale = min(args.max_width / w, args.max_height / h, 1.0)
    display_w = int(w * base_scale)
    display_h = int(h * base_scale)
    zoom = MIN_ZOOM
    origin_x = 0.0
    origin_y = 0.0

    points: list[dict] = []
    edges: list[tuple[int, int]] = []
    edge_mode = False
    delete_mode = False
    selected_idx = None
    current_kind = "hall"
    current_floor = args.floor
    floor_shortcut_pending = False
    window_name = f"image_check: {image_path.name}"

    def refresh():
        scale = base_scale * zoom
        display_img = render_view(img, display_w, display_h, scale, origin_x, origin_y)
        cv2.imshow(
            window_name,
            draw_overlay(
                display_img,
                points,
                edges,
                scale,
                origin_x,
                origin_y,
                edge_mode,
                delete_mode,
                selected_idx,
                current_kind,
                current_floor,
                floor_shortcut_pending,
            ),
        )

    def set_zoom(next_zoom, anchor_x=None, anchor_y=None):
        nonlocal zoom, origin_x, origin_y
        next_zoom = min(max(next_zoom, MIN_ZOOM), MAX_ZOOM)
        if next_zoom == zoom:
            return

        old_scale = base_scale * zoom
        new_scale = base_scale * next_zoom
        if anchor_x is None or anchor_y is None:
            anchor_x = display_w / 2
            anchor_y = display_h / 2

        original_x = origin_x + anchor_x / old_scale
        original_y = origin_y + anchor_y / old_scale
        zoom = next_zoom
        next_view_w, next_view_h = view_size(display_w, display_h, new_scale)
        origin_x, origin_y = clamp_view_origin(
            original_x - anchor_x / new_scale,
            original_y - anchor_y / new_scale,
            next_view_w,
            next_view_h,
            w,
            h,
        )
        print(f"[VIEW] zoom={zoom:.2f}x")
        refresh()

    def pan(dx, dy):
        nonlocal origin_x, origin_y
        scale = base_scale * zoom
        crop_w, crop_h = view_size(display_w, display_h, scale)
        origin_x, origin_y = clamp_view_origin(origin_x + dx, origin_y + dy, crop_w, crop_h, w, h)
        refresh()

    def reset_view():
        nonlocal zoom, origin_x, origin_y
        zoom = MIN_ZOOM
        origin_x = 0.0
        origin_y = 0.0
        print("[VIEW] reset")
        refresh()

    def save_current():
        annotation = make_annotation(image_path, img, points, edges)
        save_annotation(output_path, annotation)
        print(f"[SAVE] {output_path} nodes={len(annotation['nodes'])}, edges={len(annotation['edges'])}")

    def new_point(original_x, original_y):
        point = {
            "kind": current_kind,
            "floor": current_floor,
            "image_xy": (original_x, original_y),
        }
        if current_kind == "entrance_connection":
            entrance_no = input("[ENTRANCE] exit number: ").strip()
            if not entrance_no:
                print("[ENTRANCE] canceled: exit number is required")
                return None
            point["entrance_no"] = entrance_no
        return point

    def connect_last_two():
        if len(points) < 2:
            print("[EDGE] 연결할 노드가 2개 이상 필요합니다.")
            return
        edge = (len(points) - 2, len(points) - 1)
        reverse_edge = (edge[1], edge[0])
        if edge in edges or reverse_edge in edges:
            print(f"[EDGE] 이미 연결됨: node_{edge[0] + 1:03d}->node_{edge[1] + 1:03d}")
            return
        edges.append(edge)
        print(f"[EDGE] node_{edge[0] + 1:03d}->node_{edge[1] + 1:03d}")
        refresh()

    def add_edge_by_indices(from_idx, to_idx):
        if from_idx == to_idx:
            print("[EDGE] 같은 노드는 연결하지 않습니다.")
            return
        edge = (from_idx, to_idx)
        reverse_edge = (to_idx, from_idx)
        if edge in edges or reverse_edge in edges:
            print(f"[EDGE] 이미 연결됨: node_{from_idx + 1:03d}->node_{to_idx + 1:03d}")
            return
        edges.append(edge)
        print(f"[EDGE] node_{from_idx + 1:03d}->node_{to_idx + 1:03d}")

    def mouse_callback(event, x, y, flags, param):
        nonlocal selected_idx
        if event == cv2.EVENT_MOUSEWHEEL:
            wheel_delta = mouse_wheel_delta(flags)
            if wheel_delta == 0:
                return
            set_zoom(zoom * ZOOM_FACTOR if wheel_delta > 0 else zoom / ZOOM_FACTOR, x, y)
            return
        if event == cv2.EVENT_LBUTTONDOWN:
            scale = base_scale * zoom
            original_x = int(round(origin_x + x / scale))
            original_y = int(round(origin_y + y / scale))
            if delete_mode:
                clicked_idx = nearest_point_index(points, original_x, original_y)
                if clicked_idx is not None:
                    removed, removed_edge_count = remove_point_and_edges(points, edges, clicked_idx)
                    removed_x, removed_y = point_xy(removed)
                    print(
                        f"[DELETE] node_{clicked_idx + 1:03d} kind={removed['kind']} "
                        f"x={removed_x}, y={removed_y}, edges={removed_edge_count}"
                    )
                    refresh()
                    return

                clicked_edge_idx = nearest_edge_index(points, edges, original_x, original_y)
                if clicked_edge_idx is not None:
                    from_idx, to_idx = edges.pop(clicked_edge_idx)
                    print(f"[DELETE] edge node_{from_idx + 1:03d}->node_{to_idx + 1:03d}")
                else:
                    print("[DELETE] no nearby node or edge")
                refresh()
                return

            if edge_mode:
                clicked_idx = nearest_point_index(points, original_x, original_y)
                if clicked_idx is None:
                    print("[EDGE] 가까운 노드를 찾지 못했습니다.")
                    refresh()
                    return
                if selected_idx is None:
                    selected_idx = clicked_idx
                    print(f"[EDGE] 시작 노드 선택: node_{selected_idx + 1:03d}")
                else:
                    add_edge_by_indices(selected_idx, clicked_idx)
                    selected_idx = None
                refresh()
                return

            connect_from_previous = is_key_down_windows(ord("E"))
            previous_idx = len(points) - 1
            point = new_point(original_x, original_y)
            if point is None:
                refresh()
                return
            points.append(point)
            current_idx = len(points) - 1
            if connect_from_previous and previous_idx >= 0:
                edges.append((previous_idx, current_idx))
                print(f"원본 좌표: x={original_x}, y={original_y}  edge: node_{previous_idx + 1:03d}->node_{current_idx + 1:03d}")
            else:
                print(f"원본 좌표: x={original_x}, y={original_y}")
            refresh()
        elif event == cv2.EVENT_RBUTTONDOWN and points:
            removed_idx = len(points) - 1
            removed, _ = remove_point_and_edges(points, edges, removed_idx)
            if selected_idx == removed_idx:
                selected_idx = None
            removed_x, removed_y = point_xy(removed)
            print(f"[UNDO] kind={removed['kind']} x={removed_x}, y={removed_y}")
            refresh()

    print(f"[IMAGE] {image_path}")
    print(f"[OUTPUT] {output_path}")
    print("[KEYS] left-click add node, hold e + left-click add and connect, e connect last two nodes, a toggle edge mode, d toggle delete mode, right-click/backspace undo, s save, c clear, q/esc quit")
    print("[TYPE] 1 hall, 2 stairs_start, 3 stairs_end, 4 elevator, 5 platform, 6 entrance_connection, 7 information")
    print("[FLOOR] press f then 1 ground, 2 B1, 3 B2, 4 B3, 5 B4")
    print("[VIEW] mouse wheel or +/- zoom, arrows/IJKL pan, 0 reset view")

    cv2.imshow(window_name, render_view(img, display_w, display_h, base_scale, origin_x, origin_y))
    cv2.setMouseCallback(window_name, mouse_callback)
    refresh()

    while True:
        key = cv2.waitKeyEx(0)
        key_char = chr(key) if 0 <= key < 256 else ""
        if key in (ord("q"), 27):
            break
        if floor_shortcut_pending and key_char in FLOOR_SHORTCUTS:
            current_floor = FLOOR_SHORTCUTS[key_char]
            floor_shortcut_pending = False
            print(f"[FLOOR] {current_floor}")
            refresh()
            continue
        if floor_shortcut_pending:
            floor_shortcut_pending = False
            print("[FLOOR] selection canceled")
            refresh()
        if key in (ord("s"), ord("S")):
            save_current()
        elif key in (ord("a"), ord("A")):
            edge_mode = not edge_mode
            delete_mode = False
            selected_idx = None
            print(f"[MODE] {'edge' if edge_mode else 'node'}")
            refresh()
        elif key in (ord("d"), ord("D")):
            delete_mode = not delete_mode
            edge_mode = False
            selected_idx = None
            print(f"[MODE] {'delete' if delete_mode else 'node'}")
            refresh()
        elif key in (ord("e"), ord("E")):
            connect_last_two()
        elif key in (ord("c"), ord("C")):
            points.clear()
            edges.clear()
            selected_idx = None
            print("[CLEAR]")
            refresh()
        elif key in (8, 127) and points:
            removed_idx = len(points) - 1
            removed, _ = remove_point_and_edges(points, edges, removed_idx)
            if selected_idx == removed_idx:
                selected_idx = None
            removed_x, removed_y = point_xy(removed)
            print(f"[UNDO] kind={removed['kind']} x={removed_x}, y={removed_y}")
            refresh()
        elif key_char in NODE_KIND_SHORTCUTS:
            current_kind = NODE_KIND_SHORTCUTS[key_char]
            print(f"[TYPE] {current_kind}")
            refresh()
        elif key in (ord("f"), ord("F")):
            floor_shortcut_pending = True
            print("[FLOOR] press 1 ground, 2 B1, 3 B2, 4 B3, or 5 B4")
            refresh()
        elif key in (ord("+"), ord("=")):
            set_zoom(zoom * ZOOM_FACTOR)
        elif key in (ord("-"), ord("_")):
            set_zoom(zoom / ZOOM_FACTOR)
        elif key in (ord("0"),):
            reset_view()
        elif key in (ord("i"), ord("I"), 2490368):
            pan(0, -view_size(display_w, display_h, base_scale * zoom)[1] * 0.15)
        elif key in (ord("k"), ord("K"), 2621440):
            pan(0, view_size(display_w, display_h, base_scale * zoom)[1] * 0.15)
        elif key in (ord("j"), ord("J"), 2424832):
            pan(-view_size(display_w, display_h, base_scale * zoom)[0] * 0.15, 0)
        elif key in (ord("l"), ord("L"), 2555904):
            pan(view_size(display_w, display_h, base_scale * zoom)[0] * 0.15, 0)

    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
