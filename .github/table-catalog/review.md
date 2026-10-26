# Microsoft Sentinel table catalog review

Observed: 2026-10-26
Source: https://api.loganalytics.io/v1/metadata
Previous tables: 941
Current tables: 945
Added: 4
Removed from catalog: 0

A table disappearing from this catalog does not prove that the service or table was removed. Confirm every change against public documentation before editing the baseline.

## Added tables

### NWPacketCaptureDnsQuery

- Type: Microsoft
- API state: Any
- Description: DNS queries and any matching responses observed in packet captures.

### NWPacketCaptureHttpTransaction

- Type: Microsoft
- API state: Any
- Description: HTTP transactions observed in packet captures. A record may contain only request or response evidence.

### NWPacketCaptureNetworkSession

- Type: Microsoft
- API state: Any
- Description: Network flows observed in packet captures, including endpoints, packet and byte counts, and connection states.

### NWPacketCaptureTlsSession

- Type: Microsoft
- API state: Any
- Description: Observed TLS handshake details, including negotiated parameters and certificates.

## Removed from catalog

None.

## Classification review

- Verify each table against Microsoft Learn and its connector or solution source.
- Separate documented facts from classification judgment.
- Use the baseline curator automatic proposal or human review flow before changing canonical data.
