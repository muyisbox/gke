# Task 5: Network Policies + Istio mTLS — Defense in Depth

**Level:** Advanced

**Objective:** Implement layered network security using Kubernetes NetworkPolicies (L3/L4) and Istio mTLS/AuthorizationPolicies (L7).

## Context

This platform has GKE network policy enabled (`network_policy = true` in `gke.tf`). Combined with Istio's mTLS and authorization policies, you can enforce zero-trust networking at multiple layers.

## Steps

### Part A: Network Policy — Namespace Isolation

1. Create isolated namespaces:

   ```bash
   kubectl create namespace team-a
   kubectl create namespace team-b
   kubectl label namespace team-a istio-injection=enabled
   kubectl label namespace team-b istio-injection=enabled
   ```

2. Deploy workloads:

   ```bash
   kubectl run server-a --image=nginx -n team-a --port=80
   kubectl expose pod server-a -n team-a --port=80
   kubectl run server-b --image=nginx -n team-b --port=80
   kubectl expose pod server-b -n team-b --port=80
   kubectl run client-a --image=busybox -n team-a -- sleep 3600
   kubectl run client-b --image=busybox -n team-b -- sleep 3600
   ```

3. Verify cross-namespace access (should work):

   ```bash
   kubectl exec client-a -n team-a -- wget -qO- --timeout=3 http://server-b.team-b
   kubectl exec client-b -n team-b -- wget -qO- --timeout=3 http://server-a.team-a
   ```

4. Apply a deny-all policy for team-a:

   ```yaml
   # deny-all-team-a.yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: deny-all
     namespace: team-a
   spec:
     podSelector: {}
     policyTypes: [Ingress, Egress]
   ```

5. Allow only same-namespace traffic and DNS:

   ```yaml
   # allow-same-namespace.yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-same-namespace
     namespace: team-a
   spec:
     podSelector: {}
     policyTypes: [Ingress, Egress]
     ingress:
     - from:
       - namespaceSelector:
           matchLabels:
             kubernetes.io/metadata.name: team-a
     egress:
     - to:
       - namespaceSelector:
           matchLabels:
             kubernetes.io/metadata.name: team-a
     - ports:
       - port: 53
         protocol: UDP
       - port: 53
         protocol: TCP
   ```

6. Apply and test:

   ```bash
   kubectl apply -f deny-all-team-a.yaml -f allow-same-namespace.yaml

   # This should fail (cross-namespace blocked):
   kubectl exec client-b -n team-b -- wget -qO- --timeout=3 http://server-a.team-a

   # This should work (same namespace):
   kubectl exec client-a -n team-a -- wget -qO- --timeout=3 http://server-a.team-a
   ```

### Part B: Istio mTLS — Strict Mode

7. Apply mesh-wide strict mTLS:

   ```yaml
   # strict-mtls-mesh.yaml
   apiVersion: security.istio.io/v1
   kind: PeerAuthentication
   metadata:
     name: default
     namespace: istio-system
   spec:
     mtls:
       mode: STRICT
   ```

8. Deploy a non-mesh pod and verify it's blocked:

   ```bash
   kubectl run no-mesh --image=busybox -n team-b \
     --overrides='{"metadata":{"annotations":{"sidecar.istio.io/inject":"false"}}}' \
     -- sh -c "wget -qO- --timeout=3 http://server-b 2>&1; sleep 3600"
   kubectl logs no-mesh -n team-b
   ```

### Part C: Istio AuthorizationPolicy — L7 Controls

9. Allow only GET requests to server-a:

   ```yaml
   # authz-get-only.yaml
   apiVersion: security.istio.io/v1
   kind: AuthorizationPolicy
   metadata:
     name: allow-get-only
     namespace: team-a
   spec:
     selector:
       matchLabels:
         run: server-a
     action: ALLOW
     rules:
     - to:
       - operation:
           methods: ["GET"]
       from:
       - source:
           namespaces: ["team-a"]
   ```

10. Test — GET works, POST is denied:

    ```bash
    kubectl exec client-a -n team-a -- wget -qO- --timeout=3 http://server-a  # Works
    kubectl exec client-a -n team-a -- wget --post-data='test' -qO- --timeout=3 http://server-a  # Denied
    ```

### Part D: Defense in Depth Summary

11. You now have 3 layers of security:

    | Layer | Technology | Level | What It Controls |
    |-------|-----------|-------|-----------------|
    | 1 | NetworkPolicy | L3/L4 | Which pods can talk to which (IP + port) |
    | 2 | PeerAuthentication | L4 | Encrypts all pod-to-pod traffic (mTLS) |
    | 3 | AuthorizationPolicy | L7 | Which HTTP methods/paths are allowed |

## Cleanup

```bash
kubectl delete peerauthentication default -n istio-system
kubectl delete namespace team-a team-b
```

## Key Concepts

- **NetworkPolicy**: Enforced by GKE's network plugin at the kernel level
- **mTLS (PeerAuthentication)**: Enforced by Istio sidecars, encrypts traffic
- **AuthorizationPolicy**: L7 access control (methods, paths, headers, JWT claims)
- **Defense in depth**: Even if one layer fails, others still protect
- **Zero trust**: Never assume traffic is safe just because it's internal
