// Package test contains Terratest tests for Terraform modules
//
// This file tests the VPC module to ensure it creates the expected
// AWS networking resources including VPC, subnets, and gateways.
package test

import (
	"testing"

	// Terratest provides utilities for testing infrastructure code
	"github.com/gruntwork-io/terratest/modules/terraform"

	// Testify provides assertion functions for cleaner test code
	"github.com/stretchr/testify/assert"
)

// TestVPCModule validates the VPC Terraform module creates resources correctly.
//
// This test:
// 1. Initializes and applies the VPC module with test variables
// 2. Validates that all expected outputs are populated
// 3. Cleans up by destroying all created resources
//
// Prerequisites:
// - AWS credentials configured (via environment variables or AWS CLI profile)
// - Terraform installed and available in PATH
func TestVPCModule(t *testing.T) {
	// Run tests in parallel to speed up execution when running multiple tests
	t.Parallel()

	// =========================================================================
	// Test Configuration
	// =========================================================================
	// Define test variables that will be passed to the Terraform module.
	// Using a unique environment name helps avoid conflicts when running
	// multiple tests concurrently.

	vpcCidr := "10.100.0.0/16"
	environment := "terratest"
	availabilityZones := []string{"us-east-1a", "us-east-1b"}
	publicSubnetCidrs := []string{"10.100.1.0/24", "10.100.2.0/24"}
	privateSubnetCidrs := []string{"10.100.10.0/24", "10.100.11.0/24"}

	// =========================================================================
	// Terraform Options
	// =========================================================================
	// Configure how Terratest will invoke Terraform. The TerraformDir points
	// to the module under test, and Vars contains the input variables.

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		// Path to the Terraform module being tested
		TerraformDir: "../modules/vpc",

		// Variables to pass to the Terraform module
		// These override any default values defined in the module
		Vars: map[string]interface{}{
			"vpc_cidr":             vpcCidr,
			"environment":          environment,
			"availability_zones":   availabilityZones,
			"public_subnet_cidrs":  publicSubnetCidrs,
			"private_subnet_cidrs": privateSubnetCidrs,
			"tags": map[string]string{
				"ManagedBy": "Terratest",
				"TestName":  "TestVPCModule",
			},
		},

		// Disable color output for cleaner CI/CD logs
		NoColor: true,
	})

	// =========================================================================
	// Cleanup (Deferred)
	// =========================================================================
	// Schedule terraform destroy to run at the end of the test, regardless
	// of whether the test passes or fails. This ensures we don't leave
	// orphaned resources in AWS.
	//
	// IMPORTANT: In a real test, you would always want this enabled.
	// Comment out this line only when debugging to inspect created resources.

	defer terraform.Destroy(t, terraformOptions)

	// =========================================================================
	// Initialize and Apply
	// =========================================================================
	// Run 'terraform init' and 'terraform apply' to create the infrastructure.
	// InitAndApply will fail the test if either command returns an error.

	terraform.InitAndApply(t, terraformOptions)

	// =========================================================================
	// Output Validation
	// =========================================================================
	// Retrieve outputs from the Terraform state and validate they contain
	// expected values. This confirms the module created resources successfully.

	// Validate VPC ID output
	// The VPC ID should be a non-empty string starting with "vpc-"
	vpcID := terraform.Output(t, terraformOptions, "vpc_id")
	assert.NotEmpty(t, vpcID, "VPC ID should not be empty")
	assert.Contains(t, vpcID, "vpc-", "VPC ID should contain 'vpc-' prefix")

	// Validate public subnet IDs output
	// We expect one subnet per availability zone (2 subnets in this test)
	publicSubnetIDs := terraform.OutputList(t, terraformOptions, "public_subnet_ids")
	assert.NotEmpty(t, publicSubnetIDs, "Public subnet IDs should not be empty")
	assert.Equal(t, len(availabilityZones), len(publicSubnetIDs),
		"Should have one public subnet per availability zone")

	// Validate each public subnet ID has the correct format
	for _, subnetID := range publicSubnetIDs {
		assert.Contains(t, subnetID, "subnet-",
			"Each public subnet ID should contain 'subnet-' prefix")
	}

	// Validate private subnet IDs output
	// We expect one subnet per availability zone (2 subnets in this test)
	privateSubnetIDs := terraform.OutputList(t, terraformOptions, "private_subnet_ids")
	assert.NotEmpty(t, privateSubnetIDs, "Private subnet IDs should not be empty")
	assert.Equal(t, len(availabilityZones), len(privateSubnetIDs),
		"Should have one private subnet per availability zone")

	// Validate each private subnet ID has the correct format
	for _, subnetID := range privateSubnetIDs {
		assert.Contains(t, subnetID, "subnet-",
			"Each private subnet ID should contain 'subnet-' prefix")
	}

	// Validate NAT Gateway IP output
	// The NAT Gateway should have a public IP address assigned
	natGatewayIP := terraform.Output(t, terraformOptions, "nat_gateway_ip")
	assert.NotEmpty(t, natGatewayIP, "NAT Gateway IP should not be empty")
}
