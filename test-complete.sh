#!/bin/bash

# Complete test of the Docker stats exporter HTTP server

echo "🌐 Testing Docker Stats Exporter HTTP Server"
echo "============================================="

PORT=9418
TEST_URL="http://localhost:$PORT/metrics"

echo "Starting exporter in test mode..."
echo "Port: $PORT"
echo "URL: $TEST_URL"
echo ""

# Start the exporter in background
./docker-stats-exporter.sh --test-server --port $PORT --log-level INFO &
EXPORTER_PID=$!

echo "Exporter started with PID: $EXPORTER_PID"
echo "Waiting for server to initialize..."

# Wait for server to start
sleep 5

# Test the HTTP endpoint
echo ""
echo "Testing HTTP endpoint..."
echo "========================"

# First test - check if server responds
if curl -s --connect-timeout 5 "$TEST_URL" >/dev/null; then
    echo "✅ Server is responding!"
    echo ""
    echo "📊 Metrics content:"
    echo "-------------------"
    curl -s "$TEST_URL"
    echo ""
    echo "-------------------"
else
    echo "❌ Server is not responding"
fi

echo ""
echo "Server process info:"
ps aux | grep -E "(docker-stats-exporter|nc|socat)" | grep -v grep || echo "No processes found"

echo ""
echo "Port usage:"
netstat -ln 2>/dev/null | grep ":$PORT " || ss -ln 2>/dev/null | grep ":$PORT " || echo "Port status unknown"

# Clean up
echo ""
echo "🧹 Cleaning up..."
kill $EXPORTER_PID 2>/dev/null || true
wait $EXPORTER_PID 2>/dev/null || true

# Also kill any lingering netcat processes
pkill -f "nc.*$PORT" 2>/dev/null || true

echo "Test completed!"
echo ""
echo "💡 To run the exporter interactively:"
echo "   ./docker-stats-exporter.sh --test-server --port 9418"
echo ""
echo "   Then in another terminal:"
echo "   curl http://localhost:9418/metrics"