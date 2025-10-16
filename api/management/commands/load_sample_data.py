from django.core.management.base import BaseCommand
from django.contrib.gis.geos import Point, LineString
from api.models import Route, Location, Bus, VehiclePosition, Trip
from datetime import datetime, timedelta

class Command(BaseCommand):
    help = "Load sample routes, locations, buses, and positions for testing."

    def handle(self, *args, **options):
        self.stdout.write("🧪 Loading sample data...")

        VehiclePosition.objects.all().delete()
        Trip.objects.all().delete()
        Bus.objects.all().delete()
        Location.objects.all().delete()
        Route.objects.all().delete()

        routes = []
        for name in ["B1", "B2", "B3"]:
            route = Route.objects.create(
                name=name,
                description=f"Route {name} — sample route"
            )
            routes.append(route)

        # Create locations and build route geometries
        for route_idx, route in enumerate(routes):
            points = []
            for i in range(5):
                lon = 35.5 + i * 0.005
                lat = 33.9 + route_idx * 0.005 + i * 0.002
                point = Point(lon, lat)
                location, _ = Location.objects.get_or_create(
                    point=point,
                    defaults={"description": f"Stop {i+1} on {route.name}"}
                )
                location.routes.add(route)
                points.append(point)

            # ✅ Build LineString for route.geometry
            route.geometry = LineString(points, srid=4326)
            route.save()

        # Create buses and assign them to trips on each route
        for i, route in enumerate(routes):
            bus = Bus.objects.create(
                plate_number=f"TEST-{i+1:03}",
                capacity=40,
                speed_mps=10.0
            )

            # Create a trip for this bus and route
            trip = Trip.objects.create(
                bus=bus,
                route=route,
                departure_time=datetime.now() - timedelta(minutes=10),
                current_location=None,
                estimated_arrival_time=datetime.now() + timedelta(minutes=30)
            )

            # Create some recent GPS points for the bus
            for j in range(3):
                VehiclePosition.objects.create(
                    bus=bus,
                    location=Point(
                        35.5 + i * 0.01 + j * 0.001,
                        33.9 + i * 0.01 + j * 0.001,
                        srid=4326
                    ),
                    recorded_at=datetime.now() - timedelta(minutes=j),
                    speed_mps=bus.speed_mps,
                    heading_deg=90.0
                )

        self.stdout.write(self.style.SUCCESS("✅ Sample data loaded successfully!"))
