# graphx_connect roadmap

Keep the API small: sessions, peers and messages.

## Current foundation

- native LAN host/discover/join through Bonjour/mDNS + direct WebSocket;
- remote short-code rendezvous + ordered WebRTC DataChannel;
- server-provided short-lived ICE/TURN configuration;
- multiple peers on hosted sessions;
- stable peer identity across explicit reconnects;
- structured messages and binary packets;
- raw binary mode with zero package envelope;
- optional 4-byte sender sequencing;
- handshake-level protocol/binary-mode compatibility;
- RTT measurement through peer latency.

## Next hardening

- exercise browser ↔ browser, browser ↔ native and native ↔ native paths;
- keep established WebRTC traffic alive when signaling disappears;
- expose read-only selected-path diagnostics without leaking WebRTC objects;
- improve close/handshake failure reasons;
- verify TURN/direct behavior against production rendezvous infrastructure.

## TODO: streams

Do not add `sendStream` until the contract includes:

- bounded buffering;
- DataChannel/WebSocket backpressure;
- cancellation;
- measured chunk sizing;
- slow-receiver behavior;
- allocation/copy measurements.

`sendBytes` remains the packet primitive.

## Later: server-backed sessions

A future server transport should converge on the same `GSession` model for
authoritative games and tools. Do not mix rendezvous/signaling with intentional
application-server traffic.

## Non-goals

GraphX Connect does not know about game entities, input prediction, rollback,
scene graphs, synchronized nodes, accounts, persistence or file manifests.
