from django.core.management.base import BaseCommand
from django.contrib.gis.geos import Point, LineString
from api.models import Route, Stop, Bus, VehiclePosition, Trip
from datetime import datetime, timedelta
import random


class Command(BaseCommand):
    help = "Load sample routes, locations, and buses around Batroun & Beirut for testing."

    def handle(self, *args, **options):
        self.stdout.write("🧪 Loading sample data for Batroun and Beirut...")

        # Clear existing data
        VehiclePosition.objects.all().delete()
        Trip.objects.all().delete()
        Bus.objects.all().delete()
        Stop.objects.all().delete()
        Route.objects.all().delete()

        # Two test areas (Batroun + Beirut)
        test_areas = [
            {"name": "Batroun", "lat": 34.148448, "lon": 35.6547228},
            {"name": "Beirut", "lat": 33.8624512, "lon": 35.5663872},
        ]

        for area in test_areas:
            self.stdout.write(f"📍 Creating sample routes near {area['name']}...")

            for route_idx, route_name in enumerate(["B1", "B2", "B3"]):
                route = Route.objects.create(
                    name=f"{area['name']}-{route_name}",
                    description=f"Route {route_name} near {area['name']}"
                )

                # Create 5 stops for the route
                points = []
                for i in range(5):
                    lon = area["lon"] + (i * 0.003) + (route_idx * 0.002)
                    lat = area["lat"] + (i * 0.002) - (route_idx * 0.001)
                    point = Point(lon, lat, srid=4326)
                    Stop.objects.create(
                        route=route,
                        order=i + 1,
                        location=point,
                    )
                    points.append(point)

                # Save the route geometry
                route.geometry = LineString(points, srid=4326)
                route.save()

                # Create one bus per route
                bus = Bus.objects.create(
                    plate_number=f"{area['name'][:3].upper()}-{route_idx+1:03}",
                    capacity=40,
                    speed_mps=random.uniform(6.0, 12.0), # This will be the current speed
                    current_location=points[0], # Set initial location to the first stop
                    last_reported_at=datetime.now(),
                )

                # Create a trip for this bus
                trip = Trip.objects.create(
                    bus=bus,
                    route=route,
                    departure_time=datetime.now() - timedelta(minutes=10),
                    current_stop=None,
                    estimated_arrival_time=datetime.now() + timedelta(minutes=30)
                )

                # Create 3 recent GPS positions near the base area
                for j in range(3):
                    offset_lat = random.uniform(-0.002, 0.002)
                    offset_lon = random.uniform(-0.002, 0.002)
                    VehiclePosition.objects.create(
                        bus=bus,
                        location=Point(
                            area["lon"] + offset_lon,
                            area["lat"] + offset_lat,
                            srid=4326
                        ),
                        recorded_at=datetime.now() - timedelta(minutes=j),
                        speed_mps=bus.speed_mps,
                        heading_deg=random.choice([45.0, 90.0, 135.0, 180.0])
                    )

        self.stdout.write(self.style.SUCCESS("✅ Sample data for Batroun & Beirut loaded successfully!"))
