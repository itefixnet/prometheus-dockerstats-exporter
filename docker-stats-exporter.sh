#!/bin/bash

# Prometheus Docker Stats Exporter
# A bash-based exporter that collects Docker container statistics
# and exposes them as Prometheus metrics via HTTP

set -euo pipefail

# Default configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/docker-stats-exporter.conf"
METRICS_FILE="${SCRIPT_DIR}/metrics.prom"
METRICS_TEMP="${METRICS_FILE}.tmp"
PID_FILE="${SCRIPT_DIR}/docker-stats-exporter.pid"
LOG_FILE="${SCRIPT_DIR}/docker-stats-exporter.log"

# Default values
PORT=9417
INTERVAL=15
LOG_LEVEL="INFO"
BIND_ADDRESS="0.0.0.0"

# Load configuration if exists
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Override with command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            PORT="$2"
            shift 2
            ;;
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        --log-level)
            LOG_LEVEL="$2"
            shift 2
            ;;
        --bind-address)
            BIND_ADDRESS="$2"
            shift 2
            ;;
        --config)
            CONFIG_FILE="$2"
            # shellcheck source=/dev/null
            source "$CONFIG_FILE"
            shift 2
            ;;
        --test-server)
            TEST_MODE="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --port PORT           Port to expose metrics on (default: 9417)"
            echo "  --interval SECONDS    Collection interval in seconds (default: 15)"
            echo "  --log-level LEVEL     Log level: DEBUG, INFO, WARN, ERROR (default: INFO)"
            echo "  --bind-address ADDR   Address to bind to (default: 0.0.0.0)"
            echo "  --config FILE         Configuration file path"
            echo "  --test-server         Test HTTP server without Docker (for debugging)"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Check if we should log this level
    case "$LOG_LEVEL" in
        "DEBUG") level_num=0 ;;
        "INFO") level_num=1 ;;
        "WARN") level_num=2 ;;
        "ERROR") level_num=3 ;;
        *) level_num=1 ;;
    esac
    
    case "$level" in
        "DEBUG") msg_num=0 ;;
        "INFO") msg_num=1 ;;
        "WARN") msg_num=2 ;;
        "ERROR") msg_num=3 ;;
        *) msg_num=1 ;;
    esac
    
    if [[ $msg_num -ge $level_num ]]; then
        echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    fi
}

# Cleanup function
cleanup() {
    # Prevent multiple cleanup calls
    if [[ "${CLEANUP_DONE:-}" == "true" ]]; then
        return 0
    fi
    CLEANUP_DONE="true"
    
    log "INFO" "Shutting down exporter..."
    
    # Kill HTTP server if running
    if [[ -f "$PID_FILE" ]]; then
        local server_pid
        server_pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
            log "INFO" "Stopping HTTP server (PID: $server_pid)"
            kill "$server_pid" 2>/dev/null || true
            # Wait a bit for graceful shutdown
            sleep 1
        fi
        rm -f "$PID_FILE"
    fi
    
    # Clean up temp files
    rm -f "$METRICS_TEMP"
    
    log "INFO" "Exporter stopped"
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT EXIT

# Convert size to bytes
size_to_bytes() {
    local size_str="$1"
    
    # Remove any whitespace
    size_str=$(echo "$size_str" | tr -d ' ')
    
    # Handle special cases
    if [[ "$size_str" == "0B" || "$size_str" == "--" || -z "$size_str" ]]; then
        echo "0"
        return
    fi
    
    # Extract number and unit
    local number
    local unit
    if [[ "$size_str" =~ ^([0-9]*\.?[0-9]+)([a-zA-Z]+)$ ]]; then
        number="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]}"
    else
        echo "0"
        return
    fi
    
    # Convert to bytes
    local bytes
    case "$unit" in
        "B") bytes=$(echo "$number * 1" | bc -l) ;;
        "kB"|"KB") bytes=$(echo "$number * 1000" | bc -l) ;;
        "KiB") bytes=$(echo "$number * 1024" | bc -l) ;;
        "MB") bytes=$(echo "$number * 1000000" | bc -l) ;;
        "MiB") bytes=$(echo "$number * 1048576" | bc -l) ;;
        "GB") bytes=$(echo "$number * 1000000000" | bc -l) ;;
        "GiB") bytes=$(echo "$number * 1073741824" | bc -l) ;;
        "TB") bytes=$(echo "$number * 1000000000000" | bc -l) ;;
        "TiB") bytes=$(echo "$number * 1099511627776" | bc -l) ;;
        *) bytes="0" ;;
    esac
    
    # Return as integer
    printf "%.0f" "$bytes"
}

# Parse percentage
parse_percentage() {
    local percent_str="$1"
    
    if [[ "$percent_str" == "--" || -z "$percent_str" ]]; then
        echo "0"
        return
    fi
    
    # Remove % sign and return
    echo "$percent_str" | sed 's/%$//'
}

# Parse network/block IO
parse_io() {
    local io_str="$1"
    
    if [[ "$io_str" == "--" || -z "$io_str" ]]; then
        echo "0 0"
        return
    fi
    
    # Split by " / "
    local rx tx
    if [[ "$io_str" =~ ^(.+)\ /\ (.+)$ ]]; then
        rx=$(size_to_bytes "${BASH_REMATCH[1]}")
        tx=$(size_to_bytes "${BASH_REMATCH[2]}")
        echo "$rx $tx"
    else
        echo "0 0"
    fi
}

# Parse memory usage
parse_memory() {
    local mem_str="$1"
    
    if [[ "$mem_str" == "--" || -z "$mem_str" ]]; then
        echo "0 0"
        return
    fi
    
    # Split by " / "
    local usage limit
    if [[ "$mem_str" =~ ^(.+)\ /\ (.+)$ ]]; then
        usage=$(size_to_bytes "${BASH_REMATCH[1]}")
        limit=$(size_to_bytes "${BASH_REMATCH[2]}")
        echo "$usage $limit"
    else
        echo "0 0"
    fi
}

# Collect Docker stats and generate metrics
collect_metrics() {
    log "DEBUG" "Collecting Docker stats..."
    
    # Get docker stats output
    local docker_output
    if ! docker_output=$(docker stats --no-stream --format "table {{.Container}}\t{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}" 2>/dev/null); then
        log "WARN" "Failed to get Docker stats. Possible causes:"
        log "WARN" "  1. No containers running"
        log "WARN" "  2. Docker permission denied" 
        log "WARN" "  3. Docker daemon not responding"
        log "WARN" "Will retry in ${INTERVAL}s..."
        return 1
    fi
    
    # Create complete metrics file with all metric types and data in one pass
    cat > "$METRICS_TEMP" << 'EOF'
# HELP docker_container_cpu_usage_percent CPU usage percentage of the container
# TYPE docker_container_cpu_usage_percent gauge

# HELP docker_container_memory_usage_bytes Memory usage in bytes
# TYPE docker_container_memory_usage_bytes gauge

# HELP docker_container_memory_limit_bytes Memory limit in bytes
# TYPE docker_container_memory_limit_bytes gauge

# HELP docker_container_memory_usage_percent Memory usage percentage
# TYPE docker_container_memory_usage_percent gauge

# HELP docker_container_network_rx_bytes_total Total network bytes received
# TYPE docker_container_network_rx_bytes_total gauge

# HELP docker_container_network_tx_bytes_total Total network bytes transmitted
# TYPE docker_container_network_tx_bytes_total gauge

# HELP docker_container_block_io_read_bytes_total Total block I/O bytes read
# TYPE docker_container_block_io_read_bytes_total gauge

# HELP docker_container_block_io_write_bytes_total Total block I/O bytes written
# TYPE docker_container_block_io_write_bytes_total gauge

# HELP docker_container_pids Number of PIDs in the container
# TYPE docker_container_pids gauge

EOF

    # Process each container once and generate all metrics
    local line_count=0
    local container_count=0
    while IFS=$'\t' read -r container_id container_name cpu_perc mem_usage mem_perc net_io block_io pids; do
        ((line_count++))
        
        # Skip header line
        if [[ $line_count -eq 1 ]]; then
            continue
        fi
        
        # Skip empty lines
        if [[ -z "$container_id" ]]; then
            continue
        fi
        
        ((container_count++))
        
        log "DEBUG" "Processing container: $container_name ($container_id)"
        
        # Parse all values once
        local cpu_value
        cpu_value=$(parse_percentage "$cpu_perc")
        
        local mem_values
        mem_values=$(parse_memory "$mem_usage")
        local mem_usage_bytes mem_limit_bytes
        read -r mem_usage_bytes mem_limit_bytes <<< "$mem_values"
        
        local mem_perc_value
        mem_perc_value=$(parse_percentage "$mem_perc")
        
        local net_values
        net_values=$(parse_io "$net_io")
        local net_rx net_tx
        read -r net_rx net_tx <<< "$net_values"
        
        local block_values
        block_values=$(parse_io "$block_io")
        local block_read block_write
        read -r block_read block_write <<< "$block_values"
        
        local pids_value
        pids_value="${pids:-0}"
        
        # Generate metrics with proper escaping for labels
        local safe_container_id safe_container_name
        safe_container_id=$(echo "$container_id" | sed 's/"/\\"/g')
        safe_container_name=$(echo "$container_name" | sed 's/"/\\"/g')
        
        # Generate ALL metrics for this container at once
        {
            echo "docker_container_cpu_usage_percent{container_id=\"$safe_container_id\",container_name=\"$safe_container_name\"} $cpu_value"
            echo "docker_container_memory_usage_bytes{container_id=\"$safe_container_id\",container_name=\"$safe_container_name\"} $mem_usage_bytes"
            echo "docker_container_memory_limit_bytes{container_id=\"$safe_container_id\",container_name=\"$safe_container_name\"} $mem_limit_bytes"
            echo "docker_container_memory_usage_percent{container_id=\"$safe_container_id\",container_name=\"$safe_container_name\"} $mem_perc_value"
            echo "docker_container_network_rx_bytes_total{container_id=\"$safe_container_id\",container_name=\"$safe_container_name\"} $net_rx"
            echo "docker_container_network_tx_bytes_total{container_id=\"$safe_container_id\",container_name=\"$safe_container_name\"} $net_tx"
            echo "docker_container_block_io_read_bytes_total{container_id=\"$safe_container_id\",container_name=\"$safe_container_name\"} $block_read"
            echo "docker_container_block_io_write_bytes_total{container_id=\"$safe_container_id\",container_name=\"$safe_container_name\"} $block_write"
            echo "docker_container_pids{container_id=\"$safe_container_id\",container_name=\"$safe_container_name\"} $pids_value"
        } >> "$METRICS_TEMP"
        
    done <<< "$docker_output"
    
    # Log container count
    if [[ $container_count -eq 0 ]]; then
        log "INFO" "No running containers found"
    else
        log "DEBUG" "Processed $container_count containers"
    fi
    

    
    # Add exporter metadata
    local timestamp
    timestamp=$(date +%s)
    cat >> "$METRICS_TEMP" << EOF

# HELP docker_stats_exporter_up Exporter status (1=up, 0=down)
# TYPE docker_stats_exporter_up gauge
docker_stats_exporter_up 1

# HELP docker_stats_exporter_last_scrape_timestamp_seconds Last time metrics were scraped
# TYPE docker_stats_exporter_last_scrape_timestamp_seconds gauge
docker_stats_exporter_last_scrape_timestamp_seconds $timestamp

# HELP docker_stats_exporter_scrape_duration_seconds Time spent scraping metrics
# TYPE docker_stats_exporter_scrape_duration_seconds gauge
docker_stats_exporter_scrape_duration_seconds $(echo "scale=3; $SECONDS" | bc -l)
EOF
    
    # Atomically replace metrics file
    mv "$METRICS_TEMP" "$METRICS_FILE"
    
    log "DEBUG" "Metrics updated successfully (file: $METRICS_FILE)"
}

# Start HTTP server using netcat
start_http_server() {
    log "INFO" "Starting HTTP server on $BIND_ADDRESS:$PORT"
    
    # Test if port is available first
    if command -v netstat >/dev/null 2>&1; then
        if netstat -ln 2>/dev/null | grep -q ":$PORT "; then
            log "ERROR" "Port $PORT is already in use"
            exit 1
        fi
    fi
    
    # Create a simple HTTP server using socat or netcat
    if command -v socat >/dev/null 2>&1; then
        log "INFO" "Using socat for HTTP server"
        # Use socat if available (more robust)
        socat TCP-LISTEN:$PORT,bind=$BIND_ADDRESS,reuseaddr,fork EXEC:'bash -c "
            echo \"HTTP/1.1 200 OK\"
            echo \"Content-Type: text/plain; version=0.0.4; charset=utf-8\"
            echo \"Connection: close\"
            echo \"\"
            if [[ -f \"'$METRICS_FILE'\" ]]; then
                cat \"'$METRICS_FILE'\"
            else
                echo \"# Metrics not available yet\"
            fi
        "' &
        SERVER_PID=$!
    elif command -v nc >/dev/null 2>&1; then
        log "INFO" "Using netcat for HTTP server"
        # Fallback to netcat - improved approach
        while true; do
            {
                echo "HTTP/1.1 200 OK"
                echo "Content-Type: text/plain; version=0.0.4; charset=utf-8" 
                echo "Content-Length: $(wc -c < "$METRICS_FILE" 2>/dev/null || echo 0)"
                echo "Connection: close"
                echo ""
                if [[ -f "$METRICS_FILE" ]]; then
                    cat "$METRICS_FILE"
                else
                    echo "# Metrics not available yet"
                fi
            } | nc -l -p "$PORT" 2>/dev/null || {
                log "WARN" "HTTP server connection error, restarting listener"
                sleep 1
            }
        done &
        SERVER_PID=$!
    else
        log "ERROR" "Neither socat nor netcat (nc) found. Cannot start HTTP server."
        exit 1
    fi
    
    # Save server PID
    echo "$SERVER_PID" > "$PID_FILE"
    log "INFO" "HTTP server started with PID: $SERVER_PID"
    log "INFO" "Metrics available at: http://$BIND_ADDRESS:$PORT/metrics"
    
    # Give server a moment to start
    sleep 2
}

# Check basic dependencies (required for startup)
check_basic_dependencies() {
    log "INFO" "Checking basic dependencies..."
    
    # Check for bc (calculator)
    if ! command -v bc >/dev/null 2>&1; then
        log "ERROR" "bc (calculator) not found. Please install bc package."
        exit 1
    fi
    
    # Check for socat or netcat
    if ! command -v socat >/dev/null 2>&1 && ! command -v nc >/dev/null 2>&1; then
        log "ERROR" "Neither socat nor netcat found. Please install one of them."
        exit 1
    fi
    
    log "INFO" "Basic dependencies satisfied"
}

# Check Docker availability (non-fatal)
check_docker() {
    # Check for Docker
    if ! command -v docker >/dev/null 2>&1; then
        log "WARN" "Docker not found. Please install Docker."
        return 1
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log "WARN" "Cannot connect to Docker daemon. Common causes:"
        log "WARN" "  1. Docker is not running"
        log "WARN" "  2. User lacks permission to access Docker socket"
        log "WARN" "  3. Add user to docker group: sudo usermod -a -G docker \$USER"
        log "WARN" "  4. Restart session or run: newgrp docker"
        return 1
    fi
    
    return 0
}

# Main function
main() {
    log "INFO" "Starting Prometheus Docker Stats Exporter"
    log "INFO" "Configuration: Port=$PORT, Interval=${INTERVAL}s, LogLevel=$LOG_LEVEL"
    
    # Test mode - just run HTTP server without Docker
    if [[ "${TEST_MODE:-}" == "true" ]]; then
        log "INFO" "Running in test mode (no Docker required)"
        
        # Create a simple test metrics file
        cat > "$METRICS_FILE" << 'EOF'
# HELP test_metric A test metric for server verification
# TYPE test_metric gauge
test_metric{status="ok"} 1

# HELP http_server_up HTTP server status
# TYPE http_server_up gauge  
http_server_up 1
EOF
        
        log "INFO" "Created test metrics file"
        
        # Start HTTP server
        start_http_server
        
        log "INFO" "Test server running. Try: curl http://localhost:$PORT/metrics"
        log "INFO" "Press Ctrl+C to stop"
        
        # Keep running until interrupted
        while true; do
            sleep 1
        done
        
        return 0
    fi
    
    # Normal mode - check basic dependencies first
    check_basic_dependencies
    
    # Check Docker availability (but don't exit if not available)
    if check_docker; then
        log "INFO" "Docker is available"
    else
        log "WARN" "Docker is not available - will serve error metrics and retry"
    fi
    
    # Initialize metrics file
    touch "$METRICS_FILE"
    
    # Start HTTP server
    start_http_server
    
    # Main collection loop
    log "INFO" "Starting metrics collection loop (interval: ${INTERVAL}s)"
    log "INFO" "Press Ctrl+C to stop"
    
    while true; do
        local start_time
        start_time=$(date +%s.%N)
        
        # Try to collect metrics, but don't exit if it fails
        if collect_metrics; then
            log "DEBUG" "Metrics collection successful"
        else
            log "WARN" "Metrics collection failed, will retry in ${INTERVAL}s"
            # Create empty metrics file so HTTP server has something to serve
            cat > "$METRICS_FILE" << EOF
# HELP docker_stats_exporter_up Exporter status (1=up, 0=down)
# TYPE docker_stats_exporter_up gauge
docker_stats_exporter_up 0

# HELP docker_stats_exporter_last_error_timestamp_seconds Timestamp of last error
# TYPE docker_stats_exporter_last_error_timestamp_seconds gauge
docker_stats_exporter_last_error_timestamp_seconds $(date +%s)
EOF
        fi
        
        local end_time
        end_time=$(date +%s.%N)
        local duration
        duration=$(echo "$end_time - $start_time" | bc -l)
        
        log "DEBUG" "Collection cycle completed in ${duration}s"
        
        # Calculate sleep time
        local sleep_time
        sleep_time=$(echo "$INTERVAL - $duration" | bc -l)
        
        if (( $(echo "$sleep_time > 0" | bc -l) )); then
            sleep "$sleep_time"
        else
            log "WARN" "Collection took ${duration}s, longer than interval ${INTERVAL}s"
        fi
    done
}

# Run main function
main "$@"