"""Helpers for normalizing, validating, and resolving mobile app version rules."""
import re
from urllib.parse import urlparse

DISABLED_VERSION = "0"
MAX_VERSION_LENGTH = 20
_VERSION_RE = re.compile(r"^\d+(?:\.\d+)*$")
_PREFIX_RE = re.compile(r"^[vV](?=\d)")


def normalize_app_version(raw: str | None) -> str:
    """Trim whitespace, optional leading 'v'/'V', and trailing '+build' metadata."""
    if raw is None:
        return ""
    cleaned = raw.strip()
    if not cleaned:
        return ""
    cleaned = _PREFIX_RE.sub("", cleaned)
    return cleaned.split("+", 1)[0].strip()


def is_disabled_version(raw: str | None) -> bool:
    """Return True when the version is empty or all numeric segments are zero."""
    normalized = normalize_app_version(raw)
    if not normalized:
        return True
    if not _VERSION_RE.match(normalized):
        return False
    return all(int(part) == 0 for part in normalized.split("."))


def parse_admin_version_input(raw: str | None, field_label: str) -> str:
    """Validate and normalize an admin-entered version string for persistence.

    Empty strings and zero values ('0', '0.0.0', etc.) are preserved so admins
    can explicitly disable force or soft updates without snapping back to defaults.
    """
    normalized = normalize_app_version(raw)
    if not normalized:
        return ""
    if not _VERSION_RE.match(normalized):
        raise ValueError(
            f"{field_label} must be a numeric version like 1.1.5, or 0 / empty to disable."
        )
    if len(normalized) > MAX_VERSION_LENGTH:
        raise ValueError(
            f"{field_label} must be at most {MAX_VERSION_LENGTH} characters."
        )
    return normalized


def api_version_value(raw: str | None) -> str:
    """Resolve a stored version field for the public /misc/app-version API.

    Disabled ('', None, '0', '0.0.0') or invalid values return '0' so the
    mobile app's version comparator treats every installed build as up to date
    and suppresses the corresponding prompt without requiring mobile changes.
    """
    normalized = normalize_app_version(raw)
    if not normalized or not _VERSION_RE.match(normalized):
        return DISABLED_VERSION
    if all(int(part) == 0 for part in normalized.split(".")):
        return DISABLED_VERSION
    return normalized


def validate_store_url(raw: str | None, default_url: str, field_label: str) -> str:
    """Validate an optional store URL, falling back to default_url when cleared."""
    cleaned = (raw or "").strip()
    if not cleaned:
        return default_url
    parsed = urlparse(cleaned)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise ValueError(f"{field_label} must be a valid http(s) URL.")
    return cleaned
