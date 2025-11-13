# Grafana Dashboard Configuration for Docker Stats Exporter

## Dashboard Features

### Multi-Host Support
- **Host Selection**: Dropdown to filter by specific hosts or view all hosts
- **Container Filtering**: Filter by container names across all selected hosts
- **Cross-Host Comparison**: Compare metrics across different hosts

### Key Metrics Panels

1. **Overview Stats**
   - Total container count across all hosts
   - Number of monitored hosts
   - Average CPU and memory usage gauges

2. **Time Series Charts**
   - CPU usage by container (per host)
   - Memory usage by container (per host)
   - Network RX/TX rates
   - Disk read/write rates

3. **Top Lists**
   - Top 10 containers by CPU usage
   - Top 10 containers by memory usage

### Variables
- `$instance`: Multi-select dropdown for host selection
- `$container`: Multi-select dropdown for container filtering
- `$DS_PROMETHEUS`: Prometheus datasource

## Installation Instructions

### 1. Import Dashboard

**Method A: Upload JSON file**
```bash
# In Grafana UI:
# 1. Go to "+" → Import
# 2. Upload grafana-dashboard.json
# 3. Select your Prometheus datasource
# 4. Click Import
```

**Method B: Import by ID** (if uploaded to grafana.com)
```bash
# Use dashboard ID: [to be assigned after upload]
```

### 2. Configure Prometheus Datasource

Ensure your Prometheus is configured to scrape multiple Docker stats exporters:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'docker-stats-exporter'
    static_configs:
      - targets: 
        - 'host1:9417'
        - 'host2:9417'  
        - 'host3:9417'
    scrape_interval: 15s
    metrics_path: /metrics
    
  # Or use service discovery for dynamic hosts
  - job_name: 'docker-stats-consul'
    consul_sd_configs:
      - server: 'consul:8500'
        services: ['docker-stats-exporter']
```

### 3. Host Labeling

For better host identification, you can add labels to your Prometheus targets:

```yaml
scrape_configs:
  - job_name: 'docker-stats-exporter'
    static_configs:
      - targets: ['192.168.1.10:9417']
        labels:
          hostname: 'prod-server-01'
          environment: 'production'
          datacenter: 'us-east-1'
      - targets: ['192.168.1.11:9417']
        labels:
          hostname: 'prod-server-02'
          environment: 'production' 
          datacenter: 'us-east-1'
```

## Dashboard Usage

### Host Selection
- **All Hosts**: Select "All" in the instance dropdown
- **Specific Hosts**: Choose one or more hosts from the dropdown
- **Auto-refresh**: Dropdown updates automatically as new hosts appear

### Container Filtering
- Filter containers by name pattern (supports regex)
- Select specific containers or view all
- Filtering applies across all selected hosts

### Time Range
- Default: Last 1 hour
- Adjustable via Grafana time picker
- Auto-refresh every 30 seconds

## Customization

### Adding Custom Panels

**Example: Container Count by Host**
```promql
count by (instance) (docker_container_cpu_usage_percent{instance=~"$instance"})
```

**Example: Host Resource Utilization**
```promql
# Average CPU per host
avg by (instance) (docker_container_cpu_usage_percent{instance=~"$instance"})

# Total memory usage per host  
sum by (instance) (docker_container_memory_usage_bytes{instance=~"$instance"})
```

### Alert Rules

Add alerting rules to your Prometheus configuration:

```yaml
# alerts.yml
groups:
  - name: docker-stats
    rules:
      - alert: HighContainerCPU
        expr: docker_container_cpu_usage_percent > 90
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage in container {{ $labels.container_name }} on {{ $labels.instance }}"
          
      - alert: HighContainerMemory  
        expr: docker_container_memory_usage_percent > 95
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High memory usage in container {{ $labels.container_name }} on {{ $labels.instance }}"
```

## Troubleshooting

### No Data Showing
1. Check Prometheus targets: `http://prometheus:9090/targets`
2. Verify exporter endpoints: `curl http://host:9417/metrics`
3. Check Grafana datasource configuration

### Missing Hosts
1. Ensure all exporters are running
2. Check Prometheus scrape configuration
3. Verify network connectivity between Prometheus and exporters

### Performance Issues
1. Reduce scrape frequency for large deployments
2. Use recording rules for complex queries
3. Adjust dashboard refresh interval