"""
Custom authentication backend for fallback token validation.
Used when rest_framework_simplejwt is not available.
"""
import base64
from django.contrib.auth.models import User
from rest_framework.authentication import TokenAuthentication
from rest_framework.exceptions import AuthenticationFailed


class FallbackTokenAuthentication(TokenAuthentication):
    """
    Simple token authentication using base64-encoded user data.
    Falls back when rest_framework_simplejwt is unavailable.
    """
    
    def authenticate(self, request):
        auth = request.META.get('HTTP_AUTHORIZATION', '').split()
        
        if not auth or auth[0].lower() != 'bearer':
            return None
        
        if len(auth) == 1:
            raise AuthenticationFailed('Invalid token header. No credentials provided.')
        
        if len(auth) > 2:
            raise AuthenticationFailed('Invalid token header. Token string should not contain spaces.')
        
        token = auth[1]
        
        try:
            # Try to decode the base64 token
            decoded = base64.b64decode(token).decode()
            parts = decoded.split(':')
            
            if len(parts) < 2:
                raise AuthenticationFailed('Invalid token format.')
            
            user_id = parts[0]
            username = parts[1]
            
            # Look up the user
            try:
                user = User.objects.get(id=int(user_id), username=username)
                return (user, token)
            except (User.DoesNotExist, ValueError):
                raise AuthenticationFailed('Invalid user token.')
        
        except (TypeError, ValueError, AttributeError):
            raise AuthenticationFailed('Invalid token.')
