{ config, lib, ... }:
let
  nixosModule = config.flake.modules.nixos.opencode;
in
{
  config.perSystem =
    { pkgs, ... }:
    let
      instance = "alice-server";
      machineUser = "opencode-${instance}";
      unit = "opencode-${instance}.service";
      port = 4100;
      endpoint = "/api/info";
      password = "correct-horse-battery-staple";
      passwordFile = "/etc/opencode-${instance}-password";
      clientPasswordFile = "/etc/opencode-${instance}-alice-password";

      inherit (import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs) snakeOilPrivateKey snakeOilPublicKey;

      serverModule = {
        imports = [ nixosModule ];
        users.users = {
          alice.isNormalUser = true;
          bob.isNormalUser = true;
        };
        services.opencode = {
          enable = true;
          instances.${instance} = {
            inherit port passwordFile;
          };
        };
        environment.etc = {
          "opencode-${instance}-password" = {
            text = password;
            mode = "0400";
          };
          "opencode-${instance}-alice-password" = {
            text = password;
            user = "alice";
            mode = "0400";
          };
        };
      };
    in
    {
      checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        "modules/nixos:opencode/local-access" = pkgs.testers.runNixOSTest {
          name = "opencode-local-access";
          nodes.server = serverModule;
          testScript = ''
            server.wait_for_unit("${unit}")
            server.wait_for_open_port(${toString port})

            with subtest("the instance runs as its machine user"):
                server.succeed("test \"$(systemctl show --property=User --value ${unit})\" = ${machineUser}")

            with subtest("only a client's own copy of the password is readable by that client"):
                server.succeed("su - alice -c 'cat ${clientPasswordFile}' > /dev/null")
                server.fail("su - alice -c 'cat ${passwordFile}'")
                server.fail("su - bob -c 'cat ${clientPasswordFile}'")
                server.fail("su - bob -c 'cat ${passwordFile}'")

            with subtest("a client can reach the instance with the password"):
                server.succeed("su - alice -c 'curl --silent --fail --user opencode:$(cat ${clientPasswordFile}) http://127.0.0.1:${toString port}${endpoint}'")

            with subtest("the password gates every local user"):
                for user in ["alice", "bob"]:
                    status, output = server.execute(f"su - {user} -c \"curl --silent --output /dev/null --write-out '%{{http_code}}' --user opencode:wrong http://127.0.0.1:${toString port}${endpoint}\"")
                    assert output == "401", f"expected HTTP 401 for {user}, got {output!r} (curl exit {status})"
          '';
        };

        "modules/nixos:opencode/remote-access" = pkgs.testers.runNixOSTest {
          name = "opencode-remote-access";
          nodes = {
            server = {
              imports = [ serverModule ];
              services.openssh.enable = true;
              services.opencode.instances.${instance}.openFirewall = true;
              users.users = {
                alice = {
                  initialPassword = "alice";
                  openssh.authorizedKeys.keys = [ snakeOilPublicKey ];
                };
                bob = {
                  initialPassword = "bob";
                  openssh.authorizedKeys.keys = [ snakeOilPublicKey ];
                };
              };
            };
            client = { };
          };
          testScript = ''
            import shlex

            server.wait_for_unit("${unit}")
            server.wait_for_open_port(${toString port})
            server.wait_for_unit("sshd.service")
            client.wait_for_unit("multi-user.target")
            client.succeed("install --mode=600 ${snakeOilPrivateKey} /root/id")

            ssh = "ssh -i /root/id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ExitOnForwardFailure=yes"
            status_of = "curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10"

            with subtest("the server listens on all interfaces and the firewall opens its port"):
                listeners = server.succeed("ss --listening --numeric --tcp --no-header 'sport = :${toString port}'")
                local_addresses = [line.split()[3] for line in listeners.splitlines()]
                assert local_addresses == ["0.0.0.0:${toString port}"], listeners

            password = client.succeed(f"{ssh} alice@server cat ${clientPasswordFile}")
            assert password == "${password}", f"unexpected password: {password!r}"
            credentials = shlex.quote("opencode:" + password)

            with subtest("another machine can reach the port directly, behind the password"):
                _, code = client.execute(f"{status_of} http://server:${toString port}${endpoint}")
                assert code == "401", f"expected HTTP 401 without the password, got {code!r}"
                _, code = client.execute(f"{status_of} --user opencode:wrong http://server:${toString port}${endpoint}")
                assert code == "401", f"expected HTTP 401 with a wrong password, got {code!r}"
                client.succeed(f"curl --silent --fail --max-time 10 --user {credentials} http://server:${toString port}${endpoint}")

            with subtest("a client can use the web port through an SSH forward"):
                client.succeed(f"{ssh} -f -N -L 4101:127.0.0.1:${toString port} alice@server")
                client.succeed(f"curl --silent --fail --max-time 10 --user {credentials} http://127.0.0.1:4101${endpoint}")
                _, code = client.execute(f"{status_of} http://127.0.0.1:4101${endpoint}")
                assert code == "401", f"expected HTTP 401 without the password, got {code!r}"

            with subtest("a user who is not a client cannot read any password file over SSH"):
                client.fail(f"{ssh} bob@server cat ${clientPasswordFile}")
                client.fail(f"{ssh} bob@server cat ${passwordFile}")
          '';
        };
      };
    };
}
