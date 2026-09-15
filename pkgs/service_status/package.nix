{
  lib,
  buildGoModule,
  curl,
  git,
  gnused,
  go,
  runCommand,
  stdenv,
  testers,
  versionCheckHook,
  writeShellApplication,
  writeShellScriptBin,
}:
buildGoModule (finalAttrs: {
  pname = "service-status";
  version = "0.1.0";
  src = ./src;
  vendorHash = "sha256-Ip2GuQDOolMyDvfmXcJRlY2rMp1amS8owkqcNMOR1+Y=";

  env.CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${finalAttrs.version}"
  ];

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru.updateScript = writeShellApplication {
    name = "update-service-status";
    runtimeInputs = [
      git
      gnused
      go
    ];
    text = ''
      root=$(git rev-parse --show-toplevel)
      srcDir="$root/pkgs/service_status/src"
      pkgFile="$root/pkgs/service_status/package.nix"

      (cd "$srcDir" && go get -u ./... && go mod tidy)

      sed -i 's|vendorHash = "[^"]*"|vendorHash = ""|' "$pkgFile"

      hash=$(
        nix build "$root#service-status" --no-link 2>&1 \
          | grep -oE 'got:\s*sha256-[A-Za-z0-9+/=]+' \
          | awk '{print $2}'
      ) || true

      if [ -z "$hash" ]; then
        echo "error: could not determine new vendorHash" >&2
        exit 1
      fi

      sed -i "s|vendorHash = \"\"|vendorHash = \"$hash\"|" "$pkgFile"
    '';
  };

  passthru.tests =
    let
      mockBins =
        if stdenv.hostPlatform.isDarwin then
          {
            launchctl = writeShellScriptBin "launchctl" ''
              printf 'PID\tStatus\tLabel\n'
              printf '123\t0\torg.nix-community.home.test-daemon\n'
            '';
            plutil = writeShellScriptBin "plutil" ''
              echo '{"Label":"org.nix-community.home.test-daemon","ProgramArguments":["/bin/true"],"KeepAlive":true,"RunAtLoad":true}'
            '';
            lsof = writeShellScriptBin "lsof" ''
              echo "p1234"
              echo "cservice-status"
              echo "n127.0.0.1:$MOCK_PORT"
            '';
          }
        else
          {
            systemctl = writeShellScriptBin "systemctl" ''
              case "$2" in
                list-units)
                  echo "test-daemon.service loaded active running Test Daemon"
                  ;;
                show)
                  printf 'ActiveState=active\nSubState=running\nExecMainStatus=0\nTimersCalendar=\n'
                  ;;
              esac
            '';
            ss = writeShellScriptBin "ss" ''
              echo "State      Recv-Q Send-Q Local Address:Port  Peer Address:Port Process"
              echo "LISTEN     0      128    127.0.0.1:$MOCK_PORT     0.0.0.0:*     users:((\"service-status\",pid=1234,fd=4))"
            '';
          };
      mockJournalBins =
        if stdenv.hostPlatform.isDarwin then
          {
            log = writeShellScriptBin "log" ''
              echo '{"timestamp":"2026-06-03 13:52:31.000000-0400","messageType":"Error","eventMessage":"mock crash entry","subsystem":"com.apple.kernel"}'
            '';
            sysctl = writeShellScriptBin "sysctl" ''
              echo '{ sec = 1780509151, usec = 0 } Wed Jun  3 13:52:31 2026'
            '';
          }
        else
          {
            journalctl = writeShellScriptBin "journalctl" ''
              echo '{"__REALTIME_TIMESTAMP":"1780509151000000","PRIORITY":"3","_SYSTEMD_UNIT":"kernel","MESSAGE":"amdgpu: ring gfx timeout"}'
            '';
          };
    in
    {
      version = testers.testVersion {
        package = finalAttrs.finalPackage;
      };
      status-endpoint =
        runCommand "${finalAttrs.pname}-status-test"
          {
            meta.description = "Verifies /status endpoint returns service state JSON";
            nativeBuildInputs = [
              finalAttrs.finalPackage
              curl
            ]
            ++ (
              if stdenv.hostPlatform.isDarwin then
                [
                  mockBins.launchctl
                  mockBins.plutil
                ]
              else
                [ mockBins.systemctl ]
            );
          }
          (
            (lib.optionalString stdenv.hostPlatform.isDarwin ''
              export HOME=$(mktemp -d)
              mkdir -p "$HOME/Library/LaunchAgents"
              touch "$HOME/Library/LaunchAgents/org.nix-community.home.test-daemon.plist"
            '')
            + ''
              service-status --port 19876 &
              pid=$!
              trap 'kill $pid 2>/dev/null' EXIT
              sleep 1

              response=$(curl -sf http://127.0.0.1:19876/status)
              if ! echo "$response" | grep -q '"state"'; then
                echo "unexpected /status response: $response"
                exit 1
              fi
              touch $out
            ''
          );
      ports-endpoint =
        runCommand "${finalAttrs.pname}-ports-test"
          {
            meta.description = "Verifies /ports endpoint returns listening port info";
            nativeBuildInputs = [
              finalAttrs.finalPackage
              curl
            ]
            ++ (if stdenv.hostPlatform.isDarwin then [ mockBins.lsof ] else [ mockBins.ss ]);
          }
          ''
            export MOCK_PORT=19877

            service-status --port 19877 &
            pid=$!
            trap 'kill $pid 2>/dev/null' EXIT
            sleep 1

            response=$(curl -sf http://127.0.0.1:19877/ports)
            if ! echo "$response" | grep -q '"port"'; then
              echo "unexpected /ports response: $response"
              exit 1
            fi

            # The service itself should appear in the ports list
            if ! echo "$response" | grep -q 'service-status'; then
              echo "service-status not found in /ports response: $response"
              exit 1
            fi
            touch $out
          '';
      journal-endpoint =
        runCommand "${finalAttrs.pname}-journal-test"
          {
            meta.description = "Verifies /journal endpoint returns log entries and validates the boot and limit query params";
            nativeBuildInputs = [
              finalAttrs.finalPackage
              curl
            ]
            ++ (
              if stdenv.hostPlatform.isDarwin then
                [
                  mockJournalBins.log
                  mockJournalBins.sysctl
                ]
              else
                [ mockJournalBins.journalctl ]
            );
          }
          ''
            service-status --port 19878 &
            pid=$!
            trap 'kill $pid 2>/dev/null' EXIT
            sleep 1

            response=$(curl -sf "http://127.0.0.1:19878/journal?boot=current")
            if ! echo "$response" | grep -q '"message"'; then
              echo "unexpected /journal response: $response"
              exit 1
            fi

            # A valid limit is accepted.
            code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:19878/journal?boot=current&limit=10")
            if [ "$code" != "200" ]; then
              echo "expected 200 for valid limit, got $code"
              exit 1
            fi

            # An unknown boot selector must be rejected, never passed through
            # to the underlying log command.
            code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:19878/journal?boot=bogus")
            if [ "$code" != "400" ]; then
              echo "expected 400 for invalid boot selector, got $code"
              exit 1
            fi

            # A non-positive / non-numeric limit must be rejected.
            code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:19878/journal?boot=current&limit=0")
            if [ "$code" != "400" ]; then
              echo "expected 400 for invalid limit, got $code"
              exit 1
            fi
            touch $out
          '';
    };

  meta = {
    description = "Serves managed background service status over HTTP";
    homepage = "https://github.com/jtrrll/nix-lib";
    license = lib.licenses.agpl3Plus;
    mainProgram = "service-status";
    maintainers = [
      lib.maintainers.jtrrll
    ];
    platforms = lib.platforms.unix;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
