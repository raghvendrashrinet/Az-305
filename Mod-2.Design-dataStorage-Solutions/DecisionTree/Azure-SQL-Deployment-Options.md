## ⚡ Azure SQL Deployment Options
***SQL Server is Designed for Single Master setup Only*** No multi master
### 1. Azure SQL Database (PaaS) (fully cloud based)
  Fully managed single DB or elastic pool(auto scale)
  - Best for cloud-native apps
  - No OS-level access, simplified scaling
```
+-------------------+
| Azure SQL DB      |
|  (Single / Pool)  |
+-------------------+
```
### 2. Azure SQL Managed Instance (PaaS)- ( Supports On prem tech CLR,CrossDb transactions,Agents)
Near 100% compatibility with on-prem SQL Server
 - Supports SQL Agent, cross-database queries
 - Handles automated backups, patching, scaling
```
+---------------------------+
| Azure SQL Managed Instance|
|   (PaaS, full features)   |
+---------------------------+
```
### 3. SQL Server on Azure VMs (IaaS)
Full OS + SQL Server control
 - Ideal for legacy migrations needing unsupported features or custom plugins
 - You manage patching, backups, and licensing
```
+-------------------+
|   Azure VM (IaaS) |
|  +-------------+  |
|  | SQL Server  |  |
|  +-------------+  |
+-------------------+
```

---
## 🏷️ Service Tiers & Purchasing Models

### 1. vCore Model
Independent scaling of compute + storage.
 1. `General Purpose` → Balanced workloads, cost-effective
 2. `Business Critical` → Low latency, Always On AGs, NVMe SSDs
 3. `Hyperscale` → Up to 100 TB, rapid scaling, fast backups
```
   vCore Model
   +-------------------+
   | Compute (vCores)  |
   | Storage           |
   +-------------------+
```
### 2. DTU Model
Bundled compute, memory, I/O
- Simple workloads with predictable usage
```
+-------------------+
| DTU Bundle        |
| (CPU+Mem+I/O)     |
+-------------------+
```
### 3. Serverless Compute
Auto-scales compute based on demand
 - Pauses DB during inactivity → saves cost
```
+-------------------+
| Serverless SQL DB |
| Auto-scale & Pause|
+-------------------+
```
---
##  Azure SQL vCore service tiers 
Azure SQL separates compute (the processing layer) from storage (the data layer). This design allows independent scaling, resilience, and specialized optimizations depending on the tier.
| **[Service Tier](ca://s?q=Azure_SQL_service_tiers)** | **[Compute Layer](ca://s?q=Azure_SQL_compute_layer)** | **[Storage Layer](ca://s?q=Azure_SQL_storage_layer)** | **[How They Separate](ca://s?q=Azure_SQL_compute_storage_separation)** |
| --- | --- | --- | --- |
| **[General Purpose](ca://s?q=Azure_SQL_General_Purpose)** (SQL DB & Managed Instance) | Azure compute nodes (stateless DB engine) | Azure Blob Storage or Premium Storage | Compute and storage scale independently. If compute fails, a new node attaches to the existing remote storage volume. |
| **[Hyperscale](ca://s?q=Azure_SQL_Hyperscale)** (SQL DB & Managed Instance) | Stateless compute nodes (Primary + Read Replicas) | Distributed Page Servers + Azure Storage (Up to 100+ TB) | Pure separation. Log service, page servers, and compute nodes all scale independently without requiring full data copy operations. |
| **[Business Critical](ca://s?q=Azure_SQL_Business_Critical)** (SQL DB & Managed Instance) | Compute nodes with local super-fast NVMe SSDs | Local NVMe SSD storage attached to compute replicas | Storage is physically local to the node for low latency. Data replication uses Always On Availability Groups across 3–4 nodes for resilience rather than relying on remote storage failover. |


### 1. General Purpose
  - Compute: Runs on Azure VMs with standard performance.
  - Storage: Remote Azure Premium disks.
  - Resiliency: Single replica, automatic failover.

Trade-off: Balanced cost vs performance.

```
+-----------+        +------------------+
|  Compute  | <----> | Remote Storage   |
|  (VMs)    |        | Premium Disks    |
+-----------+        +------------------+
```
### 3. Business Critical
  - Compute: Runs on NVMe SSD-backed nodes.
  - Storage: Local SSDs tightly coupled with compute.
  - Resiliency: **Always On availability groups (multiple replicas)**.

Trade-off: Higher cost, but ultra-low latency and strong HA.

```
+-----------+   +-----------+   +-----------+
| Compute   |   | Compute   |   | Compute   |
| + Storage |   | + Storage |   | + Storage |
| (NVMe SSD)|   | (Replica) |   | (Replica) |
+-----------+   +-----------+   +-----------+
``` 
### 3. Hyperscale (Uses Sharding)
  - Compute: Scales out across multiple read/write nodes.
  - Storage: Azure storage snapshots, independent of compute.
  - Resiliency: Rapid scaling, instant backups/restores.
  - 
**`One Primary Compute Replica`: Handles all read-write workloads, transaction commits, and coordinates database operations.**  
**`Secondary Compute Replicas (0 to 4)`: Act as read-only replicas for offloading read workloads**

Secondary Compute Replicas (0 to 4):
Trade-off: Extreme scalability (up to 100 TB).

```
+-----------+       +-----------+       +-----------+
| Compute   |       | Compute   |       | Compute   |
| (Primary) |       | (Read)    |       | (Read)    |
+-----------+       +-----------+       +-----------+
       |                   |                   |
       +---------------------------------------+
                       Storage
                (Snapshot-based, 100 TB+)
```

---
## HA Options in Azure SQL
```
Azure SQL HA Options
+---------------------------------------------------+
| Business Critical -  (Always On AGs, NVMe SSDs)       |
| Zone Redundant - (replicas across AZs)               |
| Auto-Failover Groups - (cross-region automatic DR)   |
| Active Geo-Replication - (up to 4 readable replicas) |
| SQL on VMs (custom AGs / FCI setup)                |
+---------------------------------------------------+
```
## ⚡ HA Options by Service Tier

| **[Service Tier](ca://s?q=Azure_SQL_service_tiers)** | **Replica Model** | **HA Behavior** | **Best For** |
| --- | --- | --- | --- |
| **[General Purpose](ca://s?q=Azure_SQL_General_Purpose)** | Single replica | Automatic failover to a new compute node attaching to the same remote storage | Balanced workloads, cost‑effective HA |
| **[Business Critical](ca://s?q=Azure_SQL_Business_Critical)** | 3–4 replicas (Always On AGs) | Synchronous replicas with automatic failover, ultra‑low latency | Mission‑critical workloads needing strong HA |
| **[Hyperscale](ca://s?q=Azure_SQL_Hyperscale)** | Multiple compute nodes + distributed page servers | Storage snapshots + independent scaling; replicas for read scale and resilience | Very large DBs, analytics, unpredictable growth |

#### General Purpose
```Code
+-----------+        +------------------+
|  Compute  | <----> | Remote Storage   |
| (Stateless)        | Blob/Premium     |
+-----------+        +------------------+
   Single replica, auto failover
```
#### Business Critical
```Code
+-----------+   +-----------+   +-----------+
| Primary   |   | Secondary |   | Secondary |
| NVMe SSD  |   | NVMe SSD  |   | NVMe SSD  |
+-----------+   +-----------+   +-----------+
   Always On Availability Groups (multi-replica HA)
```
#### Hyperscale
```Code
+-----------+       +-----------+       +-----------+
| Compute   |       | Compute   |       | Compute   |
| (Primary) |       | (Replica) |       | (Replica) |
+-----------+       +-----------+       +-----------+
       |                   |                   |
       +---------------------------------------+
                       Storage
          (Page Servers + Azure Storage, 100TB+)
```

## ⚡ How HA Options Tie to Service Tiers

| **[HA Option](ca://s?q=Azure_SQL_HA_options)** | **Where Enabled** | **Replica Model** | **Tier Dependency** |
| --- | --- | --- | --- |
| **[Zone Redundant Deployments](ca://s?q=Azure_SQL_zone_redundant_deployment)** | Azure Portal / ARM / CLI → “Zone Redundant = Yes” | Replicas spread across Availability Zones in one region | Works with **General Purpose** and **Business Critical** |
| **[Auto‑Failover Groups](ca://s?q=Azure_SQL_auto_failover_groups)** | Azure Portal → SQL Database → Failover Groups | Primary + Secondary region, automatic failover | Available for **SQL Database** and **Managed Instance**, regardless of tier |
| **[Active Geo‑Replication](ca://s?q=Azure_SQL_active_geo_replication)** | Azure Portal → Replication settings | Up to 4 readable secondaries in different regions | Available for **SQL Database** (any tier), manual failover unless combined with failover groups |

>[!NOTE]
>`Zone Redundant, Auto‑Failover Groups, Active Geo‑Replication` are additional HA/DR features layered on top of the core service tiers. They don’t replace the tier model (General Purpose, Business Critical, Hyperscale), but extend it depending on your resiliency needs.


