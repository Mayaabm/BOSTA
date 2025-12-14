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

            # Prefer explicit dataset route name (many files use 'route_name')
            route_name = props.get("route_name") or props.get("ref") or props.get("name")
            if not route_name:
                route_counter += 1
                route_name = f"{os.path.splitext(filename)[0]}_{route_counter}"

            route_desc = props.get("description") or ""
            # Try to find an existing route by (approximate) geometry match so we update its name
            route = None
            try:
                # First try exact geometry equality
                route = Route.objects.filter(geometry__equals=geom).first()
            except Exception:
                route = None

            if not route:
                # Fallback: find the closest existing route by distance
                closest = None
                min_dist = float('inf')
                for r in Route.objects.all():
                    try:
                        d = r.geometry.distance(geom)
                    except Exception:
                        d = float('inf')
                    if d < min_dist:
                        min_dist = d
                        closest = r
                # distance is in degrees; use a small threshold (about ~50 meters ~0.0005 degrees)
                if closest is not None and min_dist < 0.0005:
                    route = closest

            if route:
                # Ensure uniqueness: if desired name exists on another route, append suffix
                conflict = Route.objects.filter(name=route_name).exclude(pk=route.pk).exists()
                final_name = route_name if not conflict else f"{route_name}_{route.pk}"
                route.name = final_name
                route.description = route_desc
                route.geometry = geom
                # copy common metadata from properties if present
                route.operator = props.get("operator") or route.operator
                route.price = props.get("price") or route.price
                route.vehicle_type = props.get("vehicule_type") or route.vehicle_type
                route.save()
                print(f"   🔁 Updated existing route: {route.name}")
            else:
                # Create new route record
                final_name = route_name
                if Route.objects.filter(name=final_name).exists():
                    # ensure uniqueness
                    suffix = 1
                    while Route.objects.filter(name=f"{final_name}_{suffix}").exists():
                        suffix += 1
                    final_name = f"{final_name}_{suffix}"
                route = Route.objects.create(
                    name=final_name,
                    description=route_desc,
                    geometry=geom,
                    operator=props.get("operator"),
                    price=props.get("price"),
                    vehicle_type=props.get("vehicule_type"),
                )
                print(f"   ✅ Created route: {route.name}")

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
                # Determine stop order (ensure int)
                raw_order = props.get("order")
                if raw_order is None:
                    stop_order = route.stops.count() + 1 if route is not None else 1
                else:
                    try:
                        stop_order = int(raw_order)
                    except Exception:
                        stop_order = route.stops.count() + 1 if route is not None else 1

                # Prefer explicit stop name fields; fall back to 'ref' or generated name
                stop_name = None
                for key in ("name", "stop_name", "stop_name_en", "ref", "stop_ref", "title"):
                    v = props.get(key)
                    if v:
                        stop_name = str(v)
                        break
                if not stop_name:
                    stop_name = f"Stop {stop_order}"

                Stop.objects.get_or_create(
                    route=route,
                    order=stop_order,
                    defaults={"location": point, "name": stop_name},
                )
                print(f"   🧭 Linked stop to route '{route.name if route else 'None'}' as '{stop_name}' (order={stop_order})")
            except Exception as e:
                print(f"   ❌ Could not create stop for route '{route.name if route else 'None'}'. Error: {e}")

print("\n✅ Finished processing all files.")
