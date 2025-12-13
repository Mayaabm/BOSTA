
"""simulate_bus_movement.py

Simulate a bus moving along a LineString route and POST location updates.
"""

import argparse
import json
import math
import sys
import time
import logging
from typing import List, Tuple, Optional

import requests
import getpass


def haversine_m(a: Tuple[float, float], b: Tuple[float, float]) -> float:
    lat1, lon1 = math.radians(a[0]), math.radians(a[1])
    lat2, lon2 = math.radians(b[0]), math.radians(b[1])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    R = 6371000.0
    hav = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * R * math.asin(math.sqrt(hav))


def interp(a: Tuple[float, float], b: Tuple[float, float], t: float) -> Tuple[float, float]:
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def load_route_from_geojson(path: str, feature_index: int = 0) -> List[Tuple[float, float]]:
    with open(path, 'r', encoding='utf-8') as fh:
        data = json.load(fh)
    features = data.get('features') if isinstance(data, dict) else None
    if not features:
        raise RuntimeError('GeoJSON has no features')
    feat = features[feature_index]
    geom = feat.get('geometry')
    if not geom or geom.get('type') != 'LineString':
        raise RuntimeError('Selected feature is not a LineString')
    coords = geom.get('coordinates')
    return [(c[1], c[0]) for c in coords]


def fetch_route_from_api(base_url: str, route_id: str) -> List[Tuple[float, float]]:
    # Try the provided base URL and also base+'/api' if the first returns 404
    tried = []
    bases = [base_url.rstrip('/')]
    if not base_url.rstrip('/').endswith('/api'):
        bases.append(base_url.rstrip('/') + '/api')
    for base in bases:
        url = f"{base}/routes/{route_id}/"
        tried.append(url)
        try:
            resp = requests.get(url, timeout=5)
            if resp.status_code == 404:
                continue
            resp.raise_for_status()
            data = resp.json()
            geom = data.get('geometry')
            if isinstance(geom, dict) and geom.get('type') == 'LineString':
                return [(c[1], c[0]) for c in geom.get('coordinates')]
            raise RuntimeError('Route geometry not found or unsupported format')
        except requests.HTTPError:
            # try next base
            continue
        except Exception:
            continue
    raise RuntimeError(f'Failed to fetch route {route_id}; tried: {tried}')


def segment_distances(points: List[Tuple[float, float]]) -> List[float]:
    return [haversine_m(points[i], points[i + 1]) for i in range(len(points) - 1)]


def cumulative_lengths(seg_lengths: List[float]) -> List[float]:
    cum = [0.0]
    s = 0.0
    for l in seg_lengths:
        s += l
        cum.append(s)
    return cum


def get_point_at_distance(points: List[Tuple[float, float]], seg_lengths: List[float], distance_m: float):
    if distance_m <= 0:
        return points[0], 0, 0.0
    cum = cumulative_lengths(seg_lengths)
    if distance_m >= cum[-1]:
        return points[-1], len(points) - 2, 1.0
    for i in range(len(seg_lengths)):
        if cum[i] <= distance_m <= cum[i + 1]:
            seg_offset = distance_m - cum[i]
            frac = seg_offset / seg_lengths[i] if seg_lengths[i] > 0 else 0.0
            return interp(points[i], points[i + 1], frac), i, frac
    return points[-1], len(points) - 2, 1.0


def _extract_point_from_geojson_point(obj):
    if not obj:
        return None
    if isinstance(obj, dict):
        coords = obj.get('coordinates') or obj.get('coords')
        if isinstance(coords, (list, tuple)) and len(coords) >= 2:
            try:
                lon, lat = float(coords[0]), float(coords[1])
                return (lat, lon)
            except Exception:
                return None
    return None


def run_simulation(points: List[Tuple[float, float]], bus_id: str, base_url: str, token: Optional[str],
                   speed_kmh: float = 30.0, interval_sec: float = 1.0, loop: bool = True,
                   start_offset_m: Optional[float] = None, start_point_index: Optional[int] = None,
                   start_latlon: Optional[Tuple[float, float]] = None, end_latlon: Optional[Tuple[float, float]] = None,
                   end_threshold_m: float = 50.0, logger: Optional[logging.Logger] = None,
                   local: bool = False):
    speed_mps = speed_kmh / 3.6
    update_url = f"{base_url.rstrip('/')}/buses/update_location/"
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = f"Bearer {token}"

    seg_lengths = segment_distances(points)

    # starting position
    if start_point_index is not None:
        if start_point_index < 0 or start_point_index >= len(points):
            raise ValueError('start_point_index out of range')
        current_seg = start_point_index if start_point_index < len(points) - 1 else len(points) - 2
        traveled_in_seg = 0.0
    elif start_latlon is not None:
        best_idx, best_dist = 0, float('inf')
        for idx, p in enumerate(points):
            d = haversine_m(p, start_latlon)
            if d < best_dist:
                best_dist = d
                best_idx = idx
        current_seg = best_idx if best_idx < len(points) - 1 else len(points) - 2
        traveled_in_seg = 0.0
        if logger:
            logger.info(f'Chosen start vertex {current_seg} (dist {best_dist:.1f} m)')
    elif start_offset_m is not None:
        pt, seg_idx, frac = get_point_at_distance(points, seg_lengths, start_offset_m)
        current_seg = seg_idx
        traveled_in_seg = frac * seg_lengths[seg_idx]
    else:
        current_seg = 0
        traveled_in_seg = 0.0

    loop_count = 0
    while True:
        seg_idx = current_seg
        while seg_idx < len(points) - 1:
            a = points[seg_idx]
            b = points[seg_idx + 1]
            seg_len = seg_lengths[seg_idx]
            if seg_len <= 0.1:
                seg_idx += 1
                traveled_in_seg = 0.0
                continue

            traveled = traveled_in_seg
            while traveled < seg_len:
                frac = traveled / seg_len
                lat, lon = interp(a, b, frac)
                payload = {'bus_id': str(bus_id), 'latitude': lat, 'longitude': lon}
                ts = time.strftime('%Y-%m-%d %H:%M:%S')
                try:
                    if local:
                        if logger:
                            logger.info(f"{ts} LOCAL loop={loop_count} seg={seg_idx} frac={frac:.3f} {lat:.6f},{lon:.6f}")
                        else:
                            print(f"{ts} LOCAL loop={loop_count} seg={seg_idx} frac={frac:.3f} {lat:.6f},{lon:.6f}")
                    else:
                        r = requests.post(update_url, json=payload, headers=headers, timeout=5)
                        if logger:
                            logger.info(f"{ts} HTTP {r.status_code} loop={loop_count} seg={seg_idx} {lat:.6f},{lon:.6f}")
                except Exception as e:
                    if logger:
                        logger.exception('Failed to send update: %s', e)
                    else:
                        print('Failed to send update:', e)

                # Check destination
                if end_latlon is not None and haversine_m((lat, lon), end_latlon) <= end_threshold_m:
                    if logger:
                        logger.info('Destination reached; stopping simulation')
                    else:
                        print('Destination reached; stopping simulation')
                    return

                time.sleep(interval_sec)
                traveled += speed_mps * interval_sec

            # send segment end
            lat_end, lon_end = b
            try:
                if local:
                    if logger:
                        logger.info(f"{time.strftime('%Y-%m-%d %H:%M:%S')} LOCAL END seg={seg_idx} {lat_end:.6f},{lon_end:.6f}")
                    else:
                        print('END', lat_end, lon_end)
                else:
                    requests.post(update_url, json={'bus_id': str(bus_id), 'latitude': lat_end, 'longitude': lon_end}, headers=headers, timeout=5)
            except Exception:
                pass

            if end_latlon is not None and haversine_m((lat_end, lon_end), end_latlon) <= end_threshold_m:
                if logger:
                    logger.info('Destination reached at segment end; finishing')
                else:
                    print('Destination reached at segment end; finishing')
                return

            seg_idx += 1
            traveled_in_seg = 0.0

        loop_count += 1
        if not loop:
            if logger:
                logger.info('Completed route (no loop); exiting')
            else:
                print('Completed route (no loop); exiting')
            return
        current_seg = 0
        traveled_in_seg = 0.0


def main(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument('--route-file', default='routes/cleaned_bus_routes.geojson')
    p.add_argument('--feature-index', type=int, default=0)
    p.add_argument('--route-id', help='Fetch route geometry from API instead of file')
    p.add_argument('--base-url', default='http://localhost:8000/api')
    p.add_argument('--bus-id', help='Bus id (required unless --interactive is used)')
    p.add_argument('--token', help='Bearer token for Authorization header')
    p.add_argument('--login', action='store_true', help='Prompt for driver credentials and fetch token from driver_login endpoint')
    p.add_argument('--start-trip', action='store_true', help='Create and start a trip for the driver before sending updates (requires auth token)')
    p.add_argument('--speed-kmh', type=float, default=30.0)
    p.add_argument('--interval-sec', type=float, default=1.0)
    p.add_argument('--loop', action='store_true')
    p.add_argument('--start-offset-m', type=float, help='Start this many meters from beginning of route')
    p.add_argument('--start-point-index', type=int, help='Start at this vertex index of the route')
    p.add_argument('--start-latlon', help='Start near this lat,lon (format: LAT,LON)')
    p.add_argument('--use-driver-locations', action='store_true', help='Fetch driver-selected start/destination from API when available')
    p.add_argument('--end-latlon', help='End near this lat,lon (format: LAT,LON)')
    p.add_argument('--end-threshold-m', type=float, default=50.0, help='Distance threshold in meters to consider destination reached')
    p.add_argument('--log-file', help='Path to write detailed logs')
    p.add_argument('--verbose', action='store_true', help='Enable verbose logging')
    p.add_argument('--local', action='store_true', help='Run locally without sending HTTP updates (just log positions)')
    p.add_argument('--interactive', action='store_true', help='Ask for missing inputs interactively')
    args = p.parse_args(argv)

    # non-interactive or interactive flow (keeps behavior from original)
    points = None
    if args.interactive:
        # prepare possible base endpoints
        bases = [args.base_url.rstrip('/')]
        if not args.base_url.rstrip('/').endswith('/api'):
            bases.append(args.base_url.rstrip('/') + '/api')

        # Offer driver login first (so we can auto-populate bus/route/start/end)
        if args.login or (not args.token and not args.local):
            do_login = input('Login as driver to fetch route/start/destination? (Y/n): ').strip().lower() or 'y'
            if do_login.startswith('y'):
                email = input('Driver email: ').strip()
                password = getpass.getpass('Password: ')
                for base in bases:
                    try:
                        r = requests.post(f"{base}/driver_login/", json={'email': email, 'password': password}, timeout=10)
                        if r.status_code == 200:
                            data = r.json()
                            tok = data.get('access') or data.get('token')
                            if tok:
                                args.token = tok
                                break
                    except Exception:
                        continue

        # if we have a token, fetch driver/me to auto-fill info
        if args.token and not args.local:
            headers = {'Authorization': f'Bearer {args.token}'}
            for base in bases:
                try:
                    r = requests.get(f"{base}/driver/me/", headers=headers, timeout=5)
                    if r.status_code != 200:
                        continue
                    js = r.json()
                    # populate bus id if available
                    bus = js.get('bus')
                    if isinstance(bus, dict):
                        try:
                            bid = bus.get('id') or bus.get('bus_id')
                            if bid and not args.bus_id:
                                args.bus_id = str(bid)
                        except Exception:
                            pass
                        p = _extract_point_from_geojson_point(bus.get('current_point'))
                    else:
                        p = None

                    # extract route geometry if present
                    route = js.get('route')
                    if isinstance(route, dict):
                        geom = route.get('geometry')
                        if isinstance(geom, dict) and geom.get('type') == 'LineString':
                            points = [(c[1], c[0]) for c in geom.get('coordinates')]
                        else:
                            # maybe stops only; try to derive start/end
                            stops = route.get('stops')
                            if isinstance(stops, list) and len(stops) >= 2 and points is None:
                                p0 = _extract_point_from_geojson_point(stops[0].get('location') or stops[0].get('point'))
                                pN = _extract_point_from_geojson_point(stops[-1].get('location') or stops[-1].get('point'))
                                if p0 and pN and points is None:
                                    points = [p0, pN]

                    # active trip may contain origin/destination
                    active_trip_id = js.get('active_trip_id')
                    if active_trip_id and (p is None or points is None):
                        try:
                            tr = requests.get(f"{base}/trips/{active_trip_id}/", headers=headers, timeout=5)
                            if tr.status_code == 200:
                                tj = tr.json()
                                for key in ('origin','origin_point','start_point','start_location'):
                                    if tj.get(key) and p is None:
                                        p = _extract_point_from_geojson_point(tj.get(key))
                                for key in ('destination','end_point','end_location','destination_point'):
                                    if tj.get(key) and points is None:
                                        dest = _extract_point_from_geojson_point(tj.get(key))
                                        if dest and p:
                                            points = [p, dest]
                        except Exception:
                            pass

                    # if we found a starting point, set start_latlon
                    if 'p' in locals() and p:
                        args.start_latlon = f"{p[0]},{p[1]}"
                    # if driver route provided start/end in variables above, set end_latlon
                    if points is not None and len(points) >= 2 and args.end_latlon is None:
                        # use last point as end
                        args.end_latlon = f"{points[-1][0]},{points[-1][1]}"
                    break
                except Exception:
                    continue

        # If token/login didn't yield points, fall back to asking user
        if points is None:
            if not args.bus_id:
                args.bus_id = input('Bus id: ').strip()
            use_bus_route = input('Use route assigned to this bus? (y/N): ').strip().lower() or 'n'
            if use_bus_route.startswith('y'):
                try:
                    for base in bases:
                        url = f"{base}/buses/{args.bus_id}/"
                        try:
                            resp = requests.get(url, timeout=5)
                            if resp.status_code == 200:
                                bus_data = resp.json()
                                route_obj = None
                                for key in ('route', 'assigned_route', 'assignedRoute'):
                                    if bus_data.get(key):
                                        route_obj = bus_data.get(key)
                                        break
                                if isinstance(route_obj, dict):
                                    geom = route_obj.get('geometry')
                                    if isinstance(geom, dict) and geom.get('type') == 'LineString':
                                        points = [(c[1], c[0]) for c in geom.get('coordinates')]
                                        break
                                    rid = route_obj.get('id') or route_obj.get('route_id')
                                    if rid:
                                        args.route_id = str(rid)
                                        break
                        except Exception:
                            continue
                except Exception:
                    pass

            if points is None:
                choose = input('Provide route via (f)ile or (i)d? (f/i) [f]: ').strip().lower() or 'f'
                if choose.startswith('f'):
                    rf = input(f'Route file [{args.route_file}]: ').strip() or args.route_file
                    fi = input(f'Feature index [{args.feature_index}]: ').strip() or str(args.feature_index)
                    args.route_file = rf
                    try:
                        args.feature_index = int(fi)
                    except Exception:
                        args.feature_index = 0
                    points = load_route_from_geojson(args.route_file, args.feature_index)
                else:
                    rid = input('Route id: ').strip()
                    args.route_id = rid

        # if not token and not local and user declined login, offer token or local
        if not args.token and not args.local:
            tk = input('Provide token or press Enter to run in local mode (no HTTP): ').strip()
            if tk:
                args.token = tk
            else:
                args.local = True

    if points is None:
        if args.route_id and not args.local:
            points = fetch_route_from_api(args.base_url, args.route_id)
        elif args.route_id and args.local:
            # Running local mode: do not perform HTTP fetch. Ask for a local route file instead.
            print('Running in local mode; cannot fetch route from API. Please provide a route file.')
            args.route_file = input(f'Route file [{args.route_file}]: ').strip() or args.route_file
            try:
                points = load_route_from_geojson(args.route_file, args.feature_index)
            except Exception as e:
                raise RuntimeError(f'Failed to load local route file: {e}')
        else:
            points = load_route_from_geojson(args.route_file, args.feature_index)

    if len(points) < 2:
        print('Route must contain at least two points')
        return 2

    if not args.bus_id:
        if args.interactive:
            args.bus_id = input('Bus id: ').strip()
        else:
            print('error: the following arguments are required: --bus-id')
            return 2

    logger = logging.getLogger('simbus')
    level = logging.DEBUG if args.verbose else logging.INFO
    handlers = [logging.StreamHandler()]
    if args.log_file:
        handlers.append(logging.FileHandler(args.log_file))
    logging.basicConfig(level=level, format='%(asctime)s %(levelname)s %(message)s', handlers=handlers)

    start_latlon = None
    if args.start_latlon:
        try:
            lat_s, lon_s = args.start_latlon.split(',')
            start_latlon = (float(lat_s.strip()), float(lon_s.strip()))
        except Exception as e:
            logger.error('Invalid --start-latlon format: %s', e)
            return 2

    end_latlon = None
    if args.end_latlon:
        try:
            lat_s, lon_s = args.end_latlon.split(',')
            end_latlon = (float(lat_s.strip()), float(lon_s.strip()))
        except Exception as e:
            logger.error('Invalid --end-latlon format: %s', e)
            return 2

    try:
        run_simulation(
            points,
            args.bus_id,
            args.base_url,
            args.token,
            speed_kmh=args.speed_kmh,
            interval_sec=args.interval_sec,
            loop=args.loop,
            start_offset_m=args.start_offset_m,
            start_point_index=args.start_point_index,
            start_latlon=start_latlon,
            end_latlon=end_latlon,
            end_threshold_m=args.end_threshold_m,
            logger=logger,
            local=args.local,
        )
    except KeyboardInterrupt:
        print('\nSimulation stopped by user')


if __name__ == '__main__':
    sys.exit(main())
