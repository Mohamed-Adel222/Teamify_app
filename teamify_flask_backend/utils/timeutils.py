"""Datetime serialization helpers."""
from datetime import timezone


def utc_iso(dt):
    """Serialize a datetime with an explicit UTC offset.

    Columns store naive UTC; without the offset clients would read the
    timestamp as local time (e.g. "3h ago" bugs in UTC+3 timezones).
    """
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.isoformat()
