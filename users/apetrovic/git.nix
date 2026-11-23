{
  programs.git = {
    enable = true;
    lfs.enable = true;

    settings = {
      user = {
        name = "apetrovic";
        email = "petrovicante6@gmail.com";
      };

      init.defaultBranch = "master";
      pull.rebase = true;
      push.autoSetupRemote = true;
      rebase.autoStash = true;
    };
  };
}
