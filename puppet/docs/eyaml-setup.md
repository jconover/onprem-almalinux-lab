# Hiera-eyaml Setup Guide

## What is Hiera-eyaml?

Hiera-eyaml is a Hiera backend that provides per-value encryption for sensitive data. Unlike encrypting entire files, eyaml allows you to encrypt individual values within YAML files while keeping the structure and non-sensitive data readable.

### Why Use Hiera-eyaml?

- **Selective encryption**: Only sensitive values are encrypted, making files easier to review and manage
- **Version control friendly**: Encrypted files can be safely committed to Git
- **Auditable**: You can see what keys exist and their structure without accessing the actual secrets
- **Separation of concerns**: Developers can work with configuration structure while only authorized personnel have decryption keys
- **Puppet integration**: Native support in Puppet's Hiera lookup system

## Installation

Install the hiera-eyaml gem on your Puppet server and any workstation that needs to encrypt/decrypt values:

```bash
# On the Puppet server (as root)
/opt/puppetlabs/puppet/bin/gem install hiera-eyaml

# Or using puppetserver gem command
puppetserver gem install hiera-eyaml

# On workstations
gem install hiera-eyaml
```

Verify the installation:

```bash
eyaml version
```

## Key Generation

Generate a new keypair for encrypting and decrypting values:

```bash
# Create the keys directory
mkdir -p /etc/puppetlabs/puppet/eyaml

# Generate keys
cd /etc/puppetlabs/puppet/eyaml
eyaml createkeys
```

This creates two files:
- `private_key.pkcs7.pem` - Used for decryption (keep this secure!)
- `public_key.pkcs7.pem` - Used for encryption (can be shared)

## Key Storage Best Practices

### On the Puppet Server

```bash
# Set proper ownership and permissions
chown -R puppet:puppet /etc/puppetlabs/puppet/eyaml
chmod 500 /etc/puppetlabs/puppet/eyaml
chmod 400 /etc/puppetlabs/puppet/eyaml/private_key.pkcs7.pem
chmod 444 /etc/puppetlabs/puppet/eyaml/public_key.pkcs7.pem
```

### Key Distribution Strategy

1. **Private key**: Only on the Puppet server and secure backup locations
   - Never commit to version control
   - Use encrypted backup systems
   - Consider using a secrets manager for key storage

2. **Public key**: Can be distributed to developers who need to add encrypted values
   - Safe to commit to version control if desired
   - Include in developer onboarding packages

### Recommended Directory Structure

```
/etc/puppetlabs/puppet/
  eyaml/
    private_key.pkcs7.pem  # Mode 400, only readable by puppet user
    public_key.pkcs7.pem   # Mode 444, readable by all
```

## Encrypting Values

### Command Line Encryption

```bash
# Encrypt a string value
eyaml encrypt -s 'my_secret_password'

# Encrypt from stdin (useful for passwords with special characters)
echo -n 'my_secret_password' | eyaml encrypt --stdin

# Encrypt using specific keys
eyaml encrypt -s 'secret' \
  --pkcs7-public-key=/etc/puppetlabs/puppet/eyaml/public_key.pkcs7.pem
```

The output will look like:

```
string: ENC[PKCS7,MIIBiQYJKoZIhvcNAQcDoIIBejCCAXYCAQAxggE...]
```

### Block Format vs String Format

For multiline values or readability, use block format:

```yaml
# String format (single line)
password: ENC[PKCS7,MIIBiQYJKoZI...]

# Block format (multiple lines)
password: >
  ENC[PKCS7,MIIBiQYJKoZIhvcNAQcDoIIBejCCAXYCAQAxggEhMIIB
  HQIBADANBgkqhkiG9w0BAQEFAASCAQBxxxxx...]
```

## Decrypting Values

### Command Line Decryption

```bash
# Decrypt an encrypted string
eyaml decrypt -s 'ENC[PKCS7,MIIBiQYJKoZI...]'

# Decrypt using specific keys
eyaml decrypt -s 'ENC[PKCS7,...]' \
  --pkcs7-private-key=/etc/puppetlabs/puppet/eyaml/private_key.pkcs7.pem
```

### Decrypting Entire Files

```bash
# Show decrypted contents of a file
eyaml decrypt -f secrets.eyaml

# Decrypt to a specific output file (be careful with this!)
eyaml decrypt -f secrets.eyaml -o secrets.yaml
```

## Editing Encrypted Files

The `eyaml edit` command provides an interactive way to edit encrypted files:

```bash
# Open encrypted file in editor
eyaml edit secrets.eyaml

# Use a specific editor
EDITOR=vim eyaml edit secrets.eyaml
```

When editing:
1. Encrypted values are shown in decrypted form with special markers
2. You can modify existing values or add new ones
3. Mark new values for encryption using `DEC::PKCS7[value]!`
4. Upon saving, marked values are automatically encrypted

### Example Edit Session

Original file shows:
```yaml
database_password: DEC::PKCS7[actual_password_here]!
```

After saving, it becomes:
```yaml
database_password: ENC[PKCS7,MIIBiQYJKoZI...]
```

## Integration with Puppet Server

### Hiera Configuration

Add the eyaml backend to your `hiera.yaml`:

```yaml
---
version: 5
defaults:
  datadir: data
  data_hash: yaml_data

hierarchy:
  - name: "Encrypted secrets"
    lookup_key: eyaml_lookup_key
    path: "secrets.eyaml"
    options:
      pkcs7_private_key: /etc/puppetlabs/puppet/eyaml/private_key.pkcs7.pem
      pkcs7_public_key: /etc/puppetlabs/puppet/eyaml/public_key.pkcs7.pem

  - name: "Per-node data"
    path: "nodes/%{trusted.certname}.yaml"

  - name: "Common data"
    path: "common.yaml"
```

### Puppet Server Configuration

Ensure the eyaml gem is available to the Puppet server:

```bash
# Install for puppetserver
puppetserver gem install hiera-eyaml

# Restart puppetserver to load the gem
systemctl restart puppetserver
```

### Using Encrypted Values in Manifests

Once configured, use encrypted values like any other Hiera data:

```puppet
# In your manifest
$db_password = lookup('database_password')

# Or using automatic parameter lookup
class myapp (
  String $database_password,
) {
  # $database_password is automatically decrypted
}
```

## Troubleshooting

### Common Issues

1. **"No such file or directory" for keys**
   - Verify key paths in hiera.yaml
   - Check file permissions

2. **"Permission denied" errors**
   - Ensure the puppet user can read the private key
   - Check directory permissions on /etc/puppetlabs/puppet/eyaml

3. **Values not decrypting**
   - Verify the eyaml gem is installed for puppetserver
   - Check that the hierarchy level uses `lookup_key: eyaml_lookup_key`
   - Restart puppetserver after configuration changes

### Testing Your Setup

```bash
# Test encryption/decryption roundtrip
original="test_secret"
encrypted=$(eyaml encrypt -s "$original" -o string)
decrypted=$(eyaml decrypt -s "$encrypted")

if [ "$original" = "$decrypted" ]; then
  echo "Encryption/decryption working correctly"
fi

# Test Puppet lookup
puppet lookup database_password --explain
```

## Security Considerations

1. **Key rotation**: Plan for periodic key rotation
2. **Backup keys securely**: Use encrypted backups or a secrets manager
3. **Audit access**: Monitor who has access to the private key
4. **Separate environments**: Consider separate keypairs for production/staging
5. **Git history**: If you accidentally commit unencrypted secrets, they remain in Git history
