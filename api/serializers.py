# api/serializers.py
from rest_framework import serializers
from api.models import Location, Bus

class PointAsGeoJSONField(serializers.Field):
    def to_representation(self, value):
        if not value:
            return None
        return {"type": "Point", "coordinates": [value.x, value.y]}  # lon, lat

class LocationNearbySerializer(serializers.ModelSerializer):
    point = PointAsGeoJSONField()
    distance_m = serializers.FloatField()
    route_id = serializers.IntegerField(source='route.id')
    route_name = serializers.CharField(source='route.name')

    class Meta:
        model = Location
        fields = ["id", "route_id", "route_name", "order", "description", "point", "distance_m"]

class BusNearbySerializer(serializers.ModelSerializer):
    current_point = PointAsGeoJSONField()
    distance_m = serializers.FloatField()

    class Meta:
        model = Bus
        fields = ["id", "plate_number", "capacity", "current_point", "speed_mps", "distance_m"]
