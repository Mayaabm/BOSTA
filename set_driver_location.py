#!/usr/bin/env python
"""
Dev script to manually set a driver's (bus) current location.
Uses the backend API endpoint instead of Django ORM to avoid GDAL dependency.

Usage:
    python set_driver_location.py
    
You'll be prompted to enter:
    - Bus ID (e.g., "bus_1", "bus_2")
    - Latitude (e.g., 33.3157)
    - Longitude (e.g., 35.4752)
    - Speed (m/s, optional, default 10.0)
"""

import requests
import json

# Backend URL
BACKEND_URL = "http://localhost:8000"
# Correct endpoint path defined by the backend: /api/buses/update_location/
UPDATE_LOCATION_ENDPOINT = f"{BACKEND_URL}/api/buses/update_location/"

# For auth, you'll need a token. For now, we'll try without auth since this is dev.
# If you get 401, update this with a valid JWT token.
AUTH_TOKEN = None  # Set this if the endpoint requires authentication

def set_driver_location():
    print("\n" + "="*60)
    print("DEV: Manually Set Driver (Bus) Current Location")
    print("="*60)
    
    # Get bus ID
    bus_id = input("\nEnter Bus ID (e.g., 'bus_1'): ").strip()
    
    # Get latitude
    while True:
        try:
            lat = float(input("Enter Latitude (e.g., 33.3157): ").strip())
            if -90 <= lat <= 90:
                break
            else:
                print("✗ Latitude must be between -90 and 90.")
        except ValueError:
            print("✗ Invalid latitude. Please enter a valid number.")
    
    # Get longitude
    while True:
        try:
            lon = float(input("Enter Longitude (e.g., 35.4752): ").strip())
            if -180 <= lon <= 180:
                break
            else:
                print("✗ Longitude must be between -180 and 180.")
        except ValueError:
            print("✗ Invalid longitude. Please enter a valid number.")
    
    # Get speed (optional)
    speed_input = input("Enter Speed in m/s (default 10.0): ").strip()
    speed = 10.0
    if speed_input:
        try:
            speed = float(speed_input)
        except ValueError:
            print("✗ Invalid speed. Using default 10.0 m/s.")
    
    # Prepare request
    payload = {
        'bus_id': bus_id,
        'latitude': lat,
        'longitude': lon,
    }
    
    headers = {
        'Content-Type': 'application/json',
    }
    
    # Add auth header if token is available
    if AUTH_TOKEN:
        headers['Authorization'] = f'Bearer {AUTH_TOKEN}'
    
    # Send request
    try:
        print(f"\n→ Sending request to {UPDATE_LOCATION_ENDPOINT}")
        response = requests.post(UPDATE_LOCATION_ENDPOINT, json=payload, headers=headers)
        
        print(f"← Response status: {response.status_code}")
        
        if response.status_code == 200:
            print(f"\n✓ Driver location updated successfully!")
            print(f"  Bus ID: {bus_id}")
            print(f"  Latitude: {lat}")
            print(f"  Longitude: {lon}")
            print(f"  Speed: {speed} m/s ({speed * 3.6:.1f} km/h)")
            print(f"\n✓ The rider app will now see this bus at the new location.")
        else:
            print(f"\n✗ Error: {response.status_code}")
            print(f"Response: {response.text}")
            
    except requests.exceptions.ConnectionError:
        print(f"\n✗ Could not connect to backend at {BACKEND_URL}")
        print("Make sure Django runserver is running: python manage.py runserver")
    except Exception as e:
        print(f"\n✗ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    set_driver_location()
