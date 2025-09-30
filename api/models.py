import os
import django


os.environ.setdefault("DJANGO_SETTINGS_MODULE", "myproject.settings")


from django.contrib.auth.models import User



from django.db import models
from django.contrib.auth.models import User


from django.db import models

# api/models.py
from django.db import models

class Bus(models.Model):
    Bus_ID = models.AutoField(primary_key=True, db_column='Bus_ID')
    plate_number = models.CharField(max_length=20, unique=True)
    capacity = models.IntegerField()
    current_location = models.CharField(max_length=100, blank=True)
    current_lat = models.FloatField(null=True, blank=True)
    current_lon = models.FloatField(null=True, blank=True)
    speed = models.FloatField(default=0.0)


class Route(models.Model):
    id = models.AutoField(primary_key=True)
    name = models.CharField(max_length=100, unique=True)
    description = models.TextField(null=True, blank=True)

class Location(models.Model):
    id = models.AutoField(primary_key=True)
    route = models.ForeignKey(Route, on_delete=models.CASCADE, related_name='stops')
    latitude = models.FloatField()
    longitude = models.FloatField()
    order = models.IntegerField()
    description = models.CharField(max_length=255, null=True, blank=True)
    cum_km = models.FloatField(default=0.0)

    class Meta:
        unique_together = ('route', 'order')
        ordering = ['route', 'order']

class Trip(models.Model):
    id = models.AutoField(primary_key=True)
    bus = models.ForeignKey(Bus, on_delete=models.CASCADE)  # still targets Bus.Bus_ID (PK)
    route = models.ForeignKey(Route, on_delete=models.CASCADE)
    departure_time = models.DateTimeField()
    current_location = models.ForeignKey(Location, on_delete=models.SET_NULL, null=True, blank=True)
    estimated_arrival_time = models.DateTimeField()




class Passenger(models.Model):
    id = models.AutoField(primary_key=True)  # Explicit PK
    current_location = models.ForeignKey(
        Location,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='waiting_passengers'
    )  # FK → Location
    destination = models.ForeignKey(
        Location,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='destination_passengers'
    )  # FK → Location

    def __str__(self):
        return f"Passenger {self.id}"
