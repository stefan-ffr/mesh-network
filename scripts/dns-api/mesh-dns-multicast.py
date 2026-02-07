#!/usr/bin/env python3
"""
Mesh DNS Multicast Discovery & Sync
- Announces this DNS server via multicast
- Discovers other DNS servers
- Syncs node registrations between DNS servers
"""

import json
import socket
import struct
import threading
import time
import sqlite3
import requests
import os
import hashlib
from datetime import datetime

# Multicast configuration
MCAST_GROUP = os.environ.get('DNS_MCAST_GROUP', '239.255.77.69')  # M.E for MEsh
MCAST_PORT = int(os.environ.get('DNS_MCAST_PORT', '5381'))
ANNOUNCE_INTERVAL = int(os.environ.get('DNS_ANNOUNCE_INTERVAL', '30'))  # seconds
SYNC_INTERVAL = int(os.environ.get('DNS_SYNC_INTERVAL', '60'))  # seconds

# Local configuration
LOCAL_API_PORT = int(os.environ.get('DNS_API_PORT', '5380'))
DB_PATH = os.environ.get('DNS_DB_PATH', '/var/lib/mesh-dns/nodes.db')
HOSTNAME = os.environ.get('HOSTNAME', socket.gethostname())

# Track known DNS peers
dns_peers = {}  # {ip: {hostname, last_seen, api_port, node_count, hash}}
peers_lock = threading.Lock()


def get_local_ip():
    """Get primary local IP address"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return '127.0.0.1'


def get_db_hash():
    """Get hash of current node database for sync detection"""
    try:
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute('SELECT hostname, ipv4, ipv6, last_seen FROM nodes ORDER BY hostname')
        data = json.dumps(c.fetchall())
        conn.close()
        return hashlib.md5(data.encode()).hexdigest()[:16]
    except:
        return '0000000000000000'


def get_node_count():
    """Get count of registered nodes"""
    try:
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute('SELECT COUNT(*) FROM nodes')
        count = c.fetchone()[0]
        conn.close()
        return count
    except:
        return 0


def create_announcement():
    """Create multicast announcement message"""
    return json.dumps({
        'type': 'dns-announce',
        'hostname': HOSTNAME,
        'ip': get_local_ip(),
        'api_port': LOCAL_API_PORT,
        'node_count': get_node_count(),
        'db_hash': get_db_hash(),
        'timestamp': int(time.time()),
        'version': '1.0'
    }).encode('utf-8')


def multicast_sender():
    """Send periodic multicast announcements"""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)

    print(f"[Multicast] Announcing on {MCAST_GROUP}:{MCAST_PORT} every {ANNOUNCE_INTERVAL}s")

    while True:
        try:
            msg = create_announcement()
            sock.sendto(msg, (MCAST_GROUP, MCAST_PORT))
            print(f"[Multicast] Announced: {get_node_count()} nodes, hash={get_db_hash()[:8]}")
        except Exception as e:
            print(f"[Multicast] Send error: {e}")

        time.sleep(ANNOUNCE_INTERVAL)


def multicast_receiver():
    """Receive multicast announcements from other DNS servers"""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    except:
        pass

    sock.bind(('', MCAST_PORT))

    # Join multicast group
    mreq = struct.pack('4sl', socket.inet_aton(MCAST_GROUP), socket.INADDR_ANY)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

    print(f"[Multicast] Listening on {MCAST_GROUP}:{MCAST_PORT}")

    local_ip = get_local_ip()

    while True:
        try:
            data, addr = sock.recvfrom(4096)
            sender_ip = addr[0]

            # Ignore our own announcements
            if sender_ip == local_ip:
                continue

            msg = json.loads(data.decode('utf-8'))

            if msg.get('type') == 'dns-announce':
                with peers_lock:
                    dns_peers[sender_ip] = {
                        'hostname': msg.get('hostname'),
                        'ip': sender_ip,
                        'api_port': msg.get('api_port', 5380),
                        'node_count': msg.get('node_count', 0),
                        'db_hash': msg.get('db_hash', ''),
                        'last_seen': int(time.time()),
                        'version': msg.get('version', '1.0')
                    }

                print(f"[Multicast] Discovered peer: {msg.get('hostname')} ({sender_ip}) - {msg.get('node_count')} nodes")

        except json.JSONDecodeError:
            pass
        except Exception as e:
            print(f"[Multicast] Receive error: {e}")


def sync_with_peer(peer_ip, peer_port):
    """Sync node database with a peer DNS server"""
    try:
        # Get peer's nodes
        resp = requests.get(f'http://{peer_ip}:{peer_port}/api/v1/nodes', timeout=10)
        if resp.status_code != 200:
            return False

        peer_nodes = resp.json().get('nodes', [])

        if not peer_nodes:
            return True

        # Get local nodes
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute('SELECT hostname, last_seen FROM nodes')
        local_nodes = {row[0]: row[1] for row in c.fetchall()}
        conn.close()

        # Merge: keep newer entries
        synced = 0
        for node in peer_nodes:
            hostname = node.get('hostname')
            peer_last_seen = node.get('last_seen', 0)

            # If we don't have this node, or peer has newer data
            if hostname not in local_nodes or peer_last_seen > local_nodes[hostname]:
                # Register via local API
                try:
                    requests.post(
                        f'http://127.0.0.1:{LOCAL_API_PORT}/api/v1/register',
                        json={
                            'hostname': hostname,
                            'ipv4': node.get('ipv4', ''),
                            'ipv6': node.get('ipv6', ''),
                            'node_type': node.get('node_type', ''),
                            'services': node.get('services', []),
                            'metadata': node.get('metadata', {})
                        },
                        timeout=5
                    )
                    synced += 1
                except:
                    pass

        if synced > 0:
            print(f"[Sync] Synced {synced} nodes from {peer_ip}")

        return True

    except Exception as e:
        print(f"[Sync] Error syncing with {peer_ip}: {e}")
        return False


def sync_manager():
    """Periodically sync with discovered peers"""
    print(f"[Sync] Starting sync manager, interval={SYNC_INTERVAL}s")

    while True:
        time.sleep(SYNC_INTERVAL)

        with peers_lock:
            active_peers = [
                (ip, p) for ip, p in dns_peers.items()
                if time.time() - p['last_seen'] < 120  # Seen in last 2 min
            ]

        if not active_peers:
            continue

        local_hash = get_db_hash()

        for peer_ip, peer_info in active_peers:
            # Only sync if hashes differ
            if peer_info['db_hash'] != local_hash:
                print(f"[Sync] Hash mismatch with {peer_info['hostname']}, syncing...")
                sync_with_peer(peer_ip, peer_info['api_port'])


def cleanup_stale_peers():
    """Remove peers not seen recently"""
    while True:
        time.sleep(120)

        with peers_lock:
            now = time.time()
            stale = [ip for ip, p in dns_peers.items() if now - p['last_seen'] > 300]
            for ip in stale:
                print(f"[Multicast] Removing stale peer: {dns_peers[ip]['hostname']} ({ip})")
                del dns_peers[ip]


def get_peers():
    """Get list of active peers (for API)"""
    with peers_lock:
        return [
            {
                'hostname': p['hostname'],
                'ip': ip,
                'api_port': p['api_port'],
                'node_count': p['node_count'],
                'last_seen': p['last_seen'],
                'age_seconds': int(time.time() - p['last_seen'])
            }
            for ip, p in dns_peers.items()
            if time.time() - p['last_seen'] < 300
        ]


# Flask API extension for peer info
def register_peer_routes(app):
    """Register peer-related API routes"""
    from flask import jsonify

    @app.route('/api/v1/peers', methods=['GET'])
    def list_peers():
        """List discovered DNS peers"""
        return jsonify({
            'peers': get_peers(),
            'count': len(get_peers()),
            'local': {
                'hostname': HOSTNAME,
                'ip': get_local_ip(),
                'api_port': LOCAL_API_PORT,
                'node_count': get_node_count(),
                'db_hash': get_db_hash()
            }
        })

    @app.route('/api/v1/sync', methods=['POST'])
    def force_sync():
        """Force sync with all peers"""
        synced = 0
        for peer in get_peers():
            if sync_with_peer(peer['ip'], peer['api_port']):
                synced += 1
        return jsonify({'status': 'ok', 'peers_synced': synced})


def start_multicast():
    """Start all multicast threads"""
    threads = [
        threading.Thread(target=multicast_sender, daemon=True, name='mcast-sender'),
        threading.Thread(target=multicast_receiver, daemon=True, name='mcast-receiver'),
        threading.Thread(target=sync_manager, daemon=True, name='sync-manager'),
        threading.Thread(target=cleanup_stale_peers, daemon=True, name='peer-cleanup'),
    ]

    for t in threads:
        t.start()
        print(f"[Multicast] Started thread: {t.name}")

    return threads


if __name__ == '__main__':
    print("=" * 60)
    print("Mesh DNS Multicast Discovery & Sync")
    print("=" * 60)
    print(f"Multicast Group: {MCAST_GROUP}:{MCAST_PORT}")
    print(f"Local API: http://{get_local_ip()}:{LOCAL_API_PORT}")
    print(f"Announce Interval: {ANNOUNCE_INTERVAL}s")
    print(f"Sync Interval: {SYNC_INTERVAL}s")
    print("=" * 60)

    threads = start_multicast()

    # Keep main thread alive
    try:
        while True:
            time.sleep(60)
            peers = get_peers()
            print(f"[Status] Active peers: {len(peers)}, Local nodes: {get_node_count()}")
    except KeyboardInterrupt:
        print("\nShutting down...")
