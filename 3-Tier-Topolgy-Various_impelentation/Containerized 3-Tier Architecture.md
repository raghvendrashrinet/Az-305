## Containerized 3-Tier Architecture
#### The Core Concept: Microservices vs. 3-Tier Container Topology
In a modern containerized 3-tier setup, we don't just run virtual machines; we break our layers down into lightweight, ephemeral containers.

- The Ingress (Tier 1): The Application Gateway acts as our L7 entry point, terminating SSL and running WAF.
- The Container Orchestrator (Tier 2): We deploy Azure Kubernetes Service (AKS) inside our private Spoke VNet. This orchestrator manages the lifecycle, scaling, and networking of our frontend and backend containerized microservices.
- The Data Tier (Tier 3): Databases remain outside the cluster on highly secure, managed PaaS services (like Azure SQL or Cosmos DB) accessed via Private Endpoints.
#### Step 1: Private AKS Network Design (BYO VNet)
To maintain a zero-trust model, your AKS cluster must never be exposed directly to the public internet. We deploy a Private AKS Cluster.

```
==================================================================================================
                                PRIVATE AKS SPOKE NETWORKING
==================================================================================================

                 [ Public Traffic ] ──► [ Azure Front Door ]
                                               │
                                               ▼
                                  ┌──────────────────────────┐
                                  │ Application Gateway + WAF│ (Public Ingress Subnet)
                                  └────────────┬─────────────┘
                                               │ (Decrypted / WAF Cleared)
                                               ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ SPOKE VNET                                                                             │
│                                                                                        │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ AKS Cluster Subnet (10.240.0.0/16)                                             │   │
│   │                                                                                │   │
│   │   ┌────────────────────────┐              ┌────────────────────────┐           │   │
│   │   │ Frontend Pods          │             │ Backend Pods           │           │   │
│   │   │ (ClusterIP Service)    │ ──────────►  │ (ClusterIP Service)    │           │   │
│   │   └────────────────────────┘              └───────────┬────────────┘           │   │
│   └───────────────────────────────────────────────────────┼────────────────────────┘   │
│                                                           │                            │
│   ┌───────────────────────────────────────────────────────▼────────────────────────┐   │
│   │ Private Endpoint Subnet                                                        │   │
│   │   └── [ Private Endpoint ] ──────────────────────────► Azure SQL Database      │   │
│   └────────────────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────────────────┘
```
1. Cluster Subnet: AKS is deployed using the Azure CNI (Container Network Interface) plug-in, meaning every single Kubernetes Pod gets a real, routable IP address directly from your Spoke VNet subnet (10.240.0.0/16).
2. Private Control Plane: The Kubernetes API server (the brain of AKS) is deployed with a private IP address. Only systems inside your Hub-and-Spoke network (like your Azure Bastion or self-hosted DevOps build runners) can issue kubectl commands to the cluster.

#### Step 2: Ingress Integration (App Gateway Ingress Controller - AGIC)
In a Kubernetes cluster, you need an Ingress Controller to route external HTTP traffic to your internal services. Instead of running a software proxy (like NGINX) inside your cluster, Azure allows you to use the Application Gateway Ingress Controller (AGIC).
- How it works: AGIC runs as a pod inside your AKS cluster. It monitors Kubernetes Ingress resources
- The Magic: When you deploy a new containerized application, AGIC automatically configures your physical Azure Application Gateway's routing rules, listeners, and backend pools in real-time.
- Direct Routing: Traffic flows directly from the Application Gateway to your Pod IPs, bypassing extra hops and optimizing network performance.

#### Step 3: Zero-Trust Pod-to-Pod Security (Network Policies)
Just because your containers live in the same cluster doesn't mean they should all be able to talk to each other. If a hacker compromises a public-facing Frontend Pod, they shouldn't be able to bypass the App layer and query the Database.

We enforce Kubernetes Network Policies (using Azure NPM or Calico) to create micro-segmentation:
```yaml
# Example: Restricting Backend to ONLY accept traffic from Frontend
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-only
  namespace: app-tier
spec:
  podSelector:
    matchLabels:
      app: backend-api
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend-ui
```
#### Step 4: Passwordless Database Authentication (Microsoft Entra ID Pod Identity)
In a traditional VM-based setup, applications connect to the database using a connection string containing a username and password. This introduces key security risks: credentials can leak in code repositories, and rotating them requires redeployments.

In our modern AKS architecture, we eliminate this risk completely using Azure AD/Entra Workload ID.

How Workload ID Works (Zero-Secrets Connection):
- he Managed Identity: You create a user-assigned Managed Identity in Azure (e.g., id-aks-app-prod).

- The Kubernetes Trust: You establish a federated trust between your AKS cluster's OpenID Connect (OIDC) issuer and Microsoft Entra ID.

- The Service Account: You map a Kubernetes ServiceAccount to that Managed Identity using annotations:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend-service-account
  namespace: app-tier
  annotations:
    azure.workload.identity/client-id: "<YOUR_AZURE_MANAGED_IDENTITY_CLIENT_ID>"
```
- The Passwordless DB Connection: When your backend app starts up, it uses the official Azure Identity SDK to exchange its Kubernetes token for an Entra access token. It uses this token to authenticate directly with Azure SQL Database. There are zero passwords or keys stored in your code, container images, or Kubernetes secrets.

#### Step 5: Secure Application Configurations & Secret Management (Azure Key Vault Integration)
For application-specific secrets that cannot use Managed Identities (such as third-party API keys like Stripe or SendGrid), we integrate Azure Key Vault using the Secrets Store CSI Driver.
- No Local Storage: Secrets are stored securely inside Azure Key Vault (protected by your Hub network and private endpoints).

- On-Demand Mounting: The CSI Driver runs inside the cluster and uses the Workload ID identity to fetch secrets from Key Vault, mounting them directly into the Pod's memory filesystem as a temporary volume. They never touch physical disks in the cluster.




