#!/bin/bash

# Script to create Pod Identity Association between Kubernetes Service Account and IAM Role
# This links the service account to the IAM role for EFS access

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
if [ $# -lt 2 ]; then
    print_error "Usage: $0 <cluster-name> <role-arn> [namespace] [service-account-name] [region]"
    print_error "Example: $0 my-eks-cluster arn:aws:iam::123456789012:role/EKSPodIdentityEFSRole default efs-pod-identity-sa us-west-2"
    exit 1
fi

CLUSTER_NAME=$1
ROLE_ARN=$2
NAMESPACE=${3:-default}
SERVICE_ACCOUNT_NAME=${4:-efs-pod-identity-sa}
REGION=${5:-us-west-2}

print_status "Creating Pod Identity Association"
print_status "Cluster: $CLUSTER_NAME"
print_status "Role ARN: $ROLE_ARN"
print_status "Namespace: $NAMESPACE"
print_status "Service Account: $SERVICE_ACCOUNT_NAME"
print_status "Region: $REGION"

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

# Create namespace if it doesn't exist
if [ "$NAMESPACE" != "default" ]; then
    print_status "Creating namespace if it doesn't exist: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
fi

# Check if service account exists
print_status "Checking if service account exists..."
if ! kubectl get serviceaccount "$SERVICE_ACCOUNT_NAME" -n "$NAMESPACE" &> /dev/null; then
    print_status "Service account doesn't exist. Creating it..."
    kubectl create serviceaccount "$SERVICE_ACCOUNT_NAME" -n "$NAMESPACE"
    kubectl annotate serviceaccount "$SERVICE_ACCOUNT_NAME" -n "$NAMESPACE" eks.amazonaws.com/pod-identity-association="true"
else
    print_status "Service account already exists"
fi

# Check if pod identity association already exists
print_status "Checking for existing pod identity associations..."
EXISTING_ASSOCIATIONS=$(aws eks list-pod-identity-associations --cluster-name "$CLUSTER_NAME" --region "$REGION" --query "associations[?namespace=='$NAMESPACE' && serviceAccount=='$SERVICE_ACCOUNT_NAME'].associationId" --output text)

if [ -n "$EXISTING_ASSOCIATIONS" ]; then
    print_warning "Pod identity association already exists:"
    for ASSOC_ID in $EXISTING_ASSOCIATIONS; do
        print_status "Association ID: $ASSOC_ID"
        aws eks describe-pod-identity-association --cluster-name "$CLUSTER_NAME" --association-id "$ASSOC_ID" --region "$REGION" --query "association.{Namespace:namespace,ServiceAccount:serviceAccount,RoleArn:roleArn}" --output table
    done
    
    read -p "Do you want to create a new association anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Skipping association creation"
        exit 0
    fi
fi

# Create the pod identity association
print_status "Creating pod identity association..."
ASSOCIATION_ID=$(aws eks create-pod-identity-association \
    --cluster-name "$CLUSTER_NAME" \
    --namespace "$NAMESPACE" \
    --service-account "$SERVICE_ACCOUNT_NAME" \
    --role-arn "$ROLE_ARN" \
    --region "$REGION" \
    --query 'association.associationId' \
    --output text)

print_status "Pod identity association created successfully!"
print_status "Association ID: $ASSOCIATION_ID"

# Wait for the association to become active
print_status "Waiting for association to become active..."
sleep 5

# Verify the association
print_status "Verifying the association..."
aws eks describe-pod-identity-association \
    --cluster-name "$CLUSTER_NAME" \
    --association-id "$ASSOCIATION_ID" \
    --region "$REGION" \
    --query "association.{Namespace:namespace,ServiceAccount:serviceAccount,RoleArn:roleArn,Status:status}" \
    --output table

print_status "Pod identity association setup completed successfully!"
print_status ""
print_status "Next steps:"
print_status "1. Deploy the EFS CSI driver if not already installed"
print_status "2. Create EFS file system and access points if needed"
print_status "3. Create PersistentVolume and PersistentVolumeClaim for EFS"
print_status "4. Deploy your application using the service account: $SERVICE_ACCOUNT_NAME"
print_status ""
print_status "The service account '$SERVICE_ACCOUNT_NAME' in namespace '$NAMESPACE' is now associated with IAM role:"
print_status "$ROLE_ARN"