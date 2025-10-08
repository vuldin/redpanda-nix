{
  description = "Redpanda - A streaming data platform for developers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        redpanda = pkgs.callPackage ./default.nix { };
      in
      {
        packages = {
          default = redpanda;
          redpanda = redpanda;
        };

        apps = {
          default = {
            type = "app";
            program = "${redpanda}/bin/redpanda";
          };

          rpk = {
            type = "app";
            program = "${redpanda}/bin/rpk";
          };

          update = {
            type = "app";
            program = toString (pkgs.writeShellScript "update-redpanda" ''
              ${./update.sh} "$@"
            '');
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            redpanda
            curl
            jq
          ];
        };
      }
    ) // {
      # NixOS module
      nixosModules.default = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.services.redpanda;
          redpandaPkg = pkgs.callPackage ./default.nix { };


          # Function to extract port from listener configuration
          # Handles both object format {address: "...", port: 1234} and simple port numbers
          extractPort = listener:
            if builtins.isAttrs listener then
              listener.port or null
            else if builtins.isInt listener then
              listener
            else
              null;

          # Extract all ports from various listener configurations
          extractPorts = settings:
            let
              redpandaCfg = settings.redpanda or {};

              # Extract Kafka API ports (can be list of listeners)
              kafkaPorts =
                if redpandaCfg ? kafka_api then
                  map extractPort (if builtins.isList redpandaCfg.kafka_api
                                   then redpandaCfg.kafka_api
                                   else [ redpandaCfg.kafka_api ])
                else [];

              # Extract Admin API ports (can be list of listeners)
              adminPorts =
                if redpandaCfg ? admin then
                  map extractPort (if builtins.isList redpandaCfg.admin
                                   then redpandaCfg.admin
                                   else [ redpandaCfg.admin ])
                else [];

              # Extract RPC server port
              rpcPorts =
                if redpandaCfg ? rpc_server then
                  [ (extractPort redpandaCfg.rpc_server) ]
                else [];

              # Extract Schema Registry ports
              schemaRegistryPorts =
                if settings ? schema_registry && settings.schema_registry ? schema_registry_api then
                  map extractPort (if builtins.isList settings.schema_registry.schema_registry_api
                                   then settings.schema_registry.schema_registry_api
                                   else [ settings.schema_registry.schema_registry_api ])
                else [];

              # Extract HTTP Proxy (PandaProxy) ports
              pandaproxyPorts =
                if settings ? pandaproxy && settings.pandaproxy ? pandaproxy_api then
                  map extractPort (if builtins.isList settings.pandaproxy.pandaproxy_api
                                   then settings.pandaproxy.pandaproxy_api
                                   else [ settings.pandaproxy.pandaproxy_api ])
                else [];

              allPorts = kafkaPorts ++ adminPorts ++ rpcPorts ++ schemaRegistryPorts ++ pandaproxyPorts;
            in
              # Filter out nulls and ensure unique ports
              lib.unique (builtins.filter (p: p != null) allPorts);

          # Determine node name (explicit nodeName or hostname)
          nodeName = if cfg.nodeName != null then cfg.nodeName else config.networking.hostName;

          # Generate seed servers from cluster.nodes configuration
          seedServers =
            if cfg.cluster.nodes != {} then
              map (name:
                let node = cfg.cluster.nodes.${name};
                in { host.address = node.rpcAddress; }
              ) (filter (name: cfg.cluster.nodes.${name}.seed) (attrNames cfg.cluster.nodes))
            else [];

          # Get current node's configuration from cluster.nodes
          currentNode =
            if cfg.cluster.nodes != {} && hasAttr nodeName cfg.cluster.nodes
            then cfg.cluster.nodes.${nodeName}
            else null;

          # Merge user settings with auto-generated cluster settings
          finalSettings = lib.recursiveUpdate cfg.settings (
            if currentNode != null then {
              redpanda = {
                # Auto-populate seed_servers from cluster configuration
                seed_servers = mkIf (seedServers != []) seedServers;

                # Auto-populate advertised_rpc_api if configured in cluster.nodes
                advertised_rpc_api = mkIf (currentNode.rpcAddress != null) {
                  address = lib.head (lib.splitString ":" currentNode.rpcAddress);
                  port = lib.toInt (lib.last (lib.splitString ":" currentNode.rpcAddress));
                };

                # Auto-populate advertised_kafka_api if configured in cluster.nodes
                advertised_kafka_api = mkIf (currentNode.kafkaAddress != null) [{
                  address = lib.head (lib.splitString ":" currentNode.kafkaAddress);
                  port = lib.toInt (lib.last (lib.splitString ":" currentNode.kafkaAddress));
                }];

                # Set rack awareness if configured
                rack = mkIf (currentNode.rack != null) currentNode.rack;
              };
            } else {}
          );

          configFile = pkgs.writeText "redpanda.yaml" (builtins.toJSON finalSettings);

          # Extract firewall ports from final merged settings
          firewallPorts = extractPorts finalSettings;

        in
        {
          options.services.redpanda = {
            enable = mkEnableOption "Redpanda streaming data platform";

            package = mkOption {
              type = types.package;
              default = redpandaPkg;
              description = "The Redpanda package to use";
            };

            nodeName = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Node name used to identify this broker in the cluster.
                If not specified, the system hostname will be used.
                This must match a key in cluster.nodes if cluster configuration is used.
              '';
              example = "broker1";
            };

            dataDir = mkOption {
              type = types.str;
              default = "/var/lib/redpanda";
              description = "Directory where Redpanda stores its data";
            };

            user = mkOption {
              type = types.str;
              default = "redpanda";
              description = "User account under which Redpanda runs";
            };

            group = mkOption {
              type = types.str;
              default = "redpanda";
              description = "Group account under which Redpanda runs";
            };

            cluster = mkOption {
              default = {};
              description = ''
                Cluster topology configuration. When configured, seed servers
                and advertised addresses are automatically generated.

                Each machine in the cluster should have the same cluster.nodes
                configuration, and will automatically discover which node it is
                based on nodeName (or hostname).
              '';
              type = types.submodule {
                options = {
                  nodes = mkOption {
                    type = types.attrsOf (types.submodule {
                      options = {
                        seed = mkOption {
                          type = types.bool;
                          default = true;
                          description = "Whether this node is a seed server";
                        };

                        rpcAddress = mkOption {
                          type = types.str;
                          description = ''
                            RPC address for internal cluster communication.
                            Format: "host:port" or "ip:port"
                          '';
                          example = "192.168.1.10:33145";
                        };

                        kafkaAddress = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                          description = ''
                            Advertised Kafka API address for client connections.
                            Format: "host:port" or "ip:port"
                            If not specified, clients use the kafka_api listener address.
                          '';
                          example = "broker1.example.com:9092";
                        };

                        rack = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                          description = ''
                            Rack ID for rack awareness (stretch clusters).
                            Used for replica placement across availability zones or datacenters.
                          '';
                          example = "us-west-2a";
                        };
                      };
                    });
                    default = {};
                    description = "Cluster node definitions indexed by node name";
                    example = {
                      broker1 = {
                        seed = true;
                        rpcAddress = "192.168.1.10:33145";
                        kafkaAddress = "broker1.example.com:9092";
                        rack = "dc1-az1";
                      };
                    };
                  };
                };
              };
            };

            settings = mkOption {
              type = types.attrs;
              default = {
                redpanda = {
                  data_directory = cfg.dataDir;
                  node_id = 0;
                  rpc_server = {
                    address = "0.0.0.0";
                    port = 33145;
                  };
                  kafka_api = [{
                    address = "0.0.0.0";
                    port = 9092;
                  }];
                  admin = [{
                    address = "0.0.0.0";
                    port = 9644;
                  }];
                  developer_mode = true;
                };
                pandaproxy = {
                  pandaproxy_api = [{
                    address = "0.0.0.0";
                    port = 8082;
                  }];
                };
                schema_registry = {
                  schema_registry_api = [{
                    address = "0.0.0.0";
                    port = 8081;
                  }];
                };
              };
              description = ''
                Redpanda configuration as a Nix attribute set.

                Ports are automatically extracted from this configuration
                and used for firewall rules when openFirewall is enabled.

                Example with multiple Kafka listeners:
                <programlisting>
                settings = {
                  redpanda = {
                    kafka_api = [
                      { address = "0.0.0.0"; port = 9092; }  # Internal
                      { address = "0.0.0.0"; port = 9093; }  # External
                    ];
                    admin = [
                      { address = "0.0.0.0"; port = 9644; }
                    ];
                    rpc_server = {
                      address = "0.0.0.0";
                      port = 33145;
                    };
                  };
                  schema_registry = {
                    schema_registry_api = [
                      { address = "0.0.0.0"; port = 8081; }
                    ];
                  };
                  pandaproxy = {
                    pandaproxy_api = [
                      { address = "0.0.0.0"; port = 8082; }
                    ];
                  };
                };
                </programlisting>
              '';
            };

            openFirewall = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Whether to automatically open firewall ports for Redpanda.

                When enabled, all ports configured in services.redpanda.settings
                will be automatically extracted and opened in the firewall.
                This includes:
                - Kafka API ports (kafka_api)
                - Admin API ports (admin)
                - RPC server port (rpc_server)
                - Schema Registry ports (schema_registry_api)
                - HTTP Proxy ports (pandaproxy_api)

                Ports are automatically discovered from your configuration,
                so you only need to configure them once in settings.
              '';
            };
          };

          config = mkIf cfg.enable {
            users.users.${cfg.user} = {
              isSystemUser = true;
              group = cfg.group;
              description = "Redpanda daemon user";
              home = cfg.dataDir;
              createHome = true;
            };

            users.groups.${cfg.group} = {};

            systemd.services.redpanda = {
              description = "Redpanda streaming data platform";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];

              serviceConfig = {
                Type = "simple";
                User = cfg.user;
                Group = cfg.group;
                ExecStart = "${cfg.package}/bin/redpanda start --config ${configFile}";
                Restart = "on-failure";
                RestartSec = "10s";

                # Security hardening
                NoNewPrivileges = true;
                PrivateTmp = true;
                ProtectSystem = "strict";
                ProtectHome = true;
                ReadWritePaths = [ cfg.dataDir ];

                # Resource limits
                LimitNOFILE = 65536;
              };
            };

            networking.firewall = mkIf cfg.openFirewall {
              allowedTCPPorts = firewallPorts;
            };

            # Add a warning if no ports were detected
            warnings = optional (cfg.openFirewall && firewallPorts == [])
              "services.redpanda.openFirewall is enabled but no ports were detected in the configuration";
          };
        };
    };
}
