"""
URL configuration for bosta_backend project.
"""
from django.contrib import admin
from django.urls import path, include
from api.views import DriverProfileView
from rest_framework_simplejwt.views import (
    TokenObtainPairView,
    TokenRefreshView,
)

# Assuming you have other API urls in `api.urls`
# We will add the new driver profile URL here.

urlpatterns = [
    path('admin/', admin.site.urls),

    # Your existing API URLs
    # path('api/', include('api.urls')), # If you have other urls

    # Endpoint for authenticated driver to get their profile
    path('api/driver/me/', DriverProfileView.as_view(), name='driver-profile'),

    # SimpleJWT Token URLs
    path('api/token/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
]