#!/bin/bash

# Setup script for EKS Pod Identity Agent
# This script installs the EKS Pod Identity Agent addon to your EKS cluster

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
    print_error "Usage: $0 <cluster-name> [region]"
    print_error "Example: $0 my-eks-cluster us-west-2"
    exit 1
fi

CLUSTER_NAME=$1
REGION=${2:-us-west-2}

print_status "Setting up EKS Pod Identity Agent for cluster: $CLUSTER_NAME in region: $REGION"

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

# Verify cluster exists
print_status "Verifying cluster exists..."
if ! aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" &> /dev/null; then
    print_error "Cluster $CLUSTER_NAME not found in region $REGION"
    exit 1
fi

# Update kubeconfig
print_status "Updating kubeconfig..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

# Check if Pod Identity Agent addon is already installed
print_status "Checking if Pod Identity Agent is already installed..."
if aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name eks-pod-identity-agent --region "$REGION" &> /dev/null; then
    print_warning "Pod Identity Agent addon is already installed"
    
    # Get current status
    ADDON_STATUS=$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name eks-pod-identity-agent --region "$REGION" --query 'addon.status' --output text)
    print_status "Current addon status: $ADDON_STATUS"
    
    if [ "$ADDON_STATUS" = "ACTIVE" ]; then
        print_status "Pod Identity Agent is already active"
    else
        print_warning "Pod Identity Agent is not active. Current status: $ADDON_STATUS"
    fi
else
    # Install the Pod Identity Agent addon
    print_status "Installing EKS Pod Identity Agent addon..."
    
    # Get the latest version
    LATEST_VERSION=$(aws eks describe-addon-versions --addon-name eks-pod-identity-agent --region "$REGION" --query 'addons[0].addonVersions[0].addonVersion' --output text)
    print_status "Installing version: $LATEST_VERSION"
    
    aws eks create-addon \
        --cluster-name "$CLUSTER_NAME" \
        --addon-name eks-pod-identity-agent \
        --addon-version "$LATEST_VERSION" \
        --region "$REGION" \
        --resolve-conflicts OVERWRITE
    
    print_status "Waiting for addon to become active..."
    aws eks wait addon-active --cluster-name "$CLUSTER_NAME" --addon-name eks-pod-identity-agent --region "$REGION"
fi

# Verify the agent pods are running
print_status "Verifying Pod Identity Agent pods are running..."
sleep 10  # Give some time for pods to start

POD_COUNT=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent --no-headers 2>/dev/null | wc -l)
if [ "$POD_COUNT" -gt 0 ]; then
    print_status "Pod Identity Agent pods are running:"
    kubectl get pods -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent
else
    print_warning "No Pod Identity Agent pods found. Checking with alternative selector..."
    kubectl get pods -n kube-system | grep -i "pod-identity" || true
fi

print_status "EKS Pod Identity Agent setup completed successfully!"
print_status ""
print_status "Next steps:"
print_status "1. Create an IAM role with EFS permissions"
print_status "2. Create a Kubernetes service account"
print_status "3. Associate the IAM role with the service account using pod identity"
print_status "4. Deploy your application with the service account"