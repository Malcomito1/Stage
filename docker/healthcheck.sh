#!/bin/sh
# Health of every component this container runs. Prints which one failed.
fail=0

if ! curl -fsS -m 3 -o /dev/null http://127.0.0.1:3000/vnc.html; then
	echo "unhealthy: noVNC web entry (port 3000) is not responding"
	fail=1
fi

if ! pgrep -f "Xvfb :1" >/dev/null; then
	echo "unhealthy: Xvfb virtual display :1 is not running"
	fail=1
fi

if ! pgrep -x x11vnc >/dev/null; then
	echo "unhealthy: x11vnc VNC server is not running"
	fail=1
fi

if ! pgrep -x stage >/dev/null; then
	echo "unhealthy: stage simulator is not running"
	fail=1
fi

exit $fail
