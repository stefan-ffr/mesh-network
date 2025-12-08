-- Mesh Network Monitoring Database Initialization

-- Nodes table
CREATE TABLE IF NOT EXISTS nodes (
    hostname TEXT PRIMARY KEY,
    ip TEXT,
    type TEXT,
    last_seen TIMESTAMP,
    status TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Metrics table
CREATE TABLE IF NOT EXISTS metrics (
    id SERIAL PRIMARY KEY,
    hostname TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    cpu_percent REAL,
    memory_percent REAL,
    disk_percent REAL,
    uptime_seconds INTEGER,
    FOREIGN KEY (hostname) REFERENCES nodes(hostname) ON DELETE CASCADE
);

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_metrics_hostname_timestamp ON metrics(hostname, timestamp DESC);

-- Services table
CREATE TABLE IF NOT EXISTS services (
    id SERIAL PRIMARY KEY,
    hostname TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    service_name TEXT,
    status TEXT,
    FOREIGN KEY (hostname) REFERENCES nodes(hostname) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_services_hostname ON services(hostname, timestamp DESC);

-- OSPF neighbors table
CREATE TABLE IF NOT EXISTS ospf_neighbors (
    id SERIAL PRIMARY KEY,
    hostname TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    neighbor_id TEXT,
    neighbor_ip TEXT,
    state TEXT,
    FOREIGN KEY (hostname) REFERENCES nodes(hostname) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_ospf_hostname ON ospf_neighbors(hostname, timestamp DESC);

-- Alerts table
CREATE TABLE IF NOT EXISTS alerts (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    hostname TEXT,
    severity TEXT,
    alert_type TEXT,
    message TEXT,
    resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_alerts_resolved ON alerts(resolved, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_alerts_hostname ON alerts(hostname);

-- Sent notifications tracking
CREATE TABLE IF NOT EXISTS sent_notifications (
    alert_id INTEGER PRIMARY KEY,
    sent_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (alert_id) REFERENCES alerts(id) ON DELETE CASCADE
);

-- Cleanup old metrics (retention function)
CREATE OR REPLACE FUNCTION cleanup_old_metrics(days INTEGER)
RETURNS void AS $$
BEGIN
    DELETE FROM metrics WHERE timestamp < NOW() - INTERVAL '1 day' * days;
    DELETE FROM services WHERE timestamp < NOW() - INTERVAL '1 day' * days;
    DELETE FROM ospf_neighbors WHERE timestamp < NOW() - INTERVAL '1 day' * days;
END;
$$ LANGUAGE plpgsql;

-- Create cleanup trigger (optional - can be called via cron)
-- SELECT cleanup_old_metrics(30);

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO mesh_monitor;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO mesh_monitor;
