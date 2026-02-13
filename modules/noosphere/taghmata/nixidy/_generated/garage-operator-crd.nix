# This file was generated with nixidy resource generator, do not edit.
{
  lib,
  options,
  config,
  ...
}:
with lib; let
  hasAttrNotNull = attr: set: hasAttr attr set && set.${attr} != null;

  attrsToList = values:
    if values != null
    then
      sort (
        a: b:
          if (hasAttrNotNull "_priority" a && hasAttrNotNull "_priority" b)
          then a._priority < b._priority
          else false
      ) (mapAttrsToList (n: v: v) values)
    else values;

  getDefaults = resource: group: version: kind:
    catAttrs "default" (
      filter (
        default:
          (default.resource == null || default.resource == resource)
          && (default.group == null || default.group == group)
          && (default.version == null || default.version == version)
          && (default.kind == null || default.kind == kind)
      )
      config.defaults
    );

  types =
    lib.types
    // rec {
      str = mkOptionType {
        name = "str";
        description = "string";
        check = isString;
        merge = mergeEqualOption;
      };

      # Either value of type `finalType` or `coercedType`, the latter is
      # converted to `finalType` using `coerceFunc`.
      coercedTo = coercedType: coerceFunc: finalType:
        mkOptionType rec {
          inherit (finalType) getSubOptions getSubModules;

          name = "coercedTo";
          description = "${finalType.description} or ${coercedType.description}";
          check = x: finalType.check x || coercedType.check x;
          merge = loc: defs: let
            coerceVal = val:
              if finalType.check val
              then val
              else let
                coerced = coerceFunc val;
              in
                assert finalType.check coerced; coerced;
          in
            finalType.merge loc (map (def: def // {value = coerceVal def.value;}) defs);
          substSubModules = m: coercedTo coercedType coerceFunc (finalType.substSubModules m);
          typeMerge = t1: t2: null;
          functor =
            (defaultFunctor name)
            // {
              wrapped = finalType;
            };
        };
    };

  mkOptionDefault = mkOverride 1001;

  mergeValuesByKey = attrMergeKey: listMergeKeys: values:
    listToAttrs (
      imap0 (
        i: value:
          nameValuePair (
            if hasAttr attrMergeKey value
            then
              if isAttrs value.${attrMergeKey}
              then toString value.${attrMergeKey}.content
              else (toString value.${attrMergeKey})
            else
              # generate merge key for list elements if it's not present
              "__kubenix_list_merge_key_"
              + (concatStringsSep "" (
                map (
                  key:
                    if isAttrs value.${key}
                    then toString value.${key}.content
                    else (toString value.${key})
                )
                listMergeKeys
              ))
          ) (value // {_priority = i;})
      )
      values
    );

  submoduleOf = ref:
    types.submodule (
      {name, ...}: {
        options = definitions."${ref}".options or {};
        config = definitions."${ref}".config or {};
      }
    );

  globalSubmoduleOf = ref:
    types.submodule (
      {name, ...}: {
        options = config.definitions."${ref}".options or {};
        config = config.definitions."${ref}".config or {};
      }
    );

  submoduleWithMergeOf = ref: mergeKey:
    types.submodule (
      {name, ...}: let
        convertName = name:
          if definitions."${ref}".options.${mergeKey}.type == types.int
          then toInt name
          else name;
      in {
        options =
          definitions."${ref}".options
          // {
            # position in original array
            _priority = mkOption {
              type = types.nullOr types.int;
              default = null;
              internal = true;
            };
          };
        config =
          definitions."${ref}".config
          // {
            ${mergeKey} = mkOverride 1002 (
              # use name as mergeKey only if it is not coming from mergeValuesByKey
              if (!hasPrefix "__kubenix_list_merge_key_" name)
              then convertName name
              else null
            );
          };
      }
    );

  submoduleForDefinition = ref: resource: kind: group: version: let
    apiVersion =
      if group == "core"
      then version
      else "${group}/${version}";
  in
    types.submodule (
      {name, ...}: {
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

  coerceAttrsOfSubmodulesToListByKey = ref: attrMergeKey: listMergeKeys: (types.coercedTo (types.listOf (submoduleOf ref)) (mergeValuesByKey attrMergeKey listMergeKeys) (
    types.attrsOf (submoduleWithMergeOf ref attrMergeKey)
  ));

  definitions = {
    "garage.rajsingh.info.v1alpha1.GarageAdminToken" = {
      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = types.nullOr types.str;
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta");
        };
        "spec" = mkOption {
          description = "GarageAdminTokenSpec defines the desired state of GarageAdminToken\nAdmin tokens are used to authenticate with the Garage Admin API.\nThey are separate from S3 access keys (GarageKey).\n\nNote: This operator uses file-based admin tokens (loaded via admin_token_file in TOML config).\nFile-based tokens always have full admin access. For scoped/restricted tokens, use Garage's\nAdmin API token management (CreateAdminToken, UpdateAdminToken) directly.";
          type = submoduleOf "garage.rajsingh.info.v1alpha1.GarageAdminTokenSpec";
        };
        "status" = mkOption {
          description = "GarageAdminTokenStatus defines the observed state of GarageAdminToken";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageAdminTokenStatus");
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageAdminTokenSpec" = {
      options = {
        "clusterRef" = mkOption {
          description = "ClusterRef references the GarageCluster this token belongs to";
          type = submoduleOf "garage.rajsingh.info.v1alpha1.GarageAdminTokenSpecClusterRef";
        };
        "expiration" = mkOption {
          description = "Expiration sets when this token expires (RFC 3339 format)\nNote: Expiration is tracked by the operator but not enforced by Garage\nfor file-based tokens. Token rotation must be done manually.";
          type = types.nullOr types.str;
        };
        "name" = mkOption {
          description = "Name is a friendly name for this admin token\nIf not set, metadata.name is used";
          type = types.nullOr types.str;
        };
        "neverExpires" = mkOption {
          description = "NeverExpires sets the token to never expire\nMutually exclusive with Expiration";
          type = types.nullOr types.bool;
        };
        "secretTemplate" = mkOption {
          description = "SecretTemplate configures how the secret containing the token is generated";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageAdminTokenSpecSecretTemplate")
          );
        };
      };

      config = {
        "expiration" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "neverExpires" = mkOverride 1002 null;
        "secretTemplate" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageAdminTokenSpecClusterRef" = {
      options = {
        "kubeConfigSecretRef" = mkOption {
          description = "KubeConfigSecretRef references a secret containing kubeconfig for a remote cluster.\nOnly used for cross-cluster references in multi-cluster federation scenarios.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageAdminTokenSpecClusterRefKubeConfigSecretRef"
            )
          );
        };
        "name" = mkOption {
          description = "Name of the GarageCluster";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "Namespace of the GarageCluster (defaults to the same namespace as the referencing resource)";
          type = types.nullOr types.str;
        };
      };

      config = {
        "kubeConfigSecretRef" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageAdminTokenSpecClusterRefKubeConfigSecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageAdminTokenSpecSecretTemplate" = {
      options = {
        "annotations" = mkOption {
          description = "Annotations to add to the secret";
          type = types.nullOr (types.attrsOf types.str);
        };
        "endpointKey" = mkOption {
          description = "EndpointKey is the key name for the admin endpoint";
          type = types.nullOr types.str;
        };
        "includeEndpoint" = mkOption {
          description = "IncludeEndpoint includes the admin API endpoint in the secret\nDefaults to true if not specified";
          type = types.nullOr types.bool;
        };
        "labels" = mkOption {
          description = "Labels to add to the secret";
          type = types.nullOr (types.attrsOf types.str);
        };
        "name" = mkOption {
          description = "Name is the name of the secret to create\nDefaults to the GarageAdminToken name";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "Namespace is the namespace for the secret\nDefaults to the GarageAdminToken namespace";
          type = types.nullOr types.str;
        };
        "tokenKey" = mkOption {
          description = "TokenKey is the key name for the admin token in the secret";
          type = types.nullOr types.str;
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "endpointKey" = mkOverride 1002 null;
        "includeEndpoint" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "tokenKey" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageAdminTokenStatus" = {
      options = {
        "conditions" = mkOption {
          description = "Conditions represent the current state";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1alpha1.GarageAdminTokenStatusConditions")
            )
          );
        };
        "expiration" = mkOption {
          description = "Expiration is when this token expires (if set)";
          type = types.nullOr types.str;
        };
        "expired" = mkOption {
          description = "Expired indicates if this token has expired";
          type = types.nullOr types.bool;
        };
        "observedGeneration" = mkOption {
          description = "ObservedGeneration is the last observed generation";
          type = types.nullOr types.int;
        };
        "phase" = mkOption {
          description = "Phase represents the current phase";
          type = types.nullOr types.str;
        };
        "secretRef" = mkOption {
          description = "SecretRef references the created secret";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageAdminTokenStatusSecretRef");
        };
        "tokenId" = mkOption {
          description = "TokenID is the Garage-assigned token ID (first 8 chars)";
          type = types.nullOr types.str;
        };
      };

      config = {
        "conditions" = mkOverride 1002 null;
        "expiration" = mkOverride 1002 null;
        "expired" = mkOverride 1002 null;
        "observedGeneration" = mkOverride 1002 null;
        "phase" = mkOverride 1002 null;
        "secretRef" = mkOverride 1002 null;
        "tokenId" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageAdminTokenStatusConditions" = {
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
          type = types.nullOr types.int;
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
    "garage.rajsingh.info.v1alpha1.GarageAdminTokenStatusSecretRef" = {
      options = {
        "name" = mkOption {
          description = "name is unique within a namespace to reference a secret resource.";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "namespace defines the space within which the secret name must be unique.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageBucket" = {
      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = types.nullOr types.str;
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta");
        };
        "spec" = mkOption {
          description = "GarageBucketSpec defines the desired state of GarageBucket";
          type = submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketSpec";
        };
        "status" = mkOption {
          description = "GarageBucketStatus defines the observed state of GarageBucket";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketStatus");
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageBucketSpec" = {
      options = {
        "clusterRef" = mkOption {
          description = "ClusterRef references the GarageCluster this bucket belongs to";
          type = submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketSpecClusterRef";
        };
        "globalAlias" = mkOption {
          description = "GlobalAlias is the global alias for this bucket (optional)\nIf not set, the bucket name from metadata.name is used";
          type = types.nullOr types.str;
        };
        "keyPermissions" = mkOption {
          description = "KeyPermissions grants access to specific GarageKeys.\n\nNote: Permissions can be granted from either direction:\n- Here (GarageBucket.keyPermissions): Grant keys access to this bucket\n- On GarageKey (GarageKey.bucketPermissions): Grant the key access to buckets\n\nBoth approaches are equivalent and result in the same Garage API calls.\nUse whichever is more convenient for your workflow:\n- Bucket-centric: Define all key access on the bucket\n- Key-centric: Define all bucket access on the key\n\nIf the same permission is defined in both places, they are merged (not conflicting).";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketSpecKeyPermissions")
            )
          );
        };
        "localAliases" = mkOption {
          description = "LocalAliases are per-key local aliases for this bucket";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketSpecLocalAliases")
            )
          );
        };
        "quotas" = mkOption {
          description = "Quotas configures bucket quotas";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketSpecQuotas");
        };
        "website" = mkOption {
          description = "Website configures static website hosting for this bucket.\nNote: Only indexDocument and errorDocument are supported via the Admin API.\nFor advanced features (routing rules, redirectAll), use S3 PutBucketWebsite API directly.";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketSpecWebsite");
        };
      };

      config = {
        "globalAlias" = mkOverride 1002 null;
        "keyPermissions" = mkOverride 1002 null;
        "localAliases" = mkOverride 1002 null;
        "quotas" = mkOverride 1002 null;
        "website" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageBucketSpecClusterRef" = {
      options = {
        "kubeConfigSecretRef" = mkOption {
          description = "KubeConfigSecretRef references a secret containing kubeconfig for a remote cluster.\nOnly used for cross-cluster references in multi-cluster federation scenarios.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketSpecClusterRefKubeConfigSecretRef"
            )
          );
        };
        "name" = mkOption {
          description = "Name of the GarageCluster";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "Namespace of the GarageCluster (defaults to the same namespace as the referencing resource)";
          type = types.nullOr types.str;
        };
      };

      config = {
        "kubeConfigSecretRef" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageBucketSpecClusterRefKubeConfigSecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageBucketSpecKeyPermissions" = {
      options = {
        "keyRef" = mkOption {
          description = "KeyRef references the GarageKey by name";
          type = types.str;
        };
        "owner" = mkOption {
          description = "Owner allows bucket owner operations";
          type = types.nullOr types.bool;
        };
        "read" = mkOption {
          description = "Read allows reading objects";
          type = types.nullOr types.bool;
        };
        "write" = mkOption {
          description = "Write allows writing objects";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "owner" = mkOverride 1002 null;
        "read" = mkOverride 1002 null;
        "write" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageBucketSpecLocalAliases" = {
      options = {
        "alias" = mkOption {
          description = "Alias is the local alias name";
          type = types.str;
        };
        "keyRef" = mkOption {
          description = "KeyRef references the GarageKey";
          type = types.str;
        };
      };

      config = {};
    };
    "garage.rajsingh.info.v1alpha1.GarageBucketSpecQuotas" = {
      options = {
        "maxObjects" = mkOption {
          description = "MaxObjects is the maximum number of objects";
          type = types.nullOr types.int;
        };
        "maxSize" = mkOption {
          description = "MaxSize is the maximum bucket size in bytes";
          type = types.nullOr (types.either types.int types.str);
        };
      };

      config = {
        "maxObjects" = mkOverride 1002 null;
        "maxSize" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageBucketSpecWebsite" = {
      options = {
        "enabled" = mkOption {
          description = "Enabled enables static website hosting";
          type = types.nullOr types.bool;
        };
        "errorDocument" = mkOption {
          description = "ErrorDocument is the error document to serve for 404s";
          type = types.nullOr types.str;
        };
        "indexDocument" = mkOption {
          description = "IndexDocument is the default index document (default: index.html)";
          type = types.nullOr types.str;
        };
      };

      config = {
        "enabled" = mkOverride 1002 null;
        "errorDocument" = mkOverride 1002 null;
        "indexDocument" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageBucketStatus" = {
      options = {
        "bucketId" = mkOption {
          description = "BucketID is the internal Garage bucket ID";
          type = types.nullOr types.str;
        };
        "conditions" = mkOption {
          description = "Conditions represent the current state";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketStatusConditions")
            )
          );
        };
        "createdAt" = mkOption {
          description = "CreatedAt is when the bucket was created in Garage";
          type = types.nullOr types.str;
        };
        "globalAlias" = mkOption {
          description = "GlobalAlias is the assigned global alias";
          type = types.nullOr types.str;
        };
        "incompleteUploadBytes" = mkOption {
          description = "IncompleteUploadBytes is the total bytes in incomplete multipart uploads";
          type = types.nullOr types.int;
        };
        "incompleteUploadParts" = mkOption {
          description = "IncompleteUploadParts is the count of parts in incomplete multipart uploads";
          type = types.nullOr types.int;
        };
        "incompleteUploads" = mkOption {
          description = "IncompleteUploads is the count of incomplete multipart uploads";
          type = types.nullOr types.int;
        };
        "keys" = mkOption {
          description = "Keys contains keys with access to this bucket";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1alpha1.GarageBucketStatusKeys" "name" []
            )
          );
          apply = attrsToList;
        };
        "localAliases" = mkOption {
          description = "LocalAliases tracks per-key local aliases for this bucket";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketStatusLocalAliases")
            )
          );
        };
        "objectCount" = mkOption {
          description = "ObjectCount is the current object count";
          type = types.nullOr types.int;
        };
        "observedGeneration" = mkOption {
          description = "ObservedGeneration is the last observed generation";
          type = types.nullOr types.int;
        };
        "phase" = mkOption {
          description = "Phase represents the current phase";
          type = types.nullOr types.str;
        };
        "quotaUsage" = mkOption {
          description = "QuotaUsage shows current quota consumption";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketStatusQuotaUsage");
        };
        "size" = mkOption {
          description = "Size is the current bucket size";
          type = types.nullOr types.str;
        };
        "websiteConfig" = mkOption {
          description = "WebsiteConfig shows the current website configuration details";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketStatusWebsiteConfig");
        };
        "websiteEnabled" = mkOption {
          description = "WebsiteEnabled indicates if website hosting is currently enabled";
          type = types.nullOr types.bool;
        };
        "websiteUrl" = mkOption {
          description = "WebsiteURL is the computed website URL (if website hosting is enabled)";
          type = types.nullOr types.str;
        };
      };

      config = {
        "bucketId" = mkOverride 1002 null;
        "conditions" = mkOverride 1002 null;
        "createdAt" = mkOverride 1002 null;
        "globalAlias" = mkOverride 1002 null;
        "incompleteUploadBytes" = mkOverride 1002 null;
        "incompleteUploadParts" = mkOverride 1002 null;
        "incompleteUploads" = mkOverride 1002 null;
        "keys" = mkOverride 1002 null;
        "localAliases" = mkOverride 1002 null;
        "objectCount" = mkOverride 1002 null;
        "observedGeneration" = mkOverride 1002 null;
        "phase" = mkOverride 1002 null;
        "quotaUsage" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "websiteConfig" = mkOverride 1002 null;
        "websiteEnabled" = mkOverride 1002 null;
        "websiteUrl" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageBucketStatusConditions" = {
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
          type = types.nullOr types.int;
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
    "garage.rajsingh.info.v1alpha1.GarageBucketStatusKeys" = {
      options = {
        "keyId" = mkOption {
          description = "KeyID is the access key ID";
          type = types.nullOr types.str;
        };
        "name" = mkOption {
          description = "Name is the key name";
          type = types.nullOr types.str;
        };
        "permissions" = mkOption {
          description = "Permissions granted to this key";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketStatusKeysPermissions")
          );
        };
      };

      config = {
        "keyId" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "permissions" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageBucketStatusKeysPermissions" = {
      options = {
        "owner" = mkOption {
          description = "Owner permission";
          type = types.nullOr types.bool;
        };
        "read" = mkOption {
          description = "Read permission";
          type = types.nullOr types.bool;
        };
        "write" = mkOption {
          description = "Write permission";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "owner" = mkOverride 1002 null;
        "read" = mkOverride 1002 null;
        "write" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageBucketStatusLocalAliases" = {
      options = {
        "alias" = mkOption {
          description = "Alias is the local alias name";
          type = types.nullOr types.str;
        };
        "keyId" = mkOption {
          description = "KeyID is the access key ID that owns this alias";
          type = types.nullOr types.str;
        };
        "keyName" = mkOption {
          description = "KeyName is the friendly name of the key";
          type = types.nullOr types.str;
        };
      };

      config = {
        "alias" = mkOverride 1002 null;
        "keyId" = mkOverride 1002 null;
        "keyName" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageBucketStatusQuotaUsage" = {
      options = {
        "objectCount" = mkOption {
          description = "ObjectCount is the current object count";
          type = types.nullOr types.int;
        };
        "objectLimit" = mkOption {
          description = "ObjectLimit is the configured object limit (0 = unlimited)";
          type = types.nullOr types.int;
        };
        "objectPercent" = mkOption {
          description = "ObjectPercent is the percentage of object quota used";
          type = types.nullOr types.int;
        };
        "sizeBytes" = mkOption {
          description = "SizeBytes is the current size in bytes";
          type = types.nullOr types.int;
        };
        "sizeLimit" = mkOption {
          description = "SizeLimit is the configured size limit in bytes (0 = unlimited)";
          type = types.nullOr types.int;
        };
        "sizePercent" = mkOption {
          description = "SizePercent is the percentage of size quota used";
          type = types.nullOr types.int;
        };
      };

      config = {
        "objectCount" = mkOverride 1002 null;
        "objectLimit" = mkOverride 1002 null;
        "objectPercent" = mkOverride 1002 null;
        "sizeBytes" = mkOverride 1002 null;
        "sizeLimit" = mkOverride 1002 null;
        "sizePercent" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageBucketStatusWebsiteConfig" = {
      options = {
        "errorDocument" = mkOption {
          description = "ErrorDocument is the configured error document";
          type = types.nullOr types.str;
        };
        "indexDocument" = mkOption {
          description = "IndexDocument is the configured index document";
          type = types.nullOr types.str;
        };
      };

      config = {
        "errorDocument" = mkOverride 1002 null;
        "indexDocument" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageCluster" = {
      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = types.nullOr types.str;
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta");
        };
        "spec" = mkOption {
          description = "GarageClusterSpec defines the desired state of GarageCluster";
          type = submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpec";
        };
        "status" = mkOption {
          description = "GarageClusterStatus defines the observed state of GarageCluster";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterStatus");
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpec" = {
      options = {
        "admin" = mkOption {
          description = "Admin configures the admin API endpoint and metrics";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAdmin");
        };
        "affinity" = mkOption {
          description = "Affinity for pod scheduling";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinity");
        };
        "blocks" = mkOption {
          description = "Blocks configures block storage settings";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecBlocks");
        };
        "capacityReservePercent" = mkOption {
          description = "CapacityReservePercent reserves a percentage of PVC capacity for overhead.\nOnly used when LayoutPolicy is \"Auto\".\nFor example, setting this to 10 will report 90% of PVC size as node capacity.\nThis is useful to reserve headroom for filesystem overhead, snapshots, or growth.\nDefault: 0 (use full PVC size as capacity)";
          type = types.nullOr types.int;
        };
        "connectTo" = mkOption {
          description = "ConnectTo specifies the storage cluster this gateway cluster connects to.\nRequired when gateway=true. The gateway cluster will:\n- Use the same RPC secret as the storage cluster\n- Connect to the storage cluster's nodes\n- Register its pods as gateway nodes in the storage cluster's layout";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecConnectTo");
        };
        "containerSecurityContext" = mkOption {
          description = "ContainerSecurityContext for Garage containers";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecContainerSecurityContext")
          );
        };
        "database" = mkOption {
          description = "Database configures the metadata database engine";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecDatabase");
        };
        "defaultNodeTags" = mkOption {
          description = "DefaultNodeTags are tags applied to all auto-managed nodes.\nOnly used when LayoutPolicy is \"Auto\".\nFor per-node tags, use LayoutPolicy \"Manual\" with GarageNode resources.";
          type = types.nullOr (types.listOf types.str);
        };
        "discovery" = mkOption {
          description = "Discovery configures peer discovery mechanisms";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecDiscovery");
        };
        "gateway" = mkOption {
          description = "Gateway marks this cluster as a gateway-only cluster.\nGateway clusters don't store data - they only handle API requests.\nWhen true:\n- Creates a StatefulSet with metadata PVC only (for node identity persistence)\n- Data storage uses EmptyDir (gateways don't store blocks)\n- Pods are registered as gateway nodes in the layout (capacity=null)\n- Must specify connectTo to reference a storage cluster";
          type = types.nullOr types.bool;
        };
        "image" = mkOption {
          description = "Image specifies the Garage container image to use.\nTakes precedence over imageRepository if both are set.";
          type = types.nullOr types.str;
        };
        "imagePullPolicy" = mkOption {
          description = "ImagePullPolicy specifies the image pull policy";
          type = types.nullOr types.str;
        };
        "imagePullSecrets" = mkOption {
          description = "ImagePullSecrets specifies secrets for pulling images from private registries";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1alpha1.GarageClusterSpecImagePullSecrets"
              "name"
              []
            )
          );
          apply = attrsToList;
        };
        "imageRepository" = mkOption {
          description = "ImageRepository overrides just the repository portion of the default Garage image,\npreserving the default tag for automatic version upgrades.\nFor example, setting this to \"my-mirror/garage\" with the default tag v2.2.0\nproduces \"my-mirror/garage:v2.2.0\".\nIgnored if image is set.";
          type = types.nullOr types.str;
        };
        "k2vApi" = mkOption {
          description = "K2VAPI configures the K2V (key-value) API endpoint";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecK2vApi");
        };
        "layoutManagement" = mkOption {
          description = "LayoutManagement controls how the cluster layout is managed";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecLayoutManagement")
          );
        };
        "layoutPolicy" = mkOption {
          description = "LayoutPolicy controls whether node layouts are automatically managed or manually configured.\n- \"Auto\": The controller automatically assigns all local pods to the layout using the\n  cluster's zone and derives capacity from data PVC size. No GarageNode resources needed.\n- \"Manual\": You must create GarageNode resources for each node you want in the layout.\n  Use this for fine-grained control over zones, capacities, or external nodes.";
          type = types.nullOr types.str;
        };
        "logging" = mkOption {
          description = "Logging configures logging behavior for Garage nodes";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecLogging");
        };
        "network" = mkOption {
          description = "Network configures RPC and API networking";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecNetwork");
        };
        "nodeSelector" = mkOption {
          description = "NodeSelector for pod scheduling";
          type = types.nullOr (types.attrsOf types.str);
        };
        "podAnnotations" = mkOption {
          description = "PodAnnotations to add to Garage pods";
          type = types.nullOr (types.attrsOf types.str);
        };
        "podDisruptionBudget" = mkOption {
          description = "PodDisruptionBudget configures the PodDisruptionBudget for the cluster";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecPodDisruptionBudget")
          );
        };
        "podLabels" = mkOption {
          description = "PodLabels to add to Garage pods";
          type = types.nullOr (types.attrsOf types.str);
        };
        "priorityClassName" = mkOption {
          description = "PriorityClassName for Garage pods";
          type = types.nullOr types.str;
        };
        "publicEndpoint" = mkOption {
          description = "PublicEndpoint configures how remote clusters reach this cluster's nodes\nRequired for multi-cluster federation";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecPublicEndpoint");
        };
        "remoteClusters" = mkOption {
          description = "RemoteClusters are Garage clusters in other Kubernetes clusters\nThe operator will auto-discover nodes and coordinate layout";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1alpha1.GarageClusterSpecRemoteClusters"
              "name"
              []
            )
          );
          apply = attrsToList;
        };
        "replicas" = mkOption {
          description = "Replicas is the number of Garage nodes to deploy in this cluster";
          type = types.int;
        };
        "replication" = mkOption {
          description = "Replication configures data replication settings";
          type = submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecReplication";
        };
        "resources" = mkOption {
          description = "Resources specifies compute resources for Garage pods";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecResources");
        };
        "s3Api" = mkOption {
          description = "S3API configures the S3-compatible API endpoint";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecS3Api");
        };
        "security" = mkOption {
          description = "Security configures security-related settings";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurity");
        };
        "securityContext" = mkOption {
          description = "SecurityContext for Garage pods";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityContext")
          );
        };
        "serviceAccountName" = mkOption {
          description = "ServiceAccountName for Garage pods";
          type = types.nullOr types.str;
        };
        "serviceAnnotations" = mkOption {
          description = "ServiceAnnotations to add to Garage services";
          type = types.nullOr (types.attrsOf types.str);
        };
        "storage" = mkOption {
          description = "Storage configures storage settings for metadata and data.\nOptional - sensible defaults are provided:\n- Storage clusters: 10Gi metadata, 100Gi data\n- Gateway clusters: 1Gi metadata only (data uses EmptyDir)";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorage");
        };
        "tolerations" = mkOption {
          description = "Tolerations for pod scheduling";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecTolerations")
            )
          );
        };
        "topologySpreadConstraints" = mkOption {
          description = "TopologySpreadConstraints for pod scheduling";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecTopologySpreadConstraints"
              )
            )
          );
        };
        "webApi" = mkOption {
          description = "WebAPI configures the static website hosting endpoint";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecWebApi");
        };
        "zone" = mkOption {
          description = "Zone is the zone name for all nodes in this cluster.\nUsed for fault tolerance - Garage distributes replicas across zones.\nRequired for multi-cluster federation.\n\nExamples: \"us-east-1\", \"rack-a\", \"dc1\", \"zone-a\"";
          type = types.nullOr types.str;
        };
      };

      config = {
        "admin" = mkOverride 1002 null;
        "affinity" = mkOverride 1002 null;
        "blocks" = mkOverride 1002 null;
        "capacityReservePercent" = mkOverride 1002 null;
        "connectTo" = mkOverride 1002 null;
        "containerSecurityContext" = mkOverride 1002 null;
        "database" = mkOverride 1002 null;
        "defaultNodeTags" = mkOverride 1002 null;
        "discovery" = mkOverride 1002 null;
        "gateway" = mkOverride 1002 null;
        "image" = mkOverride 1002 null;
        "imagePullPolicy" = mkOverride 1002 null;
        "imagePullSecrets" = mkOverride 1002 null;
        "imageRepository" = mkOverride 1002 null;
        "k2vApi" = mkOverride 1002 null;
        "layoutManagement" = mkOverride 1002 null;
        "layoutPolicy" = mkOverride 1002 null;
        "logging" = mkOverride 1002 null;
        "network" = mkOverride 1002 null;
        "nodeSelector" = mkOverride 1002 null;
        "podAnnotations" = mkOverride 1002 null;
        "podDisruptionBudget" = mkOverride 1002 null;
        "podLabels" = mkOverride 1002 null;
        "priorityClassName" = mkOverride 1002 null;
        "publicEndpoint" = mkOverride 1002 null;
        "remoteClusters" = mkOverride 1002 null;
        "resources" = mkOverride 1002 null;
        "s3Api" = mkOverride 1002 null;
        "security" = mkOverride 1002 null;
        "securityContext" = mkOverride 1002 null;
        "serviceAccountName" = mkOverride 1002 null;
        "serviceAnnotations" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "tolerations" = mkOverride 1002 null;
        "topologySpreadConstraints" = mkOverride 1002 null;
        "webApi" = mkOverride 1002 null;
        "zone" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAdmin" = {
      options = {
        "adminTokenSecretRef" = mkOption {
          description = "AdminTokenSecretRef references a secret containing the admin API token";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAdminAdminTokenSecretRef")
          );
        };
        "bindAddress" = mkOption {
          description = "BindAddress is a custom bind address for the Admin API.\nCan be a TCP address or Unix socket path (e.g., \"unix:///run/garage/admin.sock\").\nIf set, this overrides BindPort.";
          type = types.nullOr types.str;
        };
        "bindPort" = mkOption {
          description = "BindPort is the port to bind for admin API";
          type = types.nullOr types.int;
        };
        "enabled" = mkOption {
          description = "Enabled enables the admin API";
          type = types.nullOr types.bool;
        };
        "metricsRequireToken" = mkOption {
          description = "MetricsRequireToken requires authentication for /metrics endpoint";
          type = types.nullOr types.bool;
        };
        "metricsTokenSecretRef" = mkOption {
          description = "MetricsTokenSecretRef references a secret containing the metrics token";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAdminMetricsTokenSecretRef"
            )
          );
        };
        "traceSink" = mkOption {
          description = "TraceSink is the OpenTelemetry collector address for tracing\nExample: \"http://localhost:4317\"";
          type = types.nullOr types.str;
        };
      };

      config = {
        "adminTokenSecretRef" = mkOverride 1002 null;
        "bindAddress" = mkOverride 1002 null;
        "bindPort" = mkOverride 1002 null;
        "enabled" = mkOverride 1002 null;
        "metricsRequireToken" = mkOverride 1002 null;
        "metricsTokenSecretRef" = mkOverride 1002 null;
        "traceSink" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAdminAdminTokenSecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAdminMetricsTokenSecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinity" = {
      options = {
        "nodeAffinity" = mkOption {
          description = "Describes node affinity scheduling rules for the pod.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityNodeAffinity")
          );
        };
        "podAffinity" = mkOption {
          description = "Describes pod affinity scheduling rules (e.g. co-locate this pod in the same node, zone, etc. as some other pod(s)).";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinity")
          );
        };
        "podAntiAffinity" = mkOption {
          description = "Describes pod anti-affinity scheduling rules (e.g. avoid putting this pod in the same node, zone, etc. as some other pod(s)).";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinity")
          );
        };
      };

      config = {
        "nodeAffinity" = mkOverride 1002 null;
        "podAffinity" = mkOverride 1002 null;
        "podAntiAffinity" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityNodeAffinity" = {
      options = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "The scheduler will prefer to schedule pods to nodes that satisfy\nthe affinity expressions specified by this field, but it may choose\na node that violates one or more of the expressions. The node that is\nmost preferred is the one with the greatest sum of weights, i.e.\nfor each node that meets all of the scheduling requirements (resource\nrequest, requiredDuringScheduling affinity expressions, etc.),\ncompute a sum by iterating through the elements of this field and adding\n\"weight\" to the sum if the node matches the corresponding matchExpressions; the\nnode(s) with the highest sum are the most preferred.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "If the affinity requirements specified by this field are not met at\nscheduling time, the pod will not be scheduled onto the node.\nIf the affinity requirements specified by this field cease to be met\nat some point during pod execution (e.g. due to an update), the system\nmay or may not try to eventually evict the pod from its node.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecution"
            )
          );
        };
      };

      config = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecution" = {
      options = {
        "preference" = mkOption {
          description = "A node selector term, associated with the corresponding weight.";
          type = (
            submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreference"
          );
        };
        "weight" = mkOption {
          description = "Weight associated with matching the corresponding nodeSelectorTerm, in the range 1-100.";
          type = types.int;
        };
      };

      config = {};
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreference" = {
      options = {
        "matchExpressions" = mkOption {
          description = "A list of node selector requirements by node's labels.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchExpressions"
              )
            )
          );
        };
        "matchFields" = mkOption {
          description = "A list of node selector requirements by node's fields.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchFields"
              )
            )
          );
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchFields" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchExpressions" = {
      options = {
        "key" = mkOption {
          description = "The label key that the selector applies to.";
          type = types.str;
        };
        "operator" = mkOption {
          description = "Represents a key's relationship to a set of values.\nValid operators are In, NotIn, Exists, DoesNotExist. Gt, and Lt.";
          type = types.str;
        };
        "values" = mkOption {
          description = "An array of string values. If the operator is In or NotIn,\nthe values array must be non-empty. If the operator is Exists or DoesNotExist,\nthe values array must be empty. If the operator is Gt or Lt, the values\narray must have a single element, which will be interpreted as an integer.\nThis array is replaced during a strategic merge patch.";
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchFields" = {
      options = {
        "key" = mkOption {
          description = "The label key that the selector applies to.";
          type = types.str;
        };
        "operator" = mkOption {
          description = "Represents a key's relationship to a set of values.\nValid operators are In, NotIn, Exists, DoesNotExist. Gt, and Lt.";
          type = types.str;
        };
        "values" = mkOption {
          description = "An array of string values. If the operator is In or NotIn,\nthe values array must be non-empty. If the operator is Exists or DoesNotExist,\nthe values array must be empty. If the operator is Gt or Lt, the values\narray must have a single element, which will be interpreted as an integer.\nThis array is replaced during a strategic merge patch.";
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecution" = {
      options = {
        "nodeSelectorTerms" = mkOption {
          description = "Required. A list of node selector terms. The terms are ORed.";
          type = (
            types.listOf (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTerms"
            )
          );
        };
      };

      config = {};
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTerms" = {
      options = {
        "matchExpressions" = mkOption {
          description = "A list of node selector requirements by node's labels.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchExpressions"
              )
            )
          );
        };
        "matchFields" = mkOption {
          description = "A list of node selector requirements by node's fields.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchFields"
              )
            )
          );
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchFields" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchExpressions" = {
      options = {
        "key" = mkOption {
          description = "The label key that the selector applies to.";
          type = types.str;
        };
        "operator" = mkOption {
          description = "Represents a key's relationship to a set of values.\nValid operators are In, NotIn, Exists, DoesNotExist. Gt, and Lt.";
          type = types.str;
        };
        "values" = mkOption {
          description = "An array of string values. If the operator is In or NotIn,\nthe values array must be non-empty. If the operator is Exists or DoesNotExist,\nthe values array must be empty. If the operator is Gt or Lt, the values\narray must have a single element, which will be interpreted as an integer.\nThis array is replaced during a strategic merge patch.";
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchFields" = {
      options = {
        "key" = mkOption {
          description = "The label key that the selector applies to.";
          type = types.str;
        };
        "operator" = mkOption {
          description = "Represents a key's relationship to a set of values.\nValid operators are In, NotIn, Exists, DoesNotExist. Gt, and Lt.";
          type = types.str;
        };
        "values" = mkOption {
          description = "An array of string values. If the operator is In or NotIn,\nthe values array must be non-empty. If the operator is Exists or DoesNotExist,\nthe values array must be empty. If the operator is Gt or Lt, the values\narray must have a single element, which will be interpreted as an integer.\nThis array is replaced during a strategic merge patch.";
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinity" = {
      options = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "The scheduler will prefer to schedule pods to nodes that satisfy\nthe affinity expressions specified by this field, but it may choose\na node that violates one or more of the expressions. The node that is\nmost preferred is the one with the greatest sum of weights, i.e.\nfor each node that meets all of the scheduling requirements (resource\nrequest, requiredDuringScheduling affinity expressions, etc.),\ncompute a sum by iterating through the elements of this field and adding\n\"weight\" to the sum if the node has pods which matches the corresponding podAffinityTerm; the\nnode(s) with the highest sum are the most preferred.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "If the affinity requirements specified by this field are not met at\nscheduling time, the pod will not be scheduled onto the node.\nIf the affinity requirements specified by this field cease to be met\nat some point during pod execution (e.g. due to a pod label update), the\nsystem may or may not try to eventually evict the pod from its node.\nWhen there are multiple elements, the lists of nodes corresponding to each\npodAffinityTerm are intersected, i.e. all terms must be satisfied.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
      };

      config = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecution" = {
      options = {
        "podAffinityTerm" = mkOption {
          description = "Required. A pod affinity term, associated with the corresponding weight.";
          type = (
            submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm"
          );
        };
        "weight" = mkOption {
          description = "weight associated with matching the corresponding podAffinityTerm,\nin the range 1-100.";
          type = types.int;
        };
      };

      config = {};
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm" = {
      options = {
        "labelSelector" = mkOption {
          description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector"
            )
          );
        };
        "matchLabelKeys" = mkOption {
          description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
          type = types.nullOr (types.listOf types.str);
        };
        "mismatchLabelKeys" = mkOption {
          description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
          type = types.nullOr (types.listOf types.str);
        };
        "namespaceSelector" = mkOption {
          description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector"
            )
          );
        };
        "namespaces" = mkOption {
          description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
          type = types.nullOr (types.listOf types.str);
        };
        "topologyKey" = mkOption {
          description = "This pod should be co-located (affinity) or not co-located (anti-affinity) with the pods matching\nthe labelSelector in the specified namespaces, where co-located is defined as running on a node\nwhose value of the label with key topologyKey matches that of any node on which any of the\nselected pods is running.\nEmpty topologyKey is not allowed.";
          type = types.str;
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "matchLabelKeys" = mkOverride 1002 null;
        "mismatchLabelKeys" = mkOverride 1002 null;
        "namespaceSelector" = mkOverride 1002 null;
        "namespaces" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecution" = {
      options = {
        "labelSelector" = mkOption {
          description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector"
            )
          );
        };
        "matchLabelKeys" = mkOption {
          description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
          type = types.nullOr (types.listOf types.str);
        };
        "mismatchLabelKeys" = mkOption {
          description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
          type = types.nullOr (types.listOf types.str);
        };
        "namespaceSelector" = mkOption {
          description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector"
            )
          );
        };
        "namespaces" = mkOption {
          description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
          type = types.nullOr (types.listOf types.str);
        };
        "topologyKey" = mkOption {
          description = "This pod should be co-located (affinity) or not co-located (anti-affinity) with the pods matching\nthe labelSelector in the specified namespaces, where co-located is defined as running on a node\nwhose value of the label with key topologyKey matches that of any node on which any of the\nselected pods is running.\nEmpty topologyKey is not allowed.";
          type = types.str;
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "matchLabelKeys" = mkOverride 1002 null;
        "mismatchLabelKeys" = mkOverride 1002 null;
        "namespaceSelector" = mkOverride 1002 null;
        "namespaces" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinity" = {
      options = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "The scheduler will prefer to schedule pods to nodes that satisfy\nthe anti-affinity expressions specified by this field, but it may choose\na node that violates one or more of the expressions. The node that is\nmost preferred is the one with the greatest sum of weights, i.e.\nfor each node that meets all of the scheduling requirements (resource\nrequest, requiredDuringScheduling anti-affinity expressions, etc.),\ncompute a sum by iterating through the elements of this field and subtracting\n\"weight\" from the sum if the node has pods which matches the corresponding podAffinityTerm; the\nnode(s) with the highest sum are the most preferred.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "If the anti-affinity requirements specified by this field are not met at\nscheduling time, the pod will not be scheduled onto the node.\nIf the anti-affinity requirements specified by this field cease to be met\nat some point during pod execution (e.g. due to a pod label update), the\nsystem may or may not try to eventually evict the pod from its node.\nWhen there are multiple elements, the lists of nodes corresponding to each\npodAffinityTerm are intersected, i.e. all terms must be satisfied.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
      };

      config = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecution" = {
      options = {
        "podAffinityTerm" = mkOption {
          description = "Required. A pod affinity term, associated with the corresponding weight.";
          type = (
            submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm"
          );
        };
        "weight" = mkOption {
          description = "weight associated with matching the corresponding podAffinityTerm,\nin the range 1-100.";
          type = types.int;
        };
      };

      config = {};
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm" = {
      options = {
        "labelSelector" = mkOption {
          description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector"
            )
          );
        };
        "matchLabelKeys" = mkOption {
          description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
          type = types.nullOr (types.listOf types.str);
        };
        "mismatchLabelKeys" = mkOption {
          description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
          type = types.nullOr (types.listOf types.str);
        };
        "namespaceSelector" = mkOption {
          description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector"
            )
          );
        };
        "namespaces" = mkOption {
          description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
          type = types.nullOr (types.listOf types.str);
        };
        "topologyKey" = mkOption {
          description = "This pod should be co-located (affinity) or not co-located (anti-affinity) with the pods matching\nthe labelSelector in the specified namespaces, where co-located is defined as running on a node\nwhose value of the label with key topologyKey matches that of any node on which any of the\nselected pods is running.\nEmpty topologyKey is not allowed.";
          type = types.str;
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "matchLabelKeys" = mkOverride 1002 null;
        "mismatchLabelKeys" = mkOverride 1002 null;
        "namespaceSelector" = mkOverride 1002 null;
        "namespaces" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecution" = {
      options = {
        "labelSelector" = mkOption {
          description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector"
            )
          );
        };
        "matchLabelKeys" = mkOption {
          description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
          type = types.nullOr (types.listOf types.str);
        };
        "mismatchLabelKeys" = mkOption {
          description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
          type = types.nullOr (types.listOf types.str);
        };
        "namespaceSelector" = mkOption {
          description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector"
            )
          );
        };
        "namespaces" = mkOption {
          description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
          type = types.nullOr (types.listOf types.str);
        };
        "topologyKey" = mkOption {
          description = "This pod should be co-located (affinity) or not co-located (anti-affinity) with the pods matching\nthe labelSelector in the specified namespaces, where co-located is defined as running on a node\nwhose value of the label with key topologyKey matches that of any node on which any of the\nselected pods is running.\nEmpty topologyKey is not allowed.";
          type = types.str;
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "matchLabelKeys" = mkOverride 1002 null;
        "mismatchLabelKeys" = mkOverride 1002 null;
        "namespaceSelector" = mkOverride 1002 null;
        "namespaces" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecBlocks" = {
      options = {
        "compressionLevel" = mkOption {
          description = "CompressionLevel is the zstd compression level\n1-19: standard, 20-22: ultra, -1 to -99: fast, \"none\": disabled";
          type = types.nullOr types.str;
        };
        "disableScrub" = mkOption {
          description = "DisableScrub disables automatic monthly data directory scrub";
          type = types.nullOr types.bool;
        };
        "maxConcurrentReads" = mkOption {
          description = "MaxConcurrentReads is the maximum simultaneous block file reads";
          type = types.nullOr types.int;
        };
        "maxConcurrentWritesPerRequest" = mkOption {
          description = "MaxConcurrentWritesPerRequest is the maximum parallel block writes per PUT request.\nHigher values improve throughput but increase memory usage.\nDefault: 3. Recommended: 10-30 for NVMe, 3-10 for HDD.\nAdded in Garage v2.2.0.";
          type = types.nullOr types.int;
        };
        "ramBufferMax" = mkOption {
          description = "RAMBufferMax is the maximum RAM for buffering blocks";
          type = types.nullOr (types.either types.int types.str);
        };
        "size" = mkOption {
          description = "Size is the size of data blocks (default: 1M)";
          type = types.nullOr (types.either types.int types.str);
        };
        "useLocalTZ" = mkOption {
          description = "UseLocalTZ runs lifecycle worker at midnight in local timezone";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "compressionLevel" = mkOverride 1002 null;
        "disableScrub" = mkOverride 1002 null;
        "maxConcurrentReads" = mkOverride 1002 null;
        "maxConcurrentWritesPerRequest" = mkOverride 1002 null;
        "ramBufferMax" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "useLocalTZ" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecConnectTo" = {
      options = {
        "adminApiEndpoint" = mkOption {
          description = "AdminAPIEndpoint is the admin API endpoint for discovering nodes and registering gateways\nRequired if clusterRef is not in the same namespace\nExample: \"http://garage-storage.other-namespace:3903\"";
          type = types.nullOr types.str;
        };
        "adminTokenSecretRef" = mkOption {
          description = "AdminTokenSecretRef references the admin token for the storage cluster\nIf clusterRef is specified and in same namespace, uses that cluster's token";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecConnectToAdminTokenSecretRef"
            )
          );
        };
        "bootstrapPeers" = mkOption {
          description = "BootstrapPeers are the initial peers to connect to (for external storage clusters)\nFormat: \"<node_public_key>@<ip_or_hostname>:<port>\"";
          type = types.nullOr (types.listOf types.str);
        };
        "clusterRef" = mkOption {
          description = "ClusterRef references a GarageCluster in the same namespace\nThe gateway will use this cluster's RPC secret and connect to its nodes";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecConnectToClusterRef")
          );
        };
        "rpcSecretRef" = mkOption {
          description = "RPCSecretRef references a shared RPC secret (for cross-namespace or external clusters)\nIf clusterRef is specified, this is ignored (uses the referenced cluster's secret)";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecConnectToRpcSecretRef")
          );
        };
      };

      config = {
        "adminApiEndpoint" = mkOverride 1002 null;
        "adminTokenSecretRef" = mkOverride 1002 null;
        "bootstrapPeers" = mkOverride 1002 null;
        "clusterRef" = mkOverride 1002 null;
        "rpcSecretRef" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecConnectToAdminTokenSecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecConnectToClusterRef" = {
      options = {
        "kubeConfigSecretRef" = mkOption {
          description = "KubeConfigSecretRef references a secret containing kubeconfig for a remote cluster.\nOnly used for cross-cluster references in multi-cluster federation scenarios.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecConnectToClusterRefKubeConfigSecretRef"
            )
          );
        };
        "name" = mkOption {
          description = "Name of the GarageCluster";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "Namespace of the GarageCluster (defaults to the same namespace as the referencing resource)";
          type = types.nullOr types.str;
        };
      };

      config = {
        "kubeConfigSecretRef" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecConnectToClusterRefKubeConfigSecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecConnectToRpcSecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecContainerSecurityContext" = {
      options = {
        "allowPrivilegeEscalation" = mkOption {
          description = "AllowPrivilegeEscalation controls whether a process can gain more\nprivileges than its parent process. This bool directly controls if\nthe no_new_privs flag will be set on the container process.\nAllowPrivilegeEscalation is true always when the container is:\n1) run as Privileged\n2) has CAP_SYS_ADMIN\nNote that this field cannot be set when spec.os.name is windows.";
          type = types.nullOr types.bool;
        };
        "appArmorProfile" = mkOption {
          description = "appArmorProfile is the AppArmor options to use by this container. If set, this profile\noverrides the pod's appArmorProfile.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecContainerSecurityContextAppArmorProfile"
            )
          );
        };
        "capabilities" = mkOption {
          description = "The capabilities to add/drop when running containers.\nDefaults to the default set of capabilities granted by the container runtime.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecContainerSecurityContextCapabilities"
            )
          );
        };
        "privileged" = mkOption {
          description = "Run container in privileged mode.\nProcesses in privileged containers are essentially equivalent to root on the host.\nDefaults to false.\nNote that this field cannot be set when spec.os.name is windows.";
          type = types.nullOr types.bool;
        };
        "procMount" = mkOption {
          description = "procMount denotes the type of proc mount to use for the containers.\nThe default value is Default which uses the container runtime defaults for\nreadonly paths and masked paths.\nThis requires the ProcMountType feature flag to be enabled.\nNote that this field cannot be set when spec.os.name is windows.";
          type = types.nullOr types.str;
        };
        "readOnlyRootFilesystem" = mkOption {
          description = "Whether this container has a read-only root filesystem.\nDefault is false.\nNote that this field cannot be set when spec.os.name is windows.";
          type = types.nullOr types.bool;
        };
        "runAsGroup" = mkOption {
          description = "The GID to run the entrypoint of the container process.\nUses runtime default if unset.\nMay also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is windows.";
          type = types.nullOr types.int;
        };
        "runAsNonRoot" = mkOption {
          description = "Indicates that the container must run as a non-root user.\nIf true, the Kubelet will validate the image at runtime to ensure that it\ndoes not run as UID 0 (root) and fail to start the container if it does.\nIf unset or false, no such validation will be performed.\nMay also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
          type = types.nullOr types.bool;
        };
        "runAsUser" = mkOption {
          description = "The UID to run the entrypoint of the container process.\nDefaults to user specified in image metadata if unspecified.\nMay also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is windows.";
          type = types.nullOr types.int;
        };
        "seLinuxOptions" = mkOption {
          description = "The SELinux context to be applied to the container.\nIf unspecified, the container runtime will allocate a random SELinux context for each\ncontainer.  May also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecContainerSecurityContextSeLinuxOptions"
            )
          );
        };
        "seccompProfile" = mkOption {
          description = "The seccomp options to use by this container. If seccomp options are\nprovided at both the pod & container level, the container options\noverride the pod options.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecContainerSecurityContextSeccompProfile"
            )
          );
        };
        "windowsOptions" = mkOption {
          description = "The Windows specific settings applied to all containers.\nIf unspecified, the options from the PodSecurityContext will be used.\nIf set in both SecurityContext and PodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is linux.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecContainerSecurityContextWindowsOptions"
            )
          );
        };
      };

      config = {
        "allowPrivilegeEscalation" = mkOverride 1002 null;
        "appArmorProfile" = mkOverride 1002 null;
        "capabilities" = mkOverride 1002 null;
        "privileged" = mkOverride 1002 null;
        "procMount" = mkOverride 1002 null;
        "readOnlyRootFilesystem" = mkOverride 1002 null;
        "runAsGroup" = mkOverride 1002 null;
        "runAsNonRoot" = mkOverride 1002 null;
        "runAsUser" = mkOverride 1002 null;
        "seLinuxOptions" = mkOverride 1002 null;
        "seccompProfile" = mkOverride 1002 null;
        "windowsOptions" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecContainerSecurityContextAppArmorProfile" = {
      options = {
        "localhostProfile" = mkOption {
          description = "localhostProfile indicates a profile loaded on the node that should be used.\nThe profile must be preconfigured on the node to work.\nMust match the loaded name of the profile.\nMust be set if and only if type is \"Localhost\".";
          type = types.nullOr types.str;
        };
        "type" = mkOption {
          description = "type indicates which kind of AppArmor profile will be applied.\nValid options are:\n  Localhost - a profile pre-loaded on the node.\n  RuntimeDefault - the container runtime's default profile.\n  Unconfined - no AppArmor enforcement.";
          type = types.str;
        };
      };

      config = {
        "localhostProfile" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecContainerSecurityContextCapabilities" = {
      options = {
        "add" = mkOption {
          description = "Added capabilities";
          type = types.nullOr (types.listOf types.str);
        };
        "drop" = mkOption {
          description = "Removed capabilities";
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "add" = mkOverride 1002 null;
        "drop" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecContainerSecurityContextSeLinuxOptions" = {
      options = {
        "level" = mkOption {
          description = "Level is SELinux level label that applies to the container.";
          type = types.nullOr types.str;
        };
        "role" = mkOption {
          description = "Role is a SELinux role label that applies to the container.";
          type = types.nullOr types.str;
        };
        "type" = mkOption {
          description = "Type is a SELinux type label that applies to the container.";
          type = types.nullOr types.str;
        };
        "user" = mkOption {
          description = "User is a SELinux user label that applies to the container.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "level" = mkOverride 1002 null;
        "role" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
        "user" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecContainerSecurityContextSeccompProfile" = {
      options = {
        "localhostProfile" = mkOption {
          description = "localhostProfile indicates a profile defined in a file on the node should be used.\nThe profile must be preconfigured on the node to work.\nMust be a descending path, relative to the kubelet's configured seccomp profile location.\nMust be set if type is \"Localhost\". Must NOT be set for any other type.";
          type = types.nullOr types.str;
        };
        "type" = mkOption {
          description = "type indicates which kind of seccomp profile will be applied.\nValid options are:\n\nLocalhost - a profile defined in a file on the node should be used.\nRuntimeDefault - the container runtime default profile should be used.\nUnconfined - no profile should be applied.";
          type = types.str;
        };
      };

      config = {
        "localhostProfile" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecContainerSecurityContextWindowsOptions" = {
      options = {
        "gmsaCredentialSpec" = mkOption {
          description = "GMSACredentialSpec is where the GMSA admission webhook\n(https://github.com/kubernetes-sigs/windows-gmsa) inlines the contents of the\nGMSA credential spec named by the GMSACredentialSpecName field.";
          type = types.nullOr types.str;
        };
        "gmsaCredentialSpecName" = mkOption {
          description = "GMSACredentialSpecName is the name of the GMSA credential spec to use.";
          type = types.nullOr types.str;
        };
        "hostProcess" = mkOption {
          description = "HostProcess determines if a container should be run as a 'Host Process' container.\nAll of a Pod's containers must have the same effective HostProcess value\n(it is not allowed to have a mix of HostProcess containers and non-HostProcess containers).\nIn addition, if HostProcess is true then HostNetwork must also be set to true.";
          type = types.nullOr types.bool;
        };
        "runAsUserName" = mkOption {
          description = "The UserName in Windows to run the entrypoint of the container process.\nDefaults to the user specified in image metadata if unspecified.\nMay also be set in PodSecurityContext. If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "gmsaCredentialSpec" = mkOverride 1002 null;
        "gmsaCredentialSpecName" = mkOverride 1002 null;
        "hostProcess" = mkOverride 1002 null;
        "runAsUserName" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecDatabase" = {
      options = {
        "engine" = mkOption {
          description = "Engine specifies the database engine to use";
          type = types.nullOr types.str;
        };
        "fjallBlockCacheSize" = mkOption {
          description = "FjallBlockCacheSize is the block cache size for Fjall";
          type = types.nullOr (types.either types.int types.str);
        };
        "lmdbMapSize" = mkOption {
          description = "LMDBMapSize is the virtual memory region size for LMDB";
          type = types.nullOr (types.either types.int types.str);
        };
      };

      config = {
        "engine" = mkOverride 1002 null;
        "fjallBlockCacheSize" = mkOverride 1002 null;
        "lmdbMapSize" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecDiscovery" = {
      options = {
        "consul" = mkOption {
          description = "Consul configures Consul-based peer discovery";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecDiscoveryConsul")
          );
        };
        "kubernetes" = mkOption {
          description = "Kubernetes configures Kubernetes-based peer discovery";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecDiscoveryKubernetes")
          );
        };
      };

      config = {
        "consul" = mkOverride 1002 null;
        "kubernetes" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecDiscoveryConsul" = {
      options = {
        "api" = mkOption {
          description = "API specifies the service registration API (\"catalog\" or \"agent\")";
          type = types.nullOr types.str;
        };
        "caCert" = mkOption {
          description = "CACert is the CA certificate for TLS connection";
          type = types.nullOr types.str;
        };
        "caCertSecretRef" = mkOption {
          description = "CACertSecretRef references a secret containing the CA certificate";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecDiscoveryConsulCaCertSecretRef"
            )
          );
        };
        "clientCertSecretRef" = mkOption {
          description = "ClientCertSecretRef references a secret containing client TLS cert";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecDiscoveryConsulClientCertSecretRef"
            )
          );
        };
        "clientKeySecretRef" = mkOption {
          description = "ClientKeySecretRef references a secret containing client TLS key";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecDiscoveryConsulClientKeySecretRef"
            )
          );
        };
        "datacenters" = mkOption {
          description = "Datacenters for WAN federation";
          type = types.nullOr (types.listOf types.str);
        };
        "enabled" = mkOption {
          description = "Enabled enables Consul-based discovery";
          type = types.nullOr types.bool;
        };
        "httpAddr" = mkOption {
          description = "HTTPAddr is the full HTTP(S) address of Consul server";
          type = types.nullOr types.str;
        };
        "meta" = mkOption {
          description = "Meta is service metadata key-value pairs";
          type = types.nullOr (types.attrsOf types.str);
        };
        "serviceName" = mkOption {
          description = "ServiceName for Garage RPC port registration";
          type = types.nullOr types.str;
        };
        "tags" = mkOption {
          description = "Tags are additional service tags";
          type = types.nullOr (types.listOf types.str);
        };
        "tlsSkipVerify" = mkOption {
          description = "TLSSkipVerify skips TLS hostname verification";
          type = types.nullOr types.bool;
        };
        "tokenSecretRef" = mkOption {
          description = "TokenSecretRef references a secret containing the bearer token";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecDiscoveryConsulTokenSecretRef"
            )
          );
        };
      };

      config = {
        "api" = mkOverride 1002 null;
        "caCert" = mkOverride 1002 null;
        "caCertSecretRef" = mkOverride 1002 null;
        "clientCertSecretRef" = mkOverride 1002 null;
        "clientKeySecretRef" = mkOverride 1002 null;
        "datacenters" = mkOverride 1002 null;
        "enabled" = mkOverride 1002 null;
        "httpAddr" = mkOverride 1002 null;
        "meta" = mkOverride 1002 null;
        "serviceName" = mkOverride 1002 null;
        "tags" = mkOverride 1002 null;
        "tlsSkipVerify" = mkOverride 1002 null;
        "tokenSecretRef" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecDiscoveryConsulCaCertSecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecDiscoveryConsulClientCertSecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecDiscoveryConsulClientKeySecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecDiscoveryConsulTokenSecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecDiscoveryKubernetes" = {
      options = {
        "enabled" = mkOption {
          description = "Enabled enables Kubernetes-based discovery";
          type = types.nullOr types.bool;
        };
        "namespace" = mkOption {
          description = "Namespace for Garage custom resources";
          type = types.nullOr types.str;
        };
        "serviceName" = mkOption {
          description = "ServiceName label to filter custom resources";
          type = types.nullOr types.str;
        };
        "skipCRD" = mkOption {
          description = "SkipCRD skips automatic CRD creation/patching";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "enabled" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "serviceName" = mkOverride 1002 null;
        "skipCRD" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecImagePullSecrets" = {
      options = {
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecK2vApi" = {
      options = {
        "bindAddress" = mkOption {
          description = "BindAddress is a custom bind address for the K2V API.\nCan be a TCP address or Unix socket path (e.g., \"unix:///run/garage/k2v.sock\").\nIf set, this overrides BindPort.";
          type = types.nullOr types.str;
        };
        "bindPort" = mkOption {
          description = "BindPort is the port to bind for K2V API";
          type = types.nullOr types.int;
        };
        "enabled" = mkOption {
          description = "Enabled enables the K2V API";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "bindAddress" = mkOverride 1002 null;
        "bindPort" = mkOverride 1002 null;
        "enabled" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecLayoutManagement" = {
      options = {
        "autoApply" = mkOption {
          description = "AutoApply automatically applies staged layout changes";
          type = types.nullOr types.bool;
        };
        "minNodesHealthy" = mkOption {
          description = "MinNodesHealthy is the minimum healthy nodes required before applying layout changes";
          type = types.nullOr types.int;
        };
      };

      config = {
        "autoApply" = mkOverride 1002 null;
        "minNodesHealthy" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecLogging" = {
      options = {
        "journald" = mkOption {
          description = "Journald enables logging to systemd journald (requires Garage built with journald feature)";
          type = types.nullOr types.bool;
        };
        "level" = mkOption {
          description = "Level sets the log level using RUST_LOG format.\n\nExamples:\n- \"info\": Default info level for all components\n- \"debug\": Debug level for all components\n- \"garage=debug\": Debug only for garage module\n- \"garage=debug,netapp=info\": Fine-grained per-component levels\n- \"garage=trace,netapp=debug,rusoto=warn\": Multiple components\n\nSee https://docs.rs/env_logger for full syntax.";
          type = types.nullOr types.str;
        };
        "syslog" = mkOption {
          description = "Syslog enables logging to syslog (requires Garage built with syslog feature)";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "journald" = mkOverride 1002 null;
        "level" = mkOverride 1002 null;
        "syslog" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecNetwork" = {
      options = {
        "bootstrapPeers" = mkOption {
          description = "BootstrapPeers lists initial peers for cluster formation.\n\nFormat: \"<node_public_key>@<ip_or_hostname>:<port>\"\n\nExample:\n- \"563e1ac825ee3323aa441e72c26d1030d6d4414aeb3dd25287c531e7fc2bc95d@10.0.0.1:3901\"\n- \"ec79480e0ce52ae26fd00c9da684e4fa56f77571b9b8560382f859930e63571d@garage-2.example.com:3901\"";
          type = types.nullOr (types.listOf types.str);
        };
        "rpcBindOutgoing" = mkOption {
          description = "RPCBindOutgoing pre-binds outgoing sockets to same IP";
          type = types.nullOr types.bool;
        };
        "rpcBindPort" = mkOption {
          description = "RPCBindPort is the port for inter-cluster RPC";
          type = types.nullOr types.int;
        };
        "rpcPingTimeoutMs" = mkOption {
          description = "RPCPingTimeoutMs sets the RPC ping timeout in milliseconds";
          type = types.nullOr types.int;
        };
        "rpcPublicAddr" = mkOption {
          description = "RPCPublicAddr is the external address for other nodes to contact this node";
          type = types.nullOr types.str;
        };
        "rpcPublicAddrSubnet" = mkOption {
          description = "RPCPublicAddrSubnet filters autodiscovered IPs to specific subnet";
          type = types.nullOr types.str;
        };
        "rpcSecretRef" = mkOption {
          description = "RPCSecret is a reference to a secret containing the RPC secret\nThe secret must have a key 'rpc-secret' with a 32-byte hex-encoded value";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecNetworkRpcSecretRef")
          );
        };
        "rpcTimeoutMs" = mkOption {
          description = "RPCTimeoutMs sets the RPC call timeout in milliseconds";
          type = types.nullOr types.int;
        };
        "service" = mkOption {
          description = "Service configures the Kubernetes Service for the cluster";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecNetworkService");
        };
      };

      config = {
        "bootstrapPeers" = mkOverride 1002 null;
        "rpcBindOutgoing" = mkOverride 1002 null;
        "rpcBindPort" = mkOverride 1002 null;
        "rpcPingTimeoutMs" = mkOverride 1002 null;
        "rpcPublicAddr" = mkOverride 1002 null;
        "rpcPublicAddrSubnet" = mkOverride 1002 null;
        "rpcSecretRef" = mkOverride 1002 null;
        "rpcTimeoutMs" = mkOverride 1002 null;
        "service" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecNetworkRpcSecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecNetworkService" = {
      options = {
        "annotations" = mkOption {
          description = "Annotations for the service";
          type = types.nullOr (types.attrsOf types.str);
        };
        "externalTrafficPolicy" = mkOption {
          description = "ExternalTrafficPolicy for LoadBalancer/NodePort";
          type = types.nullOr types.str;
        };
        "loadBalancerIP" = mkOption {
          description = "LoadBalancerIP for LoadBalancer type";
          type = types.nullOr types.str;
        };
        "loadBalancerSourceRanges" = mkOption {
          description = "LoadBalancerSourceRanges for LoadBalancer type";
          type = types.nullOr (types.listOf types.str);
        };
        "type" = mkOption {
          description = "Type of service";
          type = types.nullOr types.str;
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "externalTrafficPolicy" = mkOverride 1002 null;
        "loadBalancerIP" = mkOverride 1002 null;
        "loadBalancerSourceRanges" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecPodDisruptionBudget" = {
      options = {
        "enabled" = mkOption {
          description = "Enabled enables PodDisruptionBudget creation";
          type = types.nullOr types.bool;
        };
        "maxUnavailable" = mkOption {
          description = "MaxUnavailable specifies the maximum number of pods that can be unavailable\nCan be an absolute number (e.g., 1) or a percentage (e.g., \"25%\")\nMutually exclusive with MinAvailable";
          type = types.nullOr types.str;
        };
        "minAvailable" = mkOption {
          description = "MinAvailable specifies the minimum number of pods that must be available\nCan be an absolute number (e.g., 2) or a percentage (e.g., \"50%\")\nMutually exclusive with MaxUnavailable";
          type = types.nullOr types.str;
        };
      };

      config = {
        "enabled" = mkOverride 1002 null;
        "maxUnavailable" = mkOverride 1002 null;
        "minAvailable" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecPublicEndpoint" = {
      options = {
        "externalIP" = mkOption {
          description = "ExternalIP configuration";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecPublicEndpointExternalIP")
          );
        };
        "loadBalancer" = mkOption {
          description = "LoadBalancer configuration";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecPublicEndpointLoadBalancer"
            )
          );
        };
        "nodePort" = mkOption {
          description = "NodePort configuration";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecPublicEndpointNodePort")
          );
        };
        "type" = mkOption {
          description = "Type specifies how nodes are exposed";
          type = types.str;
        };
      };

      config = {
        "externalIP" = mkOverride 1002 null;
        "loadBalancer" = mkOverride 1002 null;
        "nodePort" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecPublicEndpointExternalIP" = {
      options = {
        "addressTemplate" = mkOption {
          description = "AddressTemplate uses go template to generate addresses from pod info\nExample: \"garage-{{.Index}}.example.com\"";
          type = types.nullOr types.str;
        };
        "addresses" = mkOption {
          description = "Addresses maps pod names to external IPs";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "addressTemplate" = mkOverride 1002 null;
        "addresses" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecPublicEndpointLoadBalancer" = {
      options = {
        "annotations" = mkOption {
          description = "Annotations for the LoadBalancer service";
          type = types.nullOr (types.attrsOf types.str);
        };
        "perNode" = mkOption {
          description = "PerNode creates a separate LoadBalancer per node (more expensive but ensures direct routing)";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "perNode" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecPublicEndpointNodePort" = {
      options = {
        "basePort" = mkOption {
          description = "BasePort is the starting NodePort (each node gets BasePort + index)";
          type = types.nullOr types.int;
        };
        "externalAddresses" = mkOption {
          description = "ExternalAddresses are the external IPs/hostnames of the Kubernetes nodes";
          type = types.listOf types.str;
        };
      };

      config = {
        "basePort" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecRemoteClusters" = {
      options = {
        "connection" = mkOption {
          description = "Connection defines how to connect to this remote cluster";
          type = submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecRemoteClustersConnection";
        };
        "defaultCapacity" = mkOption {
          description = "DefaultCapacity is the default storage capacity to assign to remote nodes\nthat don't yet have a role in the layout. If not specified, defaults to 100Gi.\nSet to \"0\" to add nodes as gateway-only (no storage).";
          type = types.nullOr (types.either types.int types.str);
        };
        "name" = mkOption {
          description = "Name is a friendly name for this remote cluster";
          type = types.str;
        };
        "zone" = mkOption {
          description = "Zone is the zone name for nodes in this remote cluster";
          type = types.str;
        };
      };

      config = {
        "defaultCapacity" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecRemoteClustersConnection" = {
      options = {
        "adminApiEndpoint" = mkOption {
          description = "AdminAPIEndpoint is the admin API endpoint of the remote cluster\nThis should be a reachable HTTP/HTTPS URL (e.g., via Tailscale, LoadBalancer, or port-forward)\nExample: \"http://garage-remote.tailscale:3903\"";
          type = types.str;
        };
        "adminTokenSecretRef" = mkOption {
          description = "AdminTokenSecretRef references the admin token for the remote cluster's API\nIf not specified, uses the local cluster's admin token (for shared-token setups)";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecRemoteClustersConnectionAdminTokenSecretRef"
            )
          );
        };
      };

      config = {
        "adminTokenSecretRef" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecRemoteClustersConnectionAdminTokenSecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecReplication" = {
      options = {
        "consistencyMode" = mkOption {
          description = "ConsistencyMode controls quorum behavior for read/write operations.\n\nValues:\n- \"consistent\" (default): Require quorum for both reads and writes.\n  Safest option, ensures strong consistency.\n- \"degraded\": Allow reads from single node when quorum unavailable.\n  May return stale data during network partitions.\n- \"dangerous\": Allow reads AND writes without quorum.\n  WARNING: May lose data during failures!";
          type = types.nullOr types.str;
        };
        "factor" = mkOption {
          description = "Factor is the replication factor (1, 2, 3, 5, 7, etc.)\nMust be the same on all nodes in the cluster";
          type = types.int;
        };
        "zoneRedundancy" = mkOption {
          description = "ZoneRedundancy controls how data is distributed across zones.\n\nValues:\n- \"Maximum\": Maximize redundancy by placing replicas in as many zones as possible\n- \"AtLeast(n)\": Require replicas to be in at least n different zones\n\nThe value n must not exceed the replication factor.\n\nExamples:\n- \"Maximum\" (default): Best effort zone distribution\n- \"AtLeast(1)\": No zone constraint (all replicas can be in one zone)\n- \"AtLeast(2)\": Survives 1 zone failure (requires 2+ zones)\n- \"AtLeast(3)\": Survives 2 zone failures (requires 3+ zones)";
          type = types.nullOr types.str;
        };
      };

      config = {
        "consistencyMode" = mkOverride 1002 null;
        "zoneRedundancy" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecResources" = {
      options = {
        "claims" = mkOption {
          description = "Claims lists the names of resources, defined in spec.resourceClaims,\nthat are used by this container.\n\nThis field depends on the\nDynamicResourceAllocation feature gate.\n\nThis field is immutable. It can only be set for containers.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1alpha1.GarageClusterSpecResourcesClaims"
              "name"
              ["name"]
            )
          );
          apply = attrsToList;
        };
        "limits" = mkOption {
          description = "Limits describes the maximum amount of compute resources allowed.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = types.nullOr (types.attrsOf (types.either types.int types.str));
        };
        "requests" = mkOption {
          description = "Requests describes the minimum amount of compute resources required.\nIf Requests is omitted for a container, it defaults to Limits if that is explicitly specified,\notherwise to an implementation-defined value. Requests cannot exceed Limits.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = types.nullOr (types.attrsOf (types.either types.int types.str));
        };
      };

      config = {
        "claims" = mkOverride 1002 null;
        "limits" = mkOverride 1002 null;
        "requests" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecResourcesClaims" = {
      options = {
        "name" = mkOption {
          description = "Name must match the name of one entry in pod.spec.resourceClaims of\nthe Pod where this field is used. It makes that resource available\ninside a container.";
          type = types.str;
        };
        "request" = mkOption {
          description = "Request is the name chosen for a request in the referenced claim.\nIf empty, everything from the claim is made available, otherwise\nonly the result of this request.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "request" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecS3Api" = {
      options = {
        "bindAddress" = mkOption {
          description = "BindAddress is a custom bind address for the S3 API.\nCan be a TCP address (e.g., \"0.0.0.0:3900\", \"[::]:3900\") or\na Unix socket path (e.g., \"unix:///run/garage/s3.sock\").\nIf set, this overrides BindPort.";
          type = types.nullOr types.str;
        };
        "bindPort" = mkOption {
          description = "BindPort is the port to bind for S3 API";
          type = types.nullOr types.int;
        };
        "region" = mkOption {
          description = "Region is the AWS S3 region name to use";
          type = types.str;
        };
        "rootDomain" = mkOption {
          description = "RootDomain is the root domain suffix for vhost-style S3 access.\nWhen set, buckets can be accessed via <bucket-name>.<root-domain>.\n\nExamples:\n- \".s3.garage.tld\" -> Access bucket \"mybucket\" at \"mybucket.s3.garage.tld\"\n- \".s3.example.com\" -> Access bucket \"data\" at \"data.s3.example.com\"\n\nNote: Include the leading dot.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "bindAddress" = mkOverride 1002 null;
        "bindPort" = mkOverride 1002 null;
        "rootDomain" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurity" = {
      options = {
        "allowPunycode" = mkOption {
          description = "AllowPunycode allows punycode in bucket names";
          type = types.nullOr types.bool;
        };
        "allowWorldReadableSecrets" = mkOption {
          description = "AllowWorldReadableSecrets bypasses permission check for secret files";
          type = types.nullOr types.bool;
        };
        "tls" = mkOption {
          description = "TLS configures TLS settings";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityTls");
        };
      };

      config = {
        "allowPunycode" = mkOverride 1002 null;
        "allowWorldReadableSecrets" = mkOverride 1002 null;
        "tls" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityContext" = {
      options = {
        "appArmorProfile" = mkOption {
          description = "appArmorProfile is the AppArmor options to use by the containers in this pod.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityContextAppArmorProfile"
            )
          );
        };
        "fsGroup" = mkOption {
          description = "A special supplemental group that applies to all containers in a pod.\nSome volume types allow the Kubelet to change the ownership of that volume\nto be owned by the pod:\n\n1. The owning GID will be the FSGroup\n2. The setgid bit is set (new files created in the volume will be owned by FSGroup)\n3. The permission bits are OR'd with rw-rw----\n\nIf unset, the Kubelet will not modify the ownership and permissions of any volume.\nNote that this field cannot be set when spec.os.name is windows.";
          type = types.nullOr types.int;
        };
        "fsGroupChangePolicy" = mkOption {
          description = "fsGroupChangePolicy defines behavior of changing ownership and permission of the volume\nbefore being exposed inside Pod. This field will only apply to\nvolume types which support fsGroup based ownership(and permissions).\nIt will have no effect on ephemeral volume types such as: secret, configmaps\nand emptydir.\nValid values are \"OnRootMismatch\" and \"Always\". If not specified, \"Always\" is used.\nNote that this field cannot be set when spec.os.name is windows.";
          type = types.nullOr types.str;
        };
        "runAsGroup" = mkOption {
          description = "The GID to run the entrypoint of the container process.\nUses runtime default if unset.\nMay also be set in SecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence\nfor that container.\nNote that this field cannot be set when spec.os.name is windows.";
          type = types.nullOr types.int;
        };
        "runAsNonRoot" = mkOption {
          description = "Indicates that the container must run as a non-root user.\nIf true, the Kubelet will validate the image at runtime to ensure that it\ndoes not run as UID 0 (root) and fail to start the container if it does.\nIf unset or false, no such validation will be performed.\nMay also be set in SecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
          type = types.nullOr types.bool;
        };
        "runAsUser" = mkOption {
          description = "The UID to run the entrypoint of the container process.\nDefaults to user specified in image metadata if unspecified.\nMay also be set in SecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence\nfor that container.\nNote that this field cannot be set when spec.os.name is windows.";
          type = types.nullOr types.int;
        };
        "seLinuxChangePolicy" = mkOption {
          description = "seLinuxChangePolicy defines how the container's SELinux label is applied to all volumes used by the Pod.\nIt has no effect on nodes that do not support SELinux or to volumes does not support SELinux.\nValid values are \"MountOption\" and \"Recursive\".\n\n\"Recursive\" means relabeling of all files on all Pod volumes by the container runtime.\nThis may be slow for large volumes, but allows mixing privileged and unprivileged Pods sharing the same volume on the same node.\n\n\"MountOption\" mounts all eligible Pod volumes with `-o context` mount option.\nThis requires all Pods that share the same volume to use the same SELinux label.\nIt is not possible to share the same volume among privileged and unprivileged Pods.\nEligible volumes are in-tree FibreChannel and iSCSI volumes, and all CSI volumes\nwhose CSI driver announces SELinux support by setting spec.seLinuxMount: true in their\nCSIDriver instance. Other volumes are always re-labelled recursively.\n\"MountOption\" value is allowed only when SELinuxMount feature gate is enabled.\n\nIf not specified and SELinuxMount feature gate is enabled, \"MountOption\" is used.\nIf not specified and SELinuxMount feature gate is disabled, \"MountOption\" is used for ReadWriteOncePod volumes\nand \"Recursive\" for all other volumes.\n\nThis field affects only Pods that have SELinux label set, either in PodSecurityContext or in SecurityContext of all containers.\n\nAll Pods that use the same volume should use the same seLinuxChangePolicy, otherwise some pods can get stuck in ContainerCreating state.\nNote that this field cannot be set when spec.os.name is windows.";
          type = types.nullOr types.str;
        };
        "seLinuxOptions" = mkOption {
          description = "The SELinux context to be applied to all containers.\nIf unspecified, the container runtime will allocate a random SELinux context for each\ncontainer.  May also be set in SecurityContext.  If set in\nboth SecurityContext and PodSecurityContext, the value specified in SecurityContext\ntakes precedence for that container.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityContextSeLinuxOptions"
            )
          );
        };
        "seccompProfile" = mkOption {
          description = "The seccomp options to use by the containers in this pod.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityContextSeccompProfile"
            )
          );
        };
        "supplementalGroups" = mkOption {
          description = "A list of groups applied to the first process run in each container, in\naddition to the container's primary GID and fsGroup (if specified).  If\nthe SupplementalGroupsPolicy feature is enabled, the\nsupplementalGroupsPolicy field determines whether these are in addition\nto or instead of any group memberships defined in the container image.\nIf unspecified, no additional groups are added, though group memberships\ndefined in the container image may still be used, depending on the\nsupplementalGroupsPolicy field.\nNote that this field cannot be set when spec.os.name is windows.";
          type = types.nullOr (types.listOf types.int);
        };
        "supplementalGroupsPolicy" = mkOption {
          description = "Defines how supplemental groups of the first container processes are calculated.\nValid values are \"Merge\" and \"Strict\". If not specified, \"Merge\" is used.\n(Alpha) Using the field requires the SupplementalGroupsPolicy feature gate to be enabled\nand the container runtime must implement support for this feature.\nNote that this field cannot be set when spec.os.name is windows.";
          type = types.nullOr types.str;
        };
        "sysctls" = mkOption {
          description = "Sysctls hold a list of namespaced sysctls used for the pod. Pods with unsupported\nsysctls (by the container runtime) might fail to launch.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
              "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityContextSysctls"
              "name"
              []
            )
          );
          apply = attrsToList;
        };
        "windowsOptions" = mkOption {
          description = "The Windows specific settings applied to all containers.\nIf unspecified, the options within a container's SecurityContext will be used.\nIf set in both SecurityContext and PodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is linux.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityContextWindowsOptions"
            )
          );
        };
      };

      config = {
        "appArmorProfile" = mkOverride 1002 null;
        "fsGroup" = mkOverride 1002 null;
        "fsGroupChangePolicy" = mkOverride 1002 null;
        "runAsGroup" = mkOverride 1002 null;
        "runAsNonRoot" = mkOverride 1002 null;
        "runAsUser" = mkOverride 1002 null;
        "seLinuxChangePolicy" = mkOverride 1002 null;
        "seLinuxOptions" = mkOverride 1002 null;
        "seccompProfile" = mkOverride 1002 null;
        "supplementalGroups" = mkOverride 1002 null;
        "supplementalGroupsPolicy" = mkOverride 1002 null;
        "sysctls" = mkOverride 1002 null;
        "windowsOptions" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityContextAppArmorProfile" = {
      options = {
        "localhostProfile" = mkOption {
          description = "localhostProfile indicates a profile loaded on the node that should be used.\nThe profile must be preconfigured on the node to work.\nMust match the loaded name of the profile.\nMust be set if and only if type is \"Localhost\".";
          type = types.nullOr types.str;
        };
        "type" = mkOption {
          description = "type indicates which kind of AppArmor profile will be applied.\nValid options are:\n  Localhost - a profile pre-loaded on the node.\n  RuntimeDefault - the container runtime's default profile.\n  Unconfined - no AppArmor enforcement.";
          type = types.str;
        };
      };

      config = {
        "localhostProfile" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityContextSeLinuxOptions" = {
      options = {
        "level" = mkOption {
          description = "Level is SELinux level label that applies to the container.";
          type = types.nullOr types.str;
        };
        "role" = mkOption {
          description = "Role is a SELinux role label that applies to the container.";
          type = types.nullOr types.str;
        };
        "type" = mkOption {
          description = "Type is a SELinux type label that applies to the container.";
          type = types.nullOr types.str;
        };
        "user" = mkOption {
          description = "User is a SELinux user label that applies to the container.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "level" = mkOverride 1002 null;
        "role" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
        "user" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityContextSeccompProfile" = {
      options = {
        "localhostProfile" = mkOption {
          description = "localhostProfile indicates a profile defined in a file on the node should be used.\nThe profile must be preconfigured on the node to work.\nMust be a descending path, relative to the kubelet's configured seccomp profile location.\nMust be set if type is \"Localhost\". Must NOT be set for any other type.";
          type = types.nullOr types.str;
        };
        "type" = mkOption {
          description = "type indicates which kind of seccomp profile will be applied.\nValid options are:\n\nLocalhost - a profile defined in a file on the node should be used.\nRuntimeDefault - the container runtime default profile should be used.\nUnconfined - no profile should be applied.";
          type = types.str;
        };
      };

      config = {
        "localhostProfile" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityContextSysctls" = {
      options = {
        "name" = mkOption {
          description = "Name of a property to set";
          type = types.str;
        };
        "value" = mkOption {
          description = "Value of a property to set";
          type = types.str;
        };
      };

      config = {};
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityContextWindowsOptions" = {
      options = {
        "gmsaCredentialSpec" = mkOption {
          description = "GMSACredentialSpec is where the GMSA admission webhook\n(https://github.com/kubernetes-sigs/windows-gmsa) inlines the contents of the\nGMSA credential spec named by the GMSACredentialSpecName field.";
          type = types.nullOr types.str;
        };
        "gmsaCredentialSpecName" = mkOption {
          description = "GMSACredentialSpecName is the name of the GMSA credential spec to use.";
          type = types.nullOr types.str;
        };
        "hostProcess" = mkOption {
          description = "HostProcess determines if a container should be run as a 'Host Process' container.\nAll of a Pod's containers must have the same effective HostProcess value\n(it is not allowed to have a mix of HostProcess containers and non-HostProcess containers).\nIn addition, if HostProcess is true then HostNetwork must also be set to true.";
          type = types.nullOr types.bool;
        };
        "runAsUserName" = mkOption {
          description = "The UserName in Windows to run the entrypoint of the container process.\nDefaults to the user specified in image metadata if unspecified.\nMay also be set in PodSecurityContext. If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "gmsaCredentialSpec" = mkOverride 1002 null;
        "gmsaCredentialSpecName" = mkOverride 1002 null;
        "hostProcess" = mkOverride 1002 null;
        "runAsUserName" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityTls" = {
      options = {
        "caSecretRef" = mkOption {
          description = "CASecretRef references a secret containing the CA certificate for verifying peer nodes";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityTlsCaSecretRef")
          );
        };
        "certSecretRef" = mkOption {
          description = "CertSecretRef references a secret containing the TLS certificate for RPC";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityTlsCertSecretRef")
          );
        };
        "enabled" = mkOption {
          description = "Enabled enables TLS for inter-node RPC communication.\nNOTE: This does NOT enable TLS for S3/Admin APIs - use a service mesh or load balancer for that.";
          type = types.nullOr types.bool;
        };
        "keySecretRef" = mkOption {
          description = "KeySecretRef references a secret containing the TLS private key for RPC";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityTlsKeySecretRef")
          );
        };
      };

      config = {
        "caSecretRef" = mkOverride 1002 null;
        "certSecretRef" = mkOverride 1002 null;
        "enabled" = mkOverride 1002 null;
        "keySecretRef" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityTlsCaSecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityTlsCertSecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecSecurityTlsKeySecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorage" = {
      options = {
        "data" = mkOption {
          description = "Data configures data block storage";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageData");
        };
        "dataFsync" = mkOption {
          description = "DataFsync enables fsync for data block writes";
          type = types.nullOr types.bool;
        };
        "metadata" = mkOption {
          description = "Metadata configures metadata storage";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageMetadata")
          );
        };
        "metadataAutoSnapshotInterval" = mkOption {
          description = "MetadataAutoSnapshotInterval enables automatic metadata snapshots\nFormat: \"6h\", \"1d\", etc.";
          type = types.nullOr types.str;
        };
        "metadataFsync" = mkOption {
          description = "MetadataFsync enables fsync for metadata transactions";
          type = types.nullOr types.bool;
        };
        "metadataSnapshotsDir" = mkOption {
          description = "MetadataSnapshotsDir specifies directory for metadata snapshots";
          type = types.nullOr types.str;
        };
        "pvcRetentionPolicy" = mkOption {
          description = "PVCRetentionPolicy controls whether PVCs are deleted when the StatefulSet is deleted or scaled down.\nRequires Kubernetes 1.23+. If not specified, defaults to Retain for both policies.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStoragePvcRetentionPolicy"
            )
          );
        };
      };

      config = {
        "data" = mkOverride 1002 null;
        "dataFsync" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "metadataAutoSnapshotInterval" = mkOverride 1002 null;
        "metadataFsync" = mkOverride 1002 null;
        "metadataSnapshotsDir" = mkOverride 1002 null;
        "pvcRetentionPolicy" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageData" = {
      options = {
        "paths" = mkOption {
          description = "Paths specifies multiple data directories with capacities\nFor advanced multi-disk configurations. Only valid when Type=PersistentVolumeClaim.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPaths")
            )
          );
        };
        "size" = mkOption {
          description = "Size of the data volume. For PVC: storage request. For EmptyDir: sizeLimit (optional).";
          type = types.nullOr (types.either types.int types.str);
        };
        "storageClassName" = mkOption {
          description = "StorageClassName for the data PVC. Only valid when Type=PersistentVolumeClaim.";
          type = types.nullOr types.str;
        };
        "type" = mkOption {
          description = "Type specifies the volume type: PersistentVolumeClaim (default) or EmptyDir.\nWhen EmptyDir, data is lost on pod restart - only use for testing.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "paths" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "storageClassName" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPaths" = {
      options = {
        "capacity" = mkOption {
          description = "Capacity of the drive (required unless readOnly)";
          type = types.nullOr (types.either types.int types.str);
        };
        "path" = mkOption {
          description = "Path to the data directory";
          type = types.str;
        };
        "readOnly" = mkOption {
          description = "ReadOnly marks directory as legacy read-only for migrations";
          type = types.nullOr types.bool;
        };
        "volume" = mkOption {
          description = "Volume configuration if using PVC";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPathsVolume")
          );
        };
      };

      config = {
        "capacity" = mkOverride 1002 null;
        "readOnly" = mkOverride 1002 null;
        "volume" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPathsVolume" = {
      options = {
        "accessModes" = mkOption {
          description = "AccessModes for the PVC. Only valid when Type=PersistentVolumeClaim.";
          type = types.nullOr (types.listOf types.str);
        };
        "selector" = mkOption {
          description = "Selector to select PVs. Only valid when Type=PersistentVolumeClaim.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPathsVolumeSelector"
            )
          );
        };
        "size" = mkOption {
          description = "Size of the volume.\n- For PVC: storage request (defaults to 10Gi for metadata if not specified)\n- For EmptyDir: optional sizeLimit (if omitted, uses available node resources)";
          type = types.nullOr (types.either types.int types.str);
        };
        "storageClassName" = mkOption {
          description = "StorageClassName for the PVC. Only valid when Type=PersistentVolumeClaim.";
          type = types.nullOr types.str;
        };
        "type" = mkOption {
          description = "Type specifies the volume type: PersistentVolumeClaim (default) or EmptyDir.\nWhen EmptyDir, data is lost on pod restart - only use for testing.";
          type = types.nullOr types.str;
        };
        "volumeClaimTemplateSpec" = mkOption {
          description = "VolumeClaimTemplateSpec allows full customization of the PVC.\nOnly valid when Type=PersistentVolumeClaim.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpec"
            )
          );
        };
      };

      config = {
        "accessModes" = mkOverride 1002 null;
        "selector" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "storageClassName" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
        "volumeClaimTemplateSpec" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPathsVolumeSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPathsVolumeSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPathsVolumeSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpec" = {
      options = {
        "accessModes" = mkOption {
          description = "accessModes contains the desired access modes the volume should have.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#access-modes-1";
          type = types.nullOr (types.listOf types.str);
        };
        "dataSource" = mkOption {
          description = "dataSource field can be used to specify either:\n* An existing VolumeSnapshot object (snapshot.storage.k8s.io/VolumeSnapshot)\n* An existing PVC (PersistentVolumeClaim)\nIf the provisioner or an external controller can support the specified data source,\nit will create a new volume based on the contents of the specified data source.\nWhen the AnyVolumeDataSource feature gate is enabled, dataSource contents will be copied to dataSourceRef,\nand dataSourceRef contents will be copied to dataSource when dataSourceRef.namespace is not specified.\nIf the namespace is specified, then dataSourceRef will not be copied to dataSource.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecDataSource"
            )
          );
        };
        "dataSourceRef" = mkOption {
          description = "dataSourceRef specifies the object from which to populate the volume with data, if a non-empty\nvolume is desired. This may be any object from a non-empty API group (non\ncore object) or a PersistentVolumeClaim object.\nWhen this field is specified, volume binding will only succeed if the type of\nthe specified object matches some installed volume populator or dynamic\nprovisioner.\nThis field will replace the functionality of the dataSource field and as such\nif both fields are non-empty, they must have the same value. For backwards\ncompatibility, when namespace isn't specified in dataSourceRef,\nboth fields (dataSource and dataSourceRef) will be set to the same\nvalue automatically if one of them is empty and the other is non-empty.\nWhen namespace is specified in dataSourceRef,\ndataSource isn't set to the same value and must be empty.\nThere are three important differences between dataSource and dataSourceRef:\n* While dataSource only allows two specific types of objects, dataSourceRef\n  allows any non-core object, as well as PersistentVolumeClaim objects.\n* While dataSource ignores disallowed values (dropping them), dataSourceRef\n  preserves all values, and generates an error if a disallowed value is\n  specified.\n* While dataSource only allows local objects, dataSourceRef allows objects\n  in any namespaces.\n(Beta) Using this field requires the AnyVolumeDataSource feature gate to be enabled.\n(Alpha) Using the namespace field of dataSourceRef requires the CrossNamespaceVolumeDataSource feature gate to be enabled.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecDataSourceRef"
            )
          );
        };
        "resources" = mkOption {
          description = "resources represents the minimum resources the volume should have.\nUsers are allowed to specify resource requirements\nthat are lower than previous value but must still be higher than capacity recorded in the\nstatus field of the claim.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#resources";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecResources"
            )
          );
        };
        "selector" = mkOption {
          description = "selector is a label query over volumes to consider for binding.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecSelector"
            )
          );
        };
        "storageClassName" = mkOption {
          description = "storageClassName is the name of the StorageClass required by the claim.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#class-1";
          type = types.nullOr types.str;
        };
        "volumeAttributesClassName" = mkOption {
          description = "volumeAttributesClassName may be used to set the VolumeAttributesClass used by this claim.\nIf specified, the CSI driver will create or update the volume with the attributes defined\nin the corresponding VolumeAttributesClass. This has a different purpose than storageClassName,\nit can be changed after the claim is created. An empty string or nil value indicates that no\nVolumeAttributesClass will be applied to the claim. If the claim enters an Infeasible error state,\nthis field can be reset to its previous value (including nil) to cancel the modification.\nIf the resource referred to by volumeAttributesClass does not exist, this PersistentVolumeClaim will be\nset to a Pending state, as reflected by the modifyVolumeStatus field, until such as a resource\nexists.\nMore info: https://kubernetes.io/docs/concepts/storage/volume-attributes-classes/";
          type = types.nullOr types.str;
        };
        "volumeMode" = mkOption {
          description = "volumeMode defines what type of volume is required by the claim.\nValue of Filesystem is implied when not included in claim spec.";
          type = types.nullOr types.str;
        };
        "volumeName" = mkOption {
          description = "volumeName is the binding reference to the PersistentVolume backing this claim.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "accessModes" = mkOverride 1002 null;
        "dataSource" = mkOverride 1002 null;
        "dataSourceRef" = mkOverride 1002 null;
        "resources" = mkOverride 1002 null;
        "selector" = mkOverride 1002 null;
        "storageClassName" = mkOverride 1002 null;
        "volumeAttributesClassName" = mkOverride 1002 null;
        "volumeMode" = mkOverride 1002 null;
        "volumeName" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecDataSource" = {
      options = {
        "apiGroup" = mkOption {
          description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "Kind is the type of resource being referenced";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name is the name of resource being referenced";
          type = types.str;
        };
      };

      config = {
        "apiGroup" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecDataSourceRef" = {
      options = {
        "apiGroup" = mkOption {
          description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "Kind is the type of resource being referenced";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name is the name of resource being referenced";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "Namespace is the namespace of resource being referenced\nNote that when a namespace is specified, a gateway.networking.k8s.io/ReferenceGrant object is required in the referent namespace to allow that namespace's owner to accept the reference. See the ReferenceGrant documentation for details.\n(Alpha) This field requires the CrossNamespaceVolumeDataSource feature gate to be enabled.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "apiGroup" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecResources" = {
      options = {
        "limits" = mkOption {
          description = "Limits describes the maximum amount of compute resources allowed.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = types.nullOr (types.attrsOf (types.either types.int types.str));
        };
        "requests" = mkOption {
          description = "Requests describes the minimum amount of compute resources required.\nIf Requests is omitted for a container, it defaults to Limits if that is explicitly specified,\notherwise to an implementation-defined value. Requests cannot exceed Limits.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = types.nullOr (types.attrsOf (types.either types.int types.str));
        };
      };

      config = {
        "limits" = mkOverride 1002 null;
        "requests" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageMetadata" = {
      options = {
        "accessModes" = mkOption {
          description = "AccessModes for the PVC. Only valid when Type=PersistentVolumeClaim.";
          type = types.nullOr (types.listOf types.str);
        };
        "selector" = mkOption {
          description = "Selector to select PVs. Only valid when Type=PersistentVolumeClaim.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageMetadataSelector")
          );
        };
        "size" = mkOption {
          description = "Size of the volume.\n- For PVC: storage request (defaults to 10Gi for metadata if not specified)\n- For EmptyDir: optional sizeLimit (if omitted, uses available node resources)";
          type = types.nullOr (types.either types.int types.str);
        };
        "storageClassName" = mkOption {
          description = "StorageClassName for the PVC. Only valid when Type=PersistentVolumeClaim.";
          type = types.nullOr types.str;
        };
        "type" = mkOption {
          description = "Type specifies the volume type: PersistentVolumeClaim (default) or EmptyDir.\nWhen EmptyDir, data is lost on pod restart - only use for testing.";
          type = types.nullOr types.str;
        };
        "volumeClaimTemplateSpec" = mkOption {
          description = "VolumeClaimTemplateSpec allows full customization of the PVC.\nOnly valid when Type=PersistentVolumeClaim.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpec"
            )
          );
        };
      };

      config = {
        "accessModes" = mkOverride 1002 null;
        "selector" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "storageClassName" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
        "volumeClaimTemplateSpec" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageMetadataSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageMetadataSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageMetadataSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpec" = {
      options = {
        "accessModes" = mkOption {
          description = "accessModes contains the desired access modes the volume should have.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#access-modes-1";
          type = types.nullOr (types.listOf types.str);
        };
        "dataSource" = mkOption {
          description = "dataSource field can be used to specify either:\n* An existing VolumeSnapshot object (snapshot.storage.k8s.io/VolumeSnapshot)\n* An existing PVC (PersistentVolumeClaim)\nIf the provisioner or an external controller can support the specified data source,\nit will create a new volume based on the contents of the specified data source.\nWhen the AnyVolumeDataSource feature gate is enabled, dataSource contents will be copied to dataSourceRef,\nand dataSourceRef contents will be copied to dataSource when dataSourceRef.namespace is not specified.\nIf the namespace is specified, then dataSourceRef will not be copied to dataSource.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecDataSource"
            )
          );
        };
        "dataSourceRef" = mkOption {
          description = "dataSourceRef specifies the object from which to populate the volume with data, if a non-empty\nvolume is desired. This may be any object from a non-empty API group (non\ncore object) or a PersistentVolumeClaim object.\nWhen this field is specified, volume binding will only succeed if the type of\nthe specified object matches some installed volume populator or dynamic\nprovisioner.\nThis field will replace the functionality of the dataSource field and as such\nif both fields are non-empty, they must have the same value. For backwards\ncompatibility, when namespace isn't specified in dataSourceRef,\nboth fields (dataSource and dataSourceRef) will be set to the same\nvalue automatically if one of them is empty and the other is non-empty.\nWhen namespace is specified in dataSourceRef,\ndataSource isn't set to the same value and must be empty.\nThere are three important differences between dataSource and dataSourceRef:\n* While dataSource only allows two specific types of objects, dataSourceRef\n  allows any non-core object, as well as PersistentVolumeClaim objects.\n* While dataSource ignores disallowed values (dropping them), dataSourceRef\n  preserves all values, and generates an error if a disallowed value is\n  specified.\n* While dataSource only allows local objects, dataSourceRef allows objects\n  in any namespaces.\n(Beta) Using this field requires the AnyVolumeDataSource feature gate to be enabled.\n(Alpha) Using the namespace field of dataSourceRef requires the CrossNamespaceVolumeDataSource feature gate to be enabled.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecDataSourceRef"
            )
          );
        };
        "resources" = mkOption {
          description = "resources represents the minimum resources the volume should have.\nUsers are allowed to specify resource requirements\nthat are lower than previous value but must still be higher than capacity recorded in the\nstatus field of the claim.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#resources";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecResources"
            )
          );
        };
        "selector" = mkOption {
          description = "selector is a label query over volumes to consider for binding.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecSelector"
            )
          );
        };
        "storageClassName" = mkOption {
          description = "storageClassName is the name of the StorageClass required by the claim.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#class-1";
          type = types.nullOr types.str;
        };
        "volumeAttributesClassName" = mkOption {
          description = "volumeAttributesClassName may be used to set the VolumeAttributesClass used by this claim.\nIf specified, the CSI driver will create or update the volume with the attributes defined\nin the corresponding VolumeAttributesClass. This has a different purpose than storageClassName,\nit can be changed after the claim is created. An empty string or nil value indicates that no\nVolumeAttributesClass will be applied to the claim. If the claim enters an Infeasible error state,\nthis field can be reset to its previous value (including nil) to cancel the modification.\nIf the resource referred to by volumeAttributesClass does not exist, this PersistentVolumeClaim will be\nset to a Pending state, as reflected by the modifyVolumeStatus field, until such as a resource\nexists.\nMore info: https://kubernetes.io/docs/concepts/storage/volume-attributes-classes/";
          type = types.nullOr types.str;
        };
        "volumeMode" = mkOption {
          description = "volumeMode defines what type of volume is required by the claim.\nValue of Filesystem is implied when not included in claim spec.";
          type = types.nullOr types.str;
        };
        "volumeName" = mkOption {
          description = "volumeName is the binding reference to the PersistentVolume backing this claim.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "accessModes" = mkOverride 1002 null;
        "dataSource" = mkOverride 1002 null;
        "dataSourceRef" = mkOverride 1002 null;
        "resources" = mkOverride 1002 null;
        "selector" = mkOverride 1002 null;
        "storageClassName" = mkOverride 1002 null;
        "volumeAttributesClassName" = mkOverride 1002 null;
        "volumeMode" = mkOverride 1002 null;
        "volumeName" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecDataSource" = {
      options = {
        "apiGroup" = mkOption {
          description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "Kind is the type of resource being referenced";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name is the name of resource being referenced";
          type = types.str;
        };
      };

      config = {
        "apiGroup" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecDataSourceRef" = {
      options = {
        "apiGroup" = mkOption {
          description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "Kind is the type of resource being referenced";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name is the name of resource being referenced";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "Namespace is the namespace of resource being referenced\nNote that when a namespace is specified, a gateway.networking.k8s.io/ReferenceGrant object is required in the referent namespace to allow that namespace's owner to accept the reference. See the ReferenceGrant documentation for details.\n(Alpha) This field requires the CrossNamespaceVolumeDataSource feature gate to be enabled.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "apiGroup" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecResources" = {
      options = {
        "limits" = mkOption {
          description = "Limits describes the maximum amount of compute resources allowed.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = types.nullOr (types.attrsOf (types.either types.int types.str));
        };
        "requests" = mkOption {
          description = "Requests describes the minimum amount of compute resources required.\nIf Requests is omitted for a container, it defaults to Limits if that is explicitly specified,\notherwise to an implementation-defined value. Requests cannot exceed Limits.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = types.nullOr (types.attrsOf (types.either types.int types.str));
        };
      };

      config = {
        "limits" = mkOverride 1002 null;
        "requests" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecStoragePvcRetentionPolicy" = {
      options = {
        "whenDeleted" = mkOption {
          description = "WhenDeleted specifies what happens to PVCs when the StatefulSet is deleted.\n- \"Retain\" (default): PVCs are kept for manual cleanup or data recovery\n- \"Delete\": PVCs are automatically deleted with the StatefulSet";
          type = types.nullOr types.str;
        };
        "whenScaled" = mkOption {
          description = "WhenScaled specifies what happens to PVCs when the StatefulSet is scaled down.\n- \"Retain\" (default): PVCs are kept when scaling down (allows scale back up)\n- \"Delete\": PVCs for removed replicas are deleted";
          type = types.nullOr types.str;
        };
      };

      config = {
        "whenDeleted" = mkOverride 1002 null;
        "whenScaled" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecTolerations" = {
      options = {
        "effect" = mkOption {
          description = "Effect indicates the taint effect to match. Empty means match all taint effects.\nWhen specified, allowed values are NoSchedule, PreferNoSchedule and NoExecute.";
          type = types.nullOr types.str;
        };
        "key" = mkOption {
          description = "Key is the taint key that the toleration applies to. Empty means match all taint keys.\nIf the key is empty, operator must be Exists; this combination means to match all values and all keys.";
          type = types.nullOr types.str;
        };
        "operator" = mkOption {
          description = "Operator represents a key's relationship to the value.\nValid operators are Exists, Equal, Lt, and Gt. Defaults to Equal.\nExists is equivalent to wildcard for value, so that a pod can\ntolerate all taints of a particular category.\nLt and Gt perform numeric comparisons (requires feature gate TaintTolerationComparisonOperators).";
          type = types.nullOr types.str;
        };
        "tolerationSeconds" = mkOption {
          description = "TolerationSeconds represents the period of time the toleration (which must be\nof effect NoExecute, otherwise this field is ignored) tolerates the taint. By default,\nit is not set, which means tolerate the taint forever (do not evict). Zero and\nnegative values will be treated as 0 (evict immediately) by the system.";
          type = types.nullOr types.int;
        };
        "value" = mkOption {
          description = "Value is the taint value the toleration matches to.\nIf the operator is Exists, the value should be empty, otherwise just a regular string.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "effect" = mkOverride 1002 null;
        "key" = mkOverride 1002 null;
        "operator" = mkOverride 1002 null;
        "tolerationSeconds" = mkOverride 1002 null;
        "value" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecTopologySpreadConstraints" = {
      options = {
        "labelSelector" = mkOption {
          description = "LabelSelector is used to find matching pods.\nPods that match this label selector are counted to determine the number of pods\nin their corresponding topology domain.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecTopologySpreadConstraintsLabelSelector"
            )
          );
        };
        "matchLabelKeys" = mkOption {
          description = "MatchLabelKeys is a set of pod label keys to select the pods over which\nspreading will be calculated. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are ANDed with labelSelector\nto select the group of existing pods over which spreading will be calculated\nfor the incoming pod. The same key is forbidden to exist in both MatchLabelKeys and LabelSelector.\nMatchLabelKeys cannot be set when LabelSelector isn't set.\nKeys that don't exist in the incoming pod labels will\nbe ignored. A null or empty list means only match against labelSelector.\n\nThis is a beta field and requires the MatchLabelKeysInPodTopologySpread feature gate to be enabled (enabled by default).";
          type = types.nullOr (types.listOf types.str);
        };
        "maxSkew" = mkOption {
          description = "MaxSkew describes the degree to which pods may be unevenly distributed.\nWhen `whenUnsatisfiable=DoNotSchedule`, it is the maximum permitted difference\nbetween the number of matching pods in the target topology and the global minimum.\nThe global minimum is the minimum number of matching pods in an eligible domain\nor zero if the number of eligible domains is less than MinDomains.\nFor example, in a 3-zone cluster, MaxSkew is set to 1, and pods with the same\nlabelSelector spread as 2/2/1:\nIn this case, the global minimum is 1.\n| zone1 | zone2 | zone3 |\n|  P P  |  P P  |   P   |\n- if MaxSkew is 1, incoming pod can only be scheduled to zone3 to become 2/2/2;\nscheduling it onto zone1(zone2) would make the ActualSkew(3-1) on zone1(zone2)\nviolate MaxSkew(1).\n- if MaxSkew is 2, incoming pod can be scheduled onto any zone.\nWhen `whenUnsatisfiable=ScheduleAnyway`, it is used to give higher precedence\nto topologies that satisfy it.\nIt's a required field. Default value is 1 and 0 is not allowed.";
          type = types.int;
        };
        "minDomains" = mkOption {
          description = "MinDomains indicates a minimum number of eligible domains.\nWhen the number of eligible domains with matching topology keys is less than minDomains,\nPod Topology Spread treats \"global minimum\" as 0, and then the calculation of Skew is performed.\nAnd when the number of eligible domains with matching topology keys equals or greater than minDomains,\nthis value has no effect on scheduling.\nAs a result, when the number of eligible domains is less than minDomains,\nscheduler won't schedule more than maxSkew Pods to those domains.\nIf value is nil, the constraint behaves as if MinDomains is equal to 1.\nValid values are integers greater than 0.\nWhen value is not nil, WhenUnsatisfiable must be DoNotSchedule.\n\nFor example, in a 3-zone cluster, MaxSkew is set to 2, MinDomains is set to 5 and pods with the same\nlabelSelector spread as 2/2/2:\n| zone1 | zone2 | zone3 |\n|  P P  |  P P  |  P P  |\nThe number of domains is less than 5(MinDomains), so \"global minimum\" is treated as 0.\nIn this situation, new pod with the same labelSelector cannot be scheduled,\nbecause computed skew will be 3(3 - 0) if new Pod is scheduled to any of the three zones,\nit will violate MaxSkew.";
          type = types.nullOr types.int;
        };
        "nodeAffinityPolicy" = mkOption {
          description = "NodeAffinityPolicy indicates how we will treat Pod's nodeAffinity/nodeSelector\nwhen calculating pod topology spread skew. Options are:\n- Honor: only nodes matching nodeAffinity/nodeSelector are included in the calculations.\n- Ignore: nodeAffinity/nodeSelector are ignored. All nodes are included in the calculations.\n\nIf this value is nil, the behavior is equivalent to the Honor policy.";
          type = types.nullOr types.str;
        };
        "nodeTaintsPolicy" = mkOption {
          description = "NodeTaintsPolicy indicates how we will treat node taints when calculating\npod topology spread skew. Options are:\n- Honor: nodes without taints, along with tainted nodes for which the incoming pod\nhas a toleration, are included.\n- Ignore: node taints are ignored. All nodes are included.\n\nIf this value is nil, the behavior is equivalent to the Ignore policy.";
          type = types.nullOr types.str;
        };
        "topologyKey" = mkOption {
          description = "TopologyKey is the key of node labels. Nodes that have a label with this key\nand identical values are considered to be in the same topology.\nWe consider each <key, value> as a \"bucket\", and try to put balanced number\nof pods into each bucket.\nWe define a domain as a particular instance of a topology.\nAlso, we define an eligible domain as a domain whose nodes meet the requirements of\nnodeAffinityPolicy and nodeTaintsPolicy.\ne.g. If TopologyKey is \"kubernetes.io/hostname\", each Node is a domain of that topology.\nAnd, if TopologyKey is \"topology.kubernetes.io/zone\", each zone is a domain of that topology.\nIt's a required field.";
          type = types.str;
        };
        "whenUnsatisfiable" = mkOption {
          description = "WhenUnsatisfiable indicates how to deal with a pod if it doesn't satisfy\nthe spread constraint.\n- DoNotSchedule (default) tells the scheduler not to schedule it.\n- ScheduleAnyway tells the scheduler to schedule the pod in any location,\n  but giving higher precedence to topologies that would help reduce the\n  skew.\nA constraint is considered \"Unsatisfiable\" for an incoming pod\nif and only if every possible node assignment for that pod would violate\n\"MaxSkew\" on some topology.\nFor example, in a 3-zone cluster, MaxSkew is set to 1, and pods with the same\nlabelSelector spread as 3/1/1:\n| zone1 | zone2 | zone3 |\n| P P P |   P   |   P   |\nIf WhenUnsatisfiable is set to DoNotSchedule, incoming pod can only be scheduled\nto zone2(zone3) to become 3/2/1(3/1/2) as ActualSkew(2-1) on zone2(zone3) satisfies\nMaxSkew(1). In other words, the cluster can still be imbalanced, but scheduler\nwon't make it *more* imbalanced.\nIt's a required field.";
          type = types.str;
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "matchLabelKeys" = mkOverride 1002 null;
        "minDomains" = mkOverride 1002 null;
        "nodeAffinityPolicy" = mkOverride 1002 null;
        "nodeTaintsPolicy" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecTopologySpreadConstraintsLabelSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterSpecTopologySpreadConstraintsLabelSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecTopologySpreadConstraintsLabelSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterSpecWebApi" = {
      options = {
        "addHostToMetrics" = mkOption {
          description = "AddHostToMetrics adds the domain name to metrics labels for per-domain tracking.";
          type = types.nullOr types.bool;
        };
        "bindAddress" = mkOption {
          description = "BindAddress is a custom bind address for the Web API.\nCan be a TCP address or Unix socket path (e.g., \"unix:///run/garage/web.sock\").\nIf set, this overrides BindPort.";
          type = types.nullOr types.str;
        };
        "bindPort" = mkOption {
          description = "BindPort is the port to bind for web serving";
          type = types.nullOr types.int;
        };
        "enabled" = mkOption {
          description = "Enabled enables static website hosting";
          type = types.nullOr types.bool;
        };
        "rootDomain" = mkOption {
          description = "RootDomain is the root domain suffix for bucket website access.\nWhen set, bucket websites are accessible via <bucket-name>.<root-domain>.\n\nExamples:\n- \".web.garage.tld\" -> Access bucket \"site\" website at \"site.web.garage.tld\"\n- \".sites.example.com\" -> Access bucket \"blog\" at \"blog.sites.example.com\"\n\nNote: Include the leading dot.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "addHostToMetrics" = mkOverride 1002 null;
        "bindAddress" = mkOverride 1002 null;
        "bindPort" = mkOverride 1002 null;
        "enabled" = mkOverride 1002 null;
        "rootDomain" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterStatus" = {
      options = {
        "activeRepairs" = mkOption {
          description = "ActiveRepairs contains currently running repair operations";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterStatusActiveRepairs")
            )
          );
        };
        "blockErrorDetails" = mkOption {
          description = "BlockErrorDetails provides detailed information about block errors";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterStatusBlockErrorDetails")
          );
        };
        "blockErrors" = mkOption {
          description = "BlockErrors is the count of blocks with sync errors across all nodes";
          type = types.nullOr types.int;
        };
        "buildInfo" = mkOption {
          description = "BuildInfo contains Garage build information";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterStatusBuildInfo");
        };
        "clusterId" = mkOption {
          description = "ClusterID is the unique identifier of the Garage cluster";
          type = types.nullOr types.str;
        };
        "conditions" = mkOption {
          description = "Conditions represent the current state of the cluster";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterStatusConditions")
            )
          );
        };
        "drainingNodes" = mkOption {
          description = "DrainingNodes is the count of nodes that are draining data from an older layout version.\nThese nodes had a storage role in a previous layout and are migrating data to other nodes.\nA non-zero value indicates a layout transition is in progress.";
          type = types.nullOr types.int;
        };
        "endpoints" = mkOption {
          description = "Endpoints contains service endpoints";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterStatusEndpoints");
        };
        "health" = mkOption {
          description = "Health contains cluster health information";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterStatusHealth");
        };
        "layoutHistory" = mkOption {
          description = "LayoutHistory contains layout version history";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterStatusLayoutHistory")
          );
        };
        "layoutPreview" = mkOption {
          description = "LayoutPreview shows what would change if staged layout is applied";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterStatusLayoutPreview")
          );
        };
        "layoutVersion" = mkOption {
          description = "LayoutVersion is the current layout version";
          type = types.nullOr types.int;
        };
        "lifecycleStatus" = mkOption {
          description = "LifecycleStatus contains the status of bucket lifecycle operations";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterStatusLifecycleStatus")
          );
        };
        "nodes" = mkOption {
          description = "Nodes contains status information for each node";
          type = (
            types.nullOr (types.listOf (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterStatusNodes"))
          );
        };
        "observedGeneration" = mkOption {
          description = "ObservedGeneration is the last observed generation";
          type = types.nullOr types.int;
        };
        "phase" = mkOption {
          description = "Phase represents the current phase of the cluster";
          type = types.nullOr types.str;
        };
        "readyReplicas" = mkOption {
          description = "ReadyReplicas is the number of ready Garage pods";
          type = types.nullOr types.int;
        };
        "remoteClusters" = mkOption {
          description = "RemoteClusters contains status of remote clusters in the federation";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1alpha1.GarageClusterStatusRemoteClusters"
              "name"
              []
            )
          );
          apply = attrsToList;
        };
        "resyncQueueLength" = mkOption {
          description = "ResyncQueueLength is the total block resync queue depth across all nodes";
          type = types.nullOr types.int;
        };
        "scrubStatus" = mkOption {
          description = "ScrubStatus contains the status of data scrub operations";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterStatusScrubStatus");
        };
        "stagedLayoutVersion" = mkOption {
          description = "StagedLayoutVersion is the staged layout version pending application";
          type = types.nullOr types.int;
        };
        "stagedRoles" = mkOption {
          description = "StagedRoles is the number of roles in the staged layout";
          type = types.nullOr types.int;
        };
        "storageStats" = mkOption {
          description = "StorageStats contains cluster-wide storage statistics";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterStatusStorageStats");
        };
        "totalNodes" = mkOption {
          description = "TotalNodes is the total nodes across all clusters (local + remote)";
          type = types.nullOr types.int;
        };
        "workerCount" = mkOption {
          description = "WorkerCount is the total number of background workers";
          type = types.nullOr types.int;
        };
        "workers" = mkOption {
          description = "Workers contains detailed information about background workers";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterStatusWorkers");
        };
        "workersFailed" = mkOption {
          description = "WorkersFailed is the number of failed workers";
          type = types.nullOr types.int;
        };
      };

      config = {
        "activeRepairs" = mkOverride 1002 null;
        "blockErrorDetails" = mkOverride 1002 null;
        "blockErrors" = mkOverride 1002 null;
        "buildInfo" = mkOverride 1002 null;
        "clusterId" = mkOverride 1002 null;
        "conditions" = mkOverride 1002 null;
        "drainingNodes" = mkOverride 1002 null;
        "endpoints" = mkOverride 1002 null;
        "health" = mkOverride 1002 null;
        "layoutHistory" = mkOverride 1002 null;
        "layoutPreview" = mkOverride 1002 null;
        "layoutVersion" = mkOverride 1002 null;
        "lifecycleStatus" = mkOverride 1002 null;
        "nodes" = mkOverride 1002 null;
        "observedGeneration" = mkOverride 1002 null;
        "phase" = mkOverride 1002 null;
        "readyReplicas" = mkOverride 1002 null;
        "remoteClusters" = mkOverride 1002 null;
        "resyncQueueLength" = mkOverride 1002 null;
        "scrubStatus" = mkOverride 1002 null;
        "stagedLayoutVersion" = mkOverride 1002 null;
        "stagedRoles" = mkOverride 1002 null;
        "storageStats" = mkOverride 1002 null;
        "totalNodes" = mkOverride 1002 null;
        "workerCount" = mkOverride 1002 null;
        "workers" = mkOverride 1002 null;
        "workersFailed" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterStatusActiveRepairs" = {
      options = {
        "nodeId" = mkOption {
          description = "NodeID is the node running this repair";
          type = types.nullOr types.str;
        };
        "progress" = mkOption {
          description = "Progress is a human-readable progress description";
          type = types.nullOr types.str;
        };
        "startedAt" = mkOption {
          description = "StartedAt is when the repair started";
          type = types.nullOr types.str;
        };
        "type" = mkOption {
          description = "Type is the repair operation type (Tables, Blocks, Scrub, Rebalance, etc.)";
          type = types.nullOr types.str;
        };
      };

      config = {
        "nodeId" = mkOverride 1002 null;
        "progress" = mkOverride 1002 null;
        "startedAt" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterStatusBlockErrorDetails" = {
      options = {
        "count" = mkOption {
          description = "Count is the total number of blocks with errors";
          type = types.nullOr types.int;
        };
        "lastErrorAt" = mkOption {
          description = "LastErrorAt is when the most recent block error occurred";
          type = types.nullOr types.str;
        };
        "topErrors" = mkOption {
          description = "TopErrors contains details about the most problematic blocks\nLimited to top 10 blocks by error count";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterStatusBlockErrorDetailsTopErrors"
              )
            )
          );
        };
      };

      config = {
        "count" = mkOverride 1002 null;
        "lastErrorAt" = mkOverride 1002 null;
        "topErrors" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterStatusBlockErrorDetailsTopErrors" = {
      options = {
        "blockHash" = mkOption {
          description = "BlockHash is the hash of the affected block";
          type = types.nullOr types.str;
        };
        "errorCount" = mkOption {
          description = "ErrorCount is the number of times this block failed to sync";
          type = types.nullOr types.int;
        };
        "lastAttempt" = mkOption {
          description = "LastAttempt is when the last sync attempt occurred";
          type = types.nullOr types.str;
        };
        "lastError" = mkOption {
          description = "LastError is the most recent error message for this block";
          type = types.nullOr types.str;
        };
        "nextRetry" = mkOption {
          description = "NextRetry is when the next sync retry is scheduled";
          type = types.nullOr types.str;
        };
      };

      config = {
        "blockHash" = mkOverride 1002 null;
        "errorCount" = mkOverride 1002 null;
        "lastAttempt" = mkOverride 1002 null;
        "lastError" = mkOverride 1002 null;
        "nextRetry" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterStatusBuildInfo" = {
      options = {
        "features" = mkOption {
          description = "Features lists enabled Cargo features";
          type = types.nullOr (types.listOf types.str);
        };
        "rustVersion" = mkOption {
          description = "RustVersion is the Rust compiler version used to build Garage";
          type = types.nullOr types.str;
        };
        "version" = mkOption {
          description = "Version is the Garage version string (e.g., \"v1.0.1\")";
          type = types.nullOr types.str;
        };
      };

      config = {
        "features" = mkOverride 1002 null;
        "rustVersion" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterStatusConditions" = {
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
          type = types.nullOr types.int;
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
    "garage.rajsingh.info.v1alpha1.GarageClusterStatusEndpoints" = {
      options = {
        "admin" = mkOption {
          description = "Admin is the admin API endpoint";
          type = types.nullOr types.str;
        };
        "k2v" = mkOption {
          description = "K2V is the K2V API endpoint";
          type = types.nullOr types.str;
        };
        "metrics" = mkOption {
          description = "Metrics is the Prometheus metrics endpoint (typically Admin + /metrics)";
          type = types.nullOr types.str;
        };
        "rpc" = mkOption {
          description = "RPC is the internal RPC endpoint";
          type = types.nullOr types.str;
        };
        "s3" = mkOption {
          description = "S3 is the S3 API endpoint";
          type = types.nullOr types.str;
        };
        "web" = mkOption {
          description = "Web is the web hosting endpoint";
          type = types.nullOr types.str;
        };
      };

      config = {
        "admin" = mkOverride 1002 null;
        "k2v" = mkOverride 1002 null;
        "metrics" = mkOverride 1002 null;
        "rpc" = mkOverride 1002 null;
        "s3" = mkOverride 1002 null;
        "web" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterStatusHealth" = {
      options = {
        "available" = mkOption {
          description = "Available indicates if quorum is available";
          type = types.nullOr types.bool;
        };
        "connectedNodes" = mkOption {
          description = "ConnectedNodes is the number of currently connected nodes";
          type = types.nullOr types.int;
        };
        "healthy" = mkOption {
          description = "Healthy indicates if all nodes are connected";
          type = types.nullOr types.bool;
        };
        "knownNodes" = mkOption {
          description = "KnownNodes is the number of nodes seen in cluster";
          type = types.nullOr types.int;
        };
        "partitions" = mkOption {
          description = "Partitions is the total partitions in layout";
          type = types.nullOr types.int;
        };
        "partitionsAllOk" = mkOption {
          description = "PartitionsAllOK is partitions with all nodes connected";
          type = types.nullOr types.int;
        };
        "partitionsQuorum" = mkOption {
          description = "PartitionsQuorum is partitions with quorum connectivity";
          type = types.nullOr types.int;
        };
        "status" = mkOption {
          description = "Status is the overall cluster status";
          type = types.nullOr types.str;
        };
        "storageNodes" = mkOption {
          description = "StorageNodes is the number of storage nodes in layout";
          type = types.nullOr types.int;
        };
        "storageNodesOk" = mkOption {
          description = "StorageNodesOK is the number of connected storage nodes";
          type = types.nullOr types.int;
        };
      };

      config = {
        "available" = mkOverride 1002 null;
        "connectedNodes" = mkOverride 1002 null;
        "healthy" = mkOverride 1002 null;
        "knownNodes" = mkOverride 1002 null;
        "partitions" = mkOverride 1002 null;
        "partitionsAllOk" = mkOverride 1002 null;
        "partitionsQuorum" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
        "storageNodes" = mkOverride 1002 null;
        "storageNodesOk" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterStatusLayoutHistory" = {
      options = {
        "currentVersion" = mkOption {
          description = "CurrentVersion is the current layout version";
          type = types.nullOr types.int;
        };
        "minAck" = mkOption {
          description = "MinAck is the minimum acknowledged layout version by all nodes";
          type = types.nullOr types.int;
        };
        "versions" = mkOption {
          description = "Versions contains the history of layout versions";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterStatusLayoutHistoryVersions")
            )
          );
        };
      };

      config = {
        "currentVersion" = mkOverride 1002 null;
        "minAck" = mkOverride 1002 null;
        "versions" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterStatusLayoutHistoryVersions" = {
      options = {
        "gatewayNodes" = mkOption {
          description = "GatewayNodes is the number of gateway nodes in this version";
          type = types.nullOr types.int;
        };
        "status" = mkOption {
          description = "Status is the version status (Current, Draining, Historical)";
          type = types.nullOr types.str;
        };
        "storageNodes" = mkOption {
          description = "StorageNodes is the number of storage nodes in this version";
          type = types.nullOr types.int;
        };
        "version" = mkOption {
          description = "Version is the layout version number";
          type = types.nullOr types.int;
        };
      };

      config = {
        "gatewayNodes" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
        "storageNodes" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterStatusLayoutPreview" = {
      options = {
        "dataTransferEstimate" = mkOption {
          description = "DataTransferEstimate is a human-readable estimate of data movement (e.g., \"~50 GB\")";
          type = types.nullOr types.str;
        };
        "nodesAdded" = mkOption {
          description = "NodesAdded shows node IDs that would be added to the layout";
          type = types.nullOr (types.listOf types.str);
        };
        "nodesModified" = mkOption {
          description = "NodesModified shows node IDs with changed configuration (zone, capacity, tags)";
          type = types.nullOr (types.listOf types.str);
        };
        "nodesRemoved" = mkOption {
          description = "NodesRemoved shows node IDs that would be removed from the layout";
          type = types.nullOr (types.listOf types.str);
        };
        "partitionTransfers" = mkOption {
          description = "PartitionTransfers is the estimated number of partition transfers";
          type = types.nullOr types.int;
        };
        "zonesAffected" = mkOption {
          description = "ZonesAffected shows which zones would be affected by the changes";
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "dataTransferEstimate" = mkOverride 1002 null;
        "nodesAdded" = mkOverride 1002 null;
        "nodesModified" = mkOverride 1002 null;
        "nodesRemoved" = mkOverride 1002 null;
        "partitionTransfers" = mkOverride 1002 null;
        "zonesAffected" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterStatusLifecycleStatus" = {
      options = {
        "lastCompleted" = mkOption {
          description = "LastCompleted is when the last lifecycle worker run completed\n(from lifecycle-last-completed worker variable)";
          type = types.nullOr types.str;
        };
      };

      config = {
        "lastCompleted" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterStatusNodes" = {
      options = {
        "capacity" = mkOption {
          description = "Capacity is the storage capacity of the node";
          type = types.nullOr types.str;
        };
        "connected" = mkOption {
          description = "Connected indicates if the node is connected to the cluster";
          type = types.nullOr types.bool;
        };
        "dataDiskAvailable" = mkOption {
          description = "DataDiskAvailable is the available space on data disk";
          type = types.nullOr types.str;
        };
        "dataDiskTotal" = mkOption {
          description = "DataDiskTotal is the total space on data disk";
          type = types.nullOr types.str;
        };
        "gateway" = mkOption {
          description = "Gateway indicates if the node is gateway-only";
          type = types.nullOr types.bool;
        };
        "metadataDiskAvailable" = mkOption {
          description = "MetadataDiskAvailable is the available space on metadata disk";
          type = types.nullOr types.str;
        };
        "metadataDiskTotal" = mkOption {
          description = "MetadataDiskTotal is the total space on metadata disk";
          type = types.nullOr types.str;
        };
        "nodeId" = mkOption {
          description = "NodeID is the public key of the node";
          type = types.nullOr types.str;
        };
        "podName" = mkOption {
          description = "PodName is the name of the pod running this node";
          type = types.nullOr types.str;
        };
        "version" = mkOption {
          description = "Version is the Garage version running on this node";
          type = types.nullOr types.str;
        };
        "zone" = mkOption {
          description = "Zone is the zone assignment of the node";
          type = types.nullOr types.str;
        };
      };

      config = {
        "capacity" = mkOverride 1002 null;
        "connected" = mkOverride 1002 null;
        "dataDiskAvailable" = mkOverride 1002 null;
        "dataDiskTotal" = mkOverride 1002 null;
        "gateway" = mkOverride 1002 null;
        "metadataDiskAvailable" = mkOverride 1002 null;
        "metadataDiskTotal" = mkOverride 1002 null;
        "nodeId" = mkOverride 1002 null;
        "podName" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
        "zone" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterStatusRemoteClusters" = {
      options = {
        "connected" = mkOption {
          description = "Connected indicates if we can reach this cluster";
          type = types.nullOr types.bool;
        };
        "healthyNodes" = mkOption {
          description = "HealthyNodes is the number of healthy nodes";
          type = types.nullOr types.int;
        };
        "lastSeen" = mkOption {
          description = "LastSeen is when we last successfully connected";
          type = types.nullOr types.str;
        };
        "name" = mkOption {
          description = "Name is the cluster name";
          type = types.nullOr types.str;
        };
        "nodes" = mkOption {
          description = "Nodes is the number of nodes in this cluster";
          type = types.nullOr types.int;
        };
        "zone" = mkOption {
          description = "Zone is the cluster's zone";
          type = types.nullOr types.str;
        };
      };

      config = {
        "connected" = mkOverride 1002 null;
        "healthyNodes" = mkOverride 1002 null;
        "lastSeen" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "nodes" = mkOverride 1002 null;
        "zone" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterStatusScrubStatus" = {
      options = {
        "corruptedBlocks" = mkOption {
          description = "CorruptedBlocks is the number of corrupted blocks found in the last scrub\n(from scrub-corruptions_detected worker variable)";
          type = types.nullOr types.int;
        };
        "lastCompleted" = mkOption {
          description = "LastCompleted is when the last scrub completed (from scrub-last-completed worker variable)";
          type = types.nullOr types.str;
        };
        "nextRun" = mkOption {
          description = "NextRun is when the next scrub is scheduled to run (from scrub-next-run worker variable)";
          type = types.nullOr types.str;
        };
        "nodeStatuses" = mkOption {
          description = "NodeStatuses contains per-node scrub status";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageClusterStatusScrubStatusNodeStatuses"
              )
            )
          );
        };
        "paused" = mkOption {
          description = "Paused indicates if the scrub is paused";
          type = types.nullOr types.bool;
        };
        "progress" = mkOption {
          description = "Progress is a human-readable progress description (e.g., \"45% complete\")";
          type = types.nullOr types.str;
        };
        "running" = mkOption {
          description = "Running indicates if a scrub is currently running on any node";
          type = types.nullOr types.bool;
        };
        "tranquilityLevel" = mkOption {
          description = "TranquilityLevel is the current tranquility setting (higher = less aggressive)";
          type = types.nullOr types.int;
        };
      };

      config = {
        "corruptedBlocks" = mkOverride 1002 null;
        "lastCompleted" = mkOverride 1002 null;
        "nextRun" = mkOverride 1002 null;
        "nodeStatuses" = mkOverride 1002 null;
        "paused" = mkOverride 1002 null;
        "progress" = mkOverride 1002 null;
        "running" = mkOverride 1002 null;
        "tranquilityLevel" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterStatusScrubStatusNodeStatuses" = {
      options = {
        "errorsFound" = mkOption {
          description = "ErrorsFound is the number of errors found on this node";
          type = types.nullOr types.int;
        };
        "itemsChecked" = mkOption {
          description = "ItemsChecked is the number of items checked";
          type = types.nullOr types.int;
        };
        "nodeId" = mkOption {
          description = "NodeID is the node identifier";
          type = types.nullOr types.str;
        };
        "progress" = mkOption {
          description = "Progress percentage (0-100)";
          type = types.nullOr types.int;
        };
        "running" = mkOption {
          description = "Running indicates if scrub is running on this node";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "errorsFound" = mkOverride 1002 null;
        "itemsChecked" = mkOverride 1002 null;
        "nodeId" = mkOverride 1002 null;
        "progress" = mkOverride 1002 null;
        "running" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterStatusStorageStats" = {
      options = {
        "availableCapacity" = mkOption {
          description = "AvailableCapacity is the available storage across all nodes";
          type = types.nullOr (types.either types.int types.str);
        };
        "healthyPartitions" = mkOption {
          description = "HealthyPartitions is the number of partitions with full redundancy";
          type = types.nullOr types.int;
        };
        "totalCapacity" = mkOption {
          description = "TotalCapacity is the total storage capacity across all nodes";
          type = types.nullOr (types.either types.int types.str);
        };
        "totalPartitions" = mkOption {
          description = "TotalPartitions is the total number of partitions in the layout";
          type = types.nullOr types.int;
        };
        "usedCapacity" = mkOption {
          description = "UsedCapacity is the used storage across all nodes";
          type = types.nullOr (types.either types.int types.str);
        };
      };

      config = {
        "availableCapacity" = mkOverride 1002 null;
        "healthyPartitions" = mkOverride 1002 null;
        "totalCapacity" = mkOverride 1002 null;
        "totalPartitions" = mkOverride 1002 null;
        "usedCapacity" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterStatusWorkers" = {
      options = {
        "busy" = mkOption {
          description = "Busy is the number of busy/active workers";
          type = types.nullOr types.int;
        };
        "errored" = mkOption {
          description = "Errored is the number of workers with errors";
          type = types.nullOr types.int;
        };
        "errors" = mkOption {
          description = "Errors contains details about worker errors";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1alpha1.GarageClusterStatusWorkersErrors"
              "name"
              []
            )
          );
          apply = attrsToList;
        };
        "idle" = mkOption {
          description = "Idle is the number of idle workers";
          type = types.nullOr types.int;
        };
        "total" = mkOption {
          description = "Total is the total number of background workers";
          type = types.nullOr types.int;
        };
        "variables" = mkOption {
          description = "Variables contains runtime worker configuration variables\nThese can be adjusted through the Admin API to tune background worker behavior";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "busy" = mkOverride 1002 null;
        "errored" = mkOverride 1002 null;
        "errors" = mkOverride 1002 null;
        "idle" = mkOverride 1002 null;
        "total" = mkOverride 1002 null;
        "variables" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageClusterStatusWorkersErrors" = {
      options = {
        "consecutiveErrors" = mkOption {
          description = "ConsecutiveErrors is the count of consecutive errors";
          type = types.nullOr types.int;
        };
        "lastError" = mkOption {
          description = "LastError is the last error message";
          type = types.nullOr types.str;
        };
        "lastErrorSecsAgo" = mkOption {
          description = "LastErrorSecsAgo is seconds since the last error";
          type = types.nullOr types.int;
        };
        "name" = mkOption {
          description = "Name is the worker name";
          type = types.nullOr types.str;
        };
        "workerId" = mkOption {
          description = "WorkerID is the worker identifier";
          type = types.nullOr types.int;
        };
      };

      config = {
        "consecutiveErrors" = mkOverride 1002 null;
        "lastError" = mkOverride 1002 null;
        "lastErrorSecsAgo" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "workerId" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageKey" = {
      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = types.nullOr types.str;
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta");
        };
        "spec" = mkOption {
          description = "GarageKeySpec defines the desired state of GarageKey";
          type = submoduleOf "garage.rajsingh.info.v1alpha1.GarageKeySpec";
        };
        "status" = mkOption {
          description = "GarageKeyStatus defines the observed state of GarageKey";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageKeyStatus");
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageKeySpec" = {
      options = {
        "allBuckets" = mkOption {
          description = "AllBuckets grants this key access to ALL buckets in the cluster.\nUseful for admin tools, monitoring, or systems that need cluster-wide access.\nUses deny-then-allow to enforce exact permissions: flags set false are actively\nrevoked, not just ignored. Per-bucket permissions (bucketPermissions) run after\nand override additively on top.\n\nThe key must be in the same namespace as the GarageBucket resources for\nbidirectional reconciliation (bucket controller also applies these permissions\nwhen new buckets are created).\n\nNote: ListBuckets returns ALL Garage buckets, including those not managed by\nthe operator. Cluster-wide permissions will be applied to those buckets as well.";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageKeySpecAllBuckets");
        };
        "bucketPermissions" = mkOption {
          description = "BucketPermissions grants this key access to buckets.\n\nNote: Permissions can be granted from either direction:\n- Here (GarageKey.bucketPermissions): Grant this key access to buckets\n- On GarageBucket (GarageBucket.keyPermissions): Grant keys access to the bucket\n\nBoth approaches are equivalent and result in the same Garage API calls.\nUse whichever is more convenient for your workflow:\n- Key-centric: Define all bucket access on the key\n- Bucket-centric: Define all key access on the bucket\n\nIf the same permission is defined in both places, they are merged (not conflicting).";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1alpha1.GarageKeySpecBucketPermissions")
            )
          );
        };
        "clusterRef" = mkOption {
          description = "ClusterRef references the GarageCluster this key belongs to";
          type = submoduleOf "garage.rajsingh.info.v1alpha1.GarageKeySpecClusterRef";
        };
        "expiration" = mkOption {
          description = "Expiration sets when this key expires (RFC 3339 format)\nExample: \"2025-12-31T23:59:59Z\"\nMutually exclusive with NeverExpires";
          type = types.nullOr types.str;
        };
        "importKey" = mkOption {
          description = "ImportKey imports an existing key instead of generating new credentials";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageKeySpecImportKey");
        };
        "name" = mkOption {
          description = "Name is a friendly name for this access key\nIf not set, metadata.name is used";
          type = types.nullOr types.str;
        };
        "neverExpires" = mkOption {
          description = "NeverExpires sets the key to never expire\nMutually exclusive with Expiration";
          type = types.nullOr types.bool;
        };
        "permissions" = mkOption {
          description = "Permissions configures key-level permissions\nNote: For admin API access, use admin tokens configured in GarageCluster";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageKeySpecPermissions");
        };
        "secretTemplate" = mkOption {
          description = "SecretTemplate configures how the secret is generated";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageKeySpecSecretTemplate");
        };
      };

      config = {
        "allBuckets" = mkOverride 1002 null;
        "bucketPermissions" = mkOverride 1002 null;
        "expiration" = mkOverride 1002 null;
        "importKey" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "neverExpires" = mkOverride 1002 null;
        "permissions" = mkOverride 1002 null;
        "secretTemplate" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageKeySpecAllBuckets" = {
      options = {
        "owner" = mkOption {
          description = "Owner allows bucket owner operations on all buckets";
          type = types.nullOr types.bool;
        };
        "read" = mkOption {
          description = "Read allows reading objects from all buckets";
          type = types.nullOr types.bool;
        };
        "write" = mkOption {
          description = "Write allows writing objects to all buckets";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "owner" = mkOverride 1002 null;
        "read" = mkOverride 1002 null;
        "write" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageKeySpecBucketPermissions" = {
      options = {
        "bucketId" = mkOption {
          description = "BucketID references the bucket by its Garage ID";
          type = types.nullOr types.str;
        };
        "bucketRef" = mkOption {
          description = "BucketRef references the GarageBucket by name";
          type = types.nullOr types.str;
        };
        "globalAlias" = mkOption {
          description = "GlobalAlias references the bucket by global alias";
          type = types.nullOr types.str;
        };
        "owner" = mkOption {
          description = "Owner allows bucket owner operations (delete bucket, configure website, etc.)";
          type = types.nullOr types.bool;
        };
        "read" = mkOption {
          description = "Read allows reading objects from the bucket";
          type = types.nullOr types.bool;
        };
        "write" = mkOption {
          description = "Write allows writing objects to the bucket";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "bucketId" = mkOverride 1002 null;
        "bucketRef" = mkOverride 1002 null;
        "globalAlias" = mkOverride 1002 null;
        "owner" = mkOverride 1002 null;
        "read" = mkOverride 1002 null;
        "write" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageKeySpecClusterRef" = {
      options = {
        "kubeConfigSecretRef" = mkOption {
          description = "KubeConfigSecretRef references a secret containing kubeconfig for a remote cluster.\nOnly used for cross-cluster references in multi-cluster federation scenarios.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageKeySpecClusterRefKubeConfigSecretRef"
            )
          );
        };
        "name" = mkOption {
          description = "Name of the GarageCluster";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "Namespace of the GarageCluster (defaults to the same namespace as the referencing resource)";
          type = types.nullOr types.str;
        };
      };

      config = {
        "kubeConfigSecretRef" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageKeySpecClusterRefKubeConfigSecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageKeySpecImportKey" = {
      options = {
        "accessKeyId" = mkOption {
          description = "AccessKeyID is the existing access key ID";
          type = types.nullOr types.str;
        };
        "secretAccessKey" = mkOption {
          description = "SecretAccessKey is the existing secret access key";
          type = types.nullOr types.str;
        };
        "secretRef" = mkOption {
          description = "SecretRef references a secret containing the credentials\nSecret should have keys: access-key-id, secret-access-key";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageKeySpecImportKeySecretRef");
        };
      };

      config = {
        "accessKeyId" = mkOverride 1002 null;
        "secretAccessKey" = mkOverride 1002 null;
        "secretRef" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageKeySpecImportKeySecretRef" = {
      options = {
        "name" = mkOption {
          description = "name is unique within a namespace to reference a secret resource.";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "namespace defines the space within which the secret name must be unique.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageKeySpecPermissions" = {
      options = {
        "createBucket" = mkOption {
          description = "CreateBucket allows this key to create new buckets via the S3 CreateBucket API";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "createBucket" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageKeySpecSecretTemplate" = {
      options = {
        "accessKeyIdKey" = mkOption {
          description = "AccessKeyIDKey is the key name for the access key ID";
          type = types.nullOr types.str;
        };
        "additionalData" = mkOption {
          description = "AdditionalData includes additional key-value pairs in the secret";
          type = types.nullOr (types.attrsOf types.str);
        };
        "annotations" = mkOption {
          description = "Annotations to add to the secret";
          type = types.nullOr (types.attrsOf types.str);
        };
        "endpointKey" = mkOption {
          description = "EndpointKey is the key name for the S3 endpoint (includes http:// scheme)";
          type = types.nullOr types.str;
        };
        "hostKey" = mkOption {
          description = "HostKey is the key name for the S3 host (without scheme, e.g., \"host:port\")";
          type = types.nullOr types.str;
        };
        "includeEndpoint" = mkOption {
          description = "IncludeEndpoint includes the S3 endpoint in the secret\nDefaults to true if not specified";
          type = types.nullOr types.bool;
        };
        "includeRegion" = mkOption {
          description = "IncludeRegion includes the S3 region in the secret\nDefaults to true if not specified";
          type = types.nullOr types.bool;
        };
        "labels" = mkOption {
          description = "Labels to add to the secret";
          type = types.nullOr (types.attrsOf types.str);
        };
        "name" = mkOption {
          description = "Name is the name of the secret to create\nDefaults to the GarageKey name";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "Namespace is the namespace for the secret\nDefaults to the GarageKey namespace";
          type = types.nullOr types.str;
        };
        "regionKey" = mkOption {
          description = "RegionKey is the key name for the S3 region";
          type = types.nullOr types.str;
        };
        "schemeKey" = mkOption {
          description = "SchemeKey is the key name for the endpoint scheme (http or https)";
          type = types.nullOr types.str;
        };
        "secretAccessKeyKey" = mkOption {
          description = "SecretAccessKeyKey is the key name for the secret access key";
          type = types.nullOr types.str;
        };
        "type" = mkOption {
          description = "Type is the secret type";
          type = types.nullOr types.str;
        };
      };

      config = {
        "accessKeyIdKey" = mkOverride 1002 null;
        "additionalData" = mkOverride 1002 null;
        "annotations" = mkOverride 1002 null;
        "endpointKey" = mkOverride 1002 null;
        "hostKey" = mkOverride 1002 null;
        "includeEndpoint" = mkOverride 1002 null;
        "includeRegion" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "regionKey" = mkOverride 1002 null;
        "schemeKey" = mkOverride 1002 null;
        "secretAccessKeyKey" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageKeyStatus" = {
      options = {
        "accessKeyId" = mkOption {
          description = "AccessKeyID is the S3 access key ID";
          type = types.nullOr types.str;
        };
        "buckets" = mkOption {
          description = "Buckets lists buckets this key has access to";
          type = (
            types.nullOr (types.listOf (submoduleOf "garage.rajsingh.info.v1alpha1.GarageKeyStatusBuckets"))
          );
        };
        "clusterWide" = mkOption {
          description = "ClusterWide indicates this key has cluster-wide bucket access via allBuckets";
          type = types.nullOr types.bool;
        };
        "conditions" = mkOption {
          description = "Conditions represent the current state";
          type = (
            types.nullOr (types.listOf (submoduleOf "garage.rajsingh.info.v1alpha1.GarageKeyStatusConditions"))
          );
        };
        "createdAt" = mkOption {
          description = "CreatedAt is when the key was created in Garage";
          type = types.nullOr types.str;
        };
        "effectivePermissions" = mkOption {
          description = "EffectivePermissions shows merged permissions from both bucket and key definitions";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1alpha1.GarageKeyStatusEffectivePermissions")
            )
          );
        };
        "expiration" = mkOption {
          description = "Expiration is when this key expires (if set)";
          type = types.nullOr types.str;
        };
        "expired" = mkOption {
          description = "Expired indicates if this key has expired";
          type = types.nullOr types.bool;
        };
        "keyId" = mkOption {
          description = "KeyID is the Garage-assigned key ID";
          type = types.nullOr types.str;
        };
        "observedGeneration" = mkOption {
          description = "ObservedGeneration is the last observed generation";
          type = types.nullOr types.int;
        };
        "permissions" = mkOption {
          description = "Permissions shows the current permissions for this key";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageKeyStatusPermissions");
        };
        "phase" = mkOption {
          description = "Phase represents the current phase";
          type = types.nullOr types.str;
        };
        "secretRef" = mkOption {
          description = "SecretRef references the created secret";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageKeyStatusSecretRef");
        };
      };

      config = {
        "accessKeyId" = mkOverride 1002 null;
        "buckets" = mkOverride 1002 null;
        "clusterWide" = mkOverride 1002 null;
        "conditions" = mkOverride 1002 null;
        "createdAt" = mkOverride 1002 null;
        "effectivePermissions" = mkOverride 1002 null;
        "expiration" = mkOverride 1002 null;
        "expired" = mkOverride 1002 null;
        "keyId" = mkOverride 1002 null;
        "observedGeneration" = mkOverride 1002 null;
        "permissions" = mkOverride 1002 null;
        "phase" = mkOverride 1002 null;
        "secretRef" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageKeyStatusBuckets" = {
      options = {
        "bucketId" = mkOption {
          description = "BucketID is the bucket ID";
          type = types.nullOr types.str;
        };
        "globalAlias" = mkOption {
          description = "GlobalAlias is the bucket's global alias";
          type = types.nullOr types.str;
        };
        "localAlias" = mkOption {
          description = "LocalAlias is this key's local alias for the bucket";
          type = types.nullOr types.str;
        };
        "owner" = mkOption {
          description = "Owner permission";
          type = types.nullOr types.bool;
        };
        "read" = mkOption {
          description = "Read permission";
          type = types.nullOr types.bool;
        };
        "write" = mkOption {
          description = "Write permission";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "bucketId" = mkOverride 1002 null;
        "globalAlias" = mkOverride 1002 null;
        "localAlias" = mkOverride 1002 null;
        "owner" = mkOverride 1002 null;
        "read" = mkOverride 1002 null;
        "write" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageKeyStatusConditions" = {
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
          type = types.nullOr types.int;
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
    "garage.rajsingh.info.v1alpha1.GarageKeyStatusEffectivePermissions" = {
      options = {
        "bucketAlias" = mkOption {
          description = "BucketAlias is the bucket's global alias (if set)";
          type = types.nullOr types.str;
        };
        "bucketId" = mkOption {
          description = "BucketID is the bucket ID";
          type = types.nullOr types.str;
        };
        "owner" = mkOption {
          description = "Owner permission";
          type = types.nullOr types.bool;
        };
        "read" = mkOption {
          description = "Read permission";
          type = types.nullOr types.bool;
        };
        "source" = mkOption {
          description = "Source indicates where this permission was defined (\"bucket\", \"key\", or \"both\")";
          type = types.nullOr types.str;
        };
        "write" = mkOption {
          description = "Write permission";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "bucketAlias" = mkOverride 1002 null;
        "bucketId" = mkOverride 1002 null;
        "owner" = mkOverride 1002 null;
        "read" = mkOverride 1002 null;
        "source" = mkOverride 1002 null;
        "write" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageKeyStatusPermissions" = {
      options = {
        "createBucket" = mkOption {
          description = "CreateBucket allows this key to create new buckets via the S3 CreateBucket API";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "createBucket" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageKeyStatusSecretRef" = {
      options = {
        "name" = mkOption {
          description = "name is unique within a namespace to reference a secret resource.";
          type = types.nullOr types.str;
        };
        "namespace" = mkOption {
          description = "namespace defines the space within which the secret name must be unique.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNode" = {
      options = {
        "apiVersion" = mkOption {
          description = "APIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources";
          type = types.nullOr types.str;
        };
        "kind" = mkOption {
          description = "Kind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds";
          type = types.nullOr types.str;
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta");
        };
        "spec" = mkOption {
          description = "GarageNodeSpec defines the desired state of GarageNode.\n\nGarageNode represents a node in the Garage cluster. When the parent GarageCluster\nhas layoutPolicy: Manual, each GarageNode creates its own StatefulSet (replica 1)\nwith independent storage configuration.\n\nUse GarageNode when you need:\n- Heterogeneous storage (different storage classes per node)\n- Per-node resource configuration\n- Fine-grained zone/capacity control\n- External nodes (VMs, other K8s clusters)\n\nPod configuration (resources, nodeSelector, tolerations, etc.) is inherited from\nthe parent GarageCluster and can be overridden per-node.";
          type = submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpec";
        };
        "status" = mkOption {
          description = "GarageNodeStatus defines the observed state of GarageNode";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeStatus");
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpec" = {
      options = {
        "affinity" = mkOption {
          description = "Affinity overrides pod affinity rules.\nIf not specified, inherits from GarageCluster.";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinity");
        };
        "capacity" = mkOption {
          description = "Capacity is the storage capacity to report to Garage for this node.\nRequired unless Gateway is true.";
          type = types.nullOr (types.either types.int types.str);
        };
        "clusterRef" = mkOption {
          description = "ClusterRef references the GarageCluster this node belongs to.\nThe GarageNode inherits configuration from this cluster.";
          type = submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecClusterRef";
        };
        "external" = mkOption {
          description = "External marks this node as an external node (not managed by this operator).\nWhen set, no StatefulSet is created - the node is assumed to exist externally.";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecExternal");
        };
        "gateway" = mkOption {
          description = "Gateway marks this node as a gateway-only node (no storage).\nGateway nodes handle API requests but don't store data blocks.";
          type = types.nullOr types.bool;
        };
        "image" = mkOption {
          description = "Image overrides the Garage container image.\nIf not specified, inherits from GarageCluster.";
          type = types.nullOr types.str;
        };
        "imageRepository" = mkOption {
          description = "ImageRepository overrides just the repository portion of the Garage image.\nIf not specified, inherits from GarageCluster.\nIgnored if image is set.";
          type = types.nullOr types.str;
        };
        "nodeId" = mkOption {
          description = "NodeID is the public key of the Garage node.\nIf not specified, the operator will auto-discover from the pod.";
          type = types.nullOr types.str;
        };
        "nodeSelector" = mkOption {
          description = "NodeSelector overrides node selection constraints.\nIf not specified, inherits from GarageCluster.";
          type = types.nullOr (types.attrsOf types.str);
        };
        "podAnnotations" = mkOption {
          description = "PodAnnotations are additional annotations to add to this node's pod.\nMerged with annotations from GarageCluster (node-specific takes precedence).";
          type = types.nullOr (types.attrsOf types.str);
        };
        "podLabels" = mkOption {
          description = "PodLabels are additional labels to add to this node's pod.\nMerged with labels from GarageCluster (node-specific takes precedence).";
          type = types.nullOr (types.attrsOf types.str);
        };
        "priorityClassName" = mkOption {
          description = "PriorityClassName overrides the priority class for this node's pod.\nIf not specified, inherits from GarageCluster.";
          type = types.nullOr types.str;
        };
        "resources" = mkOption {
          description = "Resources overrides compute resources for the Garage container.\nIf not specified, inherits from GarageCluster.";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecResources");
        };
        "storage" = mkOption {
          description = "Storage configures storage volumes for this node's StatefulSet.\nRequired when not using External.";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecStorage");
        };
        "tags" = mkOption {
          description = "Tags are custom tags for this node in the Garage layout.";
          type = types.nullOr (types.listOf types.str);
        };
        "tolerations" = mkOption {
          description = "Tolerations overrides pod tolerations.\nIf not specified, inherits from GarageCluster.";
          type = (
            types.nullOr (types.listOf (submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecTolerations"))
          );
        };
        "zone" = mkOption {
          description = "Zone is the zone assignment for this node.\nUsed for data placement and fault tolerance.";
          type = types.str;
        };
      };

      config = {
        "affinity" = mkOverride 1002 null;
        "capacity" = mkOverride 1002 null;
        "external" = mkOverride 1002 null;
        "gateway" = mkOverride 1002 null;
        "image" = mkOverride 1002 null;
        "imageRepository" = mkOverride 1002 null;
        "nodeId" = mkOverride 1002 null;
        "nodeSelector" = mkOverride 1002 null;
        "podAnnotations" = mkOverride 1002 null;
        "podLabels" = mkOverride 1002 null;
        "priorityClassName" = mkOverride 1002 null;
        "resources" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "tags" = mkOverride 1002 null;
        "tolerations" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinity" = {
      options = {
        "nodeAffinity" = mkOption {
          description = "Describes node affinity scheduling rules for the pod.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityNodeAffinity")
          );
        };
        "podAffinity" = mkOption {
          description = "Describes pod affinity scheduling rules (e.g. co-locate this pod in the same node, zone, etc. as some other pod(s)).";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinity")
          );
        };
        "podAntiAffinity" = mkOption {
          description = "Describes pod anti-affinity scheduling rules (e.g. avoid putting this pod in the same node, zone, etc. as some other pod(s)).";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinity")
          );
        };
      };

      config = {
        "nodeAffinity" = mkOverride 1002 null;
        "podAffinity" = mkOverride 1002 null;
        "podAntiAffinity" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityNodeAffinity" = {
      options = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "The scheduler will prefer to schedule pods to nodes that satisfy\nthe affinity expressions specified by this field, but it may choose\na node that violates one or more of the expressions. The node that is\nmost preferred is the one with the greatest sum of weights, i.e.\nfor each node that meets all of the scheduling requirements (resource\nrequest, requiredDuringScheduling affinity expressions, etc.),\ncompute a sum by iterating through the elements of this field and adding\n\"weight\" to the sum if the node matches the corresponding matchExpressions; the\nnode(s) with the highest sum are the most preferred.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "If the affinity requirements specified by this field are not met at\nscheduling time, the pod will not be scheduled onto the node.\nIf the affinity requirements specified by this field cease to be met\nat some point during pod execution (e.g. due to an update), the system\nmay or may not try to eventually evict the pod from its node.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecution"
            )
          );
        };
      };

      config = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecution" = {
      options = {
        "preference" = mkOption {
          description = "A node selector term, associated with the corresponding weight.";
          type = (
            submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreference"
          );
        };
        "weight" = mkOption {
          description = "Weight associated with matching the corresponding nodeSelectorTerm, in the range 1-100.";
          type = types.int;
        };
      };

      config = {};
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreference" = {
      options = {
        "matchExpressions" = mkOption {
          description = "A list of node selector requirements by node's labels.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchExpressions"
              )
            )
          );
        };
        "matchFields" = mkOption {
          description = "A list of node selector requirements by node's fields.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchFields"
              )
            )
          );
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchFields" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchExpressions" = {
      options = {
        "key" = mkOption {
          description = "The label key that the selector applies to.";
          type = types.str;
        };
        "operator" = mkOption {
          description = "Represents a key's relationship to a set of values.\nValid operators are In, NotIn, Exists, DoesNotExist. Gt, and Lt.";
          type = types.str;
        };
        "values" = mkOption {
          description = "An array of string values. If the operator is In or NotIn,\nthe values array must be non-empty. If the operator is Exists or DoesNotExist,\nthe values array must be empty. If the operator is Gt or Lt, the values\narray must have a single element, which will be interpreted as an integer.\nThis array is replaced during a strategic merge patch.";
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchFields" = {
      options = {
        "key" = mkOption {
          description = "The label key that the selector applies to.";
          type = types.str;
        };
        "operator" = mkOption {
          description = "Represents a key's relationship to a set of values.\nValid operators are In, NotIn, Exists, DoesNotExist. Gt, and Lt.";
          type = types.str;
        };
        "values" = mkOption {
          description = "An array of string values. If the operator is In or NotIn,\nthe values array must be non-empty. If the operator is Exists or DoesNotExist,\nthe values array must be empty. If the operator is Gt or Lt, the values\narray must have a single element, which will be interpreted as an integer.\nThis array is replaced during a strategic merge patch.";
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecution" = {
      options = {
        "nodeSelectorTerms" = mkOption {
          description = "Required. A list of node selector terms. The terms are ORed.";
          type = (
            types.listOf (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTerms"
            )
          );
        };
      };

      config = {};
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTerms" = {
      options = {
        "matchExpressions" = mkOption {
          description = "A list of node selector requirements by node's labels.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchExpressions"
              )
            )
          );
        };
        "matchFields" = mkOption {
          description = "A list of node selector requirements by node's fields.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchFields"
              )
            )
          );
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchFields" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchExpressions" = {
      options = {
        "key" = mkOption {
          description = "The label key that the selector applies to.";
          type = types.str;
        };
        "operator" = mkOption {
          description = "Represents a key's relationship to a set of values.\nValid operators are In, NotIn, Exists, DoesNotExist. Gt, and Lt.";
          type = types.str;
        };
        "values" = mkOption {
          description = "An array of string values. If the operator is In or NotIn,\nthe values array must be non-empty. If the operator is Exists or DoesNotExist,\nthe values array must be empty. If the operator is Gt or Lt, the values\narray must have a single element, which will be interpreted as an integer.\nThis array is replaced during a strategic merge patch.";
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchFields" = {
      options = {
        "key" = mkOption {
          description = "The label key that the selector applies to.";
          type = types.str;
        };
        "operator" = mkOption {
          description = "Represents a key's relationship to a set of values.\nValid operators are In, NotIn, Exists, DoesNotExist. Gt, and Lt.";
          type = types.str;
        };
        "values" = mkOption {
          description = "An array of string values. If the operator is In or NotIn,\nthe values array must be non-empty. If the operator is Exists or DoesNotExist,\nthe values array must be empty. If the operator is Gt or Lt, the values\narray must have a single element, which will be interpreted as an integer.\nThis array is replaced during a strategic merge patch.";
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinity" = {
      options = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "The scheduler will prefer to schedule pods to nodes that satisfy\nthe affinity expressions specified by this field, but it may choose\na node that violates one or more of the expressions. The node that is\nmost preferred is the one with the greatest sum of weights, i.e.\nfor each node that meets all of the scheduling requirements (resource\nrequest, requiredDuringScheduling affinity expressions, etc.),\ncompute a sum by iterating through the elements of this field and adding\n\"weight\" to the sum if the node has pods which matches the corresponding podAffinityTerm; the\nnode(s) with the highest sum are the most preferred.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "If the affinity requirements specified by this field are not met at\nscheduling time, the pod will not be scheduled onto the node.\nIf the affinity requirements specified by this field cease to be met\nat some point during pod execution (e.g. due to a pod label update), the\nsystem may or may not try to eventually evict the pod from its node.\nWhen there are multiple elements, the lists of nodes corresponding to each\npodAffinityTerm are intersected, i.e. all terms must be satisfied.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
      };

      config = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecution" = {
      options = {
        "podAffinityTerm" = mkOption {
          description = "Required. A pod affinity term, associated with the corresponding weight.";
          type = (
            submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm"
          );
        };
        "weight" = mkOption {
          description = "weight associated with matching the corresponding podAffinityTerm,\nin the range 1-100.";
          type = types.int;
        };
      };

      config = {};
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm" = {
      options = {
        "labelSelector" = mkOption {
          description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector"
            )
          );
        };
        "matchLabelKeys" = mkOption {
          description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
          type = types.nullOr (types.listOf types.str);
        };
        "mismatchLabelKeys" = mkOption {
          description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
          type = types.nullOr (types.listOf types.str);
        };
        "namespaceSelector" = mkOption {
          description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector"
            )
          );
        };
        "namespaces" = mkOption {
          description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
          type = types.nullOr (types.listOf types.str);
        };
        "topologyKey" = mkOption {
          description = "This pod should be co-located (affinity) or not co-located (anti-affinity) with the pods matching\nthe labelSelector in the specified namespaces, where co-located is defined as running on a node\nwhose value of the label with key topologyKey matches that of any node on which any of the\nselected pods is running.\nEmpty topologyKey is not allowed.";
          type = types.str;
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "matchLabelKeys" = mkOverride 1002 null;
        "mismatchLabelKeys" = mkOverride 1002 null;
        "namespaceSelector" = mkOverride 1002 null;
        "namespaces" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecution" = {
      options = {
        "labelSelector" = mkOption {
          description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector"
            )
          );
        };
        "matchLabelKeys" = mkOption {
          description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
          type = types.nullOr (types.listOf types.str);
        };
        "mismatchLabelKeys" = mkOption {
          description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
          type = types.nullOr (types.listOf types.str);
        };
        "namespaceSelector" = mkOption {
          description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector"
            )
          );
        };
        "namespaces" = mkOption {
          description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
          type = types.nullOr (types.listOf types.str);
        };
        "topologyKey" = mkOption {
          description = "This pod should be co-located (affinity) or not co-located (anti-affinity) with the pods matching\nthe labelSelector in the specified namespaces, where co-located is defined as running on a node\nwhose value of the label with key topologyKey matches that of any node on which any of the\nselected pods is running.\nEmpty topologyKey is not allowed.";
          type = types.str;
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "matchLabelKeys" = mkOverride 1002 null;
        "mismatchLabelKeys" = mkOverride 1002 null;
        "namespaceSelector" = mkOverride 1002 null;
        "namespaces" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinity" = {
      options = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "The scheduler will prefer to schedule pods to nodes that satisfy\nthe anti-affinity expressions specified by this field, but it may choose\na node that violates one or more of the expressions. The node that is\nmost preferred is the one with the greatest sum of weights, i.e.\nfor each node that meets all of the scheduling requirements (resource\nrequest, requiredDuringScheduling anti-affinity expressions, etc.),\ncompute a sum by iterating through the elements of this field and subtracting\n\"weight\" from the sum if the node has pods which matches the corresponding podAffinityTerm; the\nnode(s) with the highest sum are the most preferred.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "If the anti-affinity requirements specified by this field are not met at\nscheduling time, the pod will not be scheduled onto the node.\nIf the anti-affinity requirements specified by this field cease to be met\nat some point during pod execution (e.g. due to a pod label update), the\nsystem may or may not try to eventually evict the pod from its node.\nWhen there are multiple elements, the lists of nodes corresponding to each\npodAffinityTerm are intersected, i.e. all terms must be satisfied.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
      };

      config = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecution" = {
      options = {
        "podAffinityTerm" = mkOption {
          description = "Required. A pod affinity term, associated with the corresponding weight.";
          type = (
            submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm"
          );
        };
        "weight" = mkOption {
          description = "weight associated with matching the corresponding podAffinityTerm,\nin the range 1-100.";
          type = types.int;
        };
      };

      config = {};
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm" = {
      options = {
        "labelSelector" = mkOption {
          description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector"
            )
          );
        };
        "matchLabelKeys" = mkOption {
          description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
          type = types.nullOr (types.listOf types.str);
        };
        "mismatchLabelKeys" = mkOption {
          description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
          type = types.nullOr (types.listOf types.str);
        };
        "namespaceSelector" = mkOption {
          description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector"
            )
          );
        };
        "namespaces" = mkOption {
          description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
          type = types.nullOr (types.listOf types.str);
        };
        "topologyKey" = mkOption {
          description = "This pod should be co-located (affinity) or not co-located (anti-affinity) with the pods matching\nthe labelSelector in the specified namespaces, where co-located is defined as running on a node\nwhose value of the label with key topologyKey matches that of any node on which any of the\nselected pods is running.\nEmpty topologyKey is not allowed.";
          type = types.str;
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "matchLabelKeys" = mkOverride 1002 null;
        "mismatchLabelKeys" = mkOverride 1002 null;
        "namespaceSelector" = mkOverride 1002 null;
        "namespaces" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecution" = {
      options = {
        "labelSelector" = mkOption {
          description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector"
            )
          );
        };
        "matchLabelKeys" = mkOption {
          description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
          type = types.nullOr (types.listOf types.str);
        };
        "mismatchLabelKeys" = mkOption {
          description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
          type = types.nullOr (types.listOf types.str);
        };
        "namespaceSelector" = mkOption {
          description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector"
            )
          );
        };
        "namespaces" = mkOption {
          description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
          type = types.nullOr (types.listOf types.str);
        };
        "topologyKey" = mkOption {
          description = "This pod should be co-located (affinity) or not co-located (anti-affinity) with the pods matching\nthe labelSelector in the specified namespaces, where co-located is defined as running on a node\nwhose value of the label with key topologyKey matches that of any node on which any of the\nselected pods is running.\nEmpty topologyKey is not allowed.";
          type = types.str;
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "matchLabelKeys" = mkOverride 1002 null;
        "mismatchLabelKeys" = mkOverride 1002 null;
        "namespaceSelector" = mkOverride 1002 null;
        "namespaces" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector" = {
      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions"
              )
            )
          );
        };
        "matchLabels" = mkOption {
          description = "matchLabels is a map of {key,value} pairs. A single {key,value} in the matchLabels\nmap is equivalent to an element of matchExpressions, whose key field is \"key\", the\noperator is \"In\", and the values array contains only \"value\". The requirements are ANDed.";
          type = types.nullOr (types.attrsOf types.str);
        };
      };

      config = {
        "matchExpressions" = mkOverride 1002 null;
        "matchLabels" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions" = {
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
          type = types.nullOr (types.listOf types.str);
        };
      };

      config = {
        "values" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecClusterRef" = {
      options = {
        "kubeConfigSecretRef" = mkOption {
          description = "KubeConfigSecretRef references a secret containing kubeconfig for a remote cluster.\nOnly used for cross-cluster references in multi-cluster federation scenarios.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecClusterRefKubeConfigSecretRef"
            )
          );
        };
        "name" = mkOption {
          description = "Name of the GarageCluster";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "Namespace of the GarageCluster (defaults to the same namespace as the referencing resource)";
          type = types.nullOr types.str;
        };
      };

      config = {
        "kubeConfigSecretRef" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecClusterRefKubeConfigSecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecExternal" = {
      options = {
        "address" = mkOption {
          description = "Address is the IP or hostname of the external node";
          type = types.str;
        };
        "port" = mkOption {
          description = "Port is the RPC port of the external node";
          type = types.nullOr types.int;
        };
        "remoteClusterRef" = mkOption {
          description = "RemoteClusterRef references a GarageCluster in another namespace/cluster";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecExternalRemoteClusterRef")
          );
        };
      };

      config = {
        "port" = mkOverride 1002 null;
        "remoteClusterRef" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecExternalRemoteClusterRef" = {
      options = {
        "kubeConfigSecretRef" = mkOption {
          description = "KubeConfigSecretRef references a secret containing kubeconfig for a remote cluster.\nOnly used for cross-cluster references in multi-cluster federation scenarios.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecExternalRemoteClusterRefKubeConfigSecretRef"
            )
          );
        };
        "name" = mkOption {
          description = "Name of the GarageCluster";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "Namespace of the GarageCluster (defaults to the same namespace as the referencing resource)";
          type = types.nullOr types.str;
        };
      };

      config = {
        "kubeConfigSecretRef" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecExternalRemoteClusterRefKubeConfigSecretRef" = {
      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = types.nullOr types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = types.nullOr types.bool;
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecResources" = {
      options = {
        "claims" = mkOption {
          description = "Claims lists the names of resources, defined in spec.resourceClaims,\nthat are used by this container.\n\nThis field depends on the\nDynamicResourceAllocation feature gate.\n\nThis field is immutable. It can only be set for containers.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1alpha1.GarageNodeSpecResourcesClaims"
              "name"
              ["name"]
            )
          );
          apply = attrsToList;
        };
        "limits" = mkOption {
          description = "Limits describes the maximum amount of compute resources allowed.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = types.nullOr (types.attrsOf (types.either types.int types.str));
        };
        "requests" = mkOption {
          description = "Requests describes the minimum amount of compute resources required.\nIf Requests is omitted for a container, it defaults to Limits if that is explicitly specified,\notherwise to an implementation-defined value. Requests cannot exceed Limits.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = types.nullOr (types.attrsOf (types.either types.int types.str));
        };
      };

      config = {
        "claims" = mkOverride 1002 null;
        "limits" = mkOverride 1002 null;
        "requests" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecResourcesClaims" = {
      options = {
        "name" = mkOption {
          description = "Name must match the name of one entry in pod.spec.resourceClaims of\nthe Pod where this field is used. It makes that resource available\ninside a container.";
          type = types.str;
        };
        "request" = mkOption {
          description = "Request is the name chosen for a request in the referenced claim.\nIf empty, everything from the claim is made available, otherwise\nonly the result of this request.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "request" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecStorage" = {
      options = {
        "data" = mkOption {
          description = "Data volume configuration for block storage.\nIgnored if the node is a gateway (Gateway: true).";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecStorageData");
        };
        "metadata" = mkOption {
          description = "Metadata volume configuration for node identity and cluster state.\nRequired for all nodes (storage and gateway).";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeSpecStorageMetadata");
        };
      };

      config = {
        "data" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecStorageData" = {
      options = {
        "existingClaim" = mkOption {
          description = "ExistingClaim references a pre-existing PVC by name.\nThe PVC must exist in the same namespace as the GarageCluster.\nMutually exclusive with Size.";
          type = types.nullOr types.str;
        };
        "size" = mkOption {
          description = "Size for a dynamically provisioned PVC.\nThe operator will create a PVC with this size if it doesn't exist.\nMutually exclusive with ExistingClaim.";
          type = types.nullOr (types.either types.int types.str);
        };
        "storageClassName" = mkOption {
          description = "StorageClassName for dynamically provisioned PVC.\nOnly used when Size is specified.\nIf not specified, the cluster's default storage class is used.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "existingClaim" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "storageClassName" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecStorageMetadata" = {
      options = {
        "existingClaim" = mkOption {
          description = "ExistingClaim references a pre-existing PVC by name.\nThe PVC must exist in the same namespace as the GarageCluster.\nMutually exclusive with Size.";
          type = types.nullOr types.str;
        };
        "size" = mkOption {
          description = "Size for a dynamically provisioned PVC.\nThe operator will create a PVC with this size if it doesn't exist.\nMutually exclusive with ExistingClaim.";
          type = types.nullOr (types.either types.int types.str);
        };
        "storageClassName" = mkOption {
          description = "StorageClassName for dynamically provisioned PVC.\nOnly used when Size is specified.\nIf not specified, the cluster's default storage class is used.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "existingClaim" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "storageClassName" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeSpecTolerations" = {
      options = {
        "effect" = mkOption {
          description = "Effect indicates the taint effect to match. Empty means match all taint effects.\nWhen specified, allowed values are NoSchedule, PreferNoSchedule and NoExecute.";
          type = types.nullOr types.str;
        };
        "key" = mkOption {
          description = "Key is the taint key that the toleration applies to. Empty means match all taint keys.\nIf the key is empty, operator must be Exists; this combination means to match all values and all keys.";
          type = types.nullOr types.str;
        };
        "operator" = mkOption {
          description = "Operator represents a key's relationship to the value.\nValid operators are Exists, Equal, Lt, and Gt. Defaults to Equal.\nExists is equivalent to wildcard for value, so that a pod can\ntolerate all taints of a particular category.\nLt and Gt perform numeric comparisons (requires feature gate TaintTolerationComparisonOperators).";
          type = types.nullOr types.str;
        };
        "tolerationSeconds" = mkOption {
          description = "TolerationSeconds represents the period of time the toleration (which must be\nof effect NoExecute, otherwise this field is ignored) tolerates the taint. By default,\nit is not set, which means tolerate the taint forever (do not evict). Zero and\nnegative values will be treated as 0 (evict immediately) by the system.";
          type = types.nullOr types.int;
        };
        "value" = mkOption {
          description = "Value is the taint value the toleration matches to.\nIf the operator is Exists, the value should be empty, otherwise just a regular string.";
          type = types.nullOr types.str;
        };
      };

      config = {
        "effect" = mkOverride 1002 null;
        "key" = mkOverride 1002 null;
        "operator" = mkOverride 1002 null;
        "tolerationSeconds" = mkOverride 1002 null;
        "value" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeStatus" = {
      options = {
        "address" = mkOption {
          description = "Address is the node's address in the cluster";
          type = types.nullOr types.str;
        };
        "blockErrors" = mkOption {
          description = "BlockErrors is the count of blocks with sync errors on this node";
          type = types.nullOr types.int;
        };
        "conditions" = mkOption {
          description = "Conditions represent the current state";
          type = (
            types.nullOr (types.listOf (submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeStatusConditions"))
          );
        };
        "connected" = mkOption {
          description = "Connected indicates if the node is currently connected";
          type = types.nullOr types.bool;
        };
        "dataPartition" = mkOption {
          description = "DataPartition contains disk space info for the data partition\nNote: Garage reports a single partition even with multiple data paths";
          type = types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeStatusDataPartition");
        };
        "dbEngine" = mkOption {
          description = "DBEngine is the database engine used by this node (lmdb, sqlite, fjall)";
          type = types.nullOr types.str;
        };
        "garageFeatures" = mkOption {
          description = "GarageFeatures lists the enabled Cargo features on this node";
          type = types.nullOr (types.listOf types.str);
        };
        "hostname" = mkOption {
          description = "Hostname is the hostname reported by this Garage node";
          type = types.nullOr types.str;
        };
        "inLayout" = mkOption {
          description = "InLayout indicates if this node is part of the current layout";
          type = types.nullOr types.bool;
        };
        "lastSeen" = mkOption {
          description = "LastSeen is when the node was last seen connected";
          type = types.nullOr types.str;
        };
        "layoutVersion" = mkOption {
          description = "LayoutVersion is the layout version when this node was added";
          type = types.nullOr types.int;
        };
        "metadataPartition" = mkOption {
          description = "MetadataPartition contains disk space info for the metadata partition";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageNodeStatusMetadataPartition")
          );
        };
        "nodeId" = mkOption {
          description = "NodeID is the discovered or assigned node ID";
          type = types.nullOr types.str;
        };
        "observedGeneration" = mkOption {
          description = "ObservedGeneration is the last observed generation";
          type = types.nullOr types.int;
        };
        "partitions" = mkOption {
          description = "Partitions is the number of partitions assigned to this node";
          type = types.nullOr types.int;
        };
        "phase" = mkOption {
          description = "Phase represents the current phase";
          type = types.nullOr types.str;
        };
        "repairInProgress" = mkOption {
          description = "RepairInProgress indicates if a repair operation is running";
          type = types.nullOr types.bool;
        };
        "repairProgress" = mkOption {
          description = "RepairProgress is a human-readable repair progress description";
          type = types.nullOr types.str;
        };
        "repairType" = mkOption {
          description = "RepairType is the type of repair operation in progress";
          type = types.nullOr types.str;
        };
        "storedData" = mkOption {
          description = "StoredData is the amount of data stored on this node";
          type = types.nullOr types.str;
        };
        "tags" = mkOption {
          description = "Tags are the tags assigned to this node in the layout";
          type = types.nullOr (types.listOf types.str);
        };
        "version" = mkOption {
          description = "Version is the Garage version on this node";
          type = types.nullOr types.str;
        };
      };

      config = {
        "address" = mkOverride 1002 null;
        "blockErrors" = mkOverride 1002 null;
        "conditions" = mkOverride 1002 null;
        "connected" = mkOverride 1002 null;
        "dataPartition" = mkOverride 1002 null;
        "dbEngine" = mkOverride 1002 null;
        "garageFeatures" = mkOverride 1002 null;
        "hostname" = mkOverride 1002 null;
        "inLayout" = mkOverride 1002 null;
        "lastSeen" = mkOverride 1002 null;
        "layoutVersion" = mkOverride 1002 null;
        "metadataPartition" = mkOverride 1002 null;
        "nodeId" = mkOverride 1002 null;
        "observedGeneration" = mkOverride 1002 null;
        "partitions" = mkOverride 1002 null;
        "phase" = mkOverride 1002 null;
        "repairInProgress" = mkOverride 1002 null;
        "repairProgress" = mkOverride 1002 null;
        "repairType" = mkOverride 1002 null;
        "storedData" = mkOverride 1002 null;
        "tags" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeStatusConditions" = {
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
          type = types.nullOr types.int;
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
    "garage.rajsingh.info.v1alpha1.GarageNodeStatusDataPartition" = {
      options = {
        "available" = mkOption {
          description = "Available is the available disk space";
          type = types.nullOr types.str;
        };
        "total" = mkOption {
          description = "Total is the total disk space";
          type = types.nullOr types.str;
        };
        "usedPercent" = mkOption {
          description = "UsedPercent is the percentage of disk space used (0-100)";
          type = types.nullOr types.int;
        };
      };

      config = {
        "available" = mkOverride 1002 null;
        "total" = mkOverride 1002 null;
        "usedPercent" = mkOverride 1002 null;
      };
    };
    "garage.rajsingh.info.v1alpha1.GarageNodeStatusMetadataPartition" = {
      options = {
        "available" = mkOption {
          description = "Available is the available disk space";
          type = types.nullOr types.str;
        };
        "total" = mkOption {
          description = "Total is the total disk space";
          type = types.nullOr types.str;
        };
        "usedPercent" = mkOption {
          description = "UsedPercent is the percentage of disk space used (0-100)";
          type = types.nullOr types.int;
        };
      };

      config = {
        "available" = mkOverride 1002 null;
        "total" = mkOverride 1002 null;
        "usedPercent" = mkOverride 1002 null;
      };
    };
  };
in {
  # all resource versions
  options = {
    resources =
      {
        "garage.rajsingh.info"."v1alpha1"."GarageAdminToken" = mkOption {
          description = "GarageAdminToken is the Schema for the garageadmintokens API\nIt manages admin API tokens for Garage clusters";
          type = (
            types.attrsOf (
              submoduleForDefinition "garage.rajsingh.info.v1alpha1.GarageAdminToken" "garageadmintokens"
              "GarageAdminToken"
              "garage.rajsingh.info"
              "v1alpha1"
            )
          );
          default = {};
        };
        "garage.rajsingh.info"."v1alpha1"."GarageBucket" = mkOption {
          description = "GarageBucket is the Schema for the garagebuckets API";
          type = (
            types.attrsOf (
              submoduleForDefinition "garage.rajsingh.info.v1alpha1.GarageBucket" "garagebuckets" "GarageBucket"
              "garage.rajsingh.info"
              "v1alpha1"
            )
          );
          default = {};
        };
        "garage.rajsingh.info"."v1alpha1"."GarageCluster" = mkOption {
          description = "GarageCluster is the Schema for the garageclusters API";
          type = (
            types.attrsOf (
              submoduleForDefinition "garage.rajsingh.info.v1alpha1.GarageCluster" "garageclusters"
              "GarageCluster"
              "garage.rajsingh.info"
              "v1alpha1"
            )
          );
          default = {};
        };
        "garage.rajsingh.info"."v1alpha1"."GarageKey" = mkOption {
          description = "GarageKey is the Schema for the garagekeys API";
          type = (
            types.attrsOf (
              submoduleForDefinition "garage.rajsingh.info.v1alpha1.GarageKey" "garagekeys" "GarageKey"
              "garage.rajsingh.info"
              "v1alpha1"
            )
          );
          default = {};
        };
        "garage.rajsingh.info"."v1alpha1"."GarageNode" = mkOption {
          description = "GarageNode is the Schema for the garagenodes API";
          type = (
            types.attrsOf (
              submoduleForDefinition "garage.rajsingh.info.v1alpha1.GarageNode" "garagenodes" "GarageNode"
              "garage.rajsingh.info"
              "v1alpha1"
            )
          );
          default = {};
        };
      }
      // {
        "garageAdminTokens" = mkOption {
          description = "GarageAdminToken is the Schema for the garageadmintokens API\nIt manages admin API tokens for Garage clusters";
          type = (
            types.attrsOf (
              submoduleForDefinition "garage.rajsingh.info.v1alpha1.GarageAdminToken" "garageadmintokens"
              "GarageAdminToken"
              "garage.rajsingh.info"
              "v1alpha1"
            )
          );
          default = {};
        };
        "garageBuckets" = mkOption {
          description = "GarageBucket is the Schema for the garagebuckets API";
          type = (
            types.attrsOf (
              submoduleForDefinition "garage.rajsingh.info.v1alpha1.GarageBucket" "garagebuckets" "GarageBucket"
              "garage.rajsingh.info"
              "v1alpha1"
            )
          );
          default = {};
        };
        "garageClusters" = mkOption {
          description = "GarageCluster is the Schema for the garageclusters API";
          type = (
            types.attrsOf (
              submoduleForDefinition "garage.rajsingh.info.v1alpha1.GarageCluster" "garageclusters"
              "GarageCluster"
              "garage.rajsingh.info"
              "v1alpha1"
            )
          );
          default = {};
        };
        "garageKeys" = mkOption {
          description = "GarageKey is the Schema for the garagekeys API";
          type = (
            types.attrsOf (
              submoduleForDefinition "garage.rajsingh.info.v1alpha1.GarageKey" "garagekeys" "GarageKey"
              "garage.rajsingh.info"
              "v1alpha1"
            )
          );
          default = {};
        };
        "garageNodes" = mkOption {
          description = "GarageNode is the Schema for the garagenodes API";
          type = (
            types.attrsOf (
              submoduleForDefinition "garage.rajsingh.info.v1alpha1.GarageNode" "garagenodes" "GarageNode"
              "garage.rajsingh.info"
              "v1alpha1"
            )
          );
          default = {};
        };
      };
  };

  config = {
    # expose resource definitions
    inherit definitions;

    # register resource types
    types = [
      {
        name = "garageadmintokens";
        group = "garage.rajsingh.info";
        version = "v1alpha1";
        kind = "GarageAdminToken";
        attrName = "garageAdminTokens";
      }
      {
        name = "garagebuckets";
        group = "garage.rajsingh.info";
        version = "v1alpha1";
        kind = "GarageBucket";
        attrName = "garageBuckets";
      }
      {
        name = "garageclusters";
        group = "garage.rajsingh.info";
        version = "v1alpha1";
        kind = "GarageCluster";
        attrName = "garageClusters";
      }
      {
        name = "garagekeys";
        group = "garage.rajsingh.info";
        version = "v1alpha1";
        kind = "GarageKey";
        attrName = "garageKeys";
      }
      {
        name = "garagenodes";
        group = "garage.rajsingh.info";
        version = "v1alpha1";
        kind = "GarageNode";
        attrName = "garageNodes";
      }
    ];

    resources = {
      "garage.rajsingh.info"."v1alpha1"."GarageAdminToken" =
        mkAliasDefinitions
        options.resources."garageAdminTokens";
      "garage.rajsingh.info"."v1alpha1"."GarageBucket" =
        mkAliasDefinitions
        options.resources."garageBuckets";
      "garage.rajsingh.info"."v1alpha1"."GarageCluster" =
        mkAliasDefinitions
        options.resources."garageClusters";
      "garage.rajsingh.info"."v1alpha1"."GarageKey" = mkAliasDefinitions options.resources."garageKeys";
      "garage.rajsingh.info"."v1alpha1"."GarageNode" = mkAliasDefinitions options.resources."garageNodes";
    };

    # make all namespaced resources default to the
    # application's namespace
    defaults = [
      {
        group = "garage.rajsingh.info";
        version = "v1alpha1";
        kind = "GarageAdminToken";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "garage.rajsingh.info";
        version = "v1alpha1";
        kind = "GarageBucket";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "garage.rajsingh.info";
        version = "v1alpha1";
        kind = "GarageCluster";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "garage.rajsingh.info";
        version = "v1alpha1";
        kind = "GarageKey";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "garage.rajsingh.info";
        version = "v1alpha1";
        kind = "GarageNode";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
    ];
  };
}
