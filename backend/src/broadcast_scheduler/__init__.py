"""Intelligent Broadcasting Scheduler backend.

Packages and riders enter the scheduler; each new arrival is instantly paired with the
nearest counterpart within the configured radius, and every change is streamed to
connected clients over a WebSocket.
"""

__version__ = "0.1.0"
