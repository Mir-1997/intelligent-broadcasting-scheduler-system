from broadcast_scheduler.models import EventType, SchedulerEvent
from broadcast_scheduler.realtime import EventHub


def _event() -> SchedulerEvent:
    return SchedulerEvent(type=EventType.SCHEDULER_RESET, data={})


async def test_publish_reaches_all_subscribers():
    hub = EventHub()
    a, b = hub.subscribe(), hub.subscribe()
    hub.publish(_event())
    assert (await a.next_message()) == (await b.next_message())


async def test_unsubscribed_client_gets_nothing():
    hub = EventHub()
    sub = hub.subscribe()
    hub.unsubscribe(sub)
    hub.publish(_event())
    assert sub.queue.empty()
    assert hub.subscriber_count == 0


async def test_slow_client_is_closed_on_overflow():
    hub = EventHub(max_queue=2)
    sub = hub.subscribe()
    for _ in range(5):
        hub.publish(_event())
    assert sub.closed
    messages = [sub.queue.get_nowait() for _ in range(sub.queue.qsize())]
    assert messages[-1] is None  # close sentinel
    assert len(messages) == 3
