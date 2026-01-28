# Terraform Module Tests

This directory contains [Terratest](https://terratest.gruntwork.io/) tests for validating Terraform modules.

## Overview

Terratest is a Go library that provides patterns and helper functions for testing infrastructure code. These tests deploy real infrastructure in AWS, validate it works correctly, and then destroy it.

## Prerequisites

1. **Go 1.21+** - Install from [golang.org](https://golang.org/dl/)

2. **Terraform** - Install from [terraform.io](https://www.terraform.io/downloads)

3. **AWS Credentials** - Configure via one of these methods:
   - Environment variables: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
   - AWS CLI profile: `aws configure`
   - IAM role (when running on EC2/ECS)

4. **AWS Permissions** - The credentials must have permissions to:
   - Create/delete VPCs
   - Create/delete subnets
   - Create/delete Internet Gateways
   - Create/delete NAT Gateways
   - Create/delete Elastic IPs
   - Create/delete Route Tables

## Running Tests

### Install Dependencies

First, download the required Go modules:

```bash
cd terraform/test
go mod download
```

If this is your first time running, you may also need to tidy the dependencies:

```bash
go mod tidy
```

### Run All Tests

```bash
go test -v -timeout 30m
```

The `-timeout 30m` flag is important because infrastructure tests can take several minutes to complete (NAT Gateways alone can take 2-3 minutes to provision).

### Run a Specific Test

```bash
go test -v -timeout 30m -run TestVPCModule
```

### Run Tests with Verbose Terraform Output

```bash
TF_LOG=DEBUG go test -v -timeout 30m
```

## Test Files

| File | Description |
|------|-------------|
| `vpc_test.go` | Tests for the VPC module - validates VPC, subnets, and gateways are created |

## Writing New Tests

When adding new tests, follow these patterns:

1. **Use unique names** - Include random suffixes or test-specific prefixes to avoid conflicts
2. **Always defer destroy** - Ensure resources are cleaned up even if tests fail
3. **Use `t.Parallel()`** - Enable parallel execution where possible
4. **Set appropriate timeouts** - Infrastructure provisioning takes time

Example test structure:

```go
func TestMyModule(t *testing.T) {
    t.Parallel()

    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../modules/my-module",
        Vars: map[string]interface{}{
            "variable_name": "value",
        },
    })

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    // Validate outputs
    output := terraform.Output(t, terraformOptions, "output_name")
    assert.NotEmpty(t, output)
}
```

## Cost Considerations

These tests create real AWS resources which incur costs. To minimize costs:

- Tests automatically destroy resources after completion
- If a test is interrupted, manually check for orphaned resources in AWS
- Use the AWS Cost Explorer to monitor test-related charges
- Consider running tests in a dedicated AWS account with billing alerts

## Troubleshooting

### Test Timeout

If tests timeout, increase the timeout value:

```bash
go test -v -timeout 60m
```

### Resources Not Destroyed

If a test fails mid-execution, resources may be left behind. Check the AWS Console for:

- VPCs with names containing "terratest"
- Elastic IPs not attached to instances
- NAT Gateways in "available" state

Clean up manually or run:

```bash
cd ../modules/vpc
terraform destroy
```

### Authentication Errors

Verify AWS credentials are configured:

```bash
aws sts get-caller-identity
```

### Module Not Found

Ensure you're running tests from the correct directory:

```bash
cd /path/to/terraform/test
go test -v -timeout 30m
```
