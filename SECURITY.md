# Security Policy

## Reporting Security Issues

If you discover a security vulnerability or sensitive information exposure within this repository, please report it directly to the project owner rather than opening a public issue.

- **Contact:** Shivam Salkar ([GitHub Profile](https://github.com/shivam-salkar))

## Security Guidelines & Constraints

> [!NOTE]
> The security architecture of this project is in active development and **is not yet finalized**. The following core constraints are mandatory across all contributions.

### 1. Zero Secrets in Version Control
- **No Credentials in Git:** Passwords, tokens, API keys, certificates, private keys, and encryption secrets must never be committed to Git.
- **Environment Files:** All `.env` and `.env.*` files are excluded by `.gitignore` and must remain local.

### 2. Backend & Key Isolation
- **Supabase Service-Role Keys:** The `service_role` key bypasses Row Level Security (RLS) entirely. It must **never** be exposed in client code (Flutter mobile app) or IoT gateway firmware.
- **Production Credentials:** Production database credentials and edge function secrets must be managed via encrypted environment variables or dedicated secret management services.

### 3. Over-the-Air Privacy & BLE Security
- **No Permanent Identifiers:** BLE packets transmitted over the air must never expose permanent student identifiers (such as student roll numbers, real names, or static MAC addresses).
- **Ephemeral Session Tokens:** All presence data transmitted over the peer relay must use short-lived, session-bound ephemeral tokens.
- **Anti-Replay Protections:** Packets must include nonces, timestamps, and limited TTL to prevent replay attacks outside the physical lecture duration.

### 4. Biometric Data Protection
- **Biometric / Face Verification:** Face verification will serve as an identity verification layer. Raw biometric imagery or facial templates must never be transmitted unencrypted across the BLE relay network. Verification must be executed locally on-device, gating cryptographic signature creation.
