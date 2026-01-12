{lib, ...}: let
  cache = "1m";

  mkLink = site: separator: lib.join "" (lib.splitString separator (lib.toLower site));

  k8s = [
    {
      title = "Nixidy";
      url = "https://nixidy.dev/";
      icon = "https://nixidy.dev/logo.svg";
    }

    {
      title = "Artifact Hub";
      url = "https://artifacthub.io/";
      icon = "di:artifacthub";
    }

    {
      title = "Operator Hub";
      url = "https://operatorhub.io/";
      icon = "di:artifacthub";
    }
  ];
in {
  services = [
    {
      name = "Services";
      width = "slim";
      center-vertically = true;
      columns = [
        {
          width = "slim";
          size = "full";
          widgets = [
            {
              type = "extension";
              title = "Nodes";
              url = "http://glance-k8s/extension/nodes";
              allow-potentially-dangerous-html = true;
              inherit cache;
            }

            {
              type = "extension";
              title = "GitOps";
              url = "http://glance-k8s/extension/apps";
              allow-potentially-dangerous-html = true;
              inherit cache;

              parameters = {
                show-if = ''
                  namespace != "kube-system" and
                  "glance/name" in annotations and
                   ("category" in annotations && annotations["category"] == "gitops")
                '';
              };
            }
            {
              type = "extension";
              title = "Storage";
              url = "http://glance-k8s/extension/apps";
              allow-potentially-dangerous-html = true;
              inherit cache;

              parameters = {
                # Environment.name = "Storage";
                show-if = ''
                  namespace != "kube-system" and
                  "glance/name" in annotations and
                  annotations["glance/hide"] != "true" and
                  ("category" in annotations && annotations["category"] == "storage")
                '';
              };
            }

            {
              type = "extension";
              title = "Monitoring";
              url = "http://glance-k8s/extension/apps";
              allow-potentially-dangerous-html = true;
              inherit cache;

              parameters = {
                # Environment.name = "Storage";
                show-if = ''
                  namespace != "kube-system" and
                  "glance/name" in annotations and
                   ("category" in annotations && annotations["category"] == "monitoring")
                '';
              };
            }

            {
              type = "extension";
              title = "Yarr";
              url = "http://glance-k8s/extension/apps";
              allow-potentially-dangerous-html = true;
              inherit cache;

              parameters = {
                show-if = ''
                  namespace != "kube-system" and
                  "glance/name" in annotations and
                   ("category" in annotations && annotations["category"] == "yarr")
                '';
              };
            }

            {
              type = "extension";
              title = "Security";
              url = "http://glance-k8s/extension/apps";
              allow-potentially-dangerous-html = true;
              inherit cache;

              parameters = {
                show-if = ''
                  namespace != "kube-system" and
                  "glance/name" in annotations and
                   ("category" in annotations && annotations["category"] == "security")
                '';
              };
            }
            {
              type = "extension";
              title = "Utils";
              url = "http://glance-k8s/extension/apps";
              allow-potentially-dangerous-html = true;
              inherit cache;

              parameters = {
                show-if = ''
                  namespace != "kube-system" and
                  "glance/name" in annotations and
                   ("category" in annotations && annotations["category"] == "utils")
                '';
              };
            }

            {
              type = "bookmarks";
              groups = [
                {
                  hide-arrow = true;
                  title = "K8s";
                  links = k8s;
                }

                {
                  hide-arrow = true;
                  title = "Docs";
                  links = [
                    {
                      title = "CloudNative PG";
                      url = "https://cloudnative-pg.io/docs/";
                      icon = "sh:postgresql";
                    }

                    {
                      title = "CloudNative PG Examples";
                      url = "https://github.com/cloudnative-pg/cloudnative-pg/tree/main/docs/src/samples";
                      icon = "sh:postgresql";
                    }
                    {
                      title = "Barman Cloud Plugin";
                      url = "https://cloudnative-pg.io/plugin-barman-cloud/docs/usage/";
                      icon = "sh:postgresql";
                    }

                    {
                      title = "Argo CD";
                      url = "https://argo-cd.readthedocs.io/en/stable/";
                      icon = "di:argo-cd";
                    }

                    {
                      title = "Longhorn";
                      url = "https://longhorn.io/docs";
                      icon = "di:longhorn";
                    }
                  ];
                }

                {
                  hide-arrow = true;
                  title = "Nix";
                  links = [
                    {
                      title = "Nix Wiki";
                      url = "https://wiki.nixos.org/wiki/NixOS_Wiki";
                      icon = "di:nixos";
                    }
                    {
                      title = "Noogle";
                      url = "https://noogle.dev";
                      icon = "di:nixos";
                    }

                    {
                      title = "Nixos Search";
                      url = "https://search.nixos.org/packages";
                      icon = "di:nixos";
                    }

                    {
                      title = "Clan.lol";
                      url = "https://docs.clan.lol";
                      icon = "auto-invert https://docs.clan.lol/main/static/icons/clan-logo.svg";
                    }
                  ];
                }

                {
                  hide-arrow = true;
                  title = "Utils";
                  links = [
                    {
                      title = "Deep Wiki";
                      url = "https://deepwiki.org/";
                      icon = "https://external-content.duckduckgo.com/ip3/deepwiki.org.ico";
                    }
                  ];
                }
                {
                  hide-arrow = true;
                  title = "Icons";
                  links = [
                    {
                      title = "Material Design Icons";
                      url = "https://pictogrammers.com/library/mdi/";
                      icon = "mdi:material-ui";
                    }
                    {
                      title = "Dashboard Icons";
                      url = "https://dashboardicons.com/icons";
                      icon = "di:dashboard-icons";
                    }

                    {
                      title = "Selfh.st Icons";
                      url = "https://selfh.st/icons/";
                      icon = "sh:selfh-st";
                    }
                  ];
                }
              ];
            }
          ];
        }
      ];
    }
  ];
}
