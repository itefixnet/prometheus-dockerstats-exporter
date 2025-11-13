#!/bin/bash

# Test script for Prometheus Docker Stats Exporter (Bash version)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info "🧪 Testing Prometheus Docker Stats Exporter (Bash)"
echo "=================================================="

# Check if Docker is running
print_info "Checking Docker availability..."
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi
print_success "Docker is running"

# Check dependencies
print_info "Checking dependencies..."
missing_deps=()
for cmd in docker bc socat; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing_deps+=("$cmd")
    fi
done

if [[ ${#missing_deps[@]} -gt 0 ]]; then
    print_error "Missing dependencies: ${missing_deps[*]}"
    print_info "Install with: sudo apt-get install ${missing_deps[*]} (Ubuntu/Debian)"
    exit 1
fi
print_success "All dependencies available"

# Check if script exists and is executable
if [[ ! -f "docker-stats-exporter.sh" ]]; then
    print_error "docker-stats-exporter.sh not found in current directory"
    exit 1
fi

if [[ ! -x "docker-stats-exporter.sh" ]]; then
    print_info "Making script executable..."
    chmod +x docker-stats-exporter.sh
    print_success "Script is now executable"
fi

# Test script syntax
print_info "Testing script syntax..."
if bash -n docker-stats-exporter.sh; then
    print_success "Script syntax is valid"
else
    print_error "Script has syntax errors"
    exit 1
fi

# Start some test containers if none are running
CONTAINER_COUNT=$(docker ps -q | wc -l)
if [[ $CONTAINER_COUNT -eq 0 ]]; then
    print_info "Starting test containers for metrics collection..."
    
    # Start nginx container
    if docker run -d --name test-nginx-stats nginx:alpine >/dev/null 2>&1; then
        print_success "Started test nginx container"
    else
        print_warning "Failed to start nginx container (might already exist)"
    fi
    
    # Start redis container  
    if docker run -d --name test-redis-stats redis:alpine >/dev/null 2>&1; then
        print_success "Started test redis container"
    else
        print_warning "Failed to start redis container (might already exist)"
    fi
    
    # Wait for containers to start
    sleep 3
else
    print_info "Found $CONTAINER_COUNT running containers"
fi

# Test docker stats command directly
print_info "Testing docker stats command..."
if docker stats --no-stream --format "table {{.Container}}\t{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}" >/dev/null 2>&1; then
    print_success "Docker stats command works"
else
    print_error "Docker stats command failed"
    exit 1
fi

# Run exporter in background for testing
print_info "Starting exporter in test mode..."
TEST_PORT=9418
./docker-stats-exporter.sh --port $TEST_PORT --interval 5 --log-level DEBUG &
EXPORTER_PID=$!

# Function to cleanup test
cleanup_test() {
    print_info "Cleaning up test environment..."
    
    # Kill exporter
    if kill -0 $EXPORTER_PID 2>/dev/null; then
        kill $EXPORTER_PID
        wait $EXPORTER_PID 2>/dev/null || true
        print_success "Stopped test exporter"
    fi
    
    # Remove test containers
    for container in test-nginx-stats test-redis-stats; do
        if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
            docker rm -f $container >/dev/null 2>&1
            print_success "Removed test container: $container"
        fi
    done
    
    # Clean up test files
    rm -f metrics.prom metrics.prom.tmp docker-stats-exporter.pid docker-stats-exporter.log
}

# Set up cleanup trap
trap cleanup_test EXIT

# Wait for exporter to start and collect metrics
print_info "Waiting for metrics collection..."
sleep 8

# Test metrics endpoint
print_info "Testing metrics endpoint..."
if curl -s "http://localhost:$TEST_PORT/metrics" >/dev/null 2>&1; then
    print_success "Metrics endpoint is accessible"
else
    print_error "Metrics endpoint is not accessible"
    print_info "Exporter logs:"
    if [[ -f "docker-stats-exporter.log" ]]; then
        tail -10 docker-stats-exporter.log
    fi
    exit 1
fi

# Check if metrics contain expected data
print_info "Validating metrics content..."
METRICS_CONTENT=$(curl -s "http://localhost:$TEST_PORT/metrics")

# Check for required metrics
REQUIRED_METRICS=(
    "docker_container_cpu_usage_percent"
    "docker_container_memory_usage_bytes"
    "docker_container_memory_usage_percent"
    "docker_stats_exporter_last_scrape_timestamp_seconds"
)

for metric in "${REQUIRED_METRICS[@]}"; do
    if echo "$METRICS_CONTENT" | grep -q "$metric"; then
        print_success "Found metric: $metric"
    else
        print_error "Missing metric: $metric"
        exit 1
    fi
done

# Show sample metrics
print_info "Sample metrics output:"
echo "$METRICS_CONTENT" | head -15
echo "..."

print_success "🎉 All tests passed!"
echo ""
print_info "Next steps:"
echo "  1. Set up manually following README instructions"
echo "  2. Copy files to installation directory"
echo "  3. Configure and install systemd service"
echo "  4. Start service: sudo systemctl start docker-stats-exporter"
echo "  5. View metrics: curl http://localhost:9417/metrics"
echo ""
print_info "Manual testing:"
echo "  ./docker-stats-exporter.sh --help"
echo "  ./docker-stats-exporter.sh --port 9418 --log-level DEBUG"