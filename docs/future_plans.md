# Future Plans: Remote Attestation and Advanced Security

This document outlines potential future security enhancements for the Pi cluster,
focusing on remote attestation and its requirements.

---

## Remote Attestation Without a Local TPM

### The Short Answer: Not Possible

There is **no way** to get cryptographic remote attestation of a device without
a hardware root of trust (TPM or equivalent) **on that device**.

- **Pi-A's TPM** (e.g. px5n0) can only attest **Pi-A's** boot state. It signs
  Pi-A's PCR measurements, proving Pi-A booted trusted software. It cannot make
  any claims about Pi-B's state.
- **Remote attestation** means: Pi-B proves to Pi-A (or a verifier service)
  that Pi-B booted a trusted software stack. This requires Pi-B to have its own
  TPM that measured the boot chain and can produce a signed TPM quote.
- Without a TPM on Pi-B, there is no hardware-backed guarantee that Pi-B is
  running the software it claims to be running. An attacker who compromises
  Pi-B can report fake measurements.

### What Works Without a TPM on Pi-B

**Network-bound disk encryption (Tang/Clevis)** -- already implemented:

- Pi-B unlocks its LUKS volume only when it can reach Pi-A's Tang server on the
  local network.
- This provides **location binding** ("unlock only on the right network"), not
  **software integrity** ("unlock only if the boot chain is trusted").
- If someone steals Pi-B's SD card and moves it to another network, the volume
  stays locked.

**Client certificate authentication:**

- Pi-B could present a TLS client certificate to Pi-A to prove its identity.
- This proves "the entity holding this private key is requesting access," not
  "the software stack is untampered."
- An attacker who extracts the private key (possible without disk encryption or
  with a compromised root) can impersonate Pi-B.

**Neither of these approaches verifies Pi-B's software state.** They verify
identity or network location, which are different (weaker) guarantees.

---

## Future: TPM-Based Remote Attestation (When Pi-B Has a TPM)

If Pi-B gets its own TPM module, full remote attestation becomes possible. Here
is the planned approach.

### Architecture

```
┌──────────────────────────────────┐
│   Attestation Verifier (Pi-A)    │
│                                  │
│   Holds:                         │
│   - Pi-B's TPM public key (EK)  │
│   - Expected PCR values for      │
│     Pi-B's known-good config     │
│                                  │
│   On request:                    │
│   1. Sends a random nonce        │
│   2. Receives TPM quote from     │
│      Pi-B (signed PCRs + nonce)  │
│   3. Verifies signature against  │
│      Pi-B's known EK             │
│   4. Compares PCR values against │
│      expected whitelist           │
│   5. If valid: releases LUKS key │
│      If invalid: rejects         │
└──────────────┬───────────────────┘
               │
          LAN / private network
               │
┌──────────────┴───────────────────┐
│   Pi-B (with TPM)                │
│                                  │
│   Boot sequence:                 │
│   1. Firmware measures into PCRs │
│   2. Kernel + initramfs measured │
│   3. Network comes up in initrd  │
│   4. Initrd client contacts      │
│      attestation verifier        │
│   5. Receives nonce              │
│   6. Produces TPM quote          │
│      (tpm2_quote with nonce)     │
│   7. Sends quote to verifier     │
│   8. Receives LUKS key if valid  │
│   9. Unlocks LUKS volume         │
└──────────────────────────────────┘
```

### Implementation Steps

1. **Add TPM hardware to Pi-B** -- same compatible modules as Pi-A (see
   `docs/secure-boot-guide.md` for the hardware list).

2. **Implement or adopt an attestation verifier** -- a service running on Pi-A
   (or a dedicated machine) that:
   - Accepts attestation requests over HTTPS
   - Sends a fresh nonce for each request
   - Verifies TPM quotes using `tpm2_checkquote`
   - Checks PCR values against a known-good whitelist
   - Returns the LUKS key (or a Tang-like response) if attestation passes
   - Possible tools: `tpm2-tools` (`tpm2_quote`, `tpm2_checkquote`), or a
     higher-level framework like [Keylime](https://keylime.dev/) or
     [go-attestation](https://github.com/google/go-attestation)

3. **Define expected PCR policy for Pi-B** -- record the PCR values from a
   known-good boot of Pi-B:
   ```bash
   # On Pi-B after a trusted boot
   tpm2_pcrread sha256:0,2,4,7
   ```
   Store these values on the verifier. Update them after each kernel or firmware
   change (similar to TPM re-enrollment, but on the verifier side).

4. **Implement initrd attestation client** -- a script or service in Pi-B's
   initrd that:
   - Contacts the attestation verifier
   - Receives a nonce
   - Calls `tpm2_quote` with the nonce and relevant PCRs
   - Sends the quote back to the verifier
   - Receives the LUKS key and unlocks the volume
   - Falls back to passphrase if attestation fails

5. **Optional: Combine with Tang/Clevis** -- the attestation verifier could
   act as a conditional Tang server that only responds to Clevis requests after
   attestation passes. This would integrate with the existing Clevis
   infrastructure rather than replacing it.

6. **Document and test** -- update the secure boot guide with the attestation
   workflow, including PCR update procedures after `nixos-rebuild switch`.

### PCR Update Workflow

After any `nixos-rebuild switch` that changes the kernel, initramfs, or firmware:

1. Boot Pi-B (it will fail attestation and fall back to passphrase)
2. Record new PCR values: `tpm2_pcrread sha256:0,2,4,7`
3. Update the verifier's whitelist with the new values
4. Reboot Pi-B -- attestation should now pass

This is similar to TPM re-enrollment but happens on the verifier, not on Pi-B.

### Tools and Frameworks to Evaluate

- **[Keylime](https://keylime.dev/)** -- full remote attestation framework with
  agent/verifier architecture. May be heavy for a Pi cluster but is the most
  mature option. Has a NixOS package (`keylime`).
- **[go-attestation](https://github.com/google/go-attestation)** -- Google's Go
  library for TPM attestation. Lower-level, would require building a custom
  verifier service.
- **Custom `tpm2-tools` scripts** -- simplest approach, using `tpm2_quote` on
  Pi-B and `tpm2_checkquote` on Pi-A. Good for a small cluster where a full
  framework is overkill.

---

## Software-Only "Attestation" (Not Recommended)

For completeness: it is technically possible to have Pi-B report its kernel
hash, initramfs hash, or other boot measurements to Pi-A **without a TPM**.
For example, Pi-B could compute `sha256sum /boot/Image` and send the hash.

**This is not secure and should not be relied upon.**

- An attacker who compromises Pi-B can report **any hash they want**. Without a
  TPM, there is no hardware-backed guarantee that the reported hash matches
  what actually booted.
- The measurement is taken by software running on Pi-B. If that software is
  compromised, the measurement is meaningless.
- This provides a false sense of security -- it detects accidental
  misconfiguration but not deliberate attacks.

If you need software integrity verification without a TPM, consider:

- **dm-verity** -- kernel-level read-only filesystem verification. Detects
  tampering of the root filesystem at block level. Does not require a TPM but
  only protects the root FS (not the kernel/initramfs).
- **IMA (Integrity Measurement Architecture)** -- Linux kernel subsystem that
  measures files at access time. Without a TPM to anchor the measurements, an
  attacker can tamper with the IMA log.

Neither of these replaces remote attestation. They are defense-in-depth
measures, not standalone solutions.

---

## Summary

| Approach | Requires TPM on Pi-B | Guarantees |
|----------|:---:|------------|
| Tang/Clevis (current) | No | Location binding (right network) |
| Client certificates | No | Identity (who is requesting) |
| Software hash reporting | No | Nothing reliable (attacker can lie) |
| TPM remote attestation | **Yes** | Software integrity (trusted boot chain) |
| TPM + Tang/Clevis | **Yes** | Software integrity + location binding |

**Next step:** Acquire a TPM module for Pi-B, then implement the attestation
verifier. Until then, Tang/Clevis provides the best available protection for
headless Pis without local TPMs.
