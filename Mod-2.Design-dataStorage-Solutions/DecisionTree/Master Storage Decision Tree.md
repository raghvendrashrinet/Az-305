## Master Storage Decision Tree
```
Need to store data?

            │
            ▼
Structured?
      /            \
    YES             NO
     │               │
Need SQL?        File/Object?
     │               │
Azure SQL      Blob/File Storage

Need Global Scale?
     │
Cosmos DB

Need Analytics?
     │
Data Lake Gen2

Need Shared Files?
     │
Azure Files

Need Archive?
     │
Blob Archive Tier

```
### Memory Rule

* Rows → SQL (or Cosmos DB for PostgreSQL if globally distributed).
    Cosmos DB now does have a Relational API : Azure Cosmos DB for PostgreSQL   
* Documents → Cosmos DB 
* Files → Azure Files
* Objects → Blob
* Analytics → Data Lake

## Cosmis DB  
Azure Cosmos DB has evolved beyond just being a document database. It now includes Azure Cosmos DB for PostgreSQL, which is a fully relational, distributed database engine. If you need a traditional relational database (with tables, joins, and foreign keys) but require global, multi-region scale that standard Azure SQL can't easily match, Cosmos DB is now a valid choice  

he most ironic part about Cosmos DB: the query language is SQL! Even though it is fundamentally a NoSQL document database storing JSON files, Microsoft built a SQL query engine on top of it.

This means you use the exact same relational keywords you already know—like SELECT, FROM, WHERE, JOIN, and GROUP BY—to query your non-relational JSON documents.
