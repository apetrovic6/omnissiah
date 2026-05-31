# This file was generated with nixidy resource generator, do not edit.
{
  lib,
  options,
  config,
  ...
}:

with lib;

let
  hasAttrNotNull = attr: set: hasAttr attr set && set.${attr} != null;

  attrsToList =
    values:
    if values != null then
      sort (
        a: b:
        if (hasAttrNotNull "_priority" a && hasAttrNotNull "_priority" b) then
          a._priority < b._priority
        else
          false
      ) (mapAttrsToList (n: v: v) values)
    else
      values;

  getDefaults =
    resource: group: version: kind:
    catAttrs "default" (
      filter (
        default:
        (default.resource == null || default.resource == resource)
        && (default.group == null || default.group == group)
        && (default.version == null || default.version == version)
        && (default.kind == null || default.kind == kind)
      ) config.defaults
    );

  types = lib.types // rec {
    str = mkOptionType {
      name = "str";
      description = "string";
      check = isString;
      merge = mergeEqualOption;
    };

    # Either value of type `finalType` or `coercedType`, the latter is
    # converted to `finalType` using `coerceFunc`.
    coercedTo =
      coercedType: coerceFunc: finalType:
      mkOptionType rec {
        inherit (finalType) getSubOptions getSubModules;

        name = "coercedTo";
        description = "${finalType.description} or ${coercedType.description}";
        check = x: finalType.check x || coercedType.check x;
        merge =
          loc: defs:
          let
            coerceVal =
              val:
              if finalType.check val then
                val
              else
                let
                  coerced = coerceFunc val;
                in
                assert finalType.check coerced;
                coerced;

          in
          finalType.merge loc (map (def: def // { value = coerceVal def.value; }) defs);
        substSubModules = m: coercedTo coercedType coerceFunc (finalType.substSubModules m);
        typeMerge = t1: t2: null;
        functor = (defaultFunctor name) // {
          wrapped = finalType;
        };
      };
  };

  mkOptionDefault = mkOverride 1001;

  mergeValuesByKey =
    attrMergeKey: listMergeKeys: values:
    listToAttrs (
      imap0 (
        i: value:
        nameValuePair (
          if hasAttr attrMergeKey value then
            if isAttrs value.${attrMergeKey} then
              toString value.${attrMergeKey}.content
            else
              (toString value.${attrMergeKey})
          else
            # generate merge key for list elements if it's not present
            "__kubenix_list_merge_key_"
            + (concatStringsSep "" (
              map (
                key: if isAttrs value.${key} then toString value.${key}.content else (toString value.${key})
              ) listMergeKeys
            ))
        ) (value // { _priority = i; })
      ) values
    );

  submoduleOf =
    ref:
    types.submodule (
      { name, ... }:
      {
        options = definitions."${ref}".options or { };
        config = definitions."${ref}".config or { };
      }
    );

  globalSubmoduleOf =
    ref:
    types.submodule (
      { name, ... }:
      {
        options = config.definitions."${ref}".options or { };
        config = config.definitions."${ref}".config or { };
      }
    );

  submoduleWithMergeOf =
    ref: mergeKey:
    types.submodule (
      { name, ... }:
      let
        convertName =
          name: if definitions."${ref}".options.${mergeKey}.type == types.int then toInt name else name;
      in
      {
        options = definitions."${ref}".options // {
          # position in original array
          _priority = mkOption {
            type = types.nullOr types.int;
            default = null;
            internal = true;
          };
        };
        config = definitions."${ref}".config // {
          ${mergeKey} = mkOverride 1002 (
            # use name as mergeKey only if it is not coming from mergeValuesByKey
            if (!hasPrefix "__kubenix_list_merge_key_" name) then convertName name else null
          );
        };
      }
    );

  submoduleForDefinition =
    ref: resource: kind: group: version:
    let
      apiVersion = if group == "core" then version else "${group}/${version}";
    in
    types.submodule (
      { name, ... }:
      {
        inherit (definitions."${ref}") options;

        imports = getDefaults resource group version kind;
        config = mkMerge [
          definitions."${ref}".config
          {
            kind = mkOptionDefault kind;
            apiVersion = mkOptionDefault apiVersion;

            # metdata.name cannot use option default, due deep config
            metadata.name = mkOptionDefault name;
          }
        ];
      }
    );

  coerceAttrsOfSubmodulesToListByKey =
    ref: attrMergeKey: listMergeKeys:
    (types.coercedTo (types.listOf (submoduleOf ref)) (mergeValuesByKey attrMergeKey listMergeKeys) (
      types.attrsOf (submoduleWithMergeOf ref attrMergeKey)
    ));

  definitions = {
    "frrk8s.metallb.io.v1beta1.BGPSessionState" = {

      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = (types.nullOr types.str);
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = (types.nullOr types.str);
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = (types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta"));
        };
        "spec" = mkOption {
          description = "BGPSessionStateSpec defines the desired state of BGPSessionState.";
          type = (types.nullOr types.attrs);
        };
        "status" = mkOption {
          description = "BGPSessionStateStatus defines the observed state of BGPSessionState.";
          type = (types.nullOr (submoduleOf "frrk8s.metallb.io.v1beta1.BGPSessionStateStatus"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.BGPSessionStateStatus" = {

      options = {
        "bfdStatus" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "bgpStatus" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "node" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "peer" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "vrf" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "bfdStatus" = mkOverride 1002 null;
        "bgpStatus" = mkOverride 1002 null;
        "node" = mkOverride 1002 null;
        "peer" = mkOverride 1002 null;
        "vrf" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRConfiguration" = {

      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = (types.nullOr types.str);
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = (types.nullOr types.str);
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = (types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta"));
        };
        "spec" = mkOption {
          description = "FRRConfigurationSpec defines the desired state of FRRConfiguration.";
          type = (types.nullOr (submoduleOf "frrk8s.metallb.io.v1beta1.FRRConfigurationSpec"));
        };
        "status" = mkOption {
          description = "FRRConfigurationStatus defines the observed state of FRRConfiguration.";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRConfigurationSpec" = {

      options = {
        "bgp" = mkOption {
          description = "BGP is the configuration related to the BGP protocol.";
          type = (types.nullOr (submoduleOf "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgp"));
        };
        "nodeSelector" = mkOption {
          description = "NodeSelector limits the nodes that will attempt to apply this config.\nWhen specified, the configuration will be considered only on nodes\nwhose labels match the specified selectors.\nWhen it is not specified all nodes will attempt to apply this config.";
          type = (types.nullOr (submoduleOf "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecNodeSelector"));
        };
        "raw" = mkOption {
          description = "Raw is a snippet of raw frr configuration that gets appended to the\none rendered translating the type safe API.";
          type = (types.nullOr (submoduleOf "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecRaw"));
        };
      };

      config = {
        "bgp" = mkOverride 1002 null;
        "nodeSelector" = mkOverride 1002 null;
        "raw" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgp" = {

      options = {
        "bfdProfiles" = mkOption {
          description = "BFDProfiles is the list of bfd profiles to be used when configuring the neighbors.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpBfdProfiles"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "routers" = mkOption {
          description = "Routers is the list of routers we want FRR to configure (one per VRF).";
          type = (
            types.nullOr (types.listOf (submoduleOf "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRouters"))
          );
        };
      };

      config = {
        "bfdProfiles" = mkOverride 1002 null;
        "routers" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpBfdProfiles" = {

      options = {
        "detectMultiplier" = mkOption {
          description = "Configures the detection multiplier to determine\npacket loss. The remote transmission interval will be multiplied\nby this value to determine the connection loss detection timer.";
          type = (types.nullOr types.int);
        };
        "echoInterval" = mkOption {
          description = "Configures the minimal echo receive transmission\ninterval that this system is capable of handling in milliseconds.\nDefaults to 50ms";
          type = (types.nullOr types.int);
        };
        "echoMode" = mkOption {
          description = "Enables or disables the echo transmission mode.\nThis mode is disabled by default, and not supported on multi\nhops setups.";
          type = (types.nullOr types.bool);
        };
        "minimumTtl" = mkOption {
          description = "For multi hop sessions only: configure the minimum\nexpected TTL for an incoming BFD control packet.";
          type = (types.nullOr types.int);
        };
        "name" = mkOption {
          description = "The name of the BFD Profile to be referenced in other parts\nof the configuration.";
          type = types.str;
        };
        "passiveMode" = mkOption {
          description = "Mark session as passive: a passive session will not\nattempt to start the connection and will wait for control packets\nfrom peer before it begins replying.";
          type = (types.nullOr types.bool);
        };
        "receiveInterval" = mkOption {
          description = "The minimum interval that this system is capable of\nreceiving control packets in milliseconds.\nDefaults to 300ms.";
          type = (types.nullOr types.int);
        };
        "transmitInterval" = mkOption {
          description = "The minimum transmission interval (less jitter)\nthat this system wants to use to send BFD control packets in\nmilliseconds. Defaults to 300ms";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "detectMultiplier" = mkOverride 1002 null;
        "echoInterval" = mkOverride 1002 null;
        "echoMode" = mkOverride 1002 null;
        "minimumTtl" = mkOverride 1002 null;
        "passiveMode" = mkOverride 1002 null;
        "receiveInterval" = mkOverride 1002 null;
        "transmitInterval" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRouters" = {

      options = {
        "asn" = mkOption {
          description = "ASN is the AS number to use for the local end of the session.";
          type = types.int;
        };
        "id" = mkOption {
          description = "ID is the BGP router ID";
          type = (types.nullOr types.str);
        };
        "imports" = mkOption {
          description = "Imports is the list of imported VRFs we want for this router / vrf.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersImports")
            )
          );
        };
        "neighbors" = mkOption {
          description = "Neighbors is the list of neighbors we want to establish BGP sessions with.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersNeighbors")
            )
          );
        };
        "prefixes" = mkOption {
          description = "Prefixes is the list of prefixes we want to advertise from this router instance.";
          type = (types.nullOr (types.listOf types.str));
        };
        "vrf" = mkOption {
          description = "VRF is the host vrf used to establish sessions from this router.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "id" = mkOverride 1002 null;
        "imports" = mkOverride 1002 null;
        "neighbors" = mkOverride 1002 null;
        "prefixes" = mkOverride 1002 null;
        "vrf" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersImports" = {

      options = {
        "vrf" = mkOption {
          description = "Vrf is the vrf we want to import from";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "vrf" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersNeighbors" = {

      options = {
        "address" = mkOption {
          description = "Address is the IP address to establish the session with.";
          type = (types.nullOr types.str);
        };
        "asn" = mkOption {
          description = "ASN is the AS number to use for the local end of the session.\nASN and DynamicASN are mutually exclusive and one of them must be specified.";
          type = (types.nullOr types.int);
        };
        "bfdProfile" = mkOption {
          description = "BFDProfile is the name of the BFD Profile to be used for the BFD session associated\nto the BGP session. If not set, the BFD session won't be set up.";
          type = (types.nullOr types.str);
        };
        "connectTime" = mkOption {
          description = "Requested BGP connect time, controls how long BGP waits between connection attempts to a neighbor.";
          type = (types.nullOr types.str);
        };
        "disableMP" = mkOption {
          description = "DisableMP is no longer used and has no effect.\nUse DualStackAddressFamily instead to enable the neighbor for both IPv4 and IPv6 address families.\n\nDeprecated: This field is ignored. Use DualStackAddressFamily instead.";
          type = (types.nullOr types.bool);
        };
        "dualStackAddressFamily" = mkOption {
          description = "To set if we want to enable the neighbor not only for the ipfamily related to its session,\nbut also the other one. This allows to advertise/receive IPv4 prefixes over IPv6 sessions and vice versa.";
          type = (types.nullOr types.bool);
        };
        "dynamicASN" = mkOption {
          description = "DynamicASN detects the AS number to use for the local end of the session\nwithout explicitly setting it via the ASN field. Limited to:\ninternal - if the neighbor's ASN is different than the router's the connection is denied.\nexternal - if the neighbor's ASN is the same as the router's the connection is denied.\nASN and DynamicASN are mutually exclusive and one of them must be specified.";
          type = (types.nullOr types.str);
        };
        "ebgpMultiHop" = mkOption {
          description = "EBGPMultiHop indicates if the BGPPeer is multi-hops away.";
          type = (types.nullOr types.bool);
        };
        "enableGracefulRestart" = mkOption {
          description = "EnableGracefulRestart allows BGP peer to continue to forward data packets along\nknown routes while the routing protocol information is being restored. If\nthe session is already established, the configuration will have effect\nafter reconnecting to the peer";
          type = (types.nullOr types.bool);
        };
        "holdTime" = mkOption {
          description = "HoldTime is the requested BGP hold time, per RFC4271.\nDefaults to 180s.";
          type = (types.nullOr types.str);
        };
        "interface" = mkOption {
          description = "Interface is the node interface over which the unnumbered BGP peering will\nbe established. No API validation takes place as that string value\nrepresents an interface name on the host and if user provides an invalid\nvalue, only the actual BGP session will not be established.\nAddress and Interface are mutually exclusive and one of them must be specified.\nNote: when enabling unnumbered, the neighbor will be enabled for both\nIPv4 and IPv6 address families.";
          type = (types.nullOr types.str);
        };
        "keepaliveTime" = mkOption {
          description = "KeepaliveTime is the requested BGP keepalive time, per RFC4271.\nDefaults to 60s.";
          type = (types.nullOr types.str);
        };
        "localASN" = mkOption {
          description = "LocalASN allows advertising a different AS number to the peer using BGP's\nlocal-as feature. When set, FRR will advertise this ASN to the peer\nvia \"neighbor <peer> local-as <ASN> no-prepend replace-as\", overriding\nthe router-level ASN for this specific session.\nNote: this field is only applicable to eBGP sessions (where the peer ASN differs\nfrom the router ASN). Setting it on an iBGP session is rejected.";
          type = (types.nullOr types.int);
        };
        "password" = mkOption {
          description = "Password to be used for establishing the BGP session.\nPassword and PasswordSecret are mutually exclusive.";
          type = (types.nullOr types.str);
        };
        "passwordSecret" = mkOption {
          description = "PasswordSecret is name of the authentication secret for the neighbor.\nthe secret must be of type \"kubernetes.io/basic-auth\", and created in the\nsame namespace as the frr-k8s daemon. The password is stored in the\nsecret as the key \"password\".\nPassword and PasswordSecret are mutually exclusive.";
          type = (
            types.nullOr (
              submoduleOf "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersNeighborsPasswordSecret"
            )
          );
        };
        "port" = mkOption {
          description = "Port is the port to dial when establishing the session.\nDefaults to 179.";
          type = (types.nullOr types.int);
        };
        "sourceaddress" = mkOption {
          description = "SourceAddress is the IPv4 or IPv6 source address to use for the BGP\nsession to this neighbour, may be specified as either an IP address\ndirectly or as an interface name";
          type = (types.nullOr types.str);
        };
        "toAdvertise" = mkOption {
          description = "ToAdvertise represents the list of prefixes to advertise to the given neighbor\nand the associated properties.";
          type = (
            types.nullOr (
              submoduleOf "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersNeighborsToAdvertise"
            )
          );
        };
        "toReceive" = mkOption {
          description = "ToReceive represents the list of prefixes to receive from the given neighbor.";
          type = (
            types.nullOr (
              submoduleOf "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersNeighborsToReceive"
            )
          );
        };
      };

      config = {
        "address" = mkOverride 1002 null;
        "asn" = mkOverride 1002 null;
        "bfdProfile" = mkOverride 1002 null;
        "connectTime" = mkOverride 1002 null;
        "disableMP" = mkOverride 1002 null;
        "dualStackAddressFamily" = mkOverride 1002 null;
        "dynamicASN" = mkOverride 1002 null;
        "ebgpMultiHop" = mkOverride 1002 null;
        "enableGracefulRestart" = mkOverride 1002 null;
        "holdTime" = mkOverride 1002 null;
        "interface" = mkOverride 1002 null;
        "keepaliveTime" = mkOverride 1002 null;
        "localASN" = mkOverride 1002 null;
        "password" = mkOverride 1002 null;
        "passwordSecret" = mkOverride 1002 null;
        "port" = mkOverride 1002 null;
        "sourceaddress" = mkOverride 1002 null;
        "toAdvertise" = mkOverride 1002 null;
        "toReceive" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersNeighborsPasswordSecret" = {

      options = {
        "name" = mkOption {
          description = "name is unique within a namespace to reference a secret resource.";
          type = (types.nullOr types.str);
        };
        "namespace" = mkOption {
          description = "namespace defines the space within which the secret name must be unique.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersNeighborsToAdvertise" = {

      options = {
        "allowed" = mkOption {
          description = "Allowed is is the list of prefixes allowed to be propagated to\nthis neighbor. They must match the prefixes defined in the router.";
          type = (
            types.nullOr (
              submoduleOf "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersNeighborsToAdvertiseAllowed"
            )
          );
        };
        "withCommunity" = mkOption {
          description = "PrefixesWithCommunity is a list of prefixes that are associated to a\nbgp community when being advertised. The prefixes associated to a given local pref\nmust be in the prefixes allowed to be advertised.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersNeighborsToAdvertiseWithCommunity"
              )
            )
          );
        };
        "withLocalPref" = mkOption {
          description = "PrefixesWithLocalPref is a list of prefixes that are associated to a local\npreference when being advertised. The prefixes associated to a given local pref\nmust be in the prefixes allowed to be advertised.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersNeighborsToAdvertiseWithLocalPref"
              )
            )
          );
        };
      };

      config = {
        "allowed" = mkOverride 1002 null;
        "withCommunity" = mkOverride 1002 null;
        "withLocalPref" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersNeighborsToAdvertiseAllowed" = {

      options = {
        "mode" = mkOption {
          description = "Mode is the mode to use when handling the prefixes.\nWhen set to \"filtered\", only the prefixes in the given list will be allowed.\nWhen set to \"all\", all the prefixes configured on the router will be allowed.";
          type = (types.nullOr types.str);
        };
        "prefixes" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "mode" = mkOverride 1002 null;
        "prefixes" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersNeighborsToAdvertiseWithCommunity" = {

      options = {
        "community" = mkOption {
          description = "Community is the community associated to the prefixes.";
          type = (types.nullOr types.str);
        };
        "prefixes" = mkOption {
          description = "Prefixes is the list of prefixes associated to the community.";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "community" = mkOverride 1002 null;
        "prefixes" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersNeighborsToAdvertiseWithLocalPref" = {

      options = {
        "localPref" = mkOption {
          description = "LocalPref is the local preference associated to the prefixes.";
          type = (types.nullOr types.int);
        };
        "prefixes" = mkOption {
          description = "Prefixes is the list of prefixes associated to the local preference.";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "localPref" = mkOverride 1002 null;
        "prefixes" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersNeighborsToReceive" = {

      options = {
        "allowed" = mkOption {
          description = "Allowed is the list of prefixes allowed to be received from\nthis neighbor.";
          type = (
            types.nullOr (
              submoduleOf "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersNeighborsToReceiveAllowed"
            )
          );
        };
      };

      config = {
        "allowed" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersNeighborsToReceiveAllowed" = {

      options = {
        "mode" = mkOption {
          description = "Mode is the mode to use when handling the prefixes.\nWhen set to \"filtered\", only the prefixes in the given list will be allowed.\nWhen set to \"all\", all the prefixes configured on the router will be allowed.";
          type = (types.nullOr types.str);
        };
        "prefixes" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersNeighborsToReceiveAllowedPrefixes"
              )
            )
          );
        };
      };

      config = {
        "mode" = mkOverride 1002 null;
        "prefixes" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecBgpRoutersNeighborsToReceiveAllowedPrefixes" = {

      options = {
        "ge" = mkOption {
          description = "The prefix length modifier. This selector accepts any matching prefix with length\ngreater or equal the given value.";
          type = (types.nullOr types.int);
        };
        "le" = mkOption {
          description = "The prefix length modifier. This selector accepts any matching prefix with length\nless or equal the given value.";
          type = (types.nullOr types.int);
        };
        "prefix" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "ge" = mkOverride 1002 null;
        "le" = mkOverride 1002 null;
        "prefix" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecNodeSelector" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecNodeSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecNodeSelectorMatchExpressions" = {

      options = {
        "key" = mkOption {
          description = "key is the label key that the selector applies to.";
          type = types.str;
        };
        "operator" = mkOption {
          description = "operator represents a key's relationship to a set of values.\nValid operators are In, NotIn, Exists and DoesNotExist.";
          type = types.str;
        };
        "values" = mkOption {
          description = "values is an array of string values. If the operator is In or NotIn,\nthe values array must be non-empty. If the operator is Exists or DoesNotExist,\nthe values array must be empty. This array is replaced during a strategic\nmerge patch.";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRConfigurationSpecRaw" = {

      options = {
        "priority" = mkOption {
          description = "Priority is the order with this configuration is appended to the\nbottom of the rendered configuration. A higher value means the\nraw config is appended later in the configuration file.";
          type = (types.nullOr types.int);
        };
        "rawConfig" = mkOption {
          description = "Config is a raw FRR configuration to be appended to the configuration\nrendered via the k8s api.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "priority" = mkOverride 1002 null;
        "rawConfig" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRK8sConfiguration" = {

      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = (types.nullOr types.str);
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = (types.nullOr types.str);
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = (types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta"));
        };
        "spec" = mkOption {
          description = "FRRK8sConfigurationSpec defines the desired state of FRRK8sConfiguration.";
          type = (types.nullOr (submoduleOf "frrk8s.metallb.io.v1beta1.FRRK8sConfigurationSpec"));
        };
        "status" = mkOption {
          description = "FRRK8sConfigurationStatus defines the observed state of FRRK8sConfiguration.";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRK8sConfigurationSpec" = {

      options = {
        "logLevel" = mkOption {
          description = "LogLevel sets the logging verbosity for the FRR-K8s components at runtime.\nWhen configured, this value overrides the defaults established by the --log-level CLI flag.\nValid values are: all, debug, info, warn, error, none.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "logLevel" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRNodeState" = {

      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = (types.nullOr types.str);
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = (types.nullOr types.str);
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = (types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta"));
        };
        "spec" = mkOption {
          description = "FRRNodeStateSpec defines the desired state of FRRNodeState.";
          type = (types.nullOr types.attrs);
        };
        "status" = mkOption {
          description = "FRRNodeStateStatus defines the observed state of FRRNodeState.";
          type = (types.nullOr (submoduleOf "frrk8s.metallb.io.v1beta1.FRRNodeStateStatus"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "frrk8s.metallb.io.v1beta1.FRRNodeStateStatus" = {

      options = {
        "lastConversionResult" = mkOption {
          description = "LastConversionResult is the status of the last translation between the `FRRConfiguration`s resources and FRR's configuration, contains \"success\" or an error.";
          type = (types.nullOr types.str);
        };
        "lastReloadResult" = mkOption {
          description = "LastReloadResult represents the status of the last configuration update operation by FRR, contains \"success\" or an error.";
          type = (types.nullOr types.str);
        };
        "runningConfig" = mkOption {
          description = "RunningConfig represents the current FRR running config, which is the configuration the FRR instance is currently running with.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "lastConversionResult" = mkOverride 1002 null;
        "lastReloadResult" = mkOverride 1002 null;
        "runningConfig" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.BFDProfile" = {

      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = (types.nullOr types.str);
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = (types.nullOr types.str);
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = (types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta"));
        };
        "spec" = mkOption {
          description = "BFDProfileSpec defines the desired state of BFDProfile.";
          type = (types.nullOr (submoduleOf "metallb.io.v1beta1.BFDProfileSpec"));
        };
        "status" = mkOption {
          description = "BFDProfileStatus defines the observed state of BFDProfile.";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.BFDProfileSpec" = {

      options = {
        "detectMultiplier" = mkOption {
          description = "Configures the detection multiplier to determine\npacket loss. The remote transmission interval will be multiplied\nby this value to determine the connection loss detection timer.";
          type = (types.nullOr types.int);
        };
        "echoInterval" = mkOption {
          description = "Configures the minimal echo receive transmission\ninterval that this system is capable of handling in milliseconds.\nDefaults to 50ms";
          type = (types.nullOr types.int);
        };
        "echoMode" = mkOption {
          description = "Enables or disables the echo transmission mode.\nThis mode is disabled by default, and not supported on multi\nhops setups.";
          type = (types.nullOr types.bool);
        };
        "minimumTtl" = mkOption {
          description = "For multi hop sessions only: configure the minimum\nexpected TTL for an incoming BFD control packet.";
          type = (types.nullOr types.int);
        };
        "passiveMode" = mkOption {
          description = "Mark session as passive: a passive session will not\nattempt to start the connection and will wait for control packets\nfrom peer before it begins replying.";
          type = (types.nullOr types.bool);
        };
        "receiveInterval" = mkOption {
          description = "The minimum interval that this system is capable of\nreceiving control packets in milliseconds.\nDefaults to 300ms.";
          type = (types.nullOr types.int);
        };
        "transmitInterval" = mkOption {
          description = "The minimum transmission interval (less jitter)\nthat this system wants to use to send BFD control packets in\nmilliseconds. Defaults to 300ms";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "detectMultiplier" = mkOverride 1002 null;
        "echoInterval" = mkOverride 1002 null;
        "echoMode" = mkOverride 1002 null;
        "minimumTtl" = mkOverride 1002 null;
        "passiveMode" = mkOverride 1002 null;
        "receiveInterval" = mkOverride 1002 null;
        "transmitInterval" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.BGPAdvertisement" = {

      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = (types.nullOr types.str);
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = (types.nullOr types.str);
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = (types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta"));
        };
        "spec" = mkOption {
          description = "BGPAdvertisementSpec defines the desired state of BGPAdvertisement.";
          type = (types.nullOr (submoduleOf "metallb.io.v1beta1.BGPAdvertisementSpec"));
        };
        "status" = mkOption {
          description = "BGPAdvertisementStatus defines the observed state of BGPAdvertisement.";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.BGPAdvertisementSpec" = {

      options = {
        "aggregationLength" = mkOption {
          description = "The aggregation-length advertisement option lets you “roll up” the /32s into a larger prefix. Defaults to 32. Works for IPv4 addresses.";
          type = (types.nullOr types.int);
        };
        "aggregationLengthV6" = mkOption {
          description = "The aggregation-length advertisement option lets you “roll up” the /128s into a larger prefix. Defaults to 128. Works for IPv6 addresses.";
          type = (types.nullOr types.int);
        };
        "communities" = mkOption {
          description = "The BGP communities to be associated with the announcement. Each item can be a standard community of the\nform 1234:1234, a large community of the form large:1234:1234:1234 or the name of an alias defined in the\nCommunity CRD.";
          type = (types.nullOr (types.listOf types.str));
        };
        "ipAddressPoolSelectors" = mkOption {
          description = "A selector for the IPAddressPools which would get advertised via this advertisement.\nIf no IPAddressPool is selected by this or by the list, the advertisement is applied to all the IPAddressPools.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "metallb.io.v1beta1.BGPAdvertisementSpecIpAddressPoolSelectors")
            )
          );
        };
        "ipAddressPools" = mkOption {
          description = "The list of IPAddressPools to advertise via this advertisement, selected by name.";
          type = (types.nullOr (types.listOf types.str));
        };
        "localPref" = mkOption {
          description = "The BGP LOCAL_PREF attribute which is used by BGP best path algorithm,\nPath with higher localpref is preferred over one with lower localpref.";
          type = (types.nullOr types.int);
        };
        "nodeSelectors" = mkOption {
          description = "NodeSelectors allows to limit the nodes to announce as next hops for the LoadBalancer IP. When empty, all the nodes having  are announced as next hops.";
          type = (
            types.nullOr (types.listOf (submoduleOf "metallb.io.v1beta1.BGPAdvertisementSpecNodeSelectors"))
          );
        };
        "peers" = mkOption {
          description = "Peers limits the bgppeer to advertise the ips of the selected pools to.\nWhen empty, the loadbalancer IP is announced to all the BGPPeers configured.";
          type = (types.nullOr (types.listOf types.str));
        };
        "serviceSelectors" = mkOption {
          description = "ServiceSelectors limits the set of services that will be advertised via this advertisement.\nIf empty, all services from the selected pools are advertised.\nThis field is mutually exclusive with aggregationLength and aggregationLengthV6 -\nservices can only be selected when using the default /32 (IPv4) or /128 (IPv6) aggregation.";
          type = (
            types.nullOr (types.listOf (submoduleOf "metallb.io.v1beta1.BGPAdvertisementSpecServiceSelectors"))
          );
        };
      };

      config = {
        "aggregationLength" = mkOverride 1002 null;
        "aggregationLengthV6" = mkOverride 1002 null;
        "communities" = mkOverride 1002 null;
        "ipAddressPoolSelectors" = mkOverride 1002 null;
        "ipAddressPools" = mkOverride 1002 null;
        "localPref" = mkOverride 1002 null;
        "nodeSelectors" = mkOverride 1002 null;
        "peers" = mkOverride 1002 null;
        "serviceSelectors" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.BGPAdvertisementSpecIpAddressPoolSelectors" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "metallb.io.v1beta1.BGPAdvertisementSpecIpAddressPoolSelectorsMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.BGPAdvertisementSpecIpAddressPoolSelectorsMatchExpressions" = {

      options = {
        "key" = mkOption {
          description = "key is the label key that the selector applies to.";
          type = types.str;
        };
        "operator" = mkOption {
          description = "operator represents a key's relationship to a set of values.\nValid operators are In, NotIn, Exists and DoesNotExist.";
          type = types.str;
        };
        "values" = mkOption {
          description = "values is an array of string values. If the operator is In or NotIn,\nthe values array must be non-empty. If the operator is Exists or DoesNotExist,\nthe values array must be empty. This array is replaced during a strategic\nmerge patch.";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.BGPAdvertisementSpecNodeSelectors" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "metallb.io.v1beta1.BGPAdvertisementSpecNodeSelectorsMatchExpressions")
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.BGPAdvertisementSpecNodeSelectorsMatchExpressions" = {

      options = {
        "key" = mkOption {
          description = "key is the label key that the selector applies to.";
          type = types.str;
        };
        "operator" = mkOption {
          description = "operator represents a key's relationship to a set of values.\nValid operators are In, NotIn, Exists and DoesNotExist.";
          type = types.str;
        };
        "values" = mkOption {
          description = "values is an array of string values. If the operator is In or NotIn,\nthe values array must be non-empty. If the operator is Exists or DoesNotExist,\nthe values array must be empty. This array is replaced during a strategic\nmerge patch.";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.BGPAdvertisementSpecServiceSelectors" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "metallb.io.v1beta1.BGPAdvertisementSpecServiceSelectorsMatchExpressions")
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.BGPAdvertisementSpecServiceSelectorsMatchExpressions" = {

      options = {
        "key" = mkOption {
          description = "key is the label key that the selector applies to.";
          type = types.str;
        };
        "operator" = mkOption {
          description = "operator represents a key's relationship to a set of values.\nValid operators are In, NotIn, Exists and DoesNotExist.";
          type = types.str;
        };
        "values" = mkOption {
          description = "values is an array of string values. If the operator is In or NotIn,\nthe values array must be non-empty. If the operator is Exists or DoesNotExist,\nthe values array must be empty. This array is replaced during a strategic\nmerge patch.";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.Community" = {

      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = (types.nullOr types.str);
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = (types.nullOr types.str);
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = (types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta"));
        };
        "spec" = mkOption {
          description = "CommunitySpec defines the desired state of Community.";
          type = (types.nullOr (submoduleOf "metallb.io.v1beta1.CommunitySpec"));
        };
        "status" = mkOption {
          description = "CommunityStatus defines the observed state of Community.";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.CommunitySpec" = {

      options = {
        "communities" = mkOption {
          description = "";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "metallb.io.v1beta1.CommunitySpecCommunities" "name" [ ]
            )
          );
          apply = attrsToList;
        };
      };

      config = {
        "communities" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.CommunitySpecCommunities" = {

      options = {
        "name" = mkOption {
          description = "The name of the alias for the community.";
          type = (types.nullOr types.str);
        };
        "value" = mkOption {
          description = "The BGP community value corresponding to the given name. Can be a standard community of the form 1234:1234\nor a large community of the form large:1234:1234:1234.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "value" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.ConfigurationState" = {

      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = (types.nullOr types.str);
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = (types.nullOr types.str);
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = (types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta"));
        };
        "status" = mkOption {
          description = "ConfigurationStateStatus defines the observed state of ConfigurationState.";
          type = (types.nullOr (submoduleOf "metallb.io.v1beta1.ConfigurationStateStatus"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.ConfigurationStateStatus" = {

      options = {
        "conditions" = mkOption {
          description = "Conditions contains the status conditions from the reconcilers running in this component.";
          type = (
            types.nullOr (types.listOf (submoduleOf "metallb.io.v1beta1.ConfigurationStateStatusConditions"))
          );
        };
        "errorSummary" = mkOption {
          description = "ErrorSummary contains the aggregated error messages from reconciliation failures.\nThis field is empty when Result is \"Valid\".";
          type = (types.nullOr types.str);
        };
        "result" = mkOption {
          description = "Result indicates the configuration validation result.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "conditions" = mkOverride 1002 null;
        "errorSummary" = mkOverride 1002 null;
        "result" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.ConfigurationStateStatusConditions" = {

      options = {
        "lastTransitionTime" = mkOption {
          description = "lastTransitionTime is the last time the condition transitioned from one status to another.\nThis should be when the underlying condition changed.  If that is not known, then using the time when the API field changed is acceptable.";
          type = types.str;
        };
        "message" = mkOption {
          description = "message is a human readable message indicating details about the transition.\nThis may be an empty string.";
          type = types.str;
        };
        "observedGeneration" = mkOption {
          description = "observedGeneration represents the .metadata.generation that the condition was set based upon.\nFor instance, if .metadata.generation is currently 12, but the .status.conditions[x].observedGeneration is 9, the condition is out of date\nwith respect to the current state of the instance.";
          type = (types.nullOr types.int);
        };
        "reason" = mkOption {
          description = "reason contains a programmatic identifier indicating the reason for the condition's last transition.\nProducers of specific condition types may define expected values and meanings for this field,\nand whether the values are considered a guaranteed API.\nThe value should be a CamelCase string.\nThis field may not be empty.";
          type = types.str;
        };
        "status" = mkOption {
          description = "status of the condition, one of True, False, Unknown.";
          type = types.str;
        };
        "type" = mkOption {
          description = "type of condition in CamelCase or in foo.example.com/CamelCase.";
          type = types.str;
        };
      };

      config = {
        "observedGeneration" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.IPAddressPool" = {

      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = (types.nullOr types.str);
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = (types.nullOr types.str);
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = (types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta"));
        };
        "spec" = mkOption {
          description = "IPAddressPoolSpec defines the desired state of IPAddressPool.";
          type = (submoduleOf "metallb.io.v1beta1.IPAddressPoolSpec");
        };
        "status" = mkOption {
          description = "IPAddressPoolStatus defines the observed state of IPAddressPool.";
          type = (types.nullOr (submoduleOf "metallb.io.v1beta1.IPAddressPoolStatus"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.IPAddressPoolSpec" = {

      options = {
        "addresses" = mkOption {
          description = "A list of IP address ranges over which MetalLB has authority.\nYou can list multiple ranges in a single pool, they will all share the\nsame settings. Each range can be either a CIDR prefix, or an explicit\nstart-end range of IPs.";
          type = (types.listOf types.str);
        };
        "autoAssign" = mkOption {
          description = "AutoAssign flag used to prevent MetallB from automatic allocation\nfor a pool.";
          type = (types.nullOr types.bool);
        };
        "avoidBuggyIPs" = mkOption {
          description = "AvoidBuggyIPs prevents addresses ending with .0 and .255\nto be used by a pool.";
          type = (types.nullOr types.bool);
        };
        "serviceAllocation" = mkOption {
          description = "AllocateTo makes ip pool allocation to specific namespace and/or service.\nThe controller will use the pool with lowest value of priority in case of\nmultiple matches. A pool with no priority set will be used only if the\npools with priority can't be used. If multiple matching IPAddressPools are\navailable it will check for the availability of IPs sorting the matching\nIPAddressPools by priority, starting from the highest to the lowest. If\nmultiple IPAddressPools have the same priority, choice will be random.";
          type = (types.nullOr (submoduleOf "metallb.io.v1beta1.IPAddressPoolSpecServiceAllocation"));
        };
      };

      config = {
        "autoAssign" = mkOverride 1002 null;
        "avoidBuggyIPs" = mkOverride 1002 null;
        "serviceAllocation" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.IPAddressPoolSpecServiceAllocation" = {

      options = {
        "namespaceSelectors" = mkOption {
          description = "NamespaceSelectors list of label selectors to select namespace(s) for ip pool,\nan alternative to using namespace list.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "metallb.io.v1beta1.IPAddressPoolSpecServiceAllocationNamespaceSelectors")
            )
          );
        };
        "namespaces" = mkOption {
          description = "Namespaces list of namespace(s) on which ip pool can be attached.";
          type = (types.nullOr (types.listOf types.str));
        };
        "priority" = mkOption {
          description = "Priority priority given for ip pool while ip allocation on a service.";
          type = (types.nullOr types.int);
        };
        "serviceSelectors" = mkOption {
          description = "ServiceSelectors list of label selector to select service(s) for which ip pool\ncan be used for ip allocation.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "metallb.io.v1beta1.IPAddressPoolSpecServiceAllocationServiceSelectors")
            )
          );
        };
      };

      config = {
        "namespaceSelectors" = mkOverride 1002 null;
        "namespaces" = mkOverride 1002 null;
        "priority" = mkOverride 1002 null;
        "serviceSelectors" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.IPAddressPoolSpecServiceAllocationNamespaceSelectors" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "metallb.io.v1beta1.IPAddressPoolSpecServiceAllocationNamespaceSelectorsMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.IPAddressPoolSpecServiceAllocationNamespaceSelectorsMatchExpressions" = {

      options = {
        "key" = mkOption {
          description = "key is the label key that the selector applies to.";
          type = types.str;
        };
        "operator" = mkOption {
          description = "operator represents a key's relationship to a set of values.\nValid operators are In, NotIn, Exists and DoesNotExist.";
          type = types.str;
        };
        "values" = mkOption {
          description = "values is an array of string values. If the operator is In or NotIn,\nthe values array must be non-empty. If the operator is Exists or DoesNotExist,\nthe values array must be empty. This array is replaced during a strategic\nmerge patch.";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.IPAddressPoolSpecServiceAllocationServiceSelectors" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "metallb.io.v1beta1.IPAddressPoolSpecServiceAllocationServiceSelectorsMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.IPAddressPoolSpecServiceAllocationServiceSelectorsMatchExpressions" = {

      options = {
        "key" = mkOption {
          description = "key is the label key that the selector applies to.";
          type = types.str;
        };
        "operator" = mkOption {
          description = "operator represents a key's relationship to a set of values.\nValid operators are In, NotIn, Exists and DoesNotExist.";
          type = types.str;
        };
        "values" = mkOption {
          description = "values is an array of string values. If the operator is In or NotIn,\nthe values array must be non-empty. If the operator is Exists or DoesNotExist,\nthe values array must be empty. This array is replaced during a strategic\nmerge patch.";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.IPAddressPoolStatus" = {

      options = {
        "assignedIPv4" = mkOption {
          description = "AssignedIPv4 is the number of assigned IPv4 addresses.";
          type = types.int;
        };
        "assignedIPv6" = mkOption {
          description = "AssignedIPv6 is the number of assigned IPv6 addresses.";
          type = types.int;
        };
        "availableIPv4" = mkOption {
          description = "AvailableIPv4 is the number of available IPv4 addresses.";
          type = types.int;
        };
        "availableIPv6" = mkOption {
          description = "AvailableIPv6 is the number of available IPv6 addresses.";
          type = types.int;
        };
      };

      config = { };

    };
    "metallb.io.v1beta1.L2Advertisement" = {

      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = (types.nullOr types.str);
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = (types.nullOr types.str);
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = (types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta"));
        };
        "spec" = mkOption {
          description = "L2AdvertisementSpec defines the desired state of L2Advertisement.";
          type = (types.nullOr (submoduleOf "metallb.io.v1beta1.L2AdvertisementSpec"));
        };
        "status" = mkOption {
          description = "L2AdvertisementStatus defines the observed state of L2Advertisement.";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.L2AdvertisementSpec" = {

      options = {
        "interfaces" = mkOption {
          description = "A list of interfaces to announce from. The LB IP will be announced only from these interfaces.\nIf the field is not set, we advertise from all the interfaces on the host.";
          type = (types.nullOr (types.listOf types.str));
        };
        "ipAddressPoolSelectors" = mkOption {
          description = "A selector for the IPAddressPools which would get advertised via this advertisement.\nIf no IPAddressPool is selected by this or by the list, the advertisement is applied to all the IPAddressPools.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "metallb.io.v1beta1.L2AdvertisementSpecIpAddressPoolSelectors")
            )
          );
        };
        "ipAddressPools" = mkOption {
          description = "The list of IPAddressPools to advertise via this advertisement, selected by name.";
          type = (types.nullOr (types.listOf types.str));
        };
        "nodeSelectors" = mkOption {
          description = "NodeSelectors allows to limit the nodes to announce as next hops for the LoadBalancer IP. When empty, all the nodes having  are announced as next hops.";
          type = (
            types.nullOr (types.listOf (submoduleOf "metallb.io.v1beta1.L2AdvertisementSpecNodeSelectors"))
          );
        };
        "serviceSelectors" = mkOption {
          description = "ServiceSelectors limits the set of services that will be advertised via this advertisement.\nIf empty, all services from the selected pools are advertised.";
          type = (
            types.nullOr (types.listOf (submoduleOf "metallb.io.v1beta1.L2AdvertisementSpecServiceSelectors"))
          );
        };
      };

      config = {
        "interfaces" = mkOverride 1002 null;
        "ipAddressPoolSelectors" = mkOverride 1002 null;
        "ipAddressPools" = mkOverride 1002 null;
        "nodeSelectors" = mkOverride 1002 null;
        "serviceSelectors" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.L2AdvertisementSpecIpAddressPoolSelectors" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "metallb.io.v1beta1.L2AdvertisementSpecIpAddressPoolSelectorsMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.L2AdvertisementSpecIpAddressPoolSelectorsMatchExpressions" = {

      options = {
        "key" = mkOption {
          description = "key is the label key that the selector applies to.";
          type = types.str;
        };
        "operator" = mkOption {
          description = "operator represents a key's relationship to a set of values.\nValid operators are In, NotIn, Exists and DoesNotExist.";
          type = types.str;
        };
        "values" = mkOption {
          description = "values is an array of string values. If the operator is In or NotIn,\nthe values array must be non-empty. If the operator is Exists or DoesNotExist,\nthe values array must be empty. This array is replaced during a strategic\nmerge patch.";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.L2AdvertisementSpecNodeSelectors" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "metallb.io.v1beta1.L2AdvertisementSpecNodeSelectorsMatchExpressions")
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.L2AdvertisementSpecNodeSelectorsMatchExpressions" = {

      options = {
        "key" = mkOption {
          description = "key is the label key that the selector applies to.";
          type = types.str;
        };
        "operator" = mkOption {
          description = "operator represents a key's relationship to a set of values.\nValid operators are In, NotIn, Exists and DoesNotExist.";
          type = types.str;
        };
        "values" = mkOption {
          description = "values is an array of string values. If the operator is In or NotIn,\nthe values array must be non-empty. If the operator is Exists or DoesNotExist,\nthe values array must be empty. This array is replaced during a strategic\nmerge patch.";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.L2AdvertisementSpecServiceSelectors" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "metallb.io.v1beta1.L2AdvertisementSpecServiceSelectorsMatchExpressions")
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.L2AdvertisementSpecServiceSelectorsMatchExpressions" = {

      options = {
        "key" = mkOption {
          description = "key is the label key that the selector applies to.";
          type = types.str;
        };
        "operator" = mkOption {
          description = "operator represents a key's relationship to a set of values.\nValid operators are In, NotIn, Exists and DoesNotExist.";
          type = types.str;
        };
        "values" = mkOption {
          description = "values is an array of string values. If the operator is In or NotIn,\nthe values array must be non-empty. If the operator is Exists or DoesNotExist,\nthe values array must be empty. This array is replaced during a strategic\nmerge patch.";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.ServiceBGPStatus" = {

      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = (types.nullOr types.str);
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = (types.nullOr types.str);
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = (types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta"));
        };
        "spec" = mkOption {
          description = "ServiceBGPStatusSpec defines the desired state of ServiceBGPStatus.";
          type = (types.nullOr types.attrs);
        };
        "status" = mkOption {
          description = "MetalLBServiceBGPStatus defines the observed state of ServiceBGPStatus.";
          type = (types.nullOr (submoduleOf "metallb.io.v1beta1.ServiceBGPStatusStatus"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.ServiceBGPStatusStatus" = {

      options = {
        "node" = mkOption {
          description = "Node indicates the node announcing the service.";
          type = (types.nullOr types.str);
        };
        "peers" = mkOption {
          description = "Peers indicate the BGP peers for which the service is configured to be advertised to.\nThe service being actually advertised to a given peer depends on the session state and is not indicated here.";
          type = (types.nullOr (types.listOf types.str));
        };
        "serviceName" = mkOption {
          description = "ServiceName indicates the service this status represents.";
          type = (types.nullOr types.str);
        };
        "serviceNamespace" = mkOption {
          description = "ServiceNamespace indicates the namespace of the service.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "node" = mkOverride 1002 null;
        "peers" = mkOverride 1002 null;
        "serviceName" = mkOverride 1002 null;
        "serviceNamespace" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.ServiceL2Status" = {

      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = (types.nullOr types.str);
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = (types.nullOr types.str);
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = (types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta"));
        };
        "spec" = mkOption {
          description = "ServiceL2StatusSpec defines the desired state of ServiceL2Status.";
          type = (types.nullOr types.attrs);
        };
        "status" = mkOption {
          description = "MetalLBServiceL2Status defines the observed state of ServiceL2Status.";
          type = (types.nullOr (submoduleOf "metallb.io.v1beta1.ServiceL2StatusStatus"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.ServiceL2StatusStatus" = {

      options = {
        "interfaces" = mkOption {
          description = "Interfaces indicates the interfaces that receive the directed traffic";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "metallb.io.v1beta1.ServiceL2StatusStatusInterfaces" "name" [ ]
            )
          );
          apply = attrsToList;
        };
        "node" = mkOption {
          description = "Node indicates the node that receives the directed traffic";
          type = (types.nullOr types.str);
        };
        "serviceName" = mkOption {
          description = "ServiceName indicates the service this status represents";
          type = (types.nullOr types.str);
        };
        "serviceNamespace" = mkOption {
          description = "ServiceNamespace indicates the namespace of the service";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "interfaces" = mkOverride 1002 null;
        "node" = mkOverride 1002 null;
        "serviceName" = mkOverride 1002 null;
        "serviceNamespace" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta1.ServiceL2StatusStatusInterfaces" = {

      options = {
        "name" = mkOption {
          description = "Name the name of network interface card";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta2.BGPPeer" = {

      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = (types.nullOr types.str);
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = (types.nullOr types.str);
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = (types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta"));
        };
        "spec" = mkOption {
          description = "BGPPeerSpec defines the desired state of Peer.";
          type = (types.nullOr (submoduleOf "metallb.io.v1beta2.BGPPeerSpec"));
        };
        "status" = mkOption {
          description = "BGPPeerStatus defines the observed state of Peer.";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta2.BGPPeerSpec" = {

      options = {
        "bfdProfile" = mkOption {
          description = "The name of the BFD Profile to be used for the BFD session associated to the BGP session. If not set, the BFD session won't be set up.";
          type = (types.nullOr types.str);
        };
        "connectTime" = mkOption {
          description = "Requested BGP connect time, controls how long BGP waits between connection attempts to a neighbor.";
          type = (types.nullOr types.str);
        };
        "disableMP" = mkOption {
          description = "To set if we want to disable MP BGP that will separate IPv4 and IPv6 route exchanges into distinct BGP sessions.\nDeprecated: DisableMP is deprecated in favor of dualStackAddressFamily.";
          type = (types.nullOr types.bool);
        };
        "dualStackAddressFamily" = mkOption {
          description = "To set if we want to enable the neighbor not only for the ipfamily related to its session,\nbut also the other one. This allows to advertise/receive IPv4 prefixes over IPv6 sessions and vice versa.";
          type = (types.nullOr types.bool);
        };
        "dynamicASN" = mkOption {
          description = "DynamicASN detects the AS number to use for the remote end of the session\nwithout explicitly setting it via the ASN field. Limited to:\ninternal - if the neighbor's ASN is different than MyASN connection is denied.\nexternal - if the neighbor's ASN is the same as MyASN the connection is denied.\nASN and DynamicASN are mutually exclusive and one of them must be specified.";
          type = (types.nullOr types.str);
        };
        "ebgpMultiHop" = mkOption {
          description = "To set if the BGPPeer is multi-hops away. Needed for FRR-based modes (FRR-K8s, FRR) only.";
          type = (types.nullOr types.bool);
        };
        "enableGracefulRestart" = mkOption {
          description = "EnableGracefulRestart allows BGP peer to continue to forward data packets\nalong known routes while the routing protocol information is being\nrestored. This field is immutable because it requires restart of the BGP\nsession. Supported for FRR-based modes (FRR-K8s, FRR) only.";
          type = (types.nullOr types.bool);
        };
        "holdTime" = mkOption {
          description = "Requested BGP hold time, per RFC4271.";
          type = (types.nullOr types.str);
        };
        "interface" = mkOption {
          description = "Interface is the node interface over which the unnumbered BGP peering will\nbe established. No API validation takes place as that string value\nrepresents an interface name on the host and if user provides an invalid\nvalue, only the actual BGP session will not be established.\nAddress and Interface are mutually exclusive and one of them must be specified.";
          type = (types.nullOr types.str);
        };
        "keepaliveTime" = mkOption {
          description = "Requested BGP keepalive time, per RFC4271.";
          type = (types.nullOr types.str);
        };
        "localASN" = mkOption {
          description = "LocalASN allows advertising a different AS number to the peer using BGP's\nlocal-as feature. When set, MetalLB will advertise this ASN to the peer\nvia \"neighbor <peer> local-as <ASN> no-prepend replace-as\", overriding\nthe router-level MyASN for this specific session.\nNot supported in native BGP mode.";
          type = (types.nullOr types.int);
        };
        "myASN" = mkOption {
          description = "AS number to use for the local end of the session.";
          type = types.int;
        };
        "nodeSelectors" = mkOption {
          description = "Only connect to this peer on nodes that match one of these\nselectors.";
          type = (types.nullOr (types.listOf (submoduleOf "metallb.io.v1beta2.BGPPeerSpecNodeSelectors")));
        };
        "password" = mkOption {
          description = "Authentication password for routers enforcing TCP MD5 authenticated sessions";
          type = (types.nullOr types.str);
        };
        "passwordSecret" = mkOption {
          description = "passwordSecret is name of the authentication secret for BGP Peer.\nthe secret must be of type \"kubernetes.io/basic-auth\", and created in the\nsame namespace as the MetalLB deployment. The password is stored in the\nsecret as the key \"password\".";
          type = (types.nullOr (submoduleOf "metallb.io.v1beta2.BGPPeerSpecPasswordSecret"));
        };
        "peerASN" = mkOption {
          description = "AS number to expect from the remote end of the session.\nASN and DynamicASN are mutually exclusive and one of them must be specified.";
          type = (types.nullOr types.int);
        };
        "peerAddress" = mkOption {
          description = "Address to dial when establishing the session.";
          type = (types.nullOr types.str);
        };
        "peerPort" = mkOption {
          description = "Port to dial when establishing the session.";
          type = (types.nullOr types.int);
        };
        "routerID" = mkOption {
          description = "BGP router ID to advertise to the peer";
          type = (types.nullOr types.str);
        };
        "sourceAddress" = mkOption {
          description = "Source address to use when establishing the session.";
          type = (types.nullOr types.str);
        };
        "vrf" = mkOption {
          description = "To set if we want to peer with the BGPPeer using an interface belonging to\na host vrf";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "bfdProfile" = mkOverride 1002 null;
        "connectTime" = mkOverride 1002 null;
        "disableMP" = mkOverride 1002 null;
        "dualStackAddressFamily" = mkOverride 1002 null;
        "dynamicASN" = mkOverride 1002 null;
        "ebgpMultiHop" = mkOverride 1002 null;
        "enableGracefulRestart" = mkOverride 1002 null;
        "holdTime" = mkOverride 1002 null;
        "interface" = mkOverride 1002 null;
        "keepaliveTime" = mkOverride 1002 null;
        "localASN" = mkOverride 1002 null;
        "nodeSelectors" = mkOverride 1002 null;
        "password" = mkOverride 1002 null;
        "passwordSecret" = mkOverride 1002 null;
        "peerASN" = mkOverride 1002 null;
        "peerAddress" = mkOverride 1002 null;
        "peerPort" = mkOverride 1002 null;
        "routerID" = mkOverride 1002 null;
        "sourceAddress" = mkOverride 1002 null;
        "vrf" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta2.BGPPeerSpecNodeSelectors" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "metallb.io.v1beta2.BGPPeerSpecNodeSelectorsMatchExpressions")
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta2.BGPPeerSpecNodeSelectorsMatchExpressions" = {

      options = {
        "key" = mkOption {
          description = "key is the label key that the selector applies to.";
          type = types.str;
        };
        "operator" = mkOption {
          description = "operator represents a key's relationship to a set of values.\nValid operators are In, NotIn, Exists and DoesNotExist.";
          type = types.str;
        };
        "values" = mkOption {
          description = "values is an array of string values. If the operator is In or NotIn,\nthe values array must be non-empty. If the operator is Exists or DoesNotExist,\nthe values array must be empty. This array is replaced during a strategic\nmerge patch.";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };

    };
    "metallb.io.v1beta2.BGPPeerSpecPasswordSecret" = {

      options = {
        "name" = mkOption {
          description = "name is unique within a namespace to reference a secret resource.";
          type = (types.nullOr types.str);
        };
        "namespace" = mkOption {
          description = "namespace defines the space within which the secret name must be unique.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };

  };
in
{
  # all resource versions
  options = {
    resources = {
      "frrk8s.metallb.io"."v1beta1"."BGPSessionState" = mkOption {
        description = "BGPSessionState exposes the status of a BGP Session from the FRR instance running on the node.";
        type = (
          types.attrsOf (
            submoduleForDefinition "frrk8s.metallb.io.v1beta1.BGPSessionState" "bgpsessionstates"
              "BGPSessionState"
              "frrk8s.metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "frrk8s.metallb.io"."v1beta1"."FRRConfiguration" = mkOption {
        description = "FRRConfiguration is a piece of FRR configuration.";
        type = (
          types.attrsOf (
            submoduleForDefinition "frrk8s.metallb.io.v1beta1.FRRConfiguration" "frrconfigurations"
              "FRRConfiguration"
              "frrk8s.metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "frrk8s.metallb.io"."v1beta1"."FRRK8sConfiguration" = mkOption {
        description = "FRRK8sConfiguration holds the FRR Operator configuration with global\nsettings for the K8s and FRR.";
        type = (
          types.attrsOf (
            submoduleForDefinition "frrk8s.metallb.io.v1beta1.FRRK8sConfiguration" "frrk8sconfigurations"
              "FRRK8sConfiguration"
              "frrk8s.metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "frrk8s.metallb.io"."v1beta1"."FRRNodeState" = mkOption {
        description = "FRRNodeState exposes the status of the FRR instance running on each node.";
        type = (
          types.attrsOf (
            submoduleForDefinition "frrk8s.metallb.io.v1beta1.FRRNodeState" "frrnodestates" "FRRNodeState"
              "frrk8s.metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "metallb.io"."v1beta1"."BFDProfile" = mkOption {
        description = "BFDProfile represents the settings of the bfd session that can be\noptionally associated with a BGP session.";
        type = (
          types.attrsOf (
            submoduleForDefinition "metallb.io.v1beta1.BFDProfile" "bfdprofiles" "BFDProfile" "metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "metallb.io"."v1beta1"."BGPAdvertisement" = mkOption {
        description = "BGPAdvertisement allows to advertise the IPs coming\nfrom the selected IPAddressPools via BGP, setting the parameters of the\nBGP Advertisement.";
        type = (
          types.attrsOf (
            submoduleForDefinition "metallb.io.v1beta1.BGPAdvertisement" "bgpadvertisements" "BGPAdvertisement"
              "metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "metallb.io"."v1beta1"."Community" = mkOption {
        description = "Community is a collection of aliases for communities.\nUsers can define named aliases to be used in the BGPPeer CRD.";
        type = (
          types.attrsOf (
            submoduleForDefinition "metallb.io.v1beta1.Community" "communities" "Community" "metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "metallb.io"."v1beta1"."ConfigurationState" = mkOption {
        description = "ConfigurationState is a status-only CRD that reports configuration validation results from MetalLB components.\nLabels:\n  - metallb.io/component-type: \"controller\" or \"speaker\"\n  - metallb.io/node-name: node name (only for speaker)";
        type = (
          types.attrsOf (
            submoduleForDefinition "metallb.io.v1beta1.ConfigurationState" "configurationstates"
              "ConfigurationState"
              "metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "metallb.io"."v1beta1"."IPAddressPool" = mkOption {
        description = "IPAddressPool represents a pool of IP addresses that can be allocated\nto LoadBalancer services.";
        type = (
          types.attrsOf (
            submoduleForDefinition "metallb.io.v1beta1.IPAddressPool" "ipaddresspools" "IPAddressPool"
              "metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "metallb.io"."v1beta1"."L2Advertisement" = mkOption {
        description = "L2Advertisement allows to advertise the LoadBalancer IPs provided\nby the selected pools via L2.";
        type = (
          types.attrsOf (
            submoduleForDefinition "metallb.io.v1beta1.L2Advertisement" "l2advertisements" "L2Advertisement"
              "metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "metallb.io"."v1beta1"."ServiceBGPStatus" = mkOption {
        description = "ServiceBGPStatus exposes the BGP peers a service is configured to be advertised to, per relevant node.";
        type = (
          types.attrsOf (
            submoduleForDefinition "metallb.io.v1beta1.ServiceBGPStatus" "servicebgpstatuses" "ServiceBGPStatus"
              "metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "metallb.io"."v1beta1"."ServiceL2Status" = mkOption {
        description = "ServiceL2Status reveals the actual traffic status of loadbalancer services in layer2 mode.";
        type = (
          types.attrsOf (
            submoduleForDefinition "metallb.io.v1beta1.ServiceL2Status" "servicel2statuses" "ServiceL2Status"
              "metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "metallb.io"."v1beta2"."BGPPeer" = mkOption {
        description = "BGPPeer is the Schema for the peers API.";
        type = (
          types.attrsOf (
            submoduleForDefinition "metallb.io.v1beta2.BGPPeer" "bgppeers" "BGPPeer" "metallb.io" "v1beta2"
          )
        );
        default = { };
      };

    }
    // {
      "bfdProfiles" = mkOption {
        description = "BFDProfile represents the settings of the bfd session that can be\noptionally associated with a BGP session.";
        type = (
          types.attrsOf (
            submoduleForDefinition "metallb.io.v1beta1.BFDProfile" "bfdprofiles" "BFDProfile" "metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "bgpAdvertisements" = mkOption {
        description = "BGPAdvertisement allows to advertise the IPs coming\nfrom the selected IPAddressPools via BGP, setting the parameters of the\nBGP Advertisement.";
        type = (
          types.attrsOf (
            submoduleForDefinition "metallb.io.v1beta1.BGPAdvertisement" "bgpadvertisements" "BGPAdvertisement"
              "metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "bgpPeers" = mkOption {
        description = "BGPPeer is the Schema for the peers API.";
        type = (
          types.attrsOf (
            submoduleForDefinition "metallb.io.v1beta2.BGPPeer" "bgppeers" "BGPPeer" "metallb.io" "v1beta2"
          )
        );
        default = { };
      };
      "bgpSessionStates" = mkOption {
        description = "BGPSessionState exposes the status of a BGP Session from the FRR instance running on the node.";
        type = (
          types.attrsOf (
            submoduleForDefinition "frrk8s.metallb.io.v1beta1.BGPSessionState" "bgpsessionstates"
              "BGPSessionState"
              "frrk8s.metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "communities" = mkOption {
        description = "Community is a collection of aliases for communities.\nUsers can define named aliases to be used in the BGPPeer CRD.";
        type = (
          types.attrsOf (
            submoduleForDefinition "metallb.io.v1beta1.Community" "communities" "Community" "metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "configurationStates" = mkOption {
        description = "ConfigurationState is a status-only CRD that reports configuration validation results from MetalLB components.\nLabels:\n  - metallb.io/component-type: \"controller\" or \"speaker\"\n  - metallb.io/node-name: node name (only for speaker)";
        type = (
          types.attrsOf (
            submoduleForDefinition "metallb.io.v1beta1.ConfigurationState" "configurationstates"
              "ConfigurationState"
              "metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "frrConfigurations" = mkOption {
        description = "FRRConfiguration is a piece of FRR configuration.";
        type = (
          types.attrsOf (
            submoduleForDefinition "frrk8s.metallb.io.v1beta1.FRRConfiguration" "frrconfigurations"
              "FRRConfiguration"
              "frrk8s.metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "fRRK8sConfigurations" = mkOption {
        description = "FRRK8sConfiguration holds the FRR Operator configuration with global\nsettings for the K8s and FRR.";
        type = (
          types.attrsOf (
            submoduleForDefinition "frrk8s.metallb.io.v1beta1.FRRK8sConfiguration" "frrk8sconfigurations"
              "FRRK8sConfiguration"
              "frrk8s.metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "frrNodeStates" = mkOption {
        description = "FRRNodeState exposes the status of the FRR instance running on each node.";
        type = (
          types.attrsOf (
            submoduleForDefinition "frrk8s.metallb.io.v1beta1.FRRNodeState" "frrnodestates" "FRRNodeState"
              "frrk8s.metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "ipAddressPools" = mkOption {
        description = "IPAddressPool represents a pool of IP addresses that can be allocated\nto LoadBalancer services.";
        type = (
          types.attrsOf (
            submoduleForDefinition "metallb.io.v1beta1.IPAddressPool" "ipaddresspools" "IPAddressPool"
              "metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "l2Advertisements" = mkOption {
        description = "L2Advertisement allows to advertise the LoadBalancer IPs provided\nby the selected pools via L2.";
        type = (
          types.attrsOf (
            submoduleForDefinition "metallb.io.v1beta1.L2Advertisement" "l2advertisements" "L2Advertisement"
              "metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "serviceBGPStatuses" = mkOption {
        description = "ServiceBGPStatus exposes the BGP peers a service is configured to be advertised to, per relevant node.";
        type = (
          types.attrsOf (
            submoduleForDefinition "metallb.io.v1beta1.ServiceBGPStatus" "servicebgpstatuses" "ServiceBGPStatus"
              "metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };
      "serviceL2Statuses" = mkOption {
        description = "ServiceL2Status reveals the actual traffic status of loadbalancer services in layer2 mode.";
        type = (
          types.attrsOf (
            submoduleForDefinition "metallb.io.v1beta1.ServiceL2Status" "servicel2statuses" "ServiceL2Status"
              "metallb.io"
              "v1beta1"
          )
        );
        default = { };
      };

    };
  };

  config = {
    # expose resource definitions
    inherit definitions;

    # register resource types
    types = [
      {
        name = "bgpsessionstates";
        group = "frrk8s.metallb.io";
        version = "v1beta1";
        kind = "BGPSessionState";
        attrName = "bgpSessionStates";
      }
      {
        name = "frrconfigurations";
        group = "frrk8s.metallb.io";
        version = "v1beta1";
        kind = "FRRConfiguration";
        attrName = "frrConfigurations";
      }
      {
        name = "frrk8sconfigurations";
        group = "frrk8s.metallb.io";
        version = "v1beta1";
        kind = "FRRK8sConfiguration";
        attrName = "fRRK8sConfigurations";
      }
      {
        name = "frrnodestates";
        group = "frrk8s.metallb.io";
        version = "v1beta1";
        kind = "FRRNodeState";
        attrName = "frrNodeStates";
      }
      {
        name = "bfdprofiles";
        group = "metallb.io";
        version = "v1beta1";
        kind = "BFDProfile";
        attrName = "bfdProfiles";
      }
      {
        name = "bgpadvertisements";
        group = "metallb.io";
        version = "v1beta1";
        kind = "BGPAdvertisement";
        attrName = "bgpAdvertisements";
      }
      {
        name = "communities";
        group = "metallb.io";
        version = "v1beta1";
        kind = "Community";
        attrName = "communities";
      }
      {
        name = "configurationstates";
        group = "metallb.io";
        version = "v1beta1";
        kind = "ConfigurationState";
        attrName = "configurationStates";
      }
      {
        name = "ipaddresspools";
        group = "metallb.io";
        version = "v1beta1";
        kind = "IPAddressPool";
        attrName = "ipAddressPools";
      }
      {
        name = "l2advertisements";
        group = "metallb.io";
        version = "v1beta1";
        kind = "L2Advertisement";
        attrName = "l2Advertisements";
      }
      {
        name = "servicebgpstatuses";
        group = "metallb.io";
        version = "v1beta1";
        kind = "ServiceBGPStatus";
        attrName = "serviceBGPStatuses";
      }
      {
        name = "servicel2statuses";
        group = "metallb.io";
        version = "v1beta1";
        kind = "ServiceL2Status";
        attrName = "serviceL2Statuses";
      }
      {
        name = "bgppeers";
        group = "metallb.io";
        version = "v1beta2";
        kind = "BGPPeer";
        attrName = "bgpPeers";
      }
    ];

    resources = {
      "metallb.io"."v1beta1"."BFDProfile" = mkAliasDefinitions options.resources."bfdProfiles";
      "metallb.io"."v1beta1"."BGPAdvertisement" =
        mkAliasDefinitions
          options.resources."bgpAdvertisements";
      "metallb.io"."v1beta2"."BGPPeer" = mkAliasDefinitions options.resources."bgpPeers";
      "frrk8s.metallb.io"."v1beta1"."BGPSessionState" =
        mkAliasDefinitions
          options.resources."bgpSessionStates";
      "metallb.io"."v1beta1"."Community" = mkAliasDefinitions options.resources."communities";
      "metallb.io"."v1beta1"."ConfigurationState" =
        mkAliasDefinitions
          options.resources."configurationStates";
      "frrk8s.metallb.io"."v1beta1"."FRRConfiguration" =
        mkAliasDefinitions
          options.resources."frrConfigurations";
      "frrk8s.metallb.io"."v1beta1"."FRRK8sConfiguration" =
        mkAliasDefinitions
          options.resources."fRRK8sConfigurations";
      "frrk8s.metallb.io"."v1beta1"."FRRNodeState" = mkAliasDefinitions options.resources."frrNodeStates";
      "metallb.io"."v1beta1"."IPAddressPool" = mkAliasDefinitions options.resources."ipAddressPools";
      "metallb.io"."v1beta1"."L2Advertisement" = mkAliasDefinitions options.resources."l2Advertisements";
      "metallb.io"."v1beta1"."ServiceBGPStatus" =
        mkAliasDefinitions
          options.resources."serviceBGPStatuses";
      "metallb.io"."v1beta1"."ServiceL2Status" = mkAliasDefinitions options.resources."serviceL2Statuses";

    };

    # make all namespaced resources default to the
    # application's namespace
    defaults = [
      {
        group = "frrk8s.metallb.io";
        version = "v1beta1";
        kind = "BGPSessionState";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "frrk8s.metallb.io";
        version = "v1beta1";
        kind = "FRRConfiguration";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "frrk8s.metallb.io";
        version = "v1beta1";
        kind = "FRRK8sConfiguration";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "metallb.io";
        version = "v1beta1";
        kind = "BFDProfile";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "metallb.io";
        version = "v1beta1";
        kind = "BGPAdvertisement";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "metallb.io";
        version = "v1beta1";
        kind = "Community";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "metallb.io";
        version = "v1beta1";
        kind = "ConfigurationState";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "metallb.io";
        version = "v1beta1";
        kind = "IPAddressPool";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "metallb.io";
        version = "v1beta1";
        kind = "L2Advertisement";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "metallb.io";
        version = "v1beta1";
        kind = "ServiceBGPStatus";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "metallb.io";
        version = "v1beta1";
        kind = "ServiceL2Status";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "metallb.io";
        version = "v1beta2";
        kind = "BGPPeer";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
    ];
  };
}
