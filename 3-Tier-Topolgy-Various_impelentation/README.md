## Designing a production-ready, 3-tier application architecture on Azure

Microsoft aligns infrastructure with Business Continuity and Disaster Recovery (BCDR) principles

### Part 1: Regional Strategy (Single vs. Multi-Region)
Azure's deployment recommendations depend heavily on your target SLA (Service Level Agreement), RTO, and RPO.

#### Option A: Single-Region (High Availability Focus)
If your application can tolerate region-wide downtime but requires high availability against localized hardware or power failures, Azure recommends a Zone-Redundant Single-Region Architecture.
- How it works: You deploy your infrastructure across a single region but utilize a minimum of *three distinct Availability Zones (AZs)*.
- Azure Recommendation:
    * Compute/Web/App Tier: VM-> Spread Virtual Machine Scale Sets (VMSS) or Azure Kubernetes Service (AKS) nodes across all three zones using standard load balancers.
    * Data Tier: Use zone-redundant deployment models (e.g., Azure SQL Database Zone-Redundant configuration) where synchronous replication happens automatically across zones.
  Pros/Cons: Cheaper and avoids cross-region latency, but leaves you vulnerable to a total catastrophic regional failure.

##### A. Single-Region (Zone-Redundant 3-Tier)
This architecture protects against datacenter-level failures within a single region by spreading resources across three independent Availability Zones (AZ).
- How it works: You deploy identical or scaled-down environments in a primary region and a secondary Azure Paired Region (e.g., East US and West US).
- Azure Recommendation:
  * Global Ingress: Use Azure Front Door (Layer 7 Layered Global Load Balancer) to route traffic, handle SSL offloading, and manage instant DNS failovers.
  * Compute Failover: Use Azure Site Recovery (ASR) for replicating VMs asynchronously, or maintain a "Warm Standby" AKS/App Service cluster hydrated via CI/CD pipelines.
  * Data Tier: Implement Azure SQL Active Geo-Replication or Cosmos DB multi-region replication to continuously stream data asynchronously to the secondary region.
    


```
+---------------------------------------------------------------------------------+
|                                  AZURE REGION                                   |
|                                                                                 |
|                      +-----------------------------------+                      |
|                      |      Azure Application Gateway    |                      |
|                      |         (Zone-Redundant L7)       |                      |
|                      +-----------------+-----------------+                      |
|                                        |                                        |
|         +------------------------------+------------------------------+         |
|         |                              |                              |         |
|  [ ZONE 1 ]                     [ ZONE 2 ]                     [ ZONE 3 ]       |
|  +---------------------------+  +---------------------------+  +-------------+  |
|  | Web Subnet (VMSS/AKS)     |  | Web Subnet (VMSS/AKS)     |  | Web Subnet  |  |
|  | [ Web-VM-Z1 ]             |  | [ Web-VM-Z2 ]             |  | [Web-VM-Z3] |  |
|  +-------------+-------------+  +-------------+-------------+  +------+------+  |
|                |                              |                       |         |
|  +-------------v-------------+  +-------------v-------------+  +------v------+  |
|  | App Subnet (VMSS/AKS)     |  | App Subnet (VMSS/AKS)     |  | App Subnet  |  |
|  | [ App-VM-Z1 ]             |  | [ App-VM-Z2 ]             |  | [App-VM-Z3] |  |
|  +-------------+-------------+  +-------------+-------------+  +------+------+  |
|                |                              |                       |         |
|  +-------------v-------------+  +-------------v-------------+  +------v------+  |
|  | DB Subnet (Azure SQL)     |  | DB Subnet (Azure SQL)     |  | DB Subnet   |  |
|  | [ Primary Node ] (Sync) --+->| [ Secondary Node ] (Sync)-+->| [ Read-Repl]|  |
|  +---------------------------+  +---------------------------+  +-------------+  |
+---------------------------------------------------------------------------------+
```
#### Option B: Multi-Region (Active-Passive / Disaster Recovery)
For Tier 1 critical applications requiring an RTO < 1 hour and RPO < 15 minutes, Azure recommends a Multi-Region (Active-Passive or Active-Active) Architecture.

This setup ensures business continuity (BCDR) if an entire region goes offline. Azure Front Door controls failover routing.
```
+--------------------------+
                            |     Azure Front Door     |  <-- Global DNS/SSL Routing
                            +------------+-------------+
                                         |
                 +-----------------------+-----------------------+
    (Active Path) |                                               | (Failover Path)
                 v                                               v
+---------------------------------+             +---------------------------------+
| PRIMARY REGION (e.g., East US)  |             | SECONDARY REGION (e.g., West US)|
|                                 |             |                                 |
|  +---------------------------+  |             |  +---------------------------+  |
|  | App Gateway (L7 LB)       |  |             |  | App Gateway (L7 LB)       |  |
|  +-------------+-------------+  |             |  +-------------+-------------+  |
|                |                |             |                |                |
|  +-------------v-------------+  |             |  +-------------v-------------+  |
|  | Compute Tier (AKS/VMSS)   |  |             |  | Compute Tier (Cold/Warm)  |  |
|  +-------------+-------------+  |             |  +-------------+-------------+  |
|                |                |  Replication|                |                |
|  +-------------v-------------+  |  (Async ASR)|  +-------------v-------------+  |
|  | Primary Database           |==+============>|  | DR Replica Database       |  |
|  | (Active Read/Write)       |  |  (DB Engine)|  | (Passive / Read-Only)     |  |
|  +---------------------------+  |             |  +---------------------------+  |
+---------------------------------+             +---------------------------------+
```

---

### Part 2: Network Topologies
##### A. Traditional Hub-and-Spoke (VNet Peering)
Best for custom-engineered routing requirements. Virtual networks are linked manually using bidirectional VNet Peering.
```
+------------------------------------------------------------+
       |                        SPOKE 1 VNET                        |
       |  +------------------------------------------------------+  |
       |  | App Subnets (UDR -> Hub NVA/Firewall IP)             |  |
       |  +---------------------------+--------------------------+  |
       +------------------------------|-----------------------------+
                                      | (VNet Peering)
                                      v
+-------------------------------------|-------------------------------------+
|                              HUB VNET                                     |
|  +----------------------------------v----------------------------------+  |
|  | Azure Firewall / Network Virtual Appliance (Traffic Inspection)     |  |
|  +----------------------------------+----------------------------------+  |
|                                     |                                     |
|  +----------------------------------v----------------------------------+  |
|  | ExpressRoute / VPN Gateways (On-Premises Hybrid Connectivity)       |  |
|  +----------------------------------+----------------------------------+  |
+-------------------------------------|-------------------------------------+
                                      ^
                                      | (VNet Peering)
       +------------------------------|-----------------------------+
       |                        SPOKE 2 VNET                        |
       |  +---------------------------v--------------------------+  |
       |  | Database Subnets                                     |  |
       |  +------------------------------------------------------+  |
       +------------------------------------------------------------+
```
### B. Modern Managed Hub (Azure Virtual WAN)
Virtual WAN (vWAN) - Modern Managed Hub-Spoke  
Best for large-scale, enterprise, or multi-region setups. Routes are managed automatically by the Microsoft-managed Virtual Hub.
```
    +---------------+                             +---------------+
    | Spoke VNet A  |                             | Spoke VNet B  |
    +-------+-------+                             +-------+-------+
            |                                             |
            +---------------------+   +-------------------+
                                  |   |
+---------------------------------v---v---------------------------------+
|                       SECURE VIRTUAL HUB (vWAN)                       |
|                                                                       |
|   +---------------------------------------------------------------+   |
|   |                 Managed Virtual Hub Router                    |   |
|   |         (Auto-propagates routes between all spokes)           |   |
|   +-------------------------------+-------------------------------+   |
|                                   |                                   |
|   +-------------------------------v-------------------------------+   |
|   |       Azure Firewall (Integrated Secured Hub Security)        |   |
|   +-------------------------------+-------------------------------+   |
|                                   |                                   |
|   +-------------------------------v-------------------------------+   |
|   |       vWAN VPN / ExpressRoute Gateway (Auto-scaled)          |   |
|   +---------------------------------------------------------------+   |
+-----------------------------------+-----------------------------------+
                                    |
                                    v
                            [ On-Prem Network ]
```


