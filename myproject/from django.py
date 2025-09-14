from django.db import models
from django.contrib.auth.models import User

class Bus(models.model):
 Bus_ID=models.AutoField(primary_key=True)
 plate_number = models.CharField(max_length=20, unique=True)
 capacity = models.IntegerField()
 current_location = models.CharField(max_length=100, blank=True)  # current location as a string
 speed = models.FloatField(default=0.0) 


class Location(models.model):
 id = models.AutoField(primary_key=True) 
 name = models.CharField(max_length=100, unique=True)  

 def __str__(self):
        return self.name
 
class Route(models.model):
 id = models.AutoField(primary_key=True)
 name = models.CharField(max_length=100)
 previous_route = models.ForeignKey(
        'self', on_delete=models.SET_NULL, null=True, blank=True
    )
class Trip(models.model):
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

class Passenger(models.model):
 id= models.AutoField(primary_key=True) 
 current_location = models.ForeignKey(Location, on_delete=models.SET_NULL, null=True, blank=True)
 destination = models.ForeignKey(Location, on_delete=models.SET_NULL, null=True, blank=True, related_name='destination_tickets')
     
