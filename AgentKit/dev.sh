#!/bin/bash
# Dev script to kill any existing Envoy instance and restart

echo "Stopping existing Envoy..."
pkill -9 -f "Envoy" 2>/dev/null
killall -9 Envoy 2>/dev/null
sleep 1

echo "Building and launching Envoy..."
swift run Envoy "$@" &

sleep 8
echo "Envoy launched"
