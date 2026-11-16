{...}: {
  services.imperium.vaultwarden = {
    enable = true;
    port = 8222;
    config = {
      SIGNUPS_ALLOWED = true;
      WEBSOCKET_ENABLED = true;
      WEBSOCKET_ADDRESS = "127.0.0.1";
      WEBSOCKET_PORT = 3012;

      PUSH_ENABLED = false;

      INCOMPLETE_2FA_TIME_LIMIT = 5;

      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_LOG = "critical";
    };
  };
}
