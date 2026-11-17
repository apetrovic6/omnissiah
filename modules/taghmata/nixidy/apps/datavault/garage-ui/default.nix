# The web UIs of the two Garage clusters, both from ./_app.nix.
{...}: {
  nixidy.envs.prod.apps = {
    garage-main-ui = import ./_app.nix {
      cluster = "main";
      s3Service = "garage-s3-api";
    };

    garage-backup-ui = import ./_app.nix {
      cluster = "backup";
      s3Service = "garage-backup-s3-api";
    };
  };
}
