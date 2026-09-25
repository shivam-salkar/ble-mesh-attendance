# Development Guide

This document outlines the workflow, development environment prerequisites, and conventions for contributing to the `ble-mesh-attendance` repository.

## Prerequisites

1. **Flutter SDK:**
   - Version: `>= 3.24.0` (Dart `>= 3.5.0`)
   - Platform toolchains: Android Studio / Android SDK, Xcode (macOS only)
2. **ESP-IDF:**
   - Version: `v5.1` or later (v5.2+ recommended)
   - Target: `esp32s3`
3. **Backend Tools:**
   - Node.js `>= 20.x`
   - Supabase CLI (`npm install -g supabase`)
   - Docker (required for running local Supabase)
4. **Git:**
   - Configured with your verified developer email and signing keys (if applicable)

## Repository Structure Overview

- `apps/mobile`: Flutter mobile application (Android & iOS).
- `firmware/esp32-gateway`: ESP32-S3 firmware built with ESP-IDF.
- `backend`: Supabase database migrations, seed scripts, and Edge Functions.
- `protocol`: Canonical specification of packet formats, protocol versions, and codecs.
- `docs`: Architecture, security, development, and external reference guides.
- `tests`: Cross-component integration tests and protocol verification suites.

## Workflow Rules

- **Branching Strategy:** `main` is the primary integration branch.
- **Commit Messages:** Follow conventional commits format:
  - `feat: ...` for new features
  - `fix: ...` for bug fixes
  - `docs: ...` for documentation updates
  - `chore: ...` for maintenance, build, and tooling changes
  - `refactor: ...` for code restructuring
- **Code Quality:**
  - Flutter: `flutter analyze` must pass with zero issues.
  - ESP-IDF: Code must compile with zero warnings using `-Wall -Wextra`.
- **Security:**
  - Never commit credentials, `.env` files, or private keys.
  - Review all third-party code for license compatibility and intellectual property rights.
