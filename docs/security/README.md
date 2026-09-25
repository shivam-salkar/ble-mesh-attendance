# Security Architecture & Considerations

> [!NOTE]
> The security architecture described here represents foundational guidelines and intended protections. **The detailed security architecture is not yet finalized.**

## Core Principles

### 1. No Secrets in Git
- Under no circumstances should secrets, API keys, service tokens, private keys, or passwords be committed to this repository.
- Local configuration files (`.env`, `.env.*`) are git-ignored.
- CI/CD pipelines must inject credentials via encrypted secrets (e.g., GitHub Actions Secrets).

### 2. Credential Isolation & Least Privilege
- **Supabase Service Role Key:** Possesses full administrative rights bypassing RLS. Must **never** be embedded, bundled, or accessible in mobile application builds or gateway firmware. Only trusted server-side Edge Functions may use elevated credentials.
- **Supabase Anon Key:** Usable by clients only alongside strict, defense-in-depth PostgreSQL Row Level Security (RLS) policies.
- **Gateway Wi-Fi & API Credentials:** Must be securely provisioned to hardware NVS (Non-Volatile Storage) with flash encryption enabled in production.

### 3. Privacy over the Air (BLE)
- **No Permanent Student Identifiers:** Broadcasted and relayed BLE packets must not expose permanent identifiers (e.g. Student ID numbers, names, email addresses, or static device MAC addresses).
- **Ephemeral Session Tokens:** Devices generate ephemeral, cryptographically bound tokens for the specific lecture session.
- **MAC Address Randomization:** Mobile OS BLE privacy mechanisms (resolvable private addresses) must be respected and accommodated.

### 4. Anti-Proxy & Replay Protection
- Attendance validation must **not** rely solely on client-side logic.
- **Packet Nonces & Expiry:** Packets contain unique Packet IDs, timestamps, and short TTLs to prevent replay attacks outside the designated lecture window.
- **Classroom Proximity & Gateway Validation:** Packets are valid only if received and verified through the designated classroom gateway during the active session.
- **Cryptographic Signatures:** Student attendance payloads will be signed using public-key cryptography (e.g., Ed25519) with keys secured in device-protected storage (Keystore / Keychain).

### 5. Biometric / Face Verification Integrity
- Raw biometric images must **not** be broadcasted unencrypted over the BLE relay network.
- Face verification is planned as an on-device identity confirmation step that gates cryptographic signature generation, preserving student privacy and minimizing packet payloads over bandwidth-constrained BLE.
