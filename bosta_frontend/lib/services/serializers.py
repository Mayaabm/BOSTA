from rest_framework import serializers
from .models import CustomUserProfile, Bus
from django.contrib.auth.models import User


class BusSerializer(serializers.ModelSerializer):
    class Meta:
        model = Bus
        fields = ['id', 'plate_number', 'route']


class DriverProfileSerializer(serializers.ModelSerializer):
    """
    Serializer for the driver's profile.
    Includes nested bus and user information to provide all necessary data
    in a single API call.
    """
    # Use a source to get the full name from the User model
    driver_name = serializers.CharField(source='user.get_full_name', read_only=True)
    username = serializers.CharField(source='user.username', read_only=True)
    email = serializers.EmailField(source='user.email', read_only=True)
    
    # Nested serializer to include bus details
    bus_id = serializers.CharField(source='bus.id', read_only=True)
    route_id = serializers.CharField(source='bus.route.id', read_only=True)

    class Meta:
        model = CustomUserProfile
        fields = [
            'driver_name',
            'username',
            'email',
            'bus_id',
            'route_id',
            'is_driver',
        ]