from datetime import datetime, timezone, timedelta
from typing import Optional, Dict

# In-memory store for deferred referral attribution
# Key: client_ip -> Value: {"referral_code": str, "user_agent": str, "timestamp": datetime}
_REFERRAL_CLICKS: Dict[str, dict] = {}
_TTL_HOURS = 2


def record_referral_click(ip: str, user_agent: str, referral_code: str) -> None:
    """Store a referral link click by IP address for deferred matching."""
    if not ip or not referral_code:
        return
    now = datetime.now(timezone.utc)
    _cleanup_expired(now)
    _REFERRAL_CLICKS[ip.strip()] = {
        "referral_code": referral_code.strip().upper(),
        "user_agent": user_agent or "",
        "timestamp": now,
    }


def match_referral_by_ip(ip: str) -> Optional[str]:
    """Retrieve and match a pending referral code by IP address within TTL."""
    if not ip:
        return None
    now = datetime.now(timezone.utc)
    _cleanup_expired(now)
    record = _REFERRAL_CLICKS.get(ip.strip())
    if record:
        return record["referral_code"]
    return None


def _cleanup_expired(now: datetime) -> None:
    cutoff = now - timedelta(hours=_TTL_HOURS)
    expired_keys = [k for k, v in _REFERRAL_CLICKS.items() if v["timestamp"] < cutoff]
    for k in expired_keys:
        _REFERRAL_CLICKS.pop(k, None)
