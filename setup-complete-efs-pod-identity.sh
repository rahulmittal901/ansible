#!/bin/bash

# Complete setup script for EKS Pod Identity with EFS
# This script orchestrates the entire setup process

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if required parameters are provided
if [ $# -lt 1 ]; then
    echo "Complete EKS Pod Identity with EFS Setup"
    echo "======================================"
    echo ""
    print_error "Usage: $0 <cluster-name> [region] [efs-file-system-id]"
    print_error "Example: $0 my-eks-cluster us-west-2 fs-12345678"
    echo ""
    echo "This script will:"
    echo "1. Install EKS Pod Identity Agent"
    echo "2. Create IAM role and policy for EFS access"
    echo "3. Install EFS CSI Driver"
    echo "4. Create Kubernetes service account"
    echo "5. Create pod identity association"
    echo "6. Deploy sample application with EFS mount"
    echo ""
    exit 1
fi

CLUSTER_NAME=$1
REGION=${2:-us-west-2}
EFS_FILE_SYSTEM_ID=${3}
NAMESPACE="efs-demo"
SERVICE_ACCOUNT_NAME="efs-pod-identity-sa"
ROLE_NAME="EKSPodIdentityEFSRole"

print_header "Starting complete EKS Pod Identity with EFS setup"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Namespace: $NAMESPACE"
echo "Service Account: $SERVICE_ACCOUNT_NAME"
echo "IAM Role: $ROLE_NAME"
if [ -n "$EFS_FILE_SYSTEM_ID" ]; then
    echo "EFS File System ID: $EFS_FILE_SYSTEM_ID"
else
    print_warning "No EFS file system ID provided. You'll need to update the manifests with your EFS ID."
fi
echo ""

# Step 1: Install EKS Pod Identity Agent
print_header "Step 1: Installing EKS Pod Identity Agent"
if [ -f "./setup-pod-identity-agent.sh" ]; then
    chmod +x ./setup-pod-identity-agent.sh
    ./setup-pod-identity-agent.sh "$CLUSTER_NAME" "$REGION"
else
    print_error "setup-pod-identity-agent.sh not found!"
    exit 1
fi
echo ""

# Step 2: Create IAM role and policy
print_header "Step 2: Creating IAM role and policy for EFS access"
if [ -f "./create-iam-role-for-efs.sh" ]; then
    chmod +x ./create-iam-role-for-efs.sh
    ./create-iam-role-for-efs.sh --role-name "$ROLE_NAME" --region "$REGION"
    
    # Get the role ARN
    if [ -f "/tmp/efs-role-arn.txt" ]; then
        ROLE_ARN=$(cat /tmp/efs-role-arn.txt)
        print_status "Role ARN: $ROLE_ARN"
    else
        print_error "Could not find role ARN. Please check the IAM role creation."
        exit 1
    fi
else
    print_error "create-iam-role-for-efs.sh not found!"
    exit 1
fi
echo ""

# Step 3: Install EFS CSI Driver
print_header "Step 3: Installing Amazon EFS CSI Driver"
if [ -f "./install-efs-csi-driver.sh" ]; then
    chmod +x ./install-efs-csi-driver.sh
    ./install-efs-csi-driver.sh "$CLUSTER_NAME" "$REGION"
else
    print_error "install-efs-csi-driver.sh not found!"
    exit 1
fi
echo ""

# Step 4: Create namespace and service account
print_header "Step 4: Creating namespace and service account"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f service-account.yaml
echo ""

# Step 5: Create pod identity association
print_header "Step 5: Creating pod identity association"
if [ -f "./create-pod-identity-association.sh" ]; then
    chmod +x ./create-pod-identity-association.sh
    ./create-pod-identity-association.sh "$CLUSTER_NAME" "$ROLE_ARN" "$NAMESPACE" "$SERVICE_ACCOUNT_NAME" "$REGION"
else
    print_error "create-pod-identity-association.sh not found!"
    exit 1
fi
echo ""

# Step 6: Update manifests with EFS file system ID (if provided)
if [ -n "$EFS_FILE_SYSTEM_ID" ]; then
    print_header "Step 6: Updating manifests with EFS file system ID"
    
    # Update storage class
    sed -i "s/fs-12345678/$EFS_FILE_SYSTEM_ID/g" efs-storage-class.yaml
    
    # Update PV/PVC
    sed -i "s/fs-12345678/$EFS_FILE_SYSTEM_ID/g" efs-pv-pvc.yaml
    
    print_status "Updated manifests with EFS file system ID: $EFS_FILE_SYSTEM_ID"
else
    print_warning "Please update the following files with your EFS file system ID:"
    print_warning "- efs-storage-class.yaml"
    print_warning "- efs-pv-pvc.yaml"
    print_warning "Replace 'fs-12345678' with your actual EFS file system ID"
fi
echo ""

# Step 7: Deploy EFS resources
print_header "Step 7: Deploying EFS storage resources"
kubectl apply -f efs-storage-class.yaml
kubectl apply -f efs-pv-pvc.yaml
echo ""

# Step 8: Deploy sample application
print_header "Step 8: Deploying sample application"
kubectl apply -f efs-deployment.yaml
echo ""

# Step 9: Verify deployment
print_header "Step 9: Verifying deployment"
print_status "Waiting for pods to be ready..."
kubectl wait --for=condition=ready --timeout=300s pod -l app=efs-demo -n "$NAMESPACE"

print_status "Checking pod status:"
kubectl get pods -n "$NAMESPACE" -l app=efs-demo

print_status "Checking PVC status:"
kubectl get pvc -n "$NAMESPACE"

print_status "Checking service account:"
kubectl get serviceaccount "$SERVICE_ACCOUNT_NAME" -n "$NAMESPACE"

echo ""
print_header "Setup Complete!"
print_status "Your EKS cluster is now configured with Pod Identity for EFS access."
echo ""
print_status "To verify EFS mounting, you can:"
echo "1. Check pod logs: kubectl logs -n $NAMESPACE -l app=efs-demo"
echo "2. Exec into a pod: kubectl exec -n $NAMESPACE -it <pod-name> -- /bin/bash"
echo "3. Check mounted EFS: kubectl exec -n $NAMESPACE -it <pod-name> -- ls -la /mnt/efs"
echo ""
print_status "Pod Identity Association Details:"
aws eks list-pod-identity-associations --cluster-name "$CLUSTER_NAME" --region "$REGION" --query "associations[?namespace=='$NAMESPACE' && serviceAccount=='$SERVICE_ACCOUNT_NAME']" --output table

echo ""
print_status "Setup completed successfully! 🎉"