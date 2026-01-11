{...}: let
  cache = "1m";
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
                  title = "K8s";
                  links = [
                    {
                      title = "Nixidy";
                      url = "https://nixidy.dev/";
                    }

                    {
                      title = "Artifact Hub";
                      url = "https://artifacthub.io/";
                    }

                    {
                      title = "Operator Hub";
                      url = "https://operatorhub.io/";
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
