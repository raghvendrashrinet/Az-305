## Partition Key Decision Tree
- A Partition Key is a core concept in distributed databases (like Azure Cosmos DB). It is the property or field in your data that the database engine uses to split and group your data into smaller, logical pieces called partitions.
- Why do we need a Partition Key?
Distributed databases scale horizontally. Instead of buying a bigger, more expensive server, they add more servers (nodes) to handle the load.

The database uses your partition key to distribute data and workload evenly across these servers.

```
Large Data?

      │
      ▼
Need Horizontal Scaling?

      │
Partition Key

Good Distribution?

      │
High Cardinality

Avoid Hot Partition?

      │
Evenly Distributed Key
```

Exam Tip

Bad partition key

❌ Country

Good partition key

✅ CustomerId
