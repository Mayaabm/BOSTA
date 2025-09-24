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
geojson_files = glob.glob(r"C:\Users\mayab\Downloads\mygeodata\ACTC Public Transportation\*.geojson")

for file_path in geojson_files:
    with open(file_path) as f:
        data = json.load(f)
    
    for feature in data["features"]:
        line_name = feature["properties"]["Name"]
        description = feature["properties"].get("description")
        
        Route, created = Route.objects.get_or_create(name=line_name, defaults={"description": description})
        
        coordinates = feature["geometry"]["coordinates"]
        for order, coord in enumerate(coordinates, start=1):
            longitude, latitude = coord[0], coord[1]
            Location.objects.create(
                Route=Route,
                latitude=latitude,
                longitude=longitude,
                order=order
            )

print("All bus lines loaded successfully!")

