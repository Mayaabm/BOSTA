from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework import status
from .models import CustomUserProfile
from .serializers import DriverProfileSerializer

class DriverProfileView(APIView):
    """
    API endpoint to get the current authenticated driver's profile.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        try:
            # Fetch the profile linked to the authenticated user
            profile = CustomUserProfile.objects.get(user=user)

            # Ensure the user is actually a driver
            if not profile.is_driver:
                return Response({'error': 'User is not a driver.'}, status=status.HTTP_403_FORBIDDEN)

            # Serialize the profile data
            serializer = DriverProfileSerializer(profile)
            return Response(serializer.data, status=status.HTTP_200_OK)

        except CustomUserProfile.DoesNotExist:
            return Response({'error': 'Driver profile not found.'}, status=status.HTTP_404_NOT_FOUND)
        except Exception as e:
            return Response({'error': f'An unexpected error occurred: {str(e)}'}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)