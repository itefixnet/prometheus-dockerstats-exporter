#!/bin/bash

# Troubleshooting script for Prometheus Docker Stats Exporter

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

print_info "🔧 Docker Stats Exporter Troubleshooting"
echo "========================================"

# Check if script exists
print_info "Checking exporter script..."
if [[ -f "docker-stats-exporter.sh" ]]; then
    print_success "Exporter script found"
    if [[ -x "docker-stats-exporter.sh" ]]; then
        print_success "Script is executable"
    else
        print_warning "Script is not executable. Run: chmod +x docker-stats-exporter.sh"
    fi
else
    print_error "docker-stats-exporter.sh not found in current directory"
    exit 1
fi

# Check dependencies
print_info "Checking system dependencies..."
missing_deps=()
for cmd in docker bc socat; do
    if command -v "$cmd" >/dev/null 2>&1; then
        print_success "$cmd is installed"
    else
        print_error "$cmd is missing"
        missing_deps+=("$cmd")
    fi
done

if [[ ${#missing_deps[@]} -gt 0 ]]; then
    print_error "Missing dependencies: ${missing_deps[*]}"
    print_info "Install with:"
    print_info "  Ubuntu/Debian: sudo apt-get install ${missing_deps[*]}"
    print_info "  RHEL/CentOS: sudo yum install ${missing_deps[*]}"
    exit 1
fi

# Check Docker daemon
print_info "Checking Docker daemon..."
if systemctl is-active --quiet docker 2>/dev/null; then
    print_success "Docker service is running"
elif command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        print_success "Docker daemon is accessible"
    else
        print_error "Docker daemon is not accessible"
        print_info "Possible solutions:"
        print_info "  1. Start Docker: sudo systemctl start docker"
        print_info "  2. Add user to docker group: sudo usermod -a -G docker \$USER"
        print_info "  3. Restart session: newgrp docker"
        print_info "  4. Check Docker socket: ls -la /var/run/docker.sock"
    fi
else
    print_error "Docker command not found"
fi

# Check Docker permissions
print_info "Checking Docker permissions..."
if docker ps >/dev/null 2>&1; then
    print_success "Docker permissions OK"
    
    # Check for running containers
    container_count=$(docker ps -q | wc -l)
    if [[ $container_count -gt 0 ]]; then
        print_success "Found $container_count running containers"
    else
        print_warning "No running containers found"
        print_info "Start some containers for testing:"
        print_info "  docker run -d --name test-nginx nginx:alpine"
        print_info "  docker run -d --name test-redis redis:alpine"
    fi
else
    print_error "Cannot access Docker. Permission denied."
    print_info "Solutions:"
    print_info "  1. Add user to docker group: sudo usermod -a -G docker \$(whoami)"
    print_info "  2. Log out and log back in"
    print_info "  3. Or run: newgrp docker"
    print_info "  4. Check groups: groups \$(whoami)"
fi

# Test docker stats command
print_info "Testing docker stats command..."
if docker stats --no-stream --format "table {{.Container}}\t{{.Name}}" >/dev/null 2>&1; then
    print_success "Docker stats command works"
else
    print_error "Docker stats command failed"
fi

# Check port availability
PORT=${1:-9417}
print_info "Checking port $PORT availability..."
if command -v netstat >/dev/null 2>&1; then
    if netstat -ln 2>/dev/null | grep -q ":$PORT "; then
        print_warning "Port $PORT is already in use"
        print_info "Check what's using it: sudo netstat -tlnp | grep :$PORT"
    else
        print_success "Port $PORT is available"
    fi
elif command -v ss >/dev/null 2>&1; then
    if ss -ln 2>/dev/null | grep -q ":$PORT "; then
        print_warning "Port $PORT is already in use"
        print_info "Check what's using it: sudo ss -tlnp | grep :$PORT"
    else
        print_success "Port $PORT is available"
    fi
else
    print_info "Install netstat or ss to check port usage"
fi

# Check systemd service if installed
if [[ -f "/etc/systemd/system/docker-stats-exporter.service" ]]; then
    print_info "Checking systemd service..."
    if systemctl is-active --quiet docker-stats-exporter; then
        print_success "Service is running"
    elif systemctl is-enabled --quiet docker-stats-exporter; then
        print_warning "Service is enabled but not running"
        print_info "Start it: sudo systemctl start docker-stats-exporter"
    else
        print_warning "Service is installed but not enabled"
        print_info "Enable it: sudo systemctl enable docker-stats-exporter"
    fi
    
    # Check service logs
    print_info "Recent service logs:"
    if command -v journalctl >/dev/null 2>&1; then
        journalctl -u docker-stats-exporter --no-pager -n 5 2>/dev/null || true
    fi
else
    print_info "Systemd service not installed (manual mode)"
fi

# Test metrics endpoint if service is running
if curl -s http://localhost:$PORT/metrics >/dev/null 2>&1; then
    print_success "Metrics endpoint is accessible at http://localhost:$PORT/metrics"
    
    # Check metric content
    metric_count=$(curl -s http://localhost:$PORT/metrics | grep -c "^docker_container_" || echo 0)
    if [[ $metric_count -gt 0 ]]; then
        print_success "Found $metric_count Docker container metrics"
    else
        print_warning "No Docker container metrics found"
    fi
else
    print_warning "Metrics endpoint not accessible at http://localhost:$PORT/metrics"
    print_info "Try starting the exporter manually:"
    print_info "  ./docker-stats-exporter.sh --port $PORT --log-level DEBUG"
fi

echo ""
print_info "Troubleshooting complete!"
echo ""
print_info "If issues persist:"
print_info "  1. Run with debug logging: ./docker-stats-exporter.sh --log-level DEBUG"
print_info "  2. Check logs: journalctl -u docker-stats-exporter -f"
print_info "  3. Test manually: ./docker-stats-exporter.sh --help"
echo ""
print_info "For more help, see README.md and GRAFANA.md"