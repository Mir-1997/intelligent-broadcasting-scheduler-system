"""In-process fan-out of scheduler events to WebSocket clients.

Each connected client gets its own bounded queue. ``publish`` only enqueues (it never
awaits a socket), so one slow browser can never stall a request that is adding a package.
A client whose queue overflows is disconnected; on reconnect it receives a fresh
snapshot, so it can never silently drift out of sync.

Scaling note: the hub lives in process memory, so run a single API worker. See
docs/adr/0002-realtime-websockets.md for the multi-instance path.
"""

import asyncio
import logging

from broadcast_scheduler.models import SchedulerEvent

logger = logging.getLogger(__name__)


class Subscription:
    """One client's mailbox. ``None`` in the queue means 'close this connection'."""

    def __init__(self, max_queue: int) -> None:
        self.queue: asyncio.Queue[str | None] = asyncio.Queue(maxsize=max_queue + 1)
        self._max_queue = max_queue
        self.closed = False

    def offer(self, message: str) -> None:
        if self.closed:
            return
        if self.queue.qsize() >= self._max_queue:
            logger.warning("WebSocket client too slow; disconnecting it")
            self.closed = True
            self.queue.put_nowait(None)  # the +1 slot guarantees room for the sentinel
            return
        self.queue.put_nowait(message)

    async def next_message(self) -> str | None:
        return await self.queue.get()


class EventHub:
    def __init__(self, max_queue: int = 1000) -> None:
        self._subscriptions: set[Subscription] = set()
        self._max_queue = max_queue

    @property
    def subscriber_count(self) -> int:
        return len(self._subscriptions)

    def subscribe(self) -> Subscription:
        """Register a client. Events published from now on are queued for it."""
        subscription = Subscription(self._max_queue)
        self._subscriptions.add(subscription)
        return subscription

    def unsubscribe(self, subscription: Subscription) -> None:
        self._subscriptions.discard(subscription)

    def publish(self, event: SchedulerEvent) -> None:
        """Queue ``event`` for every subscriber. Serialised once, shared by all."""
        message = event.model_dump_json()
        for subscription in list(self._subscriptions):
            subscription.offer(message)
