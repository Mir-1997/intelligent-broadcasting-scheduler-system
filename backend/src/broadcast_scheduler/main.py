"""FastAPI application factory and entry point.

Run locally with::

    uv run fastapi dev src/broadcast_scheduler/main.py
"""

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from broadcast_scheduler import __version__
from broadcast_scheduler.api import (
    admin_router,
    packages_router,
    riders_router,
    scheduler_router,
    ws_router,
)
from broadcast_scheduler.config import Settings, get_settings
from broadcast_scheduler.exceptions import ConflictError, NotFoundError
from broadcast_scheduler.realtime import EventHub
from broadcast_scheduler.repositories import SchedulerRepository, build_repository
from broadcast_scheduler.service import SchedulerService

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

DESCRIPTION = """
Packages and riders enter the scheduler. Every arrival is **instantly paired** with the
nearest counterpart (haversine distance, within `MAX_MATCH_RADIUS_MILES`); paired items
leave the scheduler and an assignment is recorded.

Live changes are streamed over the **`/ws/scheduler`** WebSocket; see
`docs/websocket-events.md` for the event contract.
"""


def create_app(
    settings: Settings | None = None, repository: SchedulerRepository | None = None
) -> FastAPI:
    """Build the app. Tests inject ``settings`` and/or ``repository``."""
    settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        repo = repository or build_repository(settings)
        hub = EventHub(max_queue=settings.websocket_queue_size)
        service = SchedulerService(repo, hub, settings)
        await service.ensure_admin()
        app.state.hub = hub
        app.state.service = service
        try:
            yield
        finally:
            await repo.close()

    app = FastAPI(
        title=settings.app_name,
        version=__version__,
        description=DESCRIPTION,
        lifespan=lifespan,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.exception_handler(NotFoundError)
    async def not_found(_: Request, exc: NotFoundError) -> JSONResponse:
        return JSONResponse(status_code=404, content={"detail": str(exc)})

    @app.exception_handler(ConflictError)
    async def conflict(_: Request, exc: ConflictError) -> JSONResponse:
        return JSONResponse(status_code=409, content={"detail": str(exc)})

    for router in (admin_router, packages_router, riders_router, scheduler_router, ws_router):
        app.include_router(router)
    return app


app = create_app()


def run() -> None:
    """Console-script entry point (``uv run broadcast-scheduler``)."""
    import uvicorn

    # A single worker is required: the WebSocket hub is in-process (see realtime.py).
    uvicorn.run("broadcast_scheduler.main:app", host="0.0.0.0", port=8000, workers=1, reload=False)
