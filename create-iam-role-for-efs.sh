#!/bin/bash

# Script to create IAM role and policy for EFS access with Pod Identity
# This role will be associated with a Kubernetes service account

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

# Default values
ROLE_NAME="EKSPodIdentityEFSRole"
POLICY_NAME="EKSPodIdentityEFSPolicy"
REGION="us-west-2"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --role-name)
            ROLE_NAME="$2"
            shift 2
            ;;
        --policy-name)
            POLICY_NAME="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --role-name ROLE_NAME     Name for the IAM role (default: EKSPodIdentityEFSRole)"
            echo "  --policy-name POLICY_NAME Name for the IAM policy (default: EKSPodIdentityEFSPolicy)"
            echo "  --region REGION           AWS region (default: us-west-2)"
            echo "  -h, --help               Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

print_status "Creating IAM role and policy for EFS access with Pod Identity"
print_status "Role name: $ROLE_NAME"
print_status "Policy name: $POLICY_NAME"
print_status "Region: $REGION"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
print_status "AWS Account ID: $ACCOUNT_ID"

# Create trust policy for Pod Identity
cat > /tmp/trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "pods.eks.amazonaws.com"
            },
            "Action": [
                "sts:AssumeRole",
                "sts:TagSession"
            ]
        }
    ]
}
EOF

# Create EFS access policy
cat > /tmp/efs-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "elasticfilesystem:DescribeFileSystems",
                "elasticfilesystem:DescribeMountTargets",
                "elasticfilesystem:DescribeAccessPoints",
                "elasticfilesystem:CreateAccessPoint",
                "elasticfilesystem:DeleteAccessPoint",
                "elasticfilesystem:ModifyMountTargetSecurityGroups",
                "elasticfilesystem:TagResource",
                "elasticfilesystem:UntagResource"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeSubnets",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeSecurityGroups"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Check if role already exists
if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
    print_warning "IAM role $ROLE_NAME already exists"
    ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
else
    # Create the IAM role
    print_status "Creating IAM role: $ROLE_NAME"
    ROLE_ARN=$(aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        --description "IAM role for EKS Pod Identity to access EFS" \
        --query 'Role.Arn' \
        --output text)
    
    print_status "Created IAM role: $ROLE_ARN"
fi

# Check if policy already exists
if aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}" &> /dev/null; then
    print_warning "IAM policy $POLICY_NAME already exists"
    POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
else
    # Create the IAM policy
    print_status "Creating IAM policy: $POLICY_NAME"
    POLICY_ARN=$(aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document file:///tmp/efs-policy.json \
        --description "Policy for EKS Pod Identity to access EFS" \
        --query 'Policy.Arn' \
        --output text)
    
    print_status "Created IAM policy: $POLICY_ARN"
fi

# Attach policy to role
print_status "Attaching policy to role..."
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "$POLICY_ARN"

# Also attach the AWS managed EFS CSI driver policy
print_status "Attaching AWS managed EFS CSI driver policy..."
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy" || print_warning "Failed to attach managed policy (it might not exist in this region)"

# Clean up temporary files
rm -f /tmp/trust-policy.json /tmp/efs-policy.json

print_status "IAM role and policy created successfully!"
print_status ""
print_status "Role ARN: $ROLE_ARN"
print_status "Policy ARN: $POLICY_ARN"
print_status ""
print_status "Next steps:"
print_status "1. Create a Kubernetes service account"
print_status "2. Associate this IAM role with the service account using:"
print_status "   aws eks create-pod-identity-association \\"
print_status "     --cluster-name YOUR_CLUSTER_NAME \\"
print_status "     --namespace YOUR_NAMESPACE \\"
print_status "     --service-account YOUR_SERVICE_ACCOUNT \\"
print_status "     --role-arn $ROLE_ARN"

# Save the role ARN to a file for later use
echo "$ROLE_ARN" > /tmp/efs-role-arn.txt
print_status "Role ARN saved to /tmp/efs-role-arn.txt"