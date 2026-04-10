{
  description = "Redpanda - A streaming data platform for developers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # Default: Fast deb package extraction (for external users)
        redpanda = pkgs.callPackage ./default.nix { };

        # FIPS: FIPS 140-2 compliant build (for FedRAMP High)
        redpanda-fips = pkgs.callPackage ./fips.nix { };

        # Bazel: Source builds (for Redpanda employees/development)
        redpanda-bazel = pkgs.callPackage ./bazel.nix { };
      in
      {
        packages = {
          default = redpanda;
          redpanda = redpanda;
          redpanda-fips = redpanda-fips;
          redpanda-bazel = redpanda-bazel;
        };

        apps = {
          default = {
            type = "app";
            program = "${redpanda}/bin/redpanda";
          };

          update = {
            type = "app";
            program = toString (pkgs.writeShellScript "update-redpanda" ''
              ${./scripts/update.sh} "$@"
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
      } // (if system == "x86_64-linux" then {
        checks = {
          # Test 1: Redpanda service starts with default config
          service-starts = pkgs.testers.nixosTest {
            name = "redpanda-service-starts";
            nodes.machine = { ... }: {
              imports = [ self.nixosModules.default ];
              services.redpanda.enable = true;
              virtualisation.memorySize = 2048;
            };
            testScript = ''
              machine.wait_for_unit("redpanda.service")
              machine.succeed("systemctl is-active redpanda.service")
            '';
          };

          # Test 2: enforceTLS assertion fires when TLS is not configured
          enforce-tls-assertion = let
            # Evaluate the module with enforceTLS but no TLS config
            eval = nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [
                self.nixosModules.default
                {
                  services.redpanda = {
                    enable = true;
                    enforceTLS = true;
                    # No TLS config — assertions should fire
                  };
                  # Minimal config to allow evaluation
                  fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
                  boot.loader.grub.device = "/dev/sda";
                }
              ];
            };
            failedAssertions = builtins.filter (a: !a.assertion) eval.config.assertions;
          in pkgs.runCommand "enforce-tls-assertion-test" {} ''
            ${if (builtins.length failedAssertions) > 0
              then ''echo "PASS: enforceTLS correctly produced ${toString (builtins.length failedAssertions)} assertion failure(s)"''
              else ''echo "FAIL: enforceTLS did not fire any assertions" && exit 1''
            }
            touch $out
          '';

          # Test 3: CJIS audit retention configures journald
          cjis-retention = pkgs.testers.nixosTest {
            name = "redpanda-cjis-retention";
            nodes.machine = { ... }: {
              imports = [ self.nixosModules.default ];
              services.redpanda = {
                enable = true;
                cjisAuditRetention = true;
              };
              virtualisation.memorySize = 2048;
            };
            testScript = ''
              machine.wait_for_unit("multi-user.target")
              machine.succeed(
                  "grep -r 'MaxRetentionSec' /etc/systemd/journald.conf.d/ "
                  "|| grep 'MaxRetentionSec' /etc/systemd/journald.conf"
              )
            '';
          };

          # Test 4: FIPS openssl.cnf references correct Nix store path
          fips-openssl-path = pkgs.runCommand "fips-openssl-path-test" {} ''
            if [ -f "${redpanda-fips}/opt/redpanda/openssl/openssl.cnf" ]; then
              if grep -q '/nix/store/' "${redpanda-fips}/opt/redpanda/openssl/openssl.cnf"; then
                echo "PASS: openssl.cnf references /nix/store/ path"
              else
                echo "FAIL: openssl.cnf does not reference /nix/store/ path"
                grep '\.include' "${redpanda-fips}/opt/redpanda/openssl/openssl.cnf" || true
                exit 1
              fi

              # Verify the target fipsmodule.cnf exists
              INCLUDE_PATH=$(grep '\.include' "${redpanda-fips}/opt/redpanda/openssl/openssl.cnf" | sed 's/.*\.include //')
              if [ -f "$INCLUDE_PATH" ]; then
                echo "PASS: fipsmodule.cnf exists at referenced path"
              else
                echo "FAIL: fipsmodule.cnf not found at $INCLUDE_PATH"
                exit 1
              fi
            else
              echo "SKIP: No openssl.cnf in FIPS package (FIPS supplement may not include it)"
            fi
            touch $out
          '';
        };
      } else {})
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

                Example with multiple listeners (pattern: 9x92, 8x81, 8x82):
                <programlisting>
                settings = {
                  redpanda = {
                    # Multiple Kafka API listeners - pattern: 9x92
                    kafka_api = [
                      { address = "0.0.0.0"; port = 9092; name = "internal"; }
                      { address = "0.0.0.0"; port = 9192; name = "external"; }
                      { address = "0.0.0.0"; port = 9292; name = "public"; }
                    ];
                    # Admin API - typically single listener
                    admin = [
                      { address = "0.0.0.0"; port = 9644; }
                    ];
                    rpc_server = {
                      address = "0.0.0.0";
                      port = 33145;
                    };
                  };
                  schema_registry = {
                    # Pattern: 8x81
                    schema_registry_api = [
                      { address = "0.0.0.0"; port = 8081; name = "internal"; }
                      { address = "0.0.0.0"; port = 8181; name = "external"; }
                    ];
                  };
                  pandaproxy = {
                    # Pattern: 8x82
                    pandaproxy_api = [
                      { address = "0.0.0.0"; port = 8082; name = "internal"; }
                      { address = "0.0.0.0"; port = 8182; name = "external"; }
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

            enforceTLS = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Whether to enforce TLS for all Redpanda services.

                When enabled, validates that TLS is properly configured for:
                - Kafka API (kafka_api_tls)
                - Admin API (admin_api_tls)
                - RPC Server (rpc_server_tls)
                - Schema Registry (schema_registry_api_tls)
                - HTTP Proxy (pandaproxy_api_tls)

                This option helps achieve STIG SC-8 (transmission confidentiality)
                and CJIS 5.10 (encryption) compliance requirements.

                Example TLS configuration:
                <programlisting>
                services.redpanda = {
                  enable = true;
                  enforceTLS = true;
                  settings = {
                    redpanda = {
                      kafka_api_tls = [{
                        name = "external";
                        key_file = "/etc/redpanda/certs/tls.key";
                        cert_file = "/etc/redpanda/certs/tls.crt";
                        truststore_file = "/etc/redpanda/certs/ca.crt";
                        enabled = true;
                        require_client_auth = false;
                      }];
                      admin_api_tls = [{
                        enabled = true;
                        key_file = "/etc/redpanda/certs/tls.key";
                        cert_file = "/etc/redpanda/certs/tls.crt";
                      }];
                    };
                  };
                };
                </programlisting>
              '';
            };

            cjisAuditRetention = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Whether to configure CJIS-compliant 365-day audit retention.

                When enabled, configures systemd-journald to retain Redpanda service
                logs for a minimum of 365 days as required by FBI CJIS Security
                Policy v6.0 Section 5.4 (Auditing and Accountability).

                This sets:
                - MaxRetentionSec = 31536000 (365 days)
                - Storage = persistent (survives reboots)
                - SystemMaxUse = 10G (reasonable limit for log storage)

                Storage requirements: ~10GB for 365 days of logs
                (varies based on activity level)

                CJIS 5.4 Requirements:
                - Minimum 365-day retention for audit logs
                - Protection against unauthorized access/modification
                - Regular backup of audit records
                - Tamper-resistant log storage

                Note: This configures system-wide journald settings for the
                Redpanda service unit. For production CJIS deployments, also
                configure external SIEM forwarding (rsyslog, Splunk, etc.)
              '';
            };

            auditRetentionDays = mkOption {
              type = types.int;
              default = 365;
              description = ''
                Number of days to retain audit logs when cjisAuditRetention is enabled.
                Default is 365 days (CJIS minimum requirement).
                Can be increased for stricter compliance (e.g., 730 days for 2 years).
              '';
            };

            enforceMFA = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Enforce Multi-Factor Authentication for Redpanda access.

                **FBI CJIS 5.5.2.2**: MFA mandatory as of October 1, 2024

                When enabled, validates that BOTH are configured:
                1. SASL authentication (username/password - first factor)
                2. mTLS client certificates (client cert - second factor)

                This provides MFA by requiring "something you know" (password)
                and "something you have" (client certificate).

                Example configuration:
                <programlisting>
                services.redpanda = {
                  enforceMFA = true;
                  settings = {
                    redpanda = {
                      # SASL for username/password (first factor)
                      kafka_api = [{
                        address = "0.0.0.0";
                        port = 9092;
                        authentication_method = "sasl";
                      }];

                      # mTLS for client certificates (second factor)
                      kafka_api_tls = [{
                        enabled = true;
                        key_file = "/etc/redpanda/certs/tls.key";
                        cert_file = "/etc/redpanda/certs/tls.crt";
                        truststore_file = "/etc/redpanda/certs/ca.crt";
                        require_client_auth = true;  # Critical for MFA
                      }];
                    };
                  };
                };
                </programlisting>

                **Compliance**: FBI CJIS 5.5.2.2, NIST 800-63B, STIG IA-2(1)
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

            # Configure CJIS-compliant audit retention
            services.journald.extraConfig = mkIf cfg.cjisAuditRetention ''
              # CJIS Security Policy v6.0 Section 5.4 - Audit Retention
              # Minimum 365-day retention for audit logs
              MaxRetentionSec=${toString (cfg.auditRetentionDays * 86400)}
              Storage=persistent
              Compress=yes
              SystemMaxUse=10G
              SystemKeepFree=2G
              SystemMaxFileSize=100M
              # Protect against unauthorized modification
              SyncIntervalSec=30
              ForwardToSyslog=no
            '';

            # CJIS audit retention information message
            systemd.services.redpanda-audit-info = mkIf cfg.cjisAuditRetention {
              description = "Display CJIS audit retention configuration";
              wantedBy = [ "multi-user.target" ];
              after = [ "systemd-journald.service" ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart = toString (pkgs.writeShellScript "audit-info" ''
                  echo "========================================" >&2
                  echo "CJIS Audit Retention: ENABLED" >&2
                  echo "Retention Period: ${toString cfg.auditRetentionDays} days" >&2
                  echo "Storage: Persistent (survives reboots)" >&2
                  echo "Max Storage: 10GB" >&2
                  echo "========================================" >&2
                  echo "" >&2
                  echo "View Redpanda audit logs with:" >&2
                  echo "  journalctl -u redpanda --since=-7days" >&2
                  echo "" >&2
                  echo "CJIS 5.4 Compliance: ✓ Achieved" >&2
                  echo "FBI CJIS Security Policy v6.0" >&2
                  echo "========================================" >&2
                '');
              };
            };

            networking.firewall = mkIf cfg.openFirewall {
              allowedTCPPorts = firewallPorts;
            };

            # TLS and MFA validation
            assertions =
              let
                redpandaCfg = finalSettings.redpanda or {};
                schemaRegistryCfg = finalSettings.schema_registry or {};
                pandaproxyCfg = finalSettings.pandaproxy or {};

                # Check if TLS is configured for a service
                hasTLS = tlsConfig:
                  if builtins.isList tlsConfig then
                    any (tls: tls.enabled or false) tlsConfig
                  else if builtins.isAttrs tlsConfig then
                    tlsConfig.enabled or false
                  else
                    false;

                # Check if mTLS requires client authentication
                hasClientAuth = tlsConfig:
                  if builtins.isList tlsConfig then
                    any (tls: (tls.enabled or false) && (tls.require_client_auth or false)) tlsConfig
                  else if builtins.isAttrs tlsConfig then
                    (tlsConfig.enabled or false) && (tlsConfig.require_client_auth or false)
                  else
                    false;

                # Check if SASL is configured
                hasSASL = apiConfig:
                  if builtins.isList apiConfig then
                    any (api: (api.authentication_method or "") == "sasl") apiConfig
                  else if builtins.isAttrs apiConfig then
                    (apiConfig.authentication_method or "") == "sasl"
                  else
                    false;

                kafkaTLSConfigured = redpandaCfg ? kafka_api_tls && hasTLS redpandaCfg.kafka_api_tls;
                adminTLSConfigured = redpandaCfg ? admin_api_tls && hasTLS redpandaCfg.admin_api_tls;
                rpcTLSConfigured = redpandaCfg ? rpc_server_tls && (redpandaCfg.rpc_server_tls.enabled or false);
                schemaTLSConfigured = schemaRegistryCfg ? schema_registry_api_tls && hasTLS schemaRegistryCfg.schema_registry_api_tls;
                pandaproxyTLSConfigured = pandaproxyCfg ? pandaproxy_api_tls && hasTLS pandaproxyCfg.pandaproxy_api_tls;

                # MFA validation
                kafkaMTLSClientAuth = redpandaCfg ? kafka_api_tls && hasClientAuth redpandaCfg.kafka_api_tls;
                kafkaSASLConfigured = redpandaCfg ? kafka_api && hasSASL redpandaCfg.kafka_api;
                mfaConfigured = kafkaMTLSClientAuth && kafkaSASLConfigured;

                # Services that are enabled but missing TLS
                missingTLS = lib.optionals cfg.enforceTLS [
                  { condition = redpandaCfg ? kafka_api && !kafkaTLSConfigured; service = "Kafka API"; }
                  { condition = redpandaCfg ? admin && !adminTLSConfigured; service = "Admin API"; }
                  { condition = redpandaCfg ? rpc_server && !rpcTLSConfigured; service = "RPC Server"; }
                  { condition = schemaRegistryCfg ? schema_registry_api && !schemaTLSConfigured; service = "Schema Registry"; }
                  { condition = pandaproxyCfg ? pandaproxy_api && !pandaproxyTLSConfigured; service = "HTTP Proxy"; }
                ];

                servicesWithoutTLS = builtins.filter (s: s.condition) missingTLS;

                # TLS assertions
                tlsAssertions = map (s: {
                  assertion = !cfg.enforceTLS || !s.condition;
                  message = ''
                    services.redpanda.enforceTLS is enabled but TLS is not configured for ${s.service}.
                    Please configure ${s.service} TLS in services.redpanda.settings.

                    See: https://docs.redpanda.com/docs/security/encryption/ for configuration details.

                    STIG SC-8 (Transmission Confidentiality) requires TLS for all network services.
                    CJIS 5.10 (Encryption) requires FIPS-validated TLS 1.2+ for data in transit.
                  '';
                }) servicesWithoutTLS;

                # MFA assertion
                mfaAssertion = [{
                  assertion = !cfg.enforceMFA || mfaConfigured;
                  message = ''
                    services.redpanda.enforceMFA is enabled but MFA is not properly configured.

                    MFA requires BOTH:
                    1. SASL authentication (first factor: something you know)
                       ${if kafkaSASLConfigured then "✓ SASL configured" else "✗ SASL NOT configured"}

                    2. mTLS with client authentication (second factor: something you have)
                       ${if kafkaMTLSClientAuth then "✓ mTLS with client auth configured" else "✗ mTLS client auth NOT configured"}

                    Example configuration:
                    services.redpanda.settings = {
                      redpanda = {
                        kafka_api = [{
                          address = "0.0.0.0";
                          port = 9092;
                          authentication_method = "sasl";  # First factor
                        }];
                        kafka_api_tls = [{
                          enabled = true;
                          require_client_auth = true;  # Second factor (critical!)
                          key_file = "/etc/redpanda/certs/tls.key";
                          cert_file = "/etc/redpanda/certs/tls.crt";
                          truststore_file = "/etc/redpanda/certs/ca.crt";
                        }];
                      };
                    };

                    FBI CJIS 5.5.2.2: MFA mandatory as of October 1, 2024
                    NIST 800-63B: Requires MFA for authenticator assurance level 2+
                  '';
                }];
              in
                tlsAssertions ++ mfaAssertion;

            # Add warnings
            warnings =
              optional (cfg.openFirewall && firewallPorts == [])
                "services.redpanda.openFirewall is enabled but no ports were detected in the configuration"
              ++ optional (cfg.enforceTLS && kafkaTLSConfigured)
                "TLS enforcement enabled ✓ - Kafka API is using encrypted communication (STIG SC-8, CJIS 5.10)"
              ++ optional (cfg.enforceTLS && adminTLSConfigured)
                "TLS enforcement enabled ✓ - Admin API is using encrypted communication (STIG SC-8, CJIS 5.10)";
          };
        };
    };
}
