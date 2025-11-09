{...}: {
  programs.firefox.enable = true;
  programs.firefox.profiles.apetrovic.extensions.force = true;

  programs.librewolf = {
    enable = true;

    profiles.apetrovic = {
      isDefault = true;
      id = 0;

      containersForce = true;
      containers = {
        google = {id = 1;};
        meta = {id = 2;};
        work = {id = 3;};
        banking = {id = 4;};
        shopping = {id = 5;};
        private = {id = 6;};
      };

      # If you set extensions.settings here or in sub-attrs,
      # and Home Manager warns it "overrides previous settings",
      # add:
      extensions = {
        force = true;
      };
    };
  };
}
