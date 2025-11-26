{...}:{
flake.lib = {
    mkHost = url: port: token: ''
      reverse_proxy "http://${url}:${port}"
      tls {
            dns cloudflare ${token}
      }
    '';
  

};

}
