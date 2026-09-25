# System Architecture

## Overview

The BLE Mesh Attendance system is designed for high-density lecture halls where cellular or campus Wi-Fi connectivity may be spotty, overwhelmed, or inaccessible for all students simultaneously. At the conclusion of a lecture, students trigger an explicit attendance flow in their mobile app. Rather than requiring direct network connectivity to the cloud, attendance payloads propagate hop-by-hop via Bluetooth Low Energy (BLE) to a physical classroom gateway (ESP32-S3), which forwards verified payloads over Wi-Fi to Supabase.

## High-Level Flow

```text
Student Mobile App (Flutter)
            ↓
     Phone BLE Layer
            ↓
Application-Level Peer Relay (Multi-hop BLE)
            ↓
  ESP32-S3 Classroom Gateway
            ↓
          Wi-Fi
            ↓
    Backend / Supabase
            ↓
   PostgreSQL Database
```

## Important Architectural Distinction

> [!IMPORTANT]
> **Student phones are intended to participate in an application-level BLE peer network. This is distinct from Bluetooth SIG Mesh.**

### Why Not Bluetooth SIG Mesh (or ESP-BLE-MESH)?
- Standard consumer smartphones (Android and iOS) do **not** provide standard developer APIs to participate directly as nodes in a Bluetooth SIG Mesh network (e.g. PB-ADV, Mesh network/transport layers) without specialized vendor firmware or proprietary platform daemons.
- ESP-BLE-MESH is Espressif's implementation of the Bluetooth SIG Mesh standard for microcontrollers. While educational for understanding mesh flooding and routing, it cannot be run directly across un-rooted Android and iOS devices.

### Application-Level BLE Peer Relay Architecture
- Operates entirely at the application layer using standard, ubiquitous BLE GAP (advertising/scanning) and GATT (services/characteristics).
- Devices act simultaneously (or interleaved) as BLE Centrals and Peripherals.
- Inspired by peer-to-peer protocols like BitChat, messages are wrapped in custom packets with TTL (Time-To-Live), unique Packet IDs for duplicate suppression, and cryptographic signatures.
- Nearby peers automatically relay encrypted attendance packets toward the classroom ESP32-S3 gateway.

## Component Responsibilities

1. **Flutter Mobile Client (`apps/mobile/`):**
   - Initiates attendance submission upon user confirmation at lecture end.
   - Future identity verification layer (e.g., face verification / biometric check).
   - Packet assembly with ephemeral tokens and signatures.
   - Scanning, advertising, and peer relaying of packets.
   - Listens for gateway ACK.

2. **ESP32-S3 Classroom Gateway (`firmware/esp32-gateway/`):**
   - Fixed physical hardware located inside the classroom.
   - Advertises classroom session identity over BLE.
   - Ingests incoming attendance packets from direct connections and multi-hop relays.
   - Performs sanity checks and packet deduplication.
   - Issues cryptographic ACKs back into the peer network.
   - Forwards packets over campus Wi-Fi to Supabase Edge Functions.

3. **Supabase Cloud Backend (`backend/`):**
   - Validates cryptographic signatures, session expiry, and attendance rules.
   - Enforces PostgreSQL Row Level Security (RLS).
   - Stores finalized attendance records in PostgreSQL.
   - Admin/Faculty dashboard for attendance viewing and session management.
