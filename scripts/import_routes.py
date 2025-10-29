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

from api.models import Route, Stop
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

all_files = [f for f in os.listdir(ROUTES_FOLDER) if f.lower().endswith(".geojson")]

# --- PASS 1: Create all routes first ---
print("--- PASS 1: Processing all routes (LineStrings) ---")
for filename in all_files:
    path = os.path.join(ROUTES_FOLDER, filename)
    print(f"Scanning for routes in {filename}...")

    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    route_counter = 0
    for feature in data["features"]:
        props = feature.get("properties", {})
        geom = GEOSGeometry(json.dumps(feature["geometry"]))

        if geom.geom_type in ("LineString", "MultiLineString"):
            if geom.hasz:
                coords_2d = [[x, y] for x, y, *_ in geom.coords] if geom.geom_type == "LineString" else [[[x, y] for x, y, *_ in line.coords] for line in geom]
                geom_json = {"type": geom.geom_type, "coordinates": coords_2d}
                geom = GEOSGeometry(json.dumps(geom_json))

            route_name = props.get("ref") or props.get("name")
            if not route_name:
                route_counter += 1
                route_name = f"{os.path.splitext(filename)[0]}_{route_counter}"

            route_desc = props.get("description") or ""
            route, _ = Route.objects.update_or_create(
                name=route_name,
                defaults={"description": route_desc, "geometry": geom}
            )
            print(f"   ✅ Route saved: {route.name}")

print("\n--- PASS 2: Processing all stops (Points) ---")
for filename in all_files:
    path = os.path.join(ROUTES_FOLDER, filename)
    print(f"Scanning for stops in {filename}...")

    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    for feature in data["features"]:
        props = feature.get("properties", {})
        geom = GEOSGeometry(json.dumps(feature["geometry"]))

        if geom.geom_type == "Point":
            coords = geom.coords
            lon, lat = coords[0:2] if isinstance(coords, (list, tuple)) else coords
            point = Point(lon, lat, srid=4326)

            # Find the route this stop belongs to.
            # A stop might be in its own file (e.g., bus_stops.geojson) and needs to find a route
            # from another file (e.g., cleaned_bus_routes_1).
            # We need a reliable property to link them. Let's stick with 'ref' or 'name'.
            route_name_to_find = props.get("ref") or props.get("name")
            
            route = None
            if route_name_to_find:
                try:
                    route = Route.objects.get(name=route_name_to_find)
                except Route.DoesNotExist:
                    print(f"   ⚠️ Route '{route_name_to_find}' was specified but not found for stop at ({lon}, {lat}).")
            
            # If no route was found via properties, find the closest one
            if not route:
                closest_route = None
                min_dist = float('inf')
                for r in Route.objects.all():
                    dist = r.geometry.distance(point)
                    if dist < min_dist:
                        min_dist = dist
                        closest_route = r
                route = closest_route
                if route:
                    print(f"   ⚙️ No 'ref' or 'name' found. Assigning stop to closest route: '{route.name}' (distance: {min_dist:.2f}m)")
            
            try:
                stop_order = props.get("order", route.stops.count() + 1)
                Stop.objects.get_or_create(route=route, order=stop_order, defaults={"location": point})
                print(f"   🧭 Linked stop to route '{route.name}'")
            except Exception as e:
                print(f"   ❌ Could not create stop for route '{route.name if route else 'None'}'. Error: {e}")

print("\n✅ Finished processing all files.")
