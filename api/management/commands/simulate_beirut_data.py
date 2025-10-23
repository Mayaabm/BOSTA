import time
import random
from datetime import datetime, timedelta
from django.core.management.base import BaseCommand
from django.contrib.gis.geos import Point, LineString
from django.utils import timezone
from api.models import Bus, VehiclePosition, Route, Trip


class Command(BaseCommand):
    help = "Simulates multiple buses moving around a specific location in Beirut."

    def handle(self, *args, **options):
        self.stdout.write("🚌 Starting Beirut bus simulation...")
        simulation_interval_seconds = 5

        # Central point provided by user
        center_lat = 33.8624512
        center_lon = 35.520512

        # Define a few small routes around the central point
        routes_data = [
            {
                "name": "Beirut Circle Line 1",
                "coords": [
                    (center_lon, center_lat),
                    (center_lon + 0.005, center_lat + 0.002),
                    (center_lon, center_lat + 0.004),
                    (center_lon - 0.005, center_lat + 0.002),
                    (center_lon, center_lat), # Loop back
                ],
            },
            {
                "name": "Beirut Cross Line 2",
                "coords": [
                    (center_lon - 0.01, center_lat - 0.005),
                    (center_lon + 0.01, center_lat + 0.005),
                ],
            },
        ]

        buses = []

        # Clear old simulated buses to avoid conflicts
        Bus.objects.filter(plate_number__startswith="SIM-BEY-").delete()

        for idx, route_data in enumerate(routes_data):
            route, _ = Route.objects.update_or_create(
                name=route_data["name"],
                defaults={"description": f"Simulated route in Beirut"}
            )
            polyline = [Point(lon, lat, srid=4326) for lon, lat in route_data["coords"]]
            route.geometry = LineString(polyline, srid=4326)
            route.save()

            bus, _ = Bus.objects.get_or_create(
                plate_number=f"SIM-BEY-{idx+1:03}",
                defaults={"capacity": 40},
            )

            Trip.objects.get_or_create(
                bus=bus, route=route,
                defaults={"departure_time": timezone.now()}
            )

            buses.append({"bus": bus, "polyline": polyline, "segment_idx": 0, "progress": 0.0, "forward": True})

        self.stdout.write(f"✅ {len(buses)} buses initialized for Beirut. Starting simulation... (Ctrl+C to stop)")

        while True:
            try:
                for b in buses:
                    bus, polyline = b["bus"], b["polyline"]
                    
                    current_idx = b["segment_idx"]
                    next_idx = (current_idx + 1) % len(polyline)

                    start, end = polyline[current_idx], polyline[next_idx]
                    
                    current_speed = random.uniform(8.0, 15.0) # ~30-55 km/h
                    distance = start.distance(end)
                    step = (current_speed * simulation_interval_seconds) / distance if distance > 0 else 1.0
                    b["progress"] += step

                    if b["progress"] >= 1.0:
                        b["segment_idx"] = next_idx
                        b["progress"] = 0.0
                        if b["segment_idx"] == 0: # Completed a loop
                            self.stdout.write(self.style.NOTICE(f"Bus {bus.plate_number} completed route, restarting."))

                    new_lon = start.x + b["progress"] * (end.x - start.x)
                    new_lat = start.y + b["progress"] * (end.y - start.y)
                    new_pos = Point(new_lon, new_lat, srid=4326)

                    bus.current_location = new_pos
                    bus.speed_mps = current_speed
                    bus.last_reported_at = timezone.now()
                    bus.save(update_fields=["current_location", "speed_mps", "last_reported_at"])

                    self.stdout.write(f"🚌 {bus.plate_number} -> Lat:{new_lat:.5f}, Lon:{new_lon:.5f}")

                time.sleep(simulation_interval_seconds)
            except KeyboardInterrupt:
                self.stdout.write(self.style.WARNING("\n🛑 Beirut simulation stopped manually."))
                break
            except Exception as e:
                self.stdout.write(self.style.ERROR(f"Error: {e}"))
                time.sleep(simulation_interval_seconds)
