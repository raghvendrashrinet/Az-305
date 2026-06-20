## AZ-305 MODULE 1
  #### IDENTITY + GOVERNANCE + MONITORING
```

                    ┌── Authentication
                    │   ├─ Entra ID
                    │   ├─ MFA ⭐
                    │   ├─ SSO ⭐
                    │   ├─ Conditional Access ⭐⭐⭐
                    │   └─ B2B vs B2C ⭐
Identity ───────────┤
                    ├── Authorization
                    │   ├─ RBAC ⭐⭐⭐
                    │   ├─ Custom Roles
                    │   ├─ PIM ⭐⭐⭐
                    │   └─ Least Privilege ⭐⭐⭐
                    │
                    ├── App Identity
                    │   ├─ Managed Identity ⭐⭐⭐
                    │   ├─ Service Principal ⭐⭐
                    │   └─ Enterprise Apps
                    │
                    ├── Secrets
                    │   ├─ Key Vault ⭐⭐⭐
                    │   ├─ Certificates
                    │   └─ Keys

Governance
├── Management Groups ⭐⭐⭐
├── Subscriptions
├── Resource Groups
├── Tags ⭐⭐
├── Azure Policy ⭐⭐⭐
├── Landing Zones ⭐⭐⭐
└── Resource Locks

Monitoring
├── Azure Monitor ⭐⭐⭐
├── Log Analytics ⭐⭐⭐
├── Application Insights ⭐⭐⭐
├── Alerts
├── Metrics
├── Diagnostic Settings
└── Workbooks
```

###  Remember for Exam
```
Authentication → Entra ID
Authorization → RBAC
Temporary Admin → PIM
Secrets → Key Vault
No credentials → Managed Identity
Governance → Policy + Landing Zones
Application Monitoring → Application Insights
Infrastructure Monitoring → Azure Monitor
```

### Key Concepts
#### 1. PIM(Privileged Identity Management) only available in  P2 License  
* Provides:
- Just-In-Time (JIT) access: Users are not permanent admins. When they need to perform an admin task, they must request activation
- Time-Bound : Once approved, the admin access automatically expires after a set period (e.g., 2 hours).  
 For Approval Workflow: Activation can require multi-factor authentication (MFA), a business justification, or approval from a designated manager.

#### 2. Conditional Access (CA) is your "If-Then" engine for identity security
* Signals (The "If"): The conditions evaluated before allowing access.
   - User/Group membership: Who is trying to sign in?
   - IP/Location: Is it from a trusted corporate network or an unexpected country?
   - Device state: Is the device compliant (e.g., enrolled in Intune)?
   - Application: What specific cloud app are they trying to access?
   - Sign-in risk: Microsoft Entra ID Protection flags if the behavior looks suspicious.  

* Controls (The "Then"): What happens once the signals are processed.
   - Block Access: Hard denial.
   - Grant Access: Allow entry, but usually with a catch (e.g., Require MFA, Require Compliant Device, or Force Password Change).
##### Note : Conditional Access requires Microsoft Entra ID P1 or higher. (Risk-based Conditional Access policies require P2).

#### 3. Microsoft Entra ID Protection (Risk Assessment)
* **Automated:** Risk calculation happens automatically in the background.
* **User Risk:** Probability that credentials are leaked (e.g., leaked on dark web).
* **Sign-in Risk:** Probability that the sign-in isn't the owner (e.g., impossible travel).
* **Enforcement:** Used as a signal in Risk-Based Conditional Access to block or force MFA.
##### Note: Requires Microsoft Entra ID P2 License.

