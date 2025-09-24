import os
import django


os.environ.setdefault("DJANGO_SETTINGS_MODULE", "myproject.settings")


from django.contrib.auth.models import User



from django.db import models
from django.contrib.auth.models import User

class Bus(models.Model):
 Bus_ID=models.AutoField(primary_key=True)
 plate_number = models.CharField(max_length=20, unique=True)
 capacity = models.IntegerField()
 current_location = models.CharField(max_length=100, blank=True)  # current location as a string
 speed = models.FloatField(default=0.0) 


class Route(models.Model):
    name = models.CharField(max_length=100)
    description = models.TextField(null=True, blank=True)

    def __str__(self):
        return self.name

class Location(models.Model):
    route = models.ForeignKey(Route, on_delete=models.CASCADE, null=True)
    latitude = models.FloatField()
    longitude = models.FloatField()
    order = models.IntegerField()  # The order of the stop in the line

    def __str__(self):
        return f"{self.bus_line.name} Stop {self.order}"
    
class Trip(models.Model):
  id = models.AutoField(primary_key=True) 
  bus = models.ForeignKey(Bus, on_delete=models.CASCADE)  
  route = models.ForeignKey(Route, on_delete=models.CASCADE)
  departure_time = models.DateTimeField() 
  current_location = models.ForeignKey(
        Location, 
        on_delete=models.SET_NULL, 
        null=True, 
        blank=True
    )  
  estimated_arrival_time = models.DateTimeField() 

class Passenger(models.Model):
 id= models.AutoField(primary_key=True) 
 current_location = models.ForeignKey(Location, on_delete=models.SET_NULL, null=True, blank=True)
 destination = models.ForeignKey(Location, on_delete=models.SET_NULL, null=True, blank=True, related_name='destination_tickets')
     
