# 3-Node Redpanda Cluster Configuration (DEVELOPMENT/TESTING ONLY)
# ===================================================================
# ⚠️  WARNING: NO TLS ENCRYPTION - NOT COMPLIANT FOR PRODUCTION
#
# This configuration is for:
# - Development clusters
# - Testing multi-node setups
# - Internal networks with VPN/IPsec encryption
#
# ❌ COMPLIANCE STATUS WITHOUT TLS:
# - STIG SC-8: ❌ FAILS (requires TLS for network services)
# - CJIS 5.10: ❌ FAILS (requires FIPS-validated TLS 1.2+)
# - FedRAMP High: ❌ FAILS (requires encryption in transit)
# - SOC 2 CC6.7: ❌ FAILS (requires encryption for sensitive data)
#
# ✅ FOR PRODUCTION: Use examples/3-node-cluster-tls.nix instead
#
# Deployment:
# - This configuration should be identical on all 3 nodes
# - Each node automatically discovers which broker it is based on hostname
# - Set hostname to: broker1, broker2, or broker3
# ===================================================================

{ config, lib, pkgs, ... }:

{
  services.redpanda = {
    enable = true;
    openFirewall = true;

    # The nodeName will match the hostname of each machine
    # Ensure each machine has a hostname matching one of the keys below:
    # - broker1.example.com → nodeName = "broker1"
    # - broker2.example.com → nodeName = "broker2"
    # - broker3.example.com → nodeName = "broker3"

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

        # RPC Server (internal cluster communication)
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

      # HTTP Proxy (PandaProxy)
      pandaproxy = {
        pandaproxy_api = [{
          address = "0.0.0.0";
          port = 8082;
        }];
      };
    };
  };
}
