---
feature: "engine-clustering"
created: "2026-03-20"
status: "confirmed"
---

# Work Plan — engine-clustering

## References

- **Brief:** [brief.md](brief.md)
- **Domains:** [domains.md](domains.md)
- **ADRs:**
  - [cluster-membership-protocol](../../.decisions/cluster-membership-protocol/adr.md)
  - [partition-to-node-ownership](../../.decisions/partition-to-node-ownership/adr.md)
  - [rebalancing-grace-period-strategy](../../.decisions/rebalancing-grace-period-strategy/adr.md)
  - [scatter-gather-query-execution](../../.decisions/scatter-gather-query-execution/adr.md)
  - [discovery-spi-design](../../.decisions/discovery-spi-design/adr.md)
  - [transport-abstraction-design](../../.decisions/transport-abstraction-design/adr.md)

## Module

`jlsm-engine` at `modules/jlsm-engine`

## Existing Constructs (to USE or EXTEND)

| # | Construct | Location | Role |
|---|-----------|----------|------|
| 1 | `Engine` | `jlsm.engine.Engine` | Interface — `ClusteredEngine` implements this |
| 2 | `Table` | `jlsm.engine.Table` | Interface — `ClusteredTable` implements this |
| 3 | `LocalEngine` | `jlsm.engine.internal.LocalEngine` | Each cluster node runs one |
| 4 | `PartitionClient` | `jlsm.table.PartitionClient` | SPI — `RemotePartitionClient` implements this |
| 5 | `PartitionedTable` | `jlsm.table.PartitionedTable` | Existing scatter-gather coordinator |
| 6 | `PartitionDescriptor` | `jlsm.table.PartitionDescriptor` | Has `nodeId` field for node assignment |
| 7 | `TableMetadata` | `jlsm.engine.TableMetadata` | Metadata record |
| 8 | `EngineMetrics` | `jlsm.engine.EngineMetrics` | Metrics record |

## New Constructs (22)

| # | Construct | Package | Kind | WU |
|---|-----------|---------|------|----|
| 1 | `NodeAddress` | `jlsm.engine.cluster` | record | WU-1 |
| 2 | `ClusterConfig` | `jlsm.engine.cluster` | record + builder | WU-1 |
| 3 | `Message` | `jlsm.engine.cluster` | record | WU-1 |
| 4 | `MessageType` | `jlsm.engine.cluster` | enum | WU-1 |
| 5 | `Member` | `jlsm.engine.cluster` | record | WU-1 |
| 6 | `MemberState` | `jlsm.engine.cluster` | enum | WU-1 |
| 7 | `MembershipView` | `jlsm.engine.cluster` | class (Comparable) | WU-1 |
| 8 | `PartialResultMetadata` | `jlsm.engine.cluster` | record | WU-1 |
| 9 | `ClusterTransport` | `jlsm.engine.cluster` | interface (SPI) | WU-1 |
| 10 | `MessageHandler` | `jlsm.engine.cluster` | functional interface | WU-1 |
| 11 | `DiscoveryProvider` | `jlsm.engine.cluster` | interface (SPI) | WU-1 |
| 12 | `MembershipProtocol` | `jlsm.engine.cluster` | interface (SPI) | WU-1 |
| 13 | `MembershipListener` | `jlsm.engine.cluster` | interface | WU-1 |
| 14 | `InJvmTransport` | `jlsm.engine.cluster.internal` | class | WU-1 |
| 15 | `InJvmDiscoveryProvider` | `jlsm.engine.cluster.internal` | class | WU-1 |
| 16 | `PhiAccrualFailureDetector` | `jlsm.engine.cluster.internal` | class | WU-2 |
| 17 | `RapidMembership` | `jlsm.engine.cluster.internal` | class | WU-2 |
| 18 | `RendezvousOwnership` | `jlsm.engine.cluster.internal` | class | WU-3 |
| 19 | `GracePeriodManager` | `jlsm.engine.cluster.internal` | class | WU-3 |
| 20 | `ClusteredEngine` | `jlsm.engine.cluster` | class | WU-4 |
| 21 | `ClusteredTable` | `jlsm.engine.cluster` | class | WU-4 |
| 22 | `RemotePartitionClient` | `jlsm.engine.cluster.internal` | class | WU-4 |

## Stub Files Written

| # | File | Status |
|---|------|--------|
| 1 | `src/main/java/jlsm/engine/cluster/NodeAddress.java` | created |
| 2 | `src/main/java/jlsm/engine/cluster/ClusterConfig.java` | created |
| 3 | `src/main/java/jlsm/engine/cluster/Message.java` | created |
| 4 | `src/main/java/jlsm/engine/cluster/MessageType.java` | created |
| 5 | `src/main/java/jlsm/engine/cluster/Member.java` | created |
| 6 | `src/main/java/jlsm/engine/cluster/MemberState.java` | created |
| 7 | `src/main/java/jlsm/engine/cluster/MembershipView.java` | created |
| 8 | `src/main/java/jlsm/engine/cluster/PartialResultMetadata.java` | created |
| 9 | `src/main/java/jlsm/engine/cluster/ClusterTransport.java` | created |
| 10 | `src/main/java/jlsm/engine/cluster/MessageHandler.java` | created |
| 11 | `src/main/java/jlsm/engine/cluster/DiscoveryProvider.java` | created |
| 12 | `src/main/java/jlsm/engine/cluster/MembershipProtocol.java` | created |
| 13 | `src/main/java/jlsm/engine/cluster/MembershipListener.java` | created |
| 14 | `src/main/java/jlsm/engine/cluster/internal/InJvmTransport.java` | created |
| 15 | `src/main/java/jlsm/engine/cluster/internal/InJvmDiscoveryProvider.java` | created |
| 16 | `src/main/java/jlsm/engine/cluster/internal/PhiAccrualFailureDetector.java` | created |
| 17 | `src/main/java/jlsm/engine/cluster/internal/RapidMembership.java` | created |
| 18 | `src/main/java/jlsm/engine/cluster/internal/RendezvousOwnership.java` | created |
| 19 | `src/main/java/jlsm/engine/cluster/internal/GracePeriodManager.java` | created |
| 20 | `src/main/java/jlsm/engine/cluster/ClusteredEngine.java` | created |
| 21 | `src/main/java/jlsm/engine/cluster/ClusteredTable.java` | created |
| 22 | `src/main/java/jlsm/engine/cluster/internal/RemotePartitionClient.java` | created |

## Contract Definitions

### 1. NodeAddress
- **Signature:** `record NodeAddress(String nodeId, String host, int port)`
- **Contract:** Immutable identity + network address of a cluster node
- **Params:** `nodeId` — unique ID (non-null, non-empty); `host` — hostname/IP (non-null, non-empty); `port` — [1, 65535]
- **Returns:** N/A (value type)
- **Side effects:** None
- **Error conditions:** `NullPointerException` on null fields; `IllegalArgumentException` on empty strings or invalid port
- **Governing ADR:** transport-abstraction-design

### 2. ClusterConfig
- **Signature:** `record ClusterConfig(Duration gracePeriod, Duration protocolPeriod, Duration pingTimeout, int indirectProbes, double phiThreshold, int consensusQuorumPercent)`
- **Contract:** Immutable clustering configuration with builder providing sensible defaults
- **Params:** All durations must be positive; `indirectProbes` >= 0; `phiThreshold` > 0; `consensusQuorumPercent` in [1, 100]
- **Returns:** N/A (value type); builder returns `ClusterConfig`
- **Side effects:** None
- **Error conditions:** `NullPointerException` on null durations; `IllegalArgumentException` on invalid ranges
- **Governing ADR:** cluster-membership-protocol, rebalancing-grace-period-strategy

### 3. Message
- **Signature:** `record Message(MessageType type, NodeAddress sender, long sequenceNumber, byte[] payload)`
- **Contract:** Typed message for cluster transport. Defensive copies of payload on construction and access
- **Params:** `type` — non-null; `sender` — non-null; `sequenceNumber` >= 0; `payload` — non-null (may be empty)
- **Returns:** `payload()` returns defensive copy
- **Side effects:** None
- **Error conditions:** `NullPointerException` on null fields; `IllegalArgumentException` on negative sequence
- **Governing ADR:** transport-abstraction-design

### 4. MessageType
- **Signature:** `enum MessageType { PING, ACK, VIEW_CHANGE, QUERY_REQUEST, QUERY_RESPONSE, STATE_DIGEST, STATE_DELTA }`
- **Contract:** Exhaustive enumeration of cluster message categories
- **Governing ADR:** transport-abstraction-design

### 5. Member
- **Signature:** `record Member(NodeAddress address, MemberState state, long incarnation)`
- **Contract:** A cluster member with address, lifecycle state, and incarnation counter for refuting suspicion
- **Params:** `address` — non-null; `state` — non-null; `incarnation` >= 0
- **Error conditions:** `NullPointerException` on null fields; `IllegalArgumentException` on negative incarnation
- **Governing ADR:** cluster-membership-protocol

### 6. MemberState
- **Signature:** `enum MemberState { ALIVE, SUSPECTED, DEAD }`
- **Contract:** Three-state lifecycle for cluster members
- **Governing ADR:** cluster-membership-protocol

### 7. MembershipView
- **Signature:** `class MembershipView implements Comparable<MembershipView>`
- **Contract:** Immutable snapshot of cluster membership at a specific epoch. Provides `liveMemberCount()`, `isMember(NodeAddress)`, `hasQuorum(int)`. Comparable by epoch.
- **Params (constructor):** `epoch` >= 0; `members` — non-null Set<Member>; `timestamp` — non-null Instant
- **Returns:** `liveMemberCount()` — int; `isMember()` — boolean; `hasQuorum()` — boolean
- **Side effects:** None
- **Error conditions:** `IllegalArgumentException` on negative epoch or invalid quorum percent
- **Governing ADR:** cluster-membership-protocol

### 8. PartialResultMetadata
- **Signature:** `record PartialResultMetadata(Set<String> unavailablePartitions, boolean isComplete)`
- **Contract:** Tracks which partitions were missing from a scatter-gather query
- **Params:** `unavailablePartitions` — non-null (defensive copy via `Set.copyOf`)
- **Governing ADR:** scatter-gather-query-execution

### 9. ClusterTransport
- **Signature:** `interface ClusterTransport extends AutoCloseable`
- **Methods:** `send(NodeAddress, Message)`, `request(NodeAddress, Message) → CompletableFuture<Message>`, `registerHandler(MessageType, MessageHandler)`
- **Contract:** Fire-and-forget + request-response + type-based handler dispatch. Thread-safe.
- **Error conditions:** `IOException` on send failure
- **Governing ADR:** transport-abstraction-design

### 10. MessageHandler
- **Signature:** `@FunctionalInterface interface MessageHandler`
- **Method:** `CompletableFuture<Message> handle(NodeAddress sender, Message msg)`
- **Contract:** Handles incoming messages of a registered type
- **Governing ADR:** transport-abstraction-design

### 11. DiscoveryProvider
- **Signature:** `interface DiscoveryProvider`
- **Methods:** `discoverSeeds() → Set<NodeAddress>` (required); `register(NodeAddress)`, `deregister(NodeAddress)` (default no-ops)
- **Contract:** Pluggable seed discovery for cluster bootstrap. Stale registrations are harmless.
- **Error conditions:** `IOException` on discovery failure
- **Governing ADR:** discovery-spi-design

### 12. MembershipProtocol
- **Signature:** `interface MembershipProtocol extends AutoCloseable`
- **Methods:** `start(List<NodeAddress>)`, `currentView() → MembershipView`, `addListener(MembershipListener)`, `leave()`
- **Contract:** Manages cluster membership lifecycle. After start, maintains consistent view.
- **Error conditions:** `IOException` on start/leave failure
- **Governing ADR:** cluster-membership-protocol

### 13. MembershipListener
- **Signature:** `interface MembershipListener`
- **Methods:** `onViewChanged(MembershipView, MembershipView)`, `onMemberJoined(Member)`, `onMemberLeft(Member)`, `onMemberSuspected(Member)`
- **Contract:** Callbacks on membership events. Must not block.
- **Governing ADR:** cluster-membership-protocol

### 14. InJvmTransport
- **Signature:** `class InJvmTransport implements ClusterTransport`
- **Contract:** Static registry of in-JVM transports. Direct handler invocation, no serialization.
- **Side effects:** Modifies static registry on construction and close
- **Error conditions:** `IllegalArgumentException` if address already registered
- **Governing ADR:** transport-abstraction-design

### 15. InJvmDiscoveryProvider
- **Signature:** `class InJvmDiscoveryProvider implements DiscoveryProvider`
- **Contract:** Static ConcurrentHashMap shared across instances for in-JVM discovery
- **Side effects:** Modifies static shared set on register/deregister
- **Governing ADR:** discovery-spi-design

### 16. PhiAccrualFailureDetector
- **Signature:** `class PhiAccrualFailureDetector`
- **Methods:** `recordHeartbeat(NodeAddress)`, `phi(NodeAddress) → double`, `isAvailable(NodeAddress, double) → boolean`
- **Contract:** Sliding window of heartbeat inter-arrival times. phi = -log10(1 - CDF(elapsed)). Returns 0.0 until >= 2 heartbeats recorded.
- **Params (constructor):** `windowSize` >= 2
- **Governing ADR:** cluster-membership-protocol

### 17. RapidMembership
- **Signature:** `class RapidMembership implements MembershipProtocol`
- **Contract:** Rapid protocol: expander graph overlay, multi-process cut detection, leaderless 75% consensus. Uses ClusterTransport, DiscoveryProvider, PhiAccrualFailureDetector.
- **Params (constructor):** `localAddress`, `transport`, `discovery`, `config`, `failureDetector` — all non-null
- **Side effects:** Starts background protocol threads. Modifies membership view on consensus.
- **Governing ADR:** cluster-membership-protocol

### 18. RendezvousOwnership
- **Signature:** `class RendezvousOwnership`
- **Methods:** `assignOwner(String, MembershipView) → NodeAddress`, `assignOwners(String, MembershipView, int) → List<NodeAddress>`, `evictBefore(long)`
- **Contract:** Pure HRW function. Cache keyed on view epoch. All nodes compute identical assignments from same view.
- **Error conditions:** `IllegalStateException` if no live members
- **Governing ADR:** partition-to-node-ownership

### 19. GracePeriodManager
- **Signature:** `class GracePeriodManager`
- **Methods:** `recordDeparture(NodeAddress, Instant)`, `isInGracePeriod(NodeAddress) → boolean`, `expiredDepartures() → Set<NodeAddress>`, `recordReturn(NodeAddress)`
- **Contract:** Tracks departed nodes. Grace period controls cleanup, not assignment. Returning nodes within grace reclaim at zero cost.
- **Params (constructor):** `gracePeriod` — positive Duration
- **Governing ADR:** rebalancing-grace-period-strategy

### 20. ClusteredEngine
- **Signature:** `class ClusteredEngine implements Engine`
- **Contract:** Wraps LocalEngine + cluster components. createTable creates locally + announces. getTable returns ClusteredTable proxy or local delegate. Listens for membership changes to trigger rebalancing. Builder pattern.
- **Side effects:** Starts membership protocol. Modifies ownership on membership changes.
- **Governing ADR:** all 6 clustering ADRs

### 21. ClusteredTable
- **Signature:** `class ClusteredTable implements Table`
- **Contract:** Partition-aware proxy. Predicate-based partition pruning (O(log P)). Concurrent scatter via transport. Streaming k-way merge gather. PartialResultMetadata for incomplete results. Writes route to single owner.
- **Side effects:** Sends messages via transport
- **Governing ADR:** scatter-gather-query-execution

### 22. RemotePartitionClient
- **Signature:** `class RemotePartitionClient implements PartitionClient`
- **Contract:** Serializes CRUD as QUERY_REQUEST messages, sends via ClusterTransport.request(), deserializes QUERY_RESPONSE.
- **Side effects:** Sends messages via transport. Blocks on response future with timeout.
- **Governing ADR:** transport-abstraction-design

## Work Units

### WU-1: Foundation (types + SPIs + in-JVM impls)
- **Constructs:** #1–15 (NodeAddress, ClusterConfig, Message, MessageType, Member, MemberState, MembershipView, PartialResultMetadata, ClusterTransport, MessageHandler, DiscoveryProvider, MembershipProtocol, MembershipListener, InJvmTransport, InJvmDiscoveryProvider)
- **Dependencies:** None
- **Estimated tests:** ~30 (record validation, builder defaults/overrides, MembershipView methods, InJvmTransport send/request/handler, InJvmDiscoveryProvider register/discover/deregister)
- **Notes:** Records and enums need validation tests. MembershipView needs liveMemberCount, isMember, hasQuorum, Comparable tests. In-JVM impls are the test infrastructure for WU-2/3/4.

### WU-2: Membership Protocol
- **Constructs:** #16–17 (PhiAccrualFailureDetector, RapidMembership)
- **Dependencies:** WU-1
- **Estimated tests:** ~20 (phi computation with known intervals, window saturation, availability threshold, Rapid join/leave/view-change/split-brain/consensus)
- **Notes:** PhiAccrualFailureDetector is independently testable with controlled timestamps. RapidMembership tested via InJvmTransport + InJvmDiscoveryProvider.

### WU-3: Ownership & Rebalancing
- **Constructs:** #18–19 (RendezvousOwnership, GracePeriodManager)
- **Dependencies:** WU-1
- **Estimated tests:** ~15 (deterministic assignment, minimal movement on view change, cache keyed on epoch, replicas ranking, grace period lifecycle, return-within-grace, expired departures)
- **Notes:** RendezvousOwnership is pure function — highly testable. GracePeriodManager needs controlled clock (Instant parameter).

### WU-4: Clustered Engine
- **Constructs:** #20–22 (ClusteredEngine, ClusteredTable, RemotePartitionClient)
- **Dependencies:** WU-1, WU-2, WU-3
- **Estimated tests:** ~25 (engine lifecycle, create/get/drop table routing, ClusteredTable scatter-gather, partition pruning, partial results, RemotePartitionClient serialization roundtrip, membership change triggers rebalancing)
- **Notes:** Integration-heavy. Uses all in-JVM impls from WU-1 + real WU-2/WU-3 implementations.

## Implementation Order

```
WU-1 (Foundation)  ──→  WU-2 (Membership)  ──→  WU-4 (Clustered Engine)
                   ──→  WU-3 (Ownership)    ──→
```

WU-2 and WU-3 can execute in parallel after WU-1 completes. WU-4 depends on all three.

## Execution Strategy

**Balanced mode:** WU-1 first (sequential), then WU-2 + WU-3 (parallel batch), then WU-4 (sequential).
