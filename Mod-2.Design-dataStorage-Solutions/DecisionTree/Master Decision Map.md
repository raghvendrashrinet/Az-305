## Master Decision Map

```
Need Data Storage
        │
        ▼
Structured?
 │             │
Yes            No
 │              │
Azure SQL     Blob/File

Need SQL Compatibility?
 │
Managed Instance

Need Full SQL Server?
 │
SQL VM

Need Global Scale?
 │
Cosmos DB

Need Analytics?
 │
Data Lake

Need Files?
 │
Azure Files

Need Archive?
 │
Archive Tier

Need DR?
 │
GRS / GZRS

Need Private Access?
 │
Private Endpoint

Need Migration?
 │
Azure Migrate / DMS
```

## 📌 Module 2 "If You See This, Think That"
| If the exam says...                | Think...                   |
| ---------------------------------- | -------------------------- |
| Managed relational database        | Azure SQL Database         |
| Lift-and-shift SQL Server          | SQL Managed Instance       |
| Full SQL Server/OS control         | SQL Server on Azure VM     |
| Globally distributed NoSQL         | Cosmos DB                  |
| Document database                  | Cosmos DB                  |
| Shared SMB file storage            | Azure Files                |
| Store images/videos                | Blob Storage               |
| Big data analytics                 | Data Lake Gen2             |
| Cheapest redundancy                | LRS                        |
| Zone resilience                    | ZRS                        |
| Cross-region disaster recovery     | GRS                        |
| Read access during regional outage | RA-GRS                     |
| Maximum resilience                 | GZRS                       |
| Temporary external access          | SAS Token                  |
| Private storage access             | Private Endpoint           |
| Database migration                 | Database Migration Service |
| Full environment migration         | Azure Migrate              |


## 🎯 AZ-305 Exam Strategy for Module 2

When answering storage questions, always evaluate in this order:

* Data type (Relational, NoSQL, Files, Objects)
* Scale (Single region vs Global)
* Availability (LRS, ZRS, GRS, GZRS)
* Security (RBAC, SAS, Private Endpoint, Key Vault)
* Migration (Azure Migrate, DMS, AzCopy)
* Cost (Access tier: Hot, Cool, Cold, Archive)
