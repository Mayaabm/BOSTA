from django.shortcuts import render
# api/views.py
from rest_framework.response import Response
from rest_framework.decorators import api_view
from .models import Bus
from .serializers import BusSerializer
from .utils import haversine

@api_view(['GET'])
def get_buses(request):
    buses = Bus.objects.all()
    serializer = BusSerializer(buses, many=True)
    return Response(serializer.data)

@api_view(['GET'])
def buses_near_location(request):
    try:
        lat = float(request.GET.get('lat'))
        lon = float(request.GET.get('lon'))
        radius = float(request.GET.get('radius', 2))  # default 2 km
    except:
        return Response({"error": "Invalid parameters"}, status=400)
    
    nearby_buses = []
    
    for bus in Bus.objects.all():
        distance = haversine(lat, lon, bus.lat, bus.lon)
        if distance <= radius:
            nearby_buses.append(bus)
    
    serializer = BusSerializer(nearby_buses, many=True)
    return Response(serializer.data)
