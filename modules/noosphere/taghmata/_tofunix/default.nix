{ref, ...}: {
  imports = [
    ./harbor
    ./forgejo
    ./kubernetes
    ./projects
    ./pocket-id
    ./barman-cloud
  ];

  terraform.backend = {
    s3 = {
      bucket = "opentofu";
      key = "terraform.tfstate";
      region = "main";
      endpoints = {
        s3 = "https://s3.main.garage.noosphere.uk";
      };
      skip_credentials_validation = true;
      skip_requesting_account_id = true;
      skip_metadata_api_check = true;
      skip_region_validation = true;
      use_path_style = true;
    };
  };

  provider.sops.default = {};
}
