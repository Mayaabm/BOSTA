import os
import sys
import django
import json

# --- Django setup ---
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(PROJECT_ROOT)  # go up one level (to folder with manage.py)
sys.path.append(PROJECT_ROOT)
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "myproject.settings")
django.setup()

from api.models import Route, Location
from django.contrib.gis.geos import GEOSGeometry, Point


ROUTES_FOLDER = r"C:\Users\mayab\.vscode\BOSTA\routes"

def extract_coords(geom):
    """Recursively extract all coordinates from LineString or MultiLineString"""
    if hasattr(geom, "coords"):
        return list(geom.coords)
    elif hasattr(geom, "geoms"):
        coords = []
        for g in geom.geoms:
            coords.extend(extract_coords(g))
        return coords
    return []

for filename in os.listdir(ROUTES_FOLDER):
    if not filename.lower().endswith(".geojson"):
        continue

    path = os.path.join(ROUTES_FOLDER, filename)
    print(f"Processing {filename}...")

    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    for feature in data["features"]:
        props = feature.get("properties", {})
        geom = GEOSGeometry(json.dumps(feature["geometry"]))

    if geom.hasz:
        print(f"   ⚙️  Geometry had Z values — converting to 2D.")
        if geom.geom_type == "LineString":
            coords_2d = [[x, y] for x, y, *_ in geom.coords]
            geom_json = {"type": "LineString", "coordinates": coords_2d}
            geom = GEOSGeometry(json.dumps(geom_json))
        elif geom.geom_type == "MultiLineString":
            coords_2d = [
                [[x, y] for x, y, *_ in line.coords]
                for line in geom
            ]
            geom_json = {"type": "MultiLineString", "coordinates": coords_2d}
            geom = GEOSGeometry(json.dumps(geom_json))



        print(f"   Feature geometry type: {geom.geom_type}")

        if geom.geom_type in ("LineString", "MultiLineString"):
            # --- Create or update Route ---
            route_name = props.get("name") or os.path.splitext(filename)[0]
            route_desc = props.get("description") or ""
            route, _ = Route.objects.get_or_create(
                name=route_name,
                defaults={"description": route_desc, "geometry": geom}
            )
            print(f"   ✅ Route saved: {route.name}")

        elif geom.geom_type == "Point":
    # Extract only longitude and latitude (ignore Z)
            coords = geom.coords
            lon, lat = coords[0:2] if isinstance(coords, (list, tuple)) else coords
            point = Point(lon, lat, srid=4326)

            print(f"   📍 Flattened point to 2D: ({lon}, {lat})")

            location, created = Location.objects.get_or_create(
                point=point,
                defaults={"description": props.get("name", "Unnamed stop")}
            )

            # Associate with routes if known
            route_name = props.get("route_name") or os.path.splitext(filename)[0]
            try:
                route = Route.objects.get(name=route_name)
                location.routes.add(route)
                print(f"   🧭 Linked stop to route: {route.name}")
            except Route.DoesNotExist:
                print(f"   ⚠️ Route {route_name} not found for point")

    print(f"✅ Finished {filename}")
