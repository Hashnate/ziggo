import asyncio
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles

from fastapi import Request
from fastapi.responses import RedirectResponse

from .config import settings
from .database import engine
from .api.v1 import auth, customer, driver, admin, bookings, ws, event, food, market, market_vendor, misc, restaurant, trip_share
from .admin_panel import routes as admin_panel_routes
from .admin_panel.routes import _AdminRedirect
from .services.schema_sync import ensure_schema
from .services.auto_cancel import auto_cancel_loop

app = FastAPI(
    title=settings.PROJECT_NAME,
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
)


_background_tasks: set[asyncio.Task] = set()


@app.on_event("startup")
async def _run_schema_sync() -> None:
    await ensure_schema(engine)


@app.on_event("startup")
async def _launch_background_tasks() -> None:
    """Spin up the food-order auto-cancel sweeper. Held in a set so the GC
    doesn't reap the task reference."""
    task = asyncio.create_task(auto_cancel_loop())
    _background_tasks.add(task)
    task.add_done_callback(_background_tasks.discard)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    return RedirectResponse(url="/admin/login")


@app.get("/health")
async def health():
    return {"status": "ok", "service": settings.PROJECT_NAME}


@app.exception_handler(_AdminRedirect)
async def admin_redirect_handler(request: Request, exc: _AdminRedirect):
    return RedirectResponse(url="/admin/login", status_code=303)


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
app.include_router(trip_share.router, prefix=settings.API_V1_STR, tags=["trip_share"])
app.include_router(ws.router, tags=["ws"])

# Admin panel static + templates
current_dir = os.path.dirname(os.path.abspath(__file__))
static_dir = os.path.join(current_dir, "admin_panel", "static")
if os.path.isdir(static_dir):
    app.mount("/static", StaticFiles(directory=static_dir), name="static")

app.include_router(admin_panel_routes.router, prefix="/admin", tags=["admin_panel"])
