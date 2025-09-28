import glob
import json
import os
import django
import sys

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "myproject.settings")
django.setup()

from api.models import Route, Location

# Folder containing all GeoJSON files


# Use recursive glob to include all .geojson files in subfolders, and filter only files
geojson_files = glob.glob(r"C:\Users\mayab\Downloads\mygeodata\ACTC Public Transportation\**\*.geojson", recursive=True)
geojson_files = [f for f in geojson_files if os.path.isfile(f)]
print(f"Found {len(geojson_files)} GeoJSON files.")


for file_path in geojson_files:
    print(f"Processing file: {file_path}")
    with open(file_path, encoding="utf-8") as f:
        data = json.load(f)

    print(f"  Found {len(data['features'])} features in file.")
    for feature in data["features"]:
        line_name = feature["properties"].get("Name")
        # Try to get stop name/description from properties, fallback to None
        stop_description = feature["properties"].get("description") or feature["properties"].get("name") or feature["properties"].get("Name")

        route_obj, created = Route.objects.get_or_create(name=line_name, defaults={"description": stop_description})
        if created:
            print(f"    Created new Route: {line_name}")
        else:
            print(f"    Found existing Route: {line_name}")

        geometry = feature["geometry"]
        coordinates = geometry["coordinates"]
        geom_type = geometry["type"]

        if geom_type == "LineString":
            for order, coord in enumerate(coordinates, start=1):
                longitude, latitude = coord[0], coord[1]
                # Try to get per-stop name/description if available (e.g., as a list in properties)
                per_stop_desc = None
                if "stops" in feature["properties"] and isinstance(feature["properties"]["stops"], list):
                    if order-1 < len(feature["properties"]["stops"]):
                        per_stop_desc = feature["properties"]["stops"][order-1].get("name") or feature["properties"]["stops"][order-1].get("description")
                Location.objects.create(
                    route=route_obj,
                    latitude=latitude,
                    longitude=longitude,
                    order=order,
                    description=per_stop_desc or stop_description
                )
            print(f"    Added {len(coordinates)} locations to Route: {line_name}")
        elif geom_type == "Point":
            longitude, latitude = coordinates[0], coordinates[1]
            Location.objects.create(
                route=route_obj,
                latitude=latitude,
                longitude=longitude,
                order=1,
                description=stop_description,
            )
            print(f"    Added 1 location to Route: {line_name}")
        else:
            print(f"    Skipped geometry type: {geom_type} for feature {line_name}")

print("All bus lines loaded successfully!")

