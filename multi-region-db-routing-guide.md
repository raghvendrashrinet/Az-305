# Multi-Region Database Routing, Replication, & Application Logic

A reference guide comparing query routing, write handling, multi-region replication, and client/proxy architectural responsibilities across traditional Primary-Replica architectures, Azure Cosmos DB, and CockroachDB.

---

## 1. Architecture Comparison Overview

| Feature | Pattern A: Primary-Replica (e.g., Azure SQL, Postgres, MySQL) | Pattern B: Cosmos DB (Multi-Master) | Distributed SQL (CockroachDB) |
| :--- | :--- | :--- | :--- |
| **Routing Responsibility** | **Application OR Database Proxy Layer** | **Database SDK** | **Database Engine** |
| **Write Endpoints** | Single Primary Endpoint | Any Regional Endpoint | Any Node in Any Region |
| **Read Endpoints** | Secondary / Replica Endpoints | Any Regional Endpoint | Any Node in Any Region |
| **Replication Strategy** | Asynchronous Streaming / Binary Logs | Asynchronous Peer-to-Peer | Consensus Quorum (Raft) |
| **Conflict Resolution** | N/A (Writes executed on Primary only) | Last-Write-Wins (LWW) or Custom | Strict Serialization (ACID) |

---

## 2. Deep Dive: Handling Pattern A (Application vs. Proxy Layer)

Because standard relational databases (PostgreSQL, MySQL, standard Azure SQL) do not inspect SQL statements to direct traffic dynamically, routing logic must be implemented in the **Application Layer** or a **Database Proxy Layer**.

### A. Application-Level Handling (Frameworks & ORMs)

In this setup, the application code itself maintains multiple database connection pools and decides where each query goes before sending it down the wire.

* **Dual Connection Pools:**
  * `Primary_Pool`: Points directly to the Read-Write Primary instance.
  * `Replica_Pool`: Points to one or more Read-Only Replica instances (or a round-robin load balancer in front of them).
* **ORM / Query Routing Logic:**
  * **Writes (`INSERT`, `UPDATE`, `DELETE`, `ALTER`):** Sent explicitly through `Primary_Pool`.
  * **Reads (`SELECT`):** Sent through `Replica_Pool`. Frameworks like Django (`using('replica')`), Spring Boot (`@Transactional(readOnly = true)`), or Rails database selectors automate this based on transaction annotations.
* **Managing Replication Lag (Read-After-Write Consistency):**
  * **Problem:** If a user updates their profile (Write → Primary) and immediately reloads the page (Read → Replica), asynchronous replication lag may cause them to see stale data.
  * **App Logic Solution ("Sticky Writes"):** When a user performs a write, the app sets a temporary session flag or cache key (e.g., in Redis for 2–5 seconds). While this flag is active, the app forces **all subsequent reads for that specific user** to hit the `Primary_Pool`, switching back to `Replica_Pool` once the replica has caught up.

---

### B. Proxy-Level Handling (Database Proxies & Middleware)

In this setup, the application code connects to a single proxy endpoint using standard SQL. The proxy sits between the app and the databases, inspecting incoming queries and routing them transparently.

* **Popular Solutions:** PgBouncer + Pgpool-II, ProxySQL (MySQL), AWS RDS Proxy, Azure SQL Auto-Failover Group Listeners, HAProxy, MariaDB MaxScale.
* **Internal Proxy Execution Flow:**
  1. **Query Parsing:** The proxy receives a SQL query on a single port.
  2. **SQL Inspection:** It parses the command type:
     * If `INSERT`, `UPDATE`, `DELETE`, `SELECT ... FOR UPDATE`, or inside an active read-write transaction $\rightarrow$ Route to **Primary Node**.
     * If standard `SELECT` $\rightarrow$ Load-balance across **Replica Nodes**.
  3. **Connection Pooling:** The proxy manages persistent connections to both primary and replica nodes, reducing connection overhead on the database engines.
* **Managing Replication Lag at the Proxy:**
  * Advanced proxies (e.g., ProxySQL or MaxScale) monitor replication lag (e.g., `Seconds_Behind_Master`).
  * If a replica exceeds a configured lag threshold (e.g., > 100ms), the proxy automatically removes it from the read pool and reroutes traffic back to the Primary until the replica catches up.

---

## 3. Pattern B: Multi-Primary (Azure Cosmos DB)

### Query Routing
* **Transparent SDK-Level Routing:** Application code issues all queries through a single global endpoint. The SDK abstracts all read/write routing logic.
* **Geo-Proximity Routing:** The Cosmos DB SDK initializes with an `ApplicationRegion` or `PreferredRegions` list. The SDK automatically routes **both reads and writes** to the local data center nearest to the application instance.

### Replication & Conflict Resolution
* **Async Multi-Master:** Writes commit locally in the receiving region first and replicate asynchronously in the background to all configured regions.
* **Conflict Resolution Mechanisms:**
  * **Last-Write-Wins (LWW) [Default]:** System timestamp (`_ts`) determines the winning record.
  * **Custom Merge Procedures:** Triggered when concurrent writes occur across regions, applying user-defined merge rules.

---

## 4. Distributed Cloud-Native (CockroachDB)

### Query Routing
* **Any-Node Entry:** The application connects to any node or local load balancer. There are no distinct read vs. write connection strings.
* **Internal Transparent Forwarding:** If a node receives a query for data it does not physically own, it transparently forwards the request across the cluster to the owning node and returns the result to the application.

### Core Architectural Pillars
* **Raft Micro-Sharding:** Tables are chunked into 64MB "Ranges" replicated across regions via Raft consensus. Writes require majority quorum agreement to commit.
* **Leaseholders:** A designated replica per Range acts as the Leaseholder, serving up-to-date reads locally without cross-region consensus overhead.
* **Declarative Locality Controls:** Schema-level directives (e.g., `REGIONAL BY ROW`, `GLOBAL TABLES`) define data residency natively rather than relying on application-level routing.
