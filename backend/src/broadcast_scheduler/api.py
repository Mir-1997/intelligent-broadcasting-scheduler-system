"""HTTP and WebSocket routes. Thin: validate, call the service, return."""

import asyncio
import contextlib
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Request, WebSocket, WebSocketDisconnect, status

from broadcast_scheduler.models import (
    Admin,
    Assignment,
    Package,
    PackageAddResult,
    PackageCreate,
    PackageStatus,
    RadiusPolicy,
    Rider,
    RiderAddResult,
    RiderCreate,
    RiderStatus,
    SchedulerState,
    SimulationRequest,
    SimulationResult,
)
from broadcast_scheduler.realtime import EventHub
from broadcast_scheduler.service import SchedulerService


def get_service(request: Request) -> SchedulerService:
    return request.app.state.service


Service = Annotated[SchedulerService, Depends(get_service)]

_ERRORS = {404: {"description": "Not found"}, 409: {"description": "Already assigned"}}

# --------------------------------------------------------------------------------------
# Admin
# --------------------------------------------------------------------------------------

admin_router = APIRouter(prefix="/admin", tags=["admin"])


@admin_router.get("", response_model=Admin, summary="Get the admin (map centre)")
async def get_admin(service: Service) -> Admin:
    return await service.get_admin()


@admin_router.put("", response_model=Admin, summary="Update the admin name/location")
async def update_admin(admin: Admin, service: Service) -> Admin:
    return await service.update_admin(admin)


# --------------------------------------------------------------------------------------
# Packages
# --------------------------------------------------------------------------------------

packages_router = APIRouter(prefix="/packages", tags=["packages"])


@packages_router.post(
    "",
    response_model=PackageAddResult,
    status_code=status.HTTP_201_CREATED,
    summary="Add a package; it is paired instantly with the nearest rider in range",
)
async def add_package(body: PackageCreate, service: Service) -> PackageAddResult:
    return await service.add_package(body)


@packages_router.get("", response_model=list[Package], summary="List packages")
async def list_packages(
    service: Service, status: Annotated[PackageStatus | None, Query()] = None
) -> list[Package]:
    return await service.list_packages(status)


@packages_router.get("/{package_id}", response_model=Package, responses=_ERRORS)
async def get_package(package_id: str, service: Service) -> Package:
    return await service.get_package(package_id)


@packages_router.delete(
    "/{package_id}",
    response_model=Package,
    responses=_ERRORS,
    summary="Remove a waiting package from the scheduler",
)
async def delete_package(package_id: str, service: Service) -> Package:
    return await service.remove_package(package_id)


# --------------------------------------------------------------------------------------
# Riders
# --------------------------------------------------------------------------------------

riders_router = APIRouter(prefix="/riders", tags=["riders"])


@riders_router.post(
    "",
    response_model=RiderAddResult,
    status_code=status.HTTP_201_CREATED,
    summary="Add a rider; they are paired instantly with the nearest waiting package",
)
async def add_rider(body: RiderCreate, service: Service) -> RiderAddResult:
    return await service.add_rider(body)


@riders_router.get("", response_model=list[Rider], summary="List riders")
async def list_riders(
    service: Service, status: Annotated[RiderStatus | None, Query()] = None
) -> list[Rider]:
    return await service.list_riders(status)


@riders_router.get("/{rider_id}", response_model=Rider, responses=_ERRORS)
async def get_rider(rider_id: str, service: Service) -> Rider:
    return await service.get_rider(rider_id)


@riders_router.delete(
    "/{rider_id}",
    response_model=Rider,
    responses=_ERRORS,
    summary="Remove an available rider from the scheduler",
)
async def delete_rider(rider_id: str, service: Service) -> Rider:
    return await service.remove_rider(rider_id)


# --------------------------------------------------------------------------------------
# Settings
# --------------------------------------------------------------------------------------

settings_router = APIRouter(prefix="/settings", tags=["settings"])


@settings_router.get(
    "/radius", response_model=RadiusPolicy, summary="How waiting packages' search radius grows"
)
async def get_radius_policy(service: Service) -> RadiusPolicy:
    return await service.get_radius_policy()


@settings_router.put(
    "/radius",
    response_model=RadiusPolicy,
    summary="Change the radius policy; applies to every waiting package immediately",
)
async def update_radius_policy(policy: RadiusPolicy, service: Service) -> RadiusPolicy:
    return await service.update_radius_policy(policy)


# --------------------------------------------------------------------------------------
# Scheduler
# --------------------------------------------------------------------------------------

scheduler_router = APIRouter(tags=["scheduler"])


@scheduler_router.get(
    "/scheduler/state",
    response_model=SchedulerState,
    summary="Waiting packages and available riders (same payload as the WS snapshot)",
)
async def get_state(service: Service) -> SchedulerState:
    return await service.get_state()


@scheduler_router.post(
    "/scheduler/reset",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete all packages, riders and assignments (admin is kept)",
)
async def reset(service: Service) -> None:
    await service.reset()


@scheduler_router.get(
    "/assignments", response_model=list[Assignment], summary="Assignment history, newest first"
)
async def list_assignments(
    service: Service, limit: Annotated[int, Query(ge=1, le=500)] = 50
) -> list[Assignment]:
    return await service.list_assignments(limit)


@scheduler_router.post(
    "/simulate",
    response_model=SimulationResult,
    summary="Spawn random packages and riders around the admin",
)
async def simulate(body: SimulationRequest, service: Service) -> SimulationResult:
    return await service.simulate(body)


@scheduler_router.get("/health", tags=["meta"], summary="Liveness probe")
async def health() -> dict[str, str]:
    return {"status": "ok"}


# --------------------------------------------------------------------------------------
# WebSocket
# --------------------------------------------------------------------------------------

ws_router = APIRouter()


@ws_router.websocket("/ws/scheduler")
async def scheduler_socket(websocket: WebSocket) -> None:
    """Stream scheduler events.

    Protocol: the first message is always ``scheduler.snapshot`` (full state); every
    following message is a delta event. The client may send ``"ping"`` and gets ``"pong"``.

    The subscription is registered *before* the snapshot is read and queued events are
    only flushed *after* it is sent, so no event can be lost between the two.
    """
    service: SchedulerService = websocket.app.state.service
    hub: EventHub = websocket.app.state.hub

    await websocket.accept()
    subscription = hub.subscribe()
    try:
        snapshot = await service.snapshot_event()
        await websocket.send_text(snapshot.model_dump_json())

        async def pump() -> None:
            while (message := await subscription.next_message()) is not None:
                await websocket.send_text(message)
            await websocket.close(code=1013)  # "try again later": client was too slow

        async def listen() -> None:
            while True:
                if await websocket.receive_text() == "ping":
                    await websocket.send_text("pong")

        tasks = {asyncio.create_task(pump()), asyncio.create_task(listen())}
        try:
            await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        finally:
            for task in tasks:
                task.cancel()
            for task in tasks:
                with contextlib.suppress(asyncio.CancelledError, Exception):  # socket gone
                    await task
    except WebSocketDisconnect:
        pass
    finally:
        hub.unsubscribe(subscription)
