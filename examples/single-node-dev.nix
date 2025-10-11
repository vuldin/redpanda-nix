# Single-Node Redpanda Configuration (DEVELOPMENT/TESTING ONLY)
# ==============================================================
# ⚠️  WARNING: NO TLS ENCRYPTION - NOT COMPLIANT FOR PRODUCTION
#
# This configuration is for:
# - Local development
# - Testing and demos
# - Learning Redpanda basics
#
# ❌ COMPLIANCE STATUS WITHOUT TLS:
# - STIG SC-8: ❌ FAILS (requires TLS)
# - CJIS 5.10: ❌ FAILS (requires FIPS TLS 1.2+)
# - FedRAMP High: ❌ FAILS (requires encryption in transit)
# - SOC 2 CC6.7: ❌ FAILS (requires encryption for sensitive data)
#
# ✅ FOR PRODUCTION: Use examples/3-node-cluster-tls.nix instead
#
# ============================================================

{ config, lib, pkgs, ... }:

{
  services.redpanda = {
    enable = true;
    openFirewall = true;

    settings = {
      redpanda = {
        data_directory = "/var/lib/redpanda";
        node_id = 0;
        developer_mode = true;  # Disable for production

        # Kafka API
        kafka_api = [{
          address = "0.0.0.0";
          port = 9092;
        }];

        # Admin API
        admin = [{
          address = "0.0.0.0";
          port = 9644;
        }];

        # RPC Server
        rpc_server = {
          address = "0.0.0.0";
          port = 33145;
        };
      };

      # Schema Registry
      schema_registry = {
        schema_registry_api = [{
          address = "0.0.0.0";
          port = 8081;
        }];
      };

      # HTTP Proxy
      pandaproxy = {
        pandaproxy_api = [{
          address = "0.0.0.0";
          port = 8082;
        }];
      };
    };
  };
}
