#!/usr/bin/env python3
"""
Mesh Network P2P IPAM (runs on EVERY node)
- No central server - all nodes participate
- Multicast consensus for IP allocation
- Automatic conflict resolution
- Self-healing and fault-tolerant
"""

import json
import socket
import struct
import threading
import time
import sqlite3
import ipaddress
import hashlib
import random
import os
from pathlib import Path

# Configuration
DB_PATH = os.environ.get('IPAM_DB_PATH', '/var/lib/mesh-network/ipam.db')
MCAST_GROUP = '239.255.77.70'
MCAST_PORT = 5382
HOSTNAME = os.environ.get('HOSTNAME', socket.gethostname())
NODE_TYPE = os.environ.get('MESH_NODE_TYPE', 'default')

# IP Ranges
NETWORK_RANGES = {
    'mesh-router': '10.10.1.0/24',
    'lan-router': '10.10.2.0/24',
    'gateway': '10.10.3.0/24',
    'monitoring': '10.10.4.0/24',
    'dns-server': '10.10.5.0/24',
    'emergency': '10.10.6.0/24',
    'comm-hub': '10.10.7.0/24',
    'data-node': '10.10.8.0/24',
    'portable-gateway': '10.10.9.0/24',
    'default': '10.10.100.0/24'
}

LEASE_TIME = 86400  # 24 hours
CONSENSUS_TIMEOUT = 3  # seconds to wait for consensus
ANNOUNCE_INTERVAL = 60  # seconds between announcements

# Shared state
known_allocations = {}  # {ip: {hostname, node_type, expires, announced_by}}
allocations_lock = threading.Lock()
my_ip = None


def init_db():
    """Initialize local IPAM database"""
    Path(DB_PATH).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''
        CREATE TABLE IF NOT EXISTS allocations (
            ip TEXT PRIMARY KEY,
            hostname TEXT,
            node_type TEXT,
            mac TEXT,
            allocated_at INTEGER,
            expires_at INTEGER,
            confirmed INTEGER DEFAULT 0
        )
    ''')
    c.execute('''
        CREATE TABLE IF NOT EXISTS my_allocation (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            ip TEXT,
            allocated_at INTEGER,
            expires_at INTEGER
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
        return None


def get_mac(interface='eth0'):
    """Get MAC address"""
    try:
        with open(f'/sys/class/net/{interface}/address') as f:
            return f.read().strip()
    except:
        return None


def get_range_for_type(node_type):
    """Get IP range for node type"""
    cidr = NETWORK_RANGES.get(node_type, NETWORK_RANGES['default'])
    return ipaddress.ip_network(cidr)


def load_known_allocations():
    """Load allocations from local database"""
    global known_allocations
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('SELECT ip, hostname, node_type, expires_at FROM allocations WHERE expires_at > ?',
              (int(time.time()),))

    with allocations_lock:
        for ip, hostname, node_type, expires in c.fetchall():
            known_allocations[ip] = {
                'hostname': hostname,
                'node_type': node_type,
                'expires': expires,
                'announced_by': 'local'
            }
    conn.close()


def save_allocation(ip, hostname, node_type, mac, expires):
    """Save allocation to local database"""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''
        INSERT OR REPLACE INTO allocations (ip, hostname, node_type, mac, allocated_at, expires_at, confirmed)
        VALUES (?, ?, ?, ?, ?, ?, 1)
    ''', (ip, hostname, node_type, mac, int(time.time()), expires))
    conn.commit()
    conn.close()


def get_my_allocation():
    """Get this node's allocated IP"""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('SELECT ip, expires_at FROM my_allocation WHERE id = 1')
    row = c.fetchone()
    conn.close()

    if row and row[1] > time.time():
        return row[0]
    return None


def save_my_allocation(ip, expires):
    """Save this node's allocation"""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''
        INSERT OR REPLACE INTO my_allocation (id, ip, allocated_at, expires_at)
        VALUES (1, ?, ?, ?)
    ''', (ip, int(time.time()), expires))
    conn.commit()
    conn.close()


def find_free_ip(node_type):
    """Find a free IP in the range for this node type"""
    network = get_range_for_type(node_type)

    with allocations_lock:
        allocated = set(known_allocations.keys())

    # Skip .1 (gateway) and .255 (broadcast)
    candidates = [str(ip) for ip in network.hosts() if not str(ip).endswith('.1')]

    # Shuffle to reduce collision probability
    random.shuffle(candidates)

    for ip in candidates:
        if ip not in allocated:
            return ip

    return None


def send_multicast(msg_dict):
    """Send multicast message"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
        msg = json.dumps(msg_dict).encode('utf-8')
        sock.sendto(msg, (MCAST_GROUP, MCAST_PORT))
        sock.close()
    except Exception as e:
        print(f"[IPAM] Multicast send error: {e}")


def request_ip():
    """Request an IP address via multicast consensus"""
    global my_ip

    # Check if we already have a valid allocation
    existing = get_my_allocation()
    if existing:
        print(f"[IPAM] Using existing allocation: {existing}")
        my_ip = existing
        return existing

    # Find a candidate IP
    candidate_ip = find_free_ip(NODE_TYPE)
    if not candidate_ip:
        print("[IPAM] No free IPs available!")
        return None

    request_id = hashlib.md5(f"{HOSTNAME}:{time.time()}:{random.random()}".encode()).hexdigest()[:8]

    print(f"[IPAM] Requesting IP {candidate_ip} (request {request_id})...")

    # Announce our intention
    send_multicast({
        'type': 'ip-request',
        'request_id': request_id,
        'ip': candidate_ip,
        'hostname': HOSTNAME,
        'node_type': NODE_TYPE,
        'mac': get_mac(),
        'timestamp': int(time.time())
    })

    # Wait for objections
    time.sleep(CONSENSUS_TIMEOUT)

    # Check if IP was claimed by someone else during consensus
    with allocations_lock:
        if candidate_ip in known_allocations:
            owner = known_allocations[candidate_ip]
            if owner['hostname'] != HOSTNAME:
                print(f"[IPAM] IP {candidate_ip} claimed by {owner['hostname']}, retrying...")
                return request_ip()  # Retry with different IP

    # No objections - claim the IP
    expires = int(time.time()) + LEASE_TIME

    send_multicast({
        'type': 'ip-claim',
        'ip': candidate_ip,
        'hostname': HOSTNAME,
        'node_type': NODE_TYPE,
        'mac': get_mac(),
        'expires': expires,
        'timestamp': int(time.time())
    })

    # Save locally
    save_allocation(candidate_ip, HOSTNAME, NODE_TYPE, get_mac(), expires)
    save_my_allocation(candidate_ip, expires)

    with allocations_lock:
        known_allocations[candidate_ip] = {
            'hostname': HOSTNAME,
            'node_type': NODE_TYPE,
            'expires': expires,
            'announced_by': 'self'
        }

    my_ip = candidate_ip
    print(f"[IPAM] Successfully claimed IP: {candidate_ip}")

    return candidate_ip


def announce_allocation():
    """Periodically announce our allocation"""
    while True:
        time.sleep(ANNOUNCE_INTERVAL)

        if my_ip:
            send_multicast({
                'type': 'ip-announce',
                'ip': my_ip,
                'hostname': HOSTNAME,
                'node_type': NODE_TYPE,
                'expires': int(time.time()) + LEASE_TIME,
                'timestamp': int(time.time())
            })


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

    while True:
        try:
            data, addr = sock.recvfrom(4096)
            msg = json.loads(data.decode('utf-8'))

            msg_type = msg.get('type')
            msg_ip = msg.get('ip')
            msg_hostname = msg.get('hostname')

            # Ignore our own messages
            if msg_hostname == HOSTNAME:
                continue

            if msg_type == 'ip-request':
                # Someone is requesting an IP - check for conflicts
                with allocations_lock:
                    if msg_ip in known_allocations:
                        owner = known_allocations[msg_ip]
                        if owner['hostname'] != msg_hostname and owner['expires'] > time.time():
                            # Conflict! Send objection
                            send_multicast({
                                'type': 'ip-objection',
                                'request_id': msg.get('request_id'),
                                'ip': msg_ip,
                                'current_owner': owner['hostname'],
                                'objector': HOSTNAME
                            })
                            print(f"[IPAM] Objected to {msg_hostname} claiming {msg_ip} (owned by {owner['hostname']})")

            elif msg_type == 'ip-claim' or msg_type == 'ip-announce':
                # Someone claimed or announced an IP
                with allocations_lock:
                    # Check for conflict with our IP
                    if msg_ip == my_ip and msg_hostname != HOSTNAME:
                        # Conflict! Lower hostname wins (deterministic)
                        if HOSTNAME < msg_hostname:
                            print(f"[IPAM] Conflict with {msg_hostname} for {msg_ip} - we keep it (lower hostname)")
                            send_multicast({
                                'type': 'ip-claim',
                                'ip': my_ip,
                                'hostname': HOSTNAME,
                                'node_type': NODE_TYPE,
                                'expires': int(time.time()) + LEASE_TIME
                            })
                        else:
                            print(f"[IPAM] Conflict with {msg_hostname} for {msg_ip} - they win, we re-request")
                            known_allocations.pop(my_ip, None)
                            # Request new IP in background
                            threading.Thread(target=request_ip, daemon=True).start()
                    else:
                        # Record their allocation
                        known_allocations[msg_ip] = {
                            'hostname': msg_hostname,
                            'node_type': msg.get('node_type', 'unknown'),
                            'expires': msg.get('expires', int(time.time()) + LEASE_TIME),
                            'announced_by': addr[0]
                        }

                        # Save to local DB for persistence
                        save_allocation(msg_ip, msg_hostname, msg.get('node_type'),
                                       msg.get('mac'), msg.get('expires', int(time.time()) + LEASE_TIME))

            elif msg_type == 'ip-release':
                # Someone released an IP
                with allocations_lock:
                    if msg_ip in known_allocations:
                        del known_allocations[msg_ip]

                conn = sqlite3.connect(DB_PATH)
                c = conn.cursor()
                c.execute('DELETE FROM allocations WHERE ip = ?', (msg_ip,))
                conn.commit()
                conn.close()

            elif msg_type == 'ip-query':
                # Someone is asking about allocations - respond with ours
                if my_ip:
                    send_multicast({
                        'type': 'ip-announce',
                        'ip': my_ip,
                        'hostname': HOSTNAME,
                        'node_type': NODE_TYPE,
                        'expires': int(time.time()) + LEASE_TIME
                    })

        except json.JSONDecodeError:
            pass
        except Exception as e:
            print(f"[IPAM] Listener error: {e}")


def query_network():
    """Query network for existing allocations"""
    print("[IPAM] Querying network for existing allocations...")

    send_multicast({
        'type': 'ip-query',
        'hostname': HOSTNAME,
        'timestamp': int(time.time())
    })

    # Wait for responses
    time.sleep(3)

    with allocations_lock:
        print(f"[IPAM] Discovered {len(known_allocations)} existing allocations")


def configure_interface(ip, interface='eth0'):
    """Configure network interface with allocated IP"""
    import subprocess

    network = get_range_for_type(NODE_TYPE)
    prefix_len = network.prefixlen
    gateway = str(list(network.hosts())[0])  # First host is gateway

    print(f"[IPAM] Configuring {interface} with {ip}/{prefix_len}")

    try:
        # Flush existing IPs in our range
        subprocess.run(['ip', 'addr', 'flush', 'dev', interface], capture_output=True)

        # Add new IP
        subprocess.run(['ip', 'addr', 'add', f'{ip}/{prefix_len}', 'dev', interface], check=True)
        subprocess.run(['ip', 'link', 'set', interface, 'up'], check=True)

        # Add default route if not exists
        subprocess.run(['ip', 'route', 'add', 'default', 'via', gateway, 'dev', interface],
                      capture_output=True)

        print(f"[IPAM] Interface configured successfully")
        return True

    except subprocess.CalledProcessError as e:
        print(f"[IPAM] Failed to configure interface: {e}")
        return False


def cleanup_expired():
    """Periodically cleanup expired allocations"""
    while True:
        time.sleep(300)  # Every 5 minutes

        now = int(time.time())

        with allocations_lock:
            expired = [ip for ip, info in known_allocations.items() if info['expires'] < now]
            for ip in expired:
                del known_allocations[ip]

        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute('DELETE FROM allocations WHERE expires_at < ?', (now,))
        conn.commit()
        conn.close()

        if expired:
            print(f"[IPAM] Cleaned up {len(expired)} expired allocations")


def main():
    """Main entry point"""
    print("=" * 50)
    print("Mesh Network P2P IPAM")
    print("=" * 50)
    print(f"Hostname: {HOSTNAME}")
    print(f"Node Type: {NODE_TYPE}")
    print(f"Multicast: {MCAST_GROUP}:{MCAST_PORT}")
    print("=" * 50)

    init_db()
    load_known_allocations()

    # Start listener thread
    threading.Thread(target=multicast_listener, daemon=True).start()

    # Start cleanup thread
    threading.Thread(target=cleanup_expired, daemon=True).start()

    # Query network for existing allocations
    query_network()

    # Request our IP
    ip = request_ip()

    if ip:
        # Configure interface
        configure_interface(ip)

        # Start announcement thread
        threading.Thread(target=announce_allocation, daemon=True).start()

        print(f"\n[IPAM] Node IP: {ip}")
        print("[IPAM] Running... (Ctrl+C to stop)")

        # Keep running
        try:
            while True:
                time.sleep(60)
                with allocations_lock:
                    print(f"[IPAM] Status: {len(known_allocations)} known allocations, my IP: {my_ip}")
        except KeyboardInterrupt:
            print("\n[IPAM] Shutting down...")

            # Announce release
            if my_ip:
                send_multicast({
                    'type': 'ip-release',
                    'ip': my_ip,
                    'hostname': HOSTNAME
                })
    else:
        print("[IPAM] Failed to obtain IP address!")
        return 1

    return 0


if __name__ == '__main__':
    exit(main())
