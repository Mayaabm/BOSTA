#!/usr/bin/env python
"""
Dev script to manually set a rider's current location.
This saves a test rider location to a JSON file for reference.

Usage:
    python set_rider_location.py
    
You'll be prompted to enter:
    - Latitude (e.g., 33.3157)
    - Longitude (e.g., 35.4752)
"""

import os
import json
from datetime import datetime

# Create a dev data file to store the test rider location
RIDER_LOCATION_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.dev_rider_location.json')

def set_rider_location():
    print("\n" + "="*60)
    print("DEV: Manually Set Rider Current Location")
    print("="*60)
    print("\nThis saves a test rider location for reference.")
    print("The app uses its own GPS; this is just for documentation.")
    
    # Get latitude
    while True:
        try:
            lat = float(input("\nEnter Rider Latitude (e.g., 33.3157): ").strip())
            if -90 <= lat <= 90:
                break
            else:
                print("✗ Latitude must be between -90 and 90.")
        except ValueError:
            print("✗ Invalid latitude. Please enter a valid number.")
    
    # Get longitude
    while True:
        try:
            lon = float(input("Enter Rider Longitude (e.g., 35.4752): ").strip())
            if -180 <= lon <= 180:
                break
            else:
                print("✗ Longitude must be between -180 and 180.")
        except ValueError:
            print("✗ Invalid longitude. Please enter a valid number.")
    
    # Save to file
    try:
        location_data = {
            'latitude': lat,
            'longitude': lon,
            'timestamp': datetime.now().isoformat()
        }
        
        with open(RIDER_LOCATION_FILE, 'w') as f:
            json.dump(location_data, f, indent=2)
        
        print(f"\n✓ Rider location saved to .dev_rider_location.json")
        print(f"  Latitude: {lat}")
        print(f"  Longitude: {lon}")
        print(f"  File: {RIDER_LOCATION_FILE}")
        
    except Exception as e:
        print(f"\n✗ Error saving rider location: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    set_rider_location()
