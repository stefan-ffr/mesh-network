# Mesh Network Monitoring Node - Dashboard
FROM python:3.11-slim

LABEL maintainer="mesh-network"
LABEL description="Mesh Network Monitoring Dashboard with WebSocket support"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    openssh-client \
    iputils-ping \
    dnsutils \
    curl \
    gcc \
    make \
    libffi-dev \
    python3-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create app user
RUN useradd -r -s /bin/bash -u 1000 mesh-monitor

# Set working directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY mesh-monitor.py .
COPY notifications.py .
COPY dashboard.py .
COPY collector.py .
COPY templates/ ./templates/
COPY static/ ./static/

# Create data directory
RUN mkdir -p /data && chown mesh-monitor:mesh-monitor /data

# Switch to non-root user
USER mesh-monitor

# Expose ports
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8080/api/status || exit 1

# Start dashboard
CMD ["python3", "dashboard.py"]
