{...}: {
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
              cache = "1s";
            }

            {
              type = "extension";
              title = "Storage";
              url = "http://glance-k8s/extension/apps";
              allow-potentially-dangerous-html = true;
              cache = "1s";

              parameters = {
                # Environment.name = "Storage";
                show-if = ''
                  namespace != "kube-system" and
                  "glance/name" in annotations and
                  ("glance/hide" not in annotations || annotations["glance/hide"] != "true" and
                  ("category" in annotations && annotations["category"] == "storage")
                '';
              };
            }

            {
              type = "extension";
              title = "Monitoring";
              url = "http://glance-k8s/extension/apps";
              allow-potentially-dangerous-html = true;
              cache = "1s";

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
              cache = "1s";

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
              title = "Utils";
              url = "http://glance-k8s/extension/apps";
              allow-potentially-dangerous-html = true;
              cache = "1s";

              parameters = {
                show-if = ''
                  namespace != "kube-system" and
                  "glance/name" in annotations and
                   ("category" in annotations && annotations["category"] == "utils")
                '';
              };
            }
          ];
        }
      ];
    }
  ];
}
