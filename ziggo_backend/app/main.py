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
