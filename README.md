# EKS Pod Identity with EFS Setup

This repository contains scripts and Kubernetes manifests to set up Amazon EKS Pod Identity for accessing Amazon EFS (Elastic File System).

## Overview

EKS Pod Identity provides a way to associate IAM roles with Kubernetes service accounts, allowing pods to securely access AWS services without managing long-lived credentials. This setup demonstrates how to use Pod Identity to mount EFS file systems in your EKS pods.

## Prerequisites

- AWS CLI installed and configured
- kubectl installed and configured
- An existing EKS cluster
- An existing EFS file system (optional - can be created separately)

## Quick Start

### Option 1: Complete Automated Setup

Run the complete setup script:

```bash
chmod +x setup-complete-efs-pod-identity.sh
./setup-complete-efs-pod-identity.sh <cluster-name> [region] [efs-file-system-id]
```

Example:
```bash
./setup-complete-efs-pod-identity.sh my-eks-cluster us-west-2 fs-12345678
```

### Option 2: Step-by-Step Manual Setup

#### Step 1: Install EKS Pod Identity Agent

```bash
chmod +x setup-pod-identity-agent.sh
./setup-pod-identity-agent.sh <cluster-name> [region]
```

#### Step 2: Create IAM Role for EFS Access

```bash
chmod +x create-iam-role-for-efs.sh
./create-iam-role-for-efs.sh --role-name EKSPodIdentityEFSRole --region us-west-2
```

#### Step 3: Install EFS CSI Driver

```bash
chmod +x install-efs-csi-driver.sh
./install-efs-csi-driver.sh <cluster-name> [region]
```

#### Step 4: Create Service Account

```bash
kubectl apply -f service-account.yaml
```

#### Step 5: Create Pod Identity Association

```bash
chmod +x create-pod-identity-association.sh
./create-pod-identity-association.sh <cluster-name> <role-arn> [namespace] [service-account-name] [region]
```

#### Step 6: Update EFS File System ID

Update the following files with your EFS file system ID:
- `efs-storage-class.yaml`
- `efs-pv-pvc.yaml`

Replace `fs-12345678` with your actual EFS file system ID.

#### Step 7: Deploy EFS Resources

```bash
kubectl apply -f efs-storage-class.yaml
kubectl apply -f efs-pv-pvc.yaml
```

#### Step 8: Deploy Sample Application

```bash
kubectl apply -f efs-deployment.yaml
```

## Files Description

### Scripts

- **`setup-complete-efs-pod-identity.sh`**: Complete automated setup script
- **`setup-pod-identity-agent.sh`**: Installs the EKS Pod Identity Agent addon
- **`create-iam-role-for-efs.sh`**: Creates IAM role and policy for EFS access
- **`install-efs-csi-driver.sh`**: Installs the Amazon EFS CSI Driver
- **`create-pod-identity-association.sh`**: Creates the pod identity association

### Kubernetes Manifests

- **`service-account.yaml`**: Kubernetes service accounts for both `default` and `efs-demo` namespaces
- **`efs-storage-class.yaml`**: StorageClass for EFS with dynamic provisioning
- **`efs-pv-pvc.yaml`**: PersistentVolume and PersistentVolumeClaim for EFS
- **`efs-deployment.yaml`**: Sample deployment that uses EFS with Pod Identity

## Verification

After deployment, verify the setup:

1. **Check pod status:**
   ```bash
   kubectl get pods -n efs-demo -l app=efs-demo
   ```

2. **Check PVC status:**
   ```bash
   kubectl get pvc -n efs-demo
   ```

3. **Check Pod Identity associations:**
   ```bash
   aws eks list-pod-identity-associations --cluster-name <cluster-name>
   ```

4. **Verify EFS mount:**
   ```bash
   kubectl exec -n efs-demo -it <pod-name> -- ls -la /mnt/efs
   ```

5. **Check pod logs:**
   ```bash
   kubectl logs -n efs-demo -l app=efs-demo
   ```

## Troubleshooting

### Common Issues

1. **Pod Identity Agent not installed:**
   - Verify the agent is running: `kubectl get pods -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent`

2. **EFS CSI Driver not working:**
   - Check CSI driver pods: `kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver`
   - Verify CSI driver is registered: `kubectl get csidriver efs.csi.aws.com`

3. **Pod cannot mount EFS:**
   - Check if the EFS file system ID is correct in the manifests
   - Verify the security groups allow NFS traffic (port 2049)
   - Check if the EFS file system is in the same VPC as the EKS cluster

4. **Pod Identity association issues:**
   - Verify the association exists: `aws eks describe-pod-identity-association --cluster-name <cluster-name> --association-id <association-id>`
   - Check IAM role trust policy includes `pods.eks.amazonaws.com`

### Logs and Debugging

- **Pod Identity Agent logs:**
  ```bash
  kubectl logs -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent
  ```

- **EFS CSI Driver logs:**
  ```bash
  kubectl logs -n kube-system -l app=efs-csi-controller
  kubectl logs -n kube-system -l app=efs-csi-node
  ```

- **Application pod logs:**
  ```bash
  kubectl logs -n efs-demo -l app=efs-demo
  ```

## Security Considerations

1. **IAM Role Permissions**: The IAM role created has permissions for EFS access. Review and adjust permissions based on your security requirements.

2. **Network Security**: Ensure your EFS file system's security groups allow inbound NFS traffic (port 2049) from your EKS worker nodes.

3. **EFS Access Points**: Consider using EFS access points for better access control and isolation.

## Customization

### Using Different Namespaces

To use a different namespace, update the following:
1. Modify the namespace in `service-account.yaml`
2. Update the namespace in `efs-deployment.yaml`
3. Update the PVC namespace in `efs-pv-pvc.yaml`
4. Use the correct namespace when creating the pod identity association

### Using EFS Access Points

To use EFS access points, modify the `volumeHandle` in `efs-pv-pvc.yaml`:
```yaml
volumeHandle: fs-12345678::fsap-12345678abcdef123
```

### Custom Storage Class Parameters

Modify `efs-storage-class.yaml` to customize:
- Directory permissions
- GID ranges
- Base path for dynamic provisioning

## Clean Up

To remove all resources:

```bash
kubectl delete -f efs-deployment.yaml
kubectl delete -f efs-pv-pvc.yaml
kubectl delete -f efs-storage-class.yaml
kubectl delete -f service-account.yaml

# Delete pod identity association
aws eks delete-pod-identity-association --cluster-name <cluster-name> --association-id <association-id>

# Delete IAM role and policy
aws iam detach-role-policy --role-name EKSPodIdentityEFSRole --policy-arn <policy-arn>
aws iam delete-role --role-name EKSPodIdentityEFSRole
aws iam delete-policy --policy-arn <policy-arn>
```

## Additional Resources

- [EKS Pod Identity Documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [Amazon EFS CSI Driver](https://github.com/kubernetes-sigs/aws-efs-csi-driver)
- [Amazon EFS User Guide](https://docs.aws.amazon.com/efs/latest/ug/)