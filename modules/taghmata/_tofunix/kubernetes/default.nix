{ref, ...}: {
  provider.kubernetes.default = {
    config_path = "~/.kube/config";
    config_context = "default";
  };
}
