{
  config = {
    touchup.attr.packages.any.attr.github-tf.enable = false;
    perSystem =
      { config, pkgs, ... }:
      {
        config = {
          terranix.terranixConfigurations.github-tf = {
            workdir = ".terraform/github";
            terraformWrapper.package = pkgs.opentofu.withPlugins (p: [ p.integrations_github ]);
            modules = [
              {
                terraform.required_providers.github = {
                  source = "integrations/github";
                  version = "~> 6.0";
                };

                provider.github = {
                  owner = "jtrrll";
                  token = "\${var.github_token}";
                };

                variable = {
                  github_token = {
                    type = "string";
                    sensitive = true;
                    description = "GitHub personal access token with repo admin permissions";
                  };
                };

                resource = {
                  github_repository.nix-lib = {
                    name = "nix-lib";
                    description = "A reusable Nix library for jtrrll's repositories";
                    visibility = "public";

                    has_issues = true;
                    has_projects = false;
                    has_wiki = false;
                    has_discussions = false;

                    allow_merge_commit = false;
                    allow_squash_merge = true;
                    allow_rebase_merge = false;
                    allow_auto_merge = true;
                    allow_update_branch = true;
                    delete_branch_on_merge = true;

                    topics = [
                      "library"
                      "nix"
                      "nixos"
                      "nixpkgs"
                    ];
                  };

                  github_branch_default.main = {
                    repository = "\${github_repository.nix-lib.name}";
                    branch = "main";
                  };

                  github_repository_vulnerability_alerts.nix-lib = {
                    repository = "\${github_repository.nix-lib.name}";
                  };

                  github_repository_ruleset.main = {
                    name = "main";
                    repository = "\${github_repository.nix-lib.name}";
                    target = "branch";
                    enforcement = "active";

                    conditions = {
                      ref_name = {
                        include = [ "~DEFAULT_BRANCH" ];
                        exclude = [ ];
                      };
                    };

                    rules = {
                      deletion = true;
                      non_fast_forward = true;
                      required_linear_history = true;
                    };
                  };

                  github_repository_ruleset.pull_requests = {
                    name = "pull-requests";
                    repository = "\${github_repository.nix-lib.name}";
                    target = "branch";
                    enforcement = "active";

                    conditions = {
                      ref_name = {
                        include = [ "~DEFAULT_BRANCH" ];
                        exclude = [ ];
                      };
                    };

                    rules = {
                      pull_request = {
                        dismiss_stale_reviews_on_push = false;
                        required_approving_review_count = 0;
                        require_last_push_approval = false;
                      };

                      required_status_checks = {
                        required_check = [
                          {
                            context = "Check";
                          }
                        ];
                        strict_required_status_checks_policy = true;
                      };
                    };
                  };
                };

                output.url = {
                  value = "\${github_repository.nix-lib.html_url}";
                };
              }
            ];
          };
          apps.github-tf = {
            meta.description = "Manages GitHub repository with OpenTofu";
            type = "app";
            program = config.terranix.terranixConfigurations.github-tf.result.app;
          };
        };
      };
  };
}
