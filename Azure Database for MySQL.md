#### two different dimensions: 
 - Deployment Models (Single vs. Flexible) and
 - Compute Tiers (General Purpose vs. Burstable).

1. Single Server (Legacy / Deprecated): 
2. Flexible Server (Modern & Recommended):
   -  Zone Redundancy: Can place standby replicas in a different Availability Zone for instant datacenter failover.
   -  Cost Savings: Allows you to stop/start the instance dynamically (so you don't pay for compute when shut down at night).
   -  Maintenance Windows: Allows setting specific days/times for maintenance updates.
  
**General Purpose vs. Burstable**
 - General Purpose (GP): Provides scalable, continuous, predictable CPU and RAM performance (using Azure D-Series VMs).(production env)
 - Uses lower-cost B-Series VMs that run at a low CPU baseline but can "burst" to full CPU power when traffic spikes occur(non production)
