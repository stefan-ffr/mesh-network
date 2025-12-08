#!/usr/bin/env python3
"""
Mesh Network Monitor - Web Dashboard
Flask-based web interface with real-time updates via WebSocket
"""

from flask import Flask, render_template, jsonify, request, session, redirect, url_for
from flask_socketio import SocketIO, emit
from flask_cors import CORS
import sqlite3
import yaml
import json
from datetime import datetime, timedelta
from pathlib import Path
import threading
import time

app = Flask(__name__)
app.config['SECRET_KEY'] = 'your-secret-key-here'  # Will be overridden by config
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*")

CONFIG_FILE = '/etc/mesh-monitor/config.yml'
DB_FILE = '/var/lib/mesh-monitor/metrics.db'

# Load configuration
with open(CONFIG_FILE, 'r') as f:
    config = yaml.safe_load(f)

dashboard_config = config.get('dashboard', {})
app.config['SECRET_KEY'] = dashboard_config.get('secret_key', 'change-me')


def get_db():
    """Get database connection"""
    db = sqlite3.connect(DB_FILE)
    db.row_factory = sqlite3.Row
    return db


def require_auth(f):
    """Authentication decorator"""
    def decorated(*args, **kwargs):
        if not dashboard_config.get('auth_enabled', True):
            return f(*args, **kwargs)

        if not session.get('authenticated'):
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    decorated.__name__ = f.__name__
    return decorated


@app.route('/login', methods=['GET', 'POST'])
def login():
    """Login page"""
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')

        if (username == dashboard_config.get('username', 'admin') and
            password == dashboard_config.get('password', 'changeme')):
            session['authenticated'] = True
            return redirect(url_for('index'))
        else:
            return render_template('login.html', error='Invalid credentials')

    return render_template('login.html')


@app.route('/logout')
def logout():
    """Logout"""
    session.pop('authenticated', None)
    return redirect(url_for('login'))


@app.route('/')
@require_auth
def index():
    """Main dashboard page"""
    return render_template('index.html')


@app.route('/api/status')
@require_auth
def api_status():
    """Get overall network status"""
    db = get_db()
    cursor = db.cursor()

    # Count nodes
    cursor.execute('SELECT COUNT(*) as total FROM nodes')
    total_nodes = cursor.fetchone()['total']

    cursor.execute("SELECT COUNT(*) as online FROM nodes WHERE status = 'online'")
    online_nodes = cursor.fetchone()['online']

    # Count alerts
    cursor.execute("SELECT COUNT(*) as critical FROM alerts WHERE resolved = 0 AND severity = 'critical'")
    critical_alerts = cursor.fetchone()['critical']

    cursor.execute("SELECT COUNT(*) as warning FROM alerts WHERE resolved = 0 AND severity = 'warning'")
    warning_alerts = cursor.fetchone()['warning']

    db.close()

    return jsonify({
        'nodes': {
            'total': total_nodes,
            'online': online_nodes,
            'offline': total_nodes - online_nodes
        },
        'alerts': {
            'critical': critical_alerts,
            'warning': warning_alerts
        }
    })


@app.route('/api/nodes')
@require_auth
def api_nodes():
    """Get all nodes"""
    db = get_db()
    cursor = db.cursor()

    cursor.execute('''
        SELECT n.hostname, n.ip, n.type, n.status, n.last_seen,
               m.cpu_percent, m.memory_percent, m.disk_percent, m.uptime_seconds
        FROM nodes n
        LEFT JOIN (
            SELECT hostname, cpu_percent, memory_percent, disk_percent, uptime_seconds
            FROM metrics
            WHERE (hostname, timestamp) IN (
                SELECT hostname, MAX(timestamp)
                FROM metrics
                GROUP BY hostname
            )
        ) m ON n.hostname = m.hostname
        ORDER BY n.hostname
    ''')

    nodes = []
    for row in cursor.fetchall():
        nodes.append({
            'hostname': row['hostname'],
            'ip': row['ip'],
            'type': row['type'],
            'status': row['status'],
            'last_seen': row['last_seen'],
            'metrics': {
                'cpu': row['cpu_percent'],
                'memory': row['memory_percent'],
                'disk': row['disk_percent'],
                'uptime': row['uptime_seconds']
            }
        })

    db.close()
    return jsonify(nodes)


@app.route('/api/nodes/<hostname>')
@require_auth
def api_node_detail(hostname):
    """Get detailed information for a specific node"""
    db = get_db()
    cursor = db.cursor()

    # Node info
    cursor.execute('SELECT * FROM nodes WHERE hostname = ?', (hostname,))
    node = cursor.fetchone()

    if not node:
        db.close()
        return jsonify({'error': 'Node not found'}), 404

    # Recent metrics (last 24 hours)
    cursor.execute('''
        SELECT timestamp, cpu_percent, memory_percent, disk_percent
        FROM metrics
        WHERE hostname = ? AND timestamp > datetime('now', '-24 hours')
        ORDER BY timestamp DESC
    ''', (hostname,))
    metrics = [dict(row) for row in cursor.fetchall()]

    # Services
    cursor.execute('''
        SELECT service_name, status
        FROM services
        WHERE hostname = ? AND (hostname, timestamp) IN (
            SELECT hostname, MAX(timestamp)
            FROM services
            WHERE hostname = ?
            GROUP BY service_name
        )
    ''', (hostname, hostname))
    services = {row['service_name']: row['status'] for row in cursor.fetchall()}

    # OSPF neighbors
    cursor.execute('''
        SELECT neighbor_id, neighbor_ip, state
        FROM ospf_neighbors
        WHERE hostname = ? AND timestamp = (
            SELECT MAX(timestamp) FROM ospf_neighbors WHERE hostname = ?
        )
    ''', (hostname, hostname))
    neighbors = [dict(row) for row in cursor.fetchall()]

    db.close()

    return jsonify({
        'node': dict(node),
        'metrics': metrics,
        'services': services,
        'ospf_neighbors': neighbors
    })


@app.route('/api/topology')
@require_auth
def api_topology():
    """Get network topology (nodes and OSPF connections)"""
    db = get_db()
    cursor = db.cursor()

    # Get all nodes
    cursor.execute('SELECT hostname, ip, type, status FROM nodes')
    nodes = [dict(row) for row in cursor.fetchall()]

    # Get OSPF connections (edges)
    cursor.execute('''
        SELECT DISTINCT o.hostname as source, o.neighbor_ip as target_ip
        FROM ospf_neighbors o
        WHERE o.timestamp > datetime('now', '-5 minutes')
        AND o.state = 'Full'
    ''')

    edges = []
    for row in cursor.fetchall():
        # Find target hostname by IP
        cursor.execute('SELECT hostname FROM nodes WHERE ip = ?', (row['target_ip'],))
        target = cursor.fetchone()
        if target:
            edges.append({
                'source': row['source'],
                'target': target['hostname']
            })

    db.close()

    return jsonify({
        'nodes': nodes,
        'edges': edges
    })


@app.route('/api/alerts')
@require_auth
def api_alerts():
    """Get active alerts"""
    db = get_db()
    cursor = db.cursor()

    resolved = request.args.get('resolved', 'false').lower() == 'true'
    limit = int(request.args.get('limit', 50))

    cursor.execute('''
        SELECT id, timestamp, hostname, severity, alert_type, message, resolved, resolved_at
        FROM alerts
        WHERE resolved = ?
        ORDER BY timestamp DESC
        LIMIT ?
    ''', (1 if resolved else 0, limit))

    alerts = [dict(row) for row in cursor.fetchall()]
    db.close()

    return jsonify(alerts)


@app.route('/api/alerts/<int:alert_id>/resolve', methods=['POST'])
@require_auth
def api_alert_resolve(alert_id):
    """Resolve an alert"""
    db = get_db()
    cursor = db.cursor()

    cursor.execute('''
        UPDATE alerts
        SET resolved = 1, resolved_at = ?
        WHERE id = ?
    ''', (datetime.now(), alert_id))

    db.commit()
    db.close()

    return jsonify({'success': True})


@app.route('/api/metrics/<hostname>')
@require_auth
def api_metrics_history(hostname):
    """Get metrics history for a node"""
    hours = int(request.args.get('hours', 24))
    db = get_db()
    cursor = db.cursor()

    cursor.execute('''
        SELECT timestamp, cpu_percent, memory_percent, disk_percent
        FROM metrics
        WHERE hostname = ? AND timestamp > datetime('now', ? || ' hours')
        ORDER BY timestamp ASC
    ''', (hostname, f'-{hours}'))

    metrics = [dict(row) for row in cursor.fetchall()]
    db.close()

    return jsonify(metrics)


def background_updates():
    """Background thread to push updates via WebSocket"""
    while True:
        time.sleep(5)  # Update every 5 seconds

        # Get current status
        db = get_db()
        cursor = db.cursor()

        cursor.execute('SELECT COUNT(*) as total FROM nodes')
        total_nodes = cursor.fetchone()['total']

        cursor.execute("SELECT COUNT(*) as online FROM nodes WHERE status = 'online'")
        online_nodes = cursor.fetchone()['online']

        cursor.execute("SELECT COUNT(*) as critical FROM alerts WHERE resolved = 0 AND severity = 'critical'")
        critical_alerts = cursor.fetchone()['critical']

        db.close()

        # Emit update to all connected clients
        socketio.emit('status_update', {
            'nodes_online': online_nodes,
            'nodes_total': total_nodes,
            'alerts_critical': critical_alerts,
            'timestamp': datetime.now().isoformat()
        })


@socketio.on('connect')
def handle_connect():
    """Handle WebSocket connection"""
    print('Client connected')
    emit('status', {'connected': True})


@socketio.on('disconnect')
def handle_disconnect():
    """Handle WebSocket disconnection"""
    print('Client disconnected')


if __name__ == '__main__':
    # Start background update thread
    update_thread = threading.Thread(target=background_updates, daemon=True)
    update_thread.start()

    # Run Flask app
    listen_addr = dashboard_config.get('listen', '0.0.0.0')
    listen_port = dashboard_config.get('port', 8080)

    print(f"Starting dashboard on {listen_addr}:{listen_port}")
    socketio.run(app, host=listen_addr, port=listen_port, debug=False)
