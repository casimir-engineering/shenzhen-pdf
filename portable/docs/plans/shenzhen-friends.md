# Shenzhen Friends — implementation brief

Status: planned; Friends implementation has not started. Translation is a separate
active change. Owner: lead integrator. Date: 2026-10-12.

## Project-manager prompt

Implement Shenzhen Friends in ShenzhenPDF: private document sharing and messaging
alongside the reader and Collection. Prioritize responsiveness, straightforward
organization and reliable transfers. Match the existing compact native interface.
Use the contracts, phases and release gates below as the implementation plan.

First resolve the transport feasibility gates. Do not promise worldwide delivery,
select production hosting, or deploy a public service before those decisions are
recorded. Preserve the updater and signing pipeline. Maintain an implementation
journal and commit each meaningful, tested change. Do not interrupt the user's
running app; use isolated headless/native fixtures under the repository rules.

## Product contract

- Add a **Friends** vector icon between the top-bar Groups and Search buttons.
  Settings has **Enable Shenzhen Friends**; disabling it removes the icon.
- Public visibility is off by default. Proposed UI default: show the Friends icon
  until disabled; creating an identity requires first use.
- **Open decision — reception lifecycle:** the user is choosing between activation
  on first Friends use each launch and automatic reconnection after initial setup.
  The proposed strict-lazy baseline creates no helper, sockets, Bluetooth objects,
  timers, key reads or database opens before first use, with no new document-open
  work. Automatic reconnection would require an explicit deferred activation policy
  and measured resource budget; do not silently implement it on startup.
- In the strict-lazy baseline, closing the picker keeps the service available, but
  after restart reception waits for activation. When the final reader process exits,
  persist pending work and stop the helper; do not install a background login item.
  Revisit this lifecycle only if the user selects automatic availability.
- One friend identity and conversation, with **Local**, **Online** or **Offline**
  connection state. These are routes, not separate contact lists. Losing the local
  route does not imply Online until an Internet connection succeeds.
- LAN and Bluetooth discoveries combine into one row after identity verification.
  Prefer a working local network route; support Bluetooth-only discovery/transfer
  after the hardware feasibility gate. Preserve conversations across route changes.
- **Make myself visible for 5 minutes** enables public discovery. Show a countdown
  and **Stop**. Expiry, sleep/wake and disabling must not extend the deadline.
  Accepted friends reconnect privately without restarting public visibility.
- Local and online friend requests require recipient acceptance. People who know
  an add-ID may request friendship without nearby visibility. Block/remove works
  independently of visibility; blocked peers cannot reconnect or send offers.
- Users can set their profile name and avatar, exchange messages and links, and
  offer documents. Never automatically fetch remote link previews.
- Messages from accepted friends appear in conversation history without approval.
  Files require **Accept / Decline**. No file bytes before acceptance.
- Incoming decisions appear only as a badge on the Friends icon and entries in
  Inbox. No banners, sounds, Dock badges, modal interruptions or automatic opening.
  Unread messages may have a row marker inside Friends; do not add external alerts.
- All user payloads use authenticated end-to-end encryption: messages, documents,
  filenames, avatars and application metadata. Routing addresses, packet timing,
  sizes and minimal discovery data are not hidden by this promise.

## Interface and interaction

Use the existing toolbar, search-field, row and chat-panel components. Preserve
vector aspect ratios and sharp rendering. Every visible button must have a single
contiguous hit area; surrounding title-bar space remains draggable.

Friends opens an anchored picker, approximately 360–400 pt wide:

1. Search field matching the other app panels.
2. **Friends / Nearby / Inbox** tabs; Friends is the default on every opening.
3. Scrollable rows; profile and **Add by ID** are secondary footer controls.

Friends sorts by latest local interaction. Rows show avatar, name, last message or
transfer preview, timestamp and a small Local/Online/Offline icon with tooltip.
Search matches name and add-ID. Nearby shows the visibility action, its remaining
time and discoverable people. Distinguish permission denied, Bluetooth off,
searching and no results; do not present failures as an empty successful search.
Inbox contains pending friend requests and document offers; its count is the
number of pending decisions, deduplicated across reader windows.

Selecting a friend opens a resizable conversation panel beside the document and
closes the picker. Friends and AI use the same conversation-panel position, never
stacking two additional panels; switching preserves drafts, selection and scroll
position. Slash-agent progress stays in the friend composer. Hide is the first
toolbar action; the recipient and connection state follow. Conversation search is
below that toolbar. Messages run oldest to newest, with the composer at the bottom.
Search jumps to the exact message with a highlight. Transfer events stay in the
same history, including accepted, declined, cancelled and failed states.

- **#** opens a searchable picker of open/Collection documents. Selection inserts
  an attachment chip for an exact document revision; it does not transmit it.
- **/** asks the existing agent to prepare a draft: summary, document search result,
  chosen pages or another supported app output. Show cancellable progress and the
  resulting text/attachments. Keep recipient, filenames and page ranges visible.
- The human's **Send** authorizes the displayed message and attachment offers. A
  slash command explicitly asking to send identified content to the current friend,
  submitted with Send/Return, authorizes that scoped operation: prepare it, show cancellable progress and send
  when ready without a second confirmation. Merely typing a command starts no sending. A request only to prepare content stays
  a draft. If recipient or content is ambiguous, resolve that scope before sending.
  Do not silently add other recipients, documents or page ranges.
- Return sends; Shift+Return inserts a line. Escape dismisses the innermost picker
  first. Renaming is inline or an immediate anchored editor, without animation.
- Attachments show filename, type, size and status. Accepted files offer **Open**.
  Transfer progress is determinate when possible and always cancellable.
- Sent/received messages and transfer records are indexed locally. Cmd+K results
  include sender/conversation, timestamp and matching context; opening a result
  navigates to the highlighted message. No network call belongs in local search.

## Identity, discovery and transport

**Identity:** generate an immutable cryptographic identity locally on first setup.
Keep private keys in Keychain. Store friends by identity, never by display name,
word alias, IP address or Bluetooth address. A key change needs explicit review.
Use a maintained E2E protocol implementation, with a documented threat model and
security review; do not invent cryptographic primitives or a new ratchet. Approve
an ADR naming the exact library/protocol, licensing and maintenance policy, pairing,
forward secrecy, replay/key-change handling and Bluetooth/Internet interoperability
before implementing real payload transport.

**Add-ID:** use a versioned, licensed, reviewed list of 2,048 simple English words,
excluding offensive, violent, technical and easily confused terms. Two words give
4,194,304 combinations; they are public lookup aliases, not secrets. A single
transactional registry allocates unique aliases, retries collisions and gives the
older registration precedence. Correct a discovered conflict by changing the newer
alias and notifying its owner, without changing keys, friends or history. Offline
aliases remain provisional until registered. Define a measured occupancy/retry
threshold for three-word allocations; existing two-word IDs remain valid.

Bind signaling and the selected transport certificate/fingerprint to the accepted
friend identity. Server HTTPS or WebRTC encryption alone does not authenticate a
friend; reject substituted negotiation data.

A server can substitute a lookup key unless users verify it independently. Provide
an out-of-band verification code/QR fingerprint and distinguish verified from
unverified contacts. Acceptance alone does not prove someone's real-world identity.
Rate-limit lookups and requests; do not expose presence through public ID lookup.

**Nearby:** use separate LAN and CoreBluetooth adapters. On macOS, Apple's
MultipeerConnectivity does not supply Bluetooth. Advertise only opaque expiring
tokens; retrieve permitted profile data over the encrypted handshake. Trusted-peer
reconnection must not broadcast stable public identity or make a hidden person
appear in Nearby. Only during explicit public visibility may strangers retrieve
the chosen public name/avatar. Otherwise require a trusted-peer handshake. Permission
prompts occur only when the feature needs them.

**Internet:** minimal HTTPS signaling, alias lookup and expiring authenticated
rendezvous records; STUN for direct connection discovery. Candidate native transport:
libdatachannel, subject to dependency/license, binary-size, ICE-backend and security
review. Do not import a browser engine for messaging. Protocols must be portable
for later Linux, Windows and mobile clients; native UI remains platform-specific.

**Open decision — relay:** direct peer-to-peer is preferred and is the current
server constraint. Some NATs/firewalls prevent direct connectivity. The user has
been asked whether to allow a relay that forwards only E2E ciphertext, with no
persistent document storage. If approved, implement a bounded fallback; if declined,
show connection unavailable and retain the local queue. A relay is not a discovery-
only server and must be described and costed accordingly. Never fall back to cleartext.

**Offline:** without server payload storage, both peers must eventually connect at
the same time. Queue on the sender and show **Waiting for recipient**. Distinguish
Queued, Connecting, Sending and Delivered; Delivered requires a durable recipient
acknowledgement, not signaling success. Read receipts are out of scope. No cloud mailbox is included in this brief.

**Cross-border:** test actual deployments and peers in mainland China and outside
China. Use documented endpoints and explicit failure states. Neither P2P nor relay
can guarantee availability on every network; publish the tested support matrix.
Production endpoint ownership, hosting and operating budget remain unassigned.

## Transfers, persistence and AI boundaries

- One lazy helper owns networking, identity sessions, storage writes and timers.
  Reader windows are separate processes; use authenticated local IPC and one
  elected owner to avoid duplicated discovery, offers or transfers.
- Settings/profile preferences are YAML. Store messages, transfer events and local
  full-text indexes transactionally, with migrations and crash recovery. No whole-
  history YAML rewrite for each message. Secrets do not belong in YAML or logs.
- On Send, bind attachments to an immutable revision or verified snapshot. Never
  silently send a newer source after the user selected an older one. If the source
  is missing or storage is insufficient, report it before offering invalid content.
- Offers contain encrypted name, format, size and content identity. On acceptance,
  stream to a private temporary file. Reject unsolicited chunks, stale acceptance
  tokens, oversized metadata and offer floods before allocating large buffers.
  Profile avatars have separate strict size/decoder limits and do not grant consent
  to documents. Sanitize filenames and prevent traversal,
  symlink escapes and overwrites. Publish only after integrity verification.
- Use established authenticated streaming-encryption APIs. Authenticate transfer
  identity, sequence and lengths; validate a final digest. Bind resume checkpoints
  to the same sender, recipient and content. Retries are idempotent.
- Benchmark Zstandard as the initial streaming lossless codec. Compress before
  encryption, sample for compressibility, and send raw bytes when compression
  wastes time or space. Bound memory/output and reject decompression bombs. Do not
  share a compression context across unrelated secrets and attacker-controlled data.
- Accepted files go to an app-managed received-files directory. Open/import through
  existing Collection consent/capture rules. Incoming transfers never overwrite a
  source or execute received content. Defer thumbnail rendering until acceptance.
- Cancel stops remaining work and removes incomplete files. It cannot guarantee
  removal of content already delivered to another device. Do not label that Undo.
- Disable stops discovery/connections and hides the icon; retain local identity,
  history and queued drafts. Deleting history/identity is a separate explicit action.
- Incoming messages/documents are untrusted input, never authority for AI actions.
  OpenRouter processing is separate from the E2E friend channel: a user's explicit
  slash request may send relevant content to the configured provider. Do not run
  background AI on incoming content or upload a friend's whole history by default.

## Agent allocation and dependency order

Maximum four active agents, including the lead. Freeze service interfaces and test
doubles before parallel implementation. Each agent owns distinct file families;
only the lead edits shared coordinator declarations, registries and build wiring.

| Phase | Lead/integrator | Worker 1 | Worker 2 | Worker 3 |
|---|---|---|---|---|
| Definition (current) | Brief, decisions, integration seams | Local/AI translation | Network/security feasibility | PM and UX organization |
| Foundation | Lifecycle/IPC contracts | Identity, store, index | Discovery, E2E, transfer spike | Native UI with fake service |
| Integration | Wire features and resolve seams | Cmd+K, # picker, / drafts | Transport, compression, recovery | UI, keyboard, accessibility |
| Verification | Final audit and release notes | Independent security review | Performance/regression QA | Independent UX critic |

Use the strongest agents for protocol/security decisions and independent review.
Use lower-cost agents for bounded fixture data, index adapters, documentation and
mechanical tests once interfaces are stable. Do not duplicate network experiments
or run concurrent heavy builds. Reuse the current translation agent independently.

Dependency sequence:

1. Lead owns transport/activation decisions and wire/schema/IPC contracts. Security
   owner delivers the E2E dependency ADR; transport owner delivers Bluetooth channel
   and Internet transport ADRs; lead delivers the helper-lifecycle ADR.
2. Transport owner delivers a two-Mac spike with measured LAN/Bluetooth-only
   throughput, dependency size and Internet reachability/relay need. Before dates
   are assigned, name hardware/network QA operators and secure access to two Macs,
   separate NAT/mobile networks and mainland-China/outside-China peers. These
   resources are not assumed to be available to coding agents.
3. Build identity/store and UI against deterministic fake peers in parallel.
4. Integrate mutual friend requests and encrypted message delivery.
5. Add offers, acceptance, resumable documents and Collection ingestion.
6. Integrate local/Cmd+K search, then # attachments and / prepared drafts.
7. Run independent reviews, correct ranked findings, document and prepare release.

Do not deploy production services or mark Friends complete at a mockup/LAN-demo
milestone. Build a usable vertical slice before expanding transport/UI scope.

## Acceptance and release gates

| Area | Required evidence |
|---|---|
| Laziness | Zero Friends helper, sockets, BLE objects, timers, Keychain/database/index work before activation and while disabled; instrumented tests, not source assertions alone |
| Performance | Same-machine baseline vs candidate launch/document-open median and p95; no new synchronous reader work; profile reproducible regressions; record idle CPU/wakeups/RSS and bounded transfer memory |
| UI latency | Cached picker/selection/search responds without waiting for network; target first feedback within 100 ms on reference hardware; report measured dataset sizes and p95 |
| Discovery | LAN+Bluetooth dedupe, expiry/permissions/route transitions; two accepted but publicly hidden friends reconnect over Bluetooth only after activation, while a third stranger cannot identify/profile them |
| Delivery | Offline queue, replay/duplicate events, two-window ownership, crash/restart/resume, decline/cancel, source deletion/change and low disk |
| Security | Identity and transport-fingerprint substitution, key changes, blocked peers, alias races, stale tokens/acceptances, unsolicited chunks, offer floods, malformed/oversized metadata, replay, corrupted chunks, traversal and expansion bombs |
| Search/AI | Indexed messages/transfer records survive restart; exact highlighted Cmd+K destination; # binds revision; / cancels, preserves scope and distinguishes preparation from an explicitly authorized send |
| Network | Two Macs: Wi-Fi, Ethernet, Bluetooth only and denied/off; Internet: distinct NATs, CGNAT, IPv4/IPv6, blocked UDP, restricted networks, China↔China and China↔outside |
| Native UX | First-click full hit bounds, no drag-region overlap, keyboard/Escape, light/dark, narrow/wide, long names, 1×/2× vector icons; no external notifications |
| Release | Protocol/security docs, journal, user features and AI controls documented separately; updater/signing untouched; meaningful tested commits |

Independent UX critic: rank actionable findings by impact; grade visual consistency,
hierarchy, density, clarity and accessibility. Iterate at most four times toward
at least 9/10. Grades cannot override failing functional/security/performance tests.
Unrun hardware/network tests remain explicit release blockers, not assumed passes.

## Translation — parallel change

Clicking Translate reveals **Local** and **AI** directly below the button. Local
retains the existing offline pipeline. AI uses existing OpenRouter credentials,
model and language settings, with cancellable work and an unchanged source file.
Selected text is translated directly; full-document AI output is a new translated
Markdown document, clearly labeled before submission. Preserve headings/tables
where feasible; do not claim preservation of the original PDF layout. Bound large
inputs explicitly; no silent truncation. Test chooser hit areas, routing, success,
error/cancellation, local regressions and zero startup work without paid API calls.

## Technical sources

- [Apple networking API guidance](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api)
- [Apple MultipeerConnectivity platform transports](https://developer.apple.com/documentation/multipeerconnectivity)
- [CoreBluetooth](https://developer.apple.com/documentation/corebluetooth) and [L2CAP publishing](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/publishl2capchannel%28withencryption%3A%29)
- [WebRTC TURN rationale](https://webrtc.org/getting-started/turn-server) and [TURN standard](https://www.rfc-editor.org/rfc/rfc8656.html)
- [libdatachannel](https://github.com/paullouisageneau/libdatachannel) and [C API/backend limitations](https://libdatachannel.org/pages/reference.html)
- [Double Ratchet](https://signal.org/docs/specifications/doubleratchet/) and [libsignal third-party support limitations](https://github.com/signalapp/libsignal)
- [Authenticated stream encryption](https://doc.libsodium.org/secret-key_cryptography/secretstream)
- [Zstandard](https://github.com/facebook/zstd)
