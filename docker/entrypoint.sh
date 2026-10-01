#!/bin/sh
# Dev entrypoint.
#
# 1. builds Stage from the bind-mounted source into a cached build dir
# 2. starts a virtual X display (Xvfb) + VNC server (x11vnc)
# 3. serves the FLTK/OpenGL GUI to the browser via noVNC on port 3000
# 4. runs the simulator in the foreground so its output lands in `docker logs`
#
# Stage is a native X11 application, so the browser view is a live view of the
# real GUI rather than a separate web frontend.
set -e

SRC=/src
BUILD="${STAGE_BUILD_DIR:-/build}"
PREFIX=/opt/stage
WORLD="${STAGE_WORLD:-worlds/simple.world}"

echo "[stage-dev] building Stage from $SRC (build dir $BUILD)"
cmake -S "$SRC" -B "$BUILD" \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX="$PREFIX" \
	-DBUILD_PLAYER_PLUGIN=OFF \
	-DCPACK_CFG=OFF
cmake --build "$BUILD" -j"$(nproc)"
cmake --install "$BUILD"

export DISPLAY=:1
export LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}"
export STAGEPATH="$PREFIX/lib"

echo "[stage-dev] starting Xvfb on :1"
Xvfb :1 -screen 0 1280x1024x24 -nolisten tcp -ac >/tmp/xvfb.log 2>&1 &

# wait for the X server to accept connections
i=0
while [ "$i" -lt 100 ]; do
	if xdpyinfo -display :1 >/dev/null 2>&1; then
		break
	fi
	i=$((i + 1))
	sleep 0.2
done
if ! xdpyinfo -display :1 >/dev/null 2>&1; then
	echo "[stage-dev] ERROR: Xvfb did not come up; see /tmp/xvfb.log" >&2
	cat /tmp/xvfb.log >&2
	exit 1
fi

echo "[stage-dev] starting x11vnc on :5900"
x11vnc -display :1 -forever -shared -nopw -rfbport 5900 -quiet >/tmp/x11vnc.log 2>&1 &

# noVNC's bundled viewer is served from a copy so we can drop an index.html in
# front of it that auto-connects to the VNC server on the same port.
NOVNC_SRC=/usr/share/novnc
WEB=/opt/novnc-web
rm -rf "$WEB"
mkdir -p "$WEB"
if [ ! -f "$NOVNC_SRC/vnc.html" ]; then
	echo "[stage-dev] ERROR: noVNC viewer not found in $NOVNC_SRC" >&2
	ls "$NOVNC_SRC" >&2 || true
	exit 1
fi
cp -r "$NOVNC_SRC/." "$WEB/"
cat >"$WEB/index.html" <<'HTML'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Stage Simulator</title>
  </head>
  <body>
    <script>
      location.replace("vnc.html?autoconnect=true&resize=scale&path=websockify");
    </script>
  </body>
</html>
HTML

echo "[stage-dev] starting noVNC web entry on port 3000"
websockify --web="$WEB" 3000 localhost:5900 >/tmp/novnc.log 2>&1 &

echo "[stage-dev] starting simulator: stage $WORLD"
cd "$SRC"
exec "$PREFIX/bin/stage" "$WORLD"
