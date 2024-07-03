#!/bin/bash

# Check if profile was passed as an argument
if [ -z "$1" ]; then
    echo "Uso: $0 <aws-profile>"
    exit 1
fi

# Define AWS CLI profile
AWS_PROFILE=$1

# Clusters that should not be deleted (add the clusters you want to keep here)
EXCLUDED_CLUSTERS=("cluster-arn-1" "cluster-arn-2")

# Function to check if a cluster is on the exclusion list
is_excluded() {
    local cluster=$1
    for excluded in "${EXCLUDED_CLUSTERS[@]}"; do
        if [ "$cluster" == "$excluded" ]; then
            return 0
        fi
    done
    return 1
}

# List all AWS regions
regions=$(aws ec2 describe-regions --profile $AWS_PROFILE --query 'Regions[*].RegionName' --output text)

# Iterate over each region
for region in $regions; do
    echo "Processing region: $region"
    
    # List all cluster in region
    clusters=$(aws ecs list-clusters --profile $AWS_PROFILE --region $region --query 'clusterArns' --output text)
    
    # Iterate over each cluster
    for cluster in $clusters; do
        # Check if the cluster is on the exclusion list
        if is_excluded "$cluster"; then
            echo "Skipping excluded cluster: $cluster"
            continue
        fi
        
        echo "Processing cluster: $cluster"
        
        # List all services in the cluster
        services=$(aws ecs list-services --cluster $cluster --profile $AWS_PROFILE --region $region --query 'serviceArns' --output text)
        
        # Itere over each service in the cluster
        for service in $services; do
            echo "Updating service: $service"
            
            # Update the number of desired tasks to 0
            aws ecs update-service --cluster $cluster --service $service --desired-count 0 --profile $AWS_PROFILE --region $region > /dev/null 2>&1
            
            # Wait until the number of active tasks is 0
            aws ecs wait services-stable --cluster $cluster --services $service --profile $AWS_PROFILE --region $region > /dev/null 2>&1
        done
        
        # List all tasks running on the cluster
        tasks=$(aws ecs list-tasks --cluster $cluster --profile $AWS_PROFILE --region $region --query 'taskArns' --output text)
        
        # Check for running tasks and wait for them to complete
        if [ -n "$tasks" ]; then
            echo "Waiting for tasks to stop in cluster: $cluster"
            aws ecs wait tasks-stopped --cluster $cluster --tasks $tasks --profile $AWS_PROFILE --region $region > /dev/null 2>&1
        fi

        # Delete services (optional if you want to clear all services before deleting the cluster)
        for service in $services; do
            echo "Deleting service: $service"
            aws ecs delete-service --cluster $cluster --service $service --force --profile $AWS_PROFILE --region $region > /dev/null 2>&1
        done
        
        # Finaly, delete the cluster
        echo "Deleting cluster: $cluster"
        aws ecs delete-cluster --cluster $cluster --profile $AWS_PROFILE --region $region > /dev/null 2>&1
    done
done

echo "All clusters and their services have been deleted in all regions, excluding specified clusters."
