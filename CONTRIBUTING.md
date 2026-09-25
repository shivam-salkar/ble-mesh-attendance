# Contributing Guidelines

Thank you for your interest in contributing to the **BLE Mesh Attendance** project.

## Proprietary Software Notice

> [!IMPORTANT]
> This repository contains **proprietary software** protected under copyright law (All Rights Reserved).
> Repository access is strictly controlled by the project owner. Contributions require explicit prior written authorization.

By submitting code, documentation, or other materials to this repository, you acknowledge and agree that:
1. All contributions become part of the proprietary codebase owned by Shivam Salkar unless explicitly agreed otherwise in writing.
2. You have the full right and legal authority to contribute the code without infringing on third-party intellectual property rights.

## Intellectual Property & Third-Party Code

- **No Unauthorized Copying:** Do NOT copy, paste, or adapt source code from third-party repositories or open-source projects without verifying that the license permits such use and receiving written consent from the project owner.
- **Reference Implementations:** Public projects such as BitChat are consulted for high-level architectural ideas, wire formats, and protocols. Do not copy their source code directly into this repository.
- **Dependency Documentation:** All third-party dependencies must be declared in official package manifests (`pubspec.yaml`, `idf_component.yml`, etc.) and documented with their license terms.
- **No Incompatible Licenses:** Do not introduce code governed by viral copyleft licenses (e.g. GPL, AGPL) that would compromise the proprietary licensing of this repository.

## Security & Secrets

- **Zero Secrets Policy:** Never commit secrets, API keys (Supabase service role keys, AWS keys, etc.), private keys, certificates, or `.env` files.
- If you accidentally commit a credential, immediately notify the project owner so it can be rotated and scrubbed from history.

## Development Standards

1. **Flutter Mobile:**
   - Run `flutter analyze` and ensure zero warnings or errors.
   - Run `flutter test` before submitting changes.
2. **ESP32 Firmware:**
   - Target ESP32-S3 using ESP-IDF v5.1+.
   - Keep components modular and cleanly separated.
3. **Commit Messages:**
   - Use conventional commit messages (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`).
