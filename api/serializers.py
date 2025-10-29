# api/serializers.py
from rest_framework import serializers
from api.models import Stop, Bus, Route

class PointAsGeoJSONField(serializers.Field):
    def to_representation(self, value):
        if not value:
            return None
        return {"type": "Point", "coordinates": [value.x, value.y]}  # lon, lat

class LineStringAsGeoJSONField(serializers.Field):
    def to_representation(self, value):
        if not value:
            return None
        # GEOS's `coords` gives a tuple of tuples, which is what we need.
        return {"type": "LineString", "coordinates": value.coords}

class StopSerializer(serializers.ModelSerializer):
    location = PointAsGeoJSONField()

    class Meta:
        model = Stop
        fields = ["id", "order", "location"]

class StopNearbySerializer(serializers.ModelSerializer):
    point = PointAsGeoJSONField(source='location')
    distance_m = serializers.FloatField()
    route_name = serializers.CharField(source='route.name')

    class Meta:
        model = Stop
        fields = ["id", "route_name", "order", "point", "distance_m"]

class BusNearbySerializer(serializers.ModelSerializer):
    current_point = PointAsGeoJSONField(source='current_location')
    distance_m = serializers.FloatField(source='distance_m.m', read_only=True)
    route_name = serializers.CharField(read_only=True) # Annotated field from view

    class Meta:
        model = Bus
        fields = ["id", "plate_number", "capacity", "speed_mps", "current_point", "distance_m", "route_name"]

class RouteSerializer(serializers.ModelSerializer):
    geometry = LineStringAsGeoJSONField()
    stops = StopSerializer(many=True, read_only=True)

    class Meta:
        model = Route
        fields = ["id", "name", "description", "geometry", "stops"]
