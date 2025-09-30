import os
import re
import json
from pathlib import Path
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from api.models import Route, Location
from api.utils import haversine  # you already have this

# ---------- helpers ----------

def norm_key(s: str) -> str:
    """Normalize a route key for matching (remove spaces/punct, lowercase)."""
    if s is None:
        return ""
    # keep letters/numbers (Arabic letters stay), remove punctuation
    s = re.sub(r"[^\w\u0600-\u06FF]+", "", s, flags=re.UNICODE)
    return s.lower()

def best_route_name_from_filename(fp: Path) -> str:
    """Use filename (without extension) as the route name."""
    return fp.stem.strip()

def extract_route_key_from_properties(props: dict) -> str:
    """
    Try common property fields that might carry route name/code.
    You can add more keys here if your data has them.
    """
    candidates = [
        "route", "Route", "ROUTE",
        "name", "Name", "NAME",
        "line", "Line", "LINE",
        "code", "Code", "CODE",
        "id", "Id", "ID"
    ]
    for k in candidates:
        if k in props and props[k]:
            return norm_key(str(props[k]))
    return ""

def extract_stop_order_from_props(props: dict, fallback_name: str = "") -> int | None:
    """
    Try to find a numeric order in properties or the name/id (e.g. B1-A12 -> 12).
    Returns int or None if not found.
    """
    # direct order field
    for k in ["order", "Order", "ORDER", "seq", "Seq", "SEQ", "stop_order", "StopOrder"]:
        if k in props:
            try:
                return int(props[k])
            except Exception:
                pass
    # try to parse from id/name text
    candidates = []
    for k in ["id", "Id", "ID", "name", "Name", "NAME", "label", "Label"]:
        if k in props and props[k]:
            candidates.append(str(props[k]))
    if fallback_name:
        candidates.append(fallback_name)

    for text in candidates:
        # Look for trailing number or -A12 style
        m = re.search(r"(\d+)$", text.strip())
        if not m:
            m = re.search(r"[A-Za-z\-\_]+(\d+)", text)
        if m:
            try:
                return int(m.group(1))
            except Exception:
                pass
    return None

def compute_cumulative_km_for_route(route: Route):
    """
    Fill cum_km for this route’s Location stops in order.
    Assumes ordering is correct.
    """
    stops = list(Location.objects.filter(route=route).order_by("order"))
    total = 0.0
    for i, s in enumerate(stops):
        if i == 0:
            s.cum_km = 0.0
        else:
            prev = stops[i - 1]
            seg = haversine(prev.latitude, prev.longitude, s.latitude, s.longitude)
            total += seg
            s.cum_km = total
        s.save(update_fields=["cum_km"])

# ---------- command ----------

class Command(BaseCommand):
    help = "Import Routes (LineString) and Stops (Point) from a folder of GeoJSON files."

    def add_arguments(self, parser):
        parser.add_argument(
            "--dir",
            dest="dirpath",
            required=True,
            help="Path to directory that contains .geojson files",
        )
        parser.add_argument(
            "--clear",
            action="store_true",
            help="If set, clears existing Locations for a route before re-importing.",
        )
        parser.add_argument(
            "--sample-linestring-stops",
            action="store_true",
            help="If a route has no Point stops, sample vertices from the LineString into pseudo-stops.",
        )
        parser.add_argument(
            "--every-nth",
            type=int,
            default=10,
            help="When sampling LineString vertices, keep every Nth vertex (default 10).",
        )

    @transaction.atomic
    def handle(self, *args, **opts):
        dirpath = Path(opts["dirpath"]).expanduser().resolve()
        if not dirpath.exists() or not dirpath.is_dir():
            raise CommandError(f"Directory not found: {dirpath}")

        files = sorted([p for p in dirpath.glob("*.geojson") if p.is_file()])
        if not files:
            self.stdout.write(self.style.WARNING("No .geojson files found."))
            return

        self.stdout.write(f"Found {len(files)} GeoJSON files.")

        # First pass: create/collect routes from LineStrings (by filename)
        routes_by_key = {}  # normalized key -> Route
        for fp in files:
            try:
                with fp.open("r", encoding="utf-8") as f:
                    data = json.load(f)
            except Exception as e:
                self.stdout.write(self.style.ERROR(f"[READ ERR] {fp.name}: {e}"))
                continue

            features = data.get("features") or []
            # Is there any LineString? If so, create a route for the file.
            has_linestring = any(
                (feat.get("geometry") or {}).get("type") == "LineString" for feat in features
            )
            if not has_linestring:
                continue

            route_name = best_route_name_from_filename(fp)
            route_norm = norm_key(route_name)
            route, _ = Route.objects.get_or_create(name=route_name, defaults={"description": ""})
            routes_by_key[route_norm] = route
            self.stdout.write(f"Route ensured from {fp.name} -> {route.name}")

        if not routes_by_key:
            self.stdout.write(self.style.WARNING("No LineStrings found, so no routes created."))
        else:
            self.stdout.write(self.style.SUCCESS(f"Ensured {len(routes_by_key)} routes exist."))

        # Second pass: load Point stops and assign to matching routes
        assigned_counts = {r.id: 0 for r in routes_by_key.values()}

        for fp in files:
            try:
                with fp.open("r", encoding="utf-8") as f:
                    data = json.load(f)
            except Exception as e:
                self.stdout.write(self.style.ERROR(f"[READ ERR] {fp.name}: {e}"))
                continue

            features = data.get("features") or []
            if not features:
                continue

            # Try to determine file’s primary route key (from filename)
            file_route_name = best_route_name_from_filename(fp)
            file_route_key = norm_key(file_route_name)
            file_route = routes_by_key.get(file_route_key)

            # Gather candidate Point features
            point_features = [
                feat for feat in features
                if (feat.get("geometry") or {}).get("type") == "Point"
            ]
            if not point_features:
                continue

            if file_route is None:
                # This file has Points but we didn't see a LineString route file with the same base name.
                # Try to match by properties per feature instead.
                self.stdout.write(self.style.WARNING(
                    f"[POINTS ONLY] {fp.name}: no matching LineString route created from this filename."
                ))

            # Bucket points to routes
            buckets = {}  # route_id -> list of (order, lat, lon, desc, raw_order_found)
            for feat in point_features:
                geom = feat.get("geometry") or {}
                coords = geom.get("coordinates") or []
                if len(coords) < 2:
                    continue
                lon, lat = coords[0], coords[1]

                props = feat.get("properties") or {}
                desc = props.get("desc") or props.get("description") or props.get("name") or ""

                # Route matching: prefer filename’s route; else try property-based key
                target_route = file_route
                if target_route is None:
                    rk = extract_route_key_from_properties(props)
                    if rk and rk in routes_by_key:
                        target_route = routes_by_key[rk]

                if target_route is None:
                    # Couldn’t match this point to any route
                    self.stdout.write(self.style.WARNING(
                        f"  WARNING: {fp.name} point '{props.get('name') or props.get('id') or desc}' "
                        f"did not match any route. Skipping."
                    ))
                    continue

                ordered = extract_stop_order_from_props(props, fallback_name=desc)
                buckets.setdefault(target_route.id, []).append((ordered, lat, lon, desc))

            # Create locations for each route bucket
            for route_id, points in buckets.items():
                route = Route.objects.get(id=route_id)
                if opts["clear"]:
                    route.stops.all().delete()

                # Sort: points with explicit order come first by that order, then append unordered in file order
                with_order = [(o, lat, lon, d) for (o, lat, lon, d) in points if o is not None]
                no_order = [(o, lat, lon, d) for (o, lat, lon, d) in points if o is None]
                with_order.sort(key=lambda x: x[0])

                new_list = with_order + no_order

                # Assign incremental order for None ones continuing from last given order
                next_idx = 1
                if with_order:
                    next_idx = with_order[-1][0] + 1

                final_points = []
                for (o, lat, lon, d) in new_list:
                    if o is None:
                        final_points.append((next_idx, lat, lon, d))
                        next_idx += 1
                    else:
                        final_points.append((o, lat, lon, d))

                # Wipe & insert (idempotent if --clear used)
                if opts["clear"]:
                    route.stops.all().delete()

                # Prevent duplicates on re-run without --clear: we’ll rebuild by wiping first if any exist
                if route.stops.exists():
                    route.stops.all().delete()

                for order, lat, lon, d in sorted(final_points, key=lambda x: x[0]):
                    Location.objects.create(
                        route=route,
                        order=order,
                        latitude=lat,
                        longitude=lon,
                        description=d or "",
                    )
                assigned_counts[route.id] += len(final_points)
                compute_cumulative_km_for_route(route)

        # Optional: for routes that got no Point stops, sample LineString vertices if asked
        if opts["sample_linestring_stops"]:
            for fp in files:
                try:
                    with fp.open("r", encoding="utf-8") as f:
                        data = json.load(f)
                except Exception:
                    continue

                features = data.get("features") or []
                lines = [
                    feat for feat in features
                    if (feat.get("geometry") or {}).get("type") == "LineString"
                ]
                if not lines:
                    continue

                route_name = best_route_name_from_filename(fp)
                route_key = norm_key(route_name)
                route = routes_by_key.get(route_key)
                if not route:
                    continue
                if assigned_counts.get(route.id, 0) > 0:
                    # already has point stops
                    continue

                # sample vertices
                coords = []
                for feat in lines:
                    c = (feat.get("geometry") or {}).get("coordinates") or []
                    if c:
                        coords.extend(c)

                if not coords:
                    continue

                # wipe current stops if any
                route.stops.all().delete()

                every = max(1, int(opts["every_nth"]))
                order = 1
                for i, (lon, lat, *_) in enumerate(coords):
                    if i % every == 0 or i == len(coords) - 1:
                        Location.objects.create(
                            route=route,
                            order=order,
                            latitude=float(lat),
                            longitude=float(lon),
                            description=f"Vertex {i}",
                        )
                        order += 1
                compute_cumulative_km_for_route(route)
                self.stdout.write(
                    self.style.WARNING(
                        f"[SAMPLED] {route.name}: created {order-1} pseudo-stops from LineString vertices."
                    )
                )

        # summary
        created_routes = len(routes_by_key)
        created_stops = sum(assigned_counts.values())
        self.stdout.write(self.style.SUCCESS(
            f"Done. Routes ensured: {created_routes}. Point stops created: {created_stops}."
        ))
