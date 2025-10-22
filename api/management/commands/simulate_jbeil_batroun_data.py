import time
import random
from datetime import datetime, timedelta
from django.core.management.base import BaseCommand
from django.contrib.gis.geos import Point, LineString
from django.utils import timezone
from api.models import Bus, VehiclePosition, Route, Trip


class Command(BaseCommand):
    help = "Simulates multiple buses moving around Jbeil and Batroun with live updates."

    def handle(self, *args, **options):
        self.stdout.write("🚌 Starting Jbeil–Batroun bus simulation...")
        simulation_interval_seconds = 5

        # Define route polylines (simplified)
        routes_data = [
            {
                "name": "Batroun Coastal Route",
                "coords": [
                    (35.6485, 34.1275),
                    (35.6500, 34.1250),
                    (35.6550, 34.1200),
                    (35.6600, 34.1150),
                    (35.6650, 34.1100),
                ],
            },
            {
                "name": "Batroun Inland Route",
                "coords": [
                    (35.6874, 34.1303),
                    (35.6820, 34.1255),
                    (35.6780, 34.1205),
                    (35.6740, 34.1155),
                    (35.6700, 34.1105),
                ],
            },
            {
                "name": "Jbeil Downtown Loop",
                "coords": [
                    (35.6489, 34.1216),
                    (35.6450, 34.1190),
                    (35.6400, 34.1150),
                    (35.6450, 34.1190),
                    (35.6489, 34.1216),
                ],
            },
            {
                "name": "Jbeil Coastal South",
                "coords": [
                    (35.6400, 34.1100),
                    (35.6420, 34.1070),
                    (35.6450, 34.1040),
                    (35.6480, 34.1010),
                    (35.6500, 34.0980),
                ],
            },
        ]

        buses = []

        for idx, route_data in enumerate(routes_data):
            route, _ = Route.objects.get_or_create(
                name=route_data["name"],
                defaults={"description": f"Simulated route around {route_data['name']}"}
            )
            polyline = [Point(lon, lat, srid=4326) for lon, lat in route_data["coords"]]
            route.geometry = LineString(polyline, srid=4326)
            route.save()

            bus, _ = Bus.objects.get_or_create(
                plate_number=f"SIM-{idx+1:03}",
                defaults={
                    "capacity": 40,
                    "speed_mps": random.uniform(6.0, 12.0),
                    "current_location": polyline[0],
                    "last_reported_at": timezone.now(),
                },
            )

            Trip.objects.get_or_create(
                bus=bus,
                route=route,
                defaults={
                    "departure_time": timezone.now() - timedelta(minutes=5),
                    "estimated_arrival_time": timezone.now() + timedelta(minutes=30),
                },
            )

            buses.append({"bus": bus, "polyline": polyline, "segment_idx": 0, "progress": 0.0})

        self.stdout.write(f"✅ {len(buses)} buses initialized. Starting simulation... (Ctrl+C to stop)")

        # Continuous simulation loop
        while True:
            try:
                for b in buses:
                    bus = b["bus"]
                    polyline = b["polyline"]
                    start = polyline[b["segment_idx"]]
                    end = polyline[(b["segment_idx"] + 1) % len(polyline)]

                    current_speed = random.uniform(6.0, 12.0)
                    distance = start.distance(end)
                    step = (current_speed * simulation_interval_seconds) / distance if distance > 0 else 1.0
                    b["progress"] += step

                    if b["progress"] >= 1.0:
                        b["segment_idx"] = (b["segment_idx"] + 1) % len(polyline)
                        b["progress"] -= 1.0

                    new_lon = start.x + b["progress"] * (end.x - start.x)
                    new_lat = start.y + b["progress"] * (end.y - start.y)
                    new_pos = Point(new_lon, new_lat, srid=4326)

                    # Update bus
                    bus.current_location = new_pos
                    bus.speed_mps = current_speed
                    bus.last_reported_at = timezone.now()
                    bus.save(update_fields=["current_location", "speed_mps", "last_reported_at"])

                    # Log a position record
                    VehiclePosition.objects.create(
                        bus=bus,
                        location=new_pos,
                        speed_mps=current_speed,
                        heading_deg=random.choice([0, 45, 90, 135, 180, 225, 270, 315]),
                        recorded_at=timezone.now(),
                    )

                    self.stdout.write(
                        f"🚌 {bus.plate_number} ({route_data['name']}) "
                        f"→ Lat:{new_lat:.5f}, Lon:{new_lon:.5f}, Speed:{current_speed*3.6:.1f} km/h"
                    )

                time.sleep(simulation_interval_seconds)

            except KeyboardInterrupt:
                self.stdout.write(self.style.WARNING("\n🛑 Simulation stopped manually."))
                break
            except Exception as e:
                self.stdout.write(self.style.ERROR(f"Error: {e}"))
                time.sleep(simulation_interval_seconds)
