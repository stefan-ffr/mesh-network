#!/usr/bin/env python3
"""
Mesh Network Monitor - Metrics Collector Daemon
Continuously collects metrics and generates alerts
"""

import sys
import time
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

from mesh_monitor import MeshMonitor
from notifications import NotificationManager


def main():
    print("Starting Mesh Network Monitor Collector...")

    monitor = MeshMonitor()
    notifier = NotificationManager(monitor.config)

    # Track sent alerts to avoid duplicates
    sent_alerts = set()

    while True:
        try:
            print(f"\n[{time.strftime('%Y-%m-%d %H:%M:%S')}] Collecting metrics...")

            # Collect from all nodes
            monitor.collect_all()

            # Get new unresolved alerts
            cursor = monitor.db.cursor()
            cursor.execute('''
                SELECT id, timestamp, hostname, severity, alert_type, message
                FROM alerts
                WHERE resolved = 0
                AND id NOT IN (
                    SELECT alert_id FROM sent_notifications
                )
                ORDER BY timestamp DESC
            ''')

            new_alerts = cursor.fetchall()

            # Send notifications for new alerts
            for alert_row in new_alerts:
                alert_id, timestamp, hostname, severity, alert_type, message = alert_row

                alert_key = f"{hostname}:{alert_type}:{severity}"

                # Avoid duplicate notifications
                if alert_key not in sent_alerts:
                    alert = {
                        'id': alert_id,
                        'timestamp': timestamp,
                        'hostname': hostname,
                        'severity': severity,
                        'type': alert_type,
                        'message': message
                    }

                    print(f"  🔔 New alert: {severity.upper()} - {hostname} - {alert_type}")

                    # Send notifications
                    results = notifier.send_alert(alert)

                    # Track sent notifications
                    sent_alerts.add(alert_key)

                    # Log notification results
                    for channel, success in results:
                        if success:
                            print(f"    ✓ {channel} notification sent")
                        else:
                            print(f"    ✗ {channel} notification failed")

            # Clean up resolved alerts from tracking
            cursor.execute('''
                SELECT hostname, alert_type, severity
                FROM alerts
                WHERE resolved = 1
            ''')
            for row in cursor.fetchall():
                alert_key = f"{row[0]}:{row[1]}:{row[2]}"
                sent_alerts.discard(alert_key)

            # Sleep until next collection interval
            interval = monitor.config.get('monitoring', {}).get('interval', 30)
            print(f"Waiting {interval} seconds until next collection...")
            time.sleep(interval)

        except KeyboardInterrupt:
            print("\nShutting down collector...")
            break
        except Exception as e:
            print(f"Error in collector loop: {e}")
            time.sleep(10)

    monitor.db.close()


if __name__ == '__main__':
    # Create sent_notifications table if it doesn't exist
    import sqlite3
    db = sqlite3.connect('/var/lib/mesh-monitor/metrics.db')
    cursor = db.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS sent_notifications (
            alert_id INTEGER PRIMARY KEY,
            sent_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    db.commit()
    db.close()

    main()
