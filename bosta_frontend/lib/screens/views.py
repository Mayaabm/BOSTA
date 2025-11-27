from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from .models import Trip
from .serializers import TripSerializer

class EndTripView(generics.UpdateAPIView):
    """
    A view to end a trip.
    """
    queryset = Trip.objects.all()
    serializer_class = TripSerializer
    permission_classes = [IsAuthenticated]
    lookup_field = 'id'

    def update(self, request, *args, **kwargs):
        trip_id = self.kwargs.get('trip_id')
        try:
            trip = Trip.objects.get(id=trip_id)
            trip.status = 'completed'
            trip.save()
            return Response({'status': 'trip ended'}, status=status.HTTP_200_OK)
        except Trip.DoesNotExist:
            return Response({'error': 'Trip not found'}, status=status.HTTP_404_NOT_FOUND)