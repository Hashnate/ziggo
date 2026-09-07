import asyncio
import os

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles

from fastapi import Request
from fastapi.responses import RedirectResponse


from .config import settings
from .database import engine
from .api.v1 import auth, customer, driver, admin, bookings, ws, event, food, market, market_vendor, misc, payments, restaurant, trip_share, public, corporate, surge_zones
from ziggo_admin_panel import routes as admin_panel_routes
from ziggo_admin_panel.routes import _AdminRedirect, _AdminForbidden
from .services.schema_sync import ensure_schema
from .services.auto_cancel import auto_cancel_loop
from .services.scheduled_dispatch import scheduled_dispatch_loop
from .services import fcm_service

app = FastAPI(
    title=settings.PROJECT_NAME,
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
)


_background_tasks: set[asyncio.Task] = set()


@app.on_event("startup")
async def _run_schema_sync() -> None:
    await ensure_schema(engine)


@app.on_event("startup")
async def _init_fcm() -> None:
    """Initialise Firebase Admin SDK. Safe no-op when credentials aren't set."""
    fcm_service.init()


@app.on_event("startup")
async def _launch_background_tasks() -> None:
    """Spin up the food-order auto-cancel sweeper. Held in a set so the GC
    doesn't reap the task reference."""
    task = asyncio.create_task(auto_cancel_loop())
    _background_tasks.add(task)
    task.add_done_callback(_background_tasks.discard)

    scheduled_task = asyncio.create_task(scheduled_dispatch_loop())
    _background_tasks.add(scheduled_task)
    scheduled_task.add_done_callback(_background_tasks.discard)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def broadcast_admin_changes_middleware(request: Request, call_next):
    response = await call_next(request)
    path = request.url.path
    method = request.method
    if (path.startswith("/admin") or path.startswith("/admin-api") or path.startswith("/api/v1/admin")) and method in ("POST", "PUT", "DELETE", "PATCH"):
        if 200 <= response.status_code < 400:
            from .services.ws_manager import manager
            asyncio.create_task(manager.broadcast_all("admin_config_update", {"type": "settings", "path": path}))
    return response


@app.get("/")
async def root():
    return RedirectResponse(url="/admin/login")


@app.get("/admin")
async def admin_root():
    return RedirectResponse(url="/admin/login")


@app.get("/health")
async def health():
    return {"status": "ok", "service": settings.PROJECT_NAME}


@app.get("/download")
async def download_redirect(request: Request, ref: str = "", code: str = ""):
    """Smart download router that logs referral clicks for deferred attribution
    and redirects user to Google Play or Apple App Store."""
    referral_code = (ref or code).strip().upper()
    client_ip = request.headers.get("x-forwarded-for", "").split(",")[0].strip() or (request.client.host if request.client else "")
    user_agent = request.headers.get("user-agent", "")

    if referral_code:
        from .services.referral_tracker_service import record_referral_click
        record_referral_click(client_ip, user_agent, referral_code)

    ua_lower = user_agent.lower()
    play_url = f"https://play.google.com/store/apps/details?id=lk.ziggo.app&referrer=ref%3D{referral_code}" if referral_code else "https://play.google.com/store/apps/details?id=lk.ziggo.app"
    app_store_url = "https://apps.apple.com/app/ziggo-app/id6778739956"

    if "android" in ua_lower:
        return RedirectResponse(url=play_url, status_code=302)
    elif "iphone" in ua_lower or "ipad" in ua_lower or "ipod" in ua_lower:
        return RedirectResponse(url=app_store_url, status_code=302)

    from fastapi.responses import HTMLResponse
    ref_box = f"""<div class="badge-box">
      <div class="badge-title">Invited Referral Code</div>
      <div class="ref-code">{referral_code}</div>
      <div style="font-size: 12px; color: #38bdf8; margin-top: 6px;">Rs. 50 bonus wallet credit upon first ride!</div>
    </div>""" if referral_code else ""

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Download Ziggo - Super App</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0a1026; color: #fff; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px; box-sizing: border-box; }}
    .card {{ background: #131b38; border: 1px solid rgba(255,255,255,0.1); border-radius: 24px; padding: 40px; max-width: 440px; width: 100%; text-align: center; box-shadow: 0 20px 40px rgba(0,0,0,0.4); }}
    .logo {{ font-size: 32px; font-weight: 900; color: #1e88e5; letter-spacing: -1px; margin-bottom: 8px; }}
    .sub {{ color: #94a3b8; font-size: 15px; margin-bottom: 28px; line-height: 1.5; }}
    .badge-box {{ background: rgba(30,136,229,0.1); border: 1px solid rgba(30,136,229,0.3); border-radius: 16px; padding: 16px; margin-bottom: 24px; }}
    .badge-title {{ font-size: 11px; text-transform: uppercase; letter-spacing: 1px; color: #94a3b8; font-weight: 700; margin-bottom: 4px; }}
    .ref-code {{ font-size: 26px; font-weight: 900; color: #60a5fa; letter-spacing: 3px; font-family: monospace; }}
    .btn {{ display: block; padding: 15px; border-radius: 14px; text-decoration: none; font-weight: 700; font-size: 15px; margin-bottom: 12px; transition: all 0.2s; }}
    .btn-play {{ background: #1e88e5; color: #fff; }}
    .btn-play:hover {{ background: #1976d2; }}
    .btn-app {{ background: rgba(255,255,255,0.08); color: #fff; border: 1px solid rgba(255,255,255,0.15); }}
    .btn-app:hover {{ background: rgba(255,255,255,0.15); }}
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">Ziggo</div>
    <p class="sub">Ride, Food, Market & Flash Delivery — All in one super app for Sri Lanka.</p>
    {ref_box}
    <a href="{play_url}" class="btn btn-play">Get it on Google Play</a>
    <a href="{app_store_url}" class="btn btn-app">Download on App Store</a>
  </div>
  <script>
    if (navigator.clipboard && '{referral_code}') {{
      navigator.clipboard.writeText('{referral_code}').catch(() => {{}});
    }}
  </script>
</body>
</html>"""
    return HTMLResponse(content=html)


@app.exception_handler(_AdminRedirect)
async def admin_redirect_handler(request: Request, exc: _AdminRedirect):
    return RedirectResponse(url="/admin/login", status_code=303)


@app.exception_handler(_AdminForbidden)
async def admin_forbidden_handler(request: Request, exc: _AdminForbidden):
    if "json" in request.headers.get("accept", "") or request.url.path.startswith("/api/"):
        from fastapi.responses import JSONResponse
        return JSONResponse(status_code=403, content={"detail": "Access denied: Insufficient permissions"})
    return RedirectResponse(url="/admin/forbidden", status_code=303)


@app.exception_handler(HTTPException)
async def admin_http_exception_handler(request: Request, exc: HTTPException):
    accept = request.headers.get("accept", "")
    if (request.url.path.startswith("/admin/") 
            and not request.url.path.startswith("/admin-api/")
            and "json" not in accept):
        referer = request.headers.get("referer") or "/admin/market-home"
        import urllib.parse
        parsed_referer = urllib.parse.urlparse(referer)
        redirect_path = parsed_referer.path or "/admin/market-home"
        
        # Keep existing query params and update/add 'error'
        query_params = urllib.parse.parse_qs(parsed_referer.query)
        query_params["error"] = [exc.detail]
        new_query = urllib.parse.urlencode(query_params, doseq=True)
        
        return RedirectResponse(url=f"{redirect_path}?{new_query}", status_code=303)
        
    # Standard JSON handling for everything else
    from fastapi.responses import JSONResponse
    return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})



# JSON API
app.include_router(auth.router, prefix=f"{settings.API_V1_STR}/auth", tags=["auth"])
app.include_router(customer.router, prefix=f"{settings.API_V1_STR}/customer", tags=["customer"])
app.include_router(driver.router, prefix=f"{settings.API_V1_STR}/driver", tags=["driver"])
app.include_router(bookings.router, prefix=f"{settings.API_V1_STR}/bookings", tags=["bookings"])
app.include_router(food.router, prefix=f"{settings.API_V1_STR}/food", tags=["food"])
app.include_router(market.router, prefix=f"{settings.API_V1_STR}/market", tags=["market"])
app.include_router(restaurant.router, prefix=f"{settings.API_V1_STR}/restaurant", tags=["restaurant"])
app.include_router(market_vendor.router, prefix=f"{settings.API_V1_STR}/market/vendor", tags=["market_vendor"])
app.include_router(event.router, prefix=f"{settings.API_V1_STR}/events", tags=["events"])
app.include_router(admin.router, prefix=f"{settings.API_V1_STR}/admin", tags=["admin"])
app.include_router(misc.router, prefix=settings.API_V1_STR, tags=["misc"])
app.include_router(public.router, prefix=f"{settings.API_V1_STR}/public", tags=["public"])
app.include_router(payments.router, prefix=f"{settings.API_V1_STR}/payments", tags=["payments"])
app.include_router(trip_share.router, prefix=settings.API_V1_STR, tags=["trip_share"])
app.include_router(ws.router, tags=["ws"])
app.include_router(corporate.router, prefix=settings.API_V1_STR, tags=["corporate"])
app.include_router(surge_zones.router, prefix=f"{settings.API_V1_STR}/surge-zones", tags=["surge_zones"])

# Admin panel static + templates. The admin_panel package now lives as a
# top-level sibling of `app/` (under /app/ziggo_admin_panel/). main.py is
# at /app/app/main.py — go up one to /app then into ziggo_admin_panel.
current_dir = os.path.dirname(os.path.abspath(__file__))
static_dir = os.path.abspath(
    os.path.join(current_dir, "..", "ziggo_admin_panel", "static")
)
if os.path.isdir(static_dir):
    app.mount("/static", StaticFiles(directory=static_dir), name="static")

app.include_router(admin_panel_routes.router, prefix="/admin", tags=["admin_panel"])

# JSON API for the new React admin (separate, read-only; live /admin unaffected)
from ziggo_admin_panel import api_react as admin_react_api  # noqa: E402
app.include_router(admin_react_api.router, prefix="/admin-api", tags=["admin_react"])
