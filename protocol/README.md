# BLE Mesh Attendance Protocol Specification

This directory contains the authoritative specification for the project-specific communication protocol used across student mobile devices, peer relays, and the ESP32-S3 gateway.

> [!IMPORTANT]
> **The protocol is not yet finalized.**
> Actual packet schemas, binary layouts, serialization formats, and UUIDs will be defined in versioned specifications.

## Architectural Context

The networking model uses an **application-level BLE peer-to-peer relay** inspired by decentralized mesh networks (such as BitChat). 

**Important distinction:** This protocol is **NOT** Bluetooth SIG Mesh (or ESP-BLE-MESH). It runs on top of standard BLE GATT/GAP advertising and characteristics at the application layer to achieve multi-hop peer relay across consumer mobile devices without specialized OS-level mesh support.

## Intended Packet Concepts

The protocol will incorporate the following core packet concepts:

1. **Protocol Version:** Identifies the packet format version to ensure backward and forward compatibility.
2. **Packet ID:** Unique nonce/identifier for each generated packet, used for duplicate suppression and routing loops prevention across relay hops.
3. **Session ID:** Ephemeral classroom attendance session identifier issued by the faculty/gateway.
4. **Temporary Student Token:** Ephemeral, time-limited cryptographic token representing student presence (prevents leaking permanent student IDs over open radio).
5. **Timestamp:** Epoch millisecond timestamp of packet creation for replay prevention and validity checks.
6. **Time-To-Live (TTL):** Maximum number of hops a packet can traverse before being dropped by relay peers.
7. **Hop Count:** Number of relays a packet has traversed, updated by each forwarding peer.
8. **Packet Type:** Indicates message purpose (e.g. Discovery / Beacon, Attendance Submission, Ingestion Ack, Route Inquiry).
9. **Cryptographic Authentication / Signature:** Public-key cryptographic signature (e.g., Ed25519) ensuring packet authenticity and non-repudiation.
10. **Acknowledgement (ACK):** Return receipt propagated back from the gateway (or direct peer) to confirm receipt.
11. **Expiry:** Expiration window after which peers must discard the packet from memory buffers.

## Versioning Structure

Formal packet specifications will be versioned sequentially under `versions/`:

```
protocol/
├── README.md
└── versions/
    └── v1/
        └── packet-spec.md
```
*(Version v1 will be authored in a subsequent milestone).*
