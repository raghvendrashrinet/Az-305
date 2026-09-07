
### Backup
 * backup policy frequency 
   - standard - daily once
   - enhanced - multiple backup daily
 * Instant restore
    - Fast Recovery: Keeps local snapshots on disk for 5 days, in a under the hood storage account(managed by azure)

* **Retention of backups**
  **Azure uses a `Grandfather-Father-Son (GFS)` retention model**
  - Retention of Daily Backup Point: 180 Days(configurable)
  - Retention of Weekly Backup Point: 12 Weeks (configurable)
  - Retention of Monthly Backup Point: 60 Months
  - Retention of Yearly  Backup Point:configurable

   Question : Maximum retention period of a snapshot : 60 months (5 years) for above configuration

  ---

  


   
    
