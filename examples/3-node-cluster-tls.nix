# 3-Node Redpanda Cluster with TLS Encryption (PRODUCTION)
# ============================================================
# COMPLIANCE: STIG SC-8, CJIS 5.10, FedRAMP High, SOC 2 CC6.7
# This is the RECOMMENDED configuration for production deployments
#
# TLS Requirements:
# - STIG SC-8: Transmission confidentiality for all network services
# - CJIS 5.10: FIPS-validated TLS 1.2+ for data in transit
# - FedRAMP: Encryption of data in transit
# - SOC 2: Encryption for sensitive data transmission
#
# Prerequisites:
# 1. Generate TLS certificates (see below)
# 2. Deploy identical configuration to all 3 nodes
# 3. Set hostname to match node name (broker1, broker2, broker3)

{ config, lib, pkgs, ... }:

{
  services.redpanda = {
    enable = true;
    openFirewall = true;
    enforceTLS = true;  # Validates TLS configuration at build time
    cjisAuditRetention = true;  # 365-day audit retention (CJIS 5.4)

    cluster.nodes = {
      broker1 = {
        seed = true;
        rpcAddress = "192.168.1.10:33145";
        kafkaAddress = "broker1.example.com:9092";
        rack = "us-west-2a";
      };

      broker2 = {
        seed = true;
        rpcAddress = "192.168.1.11:33145";
        kafkaAddress = "broker2.example.com:9092";
        rack = "us-west-2b";
      };

      broker3 = {
        seed = true;
        rpcAddress = "192.168.1.12:33145";
        kafkaAddress = "broker3.example.com:9092";
        rack = "us-west-2c";
      };
    };

    settings = {
      redpanda = {
        data_directory = "/var/lib/redpanda";
        developer_mode = false;

        # Kafka API with TLS
        kafka_api = [{
          address = "0.0.0.0";
          port = 9092;
        }];

        kafka_api_tls = [{
          name = "external";
          enabled = true;
          key_file = "/etc/redpanda/certs/tls.key";
          cert_file = "/etc/redpanda/certs/tls.crt";
          truststore_file = "/etc/redpanda/certs/ca.crt";
          require_client_auth = false;
        }];

        # Admin API with TLS
        admin = [{
          address = "0.0.0.0";
          port = 9644;
        }];

        admin_api_tls = [{
          enabled = true;
          key_file = "/etc/redpanda/certs/tls.key";
          cert_file = "/etc/redpanda/certs/tls.crt";
          truststore_file = "/etc/redpanda/certs/ca.crt";
        }];

        # RPC Server with TLS (internal cluster communication)
        rpc_server = {
          address = "0.0.0.0";
          port = 33145;
        };

        rpc_server_tls = {
          enabled = true;
          key_file = "/etc/redpanda/certs/tls.key";
          cert_file = "/etc/redpanda/certs/tls.crt";
          truststore_file = "/etc/redpanda/certs/ca.crt";
          require_client_auth = false;
        };
      };

      # Schema Registry with TLS
      schema_registry = {
        schema_registry_api = [{
          address = "0.0.0.0";
          port = 8081;
        }];

        schema_registry_api_tls = [{
          enabled = true;
          key_file = "/etc/redpanda/certs/tls.key";
          cert_file = "/etc/redpanda/certs/tls.crt";
          truststore_file = "/etc/redpanda/certs/ca.crt";
        }];
      };

      # HTTP Proxy with TLS
      pandaproxy = {
        pandaproxy_api = [{
          address = "0.0.0.0";
          port = 8082;
        }];

        pandaproxy_api_tls = [{
          enabled = true;
          key_file = "/etc/redpanda/certs/tls.key";
          cert_file = "/etc/redpanda/certs/tls.crt";
          truststore_file = "/etc/redpanda/certs/ca.crt";
        }];
      };
    };
  };

  # TLS Certificate Setup Instructions:
  # ===================================
  #
  # 1. Generate self-signed certificate (development):
  #    mkdir -p /etc/redpanda/certs
  #    openssl req -x509 -newkey rsa:4096 -nodes \
  #      -keyout /etc/redpanda/certs/tls.key \
  #      -out /etc/redpanda/certs/tls.crt \
  #      -days 365 -subj "/CN=broker1.example.com"
  #    cp /etc/redpanda/certs/tls.crt /etc/redpanda/certs/ca.crt
  #
  # 2. Production certificates (recommended):
  #    - Use Let's Encrypt, HashiCorp Vault, or your PKI
  #    - Deploy via NixOS secret management (agenix, sops-nix)
  #    - Rotate certificates every 90 days
  #
  # 3. FIPS compliance (CJIS requirement):
  #    - Use FIPS-validated OpenSSL
  #    - See: REDPANDA_FIPS_NIXOS.md for FIPS configuration
  #
  # Compliance Achieved with TLS:
  # - STIG SC-8: ✓ Transmission Confidentiality
  # - CJIS 5.10: ✓ Encryption (with FIPS mode)
  # - FedRAMP High: ✓ Data in Transit Encryption
  # - SOC 2 CC6.7: ✓ Encryption Controls
  # - NIST 800-161: ✓ Supply Chain Data Protection
}
