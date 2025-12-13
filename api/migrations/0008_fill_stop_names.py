from django.db import migrations


def fill_stop_names(apps, schema_editor):
    Stop = apps.get_model('api', 'Stop')
    Route = apps.get_model('api', 'Route')

    # For any stop without a name, try to derive a human-friendly name:
    # 1. If the stop has an order and belongs to a route with a name ->
    #    "<Route name> Stop <order>"
    # 2. Otherwise use "Stop <order>"
    # 3. If order missing, fall back to "Stop <id>"
    for stop in Stop.objects.filter(name__isnull=True):
        try:
            order = getattr(stop, 'order', None)
            route = Route.objects.filter(id=getattr(stop, 'route_id', None)).first()

            if order is not None:
                if route and getattr(route, 'name', None):
                    new_name = f"{route.name} Stop {order}"
                else:
                    new_name = f"Stop {order}"
            else:
                new_name = f"Stop {stop.id}"

            stop.name = new_name
            stop.save(update_fields=['name'])
        except Exception:
            # Best-effort migration; skip problematic rows rather than failing
            continue


def unset_stop_names(apps, schema_editor):
    Stop = apps.get_model('api', 'Stop')
    # Revert only names that match the auto-generated pattern "Stop <number>"
    Stop.objects.filter(name__regex=r'^Stop \d+$').update(name=None)


class Migration(migrations.Migration):

    dependencies = [
        ('api', '0007_stop_name'),
    ]

    operations = [
        migrations.RunPython(fill_stop_names, unset_stop_names),
    ]
