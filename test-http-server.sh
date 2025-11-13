#!/bin/bash

# Simple HTTP server test for the Docker stats exporter

PORT=${1:-9418}
METRICS_FILE="./metrics.prom"

# Create test metrics
cat > "$METRICS_FILE" << 'EOF'
# HELP test_metric A test metric for server verification
# TYPE test_metric gauge
test_metric{status="ok"} 1

# HELP http_server_up HTTP server status  
# TYPE http_server_up gauge
http_server_up 1

# HELP current_time Current timestamp
# TYPE current_time gauge
EOF

echo "current_time $(date +%s)" >> "$METRICS_FILE"

echo "Starting simple HTTP server on port $PORT..."
echo "Metrics file content:"
echo "===================="
cat "$METRICS_FILE"
echo "===================="
echo ""
echo "Test with: curl http://localhost:$PORT/metrics"
echo "Press Ctrl+C to stop"
echo ""

# Simple HTTP server using netcat in a loop
while true; do
    echo "Waiting for connection on port $PORT..."
    (
        echo "HTTP/1.1 200 OK"
        echo "Content-Type: text/plain; charset=utf-8"
        echo "Content-Length: $(wc -c < "$METRICS_FILE")"
        echo "Connection: close"
        echo ""
        cat "$METRICS_FILE"
    ) | nc -l -p "$PORT" -q 1
    echo "Request served at $(date)"
done