FROM alpine:3

# Install required packages
RUN apk add --no-cache \
    bash \
    bc \
    socat \
    docker-cli \
    wget

# Create a non-root user for the exporter
RUN addgroup -g 1000 exporter && \
    adduser -D -u 1000 -G exporter exporter

# Create application directory
WORKDIR /app

# Copy the exporter script
COPY docker-stats-exporter.sh /app/
RUN chmod +x /app/docker-stats-exporter.sh

# Set ownership of application directory
RUN chown -R exporter:exporter /app

# Switch to non-root user
USER exporter

# Set default environment variables
ENV PORT=9417 \
    INTERVAL=15 \
    LOG_LEVEL=INFO \
    BIND_ADDRESS=0.0.0.0

# Expose the metrics port
EXPOSE 9417

# Health check to verify the service is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:${PORT}/metrics || exit 1

# Set the entrypoint
ENTRYPOINT ["/app/docker-stats-exporter.sh"]

# Default command
CMD []