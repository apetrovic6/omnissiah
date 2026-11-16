# mkSopsGenerators: clan vars generators whose output is one sops-encrypted
# document, written without the sops/heredoc boilerplate.
#
#   clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
#     garage-main-rpc-secret = {
#       namespace = "garage-operator";
#       random.secret = "-hex 32";
#       data.rpc-secret = "$secret";
#     };
#   };
#
# Each entry becomes a shared generator with one non-secret file. The file is
# not a clan secret because it is already encrypted, to the cluster's age key
# (noosphere.agePublicKey): sops-secrets-operator or the OpenTofu sops
# provider decrypts it, not the machines.
#
# Per entry:
#   namespace   Namespace of the SopsSecret. Leave it out for a plain document
#               (`data` as the top-level keys, every value encrypted), which is
#               what the OpenTofu sops provider reads.
#   secretName  Name of the SopsSecret and of the Secret it produces.
#               Default: the generator's name.
#   file        Name of the output file. Default: the generator's name.
#   labels      Labels on the produced Secret.
#   random      <shell variable> = <arguments to `openssl rand`>.
#   prompts     <prompt name> = { description; type ? "hidden"; persist ? false;
#               var ? <the prompt name with - as _>; }. The answer, without
#               its line ending, is in the shell variable `var`.
#   setup       Shell run after `random` and `prompts`, for values those two
#               cannot express.
#   data        <key> = <value>. The value is the inside of a double-quoted
#               shell word, so it may use the variables above and `$(...)`.
#   runtimeInputs  Packages `setup` needs. coreutils, jq, sops and (with
#               `random`) openssl are always there.
#
# The document is assembled with jq, not a YAML heredoc, so a value may hold
# quotes, backslashes or newlines without breaking the document.
{
  lib,
  ageKey,
}: pkgs: let
  inherit (lib) mapAttrs mapAttrsToList concatStringsSep escapeShellArg imap0 optionalString optional replaceStrings attrNames optionalAttrs;

  mkGenerator = name: {
    namespace ? null,
    secretName ? name,
    file ? name,
    labels ? {},
    random ? {},
    prompts ? {},
    setup ? "",
    data,
    runtimeInputs ? [],
  }: let
    isSopsSecret = namespace != null;

    promptVar = promptName: prompt: prompt.var or (replaceStrings ["-"] ["_"] promptName);

    # The document without its values: jq fills those in at generation time.
    skeleton =
      if isSopsSecret
      then {
        apiVersion = "isindir.github.com/v1alpha3";
        kind = "SopsSecret";
        metadata = {
          name = secretName;
          inherit namespace;
        };
        spec.secretTemplates = [
          ({
              name = secretName;
              type = "Opaque";
              stringData = {};
            }
            // optionalAttrs (labels != {}) {inherit labels;})
        ];
      }
      else {};

    keys = attrNames data;
    valuesPath =
      if isSopsSecret
      then ".spec.secretTemplates[0].stringData"
      else ".";
    jqArgs = concatStringsSep " " (imap0 (i: key: ''--arg v${toString i} "${data.${key}}"'') keys);
    jqValues = concatStringsSep ", " (imap0 (i: key: "${builtins.toJSON key}: $v${toString i}") keys);
  in {
    share = true;

    files.${file}.secret = false;

    prompts =
      mapAttrs (_: prompt: {
        inherit (prompt) description;
        type = prompt.type or "hidden";
        persist = prompt.persist or false;
      })
      prompts;

    runtimeInputs =
      [pkgs.coreutils pkgs.jq pkgs.sops]
      ++ optional (random != {}) pkgs.openssl
      ++ runtimeInputs;

    script = ''
      set -euo pipefail

      ${concatStringsSep "\n" (mapAttrsToList (var: args: ''${var}="$(openssl rand ${args})"'') random)}
      ${concatStringsSep "\n" (mapAttrsToList (promptName: prompt: ''${promptVar promptName prompt}="$(tr -d '\r\n' < "$prompts/${promptName}")"'') prompts)}
      ${setup}

      jq -n --argjson doc ${escapeShellArg (builtins.toJSON skeleton)} ${jqArgs} \
        ${escapeShellArg "$doc | ${valuesPath} = {${jqValues}}"} \
        | sops encrypt \
          --age ${escapeShellArg ageKey} \
          ${optionalString isSopsSecret ''--encrypted-suffix "Templates"''} \
          --input-type json --output-type yaml \
          /dev/stdin > "$out/${file}"
    '';
  };
in
  mapAttrs mkGenerator
