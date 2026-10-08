#### Reliability  
the ability of a system to consistently perform its intended functions correctly and predictably, even when failures occur.

<img width="438" height="282" alt="image" src="https://github.com/user-attachments/assets/f949b41b-6fe3-4220-bf1c-2ea62201c5fa" />

#### 1. Resilience (High Availability & Self-Healing):
Designing the app so it continues running during localized failures or minor glitches without manual intervention (e.g., automatic failover, load balancing across Availability Zones, retry logic with exponential backoff, and local caching).
  - VM Level: Self-healing VM instances,VMSS, AKS: Pod Restart(Liveness Probe fail)
#### 2. Business Continuity & Disaster Recovery (BCDR):
1. Backups: Creating redundant copies of data to restore in case of data corruption, deletion, or loss.
2. Disaster Recovery (DR): The strategy and processes for failing over to a secondary region or infrastructure during a catastrophic regional outage or major disaster.
3. Targets: Defined by RTO (down time window) and RPO (data loss window).

#### 3. Operational Health & Observability:
Continuously monitoring system `metrics`, `logging` performance, and detecting drift or potential failures early so you can remediate them before users are impacted.
