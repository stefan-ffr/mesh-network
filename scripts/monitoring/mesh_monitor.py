#!/usr/bin/env python3
"""
Mesh Network Monitor - Main monitoring script
Collects metrics from all nodes and provides CLI interface
"""

import argparse
import sys
import yaml
import json
import subprocess
import paramiko
import sqlite3
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional
import socket
import time

# Configuration
CONFIG_FILE = '/etc/mesh-monitor/config.yml'
DB_FILE = '/var/lib/mesh-monitor/metrics.db'

class MeshMonitor:
    def __init__(self, config_file: str = CONFIG_FILE):
        self.config = self.load_config(config_file)
        self.db = sqlite3.connect(DB_FILE)
        self.init_database()

    def load_config(self, config_file: str) -> dict:
        """Load configuration from YAML file"""
        try:
            with open(config_file, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            print(f"Error: Config file not found: {config_file}")
            sys.exit(1)
        except yaml.YAMLError as e:
            print(f"Error parsing config: {e}")
            sys.exit(1)

    def init_database(self):
        """Initialize SQLite database"""
        cursor = self.db.cursor()

        # Nodes table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS nodes (
                hostname TEXT PRIMARY KEY,
                ip TEXT,
                type TEXT,
                last_seen TIMESTAMP,
                status TEXT
            )
        ''')

        # Metrics table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                hostname TEXT,
                timestamp TIMESTAMP,
                cpu_percent REAL,
                memory_percent REAL,
                disk_percent REAL,
                uptime_seconds INTEGER,
                FOREIGN KEY (hostname) REFERENCES nodes(hostname)
            )
        ''')

        # Services table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS services (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                hostname TEXT,
                timestamp TIMESTAMP,
                service_name TEXT,
                status TEXT,
                FOREIGN KEY (hostname) REFERENCES nodes(hostname)
            )
        ''')

        # OSPF neighbors table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS ospf_neighbors (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                hostname TEXT,
                timestamp TIMESTAMP,
                neighbor_id TEXT,
                neighbor_ip TEXT,
                state TEXT,
                FOREIGN KEY (hostname) REFERENCES nodes(hostname)
            )
        ''')

        # Alerts table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS alerts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TIMESTAMP,
                hostname TEXT,
                severity TEXT,
                alert_type TEXT,
                message TEXT,
                resolved BOOLEAN DEFAULT 0,
                resolved_at TIMESTAMP
            )
        ''')

        self.db.commit()

    def discover_nodes(self) -> List[Dict]:
        """Discover nodes via OSPF"""
        nodes = []

        # Get configured nodes
        if 'nodes' in self.config.get('network', {}):
            nodes.extend(self.config['network']['nodes'])

        # Auto-discover via OSPF if enabled
        if self.config.get('network', {}).get('auto_discovery', True):
            try:
                result = subprocess.run(
                    ['vtysh', '-c', 'show ip ospf neighbor json'],
                    capture_output=True,
                    text=True,
                    timeout=5
                )

                if result.returncode == 0:
                    ospf_data = json.loads(result.stdout)
                    for neighbor_id, neighbor_data in ospf_data.get('neighbors', {}).items():
                        if isinstance(neighbor_data, dict):
                            ip = neighbor_data.get('address', '')
                            if ip and not any(n['ip'] == ip for n in nodes):
                                nodes.append({
                                    'hostname': f'node-{ip.split(".")[-1]}',
                                    'ip': ip,
                                    'type': 'unknown'
                                })
            except Exception as e:
                print(f"Warning: OSPF discovery failed: {e}")

        return nodes

    def check_node_reachable(self, ip: str, timeout: int = 2) -> bool:
        """Check if node is reachable via ping"""
        try:
            result = subprocess.run(
                ['ping', '-c', '1', '-W', str(timeout), ip],
                capture_output=True,
                timeout=timeout + 1
            )
            return result.returncode == 0
        except:
            return False

    def ssh_execute(self, ip: str, command: str) -> Optional[str]:
        """Execute command on remote node via SSH"""
        try:
            ssh_config = self.config.get('monitoring', {})
            ssh_user = ssh_config.get('ssh_user', 'mesh-monitor')
            ssh_key = ssh_config.get('ssh_key', '/opt/mesh-monitor/.ssh/id_ed25519')
            timeout = ssh_config.get('timeout', 5)

            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(
                ip,
                username=ssh_user,
                key_filename=ssh_key,
                timeout=timeout,
                look_for_keys=False,
                allow_agent=False
            )

            stdin, stdout, stderr = ssh.exec_command(command, timeout=timeout)
            output = stdout.read().decode('utf-8')
            ssh.close()

            return output
        except Exception as e:
            return None

    def collect_node_metrics(self, node: Dict) -> Optional[Dict]:
        """Collect metrics from a single node"""
        hostname = node['hostname']
        ip = node['ip']

        # Check if reachable
        if not self.check_node_reachable(ip):
            return {
                'hostname': hostname,
                'status': 'unreachable',
                'timestamp': datetime.now()
            }

        metrics = {
            'hostname': hostname,
            'ip': ip,
            'status': 'online',
            'timestamp': datetime.now()
        }

        # Collect system metrics via SSH
        if self.config.get('monitoring', {}).get('ssh_enabled', True):
            # CPU
            cpu_output = self.ssh_execute(ip, "top -bn1 | grep 'Cpu(s)' | awk '{print $2}'")
            if cpu_output:
                try:
                    metrics['cpu_percent'] = float(cpu_output.strip().replace('%', '').replace(',', '.'))
                except:
                    pass

            # Memory
            mem_output = self.ssh_execute(ip, "free | grep Mem | awk '{print ($3/$2) * 100.0}'")
            if mem_output:
                try:
                    metrics['memory_percent'] = float(mem_output.strip())
                except:
                    pass

            # Disk
            disk_output = self.ssh_execute(ip, "df -h / | tail -1 | awk '{print $5}'")
            if disk_output:
                try:
                    metrics['disk_percent'] = float(disk_output.strip().replace('%', ''))
                except:
                    pass

            # Uptime
            uptime_output = self.ssh_execute(ip, "cat /proc/uptime | awk '{print $1}'")
            if uptime_output:
                try:
                    metrics['uptime_seconds'] = int(float(uptime_output.strip()))
                except:
                    pass

            # Services
            services = ['frr', 'etcd', 'coredns', 'unbound', 'isc-dhcp-server']
            metrics['services'] = {}
            for service in services:
                svc_output = self.ssh_execute(ip, f"systemctl is-active {service}")
                if svc_output:
                    metrics['services'][service] = svc_output.strip()

            # OSPF neighbors
            ospf_output = self.ssh_execute(ip, "sudo vtysh -c 'show ip ospf neighbor json'")
            if ospf_output:
                try:
                    ospf_data = json.loads(ospf_output)
                    metrics['ospf_neighbors'] = ospf_data.get('neighbors', {})
                except:
                    pass

        return metrics

    def store_metrics(self, metrics: Dict):
        """Store metrics in database"""
        cursor = self.db.cursor()
        hostname = metrics['hostname']
        timestamp = metrics['timestamp']

        # Update/insert node
        cursor.execute('''
            INSERT OR REPLACE INTO nodes (hostname, ip, type, last_seen, status)
            VALUES (?, ?, ?, ?, ?)
        ''', (
            hostname,
            metrics.get('ip', ''),
            metrics.get('type', 'unknown'),
            timestamp,
            metrics.get('status', 'unknown')
        ))

        # Store metrics if available
        if 'cpu_percent' in metrics:
            cursor.execute('''
                INSERT INTO metrics (hostname, timestamp, cpu_percent, memory_percent, disk_percent, uptime_seconds)
                VALUES (?, ?, ?, ?, ?, ?)
            ''', (
                hostname,
                timestamp,
                metrics.get('cpu_percent'),
                metrics.get('memory_percent'),
                metrics.get('disk_percent'),
                metrics.get('uptime_seconds')
            ))

        # Store service status
        for service, status in metrics.get('services', {}).items():
            cursor.execute('''
                INSERT INTO services (hostname, timestamp, service_name, status)
                VALUES (?, ?, ?, ?)
            ''', (hostname, timestamp, service, status))

        # Store OSPF neighbors
        for neighbor_id, neighbor_data in metrics.get('ospf_neighbors', {}).items():
            if isinstance(neighbor_data, dict):
                cursor.execute('''
                    INSERT INTO ospf_neighbors (hostname, timestamp, neighbor_id, neighbor_ip, state)
                    VALUES (?, ?, ?, ?, ?)
                ''', (
                    hostname,
                    timestamp,
                    neighbor_id,
                    neighbor_data.get('address', ''),
                    neighbor_data.get('state', '')
                ))

        self.db.commit()

    def check_alerts(self, metrics: Dict):
        """Check for alert conditions"""
        hostname = metrics['hostname']
        thresholds = self.config.get('thresholds', {})
        alerts = []

        # Node unreachable
        if metrics.get('status') == 'unreachable':
            alerts.append({
                'severity': 'critical',
                'type': 'node_down',
                'message': f"Node {hostname} is unreachable"
            })

        # High CPU
        cpu = metrics.get('cpu_percent', 0)
        if cpu >= thresholds.get('cpu_critical', 90):
            alerts.append({
                'severity': 'critical',
                'type': 'high_cpu',
                'message': f"CPU usage on {hostname} is {cpu:.1f}% (critical)"
            })
        elif cpu >= thresholds.get('cpu_warning', 70):
            alerts.append({
                'severity': 'warning',
                'type': 'high_cpu',
                'message': f"CPU usage on {hostname} is {cpu:.1f}% (warning)"
            })

        # High Memory
        mem = metrics.get('memory_percent', 0)
        if mem >= thresholds.get('memory_critical', 95):
            alerts.append({
                'severity': 'critical',
                'type': 'high_memory',
                'message': f"Memory usage on {hostname} is {mem:.1f}% (critical)"
            })
        elif mem >= thresholds.get('memory_warning', 80):
            alerts.append({
                'severity': 'warning',
                'type': 'high_memory',
                'message': f"Memory usage on {hostname} is {mem:.1f}% (warning)"
            })

        # High Disk
        disk = metrics.get('disk_percent', 0)
        if disk >= thresholds.get('disk_critical', 90):
            alerts.append({
                'severity': 'critical',
                'type': 'high_disk',
                'message': f"Disk usage on {hostname} is {disk:.1f}% (critical)"
            })
        elif disk >= thresholds.get('disk_warning', 80):
            alerts.append({
                'severity': 'warning',
                'type': 'high_disk',
                'message': f"Disk usage on {hostname} is {disk:.1f}% (warning)"
            })

        # Service failures
        for service, status in metrics.get('services', {}).items():
            if status != 'active':
                alerts.append({
                    'severity': 'critical',
                    'type': 'service_down',
                    'message': f"Service {service} on {hostname} is {status}"
                })

        # Store alerts
        cursor = self.db.cursor()
        for alert in alerts:
            cursor.execute('''
                INSERT INTO alerts (timestamp, hostname, severity, alert_type, message)
                VALUES (?, ?, ?, ?, ?)
            ''', (
                datetime.now(),
                hostname,
                alert['severity'],
                alert['type'],
                alert['message']
            ))
        self.db.commit()

        return alerts

    def collect_all(self):
        """Collect metrics from all nodes"""
        nodes = self.discover_nodes()
        print(f"Discovered {len(nodes)} nodes")

        for node in nodes:
            print(f"Collecting metrics from {node['hostname']} ({node['ip']})...", end=' ')
            metrics = self.collect_node_metrics(node)

            if metrics:
                self.store_metrics(metrics)
                alerts = self.check_alerts(metrics)

                if metrics.get('status') == 'online':
                    print("OK")
                else:
                    print("UNREACHABLE")

                if alerts:
                    print(f"  ⚠ {len(alerts)} alert(s) generated")
            else:
                print("FAILED")

    def show_status(self):
        """Show network overview"""
        cursor = self.db.cursor()

        # Count nodes by status
        cursor.execute('''
            SELECT status, COUNT(*) FROM nodes GROUP BY status
        ''')
        status_counts = dict(cursor.fetchall())

        # Count alerts
        cursor.execute('''
            SELECT severity, COUNT(*) FROM alerts
            WHERE resolved = 0
            GROUP BY severity
        ''')
        alert_counts = dict(cursor.fetchall())

        print("╔═══════════════════════════════════════════════╗")
        print("║       Mesh Network Monitoring Status          ║")
        print("╚═══════════════════════════════════════════════╝")
        print()
        print(f"Nodes Online:      {status_counts.get('online', 0)}")
        print(f"Nodes Unreachable: {status_counts.get('unreachable', 0)}")
        print()
        print(f"Active Alerts:")
        print(f"  Critical: {alert_counts.get('critical', 0)}")
        print(f"  Warning:  {alert_counts.get('warning', 0)}")
        print()

    def list_nodes(self):
        """List all nodes"""
        cursor = self.db.cursor()
        cursor.execute('''
            SELECT hostname, ip, type, status, last_seen
            FROM nodes
            ORDER BY hostname
        ''')

        print("╔═══════════════════════════════════════════════════════════════╗")
        print("║                        Mesh Nodes                              ║")
        print("╠═══════════════╦═══════════════╦═══════════╦══════════════════╣")
        print("║ Hostname      ║ IP Address    ║ Status    ║ Last Seen        ║")
        print("╠═══════════════╬═══════════════╬═══════════╬══════════════════╣")

        for row in cursor.fetchall():
            hostname, ip, node_type, status, last_seen = row
            status_icon = "✓" if status == "online" else "✗"
            print(f"║ {hostname:13} ║ {ip:13} ║ {status_icon} {status:7} ║ {last_seen:16} ║")

        print("╚═══════════════╩═══════════════╩═══════════╩══════════════════╝")

    def show_alerts(self):
        """Show active alerts"""
        cursor = self.db.cursor()
        cursor.execute('''
            SELECT timestamp, hostname, severity, message
            FROM alerts
            WHERE resolved = 0
            ORDER BY timestamp DESC
            LIMIT 20
        ''')

        print("╔════════════════════════════════════════════════════════════════════╗")
        print("║                        Active Alerts                                ║")
        print("╠══════════════════╦════════╦═══════════════════════════════════════╣")
        print("║ Time             ║ Level  ║ Message                                ║")
        print("╠══════════════════╬════════╬═══════════════════════════════════════╣")

        for row in cursor.fetchall():
            timestamp, hostname, severity, message = row
            severity_icon = "🔴" if severity == "critical" else "⚠"
            print(f"║ {timestamp:16} ║ {severity_icon} {severity:5} ║ {message[:35]:35} ║")

        print("╚══════════════════╩════════╩═══════════════════════════════════════╝")


def main():
    parser = argparse.ArgumentParser(description='Mesh Network Monitor')
    parser.add_argument('command', nargs='?', default='status',
                       choices=['status', 'nodes', 'alerts', 'collect', 'discover'],
                       help='Command to execute')
    parser.add_argument('--config', default=CONFIG_FILE, help='Config file path')

    args = parser.parse_args()

    monitor = MeshMonitor(args.config)

    if args.command == 'status':
        monitor.show_status()
    elif args.command == 'nodes':
        monitor.list_nodes()
    elif args.command == 'alerts':
        monitor.show_alerts()
    elif args.command == 'collect':
        monitor.collect_all()
    elif args.command == 'discover':
        nodes = monitor.discover_nodes()
        print(f"Discovered {len(nodes)} nodes:")
        for node in nodes:
            print(f"  - {node['hostname']} ({node['ip']})")


if __name__ == '__main__':
    main()
