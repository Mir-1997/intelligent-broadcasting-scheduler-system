"""Domain errors. The API layer maps them to HTTP status codes."""


class SchedulerError(Exception):
    """Base class for expected, user-facing errors."""


class NotFoundError(SchedulerError):
    """The requested entity does not exist (HTTP 404)."""


class ConflictError(SchedulerError):
    """The entity exists but is in the wrong state for the operation (HTTP 409)."""
