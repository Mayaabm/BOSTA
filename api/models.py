# api/models.py
from django.contrib.gis.db import models  # this is key
from django.contrib.auth.models import User


class CustomUserProfile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name="profile")
    current_location = models.PointField(srid=4326, null=True, blank=True)
    destination = models.PointField(srid=4326, null=True, blank=True)
    is_driver = models.BooleanField(default=False)
    is_commuter = models.BooleanField(default=True)

    def __str__(self):
        return f"Profile for {self.user.username}"


class Bus(models.Model):
    plate_number = models.CharField(max_length=20, unique=True, db_index=True)
    capacity = models.IntegerField()
    speed_mps = models.FloatField(default=0.0)  # Current speed in m/s
    driver = models.ForeignKey('CustomUserProfile', on_delete=models.SET_NULL, null=True, blank=True, related_name='bus_driven')
    current_location = models.PointField(srid=4326, null=True, blank=True)
    last_reported_at = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return self.plate_number


class Route(models.Model):
    name = models.CharField(max_length=255, unique=True, help_text="Name of the bus route")
    description = models.TextField(blank=True, help_text="A short description of the route")
    geometry = models.LineStringField(srid=4326, help_text="The geographical path of the route")
    operator = models.CharField(max_length=100, blank=True, null=True)
    price = models.CharField(max_length=50, blank=True, null=True)
    vehicle_type = models.CharField(max_length=100, blank=True, null=True)

    def __str__(self):
        return self.name


class Stop(models.Model):
    route = models.ForeignKey(Route, related_name='stops', on_delete=models.CASCADE)
    order = models.IntegerField(help_text="The order of the stop along the route")
    location = models.PointField(srid=4326, help_text="The geographical location of the stop")

    class Meta:
        ordering = ['route', 'order']

    def __str__(self):
        return f"Stop {self.order} on {self.route.name}"


class Trip(models.Model):
    bus = models.ForeignKey(Bus, on_delete=models.CASCADE, related_name='trips')
    route = models.ForeignKey(Route, on_delete=models.CASCADE, related_name='trips')
    departure_time = models.DateTimeField()
    current_stop = models.ForeignKey(Stop, on_delete=models.SET_NULL, null=True, blank=True)
    estimated_arrival_time = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f"{self.bus} on {self.route} ({self.departure_time})"



class VehiclePosition(models.Model):
    bus = models.ForeignKey(Bus, on_delete=models.CASCADE, related_name='positions')
    location = models.PointField(geography=True)
    heading_deg = models.FloatField(null=True, blank=True)
    speed_mps = models.FloatField(null=True, blank=True)
    recorded_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        indexes = [
            models.Index(fields=['bus', 'recorded_at']),
        ]

    def __str__(self):
        return f"{self.bus.plate_number} @ {self.recorded_at}"