{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.opencode;

  machineUserFor = name: "opencode-${name}";
  serverScriptFor =
    name: instance:
    pkgs.writeShellApplication {
      name = "opencode-${name}";
      runtimeInputs = [ cfg.package ];
      text = ''
        OPENCODE_PASSWORD="$(< "$CREDENTIALS_DIRECTORY/password")"
        export OPENCODE_PASSWORD
        exec opencode serve --hostname ${
          if instance.openFirewall then "0.0.0.0" else "127.0.0.1"
        } --port ${toString instance.port}
      '';
    };

  instancesByPort = lib.groupBy (instance: toString instance.port) (lib.attrValues cfg.instances);
in
{
  options.services.opencode = {
    enable = lib.mkEnableOption "opencode server instances, each running as its own machine user";

    package = lib.mkPackageOption pkgs "opencode" { };

    instances = lib.mkOption {
      default = { };
      description = ''
        opencode server instances. Each runs as the machine user
        `opencode-<name>`. Customize the user through
        `users.users.opencode-<name>`.
      '';
      example = lib.literalExpression ''
        {
          work = {
            port = 4100;
            passwordFile = "/run/secrets/opencode-work";
          };
        }
      '';
      type = lib.types.attrsOf (
        lib.types.submodule (_: {
          options = {
            port = lib.mkOption {
              type = lib.types.port;
              description = "Port the instance listens on.";
            };

            passwordFile = lib.mkOption {
              type = lib.types.pathWith {
                inStore = false;
                absolute = true;
              };
              example = "/run/secrets/opencode-work";
              description = "File holding the instance's password, read by systemd as root. Not managed by this module; each user who connects needs their own copy.";
            };

            environment = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              example = {
                OPENCODE_LOG_LEVEL = "DEBUG";
              };
              description = "Environment variables for the instance. They end up in the Nix store, so do not put secrets here.";
            };

            environmentFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              example = "/run/secrets/opencode-work";
              description = "systemd `EnvironmentFile` for the instance, for secrets.";
            };

            openFirewall = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether to listen on all interfaces and open the port in the firewall, instead of listening on loopback only. The password travels over plain HTTP.";
            };
          };
        })
      );
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      lib.mapAttrsToList (name: _: {
        assertion = lib.match "[a-z_][a-z0-9_-]*" name != null;
        message = "services.opencode.instances.${name}: the name must be usable in a unix user name (lowercase letters, digits, `_` and `-`).";
      }) cfg.instances
      ++ lib.mapAttrsToList (port: sharing: {
        assertion = lib.length sharing == 1;
        message = "services.opencode.instances: port ${port} is used by more than one instance.";
      }) instancesByPort;

    networking.firewall.allowedTCPPorts = lib.concatMap (
      instance: lib.optional instance.openFirewall instance.port
    ) (lib.attrValues cfg.instances);

    users = {
      users = lib.mkMerge (
        lib.mapAttrsToList (name: _: {
          ${machineUserFor name} = {
            isSystemUser = lib.mkDefault true;
            description = lib.mkDefault "opencode machine user for instance ${name}";
            group = lib.mkDefault (machineUserFor name);
            home = lib.mkDefault "/var/lib/${machineUserFor name}";
            createHome = lib.mkDefault true;
            homeMode = lib.mkDefault "0700";
            useDefaultShell = lib.mkDefault true;
          };
        }) cfg.instances
      );
      groups = lib.mkMerge (
        lib.mapAttrsToList (name: _: {
          ${machineUserFor name} = { };
        }) cfg.instances
      );
    };

    systemd.services = lib.mapAttrs' (
      name: instance:
      let
        user = config.users.users.${machineUserFor name};
      in
      lib.nameValuePair "opencode-${name}" {
        description = "opencode server instance ${name}";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        path = [ "/etc/profiles/per-user/${user.name}" ];
        environment = {
          GIT_CONFIG_COUNT = "1";
          GIT_CONFIG_KEY_0 = "safe.directory";
          GIT_CONFIG_VALUE_0 = "*";
        }
        // instance.environment;
        serviceConfig = {
          ExecStart = lib.getExe (serverScriptFor name instance);
          User = user.name;
          Group = user.group;
          UMask = "0002";
          WorkingDirectory = user.home;
          LoadCredential = "password:${instance.passwordFile}";
          Restart = "on-failure";
          EnvironmentFile = lib.optional (instance.environmentFile != null) instance.environmentFile;
          NoNewPrivileges = true;
          ProtectControlGroups = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          LockPersonality = true;
          RestrictSUIDSGID = true;
        };
      }
    ) cfg.instances;
  };
}
