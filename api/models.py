# api/models.py
from django.contrib.gis.db import models  # this is key

class Bus(models.Model):
    plate_number = models.CharField(max_length=20, unique=True, db_index=True)
    capacity = models.IntegerField()
    speed_mps = models.FloatField(default=0.0)  # store m/s for math

    def __str__(self):
        return self.plate_number


class Route(models.Model):
    name = models.CharField(max_length=100, unique=True)
    description = models.TextField(blank=True)
    geometry = models.LineStringField(srid=4326, null=True, blank=True)

    def __str__(self):
        return self.name


class Location(models.Model):
    point = models.PointField(srid=4326)
    description = models.CharField(max_length=255, blank=True)
    routes = models.ManyToManyField(Route, related_name="locations", blank=True)

    class Meta:
        unique_together = ('point',)

    def __str__(self):
        return self.description or f"Location {self.id}"




class Trip(models.Model):
    bus = models.ForeignKey(Bus, on_delete=models.CASCADE, related_name='trips')
    route = models.ForeignKey(Route, on_delete=models.CASCADE, related_name='trips')
    departure_time = models.DateTimeField()
    current_location = models.ForeignKey(Location, on_delete=models.SET_NULL, null=True, blank=True)
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
