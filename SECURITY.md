# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| main    | :white_check_mark: |

## Reporting a Vulnerability

**Please do not open public GitHub issues for security vulnerabilities.**

Security issues should be reported privately to allow for responsible disclosure and remediation.

### How to Report

1. **GitHub Security Advisories (Preferred):** Use the [GitHub Security Advisory](../../security/advisories/new) feature to report vulnerabilities privately.

2. **Email:** Contact the maintainers at `security@example.com` (replace with actual contact).

### What to Include in Your Report

- Description of the vulnerability
- Steps to reproduce the issue
- Affected versions or components
- Potential impact assessment
- Any suggested remediation (optional)

### Response Timeline

- **Initial Response:** Within 72 hours of receipt
- **Status Update:** Within 7 days with assessment and remediation plan
- **Resolution:** Dependent on severity and complexity

We appreciate your efforts to responsibly disclose security concerns.

## Security Considerations for Lab Use

> **DISCLAIMER:** This is an **EDUCATIONAL LAB ENVIRONMENT** and is **NOT production-ready**. The configurations, credentials, and architecture are intentionally simplified for learning purposes.

### Known Security Limitations

This lab environment has the following intentional security limitations:

| Limitation | Description |
| ---------- | ----------- |
| **Vagrant Insecure Key** | Uses Vagrant's default insecure SSH key for ease of provisioning |
| **Simple Lab Passwords** | Passwords are intentionally simple and documented for educational purposes |
| **Unencrypted Services** | Services may run without TLS/SSL encryption |
| **Flat Network Architecture** | No network segmentation between lab components |
| **Default Configurations** | Many services use default or minimal security configurations |

### DO NOT Use This Lab For

- Production workloads
- Internet-facing deployments
- Processing real or sensitive data
- Storing personal identifiable information (PII)
- Compliance-regulated environments (HIPAA, PCI-DSS, SOC2, etc.)
- Any system connected to untrusted networks

## For Production, Add

If adapting any concepts from this lab for production use, implement the following security hardening measures:

### Authentication & Access Control
- [ ] Generate unique SSH keys per host and user
- [ ] Implement strong, randomly-generated passwords
- [ ] Enable password rotation policies
- [ ] Configure multi-factor authentication (MFA)
- [ ] Implement least-privilege access controls

### Encryption & Network Security
- [ ] Enable TLS/SSL for all services and communications
- [ ] Implement proper certificate management
- [ ] Configure network segmentation and firewalls
- [ ] Use VPNs or private networks for management traffic
- [ ] Enable encryption at rest for sensitive data

### Monitoring & Compliance
- [ ] Deploy SIEM solution for centralized logging
- [ ] Configure audit logging on all systems
- [ ] Implement intrusion detection/prevention systems (IDS/IPS)
- [ ] Establish vulnerability scanning and patch management
- [ ] Create and test incident response procedures

### Infrastructure Hardening
- [ ] Remove or disable unnecessary services
- [ ] Apply CIS benchmarks or STIG hardening guides
- [ ] Implement configuration management with security baselines
- [ ] Enable SELinux/AppArmor in enforcing mode
- [ ] Configure automated security updates

---

*This security policy applies to the educational lab environment in this repository.*
