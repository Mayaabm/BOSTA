import os
import re
import sys
import json
import glob
import unicodedata

# --- Django boot ---
# Adjust project root if this script lives in scripts/
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "myproject.settings")

import django
django.setup()

from api.models import Route, Location

# -------- Config ----------
# Folder where your uploaded .geojson live (adapt if you want absolute path)
# Windows absolute path (recursive):
DATA_GLOB = r"C:\Users\mayab\Downloads\mygeodata\ACTC Public Transportation\**\*.geojson"
# Or: DATA_GLOB = r"C:\Users\mayab\Downloads\mygeodata\ACTC Public Transportation\**\*.geojson"

# Do you want to also load every LineString vertex as a Location?
LOAD_LINES_AS_LOCATIONS = False   # default False to avoid huge inserts

# Deduplicate Locations per (route, lat, lon)
DEDUPLICATE_LOCATIONS = True

# -------- Helpers ---------

ROUTE_CODE_RE = re.compile(r'(ML\d+|B\d+)', re.IGNORECASE)

def normalize_text(s: str | None) -> str | None:
    if s is None:
        return None
    # Normalize unicode, collapse whitespace/newlines
    s = unicodedata.normalize("NFKC", s)
    s = s.replace('\u00a0', ' ')  # NBSP -> space
    s = re.sub(r'\s+', ' ', s).strip()
    return s

def extract_route_code_from_filename(path: str) -> str | None:
    fname = os.path.basename(path)
    m = ROUTE_CODE_RE.search(fname)
    if m:
        return m.group(1).upper()
    return None

def extract_route_code_from_feature_name(name: str | None) -> str | None:
    if not name:
        return None
    name = normalize_text(name)
    m = ROUTE_CODE_RE.search(name)
    if m:
        return m.group(1).upper()
    return None

def parse_stop_order(name: str | None, fallback_order: int) -> int:
    """
    Try to parse strings like 'B4-A12' → block A, number 12.
    We map blocks to 0,1000,2000… so A<n> come before B<n>.
    If we can't parse, use fallback_order.
    """
    if not name:
        return fallback_order
    name = normalize_text(name)

    # Find a trailing number (stop index)
    num_match = re.search(r'(\d+)\b', name)
    num = int(num_match.group(1)) if num_match else fallback_order

    # Find a block letter like '-A' or ' A ' etc.
    block_match = re.search(r'[-\s]([A-Z])\b', name, re.IGNORECASE)
    if block_match:
        block = block_match.group(1).upper()
        block_rank = (ord(block) - ord('A'))  # A=0, B=1, ...
        return block_rank * 1000 + num

    # No block letter; return number if found, else fallback
    return num

def create_or_get_route(route_code: str, description: str | None = None) -> Route:
    route, created = Route.objects.get_or_create(
        name=route_code,
        defaults={"description": normalize_text(description)}
    )
    # If route exists and has no description, fill it once
    if not created and not route.description and description:
        route.description = normalize_text(description)
        route.save(update_fields=["description"])
    return route

def add_location(route: Route, lat: float, lon: float, order: int, description: str | None):
    if DEDUPLICATE_LOCATIONS:
        exists = Location.objects.filter(
            route=route, latitude=lat, longitude=lon
        ).exists()
        if exists:
            return False

    Location.objects.create(
        route=route,
        latitude=lat,
        longitude=lon,
        order=order,
        description=normalize_text(description),
    )
    return True

# -------- Import logic ----------

def import_geojson_folder(glob_pattern: str):
    files = glob.glob(glob_pattern, recursive=True)
    files = [f for f in files if os.path.isfile(f)]
    print(f"Found {len(files)} GeoJSON files.")

    # First pass: ensure a Route exists for each file by filename code.
    routes_by_code: dict[str, Route] = {}
    for path in files:
        code = extract_route_code_from_filename(path)
        if not code:
            print(f"SKIP (no route code in filename): {path}")
            continue

        # Optionally peek header to get a nicer description (top-level "name")
        description = None
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
            description = normalize_text(data.get("name"))
        except Exception:
            pass

        route = create_or_get_route(code, description=description)
        routes_by_code[code] = route

    print(f"Ensured {len(routes_by_code)} routes exist (by filename).")

    # Second pass: traverse features; add LineString points (optional) and Point stops
    total_points = 0
    total_lines_vertices = 0
    for path in files:
        code_from_file = extract_route_code_from_filename(path)
        if not code_from_file or code_from_file not in routes_by_code:
            continue  # nothing to do

        route = routes_by_code[code_from_file]

        with open(path, encoding="utf-8") as f:
            data = json.load(f)

        features = data.get("features") or []
        # Keep a rolling fallback order counter in case a Point lacks A/Bx pattern or number
        fallback_order = 1

        print(f"Processing: {os.path.basename(path)} | route={route.name} | {len(features)} features")

        for feat in features:
            geom = feat.get("geometry") or {}
            props = feat.get("properties") or {}
            gtype = geom.get("type")

            # Choose the route code for this feature: prefer feature name, else filename
            feat_name = props.get("Name") or props.get("name")
            code_from_feat = extract_route_code_from_feature_name(feat_name)
            route_for_feat = routes_by_code.get(code_from_feat, route)

            if gtype == "Point":
                coords = geom.get("coordinates") or []
                if len(coords) < 2:
                    continue
                lon, lat = coords[0], coords[1]
                # Stop description: prefer explicit description, else Name
                stop_desc = props.get("description") or props.get("name") or props.get("Name")
                order = parse_stop_order(feat_name, fallback_order)
                success = add_location(route_for_feat, lat, lon, order, stop_desc)
                if success:
                    total_points += 1
                    fallback_order = max(fallback_order + 1, order + 1)

            elif gtype == "LineString":
                if not LOAD_LINES_AS_LOCATIONS:
                    continue
                coords = geom.get("coordinates") or []
                for idx, coord in enumerate(coords, start=1):
                    if len(coord) < 2:
                        continue
                    lon, lat = coord[0], coord[1]
                    add_location(route_for_feat, lat, lon, idx, None)
                    total_lines_vertices += 1

            elif gtype == "MultiLineString":
                if not LOAD_LINES_AS_LOCATIONS:
                    continue
                mls = geom.get("coordinates") or []
                idx = 1
                for line in mls:
                    for coord in line:
                        if len(coord) < 2:
                            continue
                        lon, lat = coord[0], coord[1]
                        add_location(route_for_feat, lat, lon, idx, None)
                        total_lines_vertices += 1
                        idx += 1
            else:
                # Not a Point/LineString/MultiLineString — ignore
                continue

    print(f"Done. Added {total_points} stop points"
          f"{' and ' + str(total_lines_vertices) + ' line vertices' if LOAD_LINES_AS_LOCATIONS else ''}.")
    print("All routes/stops loaded successfully.")

if __name__ == "__main__":
    import_geojson_folder(DATA_GLOB)
