# Multi-Site Setup Example

## Topology
```
Site A (Office):          Site B (Warehouse):
Internet ← [GW]              [Cache Server]
             ↓                      ↓
         [Router 1] ←─ WiFi ─→ [Router 3]
             ↓                      ↓
         Clients                Clients

Site C (Storage):
[GW Backup]
    ↓
[Router 2] ←─ WiFi mesh ─→ [connects to A & B]
    ↓
Clients
```

## Features

- Redundant gateways (A primary, C backup)
- Centralized cache (Site B)
- Full mesh connectivity
- Automatic failover

## Installation

Similar to single building, but with multiple gateways:

**Gateway A (primary)**: metric 10
**Gateway C (backup)**: metric 20

Cache server accessed from all sites via anycast.
