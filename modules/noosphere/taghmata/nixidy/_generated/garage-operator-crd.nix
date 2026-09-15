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

    # Numeric bounds.
    withMinimum =
      min: base:
      lib.types.addCheck base (x: x >= min)
      // {
        description = "${base.description} (minimum ${toString min})";
      };
    withMaximum =
      max: base:
      lib.types.addCheck base (x: x <= max)
      // {
        description = "${base.description} (maximum ${toString max})";
      };
    withExclusiveMinimum =
      min: base:
      lib.types.addCheck base (x: x > min)
      // {
        description = "${base.description} (exclusive minimum ${toString min})";
      };
    withExclusiveMaximum =
      max: base:
      lib.types.addCheck base (x: x < max)
      // {
        description = "${base.description} (exclusive maximum ${toString max})";
      };
    withMultipleOf =
      m: base:
      lib.types.addCheck base (x: mod x m == 0)
      // {
        description = "${base.description} (multiple of ${toString m})";
      };

    # String constraints.
    withMinLength =
      n: base:
      lib.types.addCheck base (x: stringLength x >= n)
      // {
        description = "${base.description} (min length ${toString n})";
      };
    withMaxLength =
      n: base:
      lib.types.addCheck base (x: stringLength x <= n)
      // {
        description = "${base.description} (max length ${toString n})";
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
      { name, ... }: {
        options = definitions."${ref}".options or { };
        config = definitions."${ref}".config or { };
      }
    );

  globalSubmoduleOf =
    ref:
    types.submodule (
      { name, ... }: {
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
      { name, ... }: {
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
    "garage.rajsingh.info.v1alpha1.GarageAdminToken" = {

      options = {
        "apiVersion" = mkOption {
          description = "\nAPIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources\n";
          type = (types.nullOr types.str);
        };
        "kind" = mkOption {
          description = "\nKind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds\n";
          type = (types.nullOr types.str);
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = (types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1alpha1.GarageBucket" = {

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
          description = "GarageBucketSpec defines the desired state of GarageBucket";
          type = (submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketSpec");
        };
        "status" = mkOption {
          description = "GarageBucketStatus defines the observed state of GarageBucket";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketStatus"));
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
          type = (submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketSpecClusterRef");
        };
        "deletionPolicy" = mkOption {
          description = "DeletionPolicy controls whether deleting this resource also deletes the\ncorresponding Garage bucket. The default is Delete.";
          type = (
            types.nullOr (
              types.enum [
                "Delete"
                "Retain"
              ]
            )
          );
        };
        "globalAlias" = mkOption {
          description = "GlobalAlias is the global alias for this bucket (optional)\nIf not set, the bucket name from metadata.name is used";
          type = (types.nullOr types.str);
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
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketSpecQuotas"));
        };
        "website" = mkOption {
          description = "Website configures static website hosting for this bucket.\nNote: Only indexDocument and errorDocument are supported via the Admin API.\nFor advanced features (routing rules, redirectAll), use S3 PutBucketWebsite API directly.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketSpecWebsite"));
        };
      };

      config = {
        "deletionPolicy" = mkOverride 1002 null;
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
          type = (types.nullOr types.str);
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
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
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
          type = (types.nullOr types.bool);
        };
        "read" = mkOption {
          description = "Read allows reading objects";
          type = (types.nullOr types.bool);
        };
        "write" = mkOption {
          description = "Write allows writing objects";
          type = (types.nullOr types.bool);
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

      config = { };

    };
    "garage.rajsingh.info.v1alpha1.GarageBucketSpecQuotas" = {

      options = {
        "maxObjects" = mkOption {
          description = "MaxObjects is the maximum number of objects";
          type = (types.nullOr types.int);
        };
        "maxSize" = mkOption {
          description = "MaxSize is the maximum bucket size in bytes";
          type = (types.nullOr (types.either types.int types.str));
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
          type = (types.nullOr types.bool);
        };
        "errorDocument" = mkOption {
          description = "ErrorDocument is the error document to serve for 404s";
          type = (types.nullOr types.str);
        };
        "indexDocument" = mkOption {
          description = "IndexDocument is the default index document (default: index.html)";
          type = (types.nullOr types.str);
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
          type = (types.nullOr types.str);
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
          type = (types.nullOr types.str);
        };
        "globalAlias" = mkOption {
          description = "GlobalAlias is the assigned global alias";
          type = (types.nullOr types.str);
        };
        "incompleteUploadBytes" = mkOption {
          description = "IncompleteUploadBytes is the total bytes in incomplete multipart uploads";
          type = (types.nullOr types.int);
        };
        "incompleteUploadParts" = mkOption {
          description = "IncompleteUploadParts is the count of parts in incomplete multipart uploads";
          type = (types.nullOr types.int);
        };
        "incompleteUploads" = mkOption {
          description = "IncompleteUploads is the count of incomplete multipart uploads";
          type = (types.nullOr types.int);
        };
        "keys" = mkOption {
          description = "Keys contains keys with access to this bucket";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1alpha1.GarageBucketStatusKeys" "name" [ ]
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
          type = (types.nullOr types.int);
        };
        "observedGeneration" = mkOption {
          description = "ObservedGeneration is the last observed generation";
          type = (types.nullOr types.int);
        };
        "phase" = mkOption {
          description = "Phase represents the current phase";
          type = (types.nullOr types.str);
        };
        "quotaUsage" = mkOption {
          description = "QuotaUsage shows current quota consumption";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketStatusQuotaUsage"));
        };
        "size" = mkOption {
          description = "Size is the current bucket size";
          type = (types.nullOr types.str);
        };
        "websiteConfig" = mkOption {
          description = "WebsiteConfig shows the current website configuration details";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1alpha1.GarageBucketStatusWebsiteConfig"));
        };
        "websiteEnabled" = mkOption {
          description = "WebsiteEnabled indicates if website hosting is currently enabled";
          type = (types.nullOr types.bool);
        };
        "websiteUrl" = mkOption {
          description = "WebsiteURL is the computed website URL (if website hosting is enabled)";
          type = (types.nullOr types.str);
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
          type = (types.withMaxLength 32768 types.str);
        };
        "observedGeneration" = mkOption {
          description = "observedGeneration represents the .metadata.generation that the condition was set based upon.\nFor instance, if .metadata.generation is currently 12, but the .status.conditions[x].observedGeneration is 9, the condition is out of date\nwith respect to the current state of the instance.";
          type = (types.nullOr (types.withMinimum 0 types.int));
        };
        "reason" = mkOption {
          description = "reason contains a programmatic identifier indicating the reason for the condition's last transition.\nProducers of specific condition types may define expected values and meanings for this field,\nand whether the values are considered a guaranteed API.\nThe value should be a CamelCase string.\nThis field may not be empty.";
          type = (types.withMaxLength 1024 (types.withMinLength 1 types.str));
        };
        "status" = mkOption {
          description = "status of the condition, one of True, False, Unknown.";
          type = (
            types.enum [
              "True"
              "False"
              "Unknown"
            ]
          );
        };
        "type" = mkOption {
          description = "type of condition in CamelCase or in foo.example.com/CamelCase.";
          type = (types.withMaxLength 316 types.str);
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
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "Name is the key name";
          type = (types.nullOr types.str);
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
          type = (types.nullOr types.bool);
        };
        "read" = mkOption {
          description = "Read permission";
          type = (types.nullOr types.bool);
        };
        "write" = mkOption {
          description = "Write permission";
          type = (types.nullOr types.bool);
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
          type = (types.nullOr types.str);
        };
        "keyId" = mkOption {
          description = "KeyID is the access key ID that owns this alias";
          type = (types.nullOr types.str);
        };
        "keyName" = mkOption {
          description = "KeyName is the friendly name of the key";
          type = (types.nullOr types.str);
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
          type = (types.nullOr types.int);
        };
        "objectLimit" = mkOption {
          description = "ObjectLimit is the configured object limit (0 = unlimited)";
          type = (types.nullOr types.int);
        };
        "objectPercent" = mkOption {
          description = "ObjectPercent is the percentage of object quota used";
          type = (types.nullOr types.int);
        };
        "sizeBytes" = mkOption {
          description = "SizeBytes is the current size in bytes";
          type = (types.nullOr types.int);
        };
        "sizeLimit" = mkOption {
          description = "SizeLimit is the configured size limit in bytes (0 = unlimited)";
          type = (types.nullOr types.int);
        };
        "sizePercent" = mkOption {
          description = "SizePercent is the percentage of size quota used";
          type = (types.nullOr types.int);
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
          type = (types.nullOr types.str);
        };
        "indexDocument" = mkOption {
          description = "IndexDocument is the configured index document";
          type = (types.nullOr types.str);
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
          description = "\nAPIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources\n";
          type = (types.nullOr types.str);
        };
        "kind" = mkOption {
          description = "\nKind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds\n";
          type = (types.nullOr types.str);
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = (types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1alpha1.GarageKey" = {

      options = {
        "apiVersion" = mkOption {
          description = "\nAPIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources\n";
          type = (types.nullOr types.str);
        };
        "kind" = mkOption {
          description = "\nKind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds\n";
          type = (types.nullOr types.str);
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = (types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1alpha1.GarageNode" = {

      options = {
        "apiVersion" = mkOption {
          description = "\nAPIVersion defines the versioned schema of this representation of an object.\nServers should convert recognized schemas to the latest internal value, and\nmay reject unrecognized values.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources\n";
          type = (types.nullOr types.str);
        };
        "kind" = mkOption {
          description = "\nKind is a string value representing the REST resource this object represents.\nServers may infer this from the endpoint the client submits requests to.\nCannot be updated.\nIn CamelCase.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds\n";
          type = (types.nullOr types.str);
        };
        "metadata" = mkOption {
          description = "Standard object's metadata. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata";
          type = (types.nullOr (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageAdminToken" = {

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
          description = "GarageAdminTokenSpec defines the desired state of GarageAdminToken.\n\nGarageAdminToken provisions a static bootstrap Secret for the Garage Admin\nHTTP API. The referenced GarageCluster must explicitly select this Secret in\nspec.admin.adminTokenSecretRef. This resource does not create a row in\nGarage's dynamic Admin-token table, and deletion does not revoke bytes that a\nrunning Garage process already loaded at startup.\nAdmin tokens authenticate differently from S3 keys (GarageKey) — they use\nBearer token auth against the admin port (default 3903) instead of HMAC-SHA256.\n\nStatic configured tokens always have full admin access and no server-side\nname, scope, or expiry metadata. Use Garage's Admin API directly for a\nuser-managed scoped/dynamic token.";
          type = (submoduleOf "garage.rajsingh.info.v1beta1.GarageAdminTokenSpec");
        };
        "status" = mkOption {
          description = "GarageAdminTokenStatus defines the observed state of GarageAdminToken";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageAdminTokenStatus"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageAdminTokenSpec" = {

      options = {
        "clusterRef" = mkOption {
          description = "ClusterRef references the GarageCluster this token belongs to";
          type = (submoduleOf "garage.rajsingh.info.v1beta1.GarageAdminTokenSpecClusterRef");
        };
        "expiresAt" = mkOption {
          description = "ExpiresAt is retained for compatibility but rejected because static\nconfigured tokens have no Garage-side expiry or revocation record.";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "Name is retained for compatibility but rejected because static bootstrap\nmaterial has no Garage-side friendly name.";
          type = (types.nullOr types.str);
        };
        "neverExpires" = mkOption {
          description = "NeverExpires is retained for compatibility. Static configured tokens are\nalways non-expiring, so this field is deprecated and has no effect.";
          type = (types.nullOr types.bool);
        };
        "secretTemplate" = mkOption {
          description = "SecretTemplate configures how the secret containing the token is generated";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageAdminTokenSpecSecretTemplate")
          );
        };
      };

      config = {
        "expiresAt" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "neverExpires" = mkOverride 1002 null;
        "secretTemplate" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageAdminTokenSpecClusterRef" = {

      options = {
        "kubeConfigSecretRef" = mkOption {
          description = "KubeConfigSecretRef is reserved for a future remote Kubernetes client integration.\nIt is currently rejected by admission because the operator does not use it.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageAdminTokenSpecClusterRefKubeConfigSecretRef"
            )
          );
        };
        "name" = mkOption {
          description = "Name of the GarageCluster resource.";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "Namespace of the GarageCluster. Defaults to the referencing resource's namespace.\nCross-namespace references require a GarageReferenceGrant where supported by\nthe owning resource. GarageNode and GarageAdminToken reject them.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "kubeConfigSecretRef" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageAdminTokenSpecClusterRefKubeConfigSecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageAdminTokenSpecSecretTemplate" = {

      options = {
        "annotations" = mkOption {
          description = "Annotations to add to the secret";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "endpointKey" = mkOption {
          description = "EndpointKey is the key name for the admin endpoint";
          type = (types.nullOr types.str);
        };
        "includeEndpoint" = mkOption {
          description = "IncludeEndpoint includes the admin API endpoint in the secret\nDefaults to true if not specified";
          type = (types.nullOr types.bool);
        };
        "labels" = mkOption {
          description = "Labels to add to the secret";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "name" = mkOption {
          description = "Name is the name of the secret to create\nDefaults to the GarageAdminToken name";
          type = (types.nullOr types.str);
        };
        "tokenKey" = mkOption {
          description = "TokenKey is the key name for the admin token in the secret";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "endpointKey" = mkOverride 1002 null;
        "includeEndpoint" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "tokenKey" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageAdminTokenStatus" = {

      options = {
        "conditions" = mkOption {
          description = "Conditions represent the current state";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageAdminTokenStatusConditions")
            )
          );
        };
        "expiresAt" = mkOption {
          description = "ExpiresAt is deprecated and always cleared because static configured\ntokens have no Garage-side expiry record.";
          type = (types.nullOr types.str);
        };
        "observedGeneration" = mkOption {
          description = "ObservedGeneration is the last observed generation";
          type = (types.nullOr types.int);
        };
        "phase" = mkOption {
          description = "Phase represents the current phase";
          type = (
            types.nullOr (
              types.enum [
                "Pending"
                "Creating"
                "Ready"
                "Deleting"
                "Failed"
                "Expired"
                "Unknown"
              ]
            )
          );
        };
        "secretRef" = mkOption {
          description = "SecretRef references the created secret";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageAdminTokenStatusSecretRef"));
        };
        "tokenDigest" = mkOption {
          description = "TokenDigest is the full SHA-256 digest of the static bearer. The controller\nuses it to detect mutation of an existing generated Secret without exposing\nany bearer bytes.";
          type = (types.nullOr types.str);
        };
        "tokenId" = mkOption {
          description = "TokenID is a short display fingerprint of the generated static token. It is\nnot a Garage-assigned dynamic token ID.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "conditions" = mkOverride 1002 null;
        "expiresAt" = mkOverride 1002 null;
        "observedGeneration" = mkOverride 1002 null;
        "phase" = mkOverride 1002 null;
        "secretRef" = mkOverride 1002 null;
        "tokenDigest" = mkOverride 1002 null;
        "tokenId" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageAdminTokenStatusConditions" = {

      options = {
        "lastTransitionTime" = mkOption {
          description = "lastTransitionTime is the last time the condition transitioned from one status to another.\nThis should be when the underlying condition changed.  If that is not known, then using the time when the API field changed is acceptable.";
          type = types.str;
        };
        "message" = mkOption {
          description = "message is a human readable message indicating details about the transition.\nThis may be an empty string.";
          type = (types.withMaxLength 32768 types.str);
        };
        "observedGeneration" = mkOption {
          description = "observedGeneration represents the .metadata.generation that the condition was set based upon.\nFor instance, if .metadata.generation is currently 12, but the .status.conditions[x].observedGeneration is 9, the condition is out of date\nwith respect to the current state of the instance.";
          type = (types.nullOr (types.withMinimum 0 types.int));
        };
        "reason" = mkOption {
          description = "reason contains a programmatic identifier indicating the reason for the condition's last transition.\nProducers of specific condition types may define expected values and meanings for this field,\nand whether the values are considered a guaranteed API.\nThe value should be a CamelCase string.\nThis field may not be empty.";
          type = (types.withMaxLength 1024 (types.withMinLength 1 types.str));
        };
        "status" = mkOption {
          description = "status of the condition, one of True, False, Unknown.";
          type = (
            types.enum [
              "True"
              "False"
              "Unknown"
            ]
          );
        };
        "type" = mkOption {
          description = "type of condition in CamelCase or in foo.example.com/CamelCase.";
          type = (types.withMaxLength 316 types.str);
        };
      };

      config = {
        "observedGeneration" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageAdminTokenStatusSecretRef" = {

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
    "garage.rajsingh.info.v1beta1.GarageBucket" = {

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
          description = "GarageBucketSpec defines the desired state of GarageBucket";
          type = (submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketSpec");
        };
        "status" = mkOption {
          description = "GarageBucketStatus defines the observed state of GarageBucket";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketStatus"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketSpec" = {

      options = {
        "bucketId" = mkOption {
          description = "BucketID pins this resource to a pre-existing Garage bucket ID.\nWhen set, the operator will never create a new bucket — it only manages\nsettings and key permissions for the identified bucket. Takes priority\nover GlobalAlias-based lookup. Useful for importing existing buckets and\nfor recovery after cluster incidents.";
          type = (types.nullOr types.str);
        };
        "clusterRef" = mkOption {
          description = "ClusterRef references the GarageCluster this bucket belongs to";
          type = (submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketSpecClusterRef");
        };
        "deletionPolicy" = mkOption {
          description = "DeletionPolicy controls whether deleting this resource also deletes the\ncorresponding Garage bucket. The default is Delete.";
          type = (
            types.nullOr (
              types.enum [
                "Delete"
                "Retain"
              ]
            )
          );
        };
        "globalAlias" = mkOption {
          description = "GlobalAlias is the global alias for this bucket (optional)\nIf not set, the bucket name from metadata.name is used";
          type = (types.nullOr types.str);
        };
        "keyPermissions" = mkOption {
          description = "KeyPermissions grants access to specific GarageKeys.\n\nNote: Permissions can be granted from either direction:\n- Here (GarageBucket.keyPermissions): Grant keys access to this bucket\n- On GarageKey (GarageKey.bucketPermissions): Grant the key access to buckets\n\nBoth approaches are equivalent and result in the same Garage API calls.\nUse whichever is more convenient for your workflow:\n- Bucket-centric: Define all key access on the bucket\n- Key-centric: Define all bucket access on the key\n\nIf the same permission is defined in both places, they are merged (not conflicting).";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketSpecKeyPermissions")
            )
          );
        };
        "lifecycle" = mkOption {
          description = "Lifecycle configures bucket lifecycle policies (object expiration,\nabort of incomplete multipart uploads).\n\nGarage exposes lifecycle only via the S3 API, not the admin API. The\noperator applies rules using an internal access key it manages per\nGarageCluster. Garage supports a strict subset of the AWS S3 lifecycle\nspec: only Expiration (days or date, no ExpiredObjectDeleteMarker) and\nAbortIncompleteMultipartUpload. Filters support prefix and object size\nbounds; tag filters and the deprecated rule-level Prefix are not\naccepted.\n\nGarage's lifecycle worker runs daily at midnight (UTC by default), so\nrule evaluation is asynchronous from reconciliation.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketSpecLifecycle"));
        };
        "localAliases" = mkOption {
          description = "LocalAliases are per-key local aliases for this bucket";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketSpecLocalAliases")
            )
          );
        };
        "quotas" = mkOption {
          description = "Quotas configures bucket quotas";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketSpecQuotas"));
        };
        "website" = mkOption {
          description = "Website configures static website hosting for this bucket.\nNote: Only indexDocument and errorDocument are supported via the Admin API.\nFor advanced features (routing rules, redirectAll), use S3 PutBucketWebsite API directly.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketSpecWebsite"));
        };
      };

      config = {
        "bucketId" = mkOverride 1002 null;
        "deletionPolicy" = mkOverride 1002 null;
        "globalAlias" = mkOverride 1002 null;
        "keyPermissions" = mkOverride 1002 null;
        "lifecycle" = mkOverride 1002 null;
        "localAliases" = mkOverride 1002 null;
        "quotas" = mkOverride 1002 null;
        "website" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketSpecClusterRef" = {

      options = {
        "kubeConfigSecretRef" = mkOption {
          description = "KubeConfigSecretRef is reserved for a future remote Kubernetes client integration.\nIt is currently rejected by admission because the operator does not use it.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketSpecClusterRefKubeConfigSecretRef"
            )
          );
        };
        "name" = mkOption {
          description = "Name of the GarageCluster resource.";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "Namespace of the GarageCluster. Defaults to the referencing resource's namespace.\nCross-namespace references require a GarageReferenceGrant where supported by\nthe owning resource. GarageNode and GarageAdminToken reject them.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "kubeConfigSecretRef" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketSpecClusterRefKubeConfigSecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketSpecKeyPermissions" = {

      options = {
        "keyRef" = mkOption {
          description = "KeyRef references the GarageKey by name (and optionally namespace).";
          type = (submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketSpecKeyPermissionsKeyRef");
        };
        "owner" = mkOption {
          description = "Owner allows bucket owner operations";
          type = (types.nullOr types.bool);
        };
        "read" = mkOption {
          description = "Read allows reading objects";
          type = (types.nullOr types.bool);
        };
        "write" = mkOption {
          description = "Write allows writing objects";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "owner" = mkOverride 1002 null;
        "read" = mkOverride 1002 null;
        "write" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketSpecKeyPermissionsKeyRef" = {

      options = {
        "name" = mkOption {
          description = "Name of the GarageKey.";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "Namespace of the GarageKey. Defaults to the GarageBucket's namespace.\nCross-namespace references require a GarageReferenceGrant in the target namespace.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketSpecLifecycle" = {

      options = {
        "rules" = mkOption {
          description = "Rules to apply. The operator replaces the bucket's lifecycle\nconfiguration with this exact set on each reconcile.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketSpecLifecycleRules")
            )
          );
        };
      };

      config = {
        "rules" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketSpecLifecycleRules" = {

      options = {
        "abortIncompleteMultipartUploadDays" = mkOption {
          description = "AbortIncompleteMultipartUploadDays aborts multipart uploads that have\nbeen pending for at least this many days.";
          type = (types.nullOr (types.withMinimum 1 types.int));
        };
        "expirationDate" = mkOption {
          description = "ExpirationDate expires current objects on or after this UTC date.";
          type = (types.nullOr types.str);
        };
        "expirationDays" = mkOption {
          description = "ExpirationDays expires current objects this many days after creation.";
          type = (types.nullOr (types.withMinimum 1 types.int));
        };
        "filter" = mkOption {
          description = "Filter narrows the rule to a subset of objects. If unset, the rule\napplies to every object in the bucket.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketSpecLifecycleRulesFilter")
          );
        };
        "id" = mkOption {
          description = "ID is the rule identifier. Must be unique within the bucket.";
          type = (types.withMinLength 1 types.str);
        };
        "status" = mkOption {
          description = "Status enables or disables this rule. Disabled rules are sent to\nGarage but skipped by the lifecycle worker.";
          type = (
            types.nullOr (
              types.enum [
                "Enabled"
                "Disabled"
              ]
            )
          );
        };
      };

      config = {
        "abortIncompleteMultipartUploadDays" = mkOverride 1002 null;
        "expirationDate" = mkOverride 1002 null;
        "expirationDays" = mkOverride 1002 null;
        "filter" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketSpecLifecycleRulesFilter" = {

      options = {
        "objectSizeGreaterThan" = mkOption {
          description = "ObjectSizeGreaterThan matches objects strictly larger than this many\nbytes.";
          type = (types.nullOr (types.withMinimum 0 types.int));
        };
        "objectSizeLessThan" = mkOption {
          description = "ObjectSizeLessThan matches objects strictly smaller than this many\nbytes.";
          type = (types.nullOr (types.withMinimum 1 types.int));
        };
        "prefix" = mkOption {
          description = "Prefix matches object keys starting with this string.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "objectSizeGreaterThan" = mkOverride 1002 null;
        "objectSizeLessThan" = mkOverride 1002 null;
        "prefix" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketSpecLocalAliases" = {

      options = {
        "alias" = mkOption {
          description = "Alias is the bucket name this key will use to access the bucket.\nMust be unique within the key's alias namespace.";
          type = types.str;
        };
        "keyRef" = mkOption {
          description = "KeyRef is the name of the GarageKey in the same namespace that owns this alias.";
          type = types.str;
        };
      };

      config = { };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketSpecQuotas" = {

      options = {
        "maxObjects" = mkOption {
          description = "MaxObjects is the maximum number of objects";
          type = (types.nullOr types.int);
        };
        "maxSize" = mkOption {
          description = "MaxSize is the maximum bucket size in bytes";
          type = (types.nullOr (types.either types.int types.str));
        };
      };

      config = {
        "maxObjects" = mkOverride 1002 null;
        "maxSize" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketSpecWebsite" = {

      options = {
        "enabled" = mkOption {
          description = "Enabled enables static website hosting.";
          type = (types.nullOr types.bool);
        };
        "errorDocument" = mkOption {
          description = "ErrorDocument is the error document to serve for 404s";
          type = (types.nullOr types.str);
        };
        "indexDocument" = mkOption {
          description = "IndexDocument is the default index document (default: index.html)";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "enabled" = mkOverride 1002 null;
        "errorDocument" = mkOverride 1002 null;
        "indexDocument" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketStatus" = {

      options = {
        "bucketId" = mkOption {
          description = "BucketID is the internal Garage bucket ID";
          type = (types.nullOr types.str);
        };
        "conditions" = mkOption {
          description = "Conditions represent the current state";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketStatusConditions")
            )
          );
        };
        "createdAt" = mkOption {
          description = "CreatedAt is when the bucket was created in Garage";
          type = (types.nullOr types.str);
        };
        "globalAlias" = mkOption {
          description = "GlobalAlias is the assigned global alias";
          type = (types.nullOr types.str);
        };
        "incompleteUploadBytes" = mkOption {
          description = "IncompleteUploadBytes is the total bytes in incomplete multipart uploads";
          type = (types.nullOr types.int);
        };
        "incompleteUploadParts" = mkOption {
          description = "IncompleteUploadParts is the count of parts in incomplete multipart uploads";
          type = (types.nullOr types.int);
        };
        "incompleteUploads" = mkOption {
          description = "IncompleteUploads is the count of incomplete multipart uploads";
          type = (types.nullOr types.int);
        };
        "keys" = mkOption {
          description = "Keys contains keys with access to this bucket";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1beta1.GarageBucketStatusKeys" "name" [ ]
            )
          );
          apply = attrsToList;
        };
        "lifecycleRules" = mkOption {
          description = "LifecycleRules summarises lifecycle rules currently applied to the\nbucket in Garage. Spec is the source of truth for rule contents; this\nlist reports id and enabled state only.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketStatusLifecycleRules")
            )
          );
        };
        "localAliases" = mkOption {
          description = "LocalAliases tracks per-key local aliases for this bucket";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketStatusLocalAliases")
            )
          );
        };
        "managedGlobalAlias" = mkOption {
          description = "ManagedGlobalAlias is the global alias reserved or successfully managed from\nspec.globalAlias (or the bucket name when spec.globalAlias is empty).\nIt is separate from GlobalAlias, which reports observed Garage state, so\naliases created outside the operator are never removed accidentally.";
          type = (types.nullOr types.str);
        };
        "managedKeyGrants" = mkOption {
          description = "ManagedKeyGrants lists access key IDs with reserved or active operator\nownership from this bucket's spec.keyPermissions. IDs are recorded before\nthe first remote mutation and removed only after exact convergence, allowing\ncrash-safe revocation when a declaration is dropped without disturbing\ngrants managed through GarageKey or by hand.";
          type = (types.nullOr (types.listOf types.str));
        };
        "managedLocalAliases" = mkOption {
          description = "ManagedLocalAliases lists the per-key aliases reserved or successfully\nmanaged from spec.localAliases. IDs are recorded before the first remote\nadd so an interrupted add can still be removed safely.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketStatusManagedLocalAliases")
            )
          );
        };
        "observedGeneration" = mkOption {
          description = "ObservedGeneration is the last observed generation";
          type = (types.nullOr types.int);
        };
        "pendingGlobalAlias" = mkOption {
          description = "PendingGlobalAlias reserves a replacement before its first remote add.\nManagedGlobalAlias retains the old alias until the replacement succeeds,\nso a failed rename never leaves the bucket without its prior alias.";
          type = (types.nullOr types.str);
        };
        "phase" = mkOption {
          description = "Phase represents the current phase";
          type = (
            types.nullOr (
              types.enum [
                "Pending"
                "Creating"
                "Ready"
                "Deleting"
                "Failed"
                "Unknown"
              ]
            )
          );
        };
        "quotaUsage" = mkOption {
          description = "QuotaUsage shows current quota consumption";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketStatusQuotaUsage"));
        };
        "size" = mkOption {
          description = "Size is the current bucket size";
          type = (types.nullOr types.str);
        };
        "websiteConfig" = mkOption {
          description = "WebsiteConfig shows the current website configuration details";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketStatusWebsiteConfig"));
        };
        "websiteEnabled" = mkOption {
          description = "WebsiteEnabled indicates if website hosting is currently enabled";
          type = (types.nullOr types.bool);
        };
        "websiteUrl" = mkOption {
          description = "WebsiteURL is the computed website URL (if website hosting is enabled)";
          type = (types.nullOr types.str);
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
        "lifecycleRules" = mkOverride 1002 null;
        "localAliases" = mkOverride 1002 null;
        "managedGlobalAlias" = mkOverride 1002 null;
        "managedKeyGrants" = mkOverride 1002 null;
        "managedLocalAliases" = mkOverride 1002 null;
        "observedGeneration" = mkOverride 1002 null;
        "pendingGlobalAlias" = mkOverride 1002 null;
        "phase" = mkOverride 1002 null;
        "quotaUsage" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "websiteConfig" = mkOverride 1002 null;
        "websiteEnabled" = mkOverride 1002 null;
        "websiteUrl" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketStatusConditions" = {

      options = {
        "lastTransitionTime" = mkOption {
          description = "lastTransitionTime is the last time the condition transitioned from one status to another.\nThis should be when the underlying condition changed.  If that is not known, then using the time when the API field changed is acceptable.";
          type = types.str;
        };
        "message" = mkOption {
          description = "message is a human readable message indicating details about the transition.\nThis may be an empty string.";
          type = (types.withMaxLength 32768 types.str);
        };
        "observedGeneration" = mkOption {
          description = "observedGeneration represents the .metadata.generation that the condition was set based upon.\nFor instance, if .metadata.generation is currently 12, but the .status.conditions[x].observedGeneration is 9, the condition is out of date\nwith respect to the current state of the instance.";
          type = (types.nullOr (types.withMinimum 0 types.int));
        };
        "reason" = mkOption {
          description = "reason contains a programmatic identifier indicating the reason for the condition's last transition.\nProducers of specific condition types may define expected values and meanings for this field,\nand whether the values are considered a guaranteed API.\nThe value should be a CamelCase string.\nThis field may not be empty.";
          type = (types.withMaxLength 1024 (types.withMinLength 1 types.str));
        };
        "status" = mkOption {
          description = "status of the condition, one of True, False, Unknown.";
          type = (
            types.enum [
              "True"
              "False"
              "Unknown"
            ]
          );
        };
        "type" = mkOption {
          description = "type of condition in CamelCase or in foo.example.com/CamelCase.";
          type = (types.withMaxLength 316 types.str);
        };
      };

      config = {
        "observedGeneration" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketStatusKeys" = {

      options = {
        "keyId" = mkOption {
          description = "KeyID is the access key ID";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "Name is the key name";
          type = (types.nullOr types.str);
        };
        "permissions" = mkOption {
          description = "Permissions granted to this key";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageBucketStatusKeysPermissions")
          );
        };
      };

      config = {
        "keyId" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "permissions" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketStatusKeysPermissions" = {

      options = {
        "owner" = mkOption {
          description = "Owner permission";
          type = (types.nullOr types.bool);
        };
        "read" = mkOption {
          description = "Read permission";
          type = (types.nullOr types.bool);
        };
        "write" = mkOption {
          description = "Write permission";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "owner" = mkOverride 1002 null;
        "read" = mkOverride 1002 null;
        "write" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketStatusLifecycleRules" = {

      options = {
        "id" = mkOption {
          description = "ID of the rule.";
          type = types.str;
        };
        "status" = mkOption {
          description = "Status is Enabled or Disabled.";
          type = (
            types.enum [
              "Enabled"
              "Disabled"
            ]
          );
        };
      };

      config = { };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketStatusLocalAliases" = {

      options = {
        "alias" = mkOption {
          description = "Alias is the local alias name";
          type = (types.nullOr types.str);
        };
        "keyId" = mkOption {
          description = "KeyID is the access key ID that owns this alias";
          type = (types.nullOr types.str);
        };
        "keyName" = mkOption {
          description = "KeyName is the friendly name of the key";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "alias" = mkOverride 1002 null;
        "keyId" = mkOverride 1002 null;
        "keyName" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketStatusManagedLocalAliases" = {

      options = {
        "alias" = mkOption {
          description = "Alias is the local alias name";
          type = (types.nullOr types.str);
        };
        "keyId" = mkOption {
          description = "KeyID is the access key ID that owns this alias";
          type = (types.nullOr types.str);
        };
        "keyName" = mkOption {
          description = "KeyName is the friendly name of the key";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "alias" = mkOverride 1002 null;
        "keyId" = mkOverride 1002 null;
        "keyName" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageBucketStatusQuotaUsage" = {

      options = {
        "objectCount" = mkOption {
          description = "ObjectCount is the current object count";
          type = (types.nullOr types.int);
        };
        "objectLimit" = mkOption {
          description = "ObjectLimit is the configured object limit (0 = unlimited)";
          type = (types.nullOr types.int);
        };
        "objectPercent" = mkOption {
          description = "ObjectPercent is the percentage of object quota used";
          type = (types.nullOr types.int);
        };
        "sizeBytes" = mkOption {
          description = "SizeBytes is the current size in bytes";
          type = (types.nullOr types.int);
        };
        "sizeLimit" = mkOption {
          description = "SizeLimit is the configured size limit in bytes (0 = unlimited)";
          type = (types.nullOr types.int);
        };
        "sizePercent" = mkOption {
          description = "SizePercent is the percentage of size quota used";
          type = (types.nullOr types.int);
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
    "garage.rajsingh.info.v1beta1.GarageBucketStatusWebsiteConfig" = {

      options = {
        "errorDocument" = mkOption {
          description = "ErrorDocument is the configured error document";
          type = (types.nullOr types.str);
        };
        "indexDocument" = mkOption {
          description = "IndexDocument is the configured index document";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "errorDocument" = mkOverride 1002 null;
        "indexDocument" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageKey" = {

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
          description = "GarageKeySpec defines the desired state of GarageKey";
          type = (submoduleOf "garage.rajsingh.info.v1beta1.GarageKeySpec");
        };
        "status" = mkOption {
          description = "GarageKeyStatus defines the observed state of GarageKey";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageKeyStatus"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageKeySpec" = {

      options = {
        "allBuckets" = mkOption {
          description = "AllBuckets grants this key a baseline permission set on every bucket in the cluster.\nUseful for admin tools, backup agents, or monitoring that need cluster-wide access.\n\nHow it works: the operator calls Garage's allow/deny APIs for every bucket to\nenforce exactly the flags set here — false actively revokes, not just leaves unset.\nBucketPermissions entries are then applied on top, so you can grant broader access\nvia allBuckets and restrict specific buckets via bucketPermissions.\n\nWarning: this applies to ALL Garage buckets, including buckets not managed by the\noperator (created directly via the S3 API). Plan accordingly.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageKeySpecAllBuckets"));
        };
        "bucketPermissions" = mkOption {
          description = "BucketPermissions grants this key access to buckets.\n\nNote: Permissions can be granted from either direction:\n- Here (GarageKey.bucketPermissions): Grant this key access to buckets\n- On GarageBucket (GarageBucket.keyPermissions): Grant keys access to the bucket\n\nBoth approaches are equivalent and result in the same Garage API calls.\nUse whichever is more convenient for your workflow:\n- Key-centric: Define all bucket access on the key\n- Bucket-centric: Define all key access on the bucket\n\nIf the same permission is defined in both places, they are merged (not conflicting).";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageKeySpecBucketPermissions")
            )
          );
        };
        "clusterRef" = mkOption {
          description = "ClusterRef references the GarageCluster this key belongs to";
          type = (submoduleOf "garage.rajsingh.info.v1beta1.GarageKeySpecClusterRef");
        };
        "expiresAt" = mkOption {
          description = "ExpiresAt sets when this key expires.\nAfter this time Garage will reject requests using the key. The operator sets the\nKeyExpired condition when expired but does NOT automatically delete or rotate the key.\nMutually exclusive with neverExpires.";
          type = (types.nullOr types.str);
        };
        "importKey" = mkOption {
          description = "ImportKey imports an existing key instead of generating new credentials";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageKeySpecImportKey"));
        };
        "name" = mkOption {
          description = "Name is a friendly name for this access key\nIf not set, metadata.name is used";
          type = (types.nullOr types.str);
        };
        "neverExpires" = mkOption {
          description = "NeverExpires explicitly marks this key as having no expiration.\nSets the Garage key expiration to \"never\" rather than leaving it unset.\nMutually exclusive with expiration.";
          type = (types.nullOr types.bool);
        };
        "permissions" = mkOption {
          description = "Permissions configures key-level permissions\nNote: For admin API access, use admin tokens configured in GarageCluster";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageKeySpecPermissions"));
        };
        "secretTemplate" = mkOption {
          description = "SecretTemplate configures how the secret is generated";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageKeySpecSecretTemplate"));
        };
      };

      config = {
        "allBuckets" = mkOverride 1002 null;
        "bucketPermissions" = mkOverride 1002 null;
        "expiresAt" = mkOverride 1002 null;
        "importKey" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "neverExpires" = mkOverride 1002 null;
        "permissions" = mkOverride 1002 null;
        "secretTemplate" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageKeySpecAllBuckets" = {

      options = {
        "owner" = mkOption {
          description = "Owner allows bucket owner operations on all buckets";
          type = (types.nullOr types.bool);
        };
        "read" = mkOption {
          description = "Read allows reading objects from all buckets";
          type = (types.nullOr types.bool);
        };
        "write" = mkOption {
          description = "Write allows writing objects to all buckets";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "owner" = mkOverride 1002 null;
        "read" = mkOverride 1002 null;
        "write" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageKeySpecBucketPermissions" = {

      options = {
        "bucketId" = mkOption {
          description = "BucketID references the bucket by its Garage-internal ID.";
          type = (types.nullOr types.str);
        };
        "bucketRef" = mkOption {
          description = "BucketRef references a GarageBucket by name (and optionally namespace).\nMutually exclusive with BucketID and GlobalAlias.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageKeySpecBucketPermissionsBucketRef")
          );
        };
        "globalAlias" = mkOption {
          description = "GlobalAlias references the bucket by its global alias.";
          type = (types.nullOr types.str);
        };
        "owner" = mkOption {
          description = "Owner allows bucket owner operations (delete bucket, configure website, etc.)";
          type = (types.nullOr types.bool);
        };
        "read" = mkOption {
          description = "Read allows reading objects from the bucket.";
          type = (types.nullOr types.bool);
        };
        "write" = mkOption {
          description = "Write allows writing objects to the bucket.";
          type = (types.nullOr types.bool);
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
    "garage.rajsingh.info.v1beta1.GarageKeySpecBucketPermissionsBucketRef" = {

      options = {
        "name" = mkOption {
          description = "Name of the GarageBucket.";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "Namespace of the GarageBucket. Defaults to the GarageKey's namespace.\nCross-namespace references require a GarageReferenceGrant in the target namespace.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageKeySpecClusterRef" = {

      options = {
        "kubeConfigSecretRef" = mkOption {
          description = "KubeConfigSecretRef is reserved for a future remote Kubernetes client integration.\nIt is currently rejected by admission because the operator does not use it.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageKeySpecClusterRefKubeConfigSecretRef")
          );
        };
        "name" = mkOption {
          description = "Name of the GarageCluster resource.";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "Namespace of the GarageCluster. Defaults to the referencing resource's namespace.\nCross-namespace references require a GarageReferenceGrant where supported by\nthe owning resource. GarageNode and GarageAdminToken reject them.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "kubeConfigSecretRef" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageKeySpecClusterRefKubeConfigSecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageKeySpecImportKey" = {

      options = {
        "accessKeyId" = mkOption {
          description = "AccessKeyID is the existing Garage access key ID (must start with \"GK\").\nUse secretRef instead to avoid storing credentials in the CR.";
          type = (types.nullOr types.str);
        };
        "accessKeyIdKey" = mkOption {
          description = "AccessKeyIDKey is the key name within secretRef for the access key ID.\nDefaults to \"access-key-id\". Only valid when secretRef is set.";
          type = (types.nullOr types.str);
        };
        "secretAccessKey" = mkOption {
          description = "SecretAccessKey is the existing secret access key.\nUse secretRef instead to avoid storing credentials in the CR.";
          type = (types.nullOr types.str);
        };
        "secretAccessKeyKey" = mkOption {
          description = "SecretAccessKeyKey is the key name within secretRef for the secret access key.\nDefaults to \"secret-access-key\". Only valid when secretRef is set.";
          type = (types.nullOr types.str);
        };
        "secretRef" = mkOption {
          description = "SecretRef references a Kubernetes secret containing the credentials.\nMutually exclusive with inline accessKeyId/secretAccessKey.\nThe namespace must be empty or match the GarageKey namespace.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageKeySpecImportKeySecretRef"));
        };
      };

      config = {
        "accessKeyId" = mkOverride 1002 null;
        "accessKeyIdKey" = mkOverride 1002 null;
        "secretAccessKey" = mkOverride 1002 null;
        "secretAccessKeyKey" = mkOverride 1002 null;
        "secretRef" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageKeySpecImportKeySecretRef" = {

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
    "garage.rajsingh.info.v1beta1.GarageKeySpecPermissions" = {

      options = {
        "createBucket" = mkOption {
          description = "CreateBucket allows this key to create new buckets via the S3 CreateBucket API";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "createBucket" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageKeySpecSecretTemplate" = {

      options = {
        "accessKeyIdKey" = mkOption {
          description = "AccessKeyIDKey is the key name for the access key ID";
          type = (types.nullOr types.str);
        };
        "additionalData" = mkOption {
          description = "AdditionalData includes additional key-value pairs in the secret";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "annotations" = mkOption {
          description = "Annotations to add to the secret";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "bucketNameKey" = mkOption {
          description = "BucketNameKey is the data key under which the bucket name is written\nin the Secret. Defaults to \"bucket\". Only used when IncludeBucketName is true.";
          type = (types.nullOr types.str);
        };
        "credentialsFileKey" = mkOption {
          description = "CredentialsFileKey is the data key under which an AWS shared credentials\nfile is written. Defaults to \"credentials\". Only used when\nIncludeCredentialsFile is true.";
          type = (types.nullOr types.str);
        };
        "credentialsFileProfile" = mkOption {
          description = "CredentialsFileProfile is the profile name used in the AWS shared\ncredentials file. Defaults to \"default\". Only used when\nIncludeCredentialsFile is true.";
          type = (types.nullOr (types.withMaxLength 128 types.str));
        };
        "endpointKey" = mkOption {
          description = "EndpointKey is the key name for the S3 endpoint (includes http:// scheme)";
          type = (types.nullOr types.str);
        };
        "hostKey" = mkOption {
          description = "HostKey is the key name for the S3 host (without scheme, e.g., \"host:port\")";
          type = (types.nullOr types.str);
        };
        "includeBucketName" = mkOption {
          description = "IncludeBucketName controls whether the bucket name is written to the Secret.\nDefaults to false. When true, the bucket name is populated only if the key\nreferences exactly one bucket (via bucketRef or globalAlias); omitted otherwise.";
          type = (types.nullOr types.bool);
        };
        "includeCredentialsFile" = mkOption {
          description = "IncludeCredentialsFile controls whether an AWS shared credentials file is\nwritten to the Secret. Defaults to false. The file contains only the access\nkey ID and secret access key under CredentialsFileProfile.";
          type = (types.nullOr types.bool);
        };
        "includeEndpoint" = mkOption {
          description = "IncludeEndpoint includes the S3 endpoint in the secret\nDefaults to true if not specified";
          type = (types.nullOr types.bool);
        };
        "includeRegion" = mkOption {
          description = "IncludeRegion includes the S3 region in the secret\nDefaults to true if not specified";
          type = (types.nullOr types.bool);
        };
        "labels" = mkOption {
          description = "Labels to add to the secret";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "name" = mkOption {
          description = "Name is the name of the secret to create\nDefaults to the GarageKey name";
          type = (types.nullOr types.str);
        };
        "regionKey" = mkOption {
          description = "RegionKey is the key name for the S3 region";
          type = (types.nullOr types.str);
        };
        "schemeKey" = mkOption {
          description = "SchemeKey is the key name for the endpoint scheme (http or https)";
          type = (types.nullOr types.str);
        };
        "secretAccessKeyKey" = mkOption {
          description = "SecretAccessKeyKey is the key name for the secret access key";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is the secret type";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "accessKeyIdKey" = mkOverride 1002 null;
        "additionalData" = mkOverride 1002 null;
        "annotations" = mkOverride 1002 null;
        "bucketNameKey" = mkOverride 1002 null;
        "credentialsFileKey" = mkOverride 1002 null;
        "credentialsFileProfile" = mkOverride 1002 null;
        "endpointKey" = mkOverride 1002 null;
        "hostKey" = mkOverride 1002 null;
        "includeBucketName" = mkOverride 1002 null;
        "includeCredentialsFile" = mkOverride 1002 null;
        "includeEndpoint" = mkOverride 1002 null;
        "includeRegion" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "regionKey" = mkOverride 1002 null;
        "schemeKey" = mkOverride 1002 null;
        "secretAccessKeyKey" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageKeyStatus" = {

      options = {
        "accessKeyId" = mkOption {
          description = "AccessKeyID is the S3 access key ID";
          type = (types.nullOr types.str);
        };
        "buckets" = mkOption {
          description = "Buckets lists buckets this key has access to";
          type = (
            types.nullOr (types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageKeyStatusBuckets"))
          );
        };
        "clusterWide" = mkOption {
          description = "ClusterWide records reserved or active operator ownership of permissions\nmanaged through spec.allBuckets. It is set before the first remote allow\nand remains set until every resulting permission has been removed.";
          type = (types.nullOr types.bool);
        };
        "conditions" = mkOption {
          description = "Conditions represent the current state";
          type = (
            types.nullOr (types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageKeyStatusConditions"))
          );
        };
        "createdAt" = mkOption {
          description = "CreatedAt is when the key was created in Garage";
          type = (types.nullOr types.str);
        };
        "effectivePermissions" = mkOption {
          description = "EffectivePermissions is retained for API compatibility but is not currently\npopulated. Status.Buckets reports Garage's authoritative effective bucket access.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageKeyStatusEffectivePermissions")
            )
          );
        };
        "expiresAt" = mkOption {
          description = "ExpiresAt is when this key expires (if set)";
          type = (types.nullOr types.str);
        };
        "keyId" = mkOption {
          description = "KeyID is the Garage-assigned key ID";
          type = (types.nullOr types.str);
        };
        "managedBucketGrants" = mkOption {
          description = "ManagedBucketGrants lists Garage bucket IDs with reserved or active\noperator ownership from this key's spec.bucketPermissions. IDs are recorded\nbefore the first remote mutation and removed only after exact convergence,\nallowing crash-safe removal or downgrade without touching manual grants.\nCluster-wide spec.allBuckets ownership is represented by ClusterWide.";
          type = (types.nullOr (types.listOf types.str));
        };
        "observedGeneration" = mkOption {
          description = "ObservedGeneration is the last observed generation";
          type = (types.nullOr types.int);
        };
        "permissions" = mkOption {
          description = "Permissions shows the current permissions for this key";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageKeyStatusPermissions"));
        };
        "phase" = mkOption {
          description = "Phase represents the current phase";
          type = (
            types.nullOr (
              types.enum [
                "Pending"
                "Creating"
                "Ready"
                "Deleting"
                "Failed"
                "Expired"
                "Unknown"
              ]
            )
          );
        };
        "secretRef" = mkOption {
          description = "SecretRef references the created secret";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageKeyStatusSecretRef"));
        };
      };

      config = {
        "accessKeyId" = mkOverride 1002 null;
        "buckets" = mkOverride 1002 null;
        "clusterWide" = mkOverride 1002 null;
        "conditions" = mkOverride 1002 null;
        "createdAt" = mkOverride 1002 null;
        "effectivePermissions" = mkOverride 1002 null;
        "expiresAt" = mkOverride 1002 null;
        "keyId" = mkOverride 1002 null;
        "managedBucketGrants" = mkOverride 1002 null;
        "observedGeneration" = mkOverride 1002 null;
        "permissions" = mkOverride 1002 null;
        "phase" = mkOverride 1002 null;
        "secretRef" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageKeyStatusBuckets" = {

      options = {
        "bucketId" = mkOption {
          description = "BucketID is the bucket ID";
          type = (types.nullOr types.str);
        };
        "globalAlias" = mkOption {
          description = "GlobalAlias is the bucket's global alias";
          type = (types.nullOr types.str);
        };
        "localAlias" = mkOption {
          description = "LocalAlias is this key's local alias for the bucket";
          type = (types.nullOr types.str);
        };
        "owner" = mkOption {
          description = "Owner permission";
          type = (types.nullOr types.bool);
        };
        "read" = mkOption {
          description = "Read permission";
          type = (types.nullOr types.bool);
        };
        "write" = mkOption {
          description = "Write permission";
          type = (types.nullOr types.bool);
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
    "garage.rajsingh.info.v1beta1.GarageKeyStatusConditions" = {

      options = {
        "lastTransitionTime" = mkOption {
          description = "lastTransitionTime is the last time the condition transitioned from one status to another.\nThis should be when the underlying condition changed.  If that is not known, then using the time when the API field changed is acceptable.";
          type = types.str;
        };
        "message" = mkOption {
          description = "message is a human readable message indicating details about the transition.\nThis may be an empty string.";
          type = (types.withMaxLength 32768 types.str);
        };
        "observedGeneration" = mkOption {
          description = "observedGeneration represents the .metadata.generation that the condition was set based upon.\nFor instance, if .metadata.generation is currently 12, but the .status.conditions[x].observedGeneration is 9, the condition is out of date\nwith respect to the current state of the instance.";
          type = (types.nullOr (types.withMinimum 0 types.int));
        };
        "reason" = mkOption {
          description = "reason contains a programmatic identifier indicating the reason for the condition's last transition.\nProducers of specific condition types may define expected values and meanings for this field,\nand whether the values are considered a guaranteed API.\nThe value should be a CamelCase string.\nThis field may not be empty.";
          type = (types.withMaxLength 1024 (types.withMinLength 1 types.str));
        };
        "status" = mkOption {
          description = "status of the condition, one of True, False, Unknown.";
          type = (
            types.enum [
              "True"
              "False"
              "Unknown"
            ]
          );
        };
        "type" = mkOption {
          description = "type of condition in CamelCase or in foo.example.com/CamelCase.";
          type = (types.withMaxLength 316 types.str);
        };
      };

      config = {
        "observedGeneration" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageKeyStatusEffectivePermissions" = {

      options = {
        "bucketAlias" = mkOption {
          description = "BucketAlias is the bucket's global alias (if set)";
          type = (types.nullOr types.str);
        };
        "bucketId" = mkOption {
          description = "BucketID is the bucket ID";
          type = (types.nullOr types.str);
        };
        "owner" = mkOption {
          description = "Owner permission";
          type = (types.nullOr types.bool);
        };
        "read" = mkOption {
          description = "Read permission";
          type = (types.nullOr types.bool);
        };
        "source" = mkOption {
          description = "Source indicates where this permission was defined (\"bucket\", \"key\", or \"both\")";
          type = (types.nullOr types.str);
        };
        "write" = mkOption {
          description = "Write permission";
          type = (types.nullOr types.bool);
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
    "garage.rajsingh.info.v1beta1.GarageKeyStatusPermissions" = {

      options = {
        "createBucket" = mkOption {
          description = "CreateBucket allows this key to create new buckets via the S3 CreateBucket API";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "createBucket" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageKeyStatusSecretRef" = {

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
    "garage.rajsingh.info.v1beta1.GarageNode" = {

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
          description = "GarageNodeSpec defines the desired state of GarageNode.\n\nA GarageNode represents one durable Garage process identity and layout role.\nIn Manual mode users create GarageNodes directly. Auto-mode default storage,\nunified gateways, and named node-local pools also use operator-owned GarageNodes\ninternally so every identity follows the same layout and drain lifecycle.\n\nUse Manual layout when you need:\n  - Heterogeneous storage (different size or storage class per node)\n  - Per-node CPU/memory resource limits\n  - Fine-grained zone assignment within a cluster\n  - External nodes (VMs, bare metal, or nodes in another K8s cluster)\n\nFor a uniform default PVC group, prefer layoutPolicy: Auto — the operator creates\nand manages the GarageNode resources.\n\nPod configuration fields are inherited from the parent GarageCluster and can be\noverridden per-node. Fields not specified here fall through to the cluster default.";
          type = (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpec");
        };
        "status" = mkOption {
          description = "GarageNodeStatus defines the observed state of GarageNode";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeStatus"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpec" = {

      options = {
        "affinity" = mkOption {
          description = "Affinity overrides pod affinity rules.\nIf not specified, inherits from GarageCluster.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinity"));
        };
        "backing" = mkOption {
          description = "Backing selects the workload that backs this node's pod.\nStatefulSet (default when empty): this GarageNode owns a single-replica\nStatefulSet. NodeLocalPool: the pod comes from a cluster-owned node-local workload\nin spec.storage.nodeLocalPools — no StatefulSet, ConfigMap, or Service is\ncreated by this GarageNode; it only manages the Garage layout role for the\nKubernetes Node and membership set named below. Immutable after creation.";
          type = (
            types.nullOr (
              types.enum [
                "StatefulSet"
                "NodeLocalPool"
              ]
            )
          );
        };
        "capacity" = mkOption {
          description = "Capacity is the storage capacity to report to Garage for this node.\nRequired unless Gateway is true.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "clusterRef" = mkOption {
          description = "ClusterRef references the GarageCluster this node belongs to.\nThe GarageNode inherits configuration from this cluster.";
          type = (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecClusterRef");
        };
        "containerSecurityContext" = mkOption {
          description = "ContainerSecurityContext overrides the container-level security context for this node.\nIf not specified, inherits from GarageCluster.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecContainerSecurityContext")
          );
        };
        "env" = mkOption {
          description = "Env overrides environment variables for this node's container. Merged with\ncluster-level env (from spec.storage.env or spec.gateway.env, depending on\ntier); per-node entries take precedence on ordinary key collisions.\nGarage config-path and RPC/Admin/metrics credential variables are\noperator-reserved because drain safety and mesh identity rely on the\nrendered config and pinned immutable Secrets.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1beta1.GarageNodeSpecEnv" "name" [ ]
            )
          );
          apply = attrsToList;
        };
        "envFrom" = mkOption {
          description = "EnvFrom overrides envFrom sources for this node's container. Replaces (does\nnot merge) the cluster-level envFrom when set. A source prefix must not be\ncapable of injecting an operator-reserved Garage variable.";
          type = (
            types.nullOr (types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecEnvFrom"))
          );
        };
        "external" = mkOption {
          description = "External marks this node as an external node (not managed by this operator).\nWhen set, no StatefulSet is created - the node is assumed to exist externally.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecExternal"));
        };
        "gateway" = mkOption {
          description = "Gateway marks this node as a gateway-only node (no storage).\nGateway nodes handle API requests but don't store data blocks. Immutable:\ndelete and drain the old identity before changing its storage tier.";
          type = (types.nullOr types.bool);
        };
        "image" = mkOption {
          description = "Image overrides the Garage container image.\nIf not specified, inherits from GarageCluster.";
          type = (types.nullOr types.str);
        };
        "imagePullPolicy" = mkOption {
          description = "ImagePullPolicy overrides the image pull policy for this node's container.\nIf not specified, inherits from GarageCluster.";
          type = (
            types.nullOr (
              types.enum [
                "Always"
                "Never"
                "IfNotPresent"
              ]
            )
          );
        };
        "imagePullSecrets" = mkOption {
          description = "ImagePullSecrets overrides the image pull secrets for this node's pod.\nIf not specified, inherits from GarageCluster.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1beta1.GarageNodeSpecImagePullSecrets"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "imageRepository" = mkOption {
          description = "ImageRepository overrides just the repository portion of the Garage image.\nIf not specified, inherits from GarageCluster.\nIgnored if image is set.";
          type = (types.nullOr types.str);
        };
        "kubernetesNodeName" = mkOption {
          description = "KubernetesNodeName is the name of the Kubernetes node this GarageNode\nrepresents. Required when backing is NodeLocalPool: node_id discovery\nselects the managed node-local-pool Pod scheduled on this Kubernetes node.\nImmutable for node-local-pool-backed GarageNodes.";
          type = (types.nullOr types.str);
        };
        "logging" = mkOption {
          description = "Logging overrides cluster-level spec.logging for this node. A non-nil field\nhere wins over the cluster value; a nil field falls through to the cluster.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecLogging"));
        };
        "maintenance" = mkOption {
          description = "Maintenance configures maintenance mode for this node.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecMaintenance"));
        };
        "network" = mkOption {
          description = "Network configures per-node RPC address overrides.\nParallel to GarageCluster's spec.network but scoped to this node only.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecNetwork"));
        };
        "nodeId" = mkOption {
          description = "NodeID is the public key of the Garage node. For an external node it is\nauthoritative because there is no managed Pod. For a managed node it is\nonly an expected identity pin: before any layout or status mutation the\noperator directly queries the exact owned Pod and requires equality. If\nomitted, the operator discovers the identity from that Pod.";
          type = (types.nullOr types.str);
        };
        "nodeLocalPoolName" = mkOption {
          description = "NodeLocalPoolName is the name of the parent GarageCluster's\nspec.storage.nodeLocalPools entry that owns this node. Required and\nimmutable when backing is NodeLocalPool; omitted for StatefulSet-backed and\nexternal GarageNodes.";
          type = (types.nullOr types.str);
        };
        "nodeSelector" = mkOption {
          description = "NodeSelector overrides node selection constraints.\nIf not specified, inherits from GarageCluster.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "podAnnotations" = mkOption {
          description = "PodAnnotations are additional annotations to add to this node's pod.\nMerged with annotations from GarageCluster (node-specific takes precedence).";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "podLabels" = mkOption {
          description = "PodLabels are additional labels to add to this node's pod.\nMerged with labels from GarageCluster (node-specific takes precedence).";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "priorityClassName" = mkOption {
          description = "PriorityClassName overrides the priority class for this node's pod.\nIf not specified, inherits from GarageCluster.";
          type = (types.nullOr types.str);
        };
        "publicEndpoint" = mkOption {
          description = "PublicEndpoint configures a Kubernetes Service exposing this node's RPC port.\nParallel to GarageCluster's spec.publicEndpoint. When set to LoadBalancer type\nwithout network.rpcPublicAddr, the operator derives rpc_public_addr from the\nassigned ingress IP automatically.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecPublicEndpoint"));
        };
        "resources" = mkOption {
          description = "Resources overrides compute resources for the Garage container.\nIf not specified, inherits from GarageCluster.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecResources"));
        };
        "securityContext" = mkOption {
          description = "SecurityContext overrides the pod-level security context for this node.\nIf not specified, inherits from GarageCluster.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecSecurityContext"));
        };
        "serviceAccountName" = mkOption {
          description = "ServiceAccountName overrides the service account for this node's pod.\nIf not specified, inherits from GarageCluster.";
          type = (types.nullOr types.str);
        };
        "storage" = mkOption {
          description = "Storage configures storage volumes for this node's StatefulSet.\nRequired for managed nodes (not External).";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecStorage"));
        };
        "tags" = mkOption {
          description = "Tags are custom tags for this node in the Garage layout.";
          type = (types.nullOr (types.listOf types.str));
        };
        "tolerations" = mkOption {
          description = "Tolerations overrides pod tolerations.\nIf not specified, inherits from GarageCluster.";
          type = (
            types.nullOr (types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecTolerations"))
          );
        };
        "topologySpreadConstraints" = mkOption {
          description = "TopologySpreadConstraints overrides topology spread constraints for this node's pod.\nIf not specified, inherits from GarageCluster.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecTopologySpreadConstraints")
            )
          );
        };
        "zone" = mkOption {
          description = "Zone is the zone assignment for this node.\nUsed for data placement and fault tolerance.";
          type = types.str;
        };
        "zoneFrom" = mkOption {
          description = "ZoneFrom derives the layout zone from a label on the Kubernetes Node this\nnode's pod is scheduled to, instead of using the static Zone above. Zone\nstays required and is the fallback before the pod is scheduled or when the\nreadable Node does not carry the label. If the operator cannot read the\nrequired Kubernetes Node, reconciliation fails closed; it does not silently\nsubstitute Zone. Cluster-scoped installation is required.\n\nThe resolved value is reported as status.zone.\n\nNot valid on external nodes — there is no pod, so there is no Kubernetes\nNode to read a label from.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecZoneFrom"));
        };
      };

      config = {
        "affinity" = mkOverride 1002 null;
        "backing" = mkOverride 1002 null;
        "capacity" = mkOverride 1002 null;
        "containerSecurityContext" = mkOverride 1002 null;
        "env" = mkOverride 1002 null;
        "envFrom" = mkOverride 1002 null;
        "external" = mkOverride 1002 null;
        "gateway" = mkOverride 1002 null;
        "image" = mkOverride 1002 null;
        "imagePullPolicy" = mkOverride 1002 null;
        "imagePullSecrets" = mkOverride 1002 null;
        "imageRepository" = mkOverride 1002 null;
        "kubernetesNodeName" = mkOverride 1002 null;
        "logging" = mkOverride 1002 null;
        "maintenance" = mkOverride 1002 null;
        "network" = mkOverride 1002 null;
        "nodeId" = mkOverride 1002 null;
        "nodeLocalPoolName" = mkOverride 1002 null;
        "nodeSelector" = mkOverride 1002 null;
        "podAnnotations" = mkOverride 1002 null;
        "podLabels" = mkOverride 1002 null;
        "priorityClassName" = mkOverride 1002 null;
        "publicEndpoint" = mkOverride 1002 null;
        "resources" = mkOverride 1002 null;
        "securityContext" = mkOverride 1002 null;
        "serviceAccountName" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "tags" = mkOverride 1002 null;
        "tolerations" = mkOverride 1002 null;
        "topologySpreadConstraints" = mkOverride 1002 null;
        "zoneFrom" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinity" = {

      options = {
        "nodeAffinity" = mkOption {
          description = "Describes node affinity scheduling rules for the pod.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityNodeAffinity")
          );
        };
        "podAffinity" = mkOption {
          description = "Describes pod affinity scheduling rules (e.g. co-locate this pod in the same node, zone, etc. as some other pod(s)).";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinity")
          );
        };
        "podAntiAffinity" = mkOption {
          description = "Describes pod anti-affinity scheduling rules (e.g. avoid putting this pod in the same node, zone, etc. as some other pod(s)).";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinity")
          );
        };
      };

      config = {
        "nodeAffinity" = mkOverride 1002 null;
        "podAffinity" = mkOverride 1002 null;
        "podAntiAffinity" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityNodeAffinity" = {

      options = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "The scheduler will prefer to schedule pods to nodes that satisfy\nthe affinity expressions specified by this field, but it may choose\na node that violates one or more of the expressions. The node that is\nmost preferred is the one with the greatest sum of weights, i.e.\nfor each node that meets all of the scheduling requirements (resource\nrequest, requiredDuringScheduling affinity expressions, etc.),\ncompute a sum by iterating through the elements of this field and adding\n\"weight\" to the sum if the node matches the corresponding matchExpressions; the\nnode(s) with the highest sum are the most preferred.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "If the affinity requirements specified by this field are not met at\nscheduling time, the pod will not be scheduled onto the node.\nIf the affinity requirements specified by this field cease to be met\nat some point during pod execution (e.g. due to an update), the system\nmay or may not try to eventually evict the pod from its node.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecution"
            )
          );
        };
      };

      config = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "preference" = mkOption {
            description = "A node selector term, associated with the corresponding weight.";
            type = (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreference"
            );
          };
          "weight" = mkOption {
            description = "Weight associated with matching the corresponding nodeSelectorTerm, in the range 1-100.";
            type = types.int;
          };
        };

        config = { };

      };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreference" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "A list of node selector requirements by node's labels.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchExpressions"
                )
              )
            );
          };
          "matchFields" = mkOption {
            description = "A list of node selector requirements by node's fields.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchFields"
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchExpressions" =
      {

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
            type = (types.nullOr (types.listOf types.str));
          };
        };

        config = {
          "values" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchFields" =
      {

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
            type = (types.nullOr (types.listOf types.str));
          };
        };

        config = {
          "values" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "nodeSelectorTerms" = mkOption {
            description = "Required. A list of node selector terms. The terms are ORed.";
            type = (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTerms"
              )
            );
          };
        };

        config = { };

      };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTerms" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "A list of node selector requirements by node's labels.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchExpressions"
                )
              )
            );
          };
          "matchFields" = mkOption {
            description = "A list of node selector requirements by node's fields.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchFields"
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchExpressions" =
      {

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
            type = (types.nullOr (types.listOf types.str));
          };
        };

        config = {
          "values" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchFields" =
      {

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
            type = (types.nullOr (types.listOf types.str));
          };
        };

        config = {
          "values" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinity" = {

      options = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "The scheduler will prefer to schedule pods to nodes that satisfy\nthe affinity expressions specified by this field, but it may choose\na node that violates one or more of the expressions. The node that is\nmost preferred is the one with the greatest sum of weights, i.e.\nfor each node that meets all of the scheduling requirements (resource\nrequest, requiredDuringScheduling affinity expressions, etc.),\ncompute a sum by iterating through the elements of this field and adding\n\"weight\" to the sum if the node has pods which matches the corresponding podAffinityTerm; the\nnode(s) with the highest sum are the most preferred.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "If the affinity requirements specified by this field are not met at\nscheduling time, the pod will not be scheduled onto the node.\nIf the affinity requirements specified by this field cease to be met\nat some point during pod execution (e.g. due to a pod label update), the\nsystem may or may not try to eventually evict the pod from its node.\nWhen there are multiple elements, the lists of nodes corresponding to each\npodAffinityTerm are intersected, i.e. all terms must be satisfied.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecution"
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "podAffinityTerm" = mkOption {
            description = "Required. A pod affinity term, associated with the corresponding weight.";
            type = (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm"
            );
          };
          "weight" = mkOption {
            description = "weight associated with matching the corresponding podAffinityTerm,\nin the range 1-100.";
            type = types.int;
          };
        };

        config = { };

      };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector"
              )
            );
          };
          "matchLabelKeys" = mkOption {
            description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "mismatchLabelKeys" = mkOption {
            description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "namespaceSelector" = mkOption {
            description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector"
              )
            );
          };
          "namespaces" = mkOption {
            description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
            type = (types.nullOr (types.listOf types.str));
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector"
              )
            );
          };
          "matchLabelKeys" = mkOption {
            description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "mismatchLabelKeys" = mkOption {
            description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "namespaceSelector" = mkOption {
            description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector"
              )
            );
          };
          "namespaces" = mkOption {
            description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
            type = (types.nullOr (types.listOf types.str));
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinity" = {

      options = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "The scheduler will prefer to schedule pods to nodes that satisfy\nthe anti-affinity expressions specified by this field, but it may choose\na node that violates one or more of the expressions. The node that is\nmost preferred is the one with the greatest sum of weights, i.e.\nfor each node that meets all of the scheduling requirements (resource\nrequest, requiredDuringScheduling anti-affinity expressions, etc.),\ncompute a sum by iterating through the elements of this field and subtracting\n\"weight\" from the sum if the node has pods which matches the corresponding podAffinityTerm; the\nnode(s) with the highest sum are the most preferred.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "If the anti-affinity requirements specified by this field are not met at\nscheduling time, the pod will not be scheduled onto the node.\nIf the anti-affinity requirements specified by this field cease to be met\nat some point during pod execution (e.g. due to a pod label update), the\nsystem may or may not try to eventually evict the pod from its node.\nWhen there are multiple elements, the lists of nodes corresponding to each\npodAffinityTerm are intersected, i.e. all terms must be satisfied.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecution"
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "podAffinityTerm" = mkOption {
            description = "Required. A pod affinity term, associated with the corresponding weight.";
            type = (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm"
            );
          };
          "weight" = mkOption {
            description = "weight associated with matching the corresponding podAffinityTerm,\nin the range 1-100.";
            type = types.int;
          };
        };

        config = { };

      };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector"
              )
            );
          };
          "matchLabelKeys" = mkOption {
            description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "mismatchLabelKeys" = mkOption {
            description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "namespaceSelector" = mkOption {
            description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector"
              )
            );
          };
          "namespaces" = mkOption {
            description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
            type = (types.nullOr (types.listOf types.str));
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector"
              )
            );
          };
          "matchLabelKeys" = mkOption {
            description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "mismatchLabelKeys" = mkOption {
            description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "namespaceSelector" = mkOption {
            description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector"
              )
            );
          };
          "namespaces" = mkOption {
            description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
            type = (types.nullOr (types.listOf types.str));
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecClusterRef" = {

      options = {
        "kubeConfigSecretRef" = mkOption {
          description = "KubeConfigSecretRef is reserved for a future remote Kubernetes client integration.\nIt is currently rejected by admission because the operator does not use it.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecClusterRefKubeConfigSecretRef"
            )
          );
        };
        "name" = mkOption {
          description = "Name of the GarageCluster resource.";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "Namespace of the GarageCluster. Defaults to the referencing resource's namespace.\nCross-namespace references require a GarageReferenceGrant where supported by\nthe owning resource. GarageNode and GarageAdminToken reject them.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "kubeConfigSecretRef" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecClusterRefKubeConfigSecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecContainerSecurityContext" = {

      options = {
        "allowPrivilegeEscalation" = mkOption {
          description = "AllowPrivilegeEscalation controls whether a process can gain more\nprivileges than its parent process. This bool directly controls if\nthe no_new_privs flag will be set on the container process.\nAllowPrivilegeEscalation is true always when the container is:\n1) run as Privileged\n2) has CAP_SYS_ADMIN\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.bool);
        };
        "appArmorProfile" = mkOption {
          description = "appArmorProfile is the AppArmor options to use by this container. If set, this profile\noverrides the pod's appArmorProfile.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecContainerSecurityContextAppArmorProfile"
            )
          );
        };
        "capabilities" = mkOption {
          description = "The capabilities to add/drop when running containers.\nDefaults to the default set of capabilities granted by the container runtime.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecContainerSecurityContextCapabilities"
            )
          );
        };
        "privileged" = mkOption {
          description = "Run container in privileged mode.\nProcesses in privileged containers are essentially equivalent to root on the host.\nDefaults to false.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.bool);
        };
        "procMount" = mkOption {
          description = "procMount denotes the type of proc mount to use for the containers.\nThe default value is Default which uses the container runtime defaults for\nreadonly paths and masked paths.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.str);
        };
        "readOnlyRootFilesystem" = mkOption {
          description = "Whether this container has a read-only root filesystem.\nDefault is false.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.bool);
        };
        "runAsGroup" = mkOption {
          description = "The GID to run the entrypoint of the container process.\nUses runtime default if unset.\nMay also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.int);
        };
        "runAsNonRoot" = mkOption {
          description = "Indicates that the container must run as a non-root user.\nIf true, the Kubelet will validate the image at runtime to ensure that it\ndoes not run as UID 0 (root) and fail to start the container if it does.\nIf unset or false, no such validation will be performed.\nMay also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
          type = (types.nullOr types.bool);
        };
        "runAsUser" = mkOption {
          description = "The UID to run the entrypoint of the container process.\nDefaults to user specified in image metadata if unspecified.\nMay also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.int);
        };
        "seLinuxOptions" = mkOption {
          description = "The SELinux context to be applied to the container.\nIf unspecified, the container runtime will allocate a random SELinux context for each\ncontainer.  May also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecContainerSecurityContextSeLinuxOptions"
            )
          );
        };
        "seccompProfile" = mkOption {
          description = "The seccomp options to use by this container. If seccomp options are\nprovided at both the pod & container level, the container options\noverride the pod options.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecContainerSecurityContextSeccompProfile"
            )
          );
        };
        "windowsOptions" = mkOption {
          description = "The Windows specific settings applied to all containers.\nIf unspecified, the options from the PodSecurityContext will be used.\nIf set in both SecurityContext and PodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is linux.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecContainerSecurityContextWindowsOptions"
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecContainerSecurityContextAppArmorProfile" = {

      options = {
        "localhostProfile" = mkOption {
          description = "localhostProfile indicates a profile loaded on the node that should be used.\nThe profile must be preconfigured on the node to work.\nMust match the loaded name of the profile.\nMust be set if and only if type is \"Localhost\".";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecContainerSecurityContextCapabilities" = {

      options = {
        "add" = mkOption {
          description = "Added capabilities";
          type = (types.nullOr (types.listOf types.str));
        };
        "drop" = mkOption {
          description = "Removed capabilities";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "add" = mkOverride 1002 null;
        "drop" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecContainerSecurityContextSeLinuxOptions" = {

      options = {
        "level" = mkOption {
          description = "Level is SELinux level label that applies to the container.";
          type = (types.nullOr types.str);
        };
        "role" = mkOption {
          description = "Role is a SELinux role label that applies to the container.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is a SELinux type label that applies to the container.";
          type = (types.nullOr types.str);
        };
        "user" = mkOption {
          description = "User is a SELinux user label that applies to the container.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "level" = mkOverride 1002 null;
        "role" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
        "user" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecContainerSecurityContextSeccompProfile" = {

      options = {
        "localhostProfile" = mkOption {
          description = "localhostProfile indicates a profile defined in a file on the node should be used.\nThe profile must be preconfigured on the node to work.\nMust be a descending path, relative to the kubelet's configured seccomp profile location.\nMust be set if type is \"Localhost\". Must NOT be set for any other type.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecContainerSecurityContextWindowsOptions" = {

      options = {
        "gmsaCredentialSpec" = mkOption {
          description = "GMSACredentialSpec is where the GMSA admission webhook\n(https://github.com/kubernetes-sigs/windows-gmsa) inlines the contents of the\nGMSA credential spec named by the GMSACredentialSpecName field.";
          type = (types.nullOr types.str);
        };
        "gmsaCredentialSpecName" = mkOption {
          description = "GMSACredentialSpecName is the name of the GMSA credential spec to use.";
          type = (types.nullOr types.str);
        };
        "hostProcess" = mkOption {
          description = "HostProcess determines if a container should be run as a 'Host Process' container.\nAll of a Pod's containers must have the same effective HostProcess value\n(it is not allowed to have a mix of HostProcess containers and non-HostProcess containers).\nIn addition, if HostProcess is true then HostNetwork must also be set to true.";
          type = (types.nullOr types.bool);
        };
        "runAsUserName" = mkOption {
          description = "The UserName in Windows to run the entrypoint of the container process.\nDefaults to the user specified in image metadata if unspecified.\nMay also be set in PodSecurityContext. If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "gmsaCredentialSpec" = mkOverride 1002 null;
        "gmsaCredentialSpecName" = mkOverride 1002 null;
        "hostProcess" = mkOverride 1002 null;
        "runAsUserName" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecEnv" = {

      options = {
        "name" = mkOption {
          description = "Name of the environment variable.\nMay consist of any printable ASCII characters except '='.";
          type = types.str;
        };
        "value" = mkOption {
          description = "Variable references $(VAR_NAME) are expanded\nusing the previously defined environment variables in the container and\nany service environment variables. If a variable cannot be resolved,\nthe reference in the input string will be unchanged. Double $$ are reduced\nto a single $, which allows for escaping the $(VAR_NAME) syntax: i.e.\n\"$$(VAR_NAME)\" will produce the string literal \"$(VAR_NAME)\".\nEscaped references will never be expanded, regardless of whether the variable\nexists or not.\nDefaults to \"\".";
          type = (types.nullOr types.str);
        };
        "valueFrom" = mkOption {
          description = "Source for the environment variable's value. Cannot be used if value is not empty.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecEnvValueFrom"));
        };
      };

      config = {
        "value" = mkOverride 1002 null;
        "valueFrom" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecEnvFrom" = {

      options = {
        "configMapRef" = mkOption {
          description = "The ConfigMap to select from";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecEnvFromConfigMapRef")
          );
        };
        "prefix" = mkOption {
          description = "Optional text to prepend to the name of each environment variable.\nMay consist of any printable ASCII characters except '='.";
          type = (types.nullOr types.str);
        };
        "secretRef" = mkOption {
          description = "The Secret to select from";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecEnvFromSecretRef"));
        };
      };

      config = {
        "configMapRef" = mkOverride 1002 null;
        "prefix" = mkOverride 1002 null;
        "secretRef" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecEnvFromConfigMapRef" = {

      options = {
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the ConfigMap must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecEnvFromSecretRef" = {

      options = {
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecEnvValueFrom" = {

      options = {
        "configMapKeyRef" = mkOption {
          description = "Selects a key of a ConfigMap.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecEnvValueFromConfigMapKeyRef")
          );
        };
        "fieldRef" = mkOption {
          description = "Selects a field of the pod: supports metadata.name, metadata.namespace, `metadata.labels['<KEY>']`, `metadata.annotations['<KEY>']`,\nspec.nodeName, spec.serviceAccountName, status.hostIP, status.podIP, status.podIPs.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecEnvValueFromFieldRef")
          );
        };
        "fileKeyRef" = mkOption {
          description = "FileKeyRef selects a key of the env file.\nRequires the EnvFiles feature gate to be enabled.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecEnvValueFromFileKeyRef")
          );
        };
        "resourceFieldRef" = mkOption {
          description = "Selects a resource of the container: only resources limits and requests\n(limits.cpu, limits.memory, limits.ephemeral-storage, requests.cpu, requests.memory and requests.ephemeral-storage) are currently supported.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecEnvValueFromResourceFieldRef")
          );
        };
        "secretKeyRef" = mkOption {
          description = "Selects a key of a secret in the pod's namespace";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecEnvValueFromSecretKeyRef")
          );
        };
      };

      config = {
        "configMapKeyRef" = mkOverride 1002 null;
        "fieldRef" = mkOverride 1002 null;
        "fileKeyRef" = mkOverride 1002 null;
        "resourceFieldRef" = mkOverride 1002 null;
        "secretKeyRef" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecEnvValueFromConfigMapKeyRef" = {

      options = {
        "key" = mkOption {
          description = "The key to select from the ConfigMap's Data field.\nKeys in the BinaryData field are not currently propagated to container env vars.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the ConfigMap or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecEnvValueFromFieldRef" = {

      options = {
        "apiVersion" = mkOption {
          description = "Version of the schema the FieldPath is written in terms of, defaults to \"v1\".";
          type = (types.nullOr types.str);
        };
        "fieldPath" = mkOption {
          description = "Path of the field to select in the specified API version.";
          type = types.str;
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecEnvValueFromFileKeyRef" = {

      options = {
        "key" = mkOption {
          description = "The key within the env file. An invalid key will prevent the pod from starting.\nThe keys defined within a source may consist of any printable ASCII characters except '='.\nDuring Alpha stage of the EnvFiles feature gate, the key size is limited to 128 characters.";
          type = types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the file or its key must be defined. If the file or key\ndoes not exist, then the env var is not published.\nIf optional is set to true and the specified key does not exist,\nthe environment variable will not be set in the Pod's containers.\n\nIf optional is set to false and the specified key does not exist,\nan error will be returned during Pod creation.";
          type = (types.nullOr types.bool);
        };
        "path" = mkOption {
          description = "The path within the volume from which to select the file.\nMust be relative and may not contain the '..' path or start with '..'.";
          type = types.str;
        };
        "volumeName" = mkOption {
          description = "The name of the volume mount containing the env file.";
          type = types.str;
        };
      };

      config = {
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecEnvValueFromResourceFieldRef" = {

      options = {
        "containerName" = mkOption {
          description = "Container name: required for volumes, optional for env vars";
          type = (types.nullOr types.str);
        };
        "divisor" = mkOption {
          description = "Specifies the output format of the exposed resources, defaults to \"1\"";
          type = (types.nullOr (types.either types.int types.str));
        };
        "resource" = mkOption {
          description = "Required: resource to select";
          type = types.str;
        };
      };

      config = {
        "containerName" = mkOverride 1002 null;
        "divisor" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecEnvValueFromSecretKeyRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecExternal" = {

      options = {
        "address" = mkOption {
          description = "Address is the IP or hostname of the external node";
          type = (types.withMinLength 1 types.str);
        };
        "port" = mkOption {
          description = "Port is the RPC port of the external node";
          type = (types.nullOr (types.withMaximum 65535 (types.withMinimum 1 types.int)));
        };
        "remoteClusterRef" = mkOption {
          description = "RemoteClusterRef is retained for API compatibility but is not supported.\nSetting it is rejected because the operator has no remote-cluster client\nintegration for GarageNode reconciliation.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecExternalRemoteClusterRef")
          );
        };
      };

      config = {
        "port" = mkOverride 1002 null;
        "remoteClusterRef" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecExternalRemoteClusterRef" = {

      options = {
        "kubeConfigSecretRef" = mkOption {
          description = "KubeConfigSecretRef is reserved for a future remote Kubernetes client integration.\nIt is currently rejected by admission because the operator does not use it.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecExternalRemoteClusterRefKubeConfigSecretRef"
            )
          );
        };
        "name" = mkOption {
          description = "Name of the GarageCluster resource.";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "Namespace of the GarageCluster. Defaults to the referencing resource's namespace.\nCross-namespace references require a GarageReferenceGrant where supported by\nthe owning resource. GarageNode and GarageAdminToken reject them.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "kubeConfigSecretRef" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecExternalRemoteClusterRefKubeConfigSecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecImagePullSecrets" = {

      options = {
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecLogging" = {

      options = {
        "journald" = mkOption {
          description = "Journald enables logging to systemd journald. When nil, inherits cluster-level setting.";
          type = (types.nullOr types.bool);
        };
        "level" = mkOption {
          description = "Level sets the log level using RUST_LOG format.";
          type = (types.nullOr types.str);
        };
        "syslog" = mkOption {
          description = "Syslog enables logging to syslog. When nil, inherits cluster-level setting.";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "journald" = mkOverride 1002 null;
        "level" = mkOverride 1002 null;
        "syslog" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecMaintenance" = {

      options = {
        "suspended" = mkOption {
          description = "Suspended pauses operator reconciliation for this node when true.";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "suspended" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecNetwork" = {

      options = {
        "rpcPublicAddr" = mkOption {
          description = "RPCPublicAddr is the externally-routable RPC address for this node (host:port).\nOverrides the cluster-level network.rpcPublicAddr for this specific node.\nWhen publicEndpoint is also set to LoadBalancer and this is empty, the operator\nderives rpc_public_addr from the assigned LoadBalancer ingress IP automatically.\nOn a node-local-pool-backed node it is published only in the replicated layout\ntags; the shared DaemonSet ConfigMap cannot carry per-node settings.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "rpcPublicAddr" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecPublicEndpoint" = {

      options = {
        "externalIP" = mkOption {
          description = "ExternalIP is retained for API compatibility but is not supported.\nSetting it is rejected because the operator does not consume the explicit\naddress mapping or template.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecPublicEndpointExternalIP")
          );
        };
        "loadBalancer" = mkOption {
          description = "LoadBalancer configuration";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecPublicEndpointLoadBalancer")
          );
        };
        "nodePort" = mkOption {
          description = "NodePort configuration";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecPublicEndpointNodePort")
          );
        };
        "type" = mkOption {
          description = "Type specifies how nodes are exposed to remote clusters for RPC";
          type = (
            types.enum [
              "LoadBalancer"
              "NodePort"
              "ExternalIP"
              "Headless"
            ]
          );
        };
      };

      config = {
        "externalIP" = mkOverride 1002 null;
        "loadBalancer" = mkOverride 1002 null;
        "nodePort" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecPublicEndpointExternalIP" = {

      options = {
        "addressTemplate" = mkOption {
          description = "AddressTemplate is retained for API compatibility but is unsupported.";
          type = (types.nullOr types.str);
        };
        "addresses" = mkOption {
          description = "Addresses is retained for API compatibility but is unsupported.";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "addressTemplate" = mkOverride 1002 null;
        "addresses" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecPublicEndpointLoadBalancer" = {

      options = {
        "annotations" = mkOption {
          description = "Annotations to add to the service.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "labels" = mkOption {
          description = "Labels to add to the service. Operator-managed labels take precedence on conflict.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "perNode" = mkOption {
          description = "PerNode creates a separate LoadBalancer service per GarageCluster pod instead\nof one shared LoadBalancer service. In auto-layout GarageCluster mode, those\nservices are used for operator-driven reverse ConnectClusterNodes calls; the\npods still share one Garage ConfigMap, so distinct per-pod rpc_public_addr\nvalues are not written into Garage config. Use Manual layout with GarageNode\nresources when each node also needs its own advertised rpc_public_addr.";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "perNode" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecPublicEndpointNodePort" = {

      options = {
        "annotations" = mkOption {
          description = "Annotations to add to the service.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "basePort" = mkOption {
          description = "BasePort is the starting NodePort; Garage pod N is exposed on BasePort+N.\nIf omitted, the controller allocates starting from the RPC port base (30901).";
          type = (types.nullOr (types.withMaximum 32767 (types.withMinimum 30000 types.int)));
        };
        "externalAddresses" = mkOption {
          description = "ExternalAddresses are the externally-reachable IPs or hostnames of the Kubernetes nodes.\nThe operator maps Garage pod N to ExternalAddresses[N % len(ExternalAddresses)],\nso the order should be stable. Must have at least one entry.";
          type = (types.listOf types.str);
        };
        "labels" = mkOption {
          description = "Labels to add to the service. Operator-managed labels take precedence on conflict.";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "basePort" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecResources" = {

      options = {
        "claims" = mkOption {
          description = "Claims lists the names of resources, defined in spec.resourceClaims,\nthat are used by this container.\n\nThis field depends on the\nDynamicResourceAllocation feature gate.\n\nThis field is immutable. It can only be set for containers.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1beta1.GarageNodeSpecResourcesClaims"
                "name"
                [ "name" ]
            )
          );
          apply = attrsToList;
        };
        "limits" = mkOption {
          description = "Limits describes the maximum amount of compute resources allowed.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
        };
        "requests" = mkOption {
          description = "Requests describes the minimum amount of compute resources required.\nIf Requests is omitted for a container, it defaults to Limits if that is explicitly specified,\notherwise to an implementation-defined value. Requests cannot exceed Limits.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
        };
      };

      config = {
        "claims" = mkOverride 1002 null;
        "limits" = mkOverride 1002 null;
        "requests" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecResourcesClaims" = {

      options = {
        "name" = mkOption {
          description = "Name must match the name of one entry in pod.spec.resourceClaims of\nthe Pod where this field is used. It makes that resource available\ninside a container.";
          type = types.str;
        };
        "request" = mkOption {
          description = "Request is the name chosen for a request in the referenced claim.\nIf empty, everything from the claim is made available, otherwise\nonly the result of this request.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "request" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecSecurityContext" = {

      options = {
        "appArmorProfile" = mkOption {
          description = "appArmorProfile is the AppArmor options to use by the containers in this pod.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecSecurityContextAppArmorProfile"
            )
          );
        };
        "fsGroup" = mkOption {
          description = "A special supplemental group that applies to all containers in a pod.\nSome volume types allow the Kubelet to change the ownership of that volume\nto be owned by the pod:\n\n1. The owning GID will be the FSGroup\n2. The setgid bit is set (new files created in the volume will be owned by FSGroup)\n3. The permission bits are OR'd with rw-rw----\n\nIf unset, the Kubelet will not modify the ownership and permissions of any volume.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.int);
        };
        "fsGroupChangePolicy" = mkOption {
          description = "fsGroupChangePolicy defines behavior of changing ownership and permission of the volume\nbefore being exposed inside Pod. This field will only apply to\nvolume types which support fsGroup based ownership(and permissions).\nIt will have no effect on ephemeral volume types such as: secret, configmaps\nand emptydir.\nValid values are \"OnRootMismatch\" and \"Always\". If not specified, \"Always\" is used.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.str);
        };
        "runAsGroup" = mkOption {
          description = "The GID to run the entrypoint of the container process.\nUses runtime default if unset.\nMay also be set in SecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence\nfor that container.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.int);
        };
        "runAsNonRoot" = mkOption {
          description = "Indicates that the container must run as a non-root user.\nIf true, the Kubelet will validate the image at runtime to ensure that it\ndoes not run as UID 0 (root) and fail to start the container if it does.\nIf unset or false, no such validation will be performed.\nMay also be set in SecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
          type = (types.nullOr types.bool);
        };
        "runAsUser" = mkOption {
          description = "The UID to run the entrypoint of the container process.\nDefaults to user specified in image metadata if unspecified.\nMay also be set in SecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence\nfor that container.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.int);
        };
        "seLinuxChangePolicy" = mkOption {
          description = "seLinuxChangePolicy defines how the container's SELinux label is applied to all volumes used by the Pod.\nIt has no effect on nodes that do not support SELinux or to volumes does not support SELinux.\nValid values are \"MountOption\" and \"Recursive\".\n\n\"Recursive\" means relabeling of all files on all Pod volumes by the container runtime.\nThis may be slow for large volumes, but allows mixing privileged and unprivileged Pods sharing the same volume on the same node.\n\n\"MountOption\" mounts all eligible Pod volumes with `-o context` mount option.\nThis requires all Pods that share the same volume to use the same SELinux label.\nIt is not possible to share the same volume among privileged and unprivileged Pods.\nEligible volumes are in-tree FibreChannel and iSCSI volumes, and all CSI volumes\nwhose CSI driver announces SELinux support by setting spec.seLinuxMount: true in their\nCSIDriver instance. Other volumes are always re-labelled recursively.\n\nIf not specified, \"MountOption\" is used.\n\nThis field affects only Pods that have SELinux label set, either in PodSecurityContext or in SecurityContext of all containers.\n\nAll Pods that use the same volume should use the same seLinuxChangePolicy, otherwise some pods can get stuck in ContainerCreating state.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.str);
        };
        "seLinuxOptions" = mkOption {
          description = "The SELinux context to be applied to all containers.\nIf unspecified, the container runtime will allocate a random SELinux context for each\ncontainer.  May also be set in SecurityContext.  If set in\nboth SecurityContext and PodSecurityContext, the value specified in SecurityContext\ntakes precedence for that container.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecSecurityContextSeLinuxOptions"
            )
          );
        };
        "seccompProfile" = mkOption {
          description = "The seccomp options to use by the containers in this pod.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecSecurityContextSeccompProfile"
            )
          );
        };
        "supplementalGroups" = mkOption {
          description = "A list of groups applied to the first process run in each container, in\naddition to the container's primary GID and fsGroup (if specified).  If\nthe SupplementalGroupsPolicy feature is enabled, the\nsupplementalGroupsPolicy field determines whether these are in addition\nto or instead of any group memberships defined in the container image.\nIf unspecified, no additional groups are added, though group memberships\ndefined in the container image may still be used, depending on the\nsupplementalGroupsPolicy field.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr (types.listOf types.int));
        };
        "supplementalGroupsPolicy" = mkOption {
          description = "Defines how supplemental groups of the first container processes are calculated.\nValid values are \"Merge\" and \"Strict\". If not specified, \"Merge\" is used.\n(Alpha) Using the field requires the SupplementalGroupsPolicy feature gate to be enabled\nand the container runtime must implement support for this feature.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.str);
        };
        "sysctls" = mkOption {
          description = "Sysctls hold a list of namespaced sysctls used for the pod. Pods with unsupported\nsysctls (by the container runtime) might fail to launch.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "garage.rajsingh.info.v1beta1.GarageNodeSpecSecurityContextSysctls"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "windowsOptions" = mkOption {
          description = "The Windows specific settings applied to all containers.\nIf unspecified, the options within a container's SecurityContext will be used.\nIf set in both SecurityContext and PodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is linux.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecSecurityContextWindowsOptions"
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecSecurityContextAppArmorProfile" = {

      options = {
        "localhostProfile" = mkOption {
          description = "localhostProfile indicates a profile loaded on the node that should be used.\nThe profile must be preconfigured on the node to work.\nMust match the loaded name of the profile.\nMust be set if and only if type is \"Localhost\".";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecSecurityContextSeLinuxOptions" = {

      options = {
        "level" = mkOption {
          description = "Level is SELinux level label that applies to the container.";
          type = (types.nullOr types.str);
        };
        "role" = mkOption {
          description = "Role is a SELinux role label that applies to the container.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is a SELinux type label that applies to the container.";
          type = (types.nullOr types.str);
        };
        "user" = mkOption {
          description = "User is a SELinux user label that applies to the container.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "level" = mkOverride 1002 null;
        "role" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
        "user" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecSecurityContextSeccompProfile" = {

      options = {
        "localhostProfile" = mkOption {
          description = "localhostProfile indicates a profile defined in a file on the node should be used.\nThe profile must be preconfigured on the node to work.\nMust be a descending path, relative to the kubelet's configured seccomp profile location.\nMust be set if type is \"Localhost\". Must NOT be set for any other type.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecSecurityContextSysctls" = {

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

      config = { };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecSecurityContextWindowsOptions" = {

      options = {
        "gmsaCredentialSpec" = mkOption {
          description = "GMSACredentialSpec is where the GMSA admission webhook\n(https://github.com/kubernetes-sigs/windows-gmsa) inlines the contents of the\nGMSA credential spec named by the GMSACredentialSpecName field.";
          type = (types.nullOr types.str);
        };
        "gmsaCredentialSpecName" = mkOption {
          description = "GMSACredentialSpecName is the name of the GMSA credential spec to use.";
          type = (types.nullOr types.str);
        };
        "hostProcess" = mkOption {
          description = "HostProcess determines if a container should be run as a 'Host Process' container.\nAll of a Pod's containers must have the same effective HostProcess value\n(it is not allowed to have a mix of HostProcess containers and non-HostProcess containers).\nIn addition, if HostProcess is true then HostNetwork must also be set to true.";
          type = (types.nullOr types.bool);
        };
        "runAsUserName" = mkOption {
          description = "The UserName in Windows to run the entrypoint of the container process.\nDefaults to the user specified in image metadata if unspecified.\nMay also be set in PodSecurityContext. If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "gmsaCredentialSpec" = mkOverride 1002 null;
        "gmsaCredentialSpecName" = mkOverride 1002 null;
        "hostProcess" = mkOverride 1002 null;
        "runAsUserName" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecStorage" = {

      options = {
        "data" = mkOption {
          description = "Data volume for block storage. Ignored for gateway nodes.\nMutually exclusive with DataPaths.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageData"));
        };
        "dataFsync" = mkOption {
          description = "DataFsync enables fsync on data block writes for this node.\nOverrides the cluster-level storage.dataFsync setting.";
          type = (types.nullOr types.bool);
        };
        "dataPaths" = mkOption {
          description = "DataPaths configures multiple data directories for multi-HDD nodes.\nEach entry produces a separate volume/mount/PVC at /var/lib/garage/data-<idx>\nand the corresponding garage.toml `data_dir = [...]` array form. Use this for\nmulti-HDD nodes; mutually exclusive with .data.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageDataPaths")
            )
          );
        };
        "metadata" = mkOption {
          description = "Metadata volume for node identity and cluster state.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageMetadata"));
        };
        "metadataAutoSnapshotInterval" = mkOption {
          description = "MetadataAutoSnapshotInterval overrides the cluster-level\nstorage.metadataAutoSnapshotInterval (garage.toml `metadata_auto_snapshot_interval`)\nfor this node.";
          type = (types.nullOr types.str);
        };
        "metadataFsync" = mkOption {
          description = "MetadataFsync enables fsync on metadata writes for this node.\nOverrides the cluster-level storage.metadataFsync setting.";
          type = (types.nullOr types.bool);
        };
        "metadataSnapshotsDir" = mkOption {
          description = "MetadataSnapshotsDir overrides the cluster-level storage.metadataSnapshotsDir\n(garage.toml `metadata_snapshots_dir`) for this node.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "data" = mkOverride 1002 null;
        "dataFsync" = mkOverride 1002 null;
        "dataPaths" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "metadataAutoSnapshotInterval" = mkOverride 1002 null;
        "metadataFsync" = mkOverride 1002 null;
        "metadataSnapshotsDir" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageData" = {

      options = {
        "accessModes" = mkOption {
          description = "AccessModes for the dynamically provisioned PVC.\nDefaults to [ReadWriteOnce] if not specified.";
          type = (types.nullOr (types.listOf types.str));
        };
        "annotations" = mkOption {
          description = "Annotations to set on dynamically provisioned PVCs.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "dataSourceRef" = mkOption {
          description = "DataSourceRef is the opt-in restore source for this node's newly created PVC.\nAuto-generated nodes inherit the parent volume's source. Manual nodes may set\nit on a new claim; it cannot be combined with existingClaim.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageDataDataSourceRef")
          );
        };
        "existingClaim" = mkOption {
          description = "ExistingClaim references a pre-existing PVC by name in the cluster namespace.\nGarageNode cycle automation never reuses or infers a replacement from this\nclaim; create a distinct replacement GarageNode and drain this identity.";
          type = (types.nullOr types.str);
        };
        "labels" = mkOption {
          description = "Labels to set on dynamically provisioned PVCs.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "path" = mkOption {
          description = "Path is the in-container mount path for this volume. Only honored on\nmulti-HDD `storage.dataPaths[]` entries — both the K8s volumeMount and\nthe rendered garage.toml `data_dir = [{ path = ... }]` use this value.\nDefaults to `/data/data-<i>` when unset. The legacy-STS migration\npropagates `cluster.spec.storage.data.paths[i].path` so that on first\nboot Garage's DataLayout sees the same paths it stored under\npre-migration, avoiding partition reassignment and unnecessary\ncross-peer block refetch (../garage src/block/layout.rs).";
          type = (types.nullOr types.str);
        };
        "readOnly" = mkOption {
          description = "ReadOnly marks the entry as a legacy read-only path on multi-HDD\n`storage.dataPaths[]`. Renders as garage.toml `read_only = true`;\nno `capacity` is emitted. New use on `storage.{metadata,data}` is rejected;\nunchanged released objects are tolerated only for cleanup and migration.";
          type = (types.nullOr types.bool);
        };
        "selector" = mkOption {
          description = "Selector matches pre-provisioned PersistentVolumes for a newly created\nclaim. Kubernetes does not dynamically provision a PV when this is set;\nStorageClassName must also match the target PV. It is immutable for a live\nGarageNode because changing an already bound claim cannot move the durable\nnode_key or block data safely.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageDataSelector")
          );
        };
        "size" = mkOption {
          description = "Size creates a dynamically provisioned PVC with this capacity. For\nmulti-HDD `storage.dataPaths[]` entries it may also be set alongside\n`existingClaim` to declare the capacity advertised to Garage.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "storageClassName" = mkOption {
          description = "StorageClassName for the dynamically provisioned PVC.\nUses the cluster default if not specified.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type specifies the volume type. Defaults to PersistentVolumeClaim.\nUse EmptyDir for ephemeral storage (e.g. testing).";
          type = (
            types.nullOr (
              types.enum [
                "PersistentVolumeClaim"
                "EmptyDir"
              ]
            )
          );
        };
      };

      config = {
        "accessModes" = mkOverride 1002 null;
        "annotations" = mkOverride 1002 null;
        "dataSourceRef" = mkOverride 1002 null;
        "existingClaim" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "readOnly" = mkOverride 1002 null;
        "selector" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "storageClassName" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageDataDataSourceRef" = {

      options = {
        "apiGroup" = mkOption {
          description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
          type = (types.nullOr types.str);
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
          type = (types.nullOr types.str);
        };
      };

      config = {
        "apiGroup" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageDataPaths" = {

      options = {
        "accessModes" = mkOption {
          description = "AccessModes for the dynamically provisioned PVC.\nDefaults to [ReadWriteOnce] if not specified.";
          type = (types.nullOr (types.listOf types.str));
        };
        "annotations" = mkOption {
          description = "Annotations to set on dynamically provisioned PVCs.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "dataSourceRef" = mkOption {
          description = "DataSourceRef is the opt-in restore source for this node's newly created PVC.\nAuto-generated nodes inherit the parent volume's source. Manual nodes may set\nit on a new claim; it cannot be combined with existingClaim.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageDataPathsDataSourceRef"
            )
          );
        };
        "existingClaim" = mkOption {
          description = "ExistingClaim references a pre-existing PVC by name in the cluster namespace.\nGarageNode cycle automation never reuses or infers a replacement from this\nclaim; create a distinct replacement GarageNode and drain this identity.";
          type = (types.nullOr types.str);
        };
        "labels" = mkOption {
          description = "Labels to set on dynamically provisioned PVCs.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "path" = mkOption {
          description = "Path is the in-container mount path for this volume. Only honored on\nmulti-HDD `storage.dataPaths[]` entries — both the K8s volumeMount and\nthe rendered garage.toml `data_dir = [{ path = ... }]` use this value.\nDefaults to `/data/data-<i>` when unset. The legacy-STS migration\npropagates `cluster.spec.storage.data.paths[i].path` so that on first\nboot Garage's DataLayout sees the same paths it stored under\npre-migration, avoiding partition reassignment and unnecessary\ncross-peer block refetch (../garage src/block/layout.rs).";
          type = (types.nullOr types.str);
        };
        "readOnly" = mkOption {
          description = "ReadOnly marks the entry as a legacy read-only path on multi-HDD\n`storage.dataPaths[]`. Renders as garage.toml `read_only = true`;\nno `capacity` is emitted. New use on `storage.{metadata,data}` is rejected;\nunchanged released objects are tolerated only for cleanup and migration.";
          type = (types.nullOr types.bool);
        };
        "selector" = mkOption {
          description = "Selector matches pre-provisioned PersistentVolumes for a newly created\nclaim. Kubernetes does not dynamically provision a PV when this is set;\nStorageClassName must also match the target PV. It is immutable for a live\nGarageNode because changing an already bound claim cannot move the durable\nnode_key or block data safely.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageDataPathsSelector")
          );
        };
        "size" = mkOption {
          description = "Size creates a dynamically provisioned PVC with this capacity. For\nmulti-HDD `storage.dataPaths[]` entries it may also be set alongside\n`existingClaim` to declare the capacity advertised to Garage.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "storageClassName" = mkOption {
          description = "StorageClassName for the dynamically provisioned PVC.\nUses the cluster default if not specified.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type specifies the volume type. Defaults to PersistentVolumeClaim.\nUse EmptyDir for ephemeral storage (e.g. testing).";
          type = (
            types.nullOr (
              types.enum [
                "PersistentVolumeClaim"
                "EmptyDir"
              ]
            )
          );
        };
      };

      config = {
        "accessModes" = mkOverride 1002 null;
        "annotations" = mkOverride 1002 null;
        "dataSourceRef" = mkOverride 1002 null;
        "existingClaim" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "readOnly" = mkOverride 1002 null;
        "selector" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "storageClassName" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageDataPathsDataSourceRef" = {

      options = {
        "apiGroup" = mkOption {
          description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
          type = (types.nullOr types.str);
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
          type = (types.nullOr types.str);
        };
      };

      config = {
        "apiGroup" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageDataPathsSelector" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageDataPathsSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageDataPathsSelectorMatchExpressions" = {

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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageDataSelector" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageDataSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageDataSelectorMatchExpressions" = {

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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageMetadata" = {

      options = {
        "accessModes" = mkOption {
          description = "AccessModes for the dynamically provisioned PVC.\nDefaults to [ReadWriteOnce] if not specified.";
          type = (types.nullOr (types.listOf types.str));
        };
        "annotations" = mkOption {
          description = "Annotations to set on dynamically provisioned PVCs.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "dataSourceRef" = mkOption {
          description = "DataSourceRef is the opt-in restore source for this node's newly created PVC.\nAuto-generated nodes inherit the parent volume's source. Manual nodes may set\nit on a new claim; it cannot be combined with existingClaim.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageMetadataDataSourceRef")
          );
        };
        "existingClaim" = mkOption {
          description = "ExistingClaim references a pre-existing PVC by name in the cluster namespace.\nGarageNode cycle automation never reuses or infers a replacement from this\nclaim; create a distinct replacement GarageNode and drain this identity.";
          type = (types.nullOr types.str);
        };
        "labels" = mkOption {
          description = "Labels to set on dynamically provisioned PVCs.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "path" = mkOption {
          description = "Path is the in-container mount path for this volume. Only honored on\nmulti-HDD `storage.dataPaths[]` entries — both the K8s volumeMount and\nthe rendered garage.toml `data_dir = [{ path = ... }]` use this value.\nDefaults to `/data/data-<i>` when unset. The legacy-STS migration\npropagates `cluster.spec.storage.data.paths[i].path` so that on first\nboot Garage's DataLayout sees the same paths it stored under\npre-migration, avoiding partition reassignment and unnecessary\ncross-peer block refetch (../garage src/block/layout.rs).";
          type = (types.nullOr types.str);
        };
        "readOnly" = mkOption {
          description = "ReadOnly marks the entry as a legacy read-only path on multi-HDD\n`storage.dataPaths[]`. Renders as garage.toml `read_only = true`;\nno `capacity` is emitted. New use on `storage.{metadata,data}` is rejected;\nunchanged released objects are tolerated only for cleanup and migration.";
          type = (types.nullOr types.bool);
        };
        "selector" = mkOption {
          description = "Selector matches pre-provisioned PersistentVolumes for a newly created\nclaim. Kubernetes does not dynamically provision a PV when this is set;\nStorageClassName must also match the target PV. It is immutable for a live\nGarageNode because changing an already bound claim cannot move the durable\nnode_key or block data safely.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageMetadataSelector")
          );
        };
        "size" = mkOption {
          description = "Size creates a dynamically provisioned PVC with this capacity. For\nmulti-HDD `storage.dataPaths[]` entries it may also be set alongside\n`existingClaim` to declare the capacity advertised to Garage.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "storageClassName" = mkOption {
          description = "StorageClassName for the dynamically provisioned PVC.\nUses the cluster default if not specified.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type specifies the volume type. Defaults to PersistentVolumeClaim.\nUse EmptyDir for ephemeral storage (e.g. testing).";
          type = (
            types.nullOr (
              types.enum [
                "PersistentVolumeClaim"
                "EmptyDir"
              ]
            )
          );
        };
      };

      config = {
        "accessModes" = mkOverride 1002 null;
        "annotations" = mkOverride 1002 null;
        "dataSourceRef" = mkOverride 1002 null;
        "existingClaim" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "readOnly" = mkOverride 1002 null;
        "selector" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "storageClassName" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageMetadataDataSourceRef" = {

      options = {
        "apiGroup" = mkOption {
          description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
          type = (types.nullOr types.str);
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
          type = (types.nullOr types.str);
        };
      };

      config = {
        "apiGroup" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageMetadataSelector" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageMetadataSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecStorageMetadataSelectorMatchExpressions" = {

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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecTolerations" = {

      options = {
        "effect" = mkOption {
          description = "Effect indicates the taint effect to match. Empty means match all taint effects.\nWhen specified, allowed values are NoSchedule, PreferNoSchedule and NoExecute.";
          type = (types.nullOr types.str);
        };
        "key" = mkOption {
          description = "Key is the taint key that the toleration applies to. Empty means match all taint keys.\nIf the key is empty, operator must be Exists; this combination means to match all values and all keys.";
          type = (types.nullOr types.str);
        };
        "operator" = mkOption {
          description = "Operator represents a key's relationship to the value.\nValid operators are Exists, Equal, Lt, and Gt. Defaults to Equal.\nExists is equivalent to wildcard for value, so that a pod can\ntolerate all taints of a particular category.\nLt and Gt perform numeric comparisons (requires feature gate TaintTolerationComparisonOperators).";
          type = (types.nullOr types.str);
        };
        "tolerationSeconds" = mkOption {
          description = "TolerationSeconds represents the period of time the toleration (which must be\nof effect NoExecute, otherwise this field is ignored) tolerates the taint. By default,\nit is not set, which means tolerate the taint forever (do not evict). Zero and\nnegative values will be treated as 0 (evict immediately) by the system.";
          type = (types.nullOr types.int);
        };
        "value" = mkOption {
          description = "Value is the taint value the toleration matches to.\nIf the operator is Exists, the value should be empty, otherwise just a regular string.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecTopologySpreadConstraints" = {

      options = {
        "labelSelector" = mkOption {
          description = "LabelSelector is used to find matching pods.\nPods that match this label selector are counted to determine the number of pods\nin their corresponding topology domain.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecTopologySpreadConstraintsLabelSelector"
            )
          );
        };
        "matchLabelKeys" = mkOption {
          description = "MatchLabelKeys is a set of pod label keys to select the pods over which\nspreading will be calculated. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are ANDed with labelSelector\nto select the group of existing pods over which spreading will be calculated\nfor the incoming pod. The same key is forbidden to exist in both MatchLabelKeys and LabelSelector.\nMatchLabelKeys cannot be set when LabelSelector isn't set.\nKeys that don't exist in the incoming pod labels will\nbe ignored. A null or empty list means only match against labelSelector.\n\nThis is a beta field and requires the MatchLabelKeysInPodTopologySpread feature gate to be enabled (enabled by default).";
          type = (types.nullOr (types.listOf types.str));
        };
        "maxSkew" = mkOption {
          description = "MaxSkew describes the degree to which pods may be unevenly distributed.\nWhen `whenUnsatisfiable=DoNotSchedule`, it is the maximum permitted difference\nbetween the number of matching pods in the target topology and the global minimum.\nThe global minimum is the minimum number of matching pods in an eligible domain\nor zero if the number of eligible domains is less than MinDomains.\nFor example, in a 3-zone cluster, MaxSkew is set to 1, and pods with the same\nlabelSelector spread as 2/2/1:\nIn this case, the global minimum is 1.\n| zone1 | zone2 | zone3 |\n|  P P  |  P P  |   P   |\n- if MaxSkew is 1, incoming pod can only be scheduled to zone3 to become 2/2/2;\nscheduling it onto zone1(zone2) would make the ActualSkew(3-1) on zone1(zone2)\nviolate MaxSkew(1).\n- if MaxSkew is 2, incoming pod can be scheduled onto any zone.\nWhen `whenUnsatisfiable=ScheduleAnyway`, it is used to give higher precedence\nto topologies that satisfy it.\nIt's a required field. Default value is 1 and 0 is not allowed.";
          type = types.int;
        };
        "minDomains" = mkOption {
          description = "MinDomains indicates a minimum number of eligible domains.\nWhen the number of eligible domains with matching topology keys is less than minDomains,\nPod Topology Spread treats \"global minimum\" as 0, and then the calculation of Skew is performed.\nAnd when the number of eligible domains with matching topology keys equals or greater than minDomains,\nthis value has no effect on scheduling.\nAs a result, when the number of eligible domains is less than minDomains,\nscheduler won't schedule more than maxSkew Pods to those domains.\nIf value is nil, the constraint behaves as if MinDomains is equal to 1.\nValid values are integers greater than 0.\nWhen value is not nil, WhenUnsatisfiable must be DoNotSchedule.\n\nFor example, in a 3-zone cluster, MaxSkew is set to 2, MinDomains is set to 5 and pods with the same\nlabelSelector spread as 2/2/2:\n| zone1 | zone2 | zone3 |\n|  P P  |  P P  |  P P  |\nThe number of domains is less than 5(MinDomains), so \"global minimum\" is treated as 0.\nIn this situation, new pod with the same labelSelector cannot be scheduled,\nbecause computed skew will be 3(3 - 0) if new Pod is scheduled to any of the three zones,\nit will violate MaxSkew.";
          type = (types.nullOr types.int);
        };
        "nodeAffinityPolicy" = mkOption {
          description = "NodeAffinityPolicy indicates how we will treat Pod's nodeAffinity/nodeSelector\nwhen calculating pod topology spread skew. Options are:\n- Honor: only nodes matching nodeAffinity/nodeSelector are included in the calculations.\n- Ignore: nodeAffinity/nodeSelector are ignored. All nodes are included in the calculations.\n\nIf this value is nil, the behavior is equivalent to the Honor policy.";
          type = (types.nullOr types.str);
        };
        "nodeTaintsPolicy" = mkOption {
          description = "NodeTaintsPolicy indicates how we will treat node taints when calculating\npod topology spread skew. Options are:\n- Honor: nodes without taints, along with tainted nodes for which the incoming pod\nhas a toleration, are included.\n- Ignore: node taints are ignored. All nodes are included.\n\nIf this value is nil, the behavior is equivalent to the Ignore policy.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecTopologySpreadConstraintsLabelSelector" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeSpecTopologySpreadConstraintsLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecTopologySpreadConstraintsLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta1.GarageNodeSpecZoneFrom" = {

      options = {
        "nodeLabel" = mkOption {
          description = "NodeLabel is the label key on the Kubernetes Node whose value becomes the\nGarage layout zone.";
          type = (types.withMaxLength 316 (types.withMinLength 1 types.str));
        };
      };

      config = { };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeStatus" = {

      options = {
        "address" = mkOption {
          description = "Address is the node's address in the cluster";
          type = (types.nullOr types.str);
        };
        "blockErrors" = mkOption {
          description = "BlockErrors is retained for API compatibility but is not currently populated;\nGarage's node-status API does not expose a per-node block error count.";
          type = (types.nullOr types.int);
        };
        "clusterAdminEndpoint" = mkOption {
          description = "ClusterAdminEndpoint is the resolved Garage Admin API endpoint last used\nto manage this node's layout entry. Captured on each successful reconcile\nso that a delete-time finalizer can still attempt to drop the layout\nentry when the parent GarageCluster CR has already been deleted (edge\ngateway pattern via spec.connectTo.adminApiEndpoint).";
          type = (types.nullOr types.str);
        };
        "clusterAdminTokenSecretRef" = mkOption {
          description = "ClusterAdminTokenSecretRef references the Admin API token secret last\nused to manage this node's layout entry. The secret lives in the same\nnamespace as the GarageNode. Paired with ClusterAdminEndpoint to enable\nbest-effort finalize against an external admin API after the parent\nGarageCluster CR is gone.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeStatusClusterAdminTokenSecretRef")
          );
        };
        "conditions" = mkOption {
          description = "Conditions represent the current state";
          type = (
            types.nullOr (types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeStatusConditions"))
          );
        };
        "connected" = mkOption {
          description = "Connected indicates if the node is currently connected";
          type = (types.nullOr types.bool);
        };
        "cyclePhase" = mkOption {
          description = "CyclePhase tracks progress of a graceful node cycle triggered by the\ngarage.rajsingh.info/cycle annotation. Empty when no cycle is active.\nUsed to make the add-before-remove state machine resumable/idempotent\nacross requeues: a non-empty value means a sibling has already been\nprovisioned, so the operator continues the swap rather than re-provisioning.";
          type = (
            types.nullOr (
              types.enum [
                "Provisioning"
                "Syncing"
                "Draining"
              ]
            )
          );
        };
        "cycleSiblingName" = mkOption {
          description = "CycleSiblingName is the name of the sibling GarageNode provisioned for an\nin-progress cycle (the replacement that takes over this node's layout slot).";
          type = (types.nullOr types.str);
        };
        "cycleSiblingNodeId" = mkOption {
          description = "CycleSiblingNodeID is the exact discovered Garage node ID of the cycle\nsibling. It binds later promotion to the identity that was admitted into the\nsettled layout and the source's durable drain destination proof.";
          type = (types.nullOr types.str);
        };
        "dataPartition" = mkOption {
          description = "DataPartition contains disk space info for the data partition\nNote: Garage reports a single partition even with multiple data paths";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeStatusDataPartition"));
        };
        "dbEngine" = mkOption {
          description = "DBEngine is retained for API compatibility but is not currently populated;\nGarage's node-status API does not report the active database engine.";
          type = (types.nullOr types.str);
        };
        "garageFeatures" = mkOption {
          description = "GarageFeatures is retained for API compatibility but is not currently\npopulated because Garage's node-status API does not report build features.";
          type = (types.nullOr (types.listOf types.str));
        };
        "hostname" = mkOption {
          description = "Hostname is the hostname reported by this Garage node";
          type = (types.nullOr types.str);
        };
        "inLayout" = mkOption {
          description = "InLayout indicates if this node is part of the current layout";
          type = (types.nullOr types.bool);
        };
        "lastSeen" = mkOption {
          description = "LastSeen is when the node was last seen connected";
          type = (types.nullOr types.str);
        };
        "layoutVersion" = mkOption {
          description = "LayoutVersion is the layout version when this node was added";
          type = (types.nullOr types.int);
        };
        "managedPVCs" = mkOption {
          description = "ManagedPVCs records convention-named PVC reservations made by this\ncontroller. A pending entry contains only a one-way nonce commitment; a\nbound entry contains the exact server-assigned UID. Names and public\nannotations are not ownership proof. Legacy claims are pinned here once\nwhile their exact live StatefulSet and Pod still prove continuity.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1beta1.GarageNodeStatusManagedPVCs" "name"
                [ "name" ]
            )
          );
          apply = attrsToList;
        };
        "metadataPartition" = mkOption {
          description = "MetadataPartition contains disk space info for the metadata partition";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageNodeStatusMetadataPartition")
          );
        };
        "nodeId" = mkOption {
          description = "NodeID is the discovered or assigned node ID";
          type = (types.nullOr types.str);
        };
        "observedGeneration" = mkOption {
          description = "ObservedGeneration is the last observed generation";
          type = (types.nullOr types.int);
        };
        "observedPodUid" = mkOption {
          description = "ObservedPodUID is the UID of the workload pod whose Garage identity was\ndirectly observed. The operator persists it with the first authenticated\nNodeID and refreshes it with status so a replacement pod cannot inherit\nstale identity, connectivity, or layout evidence from its predecessor.";
          type = (types.nullOr types.str);
        };
        "parentDeletionRequestGeneration" = mkOption {
          description = "ParentDeletionRequestGeneration is a controller-owned handoff from the\nGarageCluster reconciler. A non-zero value means that parent generation\nstill intends to delete this GarageNode after reversible drain preparation.\nBinding the request to the parent generation makes a spec change cancel the\nrequest before any role is removed. A user-set drain annotation never sets\nthis field and therefore remains prepare-only.";
          type = (types.nullOr types.int);
        };
        "partitions" = mkOption {
          description = "Partitions is the number of partitions assigned to this node";
          type = (types.nullOr types.int);
        };
        "phase" = mkOption {
          description = "Phase represents the current phase";
          type = (
            types.nullOr (
              types.enum [
                "Pending"
                "Creating"
                "Running"
                "Ready"
                "Degraded"
                "Updating"
                "Deleting"
                "Failed"
                "Unknown"
              ]
            )
          );
        };
        "repairInProgress" = mkOption {
          description = "RepairInProgress is retained for API compatibility but is not currently\npopulated because Garage's Admin API exposes no per-node repair status.";
          type = (types.nullOr types.bool);
        };
        "repairProgress" = mkOption {
          description = "RepairProgress is retained for API compatibility but is not currently populated.";
          type = (types.nullOr types.str);
        };
        "repairType" = mkOption {
          description = "RepairType is retained for API compatibility but is not currently populated.";
          type = (types.nullOr types.str);
        };
        "storedData" = mkOption {
          description = "StoredData is retained for API compatibility but is not currently populated;\nGarage reports assigned partitions and disk free space, not per-node stored bytes.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "tags" = mkOption {
          description = "Tags are the tags assigned to this node in the layout";
          type = (types.nullOr (types.listOf types.str));
        };
        "version" = mkOption {
          description = "Version is the Garage version on this node";
          type = (types.nullOr types.str);
        };
        "zone" = mkOption {
          description = "Zone is the layout zone actually assigned to this node. Equal to\nspec.zone unless spec.zoneFrom resolved a different value from the\nKubernetes Node the pod is scheduled to.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "address" = mkOverride 1002 null;
        "blockErrors" = mkOverride 1002 null;
        "clusterAdminEndpoint" = mkOverride 1002 null;
        "clusterAdminTokenSecretRef" = mkOverride 1002 null;
        "conditions" = mkOverride 1002 null;
        "connected" = mkOverride 1002 null;
        "cyclePhase" = mkOverride 1002 null;
        "cycleSiblingName" = mkOverride 1002 null;
        "cycleSiblingNodeId" = mkOverride 1002 null;
        "dataPartition" = mkOverride 1002 null;
        "dbEngine" = mkOverride 1002 null;
        "garageFeatures" = mkOverride 1002 null;
        "hostname" = mkOverride 1002 null;
        "inLayout" = mkOverride 1002 null;
        "lastSeen" = mkOverride 1002 null;
        "layoutVersion" = mkOverride 1002 null;
        "managedPVCs" = mkOverride 1002 null;
        "metadataPartition" = mkOverride 1002 null;
        "nodeId" = mkOverride 1002 null;
        "observedGeneration" = mkOverride 1002 null;
        "observedPodUid" = mkOverride 1002 null;
        "parentDeletionRequestGeneration" = mkOverride 1002 null;
        "partitions" = mkOverride 1002 null;
        "phase" = mkOverride 1002 null;
        "repairInProgress" = mkOverride 1002 null;
        "repairProgress" = mkOverride 1002 null;
        "repairType" = mkOverride 1002 null;
        "storedData" = mkOverride 1002 null;
        "tags" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
        "zone" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeStatusClusterAdminTokenSecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeStatusConditions" = {

      options = {
        "lastTransitionTime" = mkOption {
          description = "lastTransitionTime is the last time the condition transitioned from one status to another.\nThis should be when the underlying condition changed.  If that is not known, then using the time when the API field changed is acceptable.";
          type = types.str;
        };
        "message" = mkOption {
          description = "message is a human readable message indicating details about the transition.\nThis may be an empty string.";
          type = (types.withMaxLength 32768 types.str);
        };
        "observedGeneration" = mkOption {
          description = "observedGeneration represents the .metadata.generation that the condition was set based upon.\nFor instance, if .metadata.generation is currently 12, but the .status.conditions[x].observedGeneration is 9, the condition is out of date\nwith respect to the current state of the instance.";
          type = (types.nullOr (types.withMinimum 0 types.int));
        };
        "reason" = mkOption {
          description = "reason contains a programmatic identifier indicating the reason for the condition's last transition.\nProducers of specific condition types may define expected values and meanings for this field,\nand whether the values are considered a guaranteed API.\nThe value should be a CamelCase string.\nThis field may not be empty.";
          type = (types.withMaxLength 1024 (types.withMinLength 1 types.str));
        };
        "status" = mkOption {
          description = "status of the condition, one of True, False, Unknown.";
          type = (
            types.enum [
              "True"
              "False"
              "Unknown"
            ]
          );
        };
        "type" = mkOption {
          description = "type of condition in CamelCase or in foo.example.com/CamelCase.";
          type = (types.withMaxLength 316 types.str);
        };
      };

      config = {
        "observedGeneration" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeStatusDataPartition" = {

      options = {
        "available" = mkOption {
          description = "Available is the available disk space";
          type = (types.nullOr (types.either types.int types.str));
        };
        "total" = mkOption {
          description = "Total is the total disk space";
          type = (types.nullOr (types.either types.int types.str));
        };
        "usedPercent" = mkOption {
          description = "UsedPercent is the percentage of disk space used (0-100)";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "available" = mkOverride 1002 null;
        "total" = mkOverride 1002 null;
        "usedPercent" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeStatusManagedPVCs" = {

      options = {
        "name" = mkOption {
          description = "Name is the exact PersistentVolumeClaim name.";
          type = types.str;
        };
        "pendingReservationHash" = mkOption {
          description = "PendingReservationHash is a SHA-256 commitment to a cryptographically\nrandom nonce stamped on a PVC before its UID can be observed. It closes\nthe create/status-update crash window without making the public status\nvalue sufficient to forge a controller reservation.\nExactly one of UID and PendingReservationHash is set.";
          type = (types.nullOr types.str);
        };
        "uid" = mkOption {
          description = "UID is the immutable API-server identity observed when the claim was\ncreated or safely migrated.\nExactly one of UID and PendingReservationHash is set.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "pendingReservationHash" = mkOverride 1002 null;
        "uid" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageNodeStatusMetadataPartition" = {

      options = {
        "available" = mkOption {
          description = "Available is the available disk space";
          type = (types.nullOr (types.either types.int types.str));
        };
        "total" = mkOption {
          description = "Total is the total disk space";
          type = (types.nullOr (types.either types.int types.str));
        };
        "usedPercent" = mkOption {
          description = "UsedPercent is the percentage of disk space used (0-100)";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "available" = mkOverride 1002 null;
        "total" = mkOverride 1002 null;
        "usedPercent" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageReferenceGrant" = {

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
          description = "GarageReferenceGrantSpec defines which namespaces and resource kinds are\npermitted to make cross-namespace references to resources in this namespace.";
          type = (submoduleOf "garage.rajsingh.info.v1beta1.GarageReferenceGrantSpec");
        };
        "status" = mkOption {
          description = "GarageReferenceGrantStatus reflects which resources are currently using this grant.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta1.GarageReferenceGrantStatus"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageReferenceGrantSpec" = {

      options = {
        "from" = mkOption {
          description = "From lists the permitted sources of cross-namespace references.";
          type = (types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageReferenceGrantSpecFrom"));
        };
        "to" = mkOption {
          description = "To lists the target resource kinds (and optionally specific names) that\nmay be referenced. If omitted, all GarageCluster and GarageBucket resources\nin this namespace are accessible. This preserves the original grant\nbehavior; newer target kinds such as GarageKey require an explicit entry.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1beta1.GarageReferenceGrantSpecTo" "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
      };

      config = {
        "to" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageReferenceGrantSpecFrom" = {

      options = {
        "kind" = mkOption {
          description = "Kind is the resource kind allowed to make cross-namespace references.\nGarageAdminToken remains in the schema for compatibility, but the static\ncredential path is namespace-local and does not accept cross-namespace grants.";
          type = (
            types.enum [
              "GarageKey"
              "GarageBucket"
              "GarageAdminToken"
            ]
          );
        };
        "namespace" = mkOption {
          description = "Namespace is the exact namespace from which cross-namespace references are\nallowed. Exactly one of Namespace or NamespaceSelector must be set.";
          type = (types.nullOr (types.withMinLength 1 types.str));
        };
        "namespaceSelector" = mkOption {
          description = "NamespaceSelector selects source namespaces by their Kubernetes labels.\nExactly one of Namespace or NamespaceSelector must be set. An empty\nselector matches every namespace.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta1.GarageReferenceGrantSpecFromNamespaceSelector"
            )
          );
        };
      };

      config = {
        "namespace" = mkOverride 1002 null;
        "namespaceSelector" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageReferenceGrantSpecFromNamespaceSelector" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta1.GarageReferenceGrantSpecFromNamespaceSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta1.GarageReferenceGrantSpecFromNamespaceSelectorMatchExpressions" = {

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
    "garage.rajsingh.info.v1beta1.GarageReferenceGrantSpecTo" = {

      options = {
        "kind" = mkOption {
          description = "Kind is the target resource kind.";
          type = (
            types.enum [
              "GarageCluster"
              "GarageBucket"
              "GarageKey"
            ]
          );
        };
        "name" = mkOption {
          description = "Name restricts access to a specific resource. If omitted, all resources of\nthe given kind in this namespace are accessible.";
          type = (types.nullOr (types.withMinLength 1 types.str));
        };
      };

      config = {
        "name" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageReferenceGrantStatus" = {

      options = {
        "conditions" = mkOption {
          description = "Conditions represent the current state.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta1.GarageReferenceGrantStatusConditions")
            )
          );
        };
        "inUseBy" = mkOption {
          description = "InUseBy lists resources currently referencing through this grant.\nRebuilt on every reconcile — safe to delete when this is empty.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1beta1.GarageReferenceGrantStatusInUseBy"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
      };

      config = {
        "conditions" = mkOverride 1002 null;
        "inUseBy" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageReferenceGrantStatusConditions" = {

      options = {
        "lastTransitionTime" = mkOption {
          description = "lastTransitionTime is the last time the condition transitioned from one status to another.\nThis should be when the underlying condition changed.  If that is not known, then using the time when the API field changed is acceptable.";
          type = types.str;
        };
        "message" = mkOption {
          description = "message is a human readable message indicating details about the transition.\nThis may be an empty string.";
          type = (types.withMaxLength 32768 types.str);
        };
        "observedGeneration" = mkOption {
          description = "observedGeneration represents the .metadata.generation that the condition was set based upon.\nFor instance, if .metadata.generation is currently 12, but the .status.conditions[x].observedGeneration is 9, the condition is out of date\nwith respect to the current state of the instance.";
          type = (types.nullOr (types.withMinimum 0 types.int));
        };
        "reason" = mkOption {
          description = "reason contains a programmatic identifier indicating the reason for the condition's last transition.\nProducers of specific condition types may define expected values and meanings for this field,\nand whether the values are considered a guaranteed API.\nThe value should be a CamelCase string.\nThis field may not be empty.";
          type = (types.withMaxLength 1024 (types.withMinLength 1 types.str));
        };
        "status" = mkOption {
          description = "status of the condition, one of True, False, Unknown.";
          type = (
            types.enum [
              "True"
              "False"
              "Unknown"
            ]
          );
        };
        "type" = mkOption {
          description = "type of condition in CamelCase or in foo.example.com/CamelCase.";
          type = (types.withMaxLength 316 types.str);
        };
      };

      config = {
        "observedGeneration" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta1.GarageReferenceGrantStatusInUseBy" = {

      options = {
        "kind" = mkOption {
          description = "Kind of the referencing resource.";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "Name of the referencing resource.";
          type = (types.nullOr types.str);
        };
        "namespace" = mkOption {
          description = "Namespace of the referencing resource.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "kind" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageCluster" = {

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
          description = "GarageClusterSpec defines the desired state of a GarageCluster.\n\nA cluster has two optional tiers:\n\n  - `storage` — long-lived storage. Its optional default group uses\n    StatefulSet/PVC nodes; nodeLocalPools add selector-driven HostPath nodes.\n  - `gateway` — routes S3/Admin traffic and stores no object blocks. Auto\n    unified clusters generate one GarageNode-owned StatefulSet per gateway\n    identity; Manual unified clusters use ordinary user-owned GarageNodes.\n    Edge clusters use one cluster-level StatefulSet. Metadata uses a small PVC\n    by default and data uses EmptyDir. Explicit EmptyDir metadata gives up\n    identity persistence and is warned at admission.\n\nSupported topology shapes are deliberately disjoint:\n\n 1. `storage` only (storage cluster).\n 2. `storage` together with `gateway` (unified cluster — most common).\n 3. `gateway` together with `connectTo` (edge gateway — pods live separately\n    from the storage backend).\n 4. `connectTo` only (management handle; no workloads).\n\n`storage` and `connectTo` are mutually exclusive. Joining independently\nmanaged storage sites is expressed with remoteClusters, not connectTo.";
          type = (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpec");
        };
        "status" = mkOption {
          description = "GarageClusterStatus defines the observed state of GarageCluster.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatus"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpec" = {

      options = {
        "admin" = mkOption {
          description = "Admin configures the admin API endpoint and metrics";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecAdmin"));
        };
        "blocks" = mkOption {
          description = "Blocks configures block storage settings";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecBlocks"));
        };
        "connectTo" = mkOption {
          description = "ConnectTo specifies a remote storage cluster this cluster connects to.\nRequired when `gateway` is set without `storage` (edge gateway pattern).";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecConnectTo"));
        };
        "database" = mkOption {
          description = "Database configures the metadata database engine";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecDatabase"));
        };
        "defaultNodeTags" = mkOption {
          description = "DefaultNodeTags are tags applied to all auto-managed nodes.\nOnly used when LayoutPolicy is \"Auto\".";
          type = (types.nullOr (types.listOf types.str));
        };
        "deletionPolicy" = mkOption {
          description = "DeletionPolicy controls deletion-time Garage layout handling.\nDestroy is whole-store teardown and does not attempt Garage's invalid\nempty-layout transition. Drain retires one federated site and\nblocks deletion until its roles migrate to surviving replicas and layout\nhistory settles. HostPath data is never deleted; PVC cleanup remains\ncontrolled by storage.pvcRetentionPolicy. When omitted, standalone clusters\nretain legacy Destroy behavior. Federated deletion is refused until this is\nset explicitly; if admission is bypassed, the controller fails closed as Drain.";
          type = (
            types.nullOr (
              types.enum [
                "Destroy"
                "Drain"
              ]
            )
          );
        };
        "discovery" = mkOption {
          description = "Discovery configures peer discovery mechanisms";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecDiscovery"));
        };
        "gateway" = mkOption {
          description = "Gateway configures the gateway tier. Auto unified clusters generate one\nGarageNode-owned StatefulSet per replica; Manual unified clusters use\nordinary user-owned GarageNodes. Edge clusters use one cluster-level\nStatefulSet. Gateway pods store no object blocks. Metadata uses a small PVC\nby default to persist identity across restarts; callers may explicitly\nchoose EmptyDir metadata and accept identity churn.\nMay be combined with `storage` (unified cluster) or `connectTo` (edge\ncluster), but never both.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGateway"));
        };
        "image" = mkOption {
          description = "Image specifies the Garage container image to use.\nTakes precedence over imageRepository if both are set.";
          type = (types.nullOr types.str);
        };
        "imagePullPolicy" = mkOption {
          description = "ImagePullPolicy specifies the image pull policy";
          type = (types.nullOr types.str);
        };
        "imagePullSecrets" = mkOption {
          description = "ImagePullSecrets specifies secrets for pulling images from private registries";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1beta2.GarageClusterSpecImagePullSecrets"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "imageRepository" = mkOption {
          description = "ImageRepository overrides just the repository portion of the default Garage image,\npreserving the default tag for automatic version upgrades.\nIgnored if image is set.";
          type = (types.nullOr types.str);
        };
        "k2vApi" = mkOption {
          description = "K2VAPI configures the K2V (key-value) API endpoint.\nOmit to disable K2V.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecK2vApi"));
        };
        "layoutManagement" = mkOption {
          description = "LayoutManagement controls automatic layout application behavior.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecLayoutManagement")
          );
        };
        "layoutPolicy" = mkOption {
          description = "LayoutPolicy controls whether node layouts are automatically managed or manually configured.";
          type = (
            types.nullOr (
              types.enum [
                "Auto"
                "Manual"
              ]
            )
          );
        };
        "logging" = mkOption {
          description = "Logging configures logging behavior for Garage nodes";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecLogging"));
        };
        "maintenance" = mkOption {
          description = "Maintenance configures maintenance mode for this cluster.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecMaintenance"));
        };
        "monitoring" = mkOption {
          description = "Monitoring configures Prometheus integration for this cluster.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecMonitoring"));
        };
        "network" = mkOption {
          description = "Network configures RPC and API networking";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecNetwork"));
        };
        "publicEndpoint" = mkOption {
          description = "PublicEndpoint configures how remote clusters reach this cluster's nodes.\nUsed for multi-cluster federation of the storage tier.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecPublicEndpoint"));
        };
        "remoteClusters" = mkOption {
          description = "RemoteClusters lists Garage clusters in other Kubernetes clusters to federate with.\nApplies to the storage tier. Gateways inherit reachability via the local storage peer.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1beta2.GarageClusterSpecRemoteClusters"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "replication" = mkOption {
          description = "Replication configures data replication settings.\nIf omitted, defaults to factor: 3 and consistencyMode: consistent.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecReplication"));
        };
        "s3Api" = mkOption {
          description = "S3API configures the S3-compatible API endpoint";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecS3Api"));
        };
        "security" = mkOption {
          description = "Security configures security-related settings";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecSecurity"));
        };
        "serviceAccountName" = mkOption {
          description = "ServiceAccountName for Garage pods (shared by both tiers).";
          type = (types.nullOr types.str);
        };
        "storage" = mkOption {
          description = "Storage configures the long-lived storage tier. The existing replicas,\nmetadata, and data fields describe the default operator-managed\nStatefulSet/PVC member group. NodeLocalPools adds independently configured\nnode-local HostPath member sets that may coexist with that group or with\nordinary user-managed GarageNodes.\nOmit for gateway-only edge clusters.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorage"));
        };
        "webApi" = mkOption {
          description = "WebAPI configures the static website hosting endpoint.\nEnabled by default with rootDomain \".<name>.<namespace>.svc\".\nSet webApi.enabled: false to turn off.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecWebApi"));
        };
        "workers" = mkOption {
          description = "Workers configures Garage background worker behavior.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecWorkers"));
        };
        "zone" = mkOption {
          description = "Zone is the static Garage layout zone used by members of this cluster and\nthe fallback before a ZoneFrom Pod is scheduled or when its readable\nKubernetes Node does not carry the configured label.\nWhen ZoneFrom is configured, one workload-owning cluster may contain roles\nin multiple actual Garage failure-domain zones.";
          type = (types.nullOr types.str);
        };
        "zoneFrom" = mkOption {
          description = "ZoneFrom derives each storage node's layout zone from a label on the\nKubernetes Node its pod is scheduled to, instead of using the single\ncluster-wide Zone above. This lets one cluster express failure domains\ninternally (racks, power circuits, switches) so replication.zoneRedundancy\nhas something to act on without splitting into a federation.\n\nApplies to operator-managed storage nodes only, including both default\nStatefulSet nodes and node-local-pool nodes. Zone remains the fallback\nwhen the label is missing or the pod is not scheduled yet. If the operator\ncannot read the required Kubernetes Node, reconciliation fails closed; it\ndoes not silently substitute Zone. Cluster-scoped installation is required.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecZoneFrom"));
        };
      };

      config = {
        "admin" = mkOverride 1002 null;
        "blocks" = mkOverride 1002 null;
        "connectTo" = mkOverride 1002 null;
        "database" = mkOverride 1002 null;
        "defaultNodeTags" = mkOverride 1002 null;
        "deletionPolicy" = mkOverride 1002 null;
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
        "maintenance" = mkOverride 1002 null;
        "monitoring" = mkOverride 1002 null;
        "network" = mkOverride 1002 null;
        "publicEndpoint" = mkOverride 1002 null;
        "remoteClusters" = mkOverride 1002 null;
        "replication" = mkOverride 1002 null;
        "s3Api" = mkOverride 1002 null;
        "security" = mkOverride 1002 null;
        "serviceAccountName" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "webApi" = mkOverride 1002 null;
        "workers" = mkOverride 1002 null;
        "zone" = mkOverride 1002 null;
        "zoneFrom" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecAdmin" = {

      options = {
        "adminTokenSecretRef" = mkOption {
          description = "AdminTokenSecretRef references the secret used by the operator to authenticate\nwith Garage's Admin API.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecAdminAdminTokenSecretRef")
          );
        };
        "bindAddress" = mkOption {
          description = "BindAddress is a custom wildcard TCP bind address for the Admin API.\nManaged workloads accept \"0.0.0.0:3903\" or \"[::]:3903\". Unix sockets,\nempty hosts, loopback, and specific hosts are rejected\nbecause Services and direct Pod probes must reach every Garage process.\nIf set, its port overrides BindPort for all generated endpoints. The\neffective Admin API TCP port is immutable after GarageCluster creation.";
          type = (types.nullOr types.str);
        };
        "bindPort" = mkOption {
          description = "BindPort is the port to bind for admin API. The effective Admin API TCP\nport is immutable after the GarageCluster is created.";
          type = (types.nullOr (types.withMaximum 65535 (types.withMinimum 1 types.int)));
        };
        "metricsRequireToken" = mkOption {
          description = "MetricsRequireToken requires Bearer token authentication for the /metrics endpoint.";
          type = (types.nullOr types.bool);
        };
        "metricsTokenSecretRef" = mkOption {
          description = "MetricsTokenSecretRef references a secret containing a token that protects /metrics.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecAdminMetricsTokenSecretRef"
            )
          );
        };
        "traceSink" = mkOption {
          description = "TraceSink is the OpenTelemetry collector address for tracing.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "adminTokenSecretRef" = mkOverride 1002 null;
        "bindAddress" = mkOverride 1002 null;
        "bindPort" = mkOverride 1002 null;
        "metricsRequireToken" = mkOverride 1002 null;
        "metricsTokenSecretRef" = mkOverride 1002 null;
        "traceSink" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecAdminAdminTokenSecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecAdminMetricsTokenSecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecBlocks" = {

      options = {
        "compressionLevel" = mkOption {
          description = "CompressionLevel is the zstd compression level.";
          type = (types.nullOr types.str);
        };
        "disableScrub" = mkOption {
          description = "DisableScrub disables automatic monthly data directory scrub.";
          type = (types.nullOr types.bool);
        };
        "maxConcurrentReads" = mkOption {
          description = "MaxConcurrentReads is the maximum simultaneous block file reads.";
          type = (types.nullOr (types.withMinimum 1 types.int));
        };
        "maxConcurrentWritesPerRequest" = mkOption {
          description = "MaxConcurrentWritesPerRequest is the maximum parallel block writes per PUT request.";
          type = (types.nullOr (types.withMinimum 1 types.int));
        };
        "ramBufferMax" = mkOption {
          description = "RAMBufferMax is the maximum RAM for buffering blocks.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "size" = mkOption {
          description = "Size is the size of data blocks (default: 1M).";
          type = (types.nullOr (types.either types.int types.str));
        };
        "useLocalTZ" = mkOption {
          description = "UseLocalTZ runs lifecycle worker at midnight in local timezone.";
          type = (types.nullOr types.bool);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecConnectTo" = {

      options = {
        "adminApiEndpoint" = mkOption {
          description = "AdminAPIEndpoint is the storage cluster's Admin API URL.";
          type = (types.nullOr types.str);
        };
        "adminTokenSecretRef" = mkOption {
          description = "AdminTokenSecretRef references the storage cluster's admin token.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecConnectToAdminTokenSecretRef"
            )
          );
        };
        "bootstrapPeers" = mkOption {
          description = "BootstrapPeers are initial peers for cluster formation.";
          type = (types.nullOr (types.listOf types.str));
        };
        "clusterRef" = mkOption {
          description = "ClusterRef references a GarageCluster in the same namespace.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecConnectToClusterRef")
          );
        };
        "rpcSecretRef" = mkOption {
          description = "RPCSecretRef references a secret containing the shared RPC secret.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecConnectToRpcSecretRef")
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecConnectToAdminTokenSecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecConnectToClusterRef" = {

      options = {
        "kubeConfigSecretRef" = mkOption {
          description = "KubeConfigSecretRef is reserved for a future remote Kubernetes client integration.\nIt is currently rejected by admission because the operator does not use it.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecConnectToClusterRefKubeConfigSecretRef"
            )
          );
        };
        "name" = mkOption {
          description = "Name of the GarageCluster resource.";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "Namespace of the GarageCluster. Defaults to the referencing resource's namespace.\nCross-namespace references require a GarageReferenceGrant in the target namespace.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "kubeConfigSecretRef" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecConnectToClusterRefKubeConfigSecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecConnectToRpcSecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecDatabase" = {

      options = {
        "engine" = mkOption {
          description = "Engine specifies the database engine to use.";
          type = (
            types.nullOr (
              types.enum [
                "lmdb"
                "sqlite"
                "fjall"
              ]
            )
          );
        };
        "fjallBlockCacheSize" = mkOption {
          description = "FjallBlockCacheSize is the block cache size for Fjall.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "lmdbMapSize" = mkOption {
          description = "LMDBMapSize is the virtual memory region size for LMDB.";
          type = (types.nullOr (types.either types.int types.str));
        };
      };

      config = {
        "engine" = mkOverride 1002 null;
        "fjallBlockCacheSize" = mkOverride 1002 null;
        "lmdbMapSize" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecDiscovery" = {

      options = {
        "consul" = mkOption {
          description = "Consul configures Consul-based peer discovery.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecDiscoveryConsul"));
        };
        "kubernetes" = mkOption {
          description = "Kubernetes configures Kubernetes-based peer discovery.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecDiscoveryKubernetes")
          );
        };
      };

      config = {
        "consul" = mkOverride 1002 null;
        "kubernetes" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecDiscoveryConsul" = {

      options = {
        "api" = mkOption {
          description = "API specifies the service registration API.";
          type = (
            types.nullOr (
              types.enum [
                "catalog"
                "agent"
              ]
            )
          );
        };
        "caCert" = mkOption {
          description = "CACert is the CA certificate for TLS connection.";
          type = (types.nullOr types.str);
        };
        "caCertSecretRef" = mkOption {
          description = "CACertSecretRef references a secret containing the CA certificate.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecDiscoveryConsulCaCertSecretRef"
            )
          );
        };
        "clientCertSecretRef" = mkOption {
          description = "ClientCertSecretRef references a secret containing client TLS cert.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecDiscoveryConsulClientCertSecretRef"
            )
          );
        };
        "clientKeySecretRef" = mkOption {
          description = "ClientKeySecretRef references a secret containing client TLS key.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecDiscoveryConsulClientKeySecretRef"
            )
          );
        };
        "datacenters" = mkOption {
          description = "Datacenters for WAN federation.";
          type = (types.nullOr (types.listOf types.str));
        };
        "enabled" = mkOption {
          description = "Enabled enables Consul-based discovery.";
          type = (types.nullOr types.bool);
        };
        "httpAddr" = mkOption {
          description = "HTTPAddr is the full HTTP(S) address of Consul server.";
          type = (types.nullOr types.str);
        };
        "meta" = mkOption {
          description = "Meta is service metadata key-value pairs.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "serviceName" = mkOption {
          description = "ServiceName for Garage RPC port registration.";
          type = (types.nullOr types.str);
        };
        "tags" = mkOption {
          description = "Tags are additional service tags.";
          type = (types.nullOr (types.listOf types.str));
        };
        "tlsSkipVerify" = mkOption {
          description = "TLSSkipVerify skips TLS hostname verification.";
          type = (types.nullOr types.bool);
        };
        "tokenSecretRef" = mkOption {
          description = "TokenSecretRef references a secret containing the bearer token.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecDiscoveryConsulTokenSecretRef"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecDiscoveryConsulCaCertSecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecDiscoveryConsulClientCertSecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecDiscoveryConsulClientKeySecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecDiscoveryConsulTokenSecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecDiscoveryKubernetes" = {

      options = {
        "enabled" = mkOption {
          description = "Enabled enables Kubernetes-based discovery.";
          type = (types.nullOr types.bool);
        };
        "namespace" = mkOption {
          description = "Namespace for Garage custom resources.";
          type = (types.nullOr types.str);
        };
        "serviceName" = mkOption {
          description = "ServiceName label to filter custom resources.";
          type = (types.nullOr types.str);
        };
        "skipCRD" = mkOption {
          description = "SkipCRD skips automatic CRD creation/patching.";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "enabled" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "serviceName" = mkOverride 1002 null;
        "skipCRD" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGateway" = {

      options = {
        "affinity" = mkOption {
          description = "Affinity for pod scheduling.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinity"));
        };
        "containerSecurityContext" = mkOption {
          description = "ContainerSecurityContext for the Garage container.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayContainerSecurityContext"
            )
          );
        };
        "env" = mkOption {
          description = "Env is a list of additional environment variables to set on the Garage\ncontainer. Garage config-path and RPC/Admin/metrics credential variables are\noperator-reserved. Typical use: setting GARAGE_ALLOW_WORLD_READABLE_SECRETS\nor another non-identity Garage startup option.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnv" "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "envFrom" = mkOption {
          description = "EnvFrom is a list of sources to populate environment variables in the\nGarage container. A source prefix must not be capable of injecting an\noperator-reserved Garage variable. Sources are evaluated before the\nper-variable Env list, matching Kubernetes container semantics.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnvFrom")
            )
          );
        };
        "metadata" = mkOption {
          description = "Metadata configures gateway metadata storage for Auto unified gateways and\nedge gateways. It defaults to a 1Gi PVC; type EmptyDir explicitly gives up\nidentity persistence. Manual unified gateways are user-owned GarageNodes,\nso this cluster-level field is rejected there. Paths and\nvolumeClaimTemplateSpec is unsupported. Selector applies to newly created\nclaims in both unified and edge gateway workloads. Change an edge gateway's\nmetadata configuration only after scaling gateway replicas to zero and\nwaiting for its capacity-less roles to retire. Data always stays EmptyDir\nbecause gateways do not store object blocks.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadata"));
        };
        "nodeSelector" = mkOption {
          description = "NodeSelector for pod scheduling.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "podAnnotations" = mkOption {
          description = "PodAnnotations to add to pods.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "podDisruptionBudget" = mkOption {
          description = "PodDisruptionBudget configures a PDB for the gateway workloads. Gateway\npods serve S3/Admin traffic but hold no object data, so a PDB only\nprotects request availability during node drains — not data durability.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayPodDisruptionBudget"
            )
          );
        };
        "podLabels" = mkOption {
          description = "PodLabels to add to pods.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "priorityClassName" = mkOption {
          description = "PriorityClassName for pods.";
          type = (types.nullOr types.str);
        };
        "pvcRetentionPolicy" = mkOption {
          description = "PVCRetentionPolicy controls gateway metadata PVC lifecycle. It preserves\nthe released v1beta1 gateway storage.pvcRetentionPolicy contract. When\nomitted, edge gateway StatefulSets keep their established Delete/Delete\nbehavior, while per-GarageNode unified gateway StatefulSets keep\nKubernetes' safer Retain/Retain default. An explicit value applies to both\nmanaged gateway shapes.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayPvcRetentionPolicy")
          );
        };
        "readinessProbe" = mkOption {
          description = "ReadinessProbe overrides the gateway tier's readiness probe. When unset,\nthe operator uses a bind-only TCP check on the S3 port. The default is\ndeliberately NOT a serving-aware admin /health probe: /health is a\ncluster-wide consistent write-quorum signal, so at replication.factor=2 a\nsingle storage-node loss (or, for a federated cluster, the window before\nremote peers join) makes /health return 503 on every node, which would mark\nall gateways NotReady and — behind a publishNotReadyAddresses=false Service\nsuch as the Tailscale anycast — withdraw the whole anycast and take down\nreads too, even though read_quorum=1 means reads still work. Serving-health\nbelongs in monitoring (alert on /health), not readiness. Set this only if\nyou have a custom read-capability gate (e.g. an exec probe) that won't\nwithdraw a gateway that can still serve reads.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayReadinessProbe")
          );
        };
        "replicas" = mkOption {
          description = "Replicas controls generated gateway identities in an Auto unified cluster,\nor the cluster-level StatefulSet replicas in an edge cluster. Set it to 0\nto retire those operator-managed roles and workloads. It does not control\nordinary user-owned gateway GarageNodes in Manual layout mode.";
          type = (types.withMinimum 0 types.int);
        };
        "resources" = mkOption {
          description = "Resources specifies compute resources for the pod.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayResources")
          );
        };
        "rpcPublicAddr" = mkOption {
          description = "RPCPublicAddr, when set, is written into the gateway pods' garage.toml as\nrpc_public_addr so that peers in other regions can dial gateways by hostname.\nIt is operationally required when federated peers cannot route directly to\neach Pod IP; leave it unset when gateways communicate only with a locally\nroutable storage tier.";
          type = (types.nullOr types.str);
        };
        "securityContext" = mkOption {
          description = "SecurityContext for the pod.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewaySecurityContext")
          );
        };
        "tolerations" = mkOption {
          description = "Tolerations for pod scheduling.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayTolerations")
            )
          );
        };
        "topologySpreadConstraints" = mkOption {
          description = "TopologySpreadConstraints for pod scheduling.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayTopologySpreadConstraints"
              )
            )
          );
        };
      };

      config = {
        "affinity" = mkOverride 1002 null;
        "containerSecurityContext" = mkOverride 1002 null;
        "env" = mkOverride 1002 null;
        "envFrom" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "nodeSelector" = mkOverride 1002 null;
        "podAnnotations" = mkOverride 1002 null;
        "podDisruptionBudget" = mkOverride 1002 null;
        "podLabels" = mkOverride 1002 null;
        "priorityClassName" = mkOverride 1002 null;
        "pvcRetentionPolicy" = mkOverride 1002 null;
        "readinessProbe" = mkOverride 1002 null;
        "resources" = mkOverride 1002 null;
        "rpcPublicAddr" = mkOverride 1002 null;
        "securityContext" = mkOverride 1002 null;
        "tolerations" = mkOverride 1002 null;
        "topologySpreadConstraints" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinity" = {

      options = {
        "nodeAffinity" = mkOption {
          description = "Describes node affinity scheduling rules for the pod.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityNodeAffinity"
            )
          );
        };
        "podAffinity" = mkOption {
          description = "Describes pod affinity scheduling rules (e.g. co-locate this pod in the same node, zone, etc. as some other pod(s)).";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinity"
            )
          );
        };
        "podAntiAffinity" = mkOption {
          description = "Describes pod anti-affinity scheduling rules (e.g. avoid putting this pod in the same node, zone, etc. as some other pod(s)).";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinity"
            )
          );
        };
      };

      config = {
        "nodeAffinity" = mkOverride 1002 null;
        "podAffinity" = mkOverride 1002 null;
        "podAntiAffinity" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityNodeAffinity" = {

      options = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "The scheduler will prefer to schedule pods to nodes that satisfy\nthe affinity expressions specified by this field, but it may choose\na node that violates one or more of the expressions. The node that is\nmost preferred is the one with the greatest sum of weights, i.e.\nfor each node that meets all of the scheduling requirements (resource\nrequest, requiredDuringScheduling affinity expressions, etc.),\ncompute a sum by iterating through the elements of this field and adding\n\"weight\" to the sum if the node matches the corresponding matchExpressions; the\nnode(s) with the highest sum are the most preferred.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "If the affinity requirements specified by this field are not met at\nscheduling time, the pod will not be scheduled onto the node.\nIf the affinity requirements specified by this field cease to be met\nat some point during pod execution (e.g. due to an update), the system\nmay or may not try to eventually evict the pod from its node.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecution"
            )
          );
        };
      };

      config = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "preference" = mkOption {
            description = "A node selector term, associated with the corresponding weight.";
            type = (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreference"
            );
          };
          "weight" = mkOption {
            description = "Weight associated with matching the corresponding nodeSelectorTerm, in the range 1-100.";
            type = types.int;
          };
        };

        config = { };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreference" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "A list of node selector requirements by node's labels.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchExpressions"
                )
              )
            );
          };
          "matchFields" = mkOption {
            description = "A list of node selector requirements by node's fields.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchFields"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchExpressions" =
      {

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
            type = (types.nullOr (types.listOf types.str));
          };
        };

        config = {
          "values" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchFields" =
      {

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
            type = (types.nullOr (types.listOf types.str));
          };
        };

        config = {
          "values" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "nodeSelectorTerms" = mkOption {
            description = "Required. A list of node selector terms. The terms are ORed.";
            type = (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTerms"
              )
            );
          };
        };

        config = { };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTerms" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "A list of node selector requirements by node's labels.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchExpressions"
                )
              )
            );
          };
          "matchFields" = mkOption {
            description = "A list of node selector requirements by node's fields.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchFields"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchExpressions" =
      {

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
            type = (types.nullOr (types.listOf types.str));
          };
        };

        config = {
          "values" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchFields" =
      {

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
            type = (types.nullOr (types.listOf types.str));
          };
        };

        config = {
          "values" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinity" = {

      options = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "The scheduler will prefer to schedule pods to nodes that satisfy\nthe affinity expressions specified by this field, but it may choose\na node that violates one or more of the expressions. The node that is\nmost preferred is the one with the greatest sum of weights, i.e.\nfor each node that meets all of the scheduling requirements (resource\nrequest, requiredDuringScheduling affinity expressions, etc.),\ncompute a sum by iterating through the elements of this field and adding\n\"weight\" to the sum if the node has pods which matches the corresponding podAffinityTerm; the\nnode(s) with the highest sum are the most preferred.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "If the affinity requirements specified by this field are not met at\nscheduling time, the pod will not be scheduled onto the node.\nIf the affinity requirements specified by this field cease to be met\nat some point during pod execution (e.g. due to a pod label update), the\nsystem may or may not try to eventually evict the pod from its node.\nWhen there are multiple elements, the lists of nodes corresponding to each\npodAffinityTerm are intersected, i.e. all terms must be satisfied.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecution"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "podAffinityTerm" = mkOption {
            description = "Required. A pod affinity term, associated with the corresponding weight.";
            type = (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm"
            );
          };
          "weight" = mkOption {
            description = "weight associated with matching the corresponding podAffinityTerm,\nin the range 1-100.";
            type = types.int;
          };
        };

        config = { };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector"
              )
            );
          };
          "matchLabelKeys" = mkOption {
            description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "mismatchLabelKeys" = mkOption {
            description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "namespaceSelector" = mkOption {
            description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector"
              )
            );
          };
          "namespaces" = mkOption {
            description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
            type = (types.nullOr (types.listOf types.str));
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector"
              )
            );
          };
          "matchLabelKeys" = mkOption {
            description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "mismatchLabelKeys" = mkOption {
            description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "namespaceSelector" = mkOption {
            description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector"
              )
            );
          };
          "namespaces" = mkOption {
            description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
            type = (types.nullOr (types.listOf types.str));
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinity" = {

      options = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "The scheduler will prefer to schedule pods to nodes that satisfy\nthe anti-affinity expressions specified by this field, but it may choose\na node that violates one or more of the expressions. The node that is\nmost preferred is the one with the greatest sum of weights, i.e.\nfor each node that meets all of the scheduling requirements (resource\nrequest, requiredDuringScheduling anti-affinity expressions, etc.),\ncompute a sum by iterating through the elements of this field and subtracting\n\"weight\" from the sum if the node has pods which matches the corresponding podAffinityTerm; the\nnode(s) with the highest sum are the most preferred.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "If the anti-affinity requirements specified by this field are not met at\nscheduling time, the pod will not be scheduled onto the node.\nIf the anti-affinity requirements specified by this field cease to be met\nat some point during pod execution (e.g. due to a pod label update), the\nsystem may or may not try to eventually evict the pod from its node.\nWhen there are multiple elements, the lists of nodes corresponding to each\npodAffinityTerm are intersected, i.e. all terms must be satisfied.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecution"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "podAffinityTerm" = mkOption {
            description = "Required. A pod affinity term, associated with the corresponding weight.";
            type = (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm"
            );
          };
          "weight" = mkOption {
            description = "weight associated with matching the corresponding podAffinityTerm,\nin the range 1-100.";
            type = types.int;
          };
        };

        config = { };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector"
              )
            );
          };
          "matchLabelKeys" = mkOption {
            description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "mismatchLabelKeys" = mkOption {
            description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "namespaceSelector" = mkOption {
            description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector"
              )
            );
          };
          "namespaces" = mkOption {
            description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
            type = (types.nullOr (types.listOf types.str));
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector"
              )
            );
          };
          "matchLabelKeys" = mkOption {
            description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "mismatchLabelKeys" = mkOption {
            description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "namespaceSelector" = mkOption {
            description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector"
              )
            );
          };
          "namespaces" = mkOption {
            description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
            type = (types.nullOr (types.listOf types.str));
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayContainerSecurityContext" = {

      options = {
        "allowPrivilegeEscalation" = mkOption {
          description = "AllowPrivilegeEscalation controls whether a process can gain more\nprivileges than its parent process. This bool directly controls if\nthe no_new_privs flag will be set on the container process.\nAllowPrivilegeEscalation is true always when the container is:\n1) run as Privileged\n2) has CAP_SYS_ADMIN\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.bool);
        };
        "appArmorProfile" = mkOption {
          description = "appArmorProfile is the AppArmor options to use by this container. If set, this profile\noverrides the pod's appArmorProfile.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayContainerSecurityContextAppArmorProfile"
            )
          );
        };
        "capabilities" = mkOption {
          description = "The capabilities to add/drop when running containers.\nDefaults to the default set of capabilities granted by the container runtime.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayContainerSecurityContextCapabilities"
            )
          );
        };
        "privileged" = mkOption {
          description = "Run container in privileged mode.\nProcesses in privileged containers are essentially equivalent to root on the host.\nDefaults to false.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.bool);
        };
        "procMount" = mkOption {
          description = "procMount denotes the type of proc mount to use for the containers.\nThe default value is Default which uses the container runtime defaults for\nreadonly paths and masked paths.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.str);
        };
        "readOnlyRootFilesystem" = mkOption {
          description = "Whether this container has a read-only root filesystem.\nDefault is false.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.bool);
        };
        "runAsGroup" = mkOption {
          description = "The GID to run the entrypoint of the container process.\nUses runtime default if unset.\nMay also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.int);
        };
        "runAsNonRoot" = mkOption {
          description = "Indicates that the container must run as a non-root user.\nIf true, the Kubelet will validate the image at runtime to ensure that it\ndoes not run as UID 0 (root) and fail to start the container if it does.\nIf unset or false, no such validation will be performed.\nMay also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
          type = (types.nullOr types.bool);
        };
        "runAsUser" = mkOption {
          description = "The UID to run the entrypoint of the container process.\nDefaults to user specified in image metadata if unspecified.\nMay also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.int);
        };
        "seLinuxOptions" = mkOption {
          description = "The SELinux context to be applied to the container.\nIf unspecified, the container runtime will allocate a random SELinux context for each\ncontainer.  May also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayContainerSecurityContextSeLinuxOptions"
            )
          );
        };
        "seccompProfile" = mkOption {
          description = "The seccomp options to use by this container. If seccomp options are\nprovided at both the pod & container level, the container options\noverride the pod options.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayContainerSecurityContextSeccompProfile"
            )
          );
        };
        "windowsOptions" = mkOption {
          description = "The Windows specific settings applied to all containers.\nIf unspecified, the options from the PodSecurityContext will be used.\nIf set in both SecurityContext and PodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is linux.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayContainerSecurityContextWindowsOptions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayContainerSecurityContextAppArmorProfile" = {

      options = {
        "localhostProfile" = mkOption {
          description = "localhostProfile indicates a profile loaded on the node that should be used.\nThe profile must be preconfigured on the node to work.\nMust match the loaded name of the profile.\nMust be set if and only if type is \"Localhost\".";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayContainerSecurityContextCapabilities" = {

      options = {
        "add" = mkOption {
          description = "Added capabilities";
          type = (types.nullOr (types.listOf types.str));
        };
        "drop" = mkOption {
          description = "Removed capabilities";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "add" = mkOverride 1002 null;
        "drop" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayContainerSecurityContextSeLinuxOptions" = {

      options = {
        "level" = mkOption {
          description = "Level is SELinux level label that applies to the container.";
          type = (types.nullOr types.str);
        };
        "role" = mkOption {
          description = "Role is a SELinux role label that applies to the container.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is a SELinux type label that applies to the container.";
          type = (types.nullOr types.str);
        };
        "user" = mkOption {
          description = "User is a SELinux user label that applies to the container.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "level" = mkOverride 1002 null;
        "role" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
        "user" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayContainerSecurityContextSeccompProfile" = {

      options = {
        "localhostProfile" = mkOption {
          description = "localhostProfile indicates a profile defined in a file on the node should be used.\nThe profile must be preconfigured on the node to work.\nMust be a descending path, relative to the kubelet's configured seccomp profile location.\nMust be set if type is \"Localhost\". Must NOT be set for any other type.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayContainerSecurityContextWindowsOptions" = {

      options = {
        "gmsaCredentialSpec" = mkOption {
          description = "GMSACredentialSpec is where the GMSA admission webhook\n(https://github.com/kubernetes-sigs/windows-gmsa) inlines the contents of the\nGMSA credential spec named by the GMSACredentialSpecName field.";
          type = (types.nullOr types.str);
        };
        "gmsaCredentialSpecName" = mkOption {
          description = "GMSACredentialSpecName is the name of the GMSA credential spec to use.";
          type = (types.nullOr types.str);
        };
        "hostProcess" = mkOption {
          description = "HostProcess determines if a container should be run as a 'Host Process' container.\nAll of a Pod's containers must have the same effective HostProcess value\n(it is not allowed to have a mix of HostProcess containers and non-HostProcess containers).\nIn addition, if HostProcess is true then HostNetwork must also be set to true.";
          type = (types.nullOr types.bool);
        };
        "runAsUserName" = mkOption {
          description = "The UserName in Windows to run the entrypoint of the container process.\nDefaults to the user specified in image metadata if unspecified.\nMay also be set in PodSecurityContext. If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "gmsaCredentialSpec" = mkOverride 1002 null;
        "gmsaCredentialSpecName" = mkOverride 1002 null;
        "hostProcess" = mkOverride 1002 null;
        "runAsUserName" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnv" = {

      options = {
        "name" = mkOption {
          description = "Name of the environment variable.\nMay consist of any printable ASCII characters except '='.";
          type = types.str;
        };
        "value" = mkOption {
          description = "Variable references $(VAR_NAME) are expanded\nusing the previously defined environment variables in the container and\nany service environment variables. If a variable cannot be resolved,\nthe reference in the input string will be unchanged. Double $$ are reduced\nto a single $, which allows for escaping the $(VAR_NAME) syntax: i.e.\n\"$$(VAR_NAME)\" will produce the string literal \"$(VAR_NAME)\".\nEscaped references will never be expanded, regardless of whether the variable\nexists or not.\nDefaults to \"\".";
          type = (types.nullOr types.str);
        };
        "valueFrom" = mkOption {
          description = "Source for the environment variable's value. Cannot be used if value is not empty.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnvValueFrom")
          );
        };
      };

      config = {
        "value" = mkOverride 1002 null;
        "valueFrom" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnvFrom" = {

      options = {
        "configMapRef" = mkOption {
          description = "The ConfigMap to select from";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnvFromConfigMapRef"
            )
          );
        };
        "prefix" = mkOption {
          description = "Optional text to prepend to the name of each environment variable.\nMay consist of any printable ASCII characters except '='.";
          type = (types.nullOr types.str);
        };
        "secretRef" = mkOption {
          description = "The Secret to select from";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnvFromSecretRef")
          );
        };
      };

      config = {
        "configMapRef" = mkOverride 1002 null;
        "prefix" = mkOverride 1002 null;
        "secretRef" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnvFromConfigMapRef" = {

      options = {
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the ConfigMap must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnvFromSecretRef" = {

      options = {
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnvValueFrom" = {

      options = {
        "configMapKeyRef" = mkOption {
          description = "Selects a key of a ConfigMap.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnvValueFromConfigMapKeyRef"
            )
          );
        };
        "fieldRef" = mkOption {
          description = "Selects a field of the pod: supports metadata.name, metadata.namespace, `metadata.labels['<KEY>']`, `metadata.annotations['<KEY>']`,\nspec.nodeName, spec.serviceAccountName, status.hostIP, status.podIP, status.podIPs.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnvValueFromFieldRef"
            )
          );
        };
        "fileKeyRef" = mkOption {
          description = "FileKeyRef selects a key of the env file.\nRequires the EnvFiles feature gate to be enabled.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnvValueFromFileKeyRef"
            )
          );
        };
        "resourceFieldRef" = mkOption {
          description = "Selects a resource of the container: only resources limits and requests\n(limits.cpu, limits.memory, limits.ephemeral-storage, requests.cpu, requests.memory and requests.ephemeral-storage) are currently supported.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnvValueFromResourceFieldRef"
            )
          );
        };
        "secretKeyRef" = mkOption {
          description = "Selects a key of a secret in the pod's namespace";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnvValueFromSecretKeyRef"
            )
          );
        };
      };

      config = {
        "configMapKeyRef" = mkOverride 1002 null;
        "fieldRef" = mkOverride 1002 null;
        "fileKeyRef" = mkOverride 1002 null;
        "resourceFieldRef" = mkOverride 1002 null;
        "secretKeyRef" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnvValueFromConfigMapKeyRef" = {

      options = {
        "key" = mkOption {
          description = "The key to select from the ConfigMap's Data field.\nKeys in the BinaryData field are not currently propagated to container env vars.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the ConfigMap or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnvValueFromFieldRef" = {

      options = {
        "apiVersion" = mkOption {
          description = "Version of the schema the FieldPath is written in terms of, defaults to \"v1\".";
          type = (types.nullOr types.str);
        };
        "fieldPath" = mkOption {
          description = "Path of the field to select in the specified API version.";
          type = types.str;
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnvValueFromFileKeyRef" = {

      options = {
        "key" = mkOption {
          description = "The key within the env file. An invalid key will prevent the pod from starting.\nThe keys defined within a source may consist of any printable ASCII characters except '='.\nDuring Alpha stage of the EnvFiles feature gate, the key size is limited to 128 characters.";
          type = types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the file or its key must be defined. If the file or key\ndoes not exist, then the env var is not published.\nIf optional is set to true and the specified key does not exist,\nthe environment variable will not be set in the Pod's containers.\n\nIf optional is set to false and the specified key does not exist,\nan error will be returned during Pod creation.";
          type = (types.nullOr types.bool);
        };
        "path" = mkOption {
          description = "The path within the volume from which to select the file.\nMust be relative and may not contain the '..' path or start with '..'.";
          type = types.str;
        };
        "volumeName" = mkOption {
          description = "The name of the volume mount containing the env file.";
          type = types.str;
        };
      };

      config = {
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnvValueFromResourceFieldRef" = {

      options = {
        "containerName" = mkOption {
          description = "Container name: required for volumes, optional for env vars";
          type = (types.nullOr types.str);
        };
        "divisor" = mkOption {
          description = "Specifies the output format of the exposed resources, defaults to \"1\"";
          type = (types.nullOr (types.either types.int types.str));
        };
        "resource" = mkOption {
          description = "Required: resource to select";
          type = types.str;
        };
      };

      config = {
        "containerName" = mkOverride 1002 null;
        "divisor" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayEnvValueFromSecretKeyRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadata" = {

      options = {
        "accessModes" = mkOption {
          description = "AccessModes for the PVC.";
          type = (types.nullOr (types.listOf types.str));
        };
        "annotations" = mkOption {
          description = "Annotations to set on the PVC.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "dataSourceRef" = mkOption {
          description = "DataSourceRef is the opt-in restore source for every generated PVC of this\nvolume role. Setting it copies the same same-namespace, non-core group\npopulator onto each Auto ordinal of this role; the populator must map\ntarget claim i to source-group member i. A core PVC or single-volume clone\nis not a safe source. Metadata and data are independent roles: restore\nidentity by setting this on metadata, object blocks by setting it on data.\nIt is immutable after the GarageCluster is created.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataDataSourceRef"
            )
          );
        };
        "labels" = mkOption {
          description = "Labels to set on the PVC.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "paths" = mkOption {
          description = "Paths configures multiple data directories for multi-disk setups.\nOnly valid for data volumes — webhook rejects this on metadata volumes.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPaths")
            )
          );
        };
        "selector" = mkOption {
          description = "Selector matches pre-provisioned PVs for newly created claims. Kubernetes\ndoes not dynamically provision a PV when this is set; StorageClassName must\nalso match the target PV.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataSelector")
          );
        };
        "size" = mkOption {
          description = "Size of the volume.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "storageClassName" = mkOption {
          description = "StorageClassName for the PVC.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type specifies the volume type: PersistentVolumeClaim (default) or EmptyDir.";
          type = (
            types.nullOr (
              types.enum [
                "PersistentVolumeClaim"
                "EmptyDir"
              ]
            )
          );
        };
        "volumeClaimTemplateSpec" = mkOption {
          description = "VolumeClaimTemplateSpec is retained for API compatibility but is not\nsupported by operator-managed workloads. Admission rejects new or changed\nvalues; an unchanged legacy value is tolerated only so it can be removed.\nArbitrary claim-template dataSource or volumeName settings can clone a\nmetadata node_key or bind multiple Garage identities to one disk. Use the\nexplicit PVC fields above, or pre-provision a PVC and reference it from an\nordinary GarageNode storage existingClaim.\nDeprecated: use explicit PVC fields or GarageNode existingClaim.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataVolumeClaimTemplateSpec"
            )
          );
        };
      };

      config = {
        "accessModes" = mkOverride 1002 null;
        "annotations" = mkOverride 1002 null;
        "dataSourceRef" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "paths" = mkOverride 1002 null;
        "selector" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "storageClassName" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
        "volumeClaimTemplateSpec" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataDataSourceRef" = {

      options = {
        "apiGroup" = mkOption {
          description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
          type = (types.nullOr types.str);
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
          type = (types.nullOr types.str);
        };
      };

      config = {
        "apiGroup" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPaths" = {

      options = {
        "capacity" = mkOption {
          description = "Capacity of the drive (required unless readOnly).";
          type = (types.nullOr (types.either types.int types.str));
        };
        "path" = mkOption {
          description = "Path to the data directory.";
          type = types.str;
        };
        "readOnly" = mkOption {
          description = "ReadOnly marks the directory as a legacy read-only Garage data source for\nmigrations. This controls Garage's block placement; the Kubernetes mount\nremains writable so Garage can maintain its per-directory marker file.";
          type = (types.nullOr types.bool);
        };
        "volume" = mkOption {
          description = "Volume configuration for this data path.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolume"
            )
          );
        };
      };

      config = {
        "capacity" = mkOverride 1002 null;
        "readOnly" = mkOverride 1002 null;
        "volume" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolume" = {

      options = {
        "accessModes" = mkOption {
          description = "AccessModes for the PVC.";
          type = (types.nullOr (types.listOf types.str));
        };
        "annotations" = mkOption {
          description = "Annotations to set on the PVC.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "dataSourceRef" = mkOption {
          description = "DataSourceRef is the opt-in restore source for this data path's PVC across\nevery Auto ordinal. Same group-populator contract as VolumeConfig.dataSourceRef.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolumeDataSourceRef"
            )
          );
        };
        "labels" = mkOption {
          description = "Labels to set on the PVC.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "selector" = mkOption {
          description = "Selector matches pre-provisioned PVs for newly created claims. Kubernetes\ndoes not dynamically provision a PV when this is set; StorageClassName must\nalso match the target PV.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolumeSelector"
            )
          );
        };
        "size" = mkOption {
          description = "Size of the volume (storage request).";
          type = (types.nullOr (types.either types.int types.str));
        };
        "storageClassName" = mkOption {
          description = "StorageClassName for the PVC.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type specifies the volume type.";
          type = (
            types.nullOr (
              types.enum [
                "PersistentVolumeClaim"
                "EmptyDir"
              ]
            )
          );
        };
        "volumeClaimTemplateSpec" = mkOption {
          description = "VolumeClaimTemplateSpec is retained for API compatibility but is not\nsupported by operator-managed workloads. Admission rejects new or changed\nvalues; an unchanged legacy value is tolerated only so it can be removed.\nUse the explicit PVC fields above, or pre-provision a PVC and reference it\nfrom an ordinary GarageNode storage existingClaim.\nDeprecated: use explicit PVC fields or GarageNode existingClaim.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolumeVolumeClaimTemplateSpec"
            )
          );
        };
      };

      config = {
        "accessModes" = mkOverride 1002 null;
        "annotations" = mkOverride 1002 null;
        "dataSourceRef" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "selector" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "storageClassName" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
        "volumeClaimTemplateSpec" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolumeDataSourceRef" = {

      options = {
        "apiGroup" = mkOption {
          description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
          type = (types.nullOr types.str);
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
          type = (types.nullOr types.str);
        };
      };

      config = {
        "apiGroup" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolumeSelector" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolumeSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolumeSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolumeVolumeClaimTemplateSpec" =
      {

        options = {
          "accessModes" = mkOption {
            description = "accessModes contains the desired access modes the volume should have.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#access-modes-1";
            type = (types.nullOr (types.listOf types.str));
          };
          "dataSource" = mkOption {
            description = "dataSource field can be used to specify either:\n* An existing VolumeSnapshot object (snapshot.storage.k8s.io/VolumeSnapshot)\n* An existing PVC (PersistentVolumeClaim)\nIf the provisioner or an external controller can support the specified data source,\nit will create a new volume based on the contents of the specified data source.\ndataSource contents will be copied to dataSourceRef, and dataSourceRef contents will be\ncopied to dataSource when dataSourceRef.namespace is not specified.\nIf the namespace is specified, then dataSourceRef will not be copied to dataSource.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolumeVolumeClaimTemplateSpecDataSource"
              )
            );
          };
          "dataSourceRef" = mkOption {
            description = "dataSourceRef specifies the object from which to populate the volume with data, if a non-empty\nvolume is desired. This may be any object from a non-empty API group (non\ncore object) or a PersistentVolumeClaim object.\nWhen this field is specified, volume binding will only succeed if the type of\nthe specified object matches some installed volume populator or dynamic\nprovisioner.\nThis field will replace the functionality of the dataSource field and as such\nif both fields are non-empty, they must have the same value. For backwards\ncompatibility, when namespace isn't specified in dataSourceRef,\nboth fields (dataSource and dataSourceRef) will be set to the same\nvalue automatically if one of them is empty and the other is non-empty.\nWhen namespace is specified in dataSourceRef,\ndataSource isn't set to the same value and must be empty.\nThere are three important differences between dataSource and dataSourceRef:\n* While dataSource only allows two specific types of objects, dataSourceRef\n  allows any non-core object, as well as PersistentVolumeClaim objects.\n* While dataSource ignores disallowed values (dropping them), dataSourceRef\n  preserves all values, and generates an error if a disallowed value is\n  specified.\n* While dataSource only allows local objects, dataSourceRef allows objects\n  in any namespaces.\n(Alpha) Using the namespace field of dataSourceRef requires the CrossNamespaceVolumeDataSource feature gate to be enabled.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolumeVolumeClaimTemplateSpecDataSourceRef"
              )
            );
          };
          "resources" = mkOption {
            description = "resources represents the minimum resources the volume should have.\nUsers are allowed to specify resource requirements\nthat are lower than previous value but must still be higher than capacity recorded in the\nstatus field of the claim.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#resources";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolumeVolumeClaimTemplateSpecResources"
              )
            );
          };
          "selector" = mkOption {
            description = "selector is a label query over volumes to consider for binding.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolumeVolumeClaimTemplateSpecSelector"
              )
            );
          };
          "storageClassName" = mkOption {
            description = "storageClassName is the name of the StorageClass required by the claim.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#class-1";
            type = (types.nullOr types.str);
          };
          "volumeAttributesClassName" = mkOption {
            description = "volumeAttributesClassName may be used to set the VolumeAttributesClass used by this claim.\nIf specified, the CSI driver will create or update the volume with the attributes defined\nin the corresponding VolumeAttributesClass. This has a different purpose than storageClassName,\nit can be changed after the claim is created. An empty string or nil value indicates that no\nVolumeAttributesClass will be applied to the claim. If the claim enters an Infeasible error state,\nthis field can be reset to its previous value (including nil) to cancel the modification.\nIf the resource referred to by volumeAttributesClass does not exist, this PersistentVolumeClaim will be\nset to a Pending state, as reflected by the modifyVolumeStatus field, until such as a resource\nexists.\nMore info: https://kubernetes.io/docs/concepts/storage/volume-attributes-classes/";
            type = (types.nullOr types.str);
          };
          "volumeMode" = mkOption {
            description = "volumeMode defines what type of volume is required by the claim.\nValue of Filesystem is implied when not included in claim spec.";
            type = (types.nullOr types.str);
          };
          "volumeName" = mkOption {
            description = "volumeName is the binding reference to the PersistentVolume backing this claim.";
            type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolumeVolumeClaimTemplateSpecDataSource" =
      {

        options = {
          "apiGroup" = mkOption {
            description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
            type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolumeVolumeClaimTemplateSpecDataSourceRef" =
      {

        options = {
          "apiGroup" = mkOption {
            description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
            type = (types.nullOr types.str);
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
            type = (types.nullOr types.str);
          };
        };

        config = {
          "apiGroup" = mkOverride 1002 null;
          "namespace" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolumeVolumeClaimTemplateSpecResources" =
      {

        options = {
          "limits" = mkOption {
            description = "Limits describes the maximum amount of compute resources allowed.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
            type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
          };
          "requests" = mkOption {
            description = "Requests describes the minimum amount of compute resources required.\nIf Requests is omitted for a container, it defaults to Limits if that is explicitly specified,\notherwise to an implementation-defined value. Requests cannot exceed Limits.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
            type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
          };
        };

        config = {
          "limits" = mkOverride 1002 null;
          "requests" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolumeVolumeClaimTemplateSpecSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolumeVolumeClaimTemplateSpecSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataPathsVolumeVolumeClaimTemplateSpecSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataSelector" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataSelectorMatchExpressions" = {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataVolumeClaimTemplateSpec" = {

      options = {
        "accessModes" = mkOption {
          description = "accessModes contains the desired access modes the volume should have.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#access-modes-1";
          type = (types.nullOr (types.listOf types.str));
        };
        "dataSource" = mkOption {
          description = "dataSource field can be used to specify either:\n* An existing VolumeSnapshot object (snapshot.storage.k8s.io/VolumeSnapshot)\n* An existing PVC (PersistentVolumeClaim)\nIf the provisioner or an external controller can support the specified data source,\nit will create a new volume based on the contents of the specified data source.\ndataSource contents will be copied to dataSourceRef, and dataSourceRef contents will be\ncopied to dataSource when dataSourceRef.namespace is not specified.\nIf the namespace is specified, then dataSourceRef will not be copied to dataSource.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataVolumeClaimTemplateSpecDataSource"
            )
          );
        };
        "dataSourceRef" = mkOption {
          description = "dataSourceRef specifies the object from which to populate the volume with data, if a non-empty\nvolume is desired. This may be any object from a non-empty API group (non\ncore object) or a PersistentVolumeClaim object.\nWhen this field is specified, volume binding will only succeed if the type of\nthe specified object matches some installed volume populator or dynamic\nprovisioner.\nThis field will replace the functionality of the dataSource field and as such\nif both fields are non-empty, they must have the same value. For backwards\ncompatibility, when namespace isn't specified in dataSourceRef,\nboth fields (dataSource and dataSourceRef) will be set to the same\nvalue automatically if one of them is empty and the other is non-empty.\nWhen namespace is specified in dataSourceRef,\ndataSource isn't set to the same value and must be empty.\nThere are three important differences between dataSource and dataSourceRef:\n* While dataSource only allows two specific types of objects, dataSourceRef\n  allows any non-core object, as well as PersistentVolumeClaim objects.\n* While dataSource ignores disallowed values (dropping them), dataSourceRef\n  preserves all values, and generates an error if a disallowed value is\n  specified.\n* While dataSource only allows local objects, dataSourceRef allows objects\n  in any namespaces.\n(Alpha) Using the namespace field of dataSourceRef requires the CrossNamespaceVolumeDataSource feature gate to be enabled.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataVolumeClaimTemplateSpecDataSourceRef"
            )
          );
        };
        "resources" = mkOption {
          description = "resources represents the minimum resources the volume should have.\nUsers are allowed to specify resource requirements\nthat are lower than previous value but must still be higher than capacity recorded in the\nstatus field of the claim.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#resources";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataVolumeClaimTemplateSpecResources"
            )
          );
        };
        "selector" = mkOption {
          description = "selector is a label query over volumes to consider for binding.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataVolumeClaimTemplateSpecSelector"
            )
          );
        };
        "storageClassName" = mkOption {
          description = "storageClassName is the name of the StorageClass required by the claim.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#class-1";
          type = (types.nullOr types.str);
        };
        "volumeAttributesClassName" = mkOption {
          description = "volumeAttributesClassName may be used to set the VolumeAttributesClass used by this claim.\nIf specified, the CSI driver will create or update the volume with the attributes defined\nin the corresponding VolumeAttributesClass. This has a different purpose than storageClassName,\nit can be changed after the claim is created. An empty string or nil value indicates that no\nVolumeAttributesClass will be applied to the claim. If the claim enters an Infeasible error state,\nthis field can be reset to its previous value (including nil) to cancel the modification.\nIf the resource referred to by volumeAttributesClass does not exist, this PersistentVolumeClaim will be\nset to a Pending state, as reflected by the modifyVolumeStatus field, until such as a resource\nexists.\nMore info: https://kubernetes.io/docs/concepts/storage/volume-attributes-classes/";
          type = (types.nullOr types.str);
        };
        "volumeMode" = mkOption {
          description = "volumeMode defines what type of volume is required by the claim.\nValue of Filesystem is implied when not included in claim spec.";
          type = (types.nullOr types.str);
        };
        "volumeName" = mkOption {
          description = "volumeName is the binding reference to the PersistentVolume backing this claim.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataVolumeClaimTemplateSpecDataSource" = {

      options = {
        "apiGroup" = mkOption {
          description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataVolumeClaimTemplateSpecDataSourceRef" =
      {

        options = {
          "apiGroup" = mkOption {
            description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
            type = (types.nullOr types.str);
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
            type = (types.nullOr types.str);
          };
        };

        config = {
          "apiGroup" = mkOverride 1002 null;
          "namespace" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataVolumeClaimTemplateSpecResources" = {

      options = {
        "limits" = mkOption {
          description = "Limits describes the maximum amount of compute resources allowed.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
        };
        "requests" = mkOption {
          description = "Requests describes the minimum amount of compute resources required.\nIf Requests is omitted for a container, it defaults to Limits if that is explicitly specified,\notherwise to an implementation-defined value. Requests cannot exceed Limits.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
        };
      };

      config = {
        "limits" = mkOverride 1002 null;
        "requests" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataVolumeClaimTemplateSpecSelector" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataVolumeClaimTemplateSpecSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayMetadataVolumeClaimTemplateSpecSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayPodDisruptionBudget" = {

      options = {
        "enabled" = mkOption {
          description = "Enabled enables PodDisruptionBudget creation";
          type = (types.nullOr types.bool);
        };
        "maxUnavailable" = mkOption {
          description = "MaxUnavailable specifies the maximum number of pods that can be unavailable.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "minAvailable" = mkOption {
          description = "MinAvailable specifies the minimum number of pods that must be available.";
          type = (types.nullOr (types.either types.int types.str));
        };
      };

      config = {
        "enabled" = mkOverride 1002 null;
        "maxUnavailable" = mkOverride 1002 null;
        "minAvailable" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayPvcRetentionPolicy" = {

      options = {
        "whenDeleted" = mkOption {
          description = "WhenDeleted specifies what happens to PVCs when the StatefulSet is deleted.";
          type = (
            types.nullOr (
              types.enum [
                "Retain"
                "Delete"
              ]
            )
          );
        };
        "whenScaled" = mkOption {
          description = "WhenScaled specifies what happens to PVCs when the StatefulSet is scaled down.";
          type = (
            types.nullOr (
              types.enum [
                "Retain"
                "Delete"
              ]
            )
          );
        };
      };

      config = {
        "whenDeleted" = mkOverride 1002 null;
        "whenScaled" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayReadinessProbe" = {

      options = {
        "exec" = mkOption {
          description = "Exec specifies a command to execute in the container.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayReadinessProbeExec")
          );
        };
        "failureThreshold" = mkOption {
          description = "Minimum consecutive failures for the probe to be considered failed after having succeeded.\nDefaults to 3. Minimum value is 1.";
          type = (types.nullOr types.int);
        };
        "grpc" = mkOption {
          description = "GRPC specifies a GRPC HealthCheckRequest.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayReadinessProbeGrpc")
          );
        };
        "httpGet" = mkOption {
          description = "HTTPGet specifies an HTTP GET request to perform.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayReadinessProbeHttpGet"
            )
          );
        };
        "initialDelaySeconds" = mkOption {
          description = "Number of seconds after the container has started before liveness probes are initiated.\nMore info: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle#container-probes";
          type = (types.nullOr types.int);
        };
        "periodSeconds" = mkOption {
          description = "How often (in seconds) to perform the probe.\nDefault to 10 seconds. Minimum value is 1.";
          type = (types.nullOr types.int);
        };
        "successThreshold" = mkOption {
          description = "Minimum consecutive successes for the probe to be considered successful after having failed.\nDefaults to 1. Must be 1 for liveness and startup. Minimum value is 1.";
          type = (types.nullOr types.int);
        };
        "tcpSocket" = mkOption {
          description = "TCPSocket specifies a connection to a TCP port.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayReadinessProbeTcpSocket"
            )
          );
        };
        "terminationGracePeriodSeconds" = mkOption {
          description = "Optional duration in seconds the pod needs to terminate gracefully upon probe failure.\nThe grace period is the duration in seconds after the processes running in the pod are sent\na termination signal and the time when the processes are forcibly halted with a kill signal.\nSet this value longer than the expected cleanup time for your process.\nIf this value is nil, the pod's terminationGracePeriodSeconds will be used. Otherwise, this\nvalue overrides the value provided by the pod spec.\nValue must be non-negative integer. The value zero indicates stop immediately via\nthe kill signal (no opportunity to shut down).\nThis is a beta field and requires enabling ProbeTerminationGracePeriod feature gate.\nMinimum value is 1. spec.terminationGracePeriodSeconds is used if unset.";
          type = (types.nullOr types.int);
        };
        "timeoutSeconds" = mkOption {
          description = "Number of seconds after which the probe times out.\nDefaults to 1 second. Minimum value is 1.\nMore info: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle#container-probes";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "exec" = mkOverride 1002 null;
        "failureThreshold" = mkOverride 1002 null;
        "grpc" = mkOverride 1002 null;
        "httpGet" = mkOverride 1002 null;
        "initialDelaySeconds" = mkOverride 1002 null;
        "periodSeconds" = mkOverride 1002 null;
        "successThreshold" = mkOverride 1002 null;
        "tcpSocket" = mkOverride 1002 null;
        "terminationGracePeriodSeconds" = mkOverride 1002 null;
        "timeoutSeconds" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayReadinessProbeExec" = {

      options = {
        "command" = mkOption {
          description = "Command is the command line to execute inside the container, the working directory for the\ncommand  is root ('/') in the container's filesystem. The command is simply exec'd, it is\nnot run inside a shell, so traditional shell instructions ('|', etc) won't work. To use\na shell, you need to explicitly call out to that shell.\nExit status of 0 is treated as live/healthy and non-zero is unhealthy.";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "command" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayReadinessProbeGrpc" = {

      options = {
        "mode" = mkOption {
          description = "mode specifies the connection mode for the gRPC health probe.\nSet to \"TLS\" to use TLS without certificate verification.\nSet to \"Plaintext\" to use a plaintext (insecure) connection explicitly.\nIf not specified, the probe uses a plaintext (insecure) connection.";
          type = (types.nullOr types.str);
        };
        "port" = mkOption {
          description = "Port number of the gRPC service. Number must be in the range 1 to 65535.";
          type = types.int;
        };
        "service" = mkOption {
          description = "Service is the name of the service to place in the gRPC HealthCheckRequest\n(see https://github.com/grpc/grpc/blob/master/doc/health-checking.md).\n\nIf this is not specified, the default behavior is defined by gRPC.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "mode" = mkOverride 1002 null;
        "service" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayReadinessProbeHttpGet" = {

      options = {
        "host" = mkOption {
          description = "Host name to connect to, defaults to the pod IP. You probably want to set\n\"Host\" in httpHeaders instead.";
          type = (types.nullOr types.str);
        };
        "httpHeaders" = mkOption {
          description = "Custom headers to set in the request. HTTP allows repeated headers.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayReadinessProbeHttpGetHttpHeaders"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "path" = mkOption {
          description = "Path to access on the HTTP server.";
          type = (types.nullOr types.str);
        };
        "port" = mkOption {
          description = "Name or number of the port to access on the container.\nNumber must be in the range 1 to 65535.\nName must be an IANA_SVC_NAME.";
          type = (types.either types.int types.str);
        };
        "protocol" = mkOption {
          description = "Protocol selects the wire protocol for the probe connection.\nNil defaults to HTTP/1.1.";
          type = (types.nullOr types.str);
        };
        "scheme" = mkOption {
          description = "Scheme to use for connecting to the host.\nDefaults to HTTP.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "host" = mkOverride 1002 null;
        "httpHeaders" = mkOverride 1002 null;
        "path" = mkOverride 1002 null;
        "protocol" = mkOverride 1002 null;
        "scheme" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayReadinessProbeHttpGetHttpHeaders" = {

      options = {
        "name" = mkOption {
          description = "The header field name.\nThis will be canonicalized upon output, so case-variant names will be understood as the same header.";
          type = types.str;
        };
        "value" = mkOption {
          description = "The header field value";
          type = types.str;
        };
      };

      config = { };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayReadinessProbeTcpSocket" = {

      options = {
        "host" = mkOption {
          description = "Optional: Host name to connect to, defaults to the pod IP.";
          type = (types.nullOr types.str);
        };
        "port" = mkOption {
          description = "Number or name of the port to access on the container.\nNumber must be in the range 1 to 65535.\nName must be an IANA_SVC_NAME.";
          type = (types.either types.int types.str);
        };
      };

      config = {
        "host" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayResources" = {

      options = {
        "claims" = mkOption {
          description = "Claims lists the names of resources, defined in spec.resourceClaims,\nthat are used by this container.\n\nThis field depends on the\nDynamicResourceAllocation feature gate.\n\nThis field is immutable. It can only be set for containers.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayResourcesClaims"
                "name"
                [ "name" ]
            )
          );
          apply = attrsToList;
        };
        "limits" = mkOption {
          description = "Limits describes the maximum amount of compute resources allowed.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
        };
        "requests" = mkOption {
          description = "Requests describes the minimum amount of compute resources required.\nIf Requests is omitted for a container, it defaults to Limits if that is explicitly specified,\notherwise to an implementation-defined value. Requests cannot exceed Limits.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
        };
      };

      config = {
        "claims" = mkOverride 1002 null;
        "limits" = mkOverride 1002 null;
        "requests" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayResourcesClaims" = {

      options = {
        "name" = mkOption {
          description = "Name must match the name of one entry in pod.spec.resourceClaims of\nthe Pod where this field is used. It makes that resource available\ninside a container.";
          type = types.str;
        };
        "request" = mkOption {
          description = "Request is the name chosen for a request in the referenced claim.\nIf empty, everything from the claim is made available, otherwise\nonly the result of this request.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "request" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewaySecurityContext" = {

      options = {
        "appArmorProfile" = mkOption {
          description = "appArmorProfile is the AppArmor options to use by the containers in this pod.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewaySecurityContextAppArmorProfile"
            )
          );
        };
        "fsGroup" = mkOption {
          description = "A special supplemental group that applies to all containers in a pod.\nSome volume types allow the Kubelet to change the ownership of that volume\nto be owned by the pod:\n\n1. The owning GID will be the FSGroup\n2. The setgid bit is set (new files created in the volume will be owned by FSGroup)\n3. The permission bits are OR'd with rw-rw----\n\nIf unset, the Kubelet will not modify the ownership and permissions of any volume.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.int);
        };
        "fsGroupChangePolicy" = mkOption {
          description = "fsGroupChangePolicy defines behavior of changing ownership and permission of the volume\nbefore being exposed inside Pod. This field will only apply to\nvolume types which support fsGroup based ownership(and permissions).\nIt will have no effect on ephemeral volume types such as: secret, configmaps\nand emptydir.\nValid values are \"OnRootMismatch\" and \"Always\". If not specified, \"Always\" is used.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.str);
        };
        "runAsGroup" = mkOption {
          description = "The GID to run the entrypoint of the container process.\nUses runtime default if unset.\nMay also be set in SecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence\nfor that container.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.int);
        };
        "runAsNonRoot" = mkOption {
          description = "Indicates that the container must run as a non-root user.\nIf true, the Kubelet will validate the image at runtime to ensure that it\ndoes not run as UID 0 (root) and fail to start the container if it does.\nIf unset or false, no such validation will be performed.\nMay also be set in SecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
          type = (types.nullOr types.bool);
        };
        "runAsUser" = mkOption {
          description = "The UID to run the entrypoint of the container process.\nDefaults to user specified in image metadata if unspecified.\nMay also be set in SecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence\nfor that container.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.int);
        };
        "seLinuxChangePolicy" = mkOption {
          description = "seLinuxChangePolicy defines how the container's SELinux label is applied to all volumes used by the Pod.\nIt has no effect on nodes that do not support SELinux or to volumes does not support SELinux.\nValid values are \"MountOption\" and \"Recursive\".\n\n\"Recursive\" means relabeling of all files on all Pod volumes by the container runtime.\nThis may be slow for large volumes, but allows mixing privileged and unprivileged Pods sharing the same volume on the same node.\n\n\"MountOption\" mounts all eligible Pod volumes with `-o context` mount option.\nThis requires all Pods that share the same volume to use the same SELinux label.\nIt is not possible to share the same volume among privileged and unprivileged Pods.\nEligible volumes are in-tree FibreChannel and iSCSI volumes, and all CSI volumes\nwhose CSI driver announces SELinux support by setting spec.seLinuxMount: true in their\nCSIDriver instance. Other volumes are always re-labelled recursively.\n\nIf not specified, \"MountOption\" is used.\n\nThis field affects only Pods that have SELinux label set, either in PodSecurityContext or in SecurityContext of all containers.\n\nAll Pods that use the same volume should use the same seLinuxChangePolicy, otherwise some pods can get stuck in ContainerCreating state.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.str);
        };
        "seLinuxOptions" = mkOption {
          description = "The SELinux context to be applied to all containers.\nIf unspecified, the container runtime will allocate a random SELinux context for each\ncontainer.  May also be set in SecurityContext.  If set in\nboth SecurityContext and PodSecurityContext, the value specified in SecurityContext\ntakes precedence for that container.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewaySecurityContextSeLinuxOptions"
            )
          );
        };
        "seccompProfile" = mkOption {
          description = "The seccomp options to use by the containers in this pod.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewaySecurityContextSeccompProfile"
            )
          );
        };
        "supplementalGroups" = mkOption {
          description = "A list of groups applied to the first process run in each container, in\naddition to the container's primary GID and fsGroup (if specified).  If\nthe SupplementalGroupsPolicy feature is enabled, the\nsupplementalGroupsPolicy field determines whether these are in addition\nto or instead of any group memberships defined in the container image.\nIf unspecified, no additional groups are added, though group memberships\ndefined in the container image may still be used, depending on the\nsupplementalGroupsPolicy field.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr (types.listOf types.int));
        };
        "supplementalGroupsPolicy" = mkOption {
          description = "Defines how supplemental groups of the first container processes are calculated.\nValid values are \"Merge\" and \"Strict\". If not specified, \"Merge\" is used.\n(Alpha) Using the field requires the SupplementalGroupsPolicy feature gate to be enabled\nand the container runtime must implement support for this feature.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.str);
        };
        "sysctls" = mkOption {
          description = "Sysctls hold a list of namespaced sysctls used for the pod. Pods with unsupported\nsysctls (by the container runtime) might fail to launch.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewaySecurityContextSysctls"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "windowsOptions" = mkOption {
          description = "The Windows specific settings applied to all containers.\nIf unspecified, the options within a container's SecurityContext will be used.\nIf set in both SecurityContext and PodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is linux.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewaySecurityContextWindowsOptions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewaySecurityContextAppArmorProfile" = {

      options = {
        "localhostProfile" = mkOption {
          description = "localhostProfile indicates a profile loaded on the node that should be used.\nThe profile must be preconfigured on the node to work.\nMust match the loaded name of the profile.\nMust be set if and only if type is \"Localhost\".";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewaySecurityContextSeLinuxOptions" = {

      options = {
        "level" = mkOption {
          description = "Level is SELinux level label that applies to the container.";
          type = (types.nullOr types.str);
        };
        "role" = mkOption {
          description = "Role is a SELinux role label that applies to the container.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is a SELinux type label that applies to the container.";
          type = (types.nullOr types.str);
        };
        "user" = mkOption {
          description = "User is a SELinux user label that applies to the container.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "level" = mkOverride 1002 null;
        "role" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
        "user" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewaySecurityContextSeccompProfile" = {

      options = {
        "localhostProfile" = mkOption {
          description = "localhostProfile indicates a profile defined in a file on the node should be used.\nThe profile must be preconfigured on the node to work.\nMust be a descending path, relative to the kubelet's configured seccomp profile location.\nMust be set if type is \"Localhost\". Must NOT be set for any other type.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewaySecurityContextSysctls" = {

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

      config = { };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewaySecurityContextWindowsOptions" = {

      options = {
        "gmsaCredentialSpec" = mkOption {
          description = "GMSACredentialSpec is where the GMSA admission webhook\n(https://github.com/kubernetes-sigs/windows-gmsa) inlines the contents of the\nGMSA credential spec named by the GMSACredentialSpecName field.";
          type = (types.nullOr types.str);
        };
        "gmsaCredentialSpecName" = mkOption {
          description = "GMSACredentialSpecName is the name of the GMSA credential spec to use.";
          type = (types.nullOr types.str);
        };
        "hostProcess" = mkOption {
          description = "HostProcess determines if a container should be run as a 'Host Process' container.\nAll of a Pod's containers must have the same effective HostProcess value\n(it is not allowed to have a mix of HostProcess containers and non-HostProcess containers).\nIn addition, if HostProcess is true then HostNetwork must also be set to true.";
          type = (types.nullOr types.bool);
        };
        "runAsUserName" = mkOption {
          description = "The UserName in Windows to run the entrypoint of the container process.\nDefaults to the user specified in image metadata if unspecified.\nMay also be set in PodSecurityContext. If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "gmsaCredentialSpec" = mkOverride 1002 null;
        "gmsaCredentialSpecName" = mkOverride 1002 null;
        "hostProcess" = mkOverride 1002 null;
        "runAsUserName" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayTolerations" = {

      options = {
        "effect" = mkOption {
          description = "Effect indicates the taint effect to match. Empty means match all taint effects.\nWhen specified, allowed values are NoSchedule, PreferNoSchedule and NoExecute.";
          type = (types.nullOr types.str);
        };
        "key" = mkOption {
          description = "Key is the taint key that the toleration applies to. Empty means match all taint keys.\nIf the key is empty, operator must be Exists; this combination means to match all values and all keys.";
          type = (types.nullOr types.str);
        };
        "operator" = mkOption {
          description = "Operator represents a key's relationship to the value.\nValid operators are Exists, Equal, Lt, and Gt. Defaults to Equal.\nExists is equivalent to wildcard for value, so that a pod can\ntolerate all taints of a particular category.\nLt and Gt perform numeric comparisons (requires feature gate TaintTolerationComparisonOperators).";
          type = (types.nullOr types.str);
        };
        "tolerationSeconds" = mkOption {
          description = "TolerationSeconds represents the period of time the toleration (which must be\nof effect NoExecute, otherwise this field is ignored) tolerates the taint. By default,\nit is not set, which means tolerate the taint forever (do not evict). Zero and\nnegative values will be treated as 0 (evict immediately) by the system.";
          type = (types.nullOr types.int);
        };
        "value" = mkOption {
          description = "Value is the taint value the toleration matches to.\nIf the operator is Exists, the value should be empty, otherwise just a regular string.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayTopologySpreadConstraints" = {

      options = {
        "labelSelector" = mkOption {
          description = "LabelSelector is used to find matching pods.\nPods that match this label selector are counted to determine the number of pods\nin their corresponding topology domain.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayTopologySpreadConstraintsLabelSelector"
            )
          );
        };
        "matchLabelKeys" = mkOption {
          description = "MatchLabelKeys is a set of pod label keys to select the pods over which\nspreading will be calculated. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are ANDed with labelSelector\nto select the group of existing pods over which spreading will be calculated\nfor the incoming pod. The same key is forbidden to exist in both MatchLabelKeys and LabelSelector.\nMatchLabelKeys cannot be set when LabelSelector isn't set.\nKeys that don't exist in the incoming pod labels will\nbe ignored. A null or empty list means only match against labelSelector.\n\nThis is a beta field and requires the MatchLabelKeysInPodTopologySpread feature gate to be enabled (enabled by default).";
          type = (types.nullOr (types.listOf types.str));
        };
        "maxSkew" = mkOption {
          description = "MaxSkew describes the degree to which pods may be unevenly distributed.\nWhen `whenUnsatisfiable=DoNotSchedule`, it is the maximum permitted difference\nbetween the number of matching pods in the target topology and the global minimum.\nThe global minimum is the minimum number of matching pods in an eligible domain\nor zero if the number of eligible domains is less than MinDomains.\nFor example, in a 3-zone cluster, MaxSkew is set to 1, and pods with the same\nlabelSelector spread as 2/2/1:\nIn this case, the global minimum is 1.\n| zone1 | zone2 | zone3 |\n|  P P  |  P P  |   P   |\n- if MaxSkew is 1, incoming pod can only be scheduled to zone3 to become 2/2/2;\nscheduling it onto zone1(zone2) would make the ActualSkew(3-1) on zone1(zone2)\nviolate MaxSkew(1).\n- if MaxSkew is 2, incoming pod can be scheduled onto any zone.\nWhen `whenUnsatisfiable=ScheduleAnyway`, it is used to give higher precedence\nto topologies that satisfy it.\nIt's a required field. Default value is 1 and 0 is not allowed.";
          type = types.int;
        };
        "minDomains" = mkOption {
          description = "MinDomains indicates a minimum number of eligible domains.\nWhen the number of eligible domains with matching topology keys is less than minDomains,\nPod Topology Spread treats \"global minimum\" as 0, and then the calculation of Skew is performed.\nAnd when the number of eligible domains with matching topology keys equals or greater than minDomains,\nthis value has no effect on scheduling.\nAs a result, when the number of eligible domains is less than minDomains,\nscheduler won't schedule more than maxSkew Pods to those domains.\nIf value is nil, the constraint behaves as if MinDomains is equal to 1.\nValid values are integers greater than 0.\nWhen value is not nil, WhenUnsatisfiable must be DoNotSchedule.\n\nFor example, in a 3-zone cluster, MaxSkew is set to 2, MinDomains is set to 5 and pods with the same\nlabelSelector spread as 2/2/2:\n| zone1 | zone2 | zone3 |\n|  P P  |  P P  |  P P  |\nThe number of domains is less than 5(MinDomains), so \"global minimum\" is treated as 0.\nIn this situation, new pod with the same labelSelector cannot be scheduled,\nbecause computed skew will be 3(3 - 0) if new Pod is scheduled to any of the three zones,\nit will violate MaxSkew.";
          type = (types.nullOr types.int);
        };
        "nodeAffinityPolicy" = mkOption {
          description = "NodeAffinityPolicy indicates how we will treat Pod's nodeAffinity/nodeSelector\nwhen calculating pod topology spread skew. Options are:\n- Honor: only nodes matching nodeAffinity/nodeSelector are included in the calculations.\n- Ignore: nodeAffinity/nodeSelector are ignored. All nodes are included in the calculations.\n\nIf this value is nil, the behavior is equivalent to the Honor policy.";
          type = (types.nullOr types.str);
        };
        "nodeTaintsPolicy" = mkOption {
          description = "NodeTaintsPolicy indicates how we will treat node taints when calculating\npod topology spread skew. Options are:\n- Honor: nodes without taints, along with tainted nodes for which the incoming pod\nhas a toleration, are included.\n- Ignore: node taints are ignored. All nodes are included.\n\nIf this value is nil, the behavior is equivalent to the Ignore policy.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayTopologySpreadConstraintsLabelSelector" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayTopologySpreadConstraintsLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecGatewayTopologySpreadConstraintsLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecImagePullSecrets" = {

      options = {
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecK2vApi" = {

      options = {
        "bindAddress" = mkOption {
          description = "BindAddress is a custom wildcard TCP bind address for the K2V API.";
          type = (types.nullOr types.str);
        };
        "bindPort" = mkOption {
          description = "BindPort is the port to bind for K2V API.";
          type = (types.nullOr (types.withMaximum 65535 (types.withMinimum 1 types.int)));
        };
      };

      config = {
        "bindAddress" = mkOverride 1002 null;
        "bindPort" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecLayoutManagement" = {

      options = {
        "autoApply" = mkOption {
          description = "AutoApply automatically applies staged layout changes.";
          type = (types.nullOr types.bool);
        };
        "drain" = mkOption {
          description = "Drain configures the fail-closed boundary for positive-capacity removal\nacross the canonical Garage layout. It is deliberately independent of a\nlocal storage workload: management handles, mixed PVC/SMB/node-local-pool sites,\nexternal GarageNodes, scale-down, and deletionPolicy: Drain all coordinate\nthrough the same policy.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecLayoutManagementDrain")
          );
        };
        "minNodesHealthy" = mkOption {
          description = "MinNodesHealthy is the minimum healthy nodes required before applying layout changes.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "autoApply" = mkOverride 1002 null;
        "drain" = mkOverride 1002 null;
        "minNodesHealthy" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecLayoutManagementDrain" = {

      options = {
        "unverifiedPeersPolicy" = mkOption {
          description = "UnverifiedPeersPolicy defaults to Block. AssumeConsistent is required for\nfederated or externally managed processes and is a deliberate maintenance\nassertion, not an online safety guarantee.";
          type = (
            types.nullOr (
              types.enum [
                "Block"
                "AssumeConsistent"
              ]
            )
          );
        };
      };

      config = {
        "unverifiedPeersPolicy" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecLogging" = {

      options = {
        "journald" = mkOption {
          description = "Journald enables logging to systemd journald.";
          type = (types.nullOr types.bool);
        };
        "level" = mkOption {
          description = "Level sets the log level using RUST_LOG format.";
          type = (types.nullOr types.str);
        };
        "syslog" = mkOption {
          description = "Syslog enables logging to syslog.";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "journald" = mkOverride 1002 null;
        "level" = mkOverride 1002 null;
        "syslog" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecMaintenance" = {

      options = {
        "suspended" = mkOption {
          description = "Suspended pauses all reconciliation for this cluster.";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "suspended" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecMonitoring" = {

      options = {
        "additionalLabels" = mkOption {
          description = "AdditionalLabels are added to the ServiceMonitor metadata.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "enabled" = mkOption {
          description = "Enabled creates a ServiceMonitor targeting the admin API /metrics endpoint.";
          type = (types.nullOr types.bool);
        };
        "interval" = mkOption {
          description = "Interval is the Prometheus scrape interval (e.g. \"30s\", \"1m\").";
          type = (types.nullOr types.str);
        };
        "metricRelabelings" = mkOption {
          description = "MetricRelabelings are applied to samples scraped from the admin /metrics\nendpoint before ingestion (set as the ServiceMonitor endpoint's\nmetricRelabelings). Use them to drop high-cardinality series that nothing\nqueries — e.g. the per-method rpc_duration_* histograms, which dominate a\nGarage node's metric series count.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecMonitoringMetricRelabelings"
              )
            )
          );
        };
      };

      config = {
        "additionalLabels" = mkOverride 1002 null;
        "enabled" = mkOverride 1002 null;
        "interval" = mkOverride 1002 null;
        "metricRelabelings" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecMonitoringMetricRelabelings" = {

      options = {
        "action" = mkOption {
          description = "action to perform based on the regex matching.\n\n`Uppercase` and `Lowercase` actions require Prometheus >= v2.36.0.\n`DropEqual` and `KeepEqual` actions require Prometheus >= v2.41.0.\n\nDefault: \"Replace\"";
          type = (
            types.nullOr (
              types.enum [
                "replace"
                "Replace"
                "keep"
                "Keep"
                "drop"
                "Drop"
                "hashmod"
                "HashMod"
                "labelmap"
                "LabelMap"
                "labeldrop"
                "LabelDrop"
                "labelkeep"
                "LabelKeep"
                "lowercase"
                "Lowercase"
                "uppercase"
                "Uppercase"
                "keepequal"
                "KeepEqual"
                "dropequal"
                "DropEqual"
              ]
            )
          );
        };
        "modulus" = mkOption {
          description = "modulus to take of the hash of the source label values.\n\nOnly applicable when the action is `HashMod`.";
          type = (types.nullOr (types.withMinimum 0 types.int));
        };
        "regex" = mkOption {
          description = "regex defines the regular expression against which the extracted value is matched.";
          type = (types.nullOr types.str);
        };
        "replacement" = mkOption {
          description = "replacement value against which a Replace action is performed if the\nregular expression matches.\n\nRegex capture groups are available.";
          type = (types.nullOr types.str);
        };
        "separator" = mkOption {
          description = "separator defines the string between concatenated SourceLabels.";
          type = (types.nullOr types.str);
        };
        "sourceLabels" = mkOption {
          description = "sourceLabels defines the source labels select values from existing labels. Their content is\nconcatenated using the configured Separator and matched against the\nconfigured regular expression.";
          type = (types.nullOr (types.listOf types.str));
        };
        "targetLabel" = mkOption {
          description = "targetLabel defines the label to which the resulting string is written in a replacement.\n\nIt is mandatory for `Replace`, `HashMod`, `Lowercase`, `Uppercase`,\n`KeepEqual` and `DropEqual` actions.\n\nRegex capture groups are available.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "action" = mkOverride 1002 null;
        "modulus" = mkOverride 1002 null;
        "regex" = mkOverride 1002 null;
        "replacement" = mkOverride 1002 null;
        "separator" = mkOverride 1002 null;
        "sourceLabels" = mkOverride 1002 null;
        "targetLabel" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecNetwork" = {

      options = {
        "bootstrapPeers" = mkOption {
          description = "BootstrapPeers lists initial peers for cluster formation.";
          type = (types.nullOr (types.listOf types.str));
        };
        "rpcBindAddress" = mkOption {
          description = "RPCBindAddress is a custom wildcard TCP bind address for the RPC server.";
          type = (types.nullOr types.str);
        };
        "rpcBindOutgoing" = mkOption {
          description = "RPCBindOutgoing pre-binds outgoing sockets to same IP.";
          type = (types.nullOr types.bool);
        };
        "rpcBindPort" = mkOption {
          description = "RPCBindPort is the port for inter-cluster RPC.";
          type = (types.nullOr (types.withMaximum 65535 (types.withMinimum 1 types.int)));
        };
        "rpcPingTimeout" = mkOption {
          description = "RPCPingTimeout sets the RPC ping timeout.";
          type = (types.nullOr types.str);
        };
        "rpcPublicAddr" = mkOption {
          description = "RPCPublicAddr is the external address for storage-tier nodes to advertise.\nGateway tier has its own rpcPublicAddr field on `spec.gateway`.";
          type = (types.nullOr types.str);
        };
        "rpcPublicAddrSubnet" = mkOption {
          description = "RPCPublicAddrSubnet filters autodiscovered IPs to specific subnet.";
          type = (types.nullOr types.str);
        };
        "rpcSecretRef" = mkOption {
          description = "RPCSecretRef references a secret containing the shared RPC secret.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecNetworkRpcSecretRef")
          );
        };
        "rpcTimeout" = mkOption {
          description = "RPCTimeout sets the RPC call timeout.";
          type = (types.nullOr types.str);
        };
        "service" = mkOption {
          description = "Service configures the Kubernetes Service for the cluster.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecNetworkService"));
        };
      };

      config = {
        "bootstrapPeers" = mkOverride 1002 null;
        "rpcBindAddress" = mkOverride 1002 null;
        "rpcBindOutgoing" = mkOverride 1002 null;
        "rpcBindPort" = mkOverride 1002 null;
        "rpcPingTimeout" = mkOverride 1002 null;
        "rpcPublicAddr" = mkOverride 1002 null;
        "rpcPublicAddrSubnet" = mkOverride 1002 null;
        "rpcSecretRef" = mkOverride 1002 null;
        "rpcTimeout" = mkOverride 1002 null;
        "service" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecNetworkRpcSecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecNetworkService" = {

      options = {
        "annotations" = mkOption {
          description = "Annotations to add to the service.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "externalTrafficPolicy" = mkOption {
          description = "ExternalTrafficPolicy for LoadBalancer/NodePort.";
          type = (types.nullOr types.str);
        };
        "labels" = mkOption {
          description = "Labels to add to the service. Operator-managed labels take precedence on conflict.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "loadBalancerIP" = mkOption {
          description = "LoadBalancerIP for LoadBalancer type.";
          type = (types.nullOr types.str);
        };
        "loadBalancerSourceRanges" = mkOption {
          description = "LoadBalancerSourceRanges for LoadBalancer type.";
          type = (types.nullOr (types.listOf types.str));
        };
        "type" = mkOption {
          description = "Type of service.";
          type = (
            types.nullOr (
              types.enum [
                "ClusterIP"
                "NodePort"
                "LoadBalancer"
              ]
            )
          );
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "externalTrafficPolicy" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "loadBalancerIP" = mkOverride 1002 null;
        "loadBalancerSourceRanges" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecPublicEndpoint" = {

      options = {
        "externalIP" = mkOption {
          description = "ExternalIP is retained for API compatibility but is not supported.\nSetting it is rejected because the operator does not consume the explicit\naddress mapping or template.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecPublicEndpointExternalIP")
          );
        };
        "loadBalancer" = mkOption {
          description = "LoadBalancer configuration.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecPublicEndpointLoadBalancer"
            )
          );
        };
        "nodePort" = mkOption {
          description = "NodePort configuration.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecPublicEndpointNodePort")
          );
        };
        "type" = mkOption {
          description = "Type specifies how nodes are exposed to remote clusters for RPC.";
          type = (
            types.enum [
              "LoadBalancer"
              "NodePort"
              "ExternalIP"
              "Headless"
            ]
          );
        };
      };

      config = {
        "externalIP" = mkOverride 1002 null;
        "loadBalancer" = mkOverride 1002 null;
        "nodePort" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecPublicEndpointExternalIP" = {

      options = {
        "addressTemplate" = mkOption {
          description = "AddressTemplate is retained for API compatibility but is unsupported.";
          type = (types.nullOr types.str);
        };
        "addresses" = mkOption {
          description = "Addresses is retained for API compatibility but is unsupported.";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "addressTemplate" = mkOverride 1002 null;
        "addresses" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecPublicEndpointLoadBalancer" = {

      options = {
        "annotations" = mkOption {
          description = "Annotations to add to the service.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "labels" = mkOption {
          description = "Labels to add to the service. Operator-managed labels take precedence on conflict.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "perNode" = mkOption {
          description = "PerNode creates a separate LoadBalancer service per GarageCluster pod.";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "perNode" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecPublicEndpointNodePort" = {

      options = {
        "annotations" = mkOption {
          description = "Annotations to add to the service.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "basePort" = mkOption {
          description = "BasePort is the starting NodePort; Garage pod N is exposed on BasePort+N.";
          type = (types.nullOr (types.withMaximum 32767 (types.withMinimum 30000 types.int)));
        };
        "externalAddresses" = mkOption {
          description = "ExternalAddresses are the externally-reachable IPs or hostnames of the Kubernetes nodes.";
          type = (types.listOf types.str);
        };
        "labels" = mkOption {
          description = "Labels to add to the service. Operator-managed labels take precedence on conflict.";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "basePort" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecRemoteClusters" = {

      options = {
        "connection" = mkOption {
          description = "Connection defines how to connect to this remote cluster.";
          type = (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecRemoteClustersConnection");
        };
        "defaultCapacity" = mkOption {
          description = "DefaultCapacity is retained for API compatibility but is not supported.\nRemote role capacity is copied from the source cluster's committed or\nstaged layout and cannot be overridden by the importing cluster.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "name" = mkOption {
          description = "Name is a friendly name for this remote cluster.";
          type = (types.withMinLength 1 types.str);
        };
        "zone" = mkOption {
          description = "Zone is the zone name for nodes in this remote cluster.";
          type = (types.withMinLength 1 types.str);
        };
      };

      config = {
        "defaultCapacity" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecRemoteClustersConnection" = {

      options = {
        "adminApiEndpoint" = mkOption {
          description = "AdminAPIEndpoint is the admin API endpoint of the remote cluster.";
          type = (types.withMinLength 1 types.str);
        };
        "adminTokenSecretRef" = mkOption {
          description = "AdminTokenSecretRef references the admin token for the remote cluster's API.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecRemoteClustersConnectionAdminTokenSecretRef"
            )
          );
        };
        "gatewayRpcEndpointTemplate" = mkOption {
          description = "GatewayRPCEndpointTemplate is a hostname:port template used by federation\nto connect to remote gateway pods individually. The literal `{ordinal}`\nis replaced with each remote gateway pod's ordinal (0, 1, ...) parsed\nfrom the layout role's pod-name tag (e.g. `garage-gateway-0`).\n\nRequired when the remote cluster runs gateway pods that participate in\nthe cluster layout (default since v0.5.8). FullReplication tables\n(key_table, bucket_table, ...) need quorum across all_nodes, which\nincludes remote gateways. Without this field the operator only peers\nstorage↔storage cross-region; remote gateways appear in layout but\nremain unreachable, blocking GetKeyInfo / DeleteKey / FullReplication\nwrites that need full quorum.\n\nExample: \"ottawa-garage-gw-{ordinal}.keiretsu.ts.net:3901\"";
          type = (types.nullOr types.str);
        };
        "storageRpcEndpointTemplate" = mkOption {
          description = "StorageRPCEndpointTemplate is a hostname:port template used by federation\nto connect to remote STORAGE pods individually, mirroring\nGatewayRPCEndpointTemplate. The literal `{ordinal}` is replaced with each\nremote storage pod's ordinal (0, 1, ...) parsed from the layout role's\npod-name tag (e.g. `garage-storage-0`).\n\nNeeded when a remote region runs more than one storage pod behind a single\nadmin hostname (e.g. a Tailscale VIP): the default storage↔storage connect\nloop dials every remote node at that one shared hostname, which only ever\nlands one pod, leaving the rest unreachable cross-region. Set this together\nwith the remote region's spec.storage.rpcPublicAddr `{ordinal}` template so\neach storage pod is both advertised and dialed per-pod.\n\nExample: \"ottawa-storage-{ordinal}.keiretsu.ts.net:3901\"";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "adminTokenSecretRef" = mkOverride 1002 null;
        "gatewayRpcEndpointTemplate" = mkOverride 1002 null;
        "storageRpcEndpointTemplate" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecRemoteClustersConnectionAdminTokenSecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecReplication" = {

      options = {
        "consistencyMode" = mkOption {
          description = "ConsistencyMode controls quorum behavior for read/write operations.";
          type = (
            types.nullOr (
              types.enum [
                "consistent"
                "degraded"
                "dangerous"
              ]
            )
          );
        };
        "factor" = mkOption {
          description = "Factor is the replication factor (1, 2, 3, 5, 7, etc.)";
          type = (types.withMaximum 7 (types.withMinimum 1 types.int));
        };
        "zoneRedundancyMinZones" = mkOption {
          description = "ZoneRedundancyMinZones is the minimum number of zones required.";
          type = (types.nullOr (types.withMaximum 7 (types.withMinimum 1 types.int)));
        };
        "zoneRedundancyMode" = mkOption {
          description = "ZoneRedundancyMode controls how data is distributed across zones.";
          type = (
            types.nullOr (
              types.enum [
                "Maximum"
                "AtLeast"
              ]
            )
          );
        };
      };

      config = {
        "consistencyMode" = mkOverride 1002 null;
        "zoneRedundancyMinZones" = mkOverride 1002 null;
        "zoneRedundancyMode" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecS3Api" = {

      options = {
        "bindAddress" = mkOption {
          description = "BindAddress is a custom wildcard TCP bind address for the S3 API.";
          type = (types.nullOr types.str);
        };
        "bindPort" = mkOption {
          description = "BindPort is the port to bind for S3 API.";
          type = (types.nullOr (types.withMaximum 65535 (types.withMinimum 1 types.int)));
        };
        "region" = mkOption {
          description = "Region is the AWS S3 region name to use.";
          type = types.str;
        };
        "rootDomain" = mkOption {
          description = "RootDomain is the root domain suffix for vhost-style S3 access.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "bindAddress" = mkOverride 1002 null;
        "bindPort" = mkOverride 1002 null;
        "rootDomain" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecSecurity" = {

      options = {
        "allowInsecureSecretPermissions" = mkOption {
          description = "AllowInsecureSecretPermissions bypasses Garage's check that secret files\nare not world-readable on disk.";
          type = (types.nullOr types.bool);
        };
        "allowPunycode" = mkOption {
          description = "AllowPunycode allows punycode in bucket names.";
          type = (types.nullOr types.bool);
        };
        "tls" = mkOption {
          description = "TLS configures TLS settings.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecSecurityTls"));
        };
      };

      config = {
        "allowInsecureSecretPermissions" = mkOverride 1002 null;
        "allowPunycode" = mkOverride 1002 null;
        "tls" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecSecurityTls" = {

      options = {
        "caSecretRef" = mkOption {
          description = "CASecretRef references a secret containing the CA certificate.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecSecurityTlsCaSecretRef")
          );
        };
        "certSecretRef" = mkOption {
          description = "CertSecretRef references a secret containing the TLS certificate for RPC.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecSecurityTlsCertSecretRef")
          );
        };
        "enabled" = mkOption {
          description = "Enabled enables TLS for inter-node RPC communication.";
          type = (types.nullOr types.bool);
        };
        "keySecretRef" = mkOption {
          description = "KeySecretRef references a secret containing the TLS private key for RPC.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecSecurityTlsKeySecretRef")
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecSecurityTlsCaSecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecSecurityTlsCertSecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecSecurityTlsKeySecretRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorage" = {

      options = {
        "affinity" = mkOption {
          description = "Affinity for pod scheduling.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinity"));
        };
        "capacityReservePercent" = mkOption {
          description = "CapacityReservePercent reserves a percentage of PVC capacity for overhead.\nOnly meaningful when LayoutPolicy is \"Auto\".";
          type = (types.nullOr (types.withMaximum 50 (types.withMinimum 0 types.int)));
        };
        "containerSecurityContext" = mkOption {
          description = "ContainerSecurityContext for the Garage container.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageContainerSecurityContext"
            )
          );
        };
        "data" = mkOption {
          description = "Data configures object-block storage for the default StatefulSet/PVC group.\nIt may be omitted together with metadata when replicas is 0.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageData"));
        };
        "dataFsync" = mkOption {
          description = "DataFsync enables fsync for data block writes.";
          type = (types.nullOr types.bool);
        };
        "env" = mkOption {
          description = "Env is a list of additional environment variables to set on the Garage\ncontainer. Garage config-path and RPC/Admin/metrics credential variables are\noperator-reserved. Typical use: setting GARAGE_ALLOW_WORLD_READABLE_SECRETS\nor another non-identity Garage startup option.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnv" "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "envFrom" = mkOption {
          description = "EnvFrom is a list of sources to populate environment variables in the\nGarage container. A source prefix must not be capable of injecting an\noperator-reserved Garage variable. Sources are evaluated before the\nper-variable Env list, matching Kubernetes container semantics.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnvFrom")
            )
          );
        };
        "layoutPolicy" = mkOption {
          description = "LayoutPolicy overrides the cluster-level spec.layoutPolicy for the STORAGE\ndefault StatefulSet/PVC group only. This lets a cluster hand-manage SMB/PVC\nGarageNodes (Manual) while node-local pools remain operator-managed and\nwhile the gateway tier follows the cluster policy. Defaults to\nspec.layoutPolicy when empty. Auto->Manual is one-way for the default group.";
          type = (
            types.nullOr (
              types.enum [
                "Auto"
                "Manual"
              ]
            )
          );
        };
        "metadata" = mkOption {
          description = "Metadata configures Garage node identity + index DB storage for the\ndefault StatefulSet/PVC group. It may be omitted together with data when\nreplicas is 0 and only Manual GarageNodes or node-local pools are used.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadata"));
        };
        "metadataAutoSnapshotInterval" = mkOption {
          description = "MetadataAutoSnapshotInterval enables automatic metadata snapshots.";
          type = (types.nullOr types.str);
        };
        "metadataFsync" = mkOption {
          description = "MetadataFsync enables fsync for metadata transactions.";
          type = (types.nullOr types.bool);
        };
        "metadataSnapshotsDir" = mkOption {
          description = "MetadataSnapshotsDir specifies directory for metadata snapshots";
          type = (types.nullOr types.str);
        };
        "nodeLocalPools" = mkOption {
          description = "NodeLocalPools adds named node-local storage member sets.\n\nEach entry is currently realized as one operator-managed DaemonSet. One\nGarage Pod and one generated GarageNode identity run on every Kubernetes\nNode selected by the entry. Metadata and block data remain tied to that\nNode's HostPaths.\n\nThe DaemonSet is an implementation of the node-local contract, not a\nselectable workload mode. The operator coordinates activation, rollout,\nGarage layout membership, draining, and retirement.\n\nMultiple entries produce multiple DaemonSets; one entry is the normal\nsingle-DaemonSet deployment. Entries remain operator-managed even when\nstorage.layoutPolicy is Manual and are independent of the optional default\nStatefulSet/PVC group. Across all entries, at most 255 Kubernetes Nodes may\nbe selected. Garage's global layout accepts at most 256 positive-capacity\nroles across node-local, PVC, SMB, manual, external, and federated members;\nthose other members consume the same headroom and can make activation fail\nbelow the selector ceiling. At 255 live roles, a new node-local activation\nis eligible only for a locally proven retiring generated member. This is not\na reservation against independently operated federated sites.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPools"
                "name"
                [ "name" ]
            )
          );
          apply = attrsToList;
        };
        "nodeSelector" = mkOption {
          description = "NodeSelector for pod scheduling.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "podAnnotations" = mkOption {
          description = "PodAnnotations to add to pods.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "podDisruptionBudget" = mkOption {
          description = "PodDisruptionBudget configures one PDB covering the storage tier,\nincluding the default StatefulSet and all node-local pools.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStoragePodDisruptionBudget"
            )
          );
        };
        "podLabels" = mkOption {
          description = "PodLabels to add to pods.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "priorityClassName" = mkOption {
          description = "PriorityClassName for pods.";
          type = (types.nullOr types.str);
        };
        "pvcRetentionPolicy" = mkOption {
          description = "PVCRetentionPolicy controls PVC lifecycle when the StatefulSet is deleted or scaled down.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStoragePvcRetentionPolicy")
          );
        };
        "replicas" = mkOption {
          description = "Replicas controls only the default operator-managed StatefulSet/PVC group.\nSet it to 0 to disable that group. Ordinary Manual GarageNodes and\nnode-local-pool members remain independently declared; pool cardinality\nfollows each entry's selector.";
          type = (types.withMinimum 0 types.int);
        };
        "resources" = mkOption {
          description = "Resources specifies compute resources for the pod.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageResources")
          );
        };
        "rpcPublicAddr" = mkOption {
          description = "RPCPublicAddr is the externally-routable rpc_public_addr advertised by\nstorage pods so peers in other regions can dial them by hostname.\n\nWith replicas > 1 a single shared address only ever routes to one pod\n(e.g. behind a Tailscale VIP), leaving the others unreachable\ncross-region. Use an `{ordinal}` placeholder — the operator substitutes\neach pod's ordinal (0, 1, ...), symmetric with the gateway tier's\nrpcPublicAddr and with remoteClusters[].storageRpcEndpointTemplate on the\nconsuming side — so every pod advertises its own address. An address\nwithout the placeholder is rendered verbatim (fine for a single-replica\nstorage tier). When a per-node publicEndpoint (LoadBalancer perNode) is in\neffect, that address wins and this field is ignored.\n\nExample: \"us-east-storage-{ordinal}.example.ts.net:3901\"";
          type = (types.nullOr types.str);
        };
        "securityContext" = mkOption {
          description = "SecurityContext for the pod.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageSecurityContext")
          );
        };
        "tolerations" = mkOption {
          description = "Tolerations for pod scheduling.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageTolerations")
            )
          );
        };
        "topologySpreadConstraints" = mkOption {
          description = "TopologySpreadConstraints for pod scheduling.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageTopologySpreadConstraints"
              )
            )
          );
        };
      };

      config = {
        "affinity" = mkOverride 1002 null;
        "capacityReservePercent" = mkOverride 1002 null;
        "containerSecurityContext" = mkOverride 1002 null;
        "data" = mkOverride 1002 null;
        "dataFsync" = mkOverride 1002 null;
        "env" = mkOverride 1002 null;
        "envFrom" = mkOverride 1002 null;
        "layoutPolicy" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "metadataAutoSnapshotInterval" = mkOverride 1002 null;
        "metadataFsync" = mkOverride 1002 null;
        "metadataSnapshotsDir" = mkOverride 1002 null;
        "nodeLocalPools" = mkOverride 1002 null;
        "nodeSelector" = mkOverride 1002 null;
        "podAnnotations" = mkOverride 1002 null;
        "podDisruptionBudget" = mkOverride 1002 null;
        "podLabels" = mkOverride 1002 null;
        "priorityClassName" = mkOverride 1002 null;
        "pvcRetentionPolicy" = mkOverride 1002 null;
        "resources" = mkOverride 1002 null;
        "rpcPublicAddr" = mkOverride 1002 null;
        "securityContext" = mkOverride 1002 null;
        "tolerations" = mkOverride 1002 null;
        "topologySpreadConstraints" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinity" = {

      options = {
        "nodeAffinity" = mkOption {
          description = "Describes node affinity scheduling rules for the pod.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityNodeAffinity"
            )
          );
        };
        "podAffinity" = mkOption {
          description = "Describes pod affinity scheduling rules (e.g. co-locate this pod in the same node, zone, etc. as some other pod(s)).";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinity"
            )
          );
        };
        "podAntiAffinity" = mkOption {
          description = "Describes pod anti-affinity scheduling rules (e.g. avoid putting this pod in the same node, zone, etc. as some other pod(s)).";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinity"
            )
          );
        };
      };

      config = {
        "nodeAffinity" = mkOverride 1002 null;
        "podAffinity" = mkOverride 1002 null;
        "podAntiAffinity" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityNodeAffinity" = {

      options = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "The scheduler will prefer to schedule pods to nodes that satisfy\nthe affinity expressions specified by this field, but it may choose\na node that violates one or more of the expressions. The node that is\nmost preferred is the one with the greatest sum of weights, i.e.\nfor each node that meets all of the scheduling requirements (resource\nrequest, requiredDuringScheduling affinity expressions, etc.),\ncompute a sum by iterating through the elements of this field and adding\n\"weight\" to the sum if the node matches the corresponding matchExpressions; the\nnode(s) with the highest sum are the most preferred.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "If the affinity requirements specified by this field are not met at\nscheduling time, the pod will not be scheduled onto the node.\nIf the affinity requirements specified by this field cease to be met\nat some point during pod execution (e.g. due to an update), the system\nmay or may not try to eventually evict the pod from its node.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecution"
            )
          );
        };
      };

      config = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "preference" = mkOption {
            description = "A node selector term, associated with the corresponding weight.";
            type = (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreference"
            );
          };
          "weight" = mkOption {
            description = "Weight associated with matching the corresponding nodeSelectorTerm, in the range 1-100.";
            type = types.int;
          };
        };

        config = { };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreference" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "A list of node selector requirements by node's labels.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchExpressions"
                )
              )
            );
          };
          "matchFields" = mkOption {
            description = "A list of node selector requirements by node's fields.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchFields"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchExpressions" =
      {

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
            type = (types.nullOr (types.listOf types.str));
          };
        };

        config = {
          "values" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchFields" =
      {

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
            type = (types.nullOr (types.listOf types.str));
          };
        };

        config = {
          "values" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "nodeSelectorTerms" = mkOption {
            description = "Required. A list of node selector terms. The terms are ORed.";
            type = (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTerms"
              )
            );
          };
        };

        config = { };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTerms" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "A list of node selector requirements by node's labels.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchExpressions"
                )
              )
            );
          };
          "matchFields" = mkOption {
            description = "A list of node selector requirements by node's fields.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchFields"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchExpressions" =
      {

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
            type = (types.nullOr (types.listOf types.str));
          };
        };

        config = {
          "values" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchFields" =
      {

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
            type = (types.nullOr (types.listOf types.str));
          };
        };

        config = {
          "values" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinity" = {

      options = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "The scheduler will prefer to schedule pods to nodes that satisfy\nthe affinity expressions specified by this field, but it may choose\na node that violates one or more of the expressions. The node that is\nmost preferred is the one with the greatest sum of weights, i.e.\nfor each node that meets all of the scheduling requirements (resource\nrequest, requiredDuringScheduling affinity expressions, etc.),\ncompute a sum by iterating through the elements of this field and adding\n\"weight\" to the sum if the node has pods which matches the corresponding podAffinityTerm; the\nnode(s) with the highest sum are the most preferred.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "If the affinity requirements specified by this field are not met at\nscheduling time, the pod will not be scheduled onto the node.\nIf the affinity requirements specified by this field cease to be met\nat some point during pod execution (e.g. due to a pod label update), the\nsystem may or may not try to eventually evict the pod from its node.\nWhen there are multiple elements, the lists of nodes corresponding to each\npodAffinityTerm are intersected, i.e. all terms must be satisfied.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecution"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "podAffinityTerm" = mkOption {
            description = "Required. A pod affinity term, associated with the corresponding weight.";
            type = (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm"
            );
          };
          "weight" = mkOption {
            description = "weight associated with matching the corresponding podAffinityTerm,\nin the range 1-100.";
            type = types.int;
          };
        };

        config = { };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector"
              )
            );
          };
          "matchLabelKeys" = mkOption {
            description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "mismatchLabelKeys" = mkOption {
            description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "namespaceSelector" = mkOption {
            description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector"
              )
            );
          };
          "namespaces" = mkOption {
            description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
            type = (types.nullOr (types.listOf types.str));
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector"
              )
            );
          };
          "matchLabelKeys" = mkOption {
            description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "mismatchLabelKeys" = mkOption {
            description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "namespaceSelector" = mkOption {
            description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector"
              )
            );
          };
          "namespaces" = mkOption {
            description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
            type = (types.nullOr (types.listOf types.str));
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinity" = {

      options = {
        "preferredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "The scheduler will prefer to schedule pods to nodes that satisfy\nthe anti-affinity expressions specified by this field, but it may choose\na node that violates one or more of the expressions. The node that is\nmost preferred is the one with the greatest sum of weights, i.e.\nfor each node that meets all of the scheduling requirements (resource\nrequest, requiredDuringScheduling anti-affinity expressions, etc.),\ncompute a sum by iterating through the elements of this field and subtracting\n\"weight\" from the sum if the node has pods which matches the corresponding podAffinityTerm; the\nnode(s) with the highest sum are the most preferred.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecution"
              )
            )
          );
        };
        "requiredDuringSchedulingIgnoredDuringExecution" = mkOption {
          description = "If the anti-affinity requirements specified by this field are not met at\nscheduling time, the pod will not be scheduled onto the node.\nIf the anti-affinity requirements specified by this field cease to be met\nat some point during pod execution (e.g. due to a pod label update), the\nsystem may or may not try to eventually evict the pod from its node.\nWhen there are multiple elements, the lists of nodes corresponding to each\npodAffinityTerm are intersected, i.e. all terms must be satisfied.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecution"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "podAffinityTerm" = mkOption {
            description = "Required. A pod affinity term, associated with the corresponding weight.";
            type = (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm"
            );
          };
          "weight" = mkOption {
            description = "weight associated with matching the corresponding podAffinityTerm,\nin the range 1-100.";
            type = types.int;
          };
        };

        config = { };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector"
              )
            );
          };
          "matchLabelKeys" = mkOption {
            description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "mismatchLabelKeys" = mkOption {
            description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "namespaceSelector" = mkOption {
            description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector"
              )
            );
          };
          "namespaces" = mkOption {
            description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
            type = (types.nullOr (types.listOf types.str));
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector"
              )
            );
          };
          "matchLabelKeys" = mkOption {
            description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "mismatchLabelKeys" = mkOption {
            description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "namespaceSelector" = mkOption {
            description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector"
              )
            );
          };
          "namespaces" = mkOption {
            description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
            type = (types.nullOr (types.listOf types.str));
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageContainerSecurityContext" = {

      options = {
        "allowPrivilegeEscalation" = mkOption {
          description = "AllowPrivilegeEscalation controls whether a process can gain more\nprivileges than its parent process. This bool directly controls if\nthe no_new_privs flag will be set on the container process.\nAllowPrivilegeEscalation is true always when the container is:\n1) run as Privileged\n2) has CAP_SYS_ADMIN\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.bool);
        };
        "appArmorProfile" = mkOption {
          description = "appArmorProfile is the AppArmor options to use by this container. If set, this profile\noverrides the pod's appArmorProfile.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageContainerSecurityContextAppArmorProfile"
            )
          );
        };
        "capabilities" = mkOption {
          description = "The capabilities to add/drop when running containers.\nDefaults to the default set of capabilities granted by the container runtime.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageContainerSecurityContextCapabilities"
            )
          );
        };
        "privileged" = mkOption {
          description = "Run container in privileged mode.\nProcesses in privileged containers are essentially equivalent to root on the host.\nDefaults to false.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.bool);
        };
        "procMount" = mkOption {
          description = "procMount denotes the type of proc mount to use for the containers.\nThe default value is Default which uses the container runtime defaults for\nreadonly paths and masked paths.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.str);
        };
        "readOnlyRootFilesystem" = mkOption {
          description = "Whether this container has a read-only root filesystem.\nDefault is false.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.bool);
        };
        "runAsGroup" = mkOption {
          description = "The GID to run the entrypoint of the container process.\nUses runtime default if unset.\nMay also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.int);
        };
        "runAsNonRoot" = mkOption {
          description = "Indicates that the container must run as a non-root user.\nIf true, the Kubelet will validate the image at runtime to ensure that it\ndoes not run as UID 0 (root) and fail to start the container if it does.\nIf unset or false, no such validation will be performed.\nMay also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
          type = (types.nullOr types.bool);
        };
        "runAsUser" = mkOption {
          description = "The UID to run the entrypoint of the container process.\nDefaults to user specified in image metadata if unspecified.\nMay also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.int);
        };
        "seLinuxOptions" = mkOption {
          description = "The SELinux context to be applied to the container.\nIf unspecified, the container runtime will allocate a random SELinux context for each\ncontainer.  May also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageContainerSecurityContextSeLinuxOptions"
            )
          );
        };
        "seccompProfile" = mkOption {
          description = "The seccomp options to use by this container. If seccomp options are\nprovided at both the pod & container level, the container options\noverride the pod options.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageContainerSecurityContextSeccompProfile"
            )
          );
        };
        "windowsOptions" = mkOption {
          description = "The Windows specific settings applied to all containers.\nIf unspecified, the options from the PodSecurityContext will be used.\nIf set in both SecurityContext and PodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is linux.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageContainerSecurityContextWindowsOptions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageContainerSecurityContextAppArmorProfile" = {

      options = {
        "localhostProfile" = mkOption {
          description = "localhostProfile indicates a profile loaded on the node that should be used.\nThe profile must be preconfigured on the node to work.\nMust match the loaded name of the profile.\nMust be set if and only if type is \"Localhost\".";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageContainerSecurityContextCapabilities" = {

      options = {
        "add" = mkOption {
          description = "Added capabilities";
          type = (types.nullOr (types.listOf types.str));
        };
        "drop" = mkOption {
          description = "Removed capabilities";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "add" = mkOverride 1002 null;
        "drop" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageContainerSecurityContextSeLinuxOptions" = {

      options = {
        "level" = mkOption {
          description = "Level is SELinux level label that applies to the container.";
          type = (types.nullOr types.str);
        };
        "role" = mkOption {
          description = "Role is a SELinux role label that applies to the container.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is a SELinux type label that applies to the container.";
          type = (types.nullOr types.str);
        };
        "user" = mkOption {
          description = "User is a SELinux user label that applies to the container.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "level" = mkOverride 1002 null;
        "role" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
        "user" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageContainerSecurityContextSeccompProfile" = {

      options = {
        "localhostProfile" = mkOption {
          description = "localhostProfile indicates a profile defined in a file on the node should be used.\nThe profile must be preconfigured on the node to work.\nMust be a descending path, relative to the kubelet's configured seccomp profile location.\nMust be set if type is \"Localhost\". Must NOT be set for any other type.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageContainerSecurityContextWindowsOptions" = {

      options = {
        "gmsaCredentialSpec" = mkOption {
          description = "GMSACredentialSpec is where the GMSA admission webhook\n(https://github.com/kubernetes-sigs/windows-gmsa) inlines the contents of the\nGMSA credential spec named by the GMSACredentialSpecName field.";
          type = (types.nullOr types.str);
        };
        "gmsaCredentialSpecName" = mkOption {
          description = "GMSACredentialSpecName is the name of the GMSA credential spec to use.";
          type = (types.nullOr types.str);
        };
        "hostProcess" = mkOption {
          description = "HostProcess determines if a container should be run as a 'Host Process' container.\nAll of a Pod's containers must have the same effective HostProcess value\n(it is not allowed to have a mix of HostProcess containers and non-HostProcess containers).\nIn addition, if HostProcess is true then HostNetwork must also be set to true.";
          type = (types.nullOr types.bool);
        };
        "runAsUserName" = mkOption {
          description = "The UserName in Windows to run the entrypoint of the container process.\nDefaults to the user specified in image metadata if unspecified.\nMay also be set in PodSecurityContext. If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "gmsaCredentialSpec" = mkOverride 1002 null;
        "gmsaCredentialSpecName" = mkOverride 1002 null;
        "hostProcess" = mkOverride 1002 null;
        "runAsUserName" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageData" = {

      options = {
        "accessModes" = mkOption {
          description = "AccessModes for the PVC.";
          type = (types.nullOr (types.listOf types.str));
        };
        "annotations" = mkOption {
          description = "Annotations to set on the PVC.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "dataSourceRef" = mkOption {
          description = "DataSourceRef is the opt-in restore source for every generated PVC of this\nvolume role. Setting it copies the same same-namespace, non-core group\npopulator onto each Auto ordinal of this role; the populator must map\ntarget claim i to source-group member i. A core PVC or single-volume clone\nis not a safe source. Metadata and data are independent roles: restore\nidentity by setting this on metadata, object blocks by setting it on data.\nIt is immutable after the GarageCluster is created.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataDataSourceRef")
          );
        };
        "labels" = mkOption {
          description = "Labels to set on the PVC.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "paths" = mkOption {
          description = "Paths configures multiple data directories for multi-disk setups.\nOnly valid for data volumes — webhook rejects this on metadata volumes.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPaths")
            )
          );
        };
        "selector" = mkOption {
          description = "Selector matches pre-provisioned PVs for newly created claims. Kubernetes\ndoes not dynamically provision a PV when this is set; StorageClassName must\nalso match the target PV.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataSelector")
          );
        };
        "size" = mkOption {
          description = "Size of the volume.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "storageClassName" = mkOption {
          description = "StorageClassName for the PVC.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type specifies the volume type: PersistentVolumeClaim (default) or EmptyDir.";
          type = (
            types.nullOr (
              types.enum [
                "PersistentVolumeClaim"
                "EmptyDir"
              ]
            )
          );
        };
        "volumeClaimTemplateSpec" = mkOption {
          description = "VolumeClaimTemplateSpec is retained for API compatibility but is not\nsupported by operator-managed workloads. Admission rejects new or changed\nvalues; an unchanged legacy value is tolerated only so it can be removed.\nArbitrary claim-template dataSource or volumeName settings can clone a\nmetadata node_key or bind multiple Garage identities to one disk. Use the\nexplicit PVC fields above, or pre-provision a PVC and reference it from an\nordinary GarageNode storage existingClaim.\nDeprecated: use explicit PVC fields or GarageNode existingClaim.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataVolumeClaimTemplateSpec"
            )
          );
        };
      };

      config = {
        "accessModes" = mkOverride 1002 null;
        "annotations" = mkOverride 1002 null;
        "dataSourceRef" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "paths" = mkOverride 1002 null;
        "selector" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "storageClassName" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
        "volumeClaimTemplateSpec" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataDataSourceRef" = {

      options = {
        "apiGroup" = mkOption {
          description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
          type = (types.nullOr types.str);
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
          type = (types.nullOr types.str);
        };
      };

      config = {
        "apiGroup" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPaths" = {

      options = {
        "capacity" = mkOption {
          description = "Capacity of the drive (required unless readOnly).";
          type = (types.nullOr (types.either types.int types.str));
        };
        "path" = mkOption {
          description = "Path to the data directory.";
          type = types.str;
        };
        "readOnly" = mkOption {
          description = "ReadOnly marks the directory as a legacy read-only Garage data source for\nmigrations. This controls Garage's block placement; the Kubernetes mount\nremains writable so Garage can maintain its per-directory marker file.";
          type = (types.nullOr types.bool);
        };
        "volume" = mkOption {
          description = "Volume configuration for this data path.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolume")
          );
        };
      };

      config = {
        "capacity" = mkOverride 1002 null;
        "readOnly" = mkOverride 1002 null;
        "volume" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolume" = {

      options = {
        "accessModes" = mkOption {
          description = "AccessModes for the PVC.";
          type = (types.nullOr (types.listOf types.str));
        };
        "annotations" = mkOption {
          description = "Annotations to set on the PVC.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "dataSourceRef" = mkOption {
          description = "DataSourceRef is the opt-in restore source for this data path's PVC across\nevery Auto ordinal. Same group-populator contract as VolumeConfig.dataSourceRef.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolumeDataSourceRef"
            )
          );
        };
        "labels" = mkOption {
          description = "Labels to set on the PVC.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "selector" = mkOption {
          description = "Selector matches pre-provisioned PVs for newly created claims. Kubernetes\ndoes not dynamically provision a PV when this is set; StorageClassName must\nalso match the target PV.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolumeSelector"
            )
          );
        };
        "size" = mkOption {
          description = "Size of the volume (storage request).";
          type = (types.nullOr (types.either types.int types.str));
        };
        "storageClassName" = mkOption {
          description = "StorageClassName for the PVC.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type specifies the volume type.";
          type = (
            types.nullOr (
              types.enum [
                "PersistentVolumeClaim"
                "EmptyDir"
              ]
            )
          );
        };
        "volumeClaimTemplateSpec" = mkOption {
          description = "VolumeClaimTemplateSpec is retained for API compatibility but is not\nsupported by operator-managed workloads. Admission rejects new or changed\nvalues; an unchanged legacy value is tolerated only so it can be removed.\nUse the explicit PVC fields above, or pre-provision a PVC and reference it\nfrom an ordinary GarageNode storage existingClaim.\nDeprecated: use explicit PVC fields or GarageNode existingClaim.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpec"
            )
          );
        };
      };

      config = {
        "accessModes" = mkOverride 1002 null;
        "annotations" = mkOverride 1002 null;
        "dataSourceRef" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "selector" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "storageClassName" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
        "volumeClaimTemplateSpec" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolumeDataSourceRef" = {

      options = {
        "apiGroup" = mkOption {
          description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
          type = (types.nullOr types.str);
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
          type = (types.nullOr types.str);
        };
      };

      config = {
        "apiGroup" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolumeSelector" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolumeSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolumeSelectorMatchExpressions" = {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpec" = {

      options = {
        "accessModes" = mkOption {
          description = "accessModes contains the desired access modes the volume should have.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#access-modes-1";
          type = (types.nullOr (types.listOf types.str));
        };
        "dataSource" = mkOption {
          description = "dataSource field can be used to specify either:\n* An existing VolumeSnapshot object (snapshot.storage.k8s.io/VolumeSnapshot)\n* An existing PVC (PersistentVolumeClaim)\nIf the provisioner or an external controller can support the specified data source,\nit will create a new volume based on the contents of the specified data source.\ndataSource contents will be copied to dataSourceRef, and dataSourceRef contents will be\ncopied to dataSource when dataSourceRef.namespace is not specified.\nIf the namespace is specified, then dataSourceRef will not be copied to dataSource.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecDataSource"
            )
          );
        };
        "dataSourceRef" = mkOption {
          description = "dataSourceRef specifies the object from which to populate the volume with data, if a non-empty\nvolume is desired. This may be any object from a non-empty API group (non\ncore object) or a PersistentVolumeClaim object.\nWhen this field is specified, volume binding will only succeed if the type of\nthe specified object matches some installed volume populator or dynamic\nprovisioner.\nThis field will replace the functionality of the dataSource field and as such\nif both fields are non-empty, they must have the same value. For backwards\ncompatibility, when namespace isn't specified in dataSourceRef,\nboth fields (dataSource and dataSourceRef) will be set to the same\nvalue automatically if one of them is empty and the other is non-empty.\nWhen namespace is specified in dataSourceRef,\ndataSource isn't set to the same value and must be empty.\nThere are three important differences between dataSource and dataSourceRef:\n* While dataSource only allows two specific types of objects, dataSourceRef\n  allows any non-core object, as well as PersistentVolumeClaim objects.\n* While dataSource ignores disallowed values (dropping them), dataSourceRef\n  preserves all values, and generates an error if a disallowed value is\n  specified.\n* While dataSource only allows local objects, dataSourceRef allows objects\n  in any namespaces.\n(Alpha) Using the namespace field of dataSourceRef requires the CrossNamespaceVolumeDataSource feature gate to be enabled.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecDataSourceRef"
            )
          );
        };
        "resources" = mkOption {
          description = "resources represents the minimum resources the volume should have.\nUsers are allowed to specify resource requirements\nthat are lower than previous value but must still be higher than capacity recorded in the\nstatus field of the claim.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#resources";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecResources"
            )
          );
        };
        "selector" = mkOption {
          description = "selector is a label query over volumes to consider for binding.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecSelector"
            )
          );
        };
        "storageClassName" = mkOption {
          description = "storageClassName is the name of the StorageClass required by the claim.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#class-1";
          type = (types.nullOr types.str);
        };
        "volumeAttributesClassName" = mkOption {
          description = "volumeAttributesClassName may be used to set the VolumeAttributesClass used by this claim.\nIf specified, the CSI driver will create or update the volume with the attributes defined\nin the corresponding VolumeAttributesClass. This has a different purpose than storageClassName,\nit can be changed after the claim is created. An empty string or nil value indicates that no\nVolumeAttributesClass will be applied to the claim. If the claim enters an Infeasible error state,\nthis field can be reset to its previous value (including nil) to cancel the modification.\nIf the resource referred to by volumeAttributesClass does not exist, this PersistentVolumeClaim will be\nset to a Pending state, as reflected by the modifyVolumeStatus field, until such as a resource\nexists.\nMore info: https://kubernetes.io/docs/concepts/storage/volume-attributes-classes/";
          type = (types.nullOr types.str);
        };
        "volumeMode" = mkOption {
          description = "volumeMode defines what type of volume is required by the claim.\nValue of Filesystem is implied when not included in claim spec.";
          type = (types.nullOr types.str);
        };
        "volumeName" = mkOption {
          description = "volumeName is the binding reference to the PersistentVolume backing this claim.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecDataSource" =
      {

        options = {
          "apiGroup" = mkOption {
            description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
            type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecDataSourceRef" =
      {

        options = {
          "apiGroup" = mkOption {
            description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
            type = (types.nullOr types.str);
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
            type = (types.nullOr types.str);
          };
        };

        config = {
          "apiGroup" = mkOverride 1002 null;
          "namespace" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecResources" =
      {

        options = {
          "limits" = mkOption {
            description = "Limits describes the maximum amount of compute resources allowed.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
            type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
          };
          "requests" = mkOption {
            description = "Requests describes the minimum amount of compute resources required.\nIf Requests is omitted for a container, it defaults to Limits if that is explicitly specified,\notherwise to an implementation-defined value. Requests cannot exceed Limits.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
            type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
          };
        };

        config = {
          "limits" = mkOverride 1002 null;
          "requests" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataPathsVolumeVolumeClaimTemplateSpecSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataSelector" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataSelectorMatchExpressions" = {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataVolumeClaimTemplateSpec" = {

      options = {
        "accessModes" = mkOption {
          description = "accessModes contains the desired access modes the volume should have.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#access-modes-1";
          type = (types.nullOr (types.listOf types.str));
        };
        "dataSource" = mkOption {
          description = "dataSource field can be used to specify either:\n* An existing VolumeSnapshot object (snapshot.storage.k8s.io/VolumeSnapshot)\n* An existing PVC (PersistentVolumeClaim)\nIf the provisioner or an external controller can support the specified data source,\nit will create a new volume based on the contents of the specified data source.\ndataSource contents will be copied to dataSourceRef, and dataSourceRef contents will be\ncopied to dataSource when dataSourceRef.namespace is not specified.\nIf the namespace is specified, then dataSourceRef will not be copied to dataSource.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataVolumeClaimTemplateSpecDataSource"
            )
          );
        };
        "dataSourceRef" = mkOption {
          description = "dataSourceRef specifies the object from which to populate the volume with data, if a non-empty\nvolume is desired. This may be any object from a non-empty API group (non\ncore object) or a PersistentVolumeClaim object.\nWhen this field is specified, volume binding will only succeed if the type of\nthe specified object matches some installed volume populator or dynamic\nprovisioner.\nThis field will replace the functionality of the dataSource field and as such\nif both fields are non-empty, they must have the same value. For backwards\ncompatibility, when namespace isn't specified in dataSourceRef,\nboth fields (dataSource and dataSourceRef) will be set to the same\nvalue automatically if one of them is empty and the other is non-empty.\nWhen namespace is specified in dataSourceRef,\ndataSource isn't set to the same value and must be empty.\nThere are three important differences between dataSource and dataSourceRef:\n* While dataSource only allows two specific types of objects, dataSourceRef\n  allows any non-core object, as well as PersistentVolumeClaim objects.\n* While dataSource ignores disallowed values (dropping them), dataSourceRef\n  preserves all values, and generates an error if a disallowed value is\n  specified.\n* While dataSource only allows local objects, dataSourceRef allows objects\n  in any namespaces.\n(Alpha) Using the namespace field of dataSourceRef requires the CrossNamespaceVolumeDataSource feature gate to be enabled.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataVolumeClaimTemplateSpecDataSourceRef"
            )
          );
        };
        "resources" = mkOption {
          description = "resources represents the minimum resources the volume should have.\nUsers are allowed to specify resource requirements\nthat are lower than previous value but must still be higher than capacity recorded in the\nstatus field of the claim.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#resources";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataVolumeClaimTemplateSpecResources"
            )
          );
        };
        "selector" = mkOption {
          description = "selector is a label query over volumes to consider for binding.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataVolumeClaimTemplateSpecSelector"
            )
          );
        };
        "storageClassName" = mkOption {
          description = "storageClassName is the name of the StorageClass required by the claim.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#class-1";
          type = (types.nullOr types.str);
        };
        "volumeAttributesClassName" = mkOption {
          description = "volumeAttributesClassName may be used to set the VolumeAttributesClass used by this claim.\nIf specified, the CSI driver will create or update the volume with the attributes defined\nin the corresponding VolumeAttributesClass. This has a different purpose than storageClassName,\nit can be changed after the claim is created. An empty string or nil value indicates that no\nVolumeAttributesClass will be applied to the claim. If the claim enters an Infeasible error state,\nthis field can be reset to its previous value (including nil) to cancel the modification.\nIf the resource referred to by volumeAttributesClass does not exist, this PersistentVolumeClaim will be\nset to a Pending state, as reflected by the modifyVolumeStatus field, until such as a resource\nexists.\nMore info: https://kubernetes.io/docs/concepts/storage/volume-attributes-classes/";
          type = (types.nullOr types.str);
        };
        "volumeMode" = mkOption {
          description = "volumeMode defines what type of volume is required by the claim.\nValue of Filesystem is implied when not included in claim spec.";
          type = (types.nullOr types.str);
        };
        "volumeName" = mkOption {
          description = "volumeName is the binding reference to the PersistentVolume backing this claim.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataVolumeClaimTemplateSpecDataSource" = {

      options = {
        "apiGroup" = mkOption {
          description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataVolumeClaimTemplateSpecDataSourceRef" = {

      options = {
        "apiGroup" = mkOption {
          description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
          type = (types.nullOr types.str);
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
          type = (types.nullOr types.str);
        };
      };

      config = {
        "apiGroup" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataVolumeClaimTemplateSpecResources" = {

      options = {
        "limits" = mkOption {
          description = "Limits describes the maximum amount of compute resources allowed.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
        };
        "requests" = mkOption {
          description = "Requests describes the minimum amount of compute resources required.\nIf Requests is omitted for a container, it defaults to Limits if that is explicitly specified,\notherwise to an implementation-defined value. Requests cannot exceed Limits.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
        };
      };

      config = {
        "limits" = mkOverride 1002 null;
        "requests" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataVolumeClaimTemplateSpecSelector" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataVolumeClaimTemplateSpecSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageDataVolumeClaimTemplateSpecSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnv" = {

      options = {
        "name" = mkOption {
          description = "Name of the environment variable.\nMay consist of any printable ASCII characters except '='.";
          type = types.str;
        };
        "value" = mkOption {
          description = "Variable references $(VAR_NAME) are expanded\nusing the previously defined environment variables in the container and\nany service environment variables. If a variable cannot be resolved,\nthe reference in the input string will be unchanged. Double $$ are reduced\nto a single $, which allows for escaping the $(VAR_NAME) syntax: i.e.\n\"$$(VAR_NAME)\" will produce the string literal \"$(VAR_NAME)\".\nEscaped references will never be expanded, regardless of whether the variable\nexists or not.\nDefaults to \"\".";
          type = (types.nullOr types.str);
        };
        "valueFrom" = mkOption {
          description = "Source for the environment variable's value. Cannot be used if value is not empty.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnvValueFrom")
          );
        };
      };

      config = {
        "value" = mkOverride 1002 null;
        "valueFrom" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnvFrom" = {

      options = {
        "configMapRef" = mkOption {
          description = "The ConfigMap to select from";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnvFromConfigMapRef"
            )
          );
        };
        "prefix" = mkOption {
          description = "Optional text to prepend to the name of each environment variable.\nMay consist of any printable ASCII characters except '='.";
          type = (types.nullOr types.str);
        };
        "secretRef" = mkOption {
          description = "The Secret to select from";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnvFromSecretRef")
          );
        };
      };

      config = {
        "configMapRef" = mkOverride 1002 null;
        "prefix" = mkOverride 1002 null;
        "secretRef" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnvFromConfigMapRef" = {

      options = {
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the ConfigMap must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnvFromSecretRef" = {

      options = {
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnvValueFrom" = {

      options = {
        "configMapKeyRef" = mkOption {
          description = "Selects a key of a ConfigMap.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnvValueFromConfigMapKeyRef"
            )
          );
        };
        "fieldRef" = mkOption {
          description = "Selects a field of the pod: supports metadata.name, metadata.namespace, `metadata.labels['<KEY>']`, `metadata.annotations['<KEY>']`,\nspec.nodeName, spec.serviceAccountName, status.hostIP, status.podIP, status.podIPs.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnvValueFromFieldRef"
            )
          );
        };
        "fileKeyRef" = mkOption {
          description = "FileKeyRef selects a key of the env file.\nRequires the EnvFiles feature gate to be enabled.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnvValueFromFileKeyRef"
            )
          );
        };
        "resourceFieldRef" = mkOption {
          description = "Selects a resource of the container: only resources limits and requests\n(limits.cpu, limits.memory, limits.ephemeral-storage, requests.cpu, requests.memory and requests.ephemeral-storage) are currently supported.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnvValueFromResourceFieldRef"
            )
          );
        };
        "secretKeyRef" = mkOption {
          description = "Selects a key of a secret in the pod's namespace";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnvValueFromSecretKeyRef"
            )
          );
        };
      };

      config = {
        "configMapKeyRef" = mkOverride 1002 null;
        "fieldRef" = mkOverride 1002 null;
        "fileKeyRef" = mkOverride 1002 null;
        "resourceFieldRef" = mkOverride 1002 null;
        "secretKeyRef" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnvValueFromConfigMapKeyRef" = {

      options = {
        "key" = mkOption {
          description = "The key to select from the ConfigMap's Data field.\nKeys in the BinaryData field are not currently propagated to container env vars.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the ConfigMap or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnvValueFromFieldRef" = {

      options = {
        "apiVersion" = mkOption {
          description = "Version of the schema the FieldPath is written in terms of, defaults to \"v1\".";
          type = (types.nullOr types.str);
        };
        "fieldPath" = mkOption {
          description = "Path of the field to select in the specified API version.";
          type = types.str;
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnvValueFromFileKeyRef" = {

      options = {
        "key" = mkOption {
          description = "The key within the env file. An invalid key will prevent the pod from starting.\nThe keys defined within a source may consist of any printable ASCII characters except '='.\nDuring Alpha stage of the EnvFiles feature gate, the key size is limited to 128 characters.";
          type = types.str;
        };
        "optional" = mkOption {
          description = "Specify whether the file or its key must be defined. If the file or key\ndoes not exist, then the env var is not published.\nIf optional is set to true and the specified key does not exist,\nthe environment variable will not be set in the Pod's containers.\n\nIf optional is set to false and the specified key does not exist,\nan error will be returned during Pod creation.";
          type = (types.nullOr types.bool);
        };
        "path" = mkOption {
          description = "The path within the volume from which to select the file.\nMust be relative and may not contain the '..' path or start with '..'.";
          type = types.str;
        };
        "volumeName" = mkOption {
          description = "The name of the volume mount containing the env file.";
          type = types.str;
        };
      };

      config = {
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnvValueFromResourceFieldRef" = {

      options = {
        "containerName" = mkOption {
          description = "Container name: required for volumes, optional for env vars";
          type = (types.nullOr types.str);
        };
        "divisor" = mkOption {
          description = "Specifies the output format of the exposed resources, defaults to \"1\"";
          type = (types.nullOr (types.either types.int types.str));
        };
        "resource" = mkOption {
          description = "Required: resource to select";
          type = types.str;
        };
      };

      config = {
        "containerName" = mkOverride 1002 null;
        "divisor" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageEnvValueFromSecretKeyRef" = {

      options = {
        "key" = mkOption {
          description = "The key of the secret to select from.  Must be a valid secret key.";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret or its key must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadata" = {

      options = {
        "accessModes" = mkOption {
          description = "AccessModes for the PVC.";
          type = (types.nullOr (types.listOf types.str));
        };
        "annotations" = mkOption {
          description = "Annotations to set on the PVC.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "dataSourceRef" = mkOption {
          description = "DataSourceRef is the opt-in restore source for every generated PVC of this\nvolume role. Setting it copies the same same-namespace, non-core group\npopulator onto each Auto ordinal of this role; the populator must map\ntarget claim i to source-group member i. A core PVC or single-volume clone\nis not a safe source. Metadata and data are independent roles: restore\nidentity by setting this on metadata, object blocks by setting it on data.\nIt is immutable after the GarageCluster is created.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataDataSourceRef"
            )
          );
        };
        "labels" = mkOption {
          description = "Labels to set on the PVC.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "paths" = mkOption {
          description = "Paths configures multiple data directories for multi-disk setups.\nOnly valid for data volumes — webhook rejects this on metadata volumes.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPaths")
            )
          );
        };
        "selector" = mkOption {
          description = "Selector matches pre-provisioned PVs for newly created claims. Kubernetes\ndoes not dynamically provision a PV when this is set; StorageClassName must\nalso match the target PV.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataSelector")
          );
        };
        "size" = mkOption {
          description = "Size of the volume.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "storageClassName" = mkOption {
          description = "StorageClassName for the PVC.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type specifies the volume type: PersistentVolumeClaim (default) or EmptyDir.";
          type = (
            types.nullOr (
              types.enum [
                "PersistentVolumeClaim"
                "EmptyDir"
              ]
            )
          );
        };
        "volumeClaimTemplateSpec" = mkOption {
          description = "VolumeClaimTemplateSpec is retained for API compatibility but is not\nsupported by operator-managed workloads. Admission rejects new or changed\nvalues; an unchanged legacy value is tolerated only so it can be removed.\nArbitrary claim-template dataSource or volumeName settings can clone a\nmetadata node_key or bind multiple Garage identities to one disk. Use the\nexplicit PVC fields above, or pre-provision a PVC and reference it from an\nordinary GarageNode storage existingClaim.\nDeprecated: use explicit PVC fields or GarageNode existingClaim.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpec"
            )
          );
        };
      };

      config = {
        "accessModes" = mkOverride 1002 null;
        "annotations" = mkOverride 1002 null;
        "dataSourceRef" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "paths" = mkOverride 1002 null;
        "selector" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "storageClassName" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
        "volumeClaimTemplateSpec" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataDataSourceRef" = {

      options = {
        "apiGroup" = mkOption {
          description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
          type = (types.nullOr types.str);
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
          type = (types.nullOr types.str);
        };
      };

      config = {
        "apiGroup" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPaths" = {

      options = {
        "capacity" = mkOption {
          description = "Capacity of the drive (required unless readOnly).";
          type = (types.nullOr (types.either types.int types.str));
        };
        "path" = mkOption {
          description = "Path to the data directory.";
          type = types.str;
        };
        "readOnly" = mkOption {
          description = "ReadOnly marks the directory as a legacy read-only Garage data source for\nmigrations. This controls Garage's block placement; the Kubernetes mount\nremains writable so Garage can maintain its per-directory marker file.";
          type = (types.nullOr types.bool);
        };
        "volume" = mkOption {
          description = "Volume configuration for this data path.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolume"
            )
          );
        };
      };

      config = {
        "capacity" = mkOverride 1002 null;
        "readOnly" = mkOverride 1002 null;
        "volume" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolume" = {

      options = {
        "accessModes" = mkOption {
          description = "AccessModes for the PVC.";
          type = (types.nullOr (types.listOf types.str));
        };
        "annotations" = mkOption {
          description = "Annotations to set on the PVC.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "dataSourceRef" = mkOption {
          description = "DataSourceRef is the opt-in restore source for this data path's PVC across\nevery Auto ordinal. Same group-populator contract as VolumeConfig.dataSourceRef.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolumeDataSourceRef"
            )
          );
        };
        "labels" = mkOption {
          description = "Labels to set on the PVC.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "selector" = mkOption {
          description = "Selector matches pre-provisioned PVs for newly created claims. Kubernetes\ndoes not dynamically provision a PV when this is set; StorageClassName must\nalso match the target PV.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolumeSelector"
            )
          );
        };
        "size" = mkOption {
          description = "Size of the volume (storage request).";
          type = (types.nullOr (types.either types.int types.str));
        };
        "storageClassName" = mkOption {
          description = "StorageClassName for the PVC.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type specifies the volume type.";
          type = (
            types.nullOr (
              types.enum [
                "PersistentVolumeClaim"
                "EmptyDir"
              ]
            )
          );
        };
        "volumeClaimTemplateSpec" = mkOption {
          description = "VolumeClaimTemplateSpec is retained for API compatibility but is not\nsupported by operator-managed workloads. Admission rejects new or changed\nvalues; an unchanged legacy value is tolerated only so it can be removed.\nUse the explicit PVC fields above, or pre-provision a PVC and reference it\nfrom an ordinary GarageNode storage existingClaim.\nDeprecated: use explicit PVC fields or GarageNode existingClaim.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolumeVolumeClaimTemplateSpec"
            )
          );
        };
      };

      config = {
        "accessModes" = mkOverride 1002 null;
        "annotations" = mkOverride 1002 null;
        "dataSourceRef" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "selector" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "storageClassName" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
        "volumeClaimTemplateSpec" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolumeDataSourceRef" = {

      options = {
        "apiGroup" = mkOption {
          description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
          type = (types.nullOr types.str);
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
          type = (types.nullOr types.str);
        };
      };

      config = {
        "apiGroup" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolumeSelector" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolumeSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolumeSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolumeVolumeClaimTemplateSpec" =
      {

        options = {
          "accessModes" = mkOption {
            description = "accessModes contains the desired access modes the volume should have.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#access-modes-1";
            type = (types.nullOr (types.listOf types.str));
          };
          "dataSource" = mkOption {
            description = "dataSource field can be used to specify either:\n* An existing VolumeSnapshot object (snapshot.storage.k8s.io/VolumeSnapshot)\n* An existing PVC (PersistentVolumeClaim)\nIf the provisioner or an external controller can support the specified data source,\nit will create a new volume based on the contents of the specified data source.\ndataSource contents will be copied to dataSourceRef, and dataSourceRef contents will be\ncopied to dataSource when dataSourceRef.namespace is not specified.\nIf the namespace is specified, then dataSourceRef will not be copied to dataSource.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolumeVolumeClaimTemplateSpecDataSource"
              )
            );
          };
          "dataSourceRef" = mkOption {
            description = "dataSourceRef specifies the object from which to populate the volume with data, if a non-empty\nvolume is desired. This may be any object from a non-empty API group (non\ncore object) or a PersistentVolumeClaim object.\nWhen this field is specified, volume binding will only succeed if the type of\nthe specified object matches some installed volume populator or dynamic\nprovisioner.\nThis field will replace the functionality of the dataSource field and as such\nif both fields are non-empty, they must have the same value. For backwards\ncompatibility, when namespace isn't specified in dataSourceRef,\nboth fields (dataSource and dataSourceRef) will be set to the same\nvalue automatically if one of them is empty and the other is non-empty.\nWhen namespace is specified in dataSourceRef,\ndataSource isn't set to the same value and must be empty.\nThere are three important differences between dataSource and dataSourceRef:\n* While dataSource only allows two specific types of objects, dataSourceRef\n  allows any non-core object, as well as PersistentVolumeClaim objects.\n* While dataSource ignores disallowed values (dropping them), dataSourceRef\n  preserves all values, and generates an error if a disallowed value is\n  specified.\n* While dataSource only allows local objects, dataSourceRef allows objects\n  in any namespaces.\n(Alpha) Using the namespace field of dataSourceRef requires the CrossNamespaceVolumeDataSource feature gate to be enabled.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolumeVolumeClaimTemplateSpecDataSourceRef"
              )
            );
          };
          "resources" = mkOption {
            description = "resources represents the minimum resources the volume should have.\nUsers are allowed to specify resource requirements\nthat are lower than previous value but must still be higher than capacity recorded in the\nstatus field of the claim.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#resources";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolumeVolumeClaimTemplateSpecResources"
              )
            );
          };
          "selector" = mkOption {
            description = "selector is a label query over volumes to consider for binding.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolumeVolumeClaimTemplateSpecSelector"
              )
            );
          };
          "storageClassName" = mkOption {
            description = "storageClassName is the name of the StorageClass required by the claim.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#class-1";
            type = (types.nullOr types.str);
          };
          "volumeAttributesClassName" = mkOption {
            description = "volumeAttributesClassName may be used to set the VolumeAttributesClass used by this claim.\nIf specified, the CSI driver will create or update the volume with the attributes defined\nin the corresponding VolumeAttributesClass. This has a different purpose than storageClassName,\nit can be changed after the claim is created. An empty string or nil value indicates that no\nVolumeAttributesClass will be applied to the claim. If the claim enters an Infeasible error state,\nthis field can be reset to its previous value (including nil) to cancel the modification.\nIf the resource referred to by volumeAttributesClass does not exist, this PersistentVolumeClaim will be\nset to a Pending state, as reflected by the modifyVolumeStatus field, until such as a resource\nexists.\nMore info: https://kubernetes.io/docs/concepts/storage/volume-attributes-classes/";
            type = (types.nullOr types.str);
          };
          "volumeMode" = mkOption {
            description = "volumeMode defines what type of volume is required by the claim.\nValue of Filesystem is implied when not included in claim spec.";
            type = (types.nullOr types.str);
          };
          "volumeName" = mkOption {
            description = "volumeName is the binding reference to the PersistentVolume backing this claim.";
            type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolumeVolumeClaimTemplateSpecDataSource" =
      {

        options = {
          "apiGroup" = mkOption {
            description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
            type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolumeVolumeClaimTemplateSpecDataSourceRef" =
      {

        options = {
          "apiGroup" = mkOption {
            description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
            type = (types.nullOr types.str);
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
            type = (types.nullOr types.str);
          };
        };

        config = {
          "apiGroup" = mkOverride 1002 null;
          "namespace" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolumeVolumeClaimTemplateSpecResources" =
      {

        options = {
          "limits" = mkOption {
            description = "Limits describes the maximum amount of compute resources allowed.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
            type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
          };
          "requests" = mkOption {
            description = "Requests describes the minimum amount of compute resources required.\nIf Requests is omitted for a container, it defaults to Limits if that is explicitly specified,\notherwise to an implementation-defined value. Requests cannot exceed Limits.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
            type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
          };
        };

        config = {
          "limits" = mkOverride 1002 null;
          "requests" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolumeVolumeClaimTemplateSpecSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolumeVolumeClaimTemplateSpecSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataPathsVolumeVolumeClaimTemplateSpecSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataSelector" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataSelectorMatchExpressions" = {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpec" = {

      options = {
        "accessModes" = mkOption {
          description = "accessModes contains the desired access modes the volume should have.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#access-modes-1";
          type = (types.nullOr (types.listOf types.str));
        };
        "dataSource" = mkOption {
          description = "dataSource field can be used to specify either:\n* An existing VolumeSnapshot object (snapshot.storage.k8s.io/VolumeSnapshot)\n* An existing PVC (PersistentVolumeClaim)\nIf the provisioner or an external controller can support the specified data source,\nit will create a new volume based on the contents of the specified data source.\ndataSource contents will be copied to dataSourceRef, and dataSourceRef contents will be\ncopied to dataSource when dataSourceRef.namespace is not specified.\nIf the namespace is specified, then dataSourceRef will not be copied to dataSource.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecDataSource"
            )
          );
        };
        "dataSourceRef" = mkOption {
          description = "dataSourceRef specifies the object from which to populate the volume with data, if a non-empty\nvolume is desired. This may be any object from a non-empty API group (non\ncore object) or a PersistentVolumeClaim object.\nWhen this field is specified, volume binding will only succeed if the type of\nthe specified object matches some installed volume populator or dynamic\nprovisioner.\nThis field will replace the functionality of the dataSource field and as such\nif both fields are non-empty, they must have the same value. For backwards\ncompatibility, when namespace isn't specified in dataSourceRef,\nboth fields (dataSource and dataSourceRef) will be set to the same\nvalue automatically if one of them is empty and the other is non-empty.\nWhen namespace is specified in dataSourceRef,\ndataSource isn't set to the same value and must be empty.\nThere are three important differences between dataSource and dataSourceRef:\n* While dataSource only allows two specific types of objects, dataSourceRef\n  allows any non-core object, as well as PersistentVolumeClaim objects.\n* While dataSource ignores disallowed values (dropping them), dataSourceRef\n  preserves all values, and generates an error if a disallowed value is\n  specified.\n* While dataSource only allows local objects, dataSourceRef allows objects\n  in any namespaces.\n(Alpha) Using the namespace field of dataSourceRef requires the CrossNamespaceVolumeDataSource feature gate to be enabled.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecDataSourceRef"
            )
          );
        };
        "resources" = mkOption {
          description = "resources represents the minimum resources the volume should have.\nUsers are allowed to specify resource requirements\nthat are lower than previous value but must still be higher than capacity recorded in the\nstatus field of the claim.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#resources";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecResources"
            )
          );
        };
        "selector" = mkOption {
          description = "selector is a label query over volumes to consider for binding.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecSelector"
            )
          );
        };
        "storageClassName" = mkOption {
          description = "storageClassName is the name of the StorageClass required by the claim.\nMore info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#class-1";
          type = (types.nullOr types.str);
        };
        "volumeAttributesClassName" = mkOption {
          description = "volumeAttributesClassName may be used to set the VolumeAttributesClass used by this claim.\nIf specified, the CSI driver will create or update the volume with the attributes defined\nin the corresponding VolumeAttributesClass. This has a different purpose than storageClassName,\nit can be changed after the claim is created. An empty string or nil value indicates that no\nVolumeAttributesClass will be applied to the claim. If the claim enters an Infeasible error state,\nthis field can be reset to its previous value (including nil) to cancel the modification.\nIf the resource referred to by volumeAttributesClass does not exist, this PersistentVolumeClaim will be\nset to a Pending state, as reflected by the modifyVolumeStatus field, until such as a resource\nexists.\nMore info: https://kubernetes.io/docs/concepts/storage/volume-attributes-classes/";
          type = (types.nullOr types.str);
        };
        "volumeMode" = mkOption {
          description = "volumeMode defines what type of volume is required by the claim.\nValue of Filesystem is implied when not included in claim spec.";
          type = (types.nullOr types.str);
        };
        "volumeName" = mkOption {
          description = "volumeName is the binding reference to the PersistentVolume backing this claim.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecDataSource" = {

      options = {
        "apiGroup" = mkOption {
          description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecDataSourceRef" =
      {

        options = {
          "apiGroup" = mkOption {
            description = "APIGroup is the group for the resource being referenced.\nIf APIGroup is not specified, the specified Kind must be in the core API group.\nFor any other third-party types, APIGroup is required.";
            type = (types.nullOr types.str);
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
            type = (types.nullOr types.str);
          };
        };

        config = {
          "apiGroup" = mkOverride 1002 null;
          "namespace" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecResources" = {

      options = {
        "limits" = mkOption {
          description = "Limits describes the maximum amount of compute resources allowed.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
        };
        "requests" = mkOption {
          description = "Requests describes the minimum amount of compute resources required.\nIf Requests is omitted for a container, it defaults to Limits if that is explicitly specified,\notherwise to an implementation-defined value. Requests cannot exceed Limits.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
        };
      };

      config = {
        "limits" = mkOverride 1002 null;
        "requests" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecSelector" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageMetadataVolumeClaimTemplateSpecSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPools" = {

      options = {
        "capacity" = mkOption {
          description = "Capacity is the uniform effective capacity advertised to the Garage\nlayout for every generated role in this pool; it is not aggregate pool\ncapacity. HostPath volumes have no PVC request\nfrom which to derive it. For multi-disk pools this may not exceed the sum\nof writable dataPaths capacities.";
          type = (types.either types.int types.str);
        };
        "data" = mkOption {
          description = "Data is the single node-local block-data directory, mounted at\n/data/data. Mutually exclusive with dataPaths.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsData")
          );
        };
        "dataPaths" = mkOption {
          description = "DataPaths configures multiple node-local Garage data directories.\nMutually exclusive with data. Every writable entry needs a capacity;\nread-only entries are retained for Garage's staged disk migration flow.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsDataPaths"
              )
            )
          );
        };
        "metadata" = mkOption {
          description = "Metadata is the node-local directory that stores Garage's durable\nnode_key and metadata database. Its hostPath is immutable after pool\ncreation because changing it changes every selected node's identity.";
          type = (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsMetadata");
        };
        "name" = mkOption {
          description = "Name identifies this operator-managed membership set and is used in child\nresource names, labels, and Garage layout tags. It is not a Garage identity,\nreplication group, quorum, zone, or failure domain.";
          type = (types.withMaxLength 63 types.str);
        };
        "network" = mkOption {
          description = "Network configures identity-specific connectivity for this pool.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsNetwork"
            )
          );
        };
        "podTemplate" = mkOption {
          description = "PodTemplate carries pod settings that do not change membership. Required\nnode affinity is intentionally unavailable: selector is the only durable\nmembership boundary.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplate"
            )
          );
        };
        "selector" = mkOption {
          description = "Selector chooses the Kubernetes Nodes that own a persistent Garage\nidentity in this pool. It is membership, not a pod scheduling hint.\nA Node may match at most one node-local pool in a GarageCluster.";
          type = (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsSelector");
        };
      };

      config = {
        "data" = mkOverride 1002 null;
        "dataPaths" = mkOverride 1002 null;
        "network" = mkOverride 1002 null;
        "podTemplate" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsData" = {

      options = {
        "hostPath" = mkOption {
          description = "HostPath is an absolute directory on each selected Kubernetes Node.";
          type = types.str;
        };
        "hostPathType" = mkOption {
          description = "HostPathType controls whether Kubernetes creates a missing directory.\nDirectory (the production default) also requires a pre-provisioned\n.garage-volume-id file inside HostPath. The pool workload mounts that\nmarker separately as HostPath type File, so an unmounted but still-present\nroot-filesystem directory cannot silently receive Garage data.\nDirectoryOrCreate skips this marker guarantee and is intended for tests or\nexplicitly ephemeral provisioning.";
          type = (
            types.nullOr (
              types.enum [
                "Directory"
                "DirectoryOrCreate"
              ]
            )
          );
        };
      };

      config = {
        "hostPathType" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsDataPaths" = {

      options = {
        "capacity" = mkOption {
          description = "Capacity is the per-directory Garage capacity. Required unless readOnly.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "hostPath" = mkOption {
          description = "HostPath is the absolute directory on each selected Kubernetes Node.";
          type = types.str;
        };
        "hostPathType" = mkOption {
          description = "HostPathType controls whether Kubernetes creates a missing directory.\nDirectory also requires a pre-provisioned .garage-volume-id file inside\nHostPath; see HostPathVolumeConfig. DirectoryOrCreate skips that production\nmount check and is intended for tests or explicitly ephemeral provisioning.";
          type = (
            types.nullOr (
              types.enum [
                "Directory"
                "DirectoryOrCreate"
              ]
            )
          );
        };
        "path" = mkOption {
          description = "Path is the absolute in-container mount path used in garage.toml.";
          type = types.str;
        };
        "readOnly" = mkOption {
          description = "ReadOnly removes this path from new block placement while keeping it\nmounted for Garage's staged disk migration.";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "capacity" = mkOverride 1002 null;
        "hostPathType" = mkOverride 1002 null;
        "readOnly" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsMetadata" = {

      options = {
        "hostPath" = mkOption {
          description = "HostPath is an absolute directory on each selected Kubernetes Node.";
          type = types.str;
        };
        "hostPathType" = mkOption {
          description = "HostPathType controls whether Kubernetes creates a missing directory.\nDirectory (the production default) also requires a pre-provisioned\n.garage-volume-id file inside HostPath. The pool workload mounts that\nmarker separately as HostPath type File, so an unmounted but still-present\nroot-filesystem directory cannot silently receive Garage data.\nDirectoryOrCreate skips this marker guarantee and is intended for tests or\nexplicitly ephemeral provisioning.";
          type = (
            types.nullOr (
              types.enum [
                "Directory"
                "DirectoryOrCreate"
              ]
            )
          );
        };
      };

      config = {
        "hostPathType" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsNetwork" = {

      options = {
        "rpcPublicAddrTemplate" = mkOption {
          description = "RPCPublicAddrTemplate is the directly routable RPC address for each node\nidentity. {nodeName} is replaced with the Kubernetes Node name and the\nresult is stored in the Garage layout's rpc-address tag.\n\nExample: \"{nodeName}.storage.example.net:3901\"";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "rpcPublicAddrTemplate" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplate" = {

      options = {
        "affinity" = mkOption {
          description = "Affinity for pod scheduling. Required node affinity is rejected because\nit would create a second, hidden membership selector.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinity"
            )
          );
        };
        "containerSecurityContext" = mkOption {
          description = "ContainerSecurityContext for the Garage container.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateContainerSecurityContext"
            )
          );
        };
        "env" = mkOption {
          description = "Env contains additional environment variables for the Garage container.\nGarage config-path and RPC/Admin/metrics credential variables are\noperator-reserved because storage-drain safety and mesh identity rely on the\nrendered config and pinned immutable Secrets.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnv"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "envFrom" = mkOption {
          description = "EnvFrom contains sources used to populate Garage container environment\nvariables. A source prefix must not be capable of injecting an\noperator-reserved Garage variable.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnvFrom"
              )
            )
          );
        };
        "podAnnotations" = mkOption {
          description = "PodAnnotations to add to pods.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "podLabels" = mkOption {
          description = "PodLabels to add to pods.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "priorityClassName" = mkOption {
          description = "PriorityClassName for pods.";
          type = (types.nullOr types.str);
        };
        "resources" = mkOption {
          description = "Resources specifies compute resources for the pod.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateResources"
            )
          );
        };
        "securityContext" = mkOption {
          description = "SecurityContext for the pod.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateSecurityContext"
            )
          );
        };
        "tolerations" = mkOption {
          description = "Tolerations for pod scheduling.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateTolerations"
              )
            )
          );
        };
        "topologySpreadConstraints" = mkOption {
          description = "TopologySpreadConstraints for pod scheduling.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateTopologySpreadConstraints"
              )
            )
          );
        };
      };

      config = {
        "affinity" = mkOverride 1002 null;
        "containerSecurityContext" = mkOverride 1002 null;
        "env" = mkOverride 1002 null;
        "envFrom" = mkOverride 1002 null;
        "podAnnotations" = mkOverride 1002 null;
        "podLabels" = mkOverride 1002 null;
        "priorityClassName" = mkOverride 1002 null;
        "resources" = mkOverride 1002 null;
        "securityContext" = mkOverride 1002 null;
        "tolerations" = mkOverride 1002 null;
        "topologySpreadConstraints" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinity" = {

      options = {
        "nodeAffinity" = mkOption {
          description = "Describes node affinity scheduling rules for the pod.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityNodeAffinity"
            )
          );
        };
        "podAffinity" = mkOption {
          description = "Describes pod affinity scheduling rules (e.g. co-locate this pod in the same node, zone, etc. as some other pod(s)).";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinity"
            )
          );
        };
        "podAntiAffinity" = mkOption {
          description = "Describes pod anti-affinity scheduling rules (e.g. avoid putting this pod in the same node, zone, etc. as some other pod(s)).";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinity"
            )
          );
        };
      };

      config = {
        "nodeAffinity" = mkOverride 1002 null;
        "podAffinity" = mkOverride 1002 null;
        "podAntiAffinity" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityNodeAffinity" =
      {

        options = {
          "preferredDuringSchedulingIgnoredDuringExecution" = mkOption {
            description = "The scheduler will prefer to schedule pods to nodes that satisfy\nthe affinity expressions specified by this field, but it may choose\na node that violates one or more of the expressions. The node that is\nmost preferred is the one with the greatest sum of weights, i.e.\nfor each node that meets all of the scheduling requirements (resource\nrequest, requiredDuringScheduling affinity expressions, etc.),\ncompute a sum by iterating through the elements of this field and adding\n\"weight\" to the sum if the node matches the corresponding matchExpressions; the\nnode(s) with the highest sum are the most preferred.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecution"
                )
              )
            );
          };
          "requiredDuringSchedulingIgnoredDuringExecution" = mkOption {
            description = "If the affinity requirements specified by this field are not met at\nscheduling time, the pod will not be scheduled onto the node.\nIf the affinity requirements specified by this field cease to be met\nat some point during pod execution (e.g. due to an update), the system\nmay or may not try to eventually evict the pod from its node.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecution"
              )
            );
          };
        };

        config = {
          "preferredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
          "requiredDuringSchedulingIgnoredDuringExecution" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "preference" = mkOption {
            description = "A node selector term, associated with the corresponding weight.";
            type = (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreference"
            );
          };
          "weight" = mkOption {
            description = "Weight associated with matching the corresponding nodeSelectorTerm, in the range 1-100.";
            type = types.int;
          };
        };

        config = { };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreference" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "A list of node selector requirements by node's labels.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchExpressions"
                )
              )
            );
          };
          "matchFields" = mkOption {
            description = "A list of node selector requirements by node's fields.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchFields"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchExpressions" =
      {

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
            type = (types.nullOr (types.listOf types.str));
          };
        };

        config = {
          "values" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityNodeAffinityPreferredDuringSchedulingIgnoredDuringExecutionPreferenceMatchFields" =
      {

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
            type = (types.nullOr (types.listOf types.str));
          };
        };

        config = {
          "values" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "nodeSelectorTerms" = mkOption {
            description = "Required. A list of node selector terms. The terms are ORed.";
            type = (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTerms"
              )
            );
          };
        };

        config = { };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTerms" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "A list of node selector requirements by node's labels.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchExpressions"
                )
              )
            );
          };
          "matchFields" = mkOption {
            description = "A list of node selector requirements by node's fields.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchFields"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchExpressions" =
      {

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
            type = (types.nullOr (types.listOf types.str));
          };
        };

        config = {
          "values" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityNodeAffinityRequiredDuringSchedulingIgnoredDuringExecutionNodeSelectorTermsMatchFields" =
      {

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
            type = (types.nullOr (types.listOf types.str));
          };
        };

        config = {
          "values" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinity" =
      {

        options = {
          "preferredDuringSchedulingIgnoredDuringExecution" = mkOption {
            description = "The scheduler will prefer to schedule pods to nodes that satisfy\nthe affinity expressions specified by this field, but it may choose\na node that violates one or more of the expressions. The node that is\nmost preferred is the one with the greatest sum of weights, i.e.\nfor each node that meets all of the scheduling requirements (resource\nrequest, requiredDuringScheduling affinity expressions, etc.),\ncompute a sum by iterating through the elements of this field and adding\n\"weight\" to the sum if the node has pods which matches the corresponding podAffinityTerm; the\nnode(s) with the highest sum are the most preferred.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecution"
                )
              )
            );
          };
          "requiredDuringSchedulingIgnoredDuringExecution" = mkOption {
            description = "If the affinity requirements specified by this field are not met at\nscheduling time, the pod will not be scheduled onto the node.\nIf the affinity requirements specified by this field cease to be met\nat some point during pod execution (e.g. due to a pod label update), the\nsystem may or may not try to eventually evict the pod from its node.\nWhen there are multiple elements, the lists of nodes corresponding to each\npodAffinityTerm are intersected, i.e. all terms must be satisfied.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecution"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "podAffinityTerm" = mkOption {
            description = "Required. A pod affinity term, associated with the corresponding weight.";
            type = (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm"
            );
          };
          "weight" = mkOption {
            description = "weight associated with matching the corresponding podAffinityTerm,\nin the range 1-100.";
            type = types.int;
          };
        };

        config = { };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector"
              )
            );
          };
          "matchLabelKeys" = mkOption {
            description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "mismatchLabelKeys" = mkOption {
            description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "namespaceSelector" = mkOption {
            description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector"
              )
            );
          };
          "namespaces" = mkOption {
            description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
            type = (types.nullOr (types.listOf types.str));
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector"
              )
            );
          };
          "matchLabelKeys" = mkOption {
            description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "mismatchLabelKeys" = mkOption {
            description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "namespaceSelector" = mkOption {
            description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector"
              )
            );
          };
          "namespaces" = mkOption {
            description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
            type = (types.nullOr (types.listOf types.str));
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinity" =
      {

        options = {
          "preferredDuringSchedulingIgnoredDuringExecution" = mkOption {
            description = "The scheduler will prefer to schedule pods to nodes that satisfy\nthe anti-affinity expressions specified by this field, but it may choose\na node that violates one or more of the expressions. The node that is\nmost preferred is the one with the greatest sum of weights, i.e.\nfor each node that meets all of the scheduling requirements (resource\nrequest, requiredDuringScheduling anti-affinity expressions, etc.),\ncompute a sum by iterating through the elements of this field and subtracting\n\"weight\" from the sum if the node has pods which matches the corresponding podAffinityTerm; the\nnode(s) with the highest sum are the most preferred.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecution"
                )
              )
            );
          };
          "requiredDuringSchedulingIgnoredDuringExecution" = mkOption {
            description = "If the anti-affinity requirements specified by this field are not met at\nscheduling time, the pod will not be scheduled onto the node.\nIf the anti-affinity requirements specified by this field cease to be met\nat some point during pod execution (e.g. due to a pod label update), the\nsystem may or may not try to eventually evict the pod from its node.\nWhen there are multiple elements, the lists of nodes corresponding to each\npodAffinityTerm are intersected, i.e. all terms must be satisfied.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecution"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "podAffinityTerm" = mkOption {
            description = "Required. A pod affinity term, associated with the corresponding weight.";
            type = (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm"
            );
          };
          "weight" = mkOption {
            description = "weight associated with matching the corresponding podAffinityTerm,\nin the range 1-100.";
            type = types.int;
          };
        };

        config = { };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTerm" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector"
              )
            );
          };
          "matchLabelKeys" = mkOption {
            description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "mismatchLabelKeys" = mkOption {
            description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "namespaceSelector" = mkOption {
            description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector"
              )
            );
          };
          "namespaces" = mkOption {
            description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
            type = (types.nullOr (types.listOf types.str));
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityPreferredDuringSchedulingIgnoredDuringExecutionPodAffinityTermNamespaceSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecution" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "A label query over a set of resources, in this case pods.\nIf it's null, this PodAffinityTerm matches with no Pods.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector"
              )
            );
          };
          "matchLabelKeys" = mkOption {
            description = "MatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key in (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both matchLabelKeys and labelSelector.\nAlso, matchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "mismatchLabelKeys" = mkOption {
            description = "MismatchLabelKeys is a set of pod label keys to select which pods will\nbe taken into consideration. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are merged with `labelSelector` as `key notin (value)`\nto select the group of existing pods which pods will be taken into consideration\nfor the incoming pod's pod (anti) affinity. Keys that don't exist in the incoming\npod labels will be ignored. The default value is empty.\nThe same key is forbidden to exist in both mismatchLabelKeys and labelSelector.\nAlso, mismatchLabelKeys cannot be set when labelSelector isn't set.";
            type = (types.nullOr (types.listOf types.str));
          };
          "namespaceSelector" = mkOption {
            description = "A label query over the set of namespaces that the term applies to.\nThe term is applied to the union of the namespaces selected by this field\nand the ones listed in the namespaces field.\nnull selector and null or empty namespaces list means \"this pod's namespace\".\nAn empty selector ({}) matches all namespaces.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector"
              )
            );
          };
          "namespaces" = mkOption {
            description = "namespaces specifies a static list of namespace names that the term applies to.\nThe term is applied to the union of the namespaces listed in this field\nand the ones selected by namespaceSelector.\nnull or empty namespaces list and null namespaceSelector means \"this pod's namespace\".";
            type = (types.nullOr (types.listOf types.str));
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateAffinityPodAntiAffinityRequiredDuringSchedulingIgnoredDuringExecutionNamespaceSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateContainerSecurityContext" =
      {

        options = {
          "allowPrivilegeEscalation" = mkOption {
            description = "AllowPrivilegeEscalation controls whether a process can gain more\nprivileges than its parent process. This bool directly controls if\nthe no_new_privs flag will be set on the container process.\nAllowPrivilegeEscalation is true always when the container is:\n1) run as Privileged\n2) has CAP_SYS_ADMIN\nNote that this field cannot be set when spec.os.name is windows.";
            type = (types.nullOr types.bool);
          };
          "appArmorProfile" = mkOption {
            description = "appArmorProfile is the AppArmor options to use by this container. If set, this profile\noverrides the pod's appArmorProfile.\nNote that this field cannot be set when spec.os.name is windows.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateContainerSecurityContextAppArmorProfile"
              )
            );
          };
          "capabilities" = mkOption {
            description = "The capabilities to add/drop when running containers.\nDefaults to the default set of capabilities granted by the container runtime.\nNote that this field cannot be set when spec.os.name is windows.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateContainerSecurityContextCapabilities"
              )
            );
          };
          "privileged" = mkOption {
            description = "Run container in privileged mode.\nProcesses in privileged containers are essentially equivalent to root on the host.\nDefaults to false.\nNote that this field cannot be set when spec.os.name is windows.";
            type = (types.nullOr types.bool);
          };
          "procMount" = mkOption {
            description = "procMount denotes the type of proc mount to use for the containers.\nThe default value is Default which uses the container runtime defaults for\nreadonly paths and masked paths.\nNote that this field cannot be set when spec.os.name is windows.";
            type = (types.nullOr types.str);
          };
          "readOnlyRootFilesystem" = mkOption {
            description = "Whether this container has a read-only root filesystem.\nDefault is false.\nNote that this field cannot be set when spec.os.name is windows.";
            type = (types.nullOr types.bool);
          };
          "runAsGroup" = mkOption {
            description = "The GID to run the entrypoint of the container process.\nUses runtime default if unset.\nMay also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is windows.";
            type = (types.nullOr types.int);
          };
          "runAsNonRoot" = mkOption {
            description = "Indicates that the container must run as a non-root user.\nIf true, the Kubelet will validate the image at runtime to ensure that it\ndoes not run as UID 0 (root) and fail to start the container if it does.\nIf unset or false, no such validation will be performed.\nMay also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
            type = (types.nullOr types.bool);
          };
          "runAsUser" = mkOption {
            description = "The UID to run the entrypoint of the container process.\nDefaults to user specified in image metadata if unspecified.\nMay also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is windows.";
            type = (types.nullOr types.int);
          };
          "seLinuxOptions" = mkOption {
            description = "The SELinux context to be applied to the container.\nIf unspecified, the container runtime will allocate a random SELinux context for each\ncontainer.  May also be set in PodSecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is windows.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateContainerSecurityContextSeLinuxOptions"
              )
            );
          };
          "seccompProfile" = mkOption {
            description = "The seccomp options to use by this container. If seccomp options are\nprovided at both the pod & container level, the container options\noverride the pod options.\nNote that this field cannot be set when spec.os.name is windows.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateContainerSecurityContextSeccompProfile"
              )
            );
          };
          "windowsOptions" = mkOption {
            description = "The Windows specific settings applied to all containers.\nIf unspecified, the options from the PodSecurityContext will be used.\nIf set in both SecurityContext and PodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is linux.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateContainerSecurityContextWindowsOptions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateContainerSecurityContextAppArmorProfile" =
      {

        options = {
          "localhostProfile" = mkOption {
            description = "localhostProfile indicates a profile loaded on the node that should be used.\nThe profile must be preconfigured on the node to work.\nMust match the loaded name of the profile.\nMust be set if and only if type is \"Localhost\".";
            type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateContainerSecurityContextCapabilities" =
      {

        options = {
          "add" = mkOption {
            description = "Added capabilities";
            type = (types.nullOr (types.listOf types.str));
          };
          "drop" = mkOption {
            description = "Removed capabilities";
            type = (types.nullOr (types.listOf types.str));
          };
        };

        config = {
          "add" = mkOverride 1002 null;
          "drop" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateContainerSecurityContextSeLinuxOptions" =
      {

        options = {
          "level" = mkOption {
            description = "Level is SELinux level label that applies to the container.";
            type = (types.nullOr types.str);
          };
          "role" = mkOption {
            description = "Role is a SELinux role label that applies to the container.";
            type = (types.nullOr types.str);
          };
          "type" = mkOption {
            description = "Type is a SELinux type label that applies to the container.";
            type = (types.nullOr types.str);
          };
          "user" = mkOption {
            description = "User is a SELinux user label that applies to the container.";
            type = (types.nullOr types.str);
          };
        };

        config = {
          "level" = mkOverride 1002 null;
          "role" = mkOverride 1002 null;
          "type" = mkOverride 1002 null;
          "user" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateContainerSecurityContextSeccompProfile" =
      {

        options = {
          "localhostProfile" = mkOption {
            description = "localhostProfile indicates a profile defined in a file on the node should be used.\nThe profile must be preconfigured on the node to work.\nMust be a descending path, relative to the kubelet's configured seccomp profile location.\nMust be set if type is \"Localhost\". Must NOT be set for any other type.";
            type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateContainerSecurityContextWindowsOptions" =
      {

        options = {
          "gmsaCredentialSpec" = mkOption {
            description = "GMSACredentialSpec is where the GMSA admission webhook\n(https://github.com/kubernetes-sigs/windows-gmsa) inlines the contents of the\nGMSA credential spec named by the GMSACredentialSpecName field.";
            type = (types.nullOr types.str);
          };
          "gmsaCredentialSpecName" = mkOption {
            description = "GMSACredentialSpecName is the name of the GMSA credential spec to use.";
            type = (types.nullOr types.str);
          };
          "hostProcess" = mkOption {
            description = "HostProcess determines if a container should be run as a 'Host Process' container.\nAll of a Pod's containers must have the same effective HostProcess value\n(it is not allowed to have a mix of HostProcess containers and non-HostProcess containers).\nIn addition, if HostProcess is true then HostNetwork must also be set to true.";
            type = (types.nullOr types.bool);
          };
          "runAsUserName" = mkOption {
            description = "The UserName in Windows to run the entrypoint of the container process.\nDefaults to the user specified in image metadata if unspecified.\nMay also be set in PodSecurityContext. If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
            type = (types.nullOr types.str);
          };
        };

        config = {
          "gmsaCredentialSpec" = mkOverride 1002 null;
          "gmsaCredentialSpecName" = mkOverride 1002 null;
          "hostProcess" = mkOverride 1002 null;
          "runAsUserName" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnv" = {

      options = {
        "name" = mkOption {
          description = "Name of the environment variable.\nMay consist of any printable ASCII characters except '='.";
          type = types.str;
        };
        "value" = mkOption {
          description = "Variable references $(VAR_NAME) are expanded\nusing the previously defined environment variables in the container and\nany service environment variables. If a variable cannot be resolved,\nthe reference in the input string will be unchanged. Double $$ are reduced\nto a single $, which allows for escaping the $(VAR_NAME) syntax: i.e.\n\"$$(VAR_NAME)\" will produce the string literal \"$(VAR_NAME)\".\nEscaped references will never be expanded, regardless of whether the variable\nexists or not.\nDefaults to \"\".";
          type = (types.nullOr types.str);
        };
        "valueFrom" = mkOption {
          description = "Source for the environment variable's value. Cannot be used if value is not empty.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnvValueFrom"
            )
          );
        };
      };

      config = {
        "value" = mkOverride 1002 null;
        "valueFrom" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnvFrom" = {

      options = {
        "configMapRef" = mkOption {
          description = "The ConfigMap to select from";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnvFromConfigMapRef"
            )
          );
        };
        "prefix" = mkOption {
          description = "Optional text to prepend to the name of each environment variable.\nMay consist of any printable ASCII characters except '='.";
          type = (types.nullOr types.str);
        };
        "secretRef" = mkOption {
          description = "The Secret to select from";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnvFromSecretRef"
            )
          );
        };
      };

      config = {
        "configMapRef" = mkOverride 1002 null;
        "prefix" = mkOverride 1002 null;
        "secretRef" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnvFromConfigMapRef" =
      {

        options = {
          "name" = mkOption {
            description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
            type = (types.nullOr types.str);
          };
          "optional" = mkOption {
            description = "Specify whether the ConfigMap must be defined";
            type = (types.nullOr types.bool);
          };
        };

        config = {
          "name" = mkOverride 1002 null;
          "optional" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnvFromSecretRef" = {

      options = {
        "name" = mkOption {
          description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
          type = (types.nullOr types.str);
        };
        "optional" = mkOption {
          description = "Specify whether the Secret must be defined";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnvValueFrom" = {

      options = {
        "configMapKeyRef" = mkOption {
          description = "Selects a key of a ConfigMap.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnvValueFromConfigMapKeyRef"
            )
          );
        };
        "fieldRef" = mkOption {
          description = "Selects a field of the pod: supports metadata.name, metadata.namespace, `metadata.labels['<KEY>']`, `metadata.annotations['<KEY>']`,\nspec.nodeName, spec.serviceAccountName, status.hostIP, status.podIP, status.podIPs.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnvValueFromFieldRef"
            )
          );
        };
        "fileKeyRef" = mkOption {
          description = "FileKeyRef selects a key of the env file.\nRequires the EnvFiles feature gate to be enabled.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnvValueFromFileKeyRef"
            )
          );
        };
        "resourceFieldRef" = mkOption {
          description = "Selects a resource of the container: only resources limits and requests\n(limits.cpu, limits.memory, limits.ephemeral-storage, requests.cpu, requests.memory and requests.ephemeral-storage) are currently supported.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnvValueFromResourceFieldRef"
            )
          );
        };
        "secretKeyRef" = mkOption {
          description = "Selects a key of a secret in the pod's namespace";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnvValueFromSecretKeyRef"
            )
          );
        };
      };

      config = {
        "configMapKeyRef" = mkOverride 1002 null;
        "fieldRef" = mkOverride 1002 null;
        "fileKeyRef" = mkOverride 1002 null;
        "resourceFieldRef" = mkOverride 1002 null;
        "secretKeyRef" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnvValueFromConfigMapKeyRef" =
      {

        options = {
          "key" = mkOption {
            description = "The key to select from the ConfigMap's Data field.\nKeys in the BinaryData field are not currently propagated to container env vars.";
            type = types.str;
          };
          "name" = mkOption {
            description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
            type = (types.nullOr types.str);
          };
          "optional" = mkOption {
            description = "Specify whether the ConfigMap or its key must be defined";
            type = (types.nullOr types.bool);
          };
        };

        config = {
          "name" = mkOverride 1002 null;
          "optional" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnvValueFromFieldRef" =
      {

        options = {
          "apiVersion" = mkOption {
            description = "Version of the schema the FieldPath is written in terms of, defaults to \"v1\".";
            type = (types.nullOr types.str);
          };
          "fieldPath" = mkOption {
            description = "Path of the field to select in the specified API version.";
            type = types.str;
          };
        };

        config = {
          "apiVersion" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnvValueFromFileKeyRef" =
      {

        options = {
          "key" = mkOption {
            description = "The key within the env file. An invalid key will prevent the pod from starting.\nThe keys defined within a source may consist of any printable ASCII characters except '='.\nDuring Alpha stage of the EnvFiles feature gate, the key size is limited to 128 characters.";
            type = types.str;
          };
          "optional" = mkOption {
            description = "Specify whether the file or its key must be defined. If the file or key\ndoes not exist, then the env var is not published.\nIf optional is set to true and the specified key does not exist,\nthe environment variable will not be set in the Pod's containers.\n\nIf optional is set to false and the specified key does not exist,\nan error will be returned during Pod creation.";
            type = (types.nullOr types.bool);
          };
          "path" = mkOption {
            description = "The path within the volume from which to select the file.\nMust be relative and may not contain the '..' path or start with '..'.";
            type = types.str;
          };
          "volumeName" = mkOption {
            description = "The name of the volume mount containing the env file.";
            type = types.str;
          };
        };

        config = {
          "optional" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnvValueFromResourceFieldRef" =
      {

        options = {
          "containerName" = mkOption {
            description = "Container name: required for volumes, optional for env vars";
            type = (types.nullOr types.str);
          };
          "divisor" = mkOption {
            description = "Specifies the output format of the exposed resources, defaults to \"1\"";
            type = (types.nullOr (types.either types.int types.str));
          };
          "resource" = mkOption {
            description = "Required: resource to select";
            type = types.str;
          };
        };

        config = {
          "containerName" = mkOverride 1002 null;
          "divisor" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateEnvValueFromSecretKeyRef" =
      {

        options = {
          "key" = mkOption {
            description = "The key of the secret to select from.  Must be a valid secret key.";
            type = types.str;
          };
          "name" = mkOption {
            description = "Name of the referent.\nThis field is effectively required, but due to backwards compatibility is\nallowed to be empty. Instances of this type with an empty value here are\nalmost certainly wrong.\nMore info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names";
            type = (types.nullOr types.str);
          };
          "optional" = mkOption {
            description = "Specify whether the Secret or its key must be defined";
            type = (types.nullOr types.bool);
          };
        };

        config = {
          "name" = mkOverride 1002 null;
          "optional" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateResources" = {

      options = {
        "claims" = mkOption {
          description = "Claims lists the names of resources, defined in spec.resourceClaims,\nthat are used by this container.\n\nThis field depends on the\nDynamicResourceAllocation feature gate.\n\nThis field is immutable. It can only be set for containers.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateResourcesClaims"
                "name"
                [ "name" ]
            )
          );
          apply = attrsToList;
        };
        "limits" = mkOption {
          description = "Limits describes the maximum amount of compute resources allowed.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
        };
        "requests" = mkOption {
          description = "Requests describes the minimum amount of compute resources required.\nIf Requests is omitted for a container, it defaults to Limits if that is explicitly specified,\notherwise to an implementation-defined value. Requests cannot exceed Limits.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
        };
      };

      config = {
        "claims" = mkOverride 1002 null;
        "limits" = mkOverride 1002 null;
        "requests" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateResourcesClaims" = {

      options = {
        "name" = mkOption {
          description = "Name must match the name of one entry in pod.spec.resourceClaims of\nthe Pod where this field is used. It makes that resource available\ninside a container.";
          type = types.str;
        };
        "request" = mkOption {
          description = "Request is the name chosen for a request in the referenced claim.\nIf empty, everything from the claim is made available, otherwise\nonly the result of this request.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "request" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateSecurityContext" = {

      options = {
        "appArmorProfile" = mkOption {
          description = "appArmorProfile is the AppArmor options to use by the containers in this pod.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateSecurityContextAppArmorProfile"
            )
          );
        };
        "fsGroup" = mkOption {
          description = "A special supplemental group that applies to all containers in a pod.\nSome volume types allow the Kubelet to change the ownership of that volume\nto be owned by the pod:\n\n1. The owning GID will be the FSGroup\n2. The setgid bit is set (new files created in the volume will be owned by FSGroup)\n3. The permission bits are OR'd with rw-rw----\n\nIf unset, the Kubelet will not modify the ownership and permissions of any volume.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.int);
        };
        "fsGroupChangePolicy" = mkOption {
          description = "fsGroupChangePolicy defines behavior of changing ownership and permission of the volume\nbefore being exposed inside Pod. This field will only apply to\nvolume types which support fsGroup based ownership(and permissions).\nIt will have no effect on ephemeral volume types such as: secret, configmaps\nand emptydir.\nValid values are \"OnRootMismatch\" and \"Always\". If not specified, \"Always\" is used.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.str);
        };
        "runAsGroup" = mkOption {
          description = "The GID to run the entrypoint of the container process.\nUses runtime default if unset.\nMay also be set in SecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence\nfor that container.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.int);
        };
        "runAsNonRoot" = mkOption {
          description = "Indicates that the container must run as a non-root user.\nIf true, the Kubelet will validate the image at runtime to ensure that it\ndoes not run as UID 0 (root) and fail to start the container if it does.\nIf unset or false, no such validation will be performed.\nMay also be set in SecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
          type = (types.nullOr types.bool);
        };
        "runAsUser" = mkOption {
          description = "The UID to run the entrypoint of the container process.\nDefaults to user specified in image metadata if unspecified.\nMay also be set in SecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence\nfor that container.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.int);
        };
        "seLinuxChangePolicy" = mkOption {
          description = "seLinuxChangePolicy defines how the container's SELinux label is applied to all volumes used by the Pod.\nIt has no effect on nodes that do not support SELinux or to volumes does not support SELinux.\nValid values are \"MountOption\" and \"Recursive\".\n\n\"Recursive\" means relabeling of all files on all Pod volumes by the container runtime.\nThis may be slow for large volumes, but allows mixing privileged and unprivileged Pods sharing the same volume on the same node.\n\n\"MountOption\" mounts all eligible Pod volumes with `-o context` mount option.\nThis requires all Pods that share the same volume to use the same SELinux label.\nIt is not possible to share the same volume among privileged and unprivileged Pods.\nEligible volumes are in-tree FibreChannel and iSCSI volumes, and all CSI volumes\nwhose CSI driver announces SELinux support by setting spec.seLinuxMount: true in their\nCSIDriver instance. Other volumes are always re-labelled recursively.\n\nIf not specified, \"MountOption\" is used.\n\nThis field affects only Pods that have SELinux label set, either in PodSecurityContext or in SecurityContext of all containers.\n\nAll Pods that use the same volume should use the same seLinuxChangePolicy, otherwise some pods can get stuck in ContainerCreating state.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.str);
        };
        "seLinuxOptions" = mkOption {
          description = "The SELinux context to be applied to all containers.\nIf unspecified, the container runtime will allocate a random SELinux context for each\ncontainer.  May also be set in SecurityContext.  If set in\nboth SecurityContext and PodSecurityContext, the value specified in SecurityContext\ntakes precedence for that container.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateSecurityContextSeLinuxOptions"
            )
          );
        };
        "seccompProfile" = mkOption {
          description = "The seccomp options to use by the containers in this pod.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateSecurityContextSeccompProfile"
            )
          );
        };
        "supplementalGroups" = mkOption {
          description = "A list of groups applied to the first process run in each container, in\naddition to the container's primary GID and fsGroup (if specified).  If\nthe SupplementalGroupsPolicy feature is enabled, the\nsupplementalGroupsPolicy field determines whether these are in addition\nto or instead of any group memberships defined in the container image.\nIf unspecified, no additional groups are added, though group memberships\ndefined in the container image may still be used, depending on the\nsupplementalGroupsPolicy field.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr (types.listOf types.int));
        };
        "supplementalGroupsPolicy" = mkOption {
          description = "Defines how supplemental groups of the first container processes are calculated.\nValid values are \"Merge\" and \"Strict\". If not specified, \"Merge\" is used.\n(Alpha) Using the field requires the SupplementalGroupsPolicy feature gate to be enabled\nand the container runtime must implement support for this feature.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.str);
        };
        "sysctls" = mkOption {
          description = "Sysctls hold a list of namespaced sysctls used for the pod. Pods with unsupported\nsysctls (by the container runtime) might fail to launch.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateSecurityContextSysctls"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "windowsOptions" = mkOption {
          description = "The Windows specific settings applied to all containers.\nIf unspecified, the options within a container's SecurityContext will be used.\nIf set in both SecurityContext and PodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is linux.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateSecurityContextWindowsOptions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateSecurityContextAppArmorProfile" =
      {

        options = {
          "localhostProfile" = mkOption {
            description = "localhostProfile indicates a profile loaded on the node that should be used.\nThe profile must be preconfigured on the node to work.\nMust match the loaded name of the profile.\nMust be set if and only if type is \"Localhost\".";
            type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateSecurityContextSeLinuxOptions" =
      {

        options = {
          "level" = mkOption {
            description = "Level is SELinux level label that applies to the container.";
            type = (types.nullOr types.str);
          };
          "role" = mkOption {
            description = "Role is a SELinux role label that applies to the container.";
            type = (types.nullOr types.str);
          };
          "type" = mkOption {
            description = "Type is a SELinux type label that applies to the container.";
            type = (types.nullOr types.str);
          };
          "user" = mkOption {
            description = "User is a SELinux user label that applies to the container.";
            type = (types.nullOr types.str);
          };
        };

        config = {
          "level" = mkOverride 1002 null;
          "role" = mkOverride 1002 null;
          "type" = mkOverride 1002 null;
          "user" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateSecurityContextSeccompProfile" =
      {

        options = {
          "localhostProfile" = mkOption {
            description = "localhostProfile indicates a profile defined in a file on the node should be used.\nThe profile must be preconfigured on the node to work.\nMust be a descending path, relative to the kubelet's configured seccomp profile location.\nMust be set if type is \"Localhost\". Must NOT be set for any other type.";
            type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateSecurityContextSysctls" =
      {

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

        config = { };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateSecurityContextWindowsOptions" =
      {

        options = {
          "gmsaCredentialSpec" = mkOption {
            description = "GMSACredentialSpec is where the GMSA admission webhook\n(https://github.com/kubernetes-sigs/windows-gmsa) inlines the contents of the\nGMSA credential spec named by the GMSACredentialSpecName field.";
            type = (types.nullOr types.str);
          };
          "gmsaCredentialSpecName" = mkOption {
            description = "GMSACredentialSpecName is the name of the GMSA credential spec to use.";
            type = (types.nullOr types.str);
          };
          "hostProcess" = mkOption {
            description = "HostProcess determines if a container should be run as a 'Host Process' container.\nAll of a Pod's containers must have the same effective HostProcess value\n(it is not allowed to have a mix of HostProcess containers and non-HostProcess containers).\nIn addition, if HostProcess is true then HostNetwork must also be set to true.";
            type = (types.nullOr types.bool);
          };
          "runAsUserName" = mkOption {
            description = "The UserName in Windows to run the entrypoint of the container process.\nDefaults to the user specified in image metadata if unspecified.\nMay also be set in PodSecurityContext. If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
            type = (types.nullOr types.str);
          };
        };

        config = {
          "gmsaCredentialSpec" = mkOverride 1002 null;
          "gmsaCredentialSpecName" = mkOverride 1002 null;
          "hostProcess" = mkOverride 1002 null;
          "runAsUserName" = mkOverride 1002 null;
        };

      };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateTolerations" = {

      options = {
        "effect" = mkOption {
          description = "Effect indicates the taint effect to match. Empty means match all taint effects.\nWhen specified, allowed values are NoSchedule, PreferNoSchedule and NoExecute.";
          type = (types.nullOr types.str);
        };
        "key" = mkOption {
          description = "Key is the taint key that the toleration applies to. Empty means match all taint keys.\nIf the key is empty, operator must be Exists; this combination means to match all values and all keys.";
          type = (types.nullOr types.str);
        };
        "operator" = mkOption {
          description = "Operator represents a key's relationship to the value.\nValid operators are Exists, Equal, Lt, and Gt. Defaults to Equal.\nExists is equivalent to wildcard for value, so that a pod can\ntolerate all taints of a particular category.\nLt and Gt perform numeric comparisons (requires feature gate TaintTolerationComparisonOperators).";
          type = (types.nullOr types.str);
        };
        "tolerationSeconds" = mkOption {
          description = "TolerationSeconds represents the period of time the toleration (which must be\nof effect NoExecute, otherwise this field is ignored) tolerates the taint. By default,\nit is not set, which means tolerate the taint forever (do not evict). Zero and\nnegative values will be treated as 0 (evict immediately) by the system.";
          type = (types.nullOr types.int);
        };
        "value" = mkOption {
          description = "Value is the taint value the toleration matches to.\nIf the operator is Exists, the value should be empty, otherwise just a regular string.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateTopologySpreadConstraints" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "LabelSelector is used to find matching pods.\nPods that match this label selector are counted to determine the number of pods\nin their corresponding topology domain.";
            type = (
              types.nullOr (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateTopologySpreadConstraintsLabelSelector"
              )
            );
          };
          "matchLabelKeys" = mkOption {
            description = "MatchLabelKeys is a set of pod label keys to select the pods over which\nspreading will be calculated. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are ANDed with labelSelector\nto select the group of existing pods over which spreading will be calculated\nfor the incoming pod. The same key is forbidden to exist in both MatchLabelKeys and LabelSelector.\nMatchLabelKeys cannot be set when LabelSelector isn't set.\nKeys that don't exist in the incoming pod labels will\nbe ignored. A null or empty list means only match against labelSelector.\n\nThis is a beta field and requires the MatchLabelKeysInPodTopologySpread feature gate to be enabled (enabled by default).";
            type = (types.nullOr (types.listOf types.str));
          };
          "maxSkew" = mkOption {
            description = "MaxSkew describes the degree to which pods may be unevenly distributed.\nWhen `whenUnsatisfiable=DoNotSchedule`, it is the maximum permitted difference\nbetween the number of matching pods in the target topology and the global minimum.\nThe global minimum is the minimum number of matching pods in an eligible domain\nor zero if the number of eligible domains is less than MinDomains.\nFor example, in a 3-zone cluster, MaxSkew is set to 1, and pods with the same\nlabelSelector spread as 2/2/1:\nIn this case, the global minimum is 1.\n| zone1 | zone2 | zone3 |\n|  P P  |  P P  |   P   |\n- if MaxSkew is 1, incoming pod can only be scheduled to zone3 to become 2/2/2;\nscheduling it onto zone1(zone2) would make the ActualSkew(3-1) on zone1(zone2)\nviolate MaxSkew(1).\n- if MaxSkew is 2, incoming pod can be scheduled onto any zone.\nWhen `whenUnsatisfiable=ScheduleAnyway`, it is used to give higher precedence\nto topologies that satisfy it.\nIt's a required field. Default value is 1 and 0 is not allowed.";
            type = types.int;
          };
          "minDomains" = mkOption {
            description = "MinDomains indicates a minimum number of eligible domains.\nWhen the number of eligible domains with matching topology keys is less than minDomains,\nPod Topology Spread treats \"global minimum\" as 0, and then the calculation of Skew is performed.\nAnd when the number of eligible domains with matching topology keys equals or greater than minDomains,\nthis value has no effect on scheduling.\nAs a result, when the number of eligible domains is less than minDomains,\nscheduler won't schedule more than maxSkew Pods to those domains.\nIf value is nil, the constraint behaves as if MinDomains is equal to 1.\nValid values are integers greater than 0.\nWhen value is not nil, WhenUnsatisfiable must be DoNotSchedule.\n\nFor example, in a 3-zone cluster, MaxSkew is set to 2, MinDomains is set to 5 and pods with the same\nlabelSelector spread as 2/2/2:\n| zone1 | zone2 | zone3 |\n|  P P  |  P P  |  P P  |\nThe number of domains is less than 5(MinDomains), so \"global minimum\" is treated as 0.\nIn this situation, new pod with the same labelSelector cannot be scheduled,\nbecause computed skew will be 3(3 - 0) if new Pod is scheduled to any of the three zones,\nit will violate MaxSkew.";
            type = (types.nullOr types.int);
          };
          "nodeAffinityPolicy" = mkOption {
            description = "NodeAffinityPolicy indicates how we will treat Pod's nodeAffinity/nodeSelector\nwhen calculating pod topology spread skew. Options are:\n- Honor: only nodes matching nodeAffinity/nodeSelector are included in the calculations.\n- Ignore: nodeAffinity/nodeSelector are ignored. All nodes are included in the calculations.\n\nIf this value is nil, the behavior is equivalent to the Honor policy.";
            type = (types.nullOr types.str);
          };
          "nodeTaintsPolicy" = mkOption {
            description = "NodeTaintsPolicy indicates how we will treat node taints when calculating\npod topology spread skew. Options are:\n- Honor: nodes without taints, along with tainted nodes for which the incoming pod\nhas a toleration, are included.\n- Ignore: node taints are ignored. All nodes are included.\n\nIf this value is nil, the behavior is equivalent to the Ignore policy.";
            type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateTopologySpreadConstraintsLabelSelector" =
      {

        options = {
          "matchExpressions" = mkOption {
            description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
            type = (
              types.nullOr (
                types.listOf (
                  submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateTopologySpreadConstraintsLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsPodTemplateTopologySpreadConstraintsLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsSelector" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageNodeLocalPoolsSelectorMatchExpressions" = {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStoragePodDisruptionBudget" = {

      options = {
        "enabled" = mkOption {
          description = "Enabled enables PodDisruptionBudget creation";
          type = (types.nullOr types.bool);
        };
        "maxUnavailable" = mkOption {
          description = "MaxUnavailable specifies the maximum number of pods that can be unavailable.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "minAvailable" = mkOption {
          description = "MinAvailable specifies the minimum number of pods that must be available.";
          type = (types.nullOr (types.either types.int types.str));
        };
      };

      config = {
        "enabled" = mkOverride 1002 null;
        "maxUnavailable" = mkOverride 1002 null;
        "minAvailable" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStoragePvcRetentionPolicy" = {

      options = {
        "whenDeleted" = mkOption {
          description = "WhenDeleted specifies what happens to PVCs when the StatefulSet is deleted.";
          type = (
            types.nullOr (
              types.enum [
                "Retain"
                "Delete"
              ]
            )
          );
        };
        "whenScaled" = mkOption {
          description = "WhenScaled specifies what happens to PVCs when the StatefulSet is scaled down.";
          type = (
            types.nullOr (
              types.enum [
                "Retain"
                "Delete"
              ]
            )
          );
        };
      };

      config = {
        "whenDeleted" = mkOverride 1002 null;
        "whenScaled" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageResources" = {

      options = {
        "claims" = mkOption {
          description = "Claims lists the names of resources, defined in spec.resourceClaims,\nthat are used by this container.\n\nThis field depends on the\nDynamicResourceAllocation feature gate.\n\nThis field is immutable. It can only be set for containers.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageResourcesClaims"
                "name"
                [ "name" ]
            )
          );
          apply = attrsToList;
        };
        "limits" = mkOption {
          description = "Limits describes the maximum amount of compute resources allowed.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
        };
        "requests" = mkOption {
          description = "Requests describes the minimum amount of compute resources required.\nIf Requests is omitted for a container, it defaults to Limits if that is explicitly specified,\notherwise to an implementation-defined value. Requests cannot exceed Limits.\nMore info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
          type = (types.nullOr (types.attrsOf (types.either types.int types.str)));
        };
      };

      config = {
        "claims" = mkOverride 1002 null;
        "limits" = mkOverride 1002 null;
        "requests" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageResourcesClaims" = {

      options = {
        "name" = mkOption {
          description = "Name must match the name of one entry in pod.spec.resourceClaims of\nthe Pod where this field is used. It makes that resource available\ninside a container.";
          type = types.str;
        };
        "request" = mkOption {
          description = "Request is the name chosen for a request in the referenced claim.\nIf empty, everything from the claim is made available, otherwise\nonly the result of this request.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "request" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageSecurityContext" = {

      options = {
        "appArmorProfile" = mkOption {
          description = "appArmorProfile is the AppArmor options to use by the containers in this pod.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageSecurityContextAppArmorProfile"
            )
          );
        };
        "fsGroup" = mkOption {
          description = "A special supplemental group that applies to all containers in a pod.\nSome volume types allow the Kubelet to change the ownership of that volume\nto be owned by the pod:\n\n1. The owning GID will be the FSGroup\n2. The setgid bit is set (new files created in the volume will be owned by FSGroup)\n3. The permission bits are OR'd with rw-rw----\n\nIf unset, the Kubelet will not modify the ownership and permissions of any volume.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.int);
        };
        "fsGroupChangePolicy" = mkOption {
          description = "fsGroupChangePolicy defines behavior of changing ownership and permission of the volume\nbefore being exposed inside Pod. This field will only apply to\nvolume types which support fsGroup based ownership(and permissions).\nIt will have no effect on ephemeral volume types such as: secret, configmaps\nand emptydir.\nValid values are \"OnRootMismatch\" and \"Always\". If not specified, \"Always\" is used.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.str);
        };
        "runAsGroup" = mkOption {
          description = "The GID to run the entrypoint of the container process.\nUses runtime default if unset.\nMay also be set in SecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence\nfor that container.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.int);
        };
        "runAsNonRoot" = mkOption {
          description = "Indicates that the container must run as a non-root user.\nIf true, the Kubelet will validate the image at runtime to ensure that it\ndoes not run as UID 0 (root) and fail to start the container if it does.\nIf unset or false, no such validation will be performed.\nMay also be set in SecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
          type = (types.nullOr types.bool);
        };
        "runAsUser" = mkOption {
          description = "The UID to run the entrypoint of the container process.\nDefaults to user specified in image metadata if unspecified.\nMay also be set in SecurityContext.  If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence\nfor that container.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.int);
        };
        "seLinuxChangePolicy" = mkOption {
          description = "seLinuxChangePolicy defines how the container's SELinux label is applied to all volumes used by the Pod.\nIt has no effect on nodes that do not support SELinux or to volumes does not support SELinux.\nValid values are \"MountOption\" and \"Recursive\".\n\n\"Recursive\" means relabeling of all files on all Pod volumes by the container runtime.\nThis may be slow for large volumes, but allows mixing privileged and unprivileged Pods sharing the same volume on the same node.\n\n\"MountOption\" mounts all eligible Pod volumes with `-o context` mount option.\nThis requires all Pods that share the same volume to use the same SELinux label.\nIt is not possible to share the same volume among privileged and unprivileged Pods.\nEligible volumes are in-tree FibreChannel and iSCSI volumes, and all CSI volumes\nwhose CSI driver announces SELinux support by setting spec.seLinuxMount: true in their\nCSIDriver instance. Other volumes are always re-labelled recursively.\n\nIf not specified, \"MountOption\" is used.\n\nThis field affects only Pods that have SELinux label set, either in PodSecurityContext or in SecurityContext of all containers.\n\nAll Pods that use the same volume should use the same seLinuxChangePolicy, otherwise some pods can get stuck in ContainerCreating state.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.str);
        };
        "seLinuxOptions" = mkOption {
          description = "The SELinux context to be applied to all containers.\nIf unspecified, the container runtime will allocate a random SELinux context for each\ncontainer.  May also be set in SecurityContext.  If set in\nboth SecurityContext and PodSecurityContext, the value specified in SecurityContext\ntakes precedence for that container.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageSecurityContextSeLinuxOptions"
            )
          );
        };
        "seccompProfile" = mkOption {
          description = "The seccomp options to use by the containers in this pod.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageSecurityContextSeccompProfile"
            )
          );
        };
        "supplementalGroups" = mkOption {
          description = "A list of groups applied to the first process run in each container, in\naddition to the container's primary GID and fsGroup (if specified).  If\nthe SupplementalGroupsPolicy feature is enabled, the\nsupplementalGroupsPolicy field determines whether these are in addition\nto or instead of any group memberships defined in the container image.\nIf unspecified, no additional groups are added, though group memberships\ndefined in the container image may still be used, depending on the\nsupplementalGroupsPolicy field.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr (types.listOf types.int));
        };
        "supplementalGroupsPolicy" = mkOption {
          description = "Defines how supplemental groups of the first container processes are calculated.\nValid values are \"Merge\" and \"Strict\". If not specified, \"Merge\" is used.\n(Alpha) Using the field requires the SupplementalGroupsPolicy feature gate to be enabled\nand the container runtime must implement support for this feature.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (types.nullOr types.str);
        };
        "sysctls" = mkOption {
          description = "Sysctls hold a list of namespaced sysctls used for the pod. Pods with unsupported\nsysctls (by the container runtime) might fail to launch.\nNote that this field cannot be set when spec.os.name is windows.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageSecurityContextSysctls"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "windowsOptions" = mkOption {
          description = "The Windows specific settings applied to all containers.\nIf unspecified, the options within a container's SecurityContext will be used.\nIf set in both SecurityContext and PodSecurityContext, the value specified in SecurityContext takes precedence.\nNote that this field cannot be set when spec.os.name is linux.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageSecurityContextWindowsOptions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageSecurityContextAppArmorProfile" = {

      options = {
        "localhostProfile" = mkOption {
          description = "localhostProfile indicates a profile loaded on the node that should be used.\nThe profile must be preconfigured on the node to work.\nMust match the loaded name of the profile.\nMust be set if and only if type is \"Localhost\".";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageSecurityContextSeLinuxOptions" = {

      options = {
        "level" = mkOption {
          description = "Level is SELinux level label that applies to the container.";
          type = (types.nullOr types.str);
        };
        "role" = mkOption {
          description = "Role is a SELinux role label that applies to the container.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is a SELinux type label that applies to the container.";
          type = (types.nullOr types.str);
        };
        "user" = mkOption {
          description = "User is a SELinux user label that applies to the container.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "level" = mkOverride 1002 null;
        "role" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
        "user" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageSecurityContextSeccompProfile" = {

      options = {
        "localhostProfile" = mkOption {
          description = "localhostProfile indicates a profile defined in a file on the node should be used.\nThe profile must be preconfigured on the node to work.\nMust be a descending path, relative to the kubelet's configured seccomp profile location.\nMust be set if type is \"Localhost\". Must NOT be set for any other type.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageSecurityContextSysctls" = {

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

      config = { };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageSecurityContextWindowsOptions" = {

      options = {
        "gmsaCredentialSpec" = mkOption {
          description = "GMSACredentialSpec is where the GMSA admission webhook\n(https://github.com/kubernetes-sigs/windows-gmsa) inlines the contents of the\nGMSA credential spec named by the GMSACredentialSpecName field.";
          type = (types.nullOr types.str);
        };
        "gmsaCredentialSpecName" = mkOption {
          description = "GMSACredentialSpecName is the name of the GMSA credential spec to use.";
          type = (types.nullOr types.str);
        };
        "hostProcess" = mkOption {
          description = "HostProcess determines if a container should be run as a 'Host Process' container.\nAll of a Pod's containers must have the same effective HostProcess value\n(it is not allowed to have a mix of HostProcess containers and non-HostProcess containers).\nIn addition, if HostProcess is true then HostNetwork must also be set to true.";
          type = (types.nullOr types.bool);
        };
        "runAsUserName" = mkOption {
          description = "The UserName in Windows to run the entrypoint of the container process.\nDefaults to the user specified in image metadata if unspecified.\nMay also be set in PodSecurityContext. If set in both SecurityContext and\nPodSecurityContext, the value specified in SecurityContext takes precedence.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "gmsaCredentialSpec" = mkOverride 1002 null;
        "gmsaCredentialSpecName" = mkOverride 1002 null;
        "hostProcess" = mkOverride 1002 null;
        "runAsUserName" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageTolerations" = {

      options = {
        "effect" = mkOption {
          description = "Effect indicates the taint effect to match. Empty means match all taint effects.\nWhen specified, allowed values are NoSchedule, PreferNoSchedule and NoExecute.";
          type = (types.nullOr types.str);
        };
        "key" = mkOption {
          description = "Key is the taint key that the toleration applies to. Empty means match all taint keys.\nIf the key is empty, operator must be Exists; this combination means to match all values and all keys.";
          type = (types.nullOr types.str);
        };
        "operator" = mkOption {
          description = "Operator represents a key's relationship to the value.\nValid operators are Exists, Equal, Lt, and Gt. Defaults to Equal.\nExists is equivalent to wildcard for value, so that a pod can\ntolerate all taints of a particular category.\nLt and Gt perform numeric comparisons (requires feature gate TaintTolerationComparisonOperators).";
          type = (types.nullOr types.str);
        };
        "tolerationSeconds" = mkOption {
          description = "TolerationSeconds represents the period of time the toleration (which must be\nof effect NoExecute, otherwise this field is ignored) tolerates the taint. By default,\nit is not set, which means tolerate the taint forever (do not evict). Zero and\nnegative values will be treated as 0 (evict immediately) by the system.";
          type = (types.nullOr types.int);
        };
        "value" = mkOption {
          description = "Value is the taint value the toleration matches to.\nIf the operator is Exists, the value should be empty, otherwise just a regular string.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageTopologySpreadConstraints" = {

      options = {
        "labelSelector" = mkOption {
          description = "LabelSelector is used to find matching pods.\nPods that match this label selector are counted to determine the number of pods\nin their corresponding topology domain.";
          type = (
            types.nullOr (
              submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageTopologySpreadConstraintsLabelSelector"
            )
          );
        };
        "matchLabelKeys" = mkOption {
          description = "MatchLabelKeys is a set of pod label keys to select the pods over which\nspreading will be calculated. The keys are used to lookup values from the\nincoming pod labels, those key-value labels are ANDed with labelSelector\nto select the group of existing pods over which spreading will be calculated\nfor the incoming pod. The same key is forbidden to exist in both MatchLabelKeys and LabelSelector.\nMatchLabelKeys cannot be set when LabelSelector isn't set.\nKeys that don't exist in the incoming pod labels will\nbe ignored. A null or empty list means only match against labelSelector.\n\nThis is a beta field and requires the MatchLabelKeysInPodTopologySpread feature gate to be enabled (enabled by default).";
          type = (types.nullOr (types.listOf types.str));
        };
        "maxSkew" = mkOption {
          description = "MaxSkew describes the degree to which pods may be unevenly distributed.\nWhen `whenUnsatisfiable=DoNotSchedule`, it is the maximum permitted difference\nbetween the number of matching pods in the target topology and the global minimum.\nThe global minimum is the minimum number of matching pods in an eligible domain\nor zero if the number of eligible domains is less than MinDomains.\nFor example, in a 3-zone cluster, MaxSkew is set to 1, and pods with the same\nlabelSelector spread as 2/2/1:\nIn this case, the global minimum is 1.\n| zone1 | zone2 | zone3 |\n|  P P  |  P P  |   P   |\n- if MaxSkew is 1, incoming pod can only be scheduled to zone3 to become 2/2/2;\nscheduling it onto zone1(zone2) would make the ActualSkew(3-1) on zone1(zone2)\nviolate MaxSkew(1).\n- if MaxSkew is 2, incoming pod can be scheduled onto any zone.\nWhen `whenUnsatisfiable=ScheduleAnyway`, it is used to give higher precedence\nto topologies that satisfy it.\nIt's a required field. Default value is 1 and 0 is not allowed.";
          type = types.int;
        };
        "minDomains" = mkOption {
          description = "MinDomains indicates a minimum number of eligible domains.\nWhen the number of eligible domains with matching topology keys is less than minDomains,\nPod Topology Spread treats \"global minimum\" as 0, and then the calculation of Skew is performed.\nAnd when the number of eligible domains with matching topology keys equals or greater than minDomains,\nthis value has no effect on scheduling.\nAs a result, when the number of eligible domains is less than minDomains,\nscheduler won't schedule more than maxSkew Pods to those domains.\nIf value is nil, the constraint behaves as if MinDomains is equal to 1.\nValid values are integers greater than 0.\nWhen value is not nil, WhenUnsatisfiable must be DoNotSchedule.\n\nFor example, in a 3-zone cluster, MaxSkew is set to 2, MinDomains is set to 5 and pods with the same\nlabelSelector spread as 2/2/2:\n| zone1 | zone2 | zone3 |\n|  P P  |  P P  |  P P  |\nThe number of domains is less than 5(MinDomains), so \"global minimum\" is treated as 0.\nIn this situation, new pod with the same labelSelector cannot be scheduled,\nbecause computed skew will be 3(3 - 0) if new Pod is scheduled to any of the three zones,\nit will violate MaxSkew.";
          type = (types.nullOr types.int);
        };
        "nodeAffinityPolicy" = mkOption {
          description = "NodeAffinityPolicy indicates how we will treat Pod's nodeAffinity/nodeSelector\nwhen calculating pod topology spread skew. Options are:\n- Honor: only nodes matching nodeAffinity/nodeSelector are included in the calculations.\n- Ignore: nodeAffinity/nodeSelector are ignored. All nodes are included in the calculations.\n\nIf this value is nil, the behavior is equivalent to the Honor policy.";
          type = (types.nullOr types.str);
        };
        "nodeTaintsPolicy" = mkOption {
          description = "NodeTaintsPolicy indicates how we will treat node taints when calculating\npod topology spread skew. Options are:\n- Honor: nodes without taints, along with tainted nodes for which the incoming pod\nhas a toleration, are included.\n- Ignore: node taints are ignored. All nodes are included.\n\nIf this value is nil, the behavior is equivalent to the Ignore policy.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageTopologySpreadConstraintsLabelSelector" = {

      options = {
        "matchExpressions" = mkOption {
          description = "matchExpressions is a list of label selector requirements. The requirements are ANDed.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageTopologySpreadConstraintsLabelSelectorMatchExpressions"
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecStorageTopologySpreadConstraintsLabelSelectorMatchExpressions" =
      {

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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecWebApi" = {

      options = {
        "addHostToMetrics" = mkOption {
          description = "AddHostToMetrics adds the domain name to metrics labels for per-domain tracking.";
          type = (types.nullOr types.bool);
        };
        "bindAddress" = mkOption {
          description = "BindAddress is a custom wildcard TCP bind address for the Web API.";
          type = (types.nullOr types.str);
        };
        "bindPort" = mkOption {
          description = "BindPort is the port to bind for web serving.";
          type = (types.nullOr (types.withMaximum 65535 (types.withMinimum 1 types.int)));
        };
        "enabled" = mkOption {
          description = "Enabled controls whether the web endpoint is active. Defaults to true.";
          type = (types.nullOr types.bool);
        };
        "rootDomain" = mkOption {
          description = "RootDomain is the root domain suffix for bucket website access.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterSpecWorkers" = {

      options = {
        "resyncTranquility" = mkOption {
          description = "ResyncTranquility controls how aggressively the block resync worker runs.";
          type = (types.nullOr (types.withMinimum 0 types.int));
        };
        "resyncWorkerCount" = mkOption {
          description = "ResyncWorkerCount sets the number of parallel block resync worker goroutines.";
          type = (types.nullOr (types.withMaximum 8 (types.withMinimum 1 types.int)));
        };
        "scrubTranquility" = mkOption {
          description = "ScrubTranquility controls how aggressively the block integrity scrub runs.";
          type = (types.nullOr (types.withMinimum 0 types.int));
        };
      };

      config = {
        "resyncTranquility" = mkOverride 1002 null;
        "resyncWorkerCount" = mkOverride 1002 null;
        "scrubTranquility" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterSpecZoneFrom" = {

      options = {
        "nodeLabel" = mkOption {
          description = "NodeLabel is the label key on the Kubernetes Node whose value becomes the\nGarage layout zone.\n\nExamples: \"topology.kubernetes.io/zone\" for cloud AZs,\n\"kubernetes.io/hostname\" for per-node failure domains, or a custom label\nsuch as \"example.com/rack\" for physical racks or power circuits.";
          type = (types.withMaxLength 316 (types.withMinLength 1 types.str));
        };
      };

      config = { };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterStatus" = {

      options = {
        "activeRepairs" = mkOption {
          description = "ActiveRepairs contains currently running repair operations.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusActiveRepairs")
            )
          );
        };
        "autoModePvcHandoffs" = mkOption {
          description = "AutoModePVCHandoffs are controller-owned, exact-UID authorizations for\nretained Auto-mode claims whose GarageNode slot was scaled down and later\nrecreated. Entries are removed after the replacement binds the exact PVC.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusAutoModePvcHandoffs")
            )
          );
        };
        "blockErrorDetails" = mkOption {
          description = "BlockErrorDetails provides detailed information about block errors.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusBlockErrorDetails")
          );
        };
        "blockErrors" = mkOption {
          description = "BlockErrors is the count of blocks with sync errors across all nodes.";
          type = (types.nullOr types.int);
        };
        "buildInfo" = mkOption {
          description = "BuildInfo contains Garage build information.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusBuildInfo"));
        };
        "clusterId" = mkOption {
          description = "ClusterID is the unique identifier of the Garage cluster.";
          type = (types.nullOr types.str);
        };
        "conditions" = mkOption {
          description = "Conditions represent the current state of the cluster.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusConditions")
            )
          );
        };
        "drainingNodes" = mkOption {
          description = "DrainingNodes is the count of nodes that are draining data from an older layout version.";
          type = (types.nullOr types.int);
        };
        "endpoints" = mkOption {
          description = "Endpoints contains service endpoints.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusEndpoints"));
        };
        "factorMigration" = mkOption {
          description = "FactorMigration tracks an in-flight coordinated replication-factor migration\n(the garage.rajsingh.info/purge-cluster-layout operation). Nil when no\nmigration has run.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusFactorMigration")
          );
        };
        "gatewayNodesNotInLayout" = mkOption {
          description = "GatewayNodesNotInLayout lists operator-owned gateway GarageNodes that report\nstatus.inLayout == false — they have lost the capacity:nil layout role that\nkeeps S3 sig-auth data replicated locally (#209), so signed requests can\nfail with \"No such key\".\nDrives the GatewayLayoutDegraded condition. Empty when every gateway node\nholds its role.";
          type = (types.nullOr (types.listOf types.str));
        };
        "gatewayReadyReplicas" = mkOption {
          description = "GatewayReadyReplicas is the number of ready gateway-tier pods.";
          type = (types.nullOr types.int);
        };
        "gatewayReplicas" = mkOption {
          description = "GatewayReplicas is the desired gateway-tier replica count.";
          type = (types.nullOr types.int);
        };
        "health" = mkOption {
          description = "Health contains cluster health information.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusHealth"));
        };
        "lastOperation" = mkOption {
          description = "LastOperation records the result of the most recently triggered operational annotation.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusLastOperation"));
        };
        "layoutDiagnosis" = mkOption {
          description = "LayoutDiagnosis is a one-line, human-readable summary of the most severe\nactive health condition (quorum at risk, remote clusters stale, federation\nmisconfigured). Empty when the cluster is healthy. Surfaced as a printcolumn\nso `kubectl get gc` shows the actionable problem at a glance.";
          type = (types.nullOr types.str);
        };
        "layoutHistory" = mkOption {
          description = "LayoutHistory contains layout version history.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusLayoutHistory"));
        };
        "layoutPreview" = mkOption {
          description = "LayoutPreview shows what would change if staged layout is applied.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusLayoutPreview"));
        };
        "layoutVersion" = mkOption {
          description = "LayoutVersion is the current layout version.";
          type = (types.nullOr types.int);
        };
        "lifecycleStatus" = mkOption {
          description = "LifecycleStatus contains the status of bucket lifecycle operations.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusLifecycleStatus")
          );
        };
        "nodes" = mkOption {
          description = "Nodes contains status information for each node.";
          type = (
            types.nullOr (types.listOf (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusNodes"))
          );
        };
        "observedGeneration" = mkOption {
          description = "ObservedGeneration is the last observed generation.";
          type = (types.nullOr types.int);
        };
        "pendingGatewayTombstones" = mkOption {
          description = "PendingGatewayTombstones lists stale gateway layout entries pending removal.\nPopulated when gateway tombstone cleanup detects orphaned entries but cannot\nremove them automatically (e.g. layoutManagement.autoApply is false).";
          type = (types.nullOr (types.listOf types.str));
        };
        "phase" = mkOption {
          description = "Phase represents the current phase of the cluster.";
          type = (
            types.nullOr (
              types.enum [
                "Pending"
                "Creating"
                "Running"
                "Ready"
                "Degraded"
                "Updating"
                "Deleting"
                "Failed"
                "Unknown"
              ]
            )
          );
        };
        "readyReplicas" = mkOption {
          description = "ReadyReplicas is the number of ready Garage pods.";
          type = (types.nullOr types.int);
        };
        "remoteClusters" = mkOption {
          description = "RemoteClusters contains status of remote clusters in the federation.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1beta2.GarageClusterStatusRemoteClusters"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "replicas" = mkOption {
          description = "Replicas is the total number of Garage pods targeted by this cluster\n(storage + gateway tiers combined).";
          type = types.int;
        };
        "resyncQueueLength" = mkOption {
          description = "ResyncQueueLength is the total block resync queue depth across all nodes.";
          type = (types.nullOr types.int);
        };
        "scaleReplicas" = mkOption {
          description = "ScaleReplicas is the actual number of non-terminating Pods in the\nworkload projected through the requested API version's scale subresource.\nFor storage and unified clusters this is only the Auto-managed default\nStatefulSet/PVC group; node-local pools, Manual GarageNodes, and unified\ngateways are excluded. A gateway-only hub object carries its gateway Pod\ncount solely to preserve the legacy v1beta1 Scale projection; v1beta2\ngateway-only Scale updates are rejected.";
          type = (types.nullOr types.int);
        };
        "scaleSelector" = mkOption {
          description = "ScaleSelector is the serialized exact selector for the Pods counted by\nScaleReplicas. It normally selects the default storage group; on a\ngateway-only hub object it selects the gateway Pods for legacy v1beta1\nScale reads. It is kept separate from the aggregate Selector so hidden\nworkloads cannot make /scale fail to converge.";
          type = (types.nullOr types.str);
        };
        "scrubStatus" = mkOption {
          description = "ScrubStatus contains the status of data scrub operations.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusScrubStatus"));
        };
        "selector" = mkOption {
          description = "Selector is the aggregate serialized label selector for pods managed by\nthis cluster. It is not used by the scale subresource.";
          type = types.str;
        };
        "stagedLayoutVersion" = mkOption {
          description = "StagedLayoutVersion is the staged layout version pending application.";
          type = (types.nullOr types.int);
        };
        "stagedRoles" = mkOption {
          description = "StagedRoles is the number of roles in the staged layout.";
          type = (types.nullOr types.int);
        };
        "storageDrain" = mkOption {
          description = "StorageDrain records the single cluster-wide positive-capacity removal and\nblock-migration proof. It excludes every other layout mutation until the\nexact actor completes its Kubernetes handoff.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusStorageDrain"));
        };
        "storageReadyReplicas" = mkOption {
          description = "StorageReadyReplicas is the aggregate number of storage identities that\nare connected and committed in Garage's layout.";
          type = (types.nullOr types.int);
        };
        "storageReplicas" = mkOption {
          description = "StorageReplicas is the aggregate desired/current storage identity count\nacross the default group, ordinary Manual GarageNodes, and node-local\npools. Use ScaleReplicas for the narrow Kubernetes Scale projection.";
          type = (types.nullOr types.int);
        };
        "storageRollout" = mkOption {
          description = "StorageRollout is the controller-owned durable record for the single\nmanaged storage/gateway pod currently being replaced. Nil when no\nparent-controlled rollout handoff is active.";
          type = (
            types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusStorageRollout")
          );
        };
        "storageStats" = mkOption {
          description = "StorageStats contains cluster-wide storage statistics.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusStorageStats"));
        };
        "totalNodes" = mkOption {
          description = "TotalNodes is the total nodes across all clusters (local + remote).";
          type = (types.nullOr types.int);
        };
        "unreachablePeers" = mkOption {
          description = "UnreachablePeers lists peers that have been continuously down beyond the\nsustained-unreachable threshold, each as \"<shortNodeId> (down <duration>)\".\nDrives the PeerUnreachable condition. Empty when all peers are reachable.";
          type = (types.nullOr (types.listOf types.str));
        };
        "workerCount" = mkOption {
          description = "WorkerCount is the total number of background workers.";
          type = (types.nullOr types.int);
        };
        "workers" = mkOption {
          description = "Workers contains detailed information about background workers.";
          type = (types.nullOr (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusWorkers"));
        };
        "workersFailed" = mkOption {
          description = "WorkersFailed is the number of failed workers.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "activeRepairs" = mkOverride 1002 null;
        "autoModePvcHandoffs" = mkOverride 1002 null;
        "blockErrorDetails" = mkOverride 1002 null;
        "blockErrors" = mkOverride 1002 null;
        "buildInfo" = mkOverride 1002 null;
        "clusterId" = mkOverride 1002 null;
        "conditions" = mkOverride 1002 null;
        "drainingNodes" = mkOverride 1002 null;
        "endpoints" = mkOverride 1002 null;
        "factorMigration" = mkOverride 1002 null;
        "gatewayNodesNotInLayout" = mkOverride 1002 null;
        "gatewayReadyReplicas" = mkOverride 1002 null;
        "gatewayReplicas" = mkOverride 1002 null;
        "health" = mkOverride 1002 null;
        "lastOperation" = mkOverride 1002 null;
        "layoutDiagnosis" = mkOverride 1002 null;
        "layoutHistory" = mkOverride 1002 null;
        "layoutPreview" = mkOverride 1002 null;
        "layoutVersion" = mkOverride 1002 null;
        "lifecycleStatus" = mkOverride 1002 null;
        "nodes" = mkOverride 1002 null;
        "observedGeneration" = mkOverride 1002 null;
        "pendingGatewayTombstones" = mkOverride 1002 null;
        "phase" = mkOverride 1002 null;
        "readyReplicas" = mkOverride 1002 null;
        "remoteClusters" = mkOverride 1002 null;
        "resyncQueueLength" = mkOverride 1002 null;
        "scaleReplicas" = mkOverride 1002 null;
        "scaleSelector" = mkOverride 1002 null;
        "scrubStatus" = mkOverride 1002 null;
        "stagedLayoutVersion" = mkOverride 1002 null;
        "stagedRoles" = mkOverride 1002 null;
        "storageDrain" = mkOverride 1002 null;
        "storageReadyReplicas" = mkOverride 1002 null;
        "storageReplicas" = mkOverride 1002 null;
        "storageRollout" = mkOverride 1002 null;
        "storageStats" = mkOverride 1002 null;
        "totalNodes" = mkOverride 1002 null;
        "unreachablePeers" = mkOverride 1002 null;
        "workerCount" = mkOverride 1002 null;
        "workers" = mkOverride 1002 null;
        "workersFailed" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterStatusActiveRepairs" = {

      options = {
        "nodeId" = mkOption {
          description = "NodeID is the node running this repair.";
          type = (types.nullOr types.str);
        };
        "progress" = mkOption {
          description = "Progress is a human-readable progress description.";
          type = (types.nullOr types.str);
        };
        "startedAt" = mkOption {
          description = "StartedAt is when the repair started.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is the repair operation type (Tables, Blocks, Scrub, Rebalance, etc.)";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "nodeId" = mkOverride 1002 null;
        "progress" = mkOverride 1002 null;
        "startedAt" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterStatusAutoModePvcHandoffs" = {

      options = {
        "previousGarageNodeUid" = mkOption {
          description = "PreviousGarageNodeUID is the exact deleted GarageNode incarnation that\nreserved the claim.";
          type = types.str;
        };
        "pvcName" = mkOption {
          description = "PVCName and PVCUID identify the exact retained claim incarnation.";
          type = types.str;
        };
        "pvcUid" = mkOption {
          description = "";
          type = types.str;
        };
        "replacementGarageNodeUid" = mkOption {
          description = "ReplacementGarageNodeUID is the only new GarageNode incarnation allowed\nto consume this handoff.";
          type = (types.nullOr types.str);
        };
        "replacementReservationHash" = mkOption {
          description = "ReplacementReservationHash is a one-way commitment to the nonce placed\non the controller-created replacement GarageNode. It closes the crash gap\nbetween Create and recording the replacement object's API-server UID.";
          type = (types.nullOr types.str);
        };
        "slotName" = mkOption {
          description = "SlotName is the stable Auto-mode slot (for example, cluster-gateway-1).";
          type = types.str;
        };
      };

      config = {
        "replacementGarageNodeUid" = mkOverride 1002 null;
        "replacementReservationHash" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterStatusBlockErrorDetails" = {

      options = {
        "count" = mkOption {
          description = "Count is the total number of blocks with errors.";
          type = (types.nullOr types.int);
        };
        "lastErrorAt" = mkOption {
          description = "LastErrorAt is when the most recent block error occurred.";
          type = (types.nullOr types.str);
        };
        "topErrors" = mkOption {
          description = "TopErrors contains details about the most problematic blocks.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusBlockErrorDetailsTopErrors"
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
    "garage.rajsingh.info.v1beta2.GarageClusterStatusBlockErrorDetailsTopErrors" = {

      options = {
        "blockHash" = mkOption {
          description = "BlockHash is the hash of the affected block.";
          type = (types.nullOr types.str);
        };
        "errorCount" = mkOption {
          description = "ErrorCount is the number of times this block failed to sync.";
          type = (types.nullOr types.int);
        };
        "lastAttempt" = mkOption {
          description = "LastAttempt is when the last sync attempt occurred.";
          type = (types.nullOr types.str);
        };
        "lastError" = mkOption {
          description = "LastError is the most recent error message for this block.";
          type = (types.nullOr types.str);
        };
        "nextRetry" = mkOption {
          description = "NextRetry is when the next sync retry is scheduled.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterStatusBuildInfo" = {

      options = {
        "features" = mkOption {
          description = "Features lists enabled Cargo features.";
          type = (types.nullOr (types.listOf types.str));
        };
        "rustVersion" = mkOption {
          description = "RustVersion is the Rust compiler version used to build Garage.";
          type = (types.nullOr types.str);
        };
        "version" = mkOption {
          description = "Version is the Garage version string.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "features" = mkOverride 1002 null;
        "rustVersion" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterStatusConditions" = {

      options = {
        "lastTransitionTime" = mkOption {
          description = "lastTransitionTime is the last time the condition transitioned from one status to another.\nThis should be when the underlying condition changed.  If that is not known, then using the time when the API field changed is acceptable.";
          type = types.str;
        };
        "message" = mkOption {
          description = "message is a human readable message indicating details about the transition.\nThis may be an empty string.";
          type = (types.withMaxLength 32768 types.str);
        };
        "observedGeneration" = mkOption {
          description = "observedGeneration represents the .metadata.generation that the condition was set based upon.\nFor instance, if .metadata.generation is currently 12, but the .status.conditions[x].observedGeneration is 9, the condition is out of date\nwith respect to the current state of the instance.";
          type = (types.nullOr (types.withMinimum 0 types.int));
        };
        "reason" = mkOption {
          description = "reason contains a programmatic identifier indicating the reason for the condition's last transition.\nProducers of specific condition types may define expected values and meanings for this field,\nand whether the values are considered a guaranteed API.\nThe value should be a CamelCase string.\nThis field may not be empty.";
          type = (types.withMaxLength 1024 (types.withMinLength 1 types.str));
        };
        "status" = mkOption {
          description = "status of the condition, one of True, False, Unknown.";
          type = (
            types.enum [
              "True"
              "False"
              "Unknown"
            ]
          );
        };
        "type" = mkOption {
          description = "type of condition in CamelCase or in foo.example.com/CamelCase.";
          type = (types.withMaxLength 316 types.str);
        };
      };

      config = {
        "observedGeneration" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterStatusEndpoints" = {

      options = {
        "admin" = mkOption {
          description = "Admin is the admin API endpoint.";
          type = (types.nullOr types.str);
        };
        "k2v" = mkOption {
          description = "K2V is the K2V API endpoint.";
          type = (types.nullOr types.str);
        };
        "metrics" = mkOption {
          description = "Metrics is the Prometheus metrics endpoint.";
          type = (types.nullOr types.str);
        };
        "rpc" = mkOption {
          description = "RPC is the internal RPC endpoint.";
          type = (types.nullOr types.str);
        };
        "s3" = mkOption {
          description = "S3 is the S3 API endpoint.";
          type = (types.nullOr types.str);
        };
        "web" = mkOption {
          description = "Web is the web hosting endpoint.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterStatusFactorMigration" = {

      options = {
        "completedAt" = mkOption {
          description = "CompletedAt is when the migration finished (Completed or Failed).";
          type = (types.nullOr types.str);
        };
        "force" = mkOption {
          description = "Force records whether the trigger carried the ,force flag (overriding the\ndangerous-mode / pending-tombstone guards). Captured at start because the\nannotation is consumed immediately.";
          type = (types.nullOr types.bool);
        };
        "fromFactor" = mkOption {
          description = "FromFactor is the replication factor before the migration.";
          type = (types.nullOr types.int);
        };
        "message" = mkOption {
          description = "Message is a human-readable description of the current phase or failure.";
          type = (types.nullOr types.str);
        };
        "phase" = mkOption {
          description = "Phase is the current migration phase.";
          type = (
            types.nullOr (
              types.enum [
                "Validating"
                "ScalingDown"
                "Purging"
                "Verifying"
                "RebuildingLayout"
                "Converging"
                "Completed"
                "Failed"
              ]
            )
          );
        };
        "phaseStartedAt" = mkOption {
          description = "PhaseStartedAt is when the current Phase was entered. It is reset on every\nphase transition and bounds each wait phase independently of the overall\nmigration duration, so a single phase that hangs (e.g. a node whose\nstatus.nodeId never repopulates after restart) trips the stuck guard\nrather than the whole migration sharing one global deadline.";
          type = (types.nullOr types.str);
        };
        "purgeId" = mkOption {
          description = "PurgeID uniquely identifies this migration; it is the marker-file suffix the\nper-node init container uses so the on-disk cluster_layout is deleted exactly\nonce even across extra restarts.";
          type = (types.nullOr types.str);
        };
        "startedAt" = mkOption {
          description = "StartedAt is when the migration began.";
          type = (types.nullOr types.str);
        };
        "toFactor" = mkOption {
          description = "ToFactor is the target replication factor.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "completedAt" = mkOverride 1002 null;
        "force" = mkOverride 1002 null;
        "fromFactor" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "phase" = mkOverride 1002 null;
        "phaseStartedAt" = mkOverride 1002 null;
        "purgeId" = mkOverride 1002 null;
        "startedAt" = mkOverride 1002 null;
        "toFactor" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterStatusHealth" = {

      options = {
        "available" = mkOption {
          description = "Available indicates if quorum is available.";
          type = (types.nullOr types.bool);
        };
        "connectedNodes" = mkOption {
          description = "ConnectedNodes is the number of currently connected nodes.";
          type = (types.nullOr types.int);
        };
        "healthy" = mkOption {
          description = "Healthy indicates if all nodes are connected.";
          type = (types.nullOr types.bool);
        };
        "knownNodes" = mkOption {
          description = "KnownNodes is the number of nodes seen in cluster.";
          type = (types.nullOr types.int);
        };
        "partitions" = mkOption {
          description = "Partitions is the total partitions in layout.";
          type = (types.nullOr types.int);
        };
        "partitionsAllOk" = mkOption {
          description = "PartitionsAllOK is partitions with all nodes connected.";
          type = (types.nullOr types.int);
        };
        "partitionsQuorum" = mkOption {
          description = "PartitionsQuorum is partitions with quorum connectivity.";
          type = (types.nullOr types.int);
        };
        "status" = mkOption {
          description = "Status is the overall cluster status.";
          type = (types.nullOr types.str);
        };
        "storageNodes" = mkOption {
          description = "StorageNodes is the number of storage nodes in layout.";
          type = (types.nullOr types.int);
        };
        "storageNodesOk" = mkOption {
          description = "StorageNodesOK is the number of connected storage nodes.";
          type = (types.nullOr types.int);
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
    "garage.rajsingh.info.v1beta2.GarageClusterStatusLastOperation" = {

      options = {
        "error" = mkOption {
          description = "Error contains the error message when Succeeded is false.";
          type = (types.nullOr types.str);
        };
        "succeeded" = mkOption {
          description = "Succeeded indicates the operation completed without error.";
          type = (types.nullOr types.bool);
        };
        "triggeredAt" = mkOption {
          description = "TriggeredAt is when the operation was triggered.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is the operation type.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "error" = mkOverride 1002 null;
        "succeeded" = mkOverride 1002 null;
        "triggeredAt" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterStatusLayoutHistory" = {

      options = {
        "currentVersion" = mkOption {
          description = "CurrentVersion is the current layout version.";
          type = (types.nullOr types.int);
        };
        "minAck" = mkOption {
          description = "MinAck is the minimum acknowledged layout version by all nodes.";
          type = (types.nullOr types.int);
        };
        "versions" = mkOption {
          description = "Versions contains at most 64 current, draining, and recent historical\nlayout versions for diagnosis. Controller safety decisions read Garage's\ncomplete live layout history instead of relying on this bounded projection.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusLayoutHistoryVersions")
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
    "garage.rajsingh.info.v1beta2.GarageClusterStatusLayoutHistoryVersions" = {

      options = {
        "gatewayNodes" = mkOption {
          description = "GatewayNodes is the number of gateway nodes in this version.";
          type = (types.nullOr types.int);
        };
        "status" = mkOption {
          description = "Status is the version status (Current, Draining, Historical).";
          type = (types.nullOr types.str);
        };
        "storageNodes" = mkOption {
          description = "StorageNodes is the number of storage nodes in this version.";
          type = (types.nullOr types.int);
        };
        "version" = mkOption {
          description = "Version is the layout version number.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "gatewayNodes" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
        "storageNodes" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterStatusLayoutPreview" = {

      options = {
        "dataTransferEstimate" = mkOption {
          description = "DataTransferEstimate is a human-readable estimate of data movement.";
          type = (types.nullOr types.str);
        };
        "nodesAdded" = mkOption {
          description = "NodesAdded shows node IDs that would be added to the layout.";
          type = (types.nullOr (types.listOf types.str));
        };
        "nodesModified" = mkOption {
          description = "NodesModified shows node IDs with changed configuration.";
          type = (types.nullOr (types.listOf types.str));
        };
        "nodesRemoved" = mkOption {
          description = "NodesRemoved shows node IDs that would be removed from the layout.";
          type = (types.nullOr (types.listOf types.str));
        };
        "partitionTransfers" = mkOption {
          description = "PartitionTransfers is the estimated number of partition transfers.";
          type = (types.nullOr types.int);
        };
        "zonesAffected" = mkOption {
          description = "ZonesAffected shows which zones would be affected by the changes.";
          type = (types.nullOr (types.listOf types.str));
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
    "garage.rajsingh.info.v1beta2.GarageClusterStatusLifecycleStatus" = {

      options = {
        "lastCompleted" = mkOption {
          description = "LastCompleted is when the last lifecycle worker run completed.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "lastCompleted" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterStatusNodes" = {

      options = {
        "capacity" = mkOption {
          description = "Capacity is the storage capacity of the node.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "connected" = mkOption {
          description = "Connected indicates if the node is connected to the cluster.";
          type = (types.nullOr types.bool);
        };
        "dataDiskAvailable" = mkOption {
          description = "DataDiskAvailable is the available space on data disk.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "dataDiskTotal" = mkOption {
          description = "DataDiskTotal is the total space on data disk.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "gateway" = mkOption {
          description = "Gateway indicates if the node is gateway-only.";
          type = (types.nullOr types.bool);
        };
        "metadataDiskAvailable" = mkOption {
          description = "MetadataDiskAvailable is the available space on metadata disk.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "metadataDiskTotal" = mkOption {
          description = "MetadataDiskTotal is the total space on metadata disk.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "nodeId" = mkOption {
          description = "NodeID is the public key of the node.";
          type = (types.nullOr types.str);
        };
        "podName" = mkOption {
          description = "PodName is the name of the pod running this node.";
          type = (types.nullOr types.str);
        };
        "tier" = mkOption {
          description = "Tier is \"storage\" or \"gateway\" depending on which tier this node belongs to.";
          type = (types.nullOr types.str);
        };
        "version" = mkOption {
          description = "Version is the Garage version running on this node.";
          type = (types.nullOr types.str);
        };
        "zone" = mkOption {
          description = "Zone is the zone assignment of the node.";
          type = (types.nullOr types.str);
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
        "tier" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
        "zone" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterStatusRemoteClusters" = {

      options = {
        "connected" = mkOption {
          description = "Connected indicates if we can reach this cluster.";
          type = (types.nullOr types.bool);
        };
        "healthyNodes" = mkOption {
          description = "HealthyNodes is the number of healthy nodes.";
          type = (types.nullOr types.int);
        };
        "lastSeen" = mkOption {
          description = "LastSeen is when we last successfully connected.";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "Name is the cluster name.";
          type = (types.nullOr types.str);
        };
        "nodes" = mkOption {
          description = "Nodes is the number of nodes in this cluster.";
          type = (types.nullOr types.int);
        };
        "zone" = mkOption {
          description = "Zone is the cluster's zone.";
          type = (types.nullOr types.str);
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
    "garage.rajsingh.info.v1beta2.GarageClusterStatusScrubStatus" = {

      options = {
        "corruptedBlocks" = mkOption {
          description = "CorruptedBlocks is the number of corrupted blocks found in the last scrub.";
          type = (types.nullOr types.int);
        };
        "lastCompleted" = mkOption {
          description = "LastCompleted is when the last scrub completed.";
          type = (types.nullOr types.str);
        };
        "nextRun" = mkOption {
          description = "NextRun is when the next scrub is scheduled to run.";
          type = (types.nullOr types.str);
        };
        "nodeStatuses" = mkOption {
          description = "NodeStatuses contains per-node scrub status.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusScrubStatusNodeStatuses")
            )
          );
        };
        "paused" = mkOption {
          description = "Paused indicates if the scrub is paused.";
          type = (types.nullOr types.bool);
        };
        "progress" = mkOption {
          description = "Progress is a human-readable progress description.";
          type = (types.nullOr types.str);
        };
        "running" = mkOption {
          description = "Running indicates if a scrub is currently running on any node.";
          type = (types.nullOr types.bool);
        };
        "tranquilityLevel" = mkOption {
          description = "TranquilityLevel is the current tranquility setting.";
          type = (types.nullOr types.int);
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
    "garage.rajsingh.info.v1beta2.GarageClusterStatusScrubStatusNodeStatuses" = {

      options = {
        "errorsFound" = mkOption {
          description = "ErrorsFound is the number of errors found on this node.";
          type = (types.nullOr types.int);
        };
        "itemsChecked" = mkOption {
          description = "ItemsChecked is the number of items checked.";
          type = (types.nullOr types.int);
        };
        "nodeId" = mkOption {
          description = "NodeID is the node identifier.";
          type = (types.nullOr types.str);
        };
        "progress" = mkOption {
          description = "Progress percentage (0-100).";
          type = (types.nullOr types.int);
        };
        "running" = mkOption {
          description = "Running indicates if scrub is running on this node.";
          type = (types.nullOr types.bool);
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
    "garage.rajsingh.info.v1beta2.GarageClusterStatusStorageDrain" = {

      options = {
        "actor" = mkOption {
          description = "Actor is the exact object authorized to advance this transaction.";
          type = (submoduleOf "garage.rajsingh.info.v1beta2.GarageClusterStatusStorageDrainActor");
        };
        "completedAt" = mkOption {
          description = "CompletedAt is set only after exact repair workers completed cleanly and\nevery enabled block-resync worker passed the terminal safety checks. The\ntransaction remains active until Actor completes its Kubernetes handoff.";
          type = (types.nullOr types.str);
        };
        "errorCount" = mkOption {
          description = "ErrorCount is the aggregate number of block resync errors.";
          type = types.int;
        };
        "layoutVersion" = mkOption {
          description = "LayoutVersion is the current Garage layout version observed with these\nverification processes and queue counters.";
          type = types.int;
        };
        "managedPodUids" = mkOption {
          description = "ManagedPodUIDs fingerprints the exact locally managed Garage processes\nobserved when this proof revision started. Any pod replacement invalidates\nworker-ID baselines because Garage worker counters can restart from zero.\nKeys are full Garage node IDs and values are Kubernetes Pod UIDs.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "queueLength" = mkOption {
          description = "QueueLength is the observed aggregate block-resync queue depth. It is\ninformational: Garage also queues future garbage collection, so readiness\nis based on completed repair workers and idle resync workers instead.";
          type = types.int;
        };
        "quietSince" = mkOption {
          description = "QuietSince starts after every exact repair worker completes without errors\nand resync-worker error baselines are recorded. The operator waits through\nGarage's maximum known delayed-resync interval, then requires every exact\nresync worker idle and error-free before a process may be stopped.";
          type = (types.nullOr types.str);
        };
        "removedStorageNodeIds" = mkOption {
          description = "RemovedStorageNodeIDs is the sorted positive-capacity subset whose removal\nrequires block-migration proof. Recording it before Apply keeps the safety\ngate durable across controller crashes and Admin API failures.";
          type = (types.listOf types.str);
        };
        "repairBaselines" = mkOption {
          description = "RepairBaselines records each storage node's highest worker ID before the\noperator launches a transaction-specific Blocks repair. It is persisted\nbefore launch so a crash cannot lose ownership of the resulting worker.";
          type = (types.nullOr (types.attrsOf types.int));
        };
        "repairWorkerIds" = mkOption {
          description = "RepairWorkerIDs records the exact post-baseline Blocks repair worker whose\nclean completion was observed on each source and destination process in\nVerificationNodeIDs.";
          type = (types.nullOr (types.attrsOf types.int));
        };
        "requiresEmptyQueue" = mkOption {
          description = "RequiresEmptyQueue is true when at least one verification process is not\nproven to use this GarageCluster's authoritative RPC timeout. In that case\nthe normally informational future-work queue must also become empty.";
          type = types.bool;
        };
        "resyncErrorBaselines" = mkOption {
          description = "ResyncErrorBaselines records the cumulative error counter of every exact\nenabled block-resync worker after all repair scans complete. Any increase\nrestarts the repair transaction.";
          type = (types.nullOr (types.attrsOf types.int));
        };
        "roleRemovalNodeIds" = mkOption {
          description = "RoleRemovalNodeIDs is the sorted set of every exact Garage layout role this\nactor is authorized to remove, including capacityless gateway roles in a\nunified cluster Drain.";
          type = (types.listOf types.str);
        };
        "startedAt" = mkOption {
          description = "StartedAt records when the pre-Apply removal intent became durable.";
          type = types.str;
        };
        "targetHash" = mkOption {
          description = "TargetHash fingerprints both normalized target sets. Every status\nupdate compares both transactionId and targetHash so a stale reconcile\ncannot overwrite a newer target revision owned by the same actor.";
          type = types.str;
        };
        "transactionId" = mkOption {
          description = "TransactionID distinguishes separate drains owned by the same object UID.";
          type = types.str;
        };
        "unavailableSourceNodeIds" = mkOption {
          description = "UnavailableSourceNodeIDs is the sorted subset of removedStorageNodeIds\nwhose processes and local disks were explicitly acknowledged as\npermanently lost. Those sources cannot run the normal Blocks scan; the\nterminal proof instead covers every surviving positive-capacity\ndestination after an administrator removes the exact dead role through\nGarage's recovery workflow. Data present only on a listed source may be\nlost.";
          type = (types.nullOr (types.listOf types.str));
        };
        "verificationNodeIds" = mkOption {
          description = "VerificationNodeIDs is the sorted union of removed source processes and\ncurrent positive-capacity destinations covered by this transaction's\ncompleted block-repair scans.";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "completedAt" = mkOverride 1002 null;
        "managedPodUids" = mkOverride 1002 null;
        "quietSince" = mkOverride 1002 null;
        "repairBaselines" = mkOverride 1002 null;
        "repairWorkerIds" = mkOverride 1002 null;
        "resyncErrorBaselines" = mkOverride 1002 null;
        "unavailableSourceNodeIds" = mkOverride 1002 null;
        "verificationNodeIds" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterStatusStorageDrainActor" = {

      options = {
        "apiVersion" = mkOption {
          description = "APIVersion is the actor's Kubernetes API version.";
          type = types.str;
        };
        "kind" = mkOption {
          description = "Kind is GarageCluster for a cluster-wide Drain deletion or GarageNode for\none logical storage member's permanent role removal.";
          type = (
            types.enum [
              "GarageCluster"
              "GarageNode"
            ]
          );
        };
        "name" = mkOption {
          description = "Name is the actor's Kubernetes object name.";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "Namespace is the actor's Kubernetes namespace.";
          type = types.str;
        };
        "uid" = mkOption {
          description = "UID is the immutable Kubernetes UID of the actor incarnation.";
          type = types.str;
        };
      };

      config = { };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterStatusStorageRollout" = {

      options = {
        "clusterGeneration" = mkOption {
          description = "ClusterGeneration is the most recent recovery-safe GarageCluster spec\ngeneration published into this actor's desired workload template.";
          type = (types.nullOr types.int);
        };
        "desiredConfigHash" = mkOption {
          description = "DesiredConfigHash is the rendered Garage configuration revision.";
          type = types.str;
        };
        "desiredPodSpecHash" = mkOption {
          description = "DesiredPodSpecHash is the operator-computed pod template revision.";
          type = types.str;
        };
        "garageNodeGeneration" = mkOption {
          description = "GarageNodeGeneration is the exact actor's most recently published\nworkload-safe spec generation, including the generated GarageNode behind a\nnode-local-pool actor.";
          type = (types.nullOr types.int);
        };
        "garageNodeId" = mkOption {
          description = "GarageNodeID is the exact Garage identity reported by the selected actor\nbefore its Pod is deleted. A replacement must rediscover this same identity;\na new ID under the same Kubernetes objects is never accepted as a handoff.";
          type = types.str;
        };
        "garageNodeName" = mkOption {
          description = "GarageNodeName identifies a StatefulSet-backed PVC, SMB, or gateway actor.\nMutually exclusive with NodeLocalPoolName and KubernetesNodeName.";
          type = (types.nullOr types.str);
        };
        "garageNodeUid" = mkOption {
          description = "GarageNodeUID anchors the actor to one immutable GarageNode incarnation.\nIt is recorded for StatefulSet and node-local-pool actors alike.";
          type = types.str;
        };
        "kubernetesNodeName" = mkOption {
          description = "KubernetesNodeName identifies the Kubernetes Node represented by a\nnode-local-pool actor.";
          type = (types.nullOr types.str);
        };
        "kubernetesNodeUid" = mkOption {
          description = "KubernetesNodeUID anchors a node-local-pool actor to the Kubernetes Node\nincarnation whose HostPath storage was validated. Empty for StatefulSets.";
          type = (types.nullOr types.str);
        };
        "nodeLocalPoolName" = mkOption {
          description = "NodeLocalPoolName identifies a spec.storage.nodeLocalPools entry.";
          type = (types.nullOr types.str);
        };
        "persistentVolumeClaims" = mkOption {
          description = "PersistentVolumeClaims anchors a StatefulSet-backed actor to every exact\nPVC mounted by the Pod selected for replacement. Recreated/deleting claims\nfail closed so controller-incarnation recovery cannot bind empty storage or\nsilently create a new Garage identity under a reused claim name. Empty for\nnode-local-pool HostPath actors.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "garage.rajsingh.info.v1beta2.GarageClusterStatusStorageRolloutPersistentVolumeClaims"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "previousPodUid" = mkOption {
          description = "PreviousPodUID is persisted before the OnDelete pod is deleted. Recovery\nnever accepts this UID as the completed replacement.";
          type = types.str;
        };
        "recoveryPodName" = mkOption {
          description = "RecoveryPodName and RecoveryPodUID identify the one failed replacement\ndurably selected for retry deletion. They are written before DELETE and\nretained until that exact UID is absent, making the operation idempotent\nacross manager and API failures. Both are empty when no retry deletion is\npending.";
          type = (types.nullOr types.str);
        };
        "recoveryPodUid" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "recoveryRequest" = mkOption {
          description = "RecoveryRequest is the last recover-storage-rollout annotation nonce the\ncontroller durably consumed before deleting a failed replacement again.";
          type = (types.nullOr types.str);
        };
        "retiredWorkloadUids" = mkOption {
          description = "RetiredWorkloadUIDs records workload-controller incarnations that were\nreplaced behind a scheduling fence. Late Pods from these exact UIDs remain\nidentifiable without trusting reused names; node-local-pool recovery waits\nfor them to disappear rather than deleting healthy non-candidate members.\nRecovery fails closed before a 33rd retired controller incarnation so this\nexact old-Pod exclusion set remains bounded in parent status.";
          type = (types.nullOr (types.listOf types.str));
        };
        "statefulSetWorkloadRecreationSafe" = mkOption {
          description = "StatefulSetWorkloadRecreationSafe records that the selected StatefulSet's\nvolumeClaimTemplate retention policy does not delete claims when the\nStatefulSet is deleted. It is false for node-local-pool actors and causes missing\nStatefulSet recovery to fail closed when claim retention was unsafe.";
          type = (types.nullOr types.bool);
        };
        "workloadFenced" = mkOption {
          description = "WorkloadFenced is true after a replacement StatefulSet/DaemonSet UID was\nCAS-adopted but before that controller was allowed to schedule its first\nPod (replicas=0 for StatefulSet, impossible nodeSelector for DaemonSet).";
          type = (types.nullOr types.bool);
        };
        "workloadUid" = mkOption {
          description = "WorkloadUID is the exact StatefulSet or DaemonSet controller incarnation\nauthorized to create and replace this actor's Pod.";
          type = types.str;
        };
      };

      config = {
        "clusterGeneration" = mkOverride 1002 null;
        "garageNodeGeneration" = mkOverride 1002 null;
        "garageNodeName" = mkOverride 1002 null;
        "kubernetesNodeName" = mkOverride 1002 null;
        "kubernetesNodeUid" = mkOverride 1002 null;
        "nodeLocalPoolName" = mkOverride 1002 null;
        "persistentVolumeClaims" = mkOverride 1002 null;
        "recoveryPodName" = mkOverride 1002 null;
        "recoveryPodUid" = mkOverride 1002 null;
        "recoveryRequest" = mkOverride 1002 null;
        "retiredWorkloadUids" = mkOverride 1002 null;
        "statefulSetWorkloadRecreationSafe" = mkOverride 1002 null;
        "workloadFenced" = mkOverride 1002 null;
      };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterStatusStorageRolloutPersistentVolumeClaims" = {

      options = {
        "name" = mkOption {
          description = "Name is the namespaced PVC referenced by the selected Pod.";
          type = types.str;
        };
        "uid" = mkOption {
          description = "UID is the exact Kubernetes PVC incarnation that contains the actor's\nmetadata/data at selection time.";
          type = types.str;
        };
      };

      config = { };

    };
    "garage.rajsingh.info.v1beta2.GarageClusterStatusStorageStats" = {

      options = {
        "availableCapacity" = mkOption {
          description = "AvailableCapacity is the available storage across all nodes.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "healthyPartitions" = mkOption {
          description = "HealthyPartitions is the number of partitions with full redundancy.";
          type = (types.nullOr types.int);
        };
        "totalCapacity" = mkOption {
          description = "TotalCapacity is the total storage capacity across all nodes.";
          type = (types.nullOr (types.either types.int types.str));
        };
        "totalPartitions" = mkOption {
          description = "TotalPartitions is the total number of partitions in the layout.";
          type = (types.nullOr types.int);
        };
        "usedCapacity" = mkOption {
          description = "UsedCapacity is the used storage across all nodes.";
          type = (types.nullOr (types.either types.int types.str));
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
    "garage.rajsingh.info.v1beta2.GarageClusterStatusWorkers" = {

      options = {
        "busy" = mkOption {
          description = "Busy is the number of busy/active workers.";
          type = (types.nullOr types.int);
        };
        "errored" = mkOption {
          description = "Errored is the number of workers with errors.";
          type = (types.nullOr types.int);
        };
        "errors" = mkOption {
          description = "Errors contains details about worker errors.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "garage.rajsingh.info.v1beta2.GarageClusterStatusWorkersErrors"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "idle" = mkOption {
          description = "Idle is the number of idle workers.";
          type = (types.nullOr types.int);
        };
        "total" = mkOption {
          description = "Total is the total number of background workers.";
          type = (types.nullOr types.int);
        };
        "variables" = mkOption {
          description = "Variables contains runtime worker configuration variables.";
          type = (types.nullOr (types.attrsOf types.str));
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
    "garage.rajsingh.info.v1beta2.GarageClusterStatusWorkersErrors" = {

      options = {
        "consecutiveErrors" = mkOption {
          description = "ConsecutiveErrors is the count of consecutive errors.";
          type = (types.nullOr types.int);
        };
        "lastError" = mkOption {
          description = "LastError is the last error message.";
          type = (types.nullOr types.str);
        };
        "lastErrorSecsAgo" = mkOption {
          description = "LastErrorSecsAgo is seconds since the last error.";
          type = (types.nullOr types.int);
        };
        "name" = mkOption {
          description = "Name is the worker name.";
          type = (types.nullOr types.str);
        };
        "workerId" = mkOption {
          description = "WorkerID is the worker identifier.";
          type = (types.nullOr types.int);
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

  };
in
{
  # all resource versions
  options = {
    resources = {
      "garage.rajsingh.info"."v1alpha1"."GarageAdminToken" = mkOption {
        description = "";
        type = (
          types.attrsOf (
            submoduleForDefinition "garage.rajsingh.info.v1alpha1.GarageAdminToken" "garageadmintokens"
              "GarageAdminToken"
              "garage.rajsingh.info"
              "v1alpha1"
          )
        );
        default = { };
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
        default = { };
      };
      "garage.rajsingh.info"."v1alpha1"."GarageCluster" = mkOption {
        description = "";
        type = (
          types.attrsOf (
            submoduleForDefinition "garage.rajsingh.info.v1alpha1.GarageCluster" "garageclusters"
              "GarageCluster"
              "garage.rajsingh.info"
              "v1alpha1"
          )
        );
        default = { };
      };
      "garage.rajsingh.info"."v1alpha1"."GarageKey" = mkOption {
        description = "";
        type = (
          types.attrsOf (
            submoduleForDefinition "garage.rajsingh.info.v1alpha1.GarageKey" "garagekeys" "GarageKey"
              "garage.rajsingh.info"
              "v1alpha1"
          )
        );
        default = { };
      };
      "garage.rajsingh.info"."v1alpha1"."GarageNode" = mkOption {
        description = "";
        type = (
          types.attrsOf (
            submoduleForDefinition "garage.rajsingh.info.v1alpha1.GarageNode" "garagenodes" "GarageNode"
              "garage.rajsingh.info"
              "v1alpha1"
          )
        );
        default = { };
      };
      "garage.rajsingh.info"."v1beta1"."GarageAdminToken" = mkOption {
        description = "GarageAdminToken is the Schema for the garageadmintokens API\nIt manages static Admin API bootstrap material for Garage clusters.";
        type = (
          types.attrsOf (
            submoduleForDefinition "garage.rajsingh.info.v1beta1.GarageAdminToken" "garageadmintokens"
              "GarageAdminToken"
              "garage.rajsingh.info"
              "v1beta1"
          )
        );
        default = { };
      };
      "garage.rajsingh.info"."v1beta1"."GarageBucket" = mkOption {
        description = "GarageBucket is the Schema for the garagebuckets API";
        type = (
          types.attrsOf (
            submoduleForDefinition "garage.rajsingh.info.v1beta1.GarageBucket" "garagebuckets" "GarageBucket"
              "garage.rajsingh.info"
              "v1beta1"
          )
        );
        default = { };
      };
      "garage.rajsingh.info"."v1beta1"."GarageKey" = mkOption {
        description = "GarageKey is the Schema for the garagekeys API";
        type = (
          types.attrsOf (
            submoduleForDefinition "garage.rajsingh.info.v1beta1.GarageKey" "garagekeys" "GarageKey"
              "garage.rajsingh.info"
              "v1beta1"
          )
        );
        default = { };
      };
      "garage.rajsingh.info"."v1beta1"."GarageNode" = mkOption {
        description = "GarageNode is the Schema for the garagenodes API";
        type = (
          types.attrsOf (
            submoduleForDefinition "garage.rajsingh.info.v1beta1.GarageNode" "garagenodes" "GarageNode"
              "garage.rajsingh.info"
              "v1beta1"
          )
        );
        default = { };
      };
      "garage.rajsingh.info"."v1beta1"."GarageReferenceGrant" = mkOption {
        description = "GarageReferenceGrant grants permission for resources in other namespaces to\nreference GarageCluster, GarageBucket, or GarageKey resources in this namespace.\nGarageAdminToken remains a listed source kind for schema/status compatibility,\nbut its static credential path is namespace-local and does not accept a grant.\n\nThis resource must be created in the destination namespace (where the\nreferenced GarageCluster, GarageBucket, or GarageKey lives). Only admins of that namespace can\ncreate it, so tenants cannot self-grant cross-namespace access.\n\nExample: allow GarageKey objects in namespace \"team-b\" to reference\nGarageCluster \"my-cluster\" in namespace \"storage-admin\":\n\n\tapiVersion: garage.rajsingh.info/v1beta1\n\tkind: GarageReferenceGrant\n\tmetadata:\n\t  namespace: storage-admin\n\tspec:\n\t  from:\n\t    - kind: GarageKey\n\t      namespace: team-b\n\t  to:\n\t    - kind: GarageCluster\n\t      name: my-cluster\n\nNamespace selectors provide the same authorization using labels. Namespace\nlabels are part of this authorization decision: namespaces that gain a\nmatching label gain access, and namespaces that lose it no longer match.";
        type = (
          types.attrsOf (
            submoduleForDefinition "garage.rajsingh.info.v1beta1.GarageReferenceGrant" "garagereferencegrants"
              "GarageReferenceGrant"
              "garage.rajsingh.info"
              "v1beta1"
          )
        );
        default = { };
      };
      "garage.rajsingh.info"."v1beta2"."GarageCluster" = mkOption {
        description = "GarageCluster is the Schema for the garageclusters API.";
        type = (
          types.attrsOf (
            submoduleForDefinition "garage.rajsingh.info.v1beta2.GarageCluster" "garageclusters" "GarageCluster"
              "garage.rajsingh.info"
              "v1beta2"
          )
        );
        default = { };
      };

    }
    // {
      "garageAdminTokens" = mkOption {
        description = "GarageAdminToken is the Schema for the garageadmintokens API\nIt manages static Admin API bootstrap material for Garage clusters.";
        type = (
          types.attrsOf (
            submoduleForDefinition "garage.rajsingh.info.v1beta1.GarageAdminToken" "garageadmintokens"
              "GarageAdminToken"
              "garage.rajsingh.info"
              "v1beta1"
          )
        );
        default = { };
      };
      "garageBuckets" = mkOption {
        description = "GarageBucket is the Schema for the garagebuckets API";
        type = (
          types.attrsOf (
            submoduleForDefinition "garage.rajsingh.info.v1beta1.GarageBucket" "garagebuckets" "GarageBucket"
              "garage.rajsingh.info"
              "v1beta1"
          )
        );
        default = { };
      };
      "garageClusters" = mkOption {
        description = "GarageCluster is the Schema for the garageclusters API.";
        type = (
          types.attrsOf (
            submoduleForDefinition "garage.rajsingh.info.v1beta2.GarageCluster" "garageclusters" "GarageCluster"
              "garage.rajsingh.info"
              "v1beta2"
          )
        );
        default = { };
      };
      "garageKeys" = mkOption {
        description = "GarageKey is the Schema for the garagekeys API";
        type = (
          types.attrsOf (
            submoduleForDefinition "garage.rajsingh.info.v1beta1.GarageKey" "garagekeys" "GarageKey"
              "garage.rajsingh.info"
              "v1beta1"
          )
        );
        default = { };
      };
      "garageNodes" = mkOption {
        description = "GarageNode is the Schema for the garagenodes API";
        type = (
          types.attrsOf (
            submoduleForDefinition "garage.rajsingh.info.v1beta1.GarageNode" "garagenodes" "GarageNode"
              "garage.rajsingh.info"
              "v1beta1"
          )
        );
        default = { };
      };
      "garageReferenceGrants" = mkOption {
        description = "GarageReferenceGrant grants permission for resources in other namespaces to\nreference GarageCluster, GarageBucket, or GarageKey resources in this namespace.\nGarageAdminToken remains a listed source kind for schema/status compatibility,\nbut its static credential path is namespace-local and does not accept a grant.\n\nThis resource must be created in the destination namespace (where the\nreferenced GarageCluster, GarageBucket, or GarageKey lives). Only admins of that namespace can\ncreate it, so tenants cannot self-grant cross-namespace access.\n\nExample: allow GarageKey objects in namespace \"team-b\" to reference\nGarageCluster \"my-cluster\" in namespace \"storage-admin\":\n\n\tapiVersion: garage.rajsingh.info/v1beta1\n\tkind: GarageReferenceGrant\n\tmetadata:\n\t  namespace: storage-admin\n\tspec:\n\t  from:\n\t    - kind: GarageKey\n\t      namespace: team-b\n\t  to:\n\t    - kind: GarageCluster\n\t      name: my-cluster\n\nNamespace selectors provide the same authorization using labels. Namespace\nlabels are part of this authorization decision: namespaces that gain a\nmatching label gain access, and namespaces that lose it no longer match.";
        type = (
          types.attrsOf (
            submoduleForDefinition "garage.rajsingh.info.v1beta1.GarageReferenceGrant" "garagereferencegrants"
              "GarageReferenceGrant"
              "garage.rajsingh.info"
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
      {
        name = "garageadmintokens";
        group = "garage.rajsingh.info";
        version = "v1beta1";
        kind = "GarageAdminToken";
        attrName = "garageAdminTokens";
      }
      {
        name = "garagebuckets";
        group = "garage.rajsingh.info";
        version = "v1beta1";
        kind = "GarageBucket";
        attrName = "garageBuckets";
      }
      {
        name = "garagekeys";
        group = "garage.rajsingh.info";
        version = "v1beta1";
        kind = "GarageKey";
        attrName = "garageKeys";
      }
      {
        name = "garagenodes";
        group = "garage.rajsingh.info";
        version = "v1beta1";
        kind = "GarageNode";
        attrName = "garageNodes";
      }
      {
        name = "garagereferencegrants";
        group = "garage.rajsingh.info";
        version = "v1beta1";
        kind = "GarageReferenceGrant";
        attrName = "garageReferenceGrants";
      }
      {
        name = "garageclusters";
        group = "garage.rajsingh.info";
        version = "v1beta2";
        kind = "GarageCluster";
        attrName = "garageClusters";
      }
    ];

    resources = {
      "garage.rajsingh.info"."v1beta1"."GarageAdminToken" =
        mkAliasDefinitions
          options.resources."garageAdminTokens";
      "garage.rajsingh.info"."v1beta1"."GarageBucket" =
        mkAliasDefinitions
          options.resources."garageBuckets";
      "garage.rajsingh.info"."v1beta2"."GarageCluster" =
        mkAliasDefinitions
          options.resources."garageClusters";
      "garage.rajsingh.info"."v1beta1"."GarageKey" = mkAliasDefinitions options.resources."garageKeys";
      "garage.rajsingh.info"."v1beta1"."GarageNode" = mkAliasDefinitions options.resources."garageNodes";
      "garage.rajsingh.info"."v1beta1"."GarageReferenceGrant" =
        mkAliasDefinitions
          options.resources."garageReferenceGrants";

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
      {
        group = "garage.rajsingh.info";
        version = "v1beta1";
        kind = "GarageAdminToken";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "garage.rajsingh.info";
        version = "v1beta1";
        kind = "GarageBucket";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "garage.rajsingh.info";
        version = "v1beta1";
        kind = "GarageKey";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "garage.rajsingh.info";
        version = "v1beta1";
        kind = "GarageNode";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "garage.rajsingh.info";
        version = "v1beta1";
        kind = "GarageReferenceGrant";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "garage.rajsingh.info";
        version = "v1beta2";
        kind = "GarageCluster";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
    ];
  };
}
