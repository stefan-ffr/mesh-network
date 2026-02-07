#!/usr/bin/env python3
"""
Mesh Network Distributed IPAM (IP Address Management)
- Fault-tolerant IP allocation across multiple servers
- Multicast coordination to prevent conflicts
- Integrated with DNS for automatic registration
"""

import json
import socket
import struct
import threading
import time
import sqlite3
import ipaddress
import hashlib
import os
from datetime import datetime
from flask import Flask, request, jsonify

app = Flask(__name__)

# Configuration
DB_PATH = os.environ.get('IPAM_DB_PATH', '/var/lib/mesh-ipam/ipam.db')
MCAST_GROUP = os.environ.get('IPAM_MCAST_GROUP', '239.255.77.70')
MCAST_PORT = int(os.environ.get('IPAM_MCAST_PORT', '5382'))
API_PORT = int(os.environ.get('IPAM_API_PORT', '5381'))
DNS_API = os.environ.get('DNS_API', 'http://127.0.0.1:5380')

# IP Ranges (configurable)
NETWORK_RANGES = json.loads(os.environ.get('IPAM_RANGES', '''
{
    "mesh-router": "10.10.1.0/24",
    "lan-router": "10.10.2.0/24",
    "gateway": "10.10.3.0/24",
    "monitoring": "10.10.4.0/24",
    "dns-server": "10.10.5.0/24",
    "emergency": "10.10.6.0/24",
    "comm-hub": "10.10.7.0/24",
    "data-node": "10.10.8.0/24",
    "default": "10.10.100.0/24"
}
'''))

# Lease time in seconds (default 24h)
LEASE_TIME = int(os.environ.get('IPAM_LEASE_TIME', '86400'))

# Local server ID (for conflict resolution)
SERVER_ID = os.environ.get('HOSTNAME', socket.gethostname())

# Known IPAM peers
ipam_peers = {}
peers_lock = threading.Lock()

# Pending allocations (for coordination)
pending_allocations = {}
pending_lock = threading.Lock()


def init_db():
    """Initialize IPAM database"""
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # IP allocations table
    c.execute('''
        CREATE TABLE IF NOT EXISTS allocations (
            ip TEXT PRIMARY KEY,
            mac TEXT,
            hostname TEXT,
            node_type TEXT,
            allocated_at INTEGER,
            expires_at INTEGER,
            server_id TEXT,
            status TEXT DEFAULT 'active'
        )
    ''')

    # Reservations (static IPs)
    c.execute('''
        CREATE TABLE IF NOT EXISTS reservations (
            ip TEXT PRIMARY KEY,
            mac TEXT,
            hostname TEXT,
            description TEXT
        )
    ''')

    # Allocation log for conflict resolution
    c.execute('''
        CREATE TABLE IF NOT EXISTS allocation_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ip TEXT,
            action TEXT,
            server_id TEXT,
            timestamp INTEGER,
            details TEXT
        )
    ''')

    conn.commit()
    conn.close()


def get_local_ip():
    """Get primary local IP"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return '127.0.0.1'


def get_range_for_type(node_type):
    """Get IP range for a node type"""
    if node_type in NETWORK_RANGES:
        return ipaddress.ip_network(NETWORK_RANGES[node_type])
    return ipaddress.ip_network(NETWORK_RANGES.get('default', '10.10.100.0/24'))


def get_allocated_ips(network):
    """Get list of allocated IPs in a network"""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # Get active allocations
    c.execute('''
        SELECT ip FROM allocations
        WHERE status = 'active' AND expires_at > ?
    ''', (int(time.time()),))
    allocated = set(row[0] for row in c.fetchall())

    # Get reservations
    c.execute('SELECT ip FROM reservations')
    reserved = set(row[0] for row in c.fetchall())

    conn.close()
    return allocated | reserved


def find_free_ip(network, exclude=None):
    """Find a free IP in the network"""
    exclude = exclude or set()
    allocated = get_allocated_ips(network)

    # Skip network address, gateway (.1), and broadcast
    for ip in network.hosts():
        ip_str = str(ip)
        if ip_str.endswith('.1'):  # Reserve .1 for gateway
            continue
        if ip_str not in allocated and ip_str not in exclude:
            return ip_str

    return None


def broadcast_allocation(ip, hostname, action='allocate'):
    """Broadcast allocation to other IPAM servers"""
    msg = json.dumps({
        'type': 'ipam-allocation',
        'action': action,
        'ip': ip,
        'hostname': hostname,
        'server_id': SERVER_ID,
        'timestamp': int(time.time())
    }).encode('utf-8')

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
        sock.sendto(msg, (MCAST_GROUP, MCAST_PORT))
        sock.close()
    except Exception as e:
        print(f"[IPAM] Broadcast error: {e}")


def request_allocation_approval(ip, hostname):
    """Request approval from peers before allocating"""
    request_id = hashlib.md5(f"{ip}:{hostname}:{time.time()}".encode()).hexdigest()[:8]

    msg = json.dumps({
        'type': 'ipam-request',
        'request_id': request_id,
        'ip': ip,
        'hostname': hostname,
        'server_id': SERVER_ID,
        'timestamp': int(time.time())
    }).encode('utf-8')

    with pending_lock:
        pending_allocations[request_id] = {
            'ip': ip,
            'hostname': hostname,
            'approvals': {SERVER_ID},  # Self-approve
            'rejections': set(),
            'timestamp': time.time()
        }

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
        sock.sendto(msg, (MCAST_GROUP, MCAST_PORT))
        sock.close()
    except Exception as e:
        print(f"[IPAM] Request broadcast error: {e}")

    # Wait for responses (up to 2 seconds)
    time.sleep(2)

    with pending_lock:
        if request_id in pending_allocations:
            alloc = pending_allocations.pop(request_id)
            # If no rejections and at least self-approved, proceed
            if not alloc['rejections']:
                return True

    return False


def allocate_ip(hostname, mac=None, node_type='default', static_ip=None):
    """Allocate an IP address"""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # Check if hostname already has an allocation
    c.execute('SELECT ip FROM allocations WHERE hostname = ? AND status = ?', (hostname, 'active'))
    existing = c.fetchone()
    if existing:
        conn.close()
        return {'status': 'existing', 'ip': existing[0]}

    # Check if MAC already has an allocation
    if mac:
        c.execute('SELECT ip FROM allocations WHERE mac = ? AND status = ?', (mac, 'active'))
        existing = c.fetchone()
        if existing:
            conn.close()
            return {'status': 'existing', 'ip': existing[0]}

        # Check for reservation
        c.execute('SELECT ip FROM reservations WHERE mac = ?', (mac,))
        reserved = c.fetchone()
        if reserved:
            static_ip = reserved[0]

    # Determine IP to allocate
    if static_ip:
        ip = static_ip
    else:
        network = get_range_for_type(node_type)
        ip = find_free_ip(network)

        if not ip:
            conn.close()
            return {'status': 'error', 'message': 'No free IPs available'}

    # Request approval from peers
    if not request_allocation_approval(ip, hostname):
        conn.close()
        return {'status': 'error', 'message': 'Allocation rejected by peer'}

    now = int(time.time())
    expires = now + LEASE_TIME

    # Insert allocation
    try:
        c.execute('''
            INSERT INTO allocations (ip, mac, hostname, node_type, allocated_at, expires_at, server_id, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, 'active')
        ''', (ip, mac, hostname, node_type, now, expires, SERVER_ID))

        # Log allocation
        c.execute('''
            INSERT INTO allocation_log (ip, action, server_id, timestamp, details)
            VALUES (?, 'allocate', ?, ?, ?)
        ''', (ip, SERVER_ID, now, json.dumps({'hostname': hostname, 'mac': mac})))

        conn.commit()
    except sqlite3.IntegrityError:
        conn.close()
        return {'status': 'error', 'message': 'IP already allocated'}

    conn.close()

    # Broadcast allocation to peers
    broadcast_allocation(ip, hostname, 'allocate')

    # Register with DNS
    try:
        import requests
        requests.post(f"{DNS_API}/api/v1/register", json={
            'hostname': hostname,
            'ipv4': ip,
            'node_type': node_type
        }, timeout=5)
    except:
        pass

    return {
        'status': 'allocated',
        'ip': ip,
        'hostname': hostname,
        'expires_at': expires,
        'lease_time': LEASE_TIME
    }


def release_ip(ip=None, hostname=None, mac=None):
    """Release an IP allocation"""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    where_clauses = []
    params = []

    if ip:
        where_clauses.append('ip = ?')
        params.append(ip)
    if hostname:
        where_clauses.append('hostname = ?')
        params.append(hostname)
    if mac:
        where_clauses.append('mac = ?')
        params.append(mac)

    if not where_clauses:
        conn.close()
        return {'status': 'error', 'message': 'No identifier provided'}

    where = ' OR '.join(where_clauses)
    c.execute(f'SELECT ip, hostname FROM allocations WHERE {where}', params)
    row = c.fetchone()

    if not row:
        conn.close()
        return {'status': 'error', 'message': 'Allocation not found'}

    released_ip, released_hostname = row

    c.execute(f'UPDATE allocations SET status = ? WHERE {where}', ['released'] + params)
    c.execute('''
        INSERT INTO allocation_log (ip, action, server_id, timestamp, details)
        VALUES (?, 'release', ?, ?, ?)
    ''', (released_ip, SERVER_ID, int(time.time()), json.dumps({'hostname': released_hostname})))

    conn.commit()
    conn.close()

    broadcast_allocation(released_ip, released_hostname, 'release')

    return {'status': 'released', 'ip': released_ip}


def renew_lease(ip=None, hostname=None):
    """Renew an IP lease"""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    if ip:
        c.execute('SELECT ip FROM allocations WHERE ip = ? AND status = ?', (ip, 'active'))
    elif hostname:
        c.execute('SELECT ip FROM allocations WHERE hostname = ? AND status = ?', (hostname, 'active'))
    else:
        conn.close()
        return {'status': 'error', 'message': 'No identifier provided'}

    row = c.fetchone()
    if not row:
        conn.close()
        return {'status': 'error', 'message': 'Allocation not found'}

    new_expires = int(time.time()) + LEASE_TIME

    if ip:
        c.execute('UPDATE allocations SET expires_at = ? WHERE ip = ?', (new_expires, ip))
    else:
        c.execute('UPDATE allocations SET expires_at = ? WHERE hostname = ?', (new_expires, hostname))

    conn.commit()
    conn.close()

    return {'status': 'renewed', 'ip': row[0], 'expires_at': new_expires}


# Multicast listener for peer coordination
def multicast_listener():
    """Listen for IPAM multicast messages"""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    except:
        pass

    sock.bind(('', MCAST_PORT))

    mreq = struct.pack('4sl', socket.inet_aton(MCAST_GROUP), socket.INADDR_ANY)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

    print(f"[IPAM] Listening on {MCAST_GROUP}:{MCAST_PORT}")
    local_ip = get_local_ip()

    while True:
        try:
            data, addr = sock.recvfrom(4096)
            sender_ip = addr[0]

            if sender_ip == local_ip:
                continue

            msg = json.loads(data.decode('utf-8'))
            msg_type = msg.get('type')

            if msg_type == 'ipam-announce':
                # Peer announcement
                with peers_lock:
                    ipam_peers[sender_ip] = {
                        'server_id': msg.get('server_id'),
                        'allocations': msg.get('allocation_count', 0),
                        'last_seen': time.time()
                    }
                print(f"[IPAM] Peer: {msg.get('server_id')} ({sender_ip})")

            elif msg_type == 'ipam-allocation':
                # Sync allocation from peer
                action = msg.get('action')
                ip = msg.get('ip')
                hostname = msg.get('hostname')

                conn = sqlite3.connect(DB_PATH)
                c = conn.cursor()

                if action == 'allocate':
                    try:
                        c.execute('''
                            INSERT OR REPLACE INTO allocations
                            (ip, hostname, allocated_at, expires_at, server_id, status)
                            VALUES (?, ?, ?, ?, ?, 'active')
                        ''', (ip, hostname, msg.get('timestamp'),
                              int(time.time()) + LEASE_TIME, msg.get('server_id')))
                    except:
                        pass

                elif action == 'release':
                    c.execute('UPDATE allocations SET status = ? WHERE ip = ?', ('released', ip))

                conn.commit()
                conn.close()

            elif msg_type == 'ipam-request':
                # Peer requesting allocation approval
                request_id = msg.get('request_id')
                ip = msg.get('ip')

                # Check if IP is already allocated locally
                conn = sqlite3.connect(DB_PATH)
                c = conn.cursor()
                c.execute('SELECT ip FROM allocations WHERE ip = ? AND status = ?', (ip, 'active'))
                exists = c.fetchone()
                conn.close()

                response = {
                    'type': 'ipam-response',
                    'request_id': request_id,
                    'approved': not exists,
                    'server_id': SERVER_ID
                }

                sock.sendto(json.dumps(response).encode(), addr)

            elif msg_type == 'ipam-response':
                # Response to our allocation request
                request_id = msg.get('request_id')
                with pending_lock:
                    if request_id in pending_allocations:
                        if msg.get('approved'):
                            pending_allocations[request_id]['approvals'].add(msg.get('server_id'))
                        else:
                            pending_allocations[request_id]['rejections'].add(msg.get('server_id'))

        except json.JSONDecodeError:
            pass
        except Exception as e:
            print(f"[IPAM] Listener error: {e}")


def announce_presence():
    """Periodically announce presence to peers"""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)

    while True:
        try:
            conn = sqlite3.connect(DB_PATH)
            c = conn.cursor()
            c.execute('SELECT COUNT(*) FROM allocations WHERE status = ?', ('active',))
            count = c.fetchone()[0]
            conn.close()

            msg = json.dumps({
                'type': 'ipam-announce',
                'server_id': SERVER_ID,
                'allocation_count': count,
                'timestamp': int(time.time())
            }).encode('utf-8')

            sock.sendto(msg, (MCAST_GROUP, MCAST_PORT))

        except Exception as e:
            print(f"[IPAM] Announce error: {e}")

        time.sleep(30)


# Flask API
@app.route('/api/v1/allocate', methods=['POST'])
def api_allocate():
    """Allocate an IP address"""
    data = request.get_json() or {}
    result = allocate_ip(
        hostname=data.get('hostname'),
        mac=data.get('mac'),
        node_type=data.get('node_type', 'default'),
        static_ip=data.get('ip')
    )
    return jsonify(result)


@app.route('/api/v1/release', methods=['POST'])
def api_release():
    """Release an IP address"""
    data = request.get_json() or {}
    result = release_ip(
        ip=data.get('ip'),
        hostname=data.get('hostname'),
        mac=data.get('mac')
    )
    return jsonify(result)


@app.route('/api/v1/renew', methods=['POST'])
def api_renew():
    """Renew an IP lease"""
    data = request.get_json() or {}
    result = renew_lease(ip=data.get('ip'), hostname=data.get('hostname'))
    return jsonify(result)


@app.route('/api/v1/allocations', methods=['GET'])
def api_list_allocations():
    """List all allocations"""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    node_type = request.args.get('type')
    active_only = request.args.get('active', 'true').lower() == 'true'

    query = 'SELECT * FROM allocations WHERE 1=1'
    params = []

    if node_type:
        query += ' AND node_type = ?'
        params.append(node_type)

    if active_only:
        query += ' AND status = ? AND expires_at > ?'
        params.extend(['active', int(time.time())])

    query += ' ORDER BY ip'
    c.execute(query, params)

    allocations = [dict(row) for row in c.fetchall()]
    conn.close()

    return jsonify({'allocations': allocations, 'count': len(allocations)})


@app.route('/api/v1/ranges', methods=['GET'])
def api_ranges():
    """Get configured IP ranges"""
    ranges = {}
    for node_type, cidr in NETWORK_RANGES.items():
        network = ipaddress.ip_network(cidr)
        allocated = len(get_allocated_ips(network) & set(str(ip) for ip in network.hosts()))
        total = network.num_addresses - 2  # Exclude network and broadcast
        ranges[node_type] = {
            'cidr': cidr,
            'total': total,
            'allocated': allocated,
            'available': total - allocated
        }
    return jsonify(ranges)


@app.route('/api/v1/peers', methods=['GET'])
def api_peers():
    """List IPAM peers"""
    with peers_lock:
        peers = [
            {
                'ip': ip,
                'server_id': info['server_id'],
                'allocations': info['allocations'],
                'last_seen': info['last_seen'],
                'age': int(time.time() - info['last_seen'])
            }
            for ip, info in ipam_peers.items()
            if time.time() - info['last_seen'] < 120
        ]
    return jsonify({'peers': peers, 'count': len(peers)})


@app.route('/api/v1/reserve', methods=['POST'])
def api_reserve():
    """Create a static IP reservation"""
    data = request.get_json() or {}

    if not data.get('ip') or not (data.get('mac') or data.get('hostname')):
        return jsonify({'error': 'ip and (mac or hostname) required'}), 400

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    try:
        c.execute('''
            INSERT INTO reservations (ip, mac, hostname, description)
            VALUES (?, ?, ?, ?)
        ''', (data['ip'], data.get('mac'), data.get('hostname'), data.get('description')))
        conn.commit()
    except sqlite3.IntegrityError:
        conn.close()
        return jsonify({'error': 'Reservation already exists'}), 400

    conn.close()
    return jsonify({'status': 'reserved', 'ip': data['ip']})


@app.route('/health', methods=['GET'])
def health():
    """Health check"""
    return jsonify({'status': 'ok', 'server_id': SERVER_ID})


if __name__ == '__main__':
    init_db()

    # Start background threads
    threading.Thread(target=multicast_listener, daemon=True).start()
    threading.Thread(target=announce_presence, daemon=True).start()

    print(f"[IPAM] Server ID: {SERVER_ID}")
    print(f"[IPAM] Multicast: {MCAST_GROUP}:{MCAST_PORT}")
    print(f"[IPAM] API Port: {API_PORT}")
    print(f"[IPAM] Ranges: {list(NETWORK_RANGES.keys())}")

    app.run(host='0.0.0.0', port=API_PORT)
