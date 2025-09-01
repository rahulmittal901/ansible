#!/bin/bash

# Script to install Amazon EFS CSI Driver for EKS
# This driver is required to mount EFS file systems in EKS pods

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if required parameters are provided
if [ $# -lt 1 ]; then
    print_error "Usage: $0 <cluster-name> [region] [service-account-role-arn]"
    print_error "Example: $0 my-eks-cluster us-west-2 arn:aws:iam::123456789012:role/EKSPodIdentityEFSRole"
    exit 1
fi

CLUSTER_NAME=$1
REGION=${2:-us-west-2}
SERVICE_ACCOUNT_ROLE_ARN=$3

print_status "Installing Amazon EFS CSI Driver for cluster: $CLUSTER_NAME in region: $REGION"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please install it first."
    exit 1
fi

# Update kubeconfig
print_status "Updating kubeconfig..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

# Method 1: Install via EKS Add-on (Recommended)
print_status "Checking if EFS CSI Driver add-on is available..."

if aws eks describe-addon-versions --addon-name aws-efs-csi-driver --region "$REGION" &> /dev/null; then
    print_status "EFS CSI Driver add-on is available. Installing via EKS add-on..."
    
    # Check if addon is already installed
    if aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name aws-efs-csi-driver --region "$REGION" &> /dev/null; then
        print_warning "EFS CSI Driver add-on is already installed"
        ADDON_STATUS=$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name aws-efs-csi-driver --region "$REGION" --query 'addon.status' --output text)
        print_status "Current addon status: $ADDON_STATUS"
    else
        # Get the latest version
        LATEST_VERSION=$(aws eks describe-addon-versions --addon-name aws-efs-csi-driver --region "$REGION" --query 'addons[0].addonVersions[0].addonVersion' --output text)
        print_status "Installing EFS CSI Driver version: $LATEST_VERSION"
        
        # Create addon configuration
        ADDON_CONFIG=""
        if [ -n "$SERVICE_ACCOUNT_ROLE_ARN" ]; then
            print_status "Configuring with service account role: $SERVICE_ACCOUNT_ROLE_ARN"
            ADDON_CONFIG="--service-account-role-arn $SERVICE_ACCOUNT_ROLE_ARN"
        fi
        
        aws eks create-addon \
            --cluster-name "$CLUSTER_NAME" \
            --addon-name aws-efs-csi-driver \
            --addon-version "$LATEST_VERSION" \
            --region "$REGION" \
            --resolve-conflicts OVERWRITE \
            $ADDON_CONFIG
        
        print_status "Waiting for addon to become active..."
        aws eks wait addon-active --cluster-name "$CLUSTER_NAME" --addon-name aws-efs-csi-driver --region "$REGION"
        print_status "EFS CSI Driver add-on installed successfully!"
    fi
else
    # Method 2: Install via kubectl (Fallback)
    print_warning "EFS CSI Driver add-on not available. Installing via kubectl..."
    
    # Check if already installed
    if kubectl get deployment efs-csi-controller -n kube-system &> /dev/null; then
        print_warning "EFS CSI Driver is already installed via kubectl"
    else
        print_status "Installing EFS CSI Driver using kubectl..."
        kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/ecr/?ref=release-1.7"
        
        print_status "Waiting for EFS CSI Driver to be ready..."
        kubectl wait --for=condition=available --timeout=300s deployment/efs-csi-controller -n kube-system
        kubectl wait --for=condition=ready --timeout=300s pod -l app=efs-csi-controller -n kube-system
    fi
fi

# Verify installation
print_status "Verifying EFS CSI Driver installation..."

# Check controller deployment
if kubectl get deployment efs-csi-controller -n kube-system &> /dev/null; then
    print_status "EFS CSI Controller is running:"
    kubectl get deployment efs-csi-controller -n kube-system
else
    print_error "EFS CSI Controller deployment not found!"
    exit 1
fi

# Check node daemonset
if kubectl get daemonset efs-csi-node -n kube-system &> /dev/null; then
    print_status "EFS CSI Node DaemonSet is running:"
    kubectl get daemonset efs-csi-node -n kube-system
else
    print_error "EFS CSI Node DaemonSet not found!"
    exit 1
fi

# Check CSI driver
print_status "Checking CSI driver registration..."
if kubectl get csidriver efs.csi.aws.com &> /dev/null; then
    print_status "EFS CSI Driver is registered:"
    kubectl get csidriver efs.csi.aws.com
else
    print_error "EFS CSI Driver not registered!"
    exit 1
fi

# Show all EFS CSI related pods
print_status "EFS CSI Driver pods:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver

print_status "Amazon EFS CSI Driver installation completed successfully!"
print_status ""
print_status "Next steps:"
print_status "1. Create an EFS file system if you haven't already"
print_status "2. Create StorageClass, PersistentVolume, and PersistentVolumeClaim"
print_status "3. Deploy your application with EFS volumes"
print_status ""
print_status "Example EFS file system creation:"
print_status "aws efs create-file-system --creation-token my-efs-token --region $REGION"