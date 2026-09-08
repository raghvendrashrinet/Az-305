# KB: Database Migration Strategies to Microsoft Azure

Migrating databases from on-premises environments to Microsoft Azure depends entirely on business requirements, downtime tolerance, and long-term cloud goals.  
Microsoft defines **four core migration plans**, categorized by how you handle the underlying database engine during the move.

---

## 1. Rehost (Lift-and-Shift)
Move your database to the cloud **as-is** with zero changes to the engine or code.  
You simply shift from on-premises hardware to Azure infrastructure.

- **Target Azure Service:** Azure Virtual Machines (IaaS) running SQL Server, Oracle, MySQL, or PostgreSQL.  
- **Best Used For:** Legacy applications requiring OS-level access, custom third-party plugins, or unsupported database versions.  
- **Pros & Cons:** Fastest migration, lowest risk. Still responsible for patching, OS maintenance, backups, and licensing.

---

## 2. Replatform (Managed Lift-and-Shift)
Keep the same database engine but move it onto an **Azure fully managed database service (PaaS).**

- **Target Azure Service:**  
  - SQL Server → Azure `SQL Managed Instance` (near 100% compatibility) or `Azure SQL Database` (isolated cloud-native).  
  - Open Source → Azure Database for PostgreSQL or MySQL.  
- **Best Used For:** Teams wanting to reduce operational overhead (backups, scaling, patching) without rewriting queries.  
- **Pros & Cons:** Major reduction in admin work, built-in HA. Requires minor compatibility testing.
```
       AZURE SQL DATABASE                      AZURE SQL MANAGED INSTANCE
+------------------------------+              +------------------------------+

|  +-------+  +-------+        |              |  +-------+  +-------+        |
|  | DB 1  |  | DB 2  |        |              |  | DB 1  |  | DB 2  |        |
|  +-------+  +-------+        |              |  +-------+  +-------+        |
|                              |              +------------------------------+
|  - Completely Isolated       |              |     Shared SQL Instance      |
|  - Independent Scaling/RAM   |              |  (SQL Agent, Linked Servers, |
|  - No Instance Boundaries    |              |   Shared Resources, Cross-DB)|
+==============================+              +==============================+

|   MICROSOFT MANAGED LAYER    |              |   MICROSOFT MANAGED LAYER    |
+------------------------------+              +------------------------------+

```

- `Azure SQL Database `: Built for modern, cloud-native apps or microservices requiring isolated databases.  
- `Azure SQL Managed Instance`: Built for `lifting and shifting` legacy on-premises workloads to the cloud with zero code changes.
---

## 3. Refactor / Rearchitect
Modify or break apart your database structure to leverage **cloud-native features, massive scale, or microservices.**

- **Target Azure Service:** Azure Cosmos DB (NoSQL/NewSQL), or split monolithic SQL into multiple Azure SQL Databases.  
- **Best Used For:** Apps redesigned for global scale, multi-region writes, or converting relational → non-relational.  
- **Pros & Cons:** Extreme scalability and performance. Requires significant code rewrites and development effort.

---

## 4. Modernize / Replatform (Cross-Engine)
Switch from a **commercial, expensive database engine** to an open-source or cloud-native variant to cut licensing costs.

- **Target Azure Service:** Migrate Oracle or IBM DB2 → Azure Database for PostgreSQL.  
- **Best Used For:** Businesses aiming to reduce costs and break free from restrictive enterprise contracts.  
- **Pros & Cons:** Huge long-term savings. Requires schema/code conversion tools for stored procedures and logic.

---

## Technical Migration Execution Styles

Regardless of the migration plan, you must decide **how data transfers over the network.**

| **Migration Type**   | **How It Works**                                                                 | **Downtime** | **Best Tool To Use** |
|-----------------------|----------------------------------------------------------------------------------|--------------|----------------------|
| **Offline Migration** | Source DB shut down or set to read-only. Backup copied and restored in Azure.    | High (hours–days depending on size) | Azure Migrate or backup/restore scripts |
| **Online Migration**  | Baseline backup restored in Azure; ongoing changes synced in real-time until cutover. | Near-Zero (minutes/seconds to switch connection string) | Azure Database Migration Service (DMS) |

---
