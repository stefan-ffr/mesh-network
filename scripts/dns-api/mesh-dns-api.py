#!/usr/bin/env python3
"""
Mesh Network DNS Registration API
Allows nodes to register themselves via REST API
"""

import json
import os
import subprocess
import sqlite3
import time
from datetime import datetime
from pathlib import Path
from flask import Flask, request, jsonify
from functools import wraps

app = Flask(__name__)

# Configuration
DB_PATH = os.environ.get('DNS_DB_PATH', '/var/lib/mesh-dns/nodes.db')
HOSTS_FILE = os.environ.get('DNS_HOSTS_FILE', '/etc/unbound/mesh-hosts.conf')
API_TOKEN = os.environ.get('DNS_API_TOKEN', '')  # Optional auth token
MESH_DOMAIN = os.environ.get('MESH_DOMAIN', 'mesh')
TTL = int(os.environ.get('DNS_TTL', '300'))

def init_db():
    """Initialize SQLite database for node tracking"""
    Path(DB_PATH).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''
        CREATE TABLE IF NOT EXISTS nodes (
            hostname TEXT PRIMARY KEY,
            ipv4 TEXT,
            ipv6 TEXT,
            node_type TEXT,
            services TEXT,
            last_seen INTEGER,
            registered_at INTEGER,
            metadata TEXT
        )
    ''')
    c.execute('''
        CREATE TABLE IF NOT EXISTS services (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            hostname TEXT,
            service_name TEXT,
            port INTEGER,
            protocol TEXT,
            priority INTEGER DEFAULT 0,
            weight INTEGER DEFAULT 0,
            UNIQUE(hostname, service_name, protocol)
        )
    ''')
    conn.commit()
    conn.close()

def require_token(f):
    """Optional API token authentication"""
    @wraps(f)
    def decorated(*args, **kwargs):
        if API_TOKEN:
            token = request.headers.get('X-API-Token') or request.args.get('token')
            if token != API_TOKEN:
                return jsonify({'error': 'Unauthorized'}), 401
        return f(*args, **kwargs)
    return decorated

def update_unbound():
    """Regenerate Unbound hosts file and reload"""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    lines = [
        f"# Mesh DNS - Auto-generated at {datetime.utcnow().isoformat()}",
        f"# Do not edit manually - use API at http://dns.{MESH_DOMAIN}:5380",
        ""
    ]

    # Add A and AAAA records
    c.execute('SELECT hostname, ipv4, ipv6, node_type FROM nodes ORDER BY hostname')
    for hostname, ipv4, ipv6, node_type in c.fetchall():
        if ipv4:
            lines.append(f'local-data: "{hostname}.{MESH_DOMAIN}. {TTL} IN A {ipv4}"')
        if ipv6:
            lines.append(f'local-data: "{hostname}.{MESH_DOMAIN}. {TTL} IN AAAA {ipv6}"')
        if node_type:
            # Add TXT record with node type
            lines.append(f'local-data: "{hostname}.{MESH_DOMAIN}. {TTL} IN TXT \\"type={node_type}\\"\"')

    # Add SRV records for services
    c.execute('''
        SELECT s.hostname, s.service_name, s.port, s.protocol, s.priority, s.weight
        FROM services s
        JOIN nodes n ON s.hostname = n.hostname
        ORDER BY s.service_name
    ''')
    for hostname, service, port, protocol, priority, weight in c.fetchall():
        # _http._tcp.mesh. 300 IN SRV 0 0 80 webserver.mesh.
        lines.append(
            f'local-data: "_{service}._{protocol}.{MESH_DOMAIN}. {TTL} IN SRV {priority} {weight} {port} {hostname}.{MESH_DOMAIN}."'
        )

    conn.close()

    # Write hosts file
    with open(HOSTS_FILE, 'w') as f:
        f.write('\n'.join(lines) + '\n')

    # Reload Unbound
    try:
        subprocess.run(['unbound-control', 'reload'], check=True, capture_output=True)
        return True
    except subprocess.CalledProcessError:
        try:
            subprocess.run(['systemctl', 'reload', 'unbound'], check=True, capture_output=True)
            return True
        except:
            return False

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({'status': 'ok', 'timestamp': int(time.time())})

@app.route('/api/v1/register', methods=['POST'])
@require_token
def register_node():
    """
    Register or update a node

    POST /api/v1/register
    {
        "hostname": "mynode",
        "ipv4": "10.10.1.50",
        "ipv6": "fd00::50",  // optional
        "node_type": "monitoring",  // optional
        "services": [  // optional
            {"name": "http", "port": 80, "protocol": "tcp"},
            {"name": "ssh", "port": 22, "protocol": "tcp"}
        ],
        "metadata": {}  // optional, any JSON
    }
    """
    data = request.get_json()

    if not data:
        return jsonify({'error': 'No JSON data provided'}), 400

    hostname = data.get('hostname', '').lower().strip()
    ipv4 = data.get('ipv4', '').strip()
    ipv6 = data.get('ipv6', '').strip()

    if not hostname:
        return jsonify({'error': 'hostname is required'}), 400

    if not ipv4 and not ipv6:
        return jsonify({'error': 'ipv4 or ipv6 is required'}), 400

    # Validate hostname (alphanumeric + hyphens)
    if not all(c.isalnum() or c == '-' for c in hostname):
        return jsonify({'error': 'Invalid hostname format'}), 400

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    now = int(time.time())

    # Upsert node
    c.execute('''
        INSERT INTO nodes (hostname, ipv4, ipv6, node_type, services, last_seen, registered_at, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(hostname) DO UPDATE SET
            ipv4 = excluded.ipv4,
            ipv6 = excluded.ipv6,
            node_type = excluded.node_type,
            services = excluded.services,
            last_seen = excluded.last_seen,
            metadata = excluded.metadata
    ''', (
        hostname,
        ipv4 or None,
        ipv6 or None,
        data.get('node_type'),
        json.dumps(data.get('services', [])),
        now,
        now,
        json.dumps(data.get('metadata', {}))
    ))

    # Update services
    services = data.get('services', [])
    if services:
        c.execute('DELETE FROM services WHERE hostname = ?', (hostname,))
        for svc in services:
            if 'name' in svc and 'port' in svc:
                c.execute('''
                    INSERT OR REPLACE INTO services (hostname, service_name, port, protocol, priority, weight)
                    VALUES (?, ?, ?, ?, ?, ?)
                ''', (
                    hostname,
                    svc['name'],
                    svc['port'],
                    svc.get('protocol', 'tcp'),
                    svc.get('priority', 0),
                    svc.get('weight', 0)
                ))

    conn.commit()
    conn.close()

    # Update DNS
    update_unbound()

    return jsonify({
        'status': 'registered',
        'hostname': hostname,
        'fqdn': f'{hostname}.{MESH_DOMAIN}',
        'ipv4': ipv4,
        'ipv6': ipv6
    })

@app.route('/api/v1/heartbeat', methods=['POST'])
@require_token
def heartbeat():
    """
    Update last_seen timestamp for a node

    POST /api/v1/heartbeat
    {"hostname": "mynode"}
    """
    data = request.get_json()
    hostname = data.get('hostname', '').lower().strip()

    if not hostname:
        return jsonify({'error': 'hostname is required'}), 400

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('UPDATE nodes SET last_seen = ? WHERE hostname = ?', (int(time.time()), hostname))
    updated = c.rowcount > 0
    conn.commit()
    conn.close()

    if updated:
        return jsonify({'status': 'ok', 'hostname': hostname})
    else:
        return jsonify({'error': 'Node not found'}), 404

@app.route('/api/v1/unregister', methods=['POST', 'DELETE'])
@require_token
def unregister_node():
    """
    Remove a node from DNS

    POST/DELETE /api/v1/unregister
    {"hostname": "mynode"}
    """
    data = request.get_json()
    hostname = data.get('hostname', '').lower().strip()

    if not hostname:
        return jsonify({'error': 'hostname is required'}), 400

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('DELETE FROM services WHERE hostname = ?', (hostname,))
    c.execute('DELETE FROM nodes WHERE hostname = ?', (hostname,))
    deleted = c.rowcount > 0
    conn.commit()
    conn.close()

    if deleted:
        update_unbound()
        return jsonify({'status': 'unregistered', 'hostname': hostname})
    else:
        return jsonify({'error': 'Node not found'}), 404

@app.route('/api/v1/nodes', methods=['GET'])
def list_nodes():
    """
    List all registered nodes

    GET /api/v1/nodes
    GET /api/v1/nodes?type=monitoring
    GET /api/v1/nodes?active=true  (seen in last 10 min)
    """
    node_type = request.args.get('type')
    active_only = request.args.get('active', '').lower() == 'true'

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    query = 'SELECT * FROM nodes WHERE 1=1'
    params = []

    if node_type:
        query += ' AND node_type = ?'
        params.append(node_type)

    if active_only:
        query += ' AND last_seen > ?'
        params.append(int(time.time()) - 600)  # 10 minutes

    query += ' ORDER BY hostname'
    c.execute(query, params)

    nodes = []
    for row in c.fetchall():
        node = dict(row)
        node['fqdn'] = f"{node['hostname']}.{MESH_DOMAIN}"
        node['services'] = json.loads(node['services']) if node['services'] else []
        node['metadata'] = json.loads(node['metadata']) if node['metadata'] else {}
        nodes.append(node)

    conn.close()
    return jsonify({'nodes': nodes, 'count': len(nodes)})

@app.route('/api/v1/nodes/<hostname>', methods=['GET'])
def get_node(hostname):
    """Get details for a specific node"""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    c.execute('SELECT * FROM nodes WHERE hostname = ?', (hostname.lower(),))
    row = c.fetchone()
    conn.close()

    if row:
        node = dict(row)
        node['fqdn'] = f"{node['hostname']}.{MESH_DOMAIN}"
        node['services'] = json.loads(node['services']) if node['services'] else []
        node['metadata'] = json.loads(node['metadata']) if node['metadata'] else {}
        return jsonify(node)
    else:
        return jsonify({'error': 'Node not found'}), 404

@app.route('/api/v1/services', methods=['GET'])
def list_services():
    """
    List all registered services

    GET /api/v1/services
    GET /api/v1/services?name=http
    """
    service_name = request.args.get('name')

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    if service_name:
        c.execute('''
            SELECT s.*, n.ipv4, n.ipv6 FROM services s
            JOIN nodes n ON s.hostname = n.hostname
            WHERE s.service_name = ?
            ORDER BY s.priority, s.weight DESC
        ''', (service_name,))
    else:
        c.execute('''
            SELECT s.*, n.ipv4, n.ipv6 FROM services s
            JOIN nodes n ON s.hostname = n.hostname
            ORDER BY s.service_name, s.priority
        ''')

    services = [dict(row) for row in c.fetchall()]
    conn.close()

    return jsonify({'services': services, 'count': len(services)})

@app.route('/api/v1/discover/<service_name>', methods=['GET'])
def discover_service(service_name):
    """
    Service discovery - find nodes offering a specific service

    GET /api/v1/discover/http
    Returns nodes with HTTP service, sorted by priority/weight
    """
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    c.execute('''
        SELECT n.hostname, n.ipv4, n.ipv6, s.port, s.protocol, s.priority, s.weight
        FROM services s
        JOIN nodes n ON s.hostname = n.hostname
        WHERE s.service_name = ? AND n.last_seen > ?
        ORDER BY s.priority ASC, s.weight DESC
    ''', (service_name, int(time.time()) - 600))

    endpoints = []
    for row in c.fetchall():
        r = dict(row)
        r['fqdn'] = f"{r['hostname']}.{MESH_DOMAIN}"
        r['url'] = f"{r['protocol']}://{r['fqdn']}:{r['port']}"
        endpoints.append(r)

    conn.close()
    return jsonify({'service': service_name, 'endpoints': endpoints, 'count': len(endpoints)})

@app.route('/api/v1/reload', methods=['POST'])
@require_token
def reload_dns():
    """Force regenerate DNS config and reload Unbound"""
    success = update_unbound()
    if success:
        return jsonify({'status': 'reloaded'})
    else:
        return jsonify({'error': 'Failed to reload Unbound'}), 500

if __name__ == '__main__':
    init_db()

    # Run with gunicorn in production
    port = int(os.environ.get('DNS_API_PORT', '5380'))
    debug = os.environ.get('DNS_API_DEBUG', 'false').lower() == 'true'
    enable_multicast = os.environ.get('DNS_MULTICAST', 'true').lower() == 'true'

    print(f"Mesh DNS API starting on port {port}")
    print(f"Database: {DB_PATH}")
    print(f"Hosts file: {HOSTS_FILE}")

    # Start multicast discovery if enabled
    if enable_multicast:
        try:
            from mesh_dns_multicast import start_multicast, register_peer_routes
            register_peer_routes(app)
            start_multicast()
            print("Multicast discovery: ENABLED")
        except ImportError:
            print("Multicast discovery: DISABLED (module not found)")
        except Exception as e:
            print(f"Multicast discovery: FAILED ({e})")
    else:
        print("Multicast discovery: DISABLED")

    app.run(host='0.0.0.0', port=port, debug=debug)
