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
    "longhorn.io.v1beta2.BackingImage" = {

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
          description = "BackingImageSpec defines the desired state of the Longhorn backing image";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.BackingImageSpec"));
        };
        "status" = mkOption {
          description = "BackingImageStatus defines the observed state of the Longhorn backing image status";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.BackingImageStatus"));
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
    "longhorn.io.v1beta2.BackingImageDataSource" = {

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
          description = "BackingImageDataSourceSpec defines the desired state of the Longhorn backing image data source";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.BackingImageDataSourceSpec"));
        };
        "status" = mkOption {
          description = "BackingImageDataSourceStatus defines the observed state of the Longhorn backing image data source";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.BackingImageDataSourceStatus"));
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
    "longhorn.io.v1beta2.BackingImageDataSourceSpec" = {

      options = {
        "checksum" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "diskPath" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "diskUUID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "fileTransferred" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "nodeID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "parameters" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "sourceType" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "uuid" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "checksum" = mkOverride 1002 null;
        "diskPath" = mkOverride 1002 null;
        "diskUUID" = mkOverride 1002 null;
        "fileTransferred" = mkOverride 1002 null;
        "nodeID" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
        "sourceType" = mkOverride 1002 null;
        "uuid" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.BackingImageDataSourceStatus" = {

      options = {
        "checksum" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "currentState" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "ip" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "ownerID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "progress" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "runningParameters" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "size" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "storageIP" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "checksum" = mkOverride 1002 null;
        "currentState" = mkOverride 1002 null;
        "ip" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
        "progress" = mkOverride 1002 null;
        "runningParameters" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "storageIP" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.BackingImageManager" = {

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
          description = "BackingImageManagerSpec defines the desired state of the Longhorn backing image manager";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.BackingImageManagerSpec"));
        };
        "status" = mkOption {
          description = "BackingImageManagerStatus defines the observed state of the Longhorn backing image manager";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.BackingImageManagerStatus"));
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
    "longhorn.io.v1beta2.BackingImageManagerSpec" = {

      options = {
        "backingImages" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "diskPath" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "diskUUID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "image" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "nodeID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "backingImages" = mkOverride 1002 null;
        "diskPath" = mkOverride 1002 null;
        "diskUUID" = mkOverride 1002 null;
        "image" = mkOverride 1002 null;
        "nodeID" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.BackingImageManagerStatus" = {

      options = {
        "apiMinVersion" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "apiVersion" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "backingImageFileMap" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
        "currentState" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "ip" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "ownerID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageIP" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "apiMinVersion" = mkOverride 1002 null;
        "apiVersion" = mkOverride 1002 null;
        "backingImageFileMap" = mkOverride 1002 null;
        "currentState" = mkOverride 1002 null;
        "ip" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
        "storageIP" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.BackingImageSpec" = {

      options = {
        "checksum" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "dataEngine" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "diskFileSpecMap" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
        "diskSelector" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "disks" = mkOption {
          description = "Deprecated. We are now using DiskFileSpecMap to assign different spec to the file on different disks.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "minNumberOfCopies" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "nodeSelector" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "secret" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "secretNamespace" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "sourceParameters" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "sourceType" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "checksum" = mkOverride 1002 null;
        "dataEngine" = mkOverride 1002 null;
        "diskFileSpecMap" = mkOverride 1002 null;
        "diskSelector" = mkOverride 1002 null;
        "disks" = mkOverride 1002 null;
        "minNumberOfCopies" = mkOverride 1002 null;
        "nodeSelector" = mkOverride 1002 null;
        "secret" = mkOverride 1002 null;
        "secretNamespace" = mkOverride 1002 null;
        "sourceParameters" = mkOverride 1002 null;
        "sourceType" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.BackingImageStatus" = {

      options = {
        "checksum" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "diskFileStatusMap" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
        "diskLastRefAtMap" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "ownerID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "realSize" = mkOption {
          description = "Real size of image in bytes, which may be smaller than the size when the file is a sparse file. Will be zero until known (e.g. while a backing image is uploading)";
          type = (types.nullOr types.int);
        };
        "size" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "uuid" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "v2FirstCopyDisk" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "v2FirstCopyStatus" = mkOption {
          description = "It is pending -> in-progress -> ready/failed";
          type = (types.nullOr types.str);
        };
        "virtualSize" = mkOption {
          description = "Virtual size of image in bytes, which may be larger than physical size. Will be zero until known (e.g. while a backing image is uploading)";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "checksum" = mkOverride 1002 null;
        "diskFileStatusMap" = mkOverride 1002 null;
        "diskLastRefAtMap" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
        "realSize" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "uuid" = mkOverride 1002 null;
        "v2FirstCopyDisk" = mkOverride 1002 null;
        "v2FirstCopyStatus" = mkOverride 1002 null;
        "virtualSize" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.Backup" = {

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
          description = "BackupSpec defines the desired state of the Longhorn backup";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.BackupSpec"));
        };
        "status" = mkOption {
          description = "BackupStatus defines the observed state of the Longhorn backup";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.BackupStatus"));
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
    "longhorn.io.v1beta2.BackupBackingImage" = {

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
          description = "BackupBackingImageSpec defines the desired state of the Longhorn backing image backup";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.BackupBackingImageSpec"));
        };
        "status" = mkOption {
          description = "BackupBackingImageStatus defines the observed state of the Longhorn backing image backup";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.BackupBackingImageStatus"));
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
    "longhorn.io.v1beta2.BackupBackingImageSpec" = {

      options = {
        "backingImage" = mkOption {
          description = "The backing image name.";
          type = types.str;
        };
        "backupTargetName" = mkOption {
          description = "The backup target name.";
          type = (types.nullOr types.str);
        };
        "labels" = mkOption {
          description = "The labels of backing image backup.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "syncRequestedAt" = mkOption {
          description = "The time to request run sync the remote backing image backup.";
          type = (types.nullOr types.str);
        };
        "userCreated" = mkOption {
          description = "Is this CR created by user through API or UI.";
          type = types.bool;
        };
      };

      config = {
        "backupTargetName" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "syncRequestedAt" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.BackupBackingImageStatus" = {

      options = {
        "backingImage" = mkOption {
          description = "The backing image name.";
          type = (types.nullOr types.str);
        };
        "backupCreatedAt" = mkOption {
          description = "The backing image backup upload finished time.";
          type = (types.nullOr types.str);
        };
        "checksum" = mkOption {
          description = "The checksum of the backing image.";
          type = (types.nullOr types.str);
        };
        "compressionMethod" = mkOption {
          description = "Compression method";
          type = (types.nullOr types.str);
        };
        "error" = mkOption {
          description = "The error message when taking the backing image backup.";
          type = (types.nullOr types.str);
        };
        "labels" = mkOption {
          description = "The labels of backing image backup.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "lastSyncedAt" = mkOption {
          description = "The last time that the backing image backup was synced with the remote backup target.";
          type = (types.nullOr types.str);
        };
        "managerAddress" = mkOption {
          description = "The address of the backing image manager that runs backing image backup.";
          type = (types.nullOr types.str);
        };
        "messages" = mkOption {
          description = "The error messages when listing or inspecting backing image backup.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "ownerID" = mkOption {
          description = "The node ID on which the controller is responsible to reconcile this CR.";
          type = (types.nullOr types.str);
        };
        "progress" = mkOption {
          description = "The backing image backup progress.";
          type = (types.nullOr types.int);
        };
        "secret" = mkOption {
          description = "Record the secret if this backup backing image is encrypted";
          type = (types.nullOr types.str);
        };
        "secretNamespace" = mkOption {
          description = "Record the secret namespace if this backup backing image is encrypted";
          type = (types.nullOr types.str);
        };
        "size" = mkOption {
          description = "The backing image size.";
          type = (types.nullOr types.int);
        };
        "state" = mkOption {
          description = "The backing image backup creation state.\nCan be \"\", \"InProgress\", \"Completed\", \"Error\", \"Unknown\".";
          type = (types.nullOr types.str);
        };
        "url" = mkOption {
          description = "The backing image backup URL.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "backingImage" = mkOverride 1002 null;
        "backupCreatedAt" = mkOverride 1002 null;
        "checksum" = mkOverride 1002 null;
        "compressionMethod" = mkOverride 1002 null;
        "error" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "lastSyncedAt" = mkOverride 1002 null;
        "managerAddress" = mkOverride 1002 null;
        "messages" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
        "progress" = mkOverride 1002 null;
        "secret" = mkOverride 1002 null;
        "secretNamespace" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "state" = mkOverride 1002 null;
        "url" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.BackupSpec" = {

      options = {
        "backupBlockSize" = mkOption {
          description = "The backup block size. 0 means the legacy default size 2MiB, and -1 indicate the block size is invalid.";
          type = (types.nullOr types.str);
        };
        "backupMode" = mkOption {
          description = "The backup mode of this backup.\nCan be \"full\" or \"incremental\"";
          type = (types.nullOr types.str);
        };
        "labels" = mkOption {
          description = "The labels of snapshot backup.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "snapshotName" = mkOption {
          description = "The snapshot name.";
          type = (types.nullOr types.str);
        };
        "syncRequestedAt" = mkOption {
          description = "The time to request run sync the remote backup.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "backupBlockSize" = mkOverride 1002 null;
        "backupMode" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "snapshotName" = mkOverride 1002 null;
        "syncRequestedAt" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.BackupStatus" = {

      options = {
        "backupCreatedAt" = mkOption {
          description = "The snapshot backup upload finished time.";
          type = (types.nullOr types.str);
        };
        "backupTargetName" = mkOption {
          description = "The backup target name.";
          type = (types.nullOr types.str);
        };
        "compressionMethod" = mkOption {
          description = "Compression method";
          type = (types.nullOr types.str);
        };
        "error" = mkOption {
          description = "The error message when taking the snapshot backup.";
          type = (types.nullOr types.str);
        };
        "labels" = mkOption {
          description = "The labels of snapshot backup.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "lastSyncedAt" = mkOption {
          description = "The last time that the backup was synced with the remote backup target.";
          type = (types.nullOr types.str);
        };
        "messages" = mkOption {
          description = "The error messages when calling longhorn engine on listing or inspecting backups.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "newlyUploadDataSize" = mkOption {
          description = "Size in bytes of newly uploaded data";
          type = (types.nullOr types.str);
        };
        "ownerID" = mkOption {
          description = "The node ID on which the controller is responsible to reconcile this backup CR.";
          type = (types.nullOr types.str);
        };
        "progress" = mkOption {
          description = "The snapshot backup progress.";
          type = (types.nullOr types.int);
        };
        "reUploadedDataSize" = mkOption {
          description = "Size in bytes of reuploaded data";
          type = (types.nullOr types.str);
        };
        "replicaAddress" = mkOption {
          description = "The address of the replica that runs snapshot backup.";
          type = (types.nullOr types.str);
        };
        "size" = mkOption {
          description = "The snapshot size.";
          type = (types.nullOr types.str);
        };
        "snapshotCreatedAt" = mkOption {
          description = "The snapshot creation time.";
          type = (types.nullOr types.str);
        };
        "snapshotName" = mkOption {
          description = "The snapshot name.";
          type = (types.nullOr types.str);
        };
        "state" = mkOption {
          description = "The backup creation state.\nCan be \"\", \"InProgress\", \"Completed\", \"Error\", \"Unknown\".";
          type = (types.nullOr types.str);
        };
        "url" = mkOption {
          description = "The snapshot backup URL.";
          type = (types.nullOr types.str);
        };
        "volumeBackingImageName" = mkOption {
          description = "The volume's backing image name.";
          type = (types.nullOr types.str);
        };
        "volumeCreated" = mkOption {
          description = "The volume creation time.";
          type = (types.nullOr types.str);
        };
        "volumeName" = mkOption {
          description = "The volume name.";
          type = (types.nullOr types.str);
        };
        "volumeSize" = mkOption {
          description = "The volume size.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "backupCreatedAt" = mkOverride 1002 null;
        "backupTargetName" = mkOverride 1002 null;
        "compressionMethod" = mkOverride 1002 null;
        "error" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "lastSyncedAt" = mkOverride 1002 null;
        "messages" = mkOverride 1002 null;
        "newlyUploadDataSize" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
        "progress" = mkOverride 1002 null;
        "reUploadedDataSize" = mkOverride 1002 null;
        "replicaAddress" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "snapshotCreatedAt" = mkOverride 1002 null;
        "snapshotName" = mkOverride 1002 null;
        "state" = mkOverride 1002 null;
        "url" = mkOverride 1002 null;
        "volumeBackingImageName" = mkOverride 1002 null;
        "volumeCreated" = mkOverride 1002 null;
        "volumeName" = mkOverride 1002 null;
        "volumeSize" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.BackupTarget" = {

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
          description = "BackupTargetSpec defines the desired state of the Longhorn backup target";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.BackupTargetSpec"));
        };
        "status" = mkOption {
          description = "BackupTargetStatus defines the observed state of the Longhorn backup target";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.BackupTargetStatus"));
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
    "longhorn.io.v1beta2.BackupTargetSpec" = {

      options = {
        "backupTargetURL" = mkOption {
          description = "The backup target URL.";
          type = (types.nullOr types.str);
        };
        "credentialSecret" = mkOption {
          description = "The backup target credential secret.";
          type = (types.nullOr types.str);
        };
        "pollInterval" = mkOption {
          description = "The interval that the cluster needs to run sync with the backup target.";
          type = (types.nullOr types.str);
        };
        "syncRequestedAt" = mkOption {
          description = "The time to request run sync the remote backup target.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "backupTargetURL" = mkOverride 1002 null;
        "credentialSecret" = mkOverride 1002 null;
        "pollInterval" = mkOverride 1002 null;
        "syncRequestedAt" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.BackupTargetStatus" = {

      options = {
        "available" = mkOption {
          description = "Available indicates if the remote backup target is available or not.";
          type = (types.nullOr types.bool);
        };
        "conditions" = mkOption {
          description = "Records the reason on why the backup target is unavailable.";
          type = (
            types.nullOr (types.listOf (submoduleOf "longhorn.io.v1beta2.BackupTargetStatusConditions"))
          );
        };
        "lastSyncedAt" = mkOption {
          description = "The last time that the controller synced with the remote backup target.";
          type = (types.nullOr types.str);
        };
        "ownerID" = mkOption {
          description = "The node ID on which the controller is responsible to reconcile this backup target CR.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "available" = mkOverride 1002 null;
        "conditions" = mkOverride 1002 null;
        "lastSyncedAt" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.BackupTargetStatusConditions" = {

      options = {
        "lastProbeTime" = mkOption {
          description = "Last time we probed the condition.";
          type = (types.nullOr types.str);
        };
        "lastTransitionTime" = mkOption {
          description = "Last time the condition transitioned from one status to another.";
          type = (types.nullOr types.str);
        };
        "message" = mkOption {
          description = "Human-readable message indicating details about last transition.";
          type = (types.nullOr types.str);
        };
        "reason" = mkOption {
          description = "Unique, one-word, CamelCase reason for the condition's last transition.";
          type = (types.nullOr types.str);
        };
        "status" = mkOption {
          description = "Status is the status of the condition.\nCan be True, False, Unknown.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is the type of the condition.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "lastProbeTime" = mkOverride 1002 null;
        "lastTransitionTime" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "reason" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.BackupVolume" = {

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
          description = "BackupVolumeSpec defines the desired state of the Longhorn backup volume";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.BackupVolumeSpec"));
        };
        "status" = mkOption {
          description = "BackupVolumeStatus defines the observed state of the Longhorn backup volume";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.BackupVolumeStatus"));
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
    "longhorn.io.v1beta2.BackupVolumeSpec" = {

      options = {
        "backupTargetName" = mkOption {
          description = "The backup target name that the backup volume was synced.";
          type = (types.nullOr types.str);
        };
        "syncRequestedAt" = mkOption {
          description = "The time to request run sync the remote backup volume.";
          type = (types.nullOr types.str);
        };
        "volumeName" = mkOption {
          description = "The volume name that the backup volume was used to backup.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "backupTargetName" = mkOverride 1002 null;
        "syncRequestedAt" = mkOverride 1002 null;
        "volumeName" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.BackupVolumeStatus" = {

      options = {
        "backingImageChecksum" = mkOption {
          description = "the backing image checksum.";
          type = (types.nullOr types.str);
        };
        "backingImageName" = mkOption {
          description = "The backing image name.";
          type = (types.nullOr types.str);
        };
        "createdAt" = mkOption {
          description = "The backup volume creation time.";
          type = (types.nullOr types.str);
        };
        "dataStored" = mkOption {
          description = "The backup volume block count.";
          type = (types.nullOr types.str);
        };
        "labels" = mkOption {
          description = "The backup volume labels.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "lastBackupAt" = mkOption {
          description = "The latest volume backup time.";
          type = (types.nullOr types.str);
        };
        "lastBackupName" = mkOption {
          description = "The latest volume backup name.";
          type = (types.nullOr types.str);
        };
        "lastModificationTime" = mkOption {
          description = "The backup volume config last modification time.";
          type = (types.nullOr types.str);
        };
        "lastSyncedAt" = mkOption {
          description = "The last time that the backup volume was synced into the cluster.";
          type = (types.nullOr types.str);
        };
        "messages" = mkOption {
          description = "The error messages when call longhorn engine on list or inspect backup volumes.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "ownerID" = mkOption {
          description = "The node ID on which the controller is responsible to reconcile this backup volume CR.";
          type = (types.nullOr types.str);
        };
        "size" = mkOption {
          description = "The backup volume size.";
          type = (types.nullOr types.str);
        };
        "storageClassName" = mkOption {
          description = "the storage class name of pv/pvc binding with the volume.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "backingImageChecksum" = mkOverride 1002 null;
        "backingImageName" = mkOverride 1002 null;
        "createdAt" = mkOverride 1002 null;
        "dataStored" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "lastBackupAt" = mkOverride 1002 null;
        "lastBackupName" = mkOverride 1002 null;
        "lastModificationTime" = mkOverride 1002 null;
        "lastSyncedAt" = mkOverride 1002 null;
        "messages" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "storageClassName" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.Engine" = {

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
          description = "EngineSpec defines the desired state of the Longhorn engine";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.EngineSpec"));
        };
        "status" = mkOption {
          description = "EngineStatus defines the observed state of the Longhorn engine";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.EngineStatus"));
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
    "longhorn.io.v1beta2.EngineImage" = {

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
          description = "EngineImageSpec defines the desired state of the Longhorn engine image";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.EngineImageSpec"));
        };
        "status" = mkOption {
          description = "EngineImageStatus defines the observed state of the Longhorn engine image";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.EngineImageStatus"));
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
    "longhorn.io.v1beta2.EngineImageSpec" = {

      options = {
        "image" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "longhorn.io.v1beta2.EngineImageStatus" = {

      options = {
        "buildDate" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "cliAPIMinVersion" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "cliAPIVersion" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "conditions" = mkOption {
          description = "";
          type = (
            types.nullOr (types.listOf (submoduleOf "longhorn.io.v1beta2.EngineImageStatusConditions"))
          );
        };
        "controllerAPIMinVersion" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "controllerAPIVersion" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "dataFormatMinVersion" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "dataFormatVersion" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "gitCommit" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "incompatible" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "noRefSince" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "nodeDeploymentMap" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.bool));
        };
        "ownerID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "refCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "state" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "version" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "buildDate" = mkOverride 1002 null;
        "cliAPIMinVersion" = mkOverride 1002 null;
        "cliAPIVersion" = mkOverride 1002 null;
        "conditions" = mkOverride 1002 null;
        "controllerAPIMinVersion" = mkOverride 1002 null;
        "controllerAPIVersion" = mkOverride 1002 null;
        "dataFormatMinVersion" = mkOverride 1002 null;
        "dataFormatVersion" = mkOverride 1002 null;
        "gitCommit" = mkOverride 1002 null;
        "incompatible" = mkOverride 1002 null;
        "noRefSince" = mkOverride 1002 null;
        "nodeDeploymentMap" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
        "refCount" = mkOverride 1002 null;
        "state" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.EngineImageStatusConditions" = {

      options = {
        "lastProbeTime" = mkOption {
          description = "Last time we probed the condition.";
          type = (types.nullOr types.str);
        };
        "lastTransitionTime" = mkOption {
          description = "Last time the condition transitioned from one status to another.";
          type = (types.nullOr types.str);
        };
        "message" = mkOption {
          description = "Human-readable message indicating details about last transition.";
          type = (types.nullOr types.str);
        };
        "reason" = mkOption {
          description = "Unique, one-word, CamelCase reason for the condition's last transition.";
          type = (types.nullOr types.str);
        };
        "status" = mkOption {
          description = "Status is the status of the condition.\nCan be True, False, Unknown.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is the type of the condition.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "lastProbeTime" = mkOverride 1002 null;
        "lastTransitionTime" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "reason" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.EngineSpec" = {

      options = {
        "active" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "backupVolume" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "dataEngine" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "desireState" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "disableFrontend" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "frontend" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "image" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "logRequested" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "nodeID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "replicaAddressMap" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "requestedBackupRestore" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "requestedDataSource" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "revisionCounterDisabled" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "salvageRequested" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "snapshotMaxCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "snapshotMaxSize" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "unmapMarkSnapChainRemovedEnabled" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "upgradedReplicaAddressMap" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "volumeName" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "volumeSize" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "active" = mkOverride 1002 null;
        "backupVolume" = mkOverride 1002 null;
        "dataEngine" = mkOverride 1002 null;
        "desireState" = mkOverride 1002 null;
        "disableFrontend" = mkOverride 1002 null;
        "frontend" = mkOverride 1002 null;
        "image" = mkOverride 1002 null;
        "logRequested" = mkOverride 1002 null;
        "nodeID" = mkOverride 1002 null;
        "replicaAddressMap" = mkOverride 1002 null;
        "requestedBackupRestore" = mkOverride 1002 null;
        "requestedDataSource" = mkOverride 1002 null;
        "revisionCounterDisabled" = mkOverride 1002 null;
        "salvageRequested" = mkOverride 1002 null;
        "snapshotMaxCount" = mkOverride 1002 null;
        "snapshotMaxSize" = mkOverride 1002 null;
        "unmapMarkSnapChainRemovedEnabled" = mkOverride 1002 null;
        "upgradedReplicaAddressMap" = mkOverride 1002 null;
        "volumeName" = mkOverride 1002 null;
        "volumeSize" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.EngineStatus" = {

      options = {
        "backupStatus" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
        "cloneStatus" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
        "conditions" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf (submoduleOf "longhorn.io.v1beta2.EngineStatusConditions")));
        };
        "currentImage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "currentReplicaAddressMap" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "currentSize" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "currentState" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "endpoint" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "instanceManagerName" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "ip" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "isExpanding" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "lastExpansionError" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "lastExpansionFailedAt" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "lastRestoredBackup" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "logFetched" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "ownerID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "port" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "purgeStatus" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
        "rebuildStatus" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
        "replicaModeMap" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "replicaTransitionTimeMap" = mkOption {
          description = "ReplicaTransitionTimeMap records the time a replica in ReplicaModeMap transitions from one mode to another (or\nfrom not being in the ReplicaModeMap to being in it). This information is sometimes required by other controllers\n(e.g. the volume controller uses it to determine the correct value for replica.Spec.lastHealthyAt).";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "restoreStatus" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
        "salvageExecuted" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "snapshotMaxCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "snapshotMaxSize" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "snapshots" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
        "snapshotsError" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "started" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "starting" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "storageIP" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "ublkID" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "unmapMarkSnapChainRemovedEnabled" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "uuid" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "backupStatus" = mkOverride 1002 null;
        "cloneStatus" = mkOverride 1002 null;
        "conditions" = mkOverride 1002 null;
        "currentImage" = mkOverride 1002 null;
        "currentReplicaAddressMap" = mkOverride 1002 null;
        "currentSize" = mkOverride 1002 null;
        "currentState" = mkOverride 1002 null;
        "endpoint" = mkOverride 1002 null;
        "instanceManagerName" = mkOverride 1002 null;
        "ip" = mkOverride 1002 null;
        "isExpanding" = mkOverride 1002 null;
        "lastExpansionError" = mkOverride 1002 null;
        "lastExpansionFailedAt" = mkOverride 1002 null;
        "lastRestoredBackup" = mkOverride 1002 null;
        "logFetched" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
        "port" = mkOverride 1002 null;
        "purgeStatus" = mkOverride 1002 null;
        "rebuildStatus" = mkOverride 1002 null;
        "replicaModeMap" = mkOverride 1002 null;
        "replicaTransitionTimeMap" = mkOverride 1002 null;
        "restoreStatus" = mkOverride 1002 null;
        "salvageExecuted" = mkOverride 1002 null;
        "snapshotMaxCount" = mkOverride 1002 null;
        "snapshotMaxSize" = mkOverride 1002 null;
        "snapshots" = mkOverride 1002 null;
        "snapshotsError" = mkOverride 1002 null;
        "started" = mkOverride 1002 null;
        "starting" = mkOverride 1002 null;
        "storageIP" = mkOverride 1002 null;
        "ublkID" = mkOverride 1002 null;
        "unmapMarkSnapChainRemovedEnabled" = mkOverride 1002 null;
        "uuid" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.EngineStatusConditions" = {

      options = {
        "lastProbeTime" = mkOption {
          description = "Last time we probed the condition.";
          type = (types.nullOr types.str);
        };
        "lastTransitionTime" = mkOption {
          description = "Last time the condition transitioned from one status to another.";
          type = (types.nullOr types.str);
        };
        "message" = mkOption {
          description = "Human-readable message indicating details about last transition.";
          type = (types.nullOr types.str);
        };
        "reason" = mkOption {
          description = "Unique, one-word, CamelCase reason for the condition's last transition.";
          type = (types.nullOr types.str);
        };
        "status" = mkOption {
          description = "Status is the status of the condition.\nCan be True, False, Unknown.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is the type of the condition.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "lastProbeTime" = mkOverride 1002 null;
        "lastTransitionTime" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "reason" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.InstanceManager" = {

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
          description = "InstanceManagerSpec defines the desired state of the Longhorn instance manager";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.InstanceManagerSpec"));
        };
        "status" = mkOption {
          description = "InstanceManagerStatus defines the observed state of the Longhorn instance manager";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.InstanceManagerStatus"));
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
    "longhorn.io.v1beta2.InstanceManagerSpec" = {

      options = {
        "dataEngine" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "dataEngineSpec" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.InstanceManagerSpecDataEngineSpec"));
        };
        "image" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "nodeID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "dataEngine" = mkOverride 1002 null;
        "dataEngineSpec" = mkOverride 1002 null;
        "image" = mkOverride 1002 null;
        "nodeID" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.InstanceManagerSpecDataEngineSpec" = {

      options = {
        "v2" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.InstanceManagerSpecDataEngineSpecV2"));
        };
      };

      config = {
        "v2" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.InstanceManagerSpecDataEngineSpecV2" = {

      options = {
        "cpuMask" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "cpuMask" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.InstanceManagerStatus" = {

      options = {
        "apiMinVersion" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "apiVersion" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "backingImages" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
        "currentState" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "dataEngineStatus" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.InstanceManagerStatusDataEngineStatus"));
        };
        "instanceEngines" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
        "instanceReplicas" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
        "instances" = mkOption {
          description = "Deprecated: Replaced by InstanceEngines and InstanceReplicas";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
        "ip" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "ownerID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "proxyApiMinVersion" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "proxyApiVersion" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "apiMinVersion" = mkOverride 1002 null;
        "apiVersion" = mkOverride 1002 null;
        "backingImages" = mkOverride 1002 null;
        "currentState" = mkOverride 1002 null;
        "dataEngineStatus" = mkOverride 1002 null;
        "instanceEngines" = mkOverride 1002 null;
        "instanceReplicas" = mkOverride 1002 null;
        "instances" = mkOverride 1002 null;
        "ip" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
        "proxyApiMinVersion" = mkOverride 1002 null;
        "proxyApiVersion" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.InstanceManagerStatusDataEngineStatus" = {

      options = {
        "v2" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.InstanceManagerStatusDataEngineStatusV2"));
        };
      };

      config = {
        "v2" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.InstanceManagerStatusDataEngineStatusV2" = {

      options = {
        "cpuMask" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "interruptModeEnabled" = mkOption {
          description = "InterruptModeEnabled indicates whether the V2 data engine is running in\ninterrupt mode (true) or polling mode (false). Set by Longhorn manager;\nread-only to users.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "cpuMask" = mkOverride 1002 null;
        "interruptModeEnabled" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.Node" = {

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
          description = "NodeSpec defines the desired state of the Longhorn node";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.NodeSpec"));
        };
        "status" = mkOption {
          description = "NodeStatus defines the observed state of the Longhorn node";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.NodeStatus"));
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
    "longhorn.io.v1beta2.NodeSpec" = {

      options = {
        "allowScheduling" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "disks" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
        "evictionRequested" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "instanceManagerCPURequest" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "name" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "tags" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "allowScheduling" = mkOverride 1002 null;
        "disks" = mkOverride 1002 null;
        "evictionRequested" = mkOverride 1002 null;
        "instanceManagerCPURequest" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "tags" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.NodeStatus" = {

      options = {
        "autoEvicting" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "conditions" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf (submoduleOf "longhorn.io.v1beta2.NodeStatusConditions")));
        };
        "diskStatus" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
        "region" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "snapshotCheckStatus" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.NodeStatusSnapshotCheckStatus"));
        };
        "zone" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "autoEvicting" = mkOverride 1002 null;
        "conditions" = mkOverride 1002 null;
        "diskStatus" = mkOverride 1002 null;
        "region" = mkOverride 1002 null;
        "snapshotCheckStatus" = mkOverride 1002 null;
        "zone" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.NodeStatusConditions" = {

      options = {
        "lastProbeTime" = mkOption {
          description = "Last time we probed the condition.";
          type = (types.nullOr types.str);
        };
        "lastTransitionTime" = mkOption {
          description = "Last time the condition transitioned from one status to another.";
          type = (types.nullOr types.str);
        };
        "message" = mkOption {
          description = "Human-readable message indicating details about last transition.";
          type = (types.nullOr types.str);
        };
        "reason" = mkOption {
          description = "Unique, one-word, CamelCase reason for the condition's last transition.";
          type = (types.nullOr types.str);
        };
        "status" = mkOption {
          description = "Status is the status of the condition.\nCan be True, False, Unknown.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is the type of the condition.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "lastProbeTime" = mkOverride 1002 null;
        "lastTransitionTime" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "reason" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.NodeStatusSnapshotCheckStatus" = {

      options = {
        "lastPeriodicCheckedAt" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "lastPeriodicCheckedAt" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.Orphan" = {

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
          description = "OrphanSpec defines the desired state of the Longhorn orphaned data";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.OrphanSpec"));
        };
        "status" = mkOption {
          description = "OrphanStatus defines the observed state of the Longhorn orphaned data";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.OrphanStatus"));
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
    "longhorn.io.v1beta2.OrphanSpec" = {

      options = {
        "dataEngine" = mkOption {
          description = "The type of data engine for instance orphan.\nCan be \"v1\", \"v2\".";
          type = (types.nullOr types.str);
        };
        "nodeID" = mkOption {
          description = "The node ID on which the controller is responsible to reconcile this orphan CR.";
          type = (types.nullOr types.str);
        };
        "orphanType" = mkOption {
          description = "The type of the orphaned data.\nCan be \"replica\".";
          type = (types.nullOr types.str);
        };
        "parameters" = mkOption {
          description = "The parameters of the orphaned data";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "dataEngine" = mkOverride 1002 null;
        "nodeID" = mkOverride 1002 null;
        "orphanType" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.OrphanStatus" = {

      options = {
        "conditions" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf (submoduleOf "longhorn.io.v1beta2.OrphanStatusConditions")));
        };
        "ownerID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "conditions" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.OrphanStatusConditions" = {

      options = {
        "lastProbeTime" = mkOption {
          description = "Last time we probed the condition.";
          type = (types.nullOr types.str);
        };
        "lastTransitionTime" = mkOption {
          description = "Last time the condition transitioned from one status to another.";
          type = (types.nullOr types.str);
        };
        "message" = mkOption {
          description = "Human-readable message indicating details about last transition.";
          type = (types.nullOr types.str);
        };
        "reason" = mkOption {
          description = "Unique, one-word, CamelCase reason for the condition's last transition.";
          type = (types.nullOr types.str);
        };
        "status" = mkOption {
          description = "Status is the status of the condition.\nCan be True, False, Unknown.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is the type of the condition.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "lastProbeTime" = mkOverride 1002 null;
        "lastTransitionTime" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "reason" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.RecurringJob" = {

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
          description = "RecurringJobSpec defines the desired state of the Longhorn recurring job";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.RecurringJobSpec"));
        };
        "status" = mkOption {
          description = "RecurringJobStatus defines the observed state of the Longhorn recurring job";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.RecurringJobStatus"));
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
    "longhorn.io.v1beta2.RecurringJobSpec" = {

      options = {
        "concurrency" = mkOption {
          description = "The concurrency of taking the snapshot/backup.";
          type = (types.nullOr types.int);
        };
        "cron" = mkOption {
          description = "The cron setting.";
          type = (types.nullOr types.str);
        };
        "groups" = mkOption {
          description = "The recurring job group.";
          type = (types.nullOr (types.listOf types.str));
        };
        "labels" = mkOption {
          description = "The label of the snapshot/backup.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "name" = mkOption {
          description = "The recurring job name.";
          type = (types.nullOr types.str);
        };
        "parameters" = mkOption {
          description = "The parameters of the snapshot/backup.\nSupport parameters: \"full-backup-interval\", \"volume-backup-policy\".";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "retain" = mkOption {
          description = "The retain count of the snapshot/backup.";
          type = (types.nullOr types.int);
        };
        "task" = mkOption {
          description = "The recurring job task.\nCan be \"snapshot\", \"snapshot-force-create\", \"snapshot-cleanup\", \"snapshot-delete\", \"backup\", \"backup-force-create\", \"filesystem-trim\" or \"system-backup\".";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "concurrency" = mkOverride 1002 null;
        "cron" = mkOverride 1002 null;
        "groups" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "name" = mkOverride 1002 null;
        "parameters" = mkOverride 1002 null;
        "retain" = mkOverride 1002 null;
        "task" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.RecurringJobStatus" = {

      options = {
        "executionCount" = mkOption {
          description = "The number of jobs that have been triggered.";
          type = (types.nullOr types.int);
        };
        "ownerID" = mkOption {
          description = "The owner ID which is responsible to reconcile this recurring job CR.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "executionCount" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.Replica" = {

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
          description = "ReplicaSpec defines the desired state of the Longhorn replica";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.ReplicaSpec"));
        };
        "status" = mkOption {
          description = "ReplicaStatus defines the observed state of the Longhorn replica";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.ReplicaStatus"));
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
    "longhorn.io.v1beta2.ReplicaSpec" = {

      options = {
        "active" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "backingImage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "dataDirectoryName" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "dataEngine" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "desireState" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "diskID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "diskPath" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "engineName" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "evictionRequested" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "failedAt" = mkOption {
          description = "FailedAt is set when a running replica fails or when a running engine is unable to use a replica for any reason.\nFailedAt indicates the time the failure occurred. When FailedAt is set, a replica is likely to have useful\n(though possibly stale) data. A replica with FailedAt set must be rebuilt from a non-failed replica (or it can\nbe used in a salvage if all replicas are failed). FailedAt is cleared before a rebuild or salvage. FailedAt may\nbe later than the corresponding entry in an engine's replicaTransitionTimeMap because it is set when the volume\ncontroller acknowledges the change.";
          type = (types.nullOr types.str);
        };
        "hardNodeAffinity" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "healthyAt" = mkOption {
          description = "HealthyAt is set the first time a replica becomes read/write in an engine after creation or rebuild. HealthyAt\nindicates the time the last successful rebuild occurred. When HealthyAt is set, a replica is likely to have\nuseful (though possibly stale) data. HealthyAt is cleared before a rebuild. HealthyAt may be later than the\ncorresponding entry in an engine's replicaTransitionTimeMap because it is set when the volume controller\nacknowledges the change.";
          type = (types.nullOr types.str);
        };
        "image" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "lastFailedAt" = mkOption {
          description = "LastFailedAt is always set at the same time as FailedAt. Unlike FailedAt, LastFailedAt is never cleared.\nLastFailedAt is not a reliable indicator of the state of a replica's data. For example, a replica with\nLastFailedAt may already be healthy and in use again. However, because it is never cleared, it can be compared to\nLastHealthyAt to help prevent dangerous replica deletion in some corner cases. LastFailedAt may be later than the\ncorresponding entry in an engine's replicaTransitionTimeMap because it is set when the volume controller\nacknowledges the change.";
          type = (types.nullOr types.str);
        };
        "lastHealthyAt" = mkOption {
          description = "LastHealthyAt is set every time a replica becomes read/write in an engine. Unlike HealthyAt, LastHealthyAt is\nnever cleared. LastHealthyAt is not a reliable indicator of the state of a replica's data. For example, a\nreplica with LastHealthyAt set may be in the middle of a rebuild. However, because it is never cleared, it can be\ncompared to LastFailedAt to help prevent dangerous replica deletion in some corner cases. LastHealthyAt may be\nlater than the corresponding entry in an engine's replicaTransitionTimeMap because it is set when the volume\ncontroller acknowledges the change.";
          type = (types.nullOr types.str);
        };
        "logRequested" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "migrationEngineName" = mkOption {
          description = "MigrationEngineName is indicating the migrating engine which current connected to this replica. This is only\nused for live migration of v2 data engine";
          type = (types.nullOr types.str);
        };
        "nodeID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "rebuildRetryCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "revisionCounterDisabled" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "salvageRequested" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "snapshotMaxCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "snapshotMaxSize" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "unmapMarkDiskChainRemovedEnabled" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "volumeName" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "volumeSize" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "active" = mkOverride 1002 null;
        "backingImage" = mkOverride 1002 null;
        "dataDirectoryName" = mkOverride 1002 null;
        "dataEngine" = mkOverride 1002 null;
        "desireState" = mkOverride 1002 null;
        "diskID" = mkOverride 1002 null;
        "diskPath" = mkOverride 1002 null;
        "engineName" = mkOverride 1002 null;
        "evictionRequested" = mkOverride 1002 null;
        "failedAt" = mkOverride 1002 null;
        "hardNodeAffinity" = mkOverride 1002 null;
        "healthyAt" = mkOverride 1002 null;
        "image" = mkOverride 1002 null;
        "lastFailedAt" = mkOverride 1002 null;
        "lastHealthyAt" = mkOverride 1002 null;
        "logRequested" = mkOverride 1002 null;
        "migrationEngineName" = mkOverride 1002 null;
        "nodeID" = mkOverride 1002 null;
        "rebuildRetryCount" = mkOverride 1002 null;
        "revisionCounterDisabled" = mkOverride 1002 null;
        "salvageRequested" = mkOverride 1002 null;
        "snapshotMaxCount" = mkOverride 1002 null;
        "snapshotMaxSize" = mkOverride 1002 null;
        "unmapMarkDiskChainRemovedEnabled" = mkOverride 1002 null;
        "volumeName" = mkOverride 1002 null;
        "volumeSize" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.ReplicaStatus" = {

      options = {
        "conditions" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf (submoduleOf "longhorn.io.v1beta2.ReplicaStatusConditions")));
        };
        "currentImage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "currentState" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "instanceManagerName" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "ip" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "logFetched" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "ownerID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "port" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "salvageExecuted" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "started" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "starting" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "storageIP" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "ublkID" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "uuid" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "conditions" = mkOverride 1002 null;
        "currentImage" = mkOverride 1002 null;
        "currentState" = mkOverride 1002 null;
        "instanceManagerName" = mkOverride 1002 null;
        "ip" = mkOverride 1002 null;
        "logFetched" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
        "port" = mkOverride 1002 null;
        "salvageExecuted" = mkOverride 1002 null;
        "started" = mkOverride 1002 null;
        "starting" = mkOverride 1002 null;
        "storageIP" = mkOverride 1002 null;
        "ublkID" = mkOverride 1002 null;
        "uuid" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.ReplicaStatusConditions" = {

      options = {
        "lastProbeTime" = mkOption {
          description = "Last time we probed the condition.";
          type = (types.nullOr types.str);
        };
        "lastTransitionTime" = mkOption {
          description = "Last time the condition transitioned from one status to another.";
          type = (types.nullOr types.str);
        };
        "message" = mkOption {
          description = "Human-readable message indicating details about last transition.";
          type = (types.nullOr types.str);
        };
        "reason" = mkOption {
          description = "Unique, one-word, CamelCase reason for the condition's last transition.";
          type = (types.nullOr types.str);
        };
        "status" = mkOption {
          description = "Status is the status of the condition.\nCan be True, False, Unknown.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is the type of the condition.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "lastProbeTime" = mkOverride 1002 null;
        "lastTransitionTime" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "reason" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.Setting" = {

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
          description = "The status of the setting.";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.SettingStatus"));
        };
        "value" = mkOption {
          description = "The value of the setting.\n- It can be a non-JSON formatted string that is applied to all the applicable data engines listed in the setting definition.\n- It can be a JSON formatted string that contains values for applicable data engines listed in the setting definition's Default.";
          type = types.str;
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.SettingStatus" = {

      options = {
        "applied" = mkOption {
          description = "The setting is applied.";
          type = types.bool;
        };
      };

      config = { };

    };
    "longhorn.io.v1beta2.ShareManager" = {

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
          description = "ShareManagerSpec defines the desired state of the Longhorn share manager";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.ShareManagerSpec"));
        };
        "status" = mkOption {
          description = "ShareManagerStatus defines the observed state of the Longhorn share manager";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.ShareManagerStatus"));
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
    "longhorn.io.v1beta2.ShareManagerSpec" = {

      options = {
        "image" = mkOption {
          description = "Share manager image used for creating a share manager pod";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "image" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.ShareManagerStatus" = {

      options = {
        "endpoint" = mkOption {
          description = "NFS endpoint that can access the mounted filesystem of the volume";
          type = (types.nullOr types.str);
        };
        "ownerID" = mkOption {
          description = "The node ID on which the controller is responsible to reconcile this share manager resource";
          type = (types.nullOr types.str);
        };
        "state" = mkOption {
          description = "The state of the share manager resource";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "endpoint" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
        "state" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.Snapshot" = {

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
          description = "SnapshotSpec defines the desired state of Longhorn Snapshot";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.SnapshotSpec"));
        };
        "status" = mkOption {
          description = "SnapshotStatus defines the observed state of Longhorn Snapshot";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.SnapshotStatus"));
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
    "longhorn.io.v1beta2.SnapshotSpec" = {

      options = {
        "createSnapshot" = mkOption {
          description = "require creating a new snapshot";
          type = (types.nullOr types.bool);
        };
        "labels" = mkOption {
          description = "The labels of snapshot";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "volume" = mkOption {
          description = "the volume that this snapshot belongs to.\nThis field is immutable after creation.";
          type = types.str;
        };
      };

      config = {
        "createSnapshot" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.SnapshotStatus" = {

      options = {
        "checksum" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "children" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.bool));
        };
        "creationTime" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "error" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "labels" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "markRemoved" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "ownerID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "parent" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "readyToUse" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "restoreSize" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "size" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "userCreated" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "checksum" = mkOverride 1002 null;
        "children" = mkOverride 1002 null;
        "creationTime" = mkOverride 1002 null;
        "error" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
        "markRemoved" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
        "parent" = mkOverride 1002 null;
        "readyToUse" = mkOverride 1002 null;
        "restoreSize" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "userCreated" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.SupportBundle" = {

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
          description = "SupportBundleSpec defines the desired state of the Longhorn SupportBundle";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.SupportBundleSpec"));
        };
        "status" = mkOption {
          description = "SupportBundleStatus defines the observed state of the Longhorn SupportBundle";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.SupportBundleStatus"));
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
    "longhorn.io.v1beta2.SupportBundleSpec" = {

      options = {
        "description" = mkOption {
          description = "A brief description of the issue";
          type = types.str;
        };
        "issueURL" = mkOption {
          description = "The issue URL";
          type = (types.nullOr types.str);
        };
        "nodeID" = mkOption {
          description = "The preferred responsible controller node ID.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "issueURL" = mkOverride 1002 null;
        "nodeID" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.SupportBundleStatus" = {

      options = {
        "conditions" = mkOption {
          description = "";
          type = (
            types.nullOr (types.listOf (submoduleOf "longhorn.io.v1beta2.SupportBundleStatusConditions"))
          );
        };
        "filename" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "filesize" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "image" = mkOption {
          description = "The support bundle manager image";
          type = (types.nullOr types.str);
        };
        "managerIP" = mkOption {
          description = "The support bundle manager IP";
          type = (types.nullOr types.str);
        };
        "ownerID" = mkOption {
          description = "The current responsible controller node ID";
          type = (types.nullOr types.str);
        };
        "progress" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "state" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "conditions" = mkOverride 1002 null;
        "filename" = mkOverride 1002 null;
        "filesize" = mkOverride 1002 null;
        "image" = mkOverride 1002 null;
        "managerIP" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
        "progress" = mkOverride 1002 null;
        "state" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.SupportBundleStatusConditions" = {

      options = {
        "lastProbeTime" = mkOption {
          description = "Last time we probed the condition.";
          type = (types.nullOr types.str);
        };
        "lastTransitionTime" = mkOption {
          description = "Last time the condition transitioned from one status to another.";
          type = (types.nullOr types.str);
        };
        "message" = mkOption {
          description = "Human-readable message indicating details about last transition.";
          type = (types.nullOr types.str);
        };
        "reason" = mkOption {
          description = "Unique, one-word, CamelCase reason for the condition's last transition.";
          type = (types.nullOr types.str);
        };
        "status" = mkOption {
          description = "Status is the status of the condition.\nCan be True, False, Unknown.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is the type of the condition.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "lastProbeTime" = mkOverride 1002 null;
        "lastTransitionTime" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "reason" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.SystemBackup" = {

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
          description = "SystemBackupSpec defines the desired state of the Longhorn SystemBackup";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.SystemBackupSpec"));
        };
        "status" = mkOption {
          description = "SystemBackupStatus defines the observed state of the Longhorn SystemBackup";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.SystemBackupStatus"));
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
    "longhorn.io.v1beta2.SystemBackupSpec" = {

      options = {
        "volumeBackupPolicy" = mkOption {
          description = "The create volume backup policy\nCan be \"if-not-present\", \"always\" or \"disabled\"";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "volumeBackupPolicy" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.SystemBackupStatus" = {

      options = {
        "conditions" = mkOption {
          description = "";
          type = (
            types.nullOr (types.listOf (submoduleOf "longhorn.io.v1beta2.SystemBackupStatusConditions"))
          );
        };
        "createdAt" = mkOption {
          description = "The system backup creation time.";
          type = (types.nullOr types.str);
        };
        "gitCommit" = mkOption {
          description = "The saved Longhorn manager git commit.";
          type = (types.nullOr types.str);
        };
        "lastSyncedAt" = mkOption {
          description = "The last time that the system backup was synced into the cluster.";
          type = (types.nullOr types.str);
        };
        "managerImage" = mkOption {
          description = "The saved manager image.";
          type = (types.nullOr types.str);
        };
        "ownerID" = mkOption {
          description = "The node ID of the responsible controller to reconcile this SystemBackup.";
          type = (types.nullOr types.str);
        };
        "state" = mkOption {
          description = "The system backup state.";
          type = (types.nullOr types.str);
        };
        "version" = mkOption {
          description = "The saved Longhorn version.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "conditions" = mkOverride 1002 null;
        "createdAt" = mkOverride 1002 null;
        "gitCommit" = mkOverride 1002 null;
        "lastSyncedAt" = mkOverride 1002 null;
        "managerImage" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
        "state" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.SystemBackupStatusConditions" = {

      options = {
        "lastProbeTime" = mkOption {
          description = "Last time we probed the condition.";
          type = (types.nullOr types.str);
        };
        "lastTransitionTime" = mkOption {
          description = "Last time the condition transitioned from one status to another.";
          type = (types.nullOr types.str);
        };
        "message" = mkOption {
          description = "Human-readable message indicating details about last transition.";
          type = (types.nullOr types.str);
        };
        "reason" = mkOption {
          description = "Unique, one-word, CamelCase reason for the condition's last transition.";
          type = (types.nullOr types.str);
        };
        "status" = mkOption {
          description = "Status is the status of the condition.\nCan be True, False, Unknown.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is the type of the condition.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "lastProbeTime" = mkOverride 1002 null;
        "lastTransitionTime" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "reason" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.SystemRestore" = {

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
          description = "SystemRestoreSpec defines the desired state of the Longhorn SystemRestore";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.SystemRestoreSpec"));
        };
        "status" = mkOption {
          description = "SystemRestoreStatus defines the observed state of the Longhorn SystemRestore";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.SystemRestoreStatus"));
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
    "longhorn.io.v1beta2.SystemRestoreSpec" = {

      options = {
        "systemBackup" = mkOption {
          description = "The system backup name in the object store.";
          type = types.str;
        };
      };

      config = { };

    };
    "longhorn.io.v1beta2.SystemRestoreStatus" = {

      options = {
        "conditions" = mkOption {
          description = "";
          type = (
            types.nullOr (types.listOf (submoduleOf "longhorn.io.v1beta2.SystemRestoreStatusConditions"))
          );
        };
        "ownerID" = mkOption {
          description = "The node ID of the responsible controller to reconcile this SystemRestore.";
          type = (types.nullOr types.str);
        };
        "sourceURL" = mkOption {
          description = "The source system backup URL.";
          type = (types.nullOr types.str);
        };
        "state" = mkOption {
          description = "The system restore state.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "conditions" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
        "sourceURL" = mkOverride 1002 null;
        "state" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.SystemRestoreStatusConditions" = {

      options = {
        "lastProbeTime" = mkOption {
          description = "Last time we probed the condition.";
          type = (types.nullOr types.str);
        };
        "lastTransitionTime" = mkOption {
          description = "Last time the condition transitioned from one status to another.";
          type = (types.nullOr types.str);
        };
        "message" = mkOption {
          description = "Human-readable message indicating details about last transition.";
          type = (types.nullOr types.str);
        };
        "reason" = mkOption {
          description = "Unique, one-word, CamelCase reason for the condition's last transition.";
          type = (types.nullOr types.str);
        };
        "status" = mkOption {
          description = "Status is the status of the condition.\nCan be True, False, Unknown.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is the type of the condition.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "lastProbeTime" = mkOverride 1002 null;
        "lastTransitionTime" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "reason" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.Volume" = {

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
          description = "VolumeSpec defines the desired state of the Longhorn volume";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.VolumeSpec"));
        };
        "status" = mkOption {
          description = "VolumeStatus defines the observed state of the Longhorn volume";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.VolumeStatus"));
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
    "longhorn.io.v1beta2.VolumeAttachment" = {

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
          description = "VolumeAttachmentSpec defines the desired state of Longhorn VolumeAttachment";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.VolumeAttachmentSpec"));
        };
        "status" = mkOption {
          description = "VolumeAttachmentStatus defines the observed state of Longhorn VolumeAttachment";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.VolumeAttachmentStatus"));
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
    "longhorn.io.v1beta2.VolumeAttachmentSpec" = {

      options = {
        "attachmentTickets" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
        "volume" = mkOption {
          description = "The name of Longhorn volume of this VolumeAttachment";
          type = types.str;
        };
      };

      config = {
        "attachmentTickets" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.VolumeAttachmentStatus" = {

      options = {
        "attachmentTicketStatuses" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
      };

      config = {
        "attachmentTicketStatuses" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.VolumeSpec" = {

      options = {
        "Standby" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "accessMode" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "backingImage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "backupBlockSize" = mkOption {
          description = "BackupBlockSize indicate the block size to create backups. The block size is immutable.";
          type = (types.nullOr types.str);
        };
        "backupCompressionMethod" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "backupTargetName" = mkOption {
          description = "The backup target name that the volume will be backed up to or is synced.";
          type = (types.nullOr types.str);
        };
        "cloneMode" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "dataEngine" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "dataLocality" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "dataSource" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "disableFrontend" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "diskSelector" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "encrypted" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "freezeFilesystemForSnapshot" = mkOption {
          description = "Setting that freezes the filesystem on the root partition before a snapshot is created.";
          type = (types.nullOr types.str);
        };
        "fromBackup" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "frontend" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "image" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "lastAttachedBy" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "migratable" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "migrationNodeID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "nodeID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "nodeSelector" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "numberOfReplicas" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "offlineRebuilding" = mkOption {
          description = "Specifies whether Longhorn should rebuild replicas while the detached volume is degraded.\n- ignored: Use the global setting for offline replica rebuilding.\n- enabled: Enable offline rebuilding for this volume, regardless of the global setting.\n- disabled: Disable offline rebuilding for this volume, regardless of the global setting";
          type = (types.nullOr types.str);
        };
        "replicaAutoBalance" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "replicaDiskSoftAntiAffinity" = mkOption {
          description = "Replica disk soft anti affinity of the volume. Set enabled to allow replicas to be scheduled in the same disk.";
          type = (types.nullOr types.str);
        };
        "replicaRebuildingBandwidthLimit" = mkOption {
          description = "ReplicaRebuildingBandwidthLimit controls the maximum write bandwidth (in megabytes per second) allowed on the destination replica during the rebuilding process. Set this value to 0 to disable bandwidth limiting.";
          type = (types.nullOr types.int);
        };
        "replicaSoftAntiAffinity" = mkOption {
          description = "Replica soft anti affinity of the volume. Set enabled to allow replicas to be scheduled on the same node.";
          type = (types.nullOr types.str);
        };
        "replicaZoneSoftAntiAffinity" = mkOption {
          description = "Replica zone soft anti affinity of the volume. Set enabled to allow replicas to be scheduled in the same zone.";
          type = (types.nullOr types.str);
        };
        "restoreVolumeRecurringJob" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "revisionCounterDisabled" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "size" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "snapshotDataIntegrity" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "snapshotMaxCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "snapshotMaxSize" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "staleReplicaTimeout" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "unmapMarkSnapChainRemoved" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "Standby" = mkOverride 1002 null;
        "accessMode" = mkOverride 1002 null;
        "backingImage" = mkOverride 1002 null;
        "backupBlockSize" = mkOverride 1002 null;
        "backupCompressionMethod" = mkOverride 1002 null;
        "backupTargetName" = mkOverride 1002 null;
        "cloneMode" = mkOverride 1002 null;
        "dataEngine" = mkOverride 1002 null;
        "dataLocality" = mkOverride 1002 null;
        "dataSource" = mkOverride 1002 null;
        "disableFrontend" = mkOverride 1002 null;
        "diskSelector" = mkOverride 1002 null;
        "encrypted" = mkOverride 1002 null;
        "freezeFilesystemForSnapshot" = mkOverride 1002 null;
        "fromBackup" = mkOverride 1002 null;
        "frontend" = mkOverride 1002 null;
        "image" = mkOverride 1002 null;
        "lastAttachedBy" = mkOverride 1002 null;
        "migratable" = mkOverride 1002 null;
        "migrationNodeID" = mkOverride 1002 null;
        "nodeID" = mkOverride 1002 null;
        "nodeSelector" = mkOverride 1002 null;
        "numberOfReplicas" = mkOverride 1002 null;
        "offlineRebuilding" = mkOverride 1002 null;
        "replicaAutoBalance" = mkOverride 1002 null;
        "replicaDiskSoftAntiAffinity" = mkOverride 1002 null;
        "replicaRebuildingBandwidthLimit" = mkOverride 1002 null;
        "replicaSoftAntiAffinity" = mkOverride 1002 null;
        "replicaZoneSoftAntiAffinity" = mkOverride 1002 null;
        "restoreVolumeRecurringJob" = mkOverride 1002 null;
        "revisionCounterDisabled" = mkOverride 1002 null;
        "size" = mkOverride 1002 null;
        "snapshotDataIntegrity" = mkOverride 1002 null;
        "snapshotMaxCount" = mkOverride 1002 null;
        "snapshotMaxSize" = mkOverride 1002 null;
        "staleReplicaTimeout" = mkOverride 1002 null;
        "unmapMarkSnapChainRemoved" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.VolumeStatus" = {

      options = {
        "actualSize" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "cloneStatus" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.VolumeStatusCloneStatus"));
        };
        "conditions" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf (submoduleOf "longhorn.io.v1beta2.VolumeStatusConditions")));
        };
        "currentImage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "currentMigrationNodeID" = mkOption {
          description = "the node that this volume is currently migrating to";
          type = (types.nullOr types.str);
        };
        "currentNodeID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "expansionRequired" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "frontendDisabled" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "isStandby" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "kubernetesStatus" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "longhorn.io.v1beta2.VolumeStatusKubernetesStatus"));
        };
        "lastBackup" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "lastBackupAt" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "lastDegradedAt" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "ownerID" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "remountRequestedAt" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "restoreInitiated" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "restoreRequired" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "robustness" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "shareEndpoint" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "shareState" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "state" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "actualSize" = mkOverride 1002 null;
        "cloneStatus" = mkOverride 1002 null;
        "conditions" = mkOverride 1002 null;
        "currentImage" = mkOverride 1002 null;
        "currentMigrationNodeID" = mkOverride 1002 null;
        "currentNodeID" = mkOverride 1002 null;
        "expansionRequired" = mkOverride 1002 null;
        "frontendDisabled" = mkOverride 1002 null;
        "isStandby" = mkOverride 1002 null;
        "kubernetesStatus" = mkOverride 1002 null;
        "lastBackup" = mkOverride 1002 null;
        "lastBackupAt" = mkOverride 1002 null;
        "lastDegradedAt" = mkOverride 1002 null;
        "ownerID" = mkOverride 1002 null;
        "remountRequestedAt" = mkOverride 1002 null;
        "restoreInitiated" = mkOverride 1002 null;
        "restoreRequired" = mkOverride 1002 null;
        "robustness" = mkOverride 1002 null;
        "shareEndpoint" = mkOverride 1002 null;
        "shareState" = mkOverride 1002 null;
        "state" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.VolumeStatusCloneStatus" = {

      options = {
        "attemptCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "nextAllowedAttemptAt" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "snapshot" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "sourceVolume" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "state" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "attemptCount" = mkOverride 1002 null;
        "nextAllowedAttemptAt" = mkOverride 1002 null;
        "snapshot" = mkOverride 1002 null;
        "sourceVolume" = mkOverride 1002 null;
        "state" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.VolumeStatusConditions" = {

      options = {
        "lastProbeTime" = mkOption {
          description = "Last time we probed the condition.";
          type = (types.nullOr types.str);
        };
        "lastTransitionTime" = mkOption {
          description = "Last time the condition transitioned from one status to another.";
          type = (types.nullOr types.str);
        };
        "message" = mkOption {
          description = "Human-readable message indicating details about last transition.";
          type = (types.nullOr types.str);
        };
        "reason" = mkOption {
          description = "Unique, one-word, CamelCase reason for the condition's last transition.";
          type = (types.nullOr types.str);
        };
        "status" = mkOption {
          description = "Status is the status of the condition.\nCan be True, False, Unknown.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "Type is the type of the condition.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "lastProbeTime" = mkOverride 1002 null;
        "lastTransitionTime" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "reason" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.VolumeStatusKubernetesStatus" = {

      options = {
        "lastPVCRefAt" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "lastPodRefAt" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "namespace" = mkOption {
          description = "determine if PVC/Namespace is history or not";
          type = (types.nullOr types.str);
        };
        "pvName" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "pvStatus" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "pvcName" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "workloadsStatus" = mkOption {
          description = "determine if Pod/Workload is history or not";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "longhorn.io.v1beta2.VolumeStatusKubernetesStatusWorkloadsStatus")
            )
          );
        };
      };

      config = {
        "lastPVCRefAt" = mkOverride 1002 null;
        "lastPodRefAt" = mkOverride 1002 null;
        "namespace" = mkOverride 1002 null;
        "pvName" = mkOverride 1002 null;
        "pvStatus" = mkOverride 1002 null;
        "pvcName" = mkOverride 1002 null;
        "workloadsStatus" = mkOverride 1002 null;
      };

    };
    "longhorn.io.v1beta2.VolumeStatusKubernetesStatusWorkloadsStatus" = {

      options = {
        "podName" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "podStatus" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "workloadName" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "workloadType" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "podName" = mkOverride 1002 null;
        "podStatus" = mkOverride 1002 null;
        "workloadName" = mkOverride 1002 null;
        "workloadType" = mkOverride 1002 null;
      };

    };

  };
in
{
  # all resource versions
  options = {
    resources = {
      "longhorn.io"."v1beta2"."BackingImage" = mkOption {
        description = "BackingImage is where Longhorn stores backing image object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.BackingImage" "backingimages" "BackingImage"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."BackingImageDataSource" = mkOption {
        description = "BackingImageDataSource is where Longhorn stores backing image data source object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.BackingImageDataSource" "backingimagedatasources"
              "BackingImageDataSource"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."BackingImageManager" = mkOption {
        description = "BackingImageManager is where Longhorn stores backing image manager object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.BackingImageManager" "backingimagemanagers"
              "BackingImageManager"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."Backup" = mkOption {
        description = "Backup is where Longhorn stores backup object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.Backup" "backups" "Backup" "longhorn.io" "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."BackupBackingImage" = mkOption {
        description = "BackupBackingImage is where Longhorn stores backing image backup object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.BackupBackingImage" "backupbackingimages"
              "BackupBackingImage"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."BackupTarget" = mkOption {
        description = "BackupTarget is where Longhorn stores backup target object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.BackupTarget" "backuptargets" "BackupTarget"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."BackupVolume" = mkOption {
        description = "BackupVolume is where Longhorn stores backup volume object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.BackupVolume" "backupvolumes" "BackupVolume"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."Engine" = mkOption {
        description = "Engine is where Longhorn stores engine object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.Engine" "engines" "Engine" "longhorn.io" "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."EngineImage" = mkOption {
        description = "EngineImage is where Longhorn stores engine image object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.EngineImage" "engineimages" "EngineImage" "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."InstanceManager" = mkOption {
        description = "InstanceManager is where Longhorn stores instance manager object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.InstanceManager" "instancemanagers" "InstanceManager"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."Node" = mkOption {
        description = "Node is where Longhorn stores Longhorn node object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.Node" "nodes" "Node" "longhorn.io" "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."Orphan" = mkOption {
        description = "Orphan is where Longhorn stores orphan object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.Orphan" "orphans" "Orphan" "longhorn.io" "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."RecurringJob" = mkOption {
        description = "RecurringJob is where Longhorn stores recurring job object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.RecurringJob" "recurringjobs" "RecurringJob"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."Replica" = mkOption {
        description = "Replica is where Longhorn stores replica object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.Replica" "replicas" "Replica" "longhorn.io" "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."Setting" = mkOption {
        description = "Setting is where Longhorn stores setting object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.Setting" "settings" "Setting" "longhorn.io" "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."ShareManager" = mkOption {
        description = "ShareManager is where Longhorn stores share manager object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.ShareManager" "sharemanagers" "ShareManager"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."Snapshot" = mkOption {
        description = "Snapshot is the Schema for the snapshots API";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.Snapshot" "snapshots" "Snapshot" "longhorn.io" "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."SupportBundle" = mkOption {
        description = "SupportBundle is where Longhorn stores support bundle object";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.SupportBundle" "supportbundles" "SupportBundle"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."SystemBackup" = mkOption {
        description = "SystemBackup is where Longhorn stores system backup object";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.SystemBackup" "systembackups" "SystemBackup"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."SystemRestore" = mkOption {
        description = "SystemRestore is where Longhorn stores system restore object";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.SystemRestore" "systemrestores" "SystemRestore"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."Volume" = mkOption {
        description = "Volume is where Longhorn stores volume object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.Volume" "volumes" "Volume" "longhorn.io" "v1beta2"
          )
        );
        default = { };
      };
      "longhorn.io"."v1beta2"."VolumeAttachment" = mkOption {
        description = "VolumeAttachment stores attachment information of a Longhorn volume";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.VolumeAttachment" "volumeattachments" "VolumeAttachment"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };

    }
    // {
      "backingImages" = mkOption {
        description = "BackingImage is where Longhorn stores backing image object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.BackingImage" "backingimages" "BackingImage"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "backingImageDataSources" = mkOption {
        description = "BackingImageDataSource is where Longhorn stores backing image data source object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.BackingImageDataSource" "backingimagedatasources"
              "BackingImageDataSource"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "backingImageManagers" = mkOption {
        description = "BackingImageManager is where Longhorn stores backing image manager object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.BackingImageManager" "backingimagemanagers"
              "BackingImageManager"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "backups" = mkOption {
        description = "Backup is where Longhorn stores backup object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.Backup" "backups" "Backup" "longhorn.io" "v1beta2"
          )
        );
        default = { };
      };
      "backupBackingImages" = mkOption {
        description = "BackupBackingImage is where Longhorn stores backing image backup object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.BackupBackingImage" "backupbackingimages"
              "BackupBackingImage"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "backupTargets" = mkOption {
        description = "BackupTarget is where Longhorn stores backup target object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.BackupTarget" "backuptargets" "BackupTarget"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "backupVolumes" = mkOption {
        description = "BackupVolume is where Longhorn stores backup volume object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.BackupVolume" "backupvolumes" "BackupVolume"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "engines" = mkOption {
        description = "Engine is where Longhorn stores engine object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.Engine" "engines" "Engine" "longhorn.io" "v1beta2"
          )
        );
        default = { };
      };
      "engineImages" = mkOption {
        description = "EngineImage is where Longhorn stores engine image object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.EngineImage" "engineimages" "EngineImage" "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "instanceManagers" = mkOption {
        description = "InstanceManager is where Longhorn stores instance manager object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.InstanceManager" "instancemanagers" "InstanceManager"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "nodes" = mkOption {
        description = "Node is where Longhorn stores Longhorn node object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.Node" "nodes" "Node" "longhorn.io" "v1beta2"
          )
        );
        default = { };
      };
      "orphans" = mkOption {
        description = "Orphan is where Longhorn stores orphan object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.Orphan" "orphans" "Orphan" "longhorn.io" "v1beta2"
          )
        );
        default = { };
      };
      "recurringJobs" = mkOption {
        description = "RecurringJob is where Longhorn stores recurring job object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.RecurringJob" "recurringjobs" "RecurringJob"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "replicas" = mkOption {
        description = "Replica is where Longhorn stores replica object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.Replica" "replicas" "Replica" "longhorn.io" "v1beta2"
          )
        );
        default = { };
      };
      "settings" = mkOption {
        description = "Setting is where Longhorn stores setting object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.Setting" "settings" "Setting" "longhorn.io" "v1beta2"
          )
        );
        default = { };
      };
      "shareManagers" = mkOption {
        description = "ShareManager is where Longhorn stores share manager object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.ShareManager" "sharemanagers" "ShareManager"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "snapshots" = mkOption {
        description = "Snapshot is the Schema for the snapshots API";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.Snapshot" "snapshots" "Snapshot" "longhorn.io" "v1beta2"
          )
        );
        default = { };
      };
      "supportBundles" = mkOption {
        description = "SupportBundle is where Longhorn stores support bundle object";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.SupportBundle" "supportbundles" "SupportBundle"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "systemBackups" = mkOption {
        description = "SystemBackup is where Longhorn stores system backup object";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.SystemBackup" "systembackups" "SystemBackup"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "systemRestores" = mkOption {
        description = "SystemRestore is where Longhorn stores system restore object";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.SystemRestore" "systemrestores" "SystemRestore"
              "longhorn.io"
              "v1beta2"
          )
        );
        default = { };
      };
      "volumes" = mkOption {
        description = "Volume is where Longhorn stores volume object.";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.Volume" "volumes" "Volume" "longhorn.io" "v1beta2"
          )
        );
        default = { };
      };
      "volumeAttachments" = mkOption {
        description = "VolumeAttachment stores attachment information of a Longhorn volume";
        type = (
          types.attrsOf (
            submoduleForDefinition "longhorn.io.v1beta2.VolumeAttachment" "volumeattachments" "VolumeAttachment"
              "longhorn.io"
              "v1beta2"
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
        name = "backingimages";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "BackingImage";
        attrName = "backingImages";
      }
      {
        name = "backingimagedatasources";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "BackingImageDataSource";
        attrName = "backingImageDataSources";
      }
      {
        name = "backingimagemanagers";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "BackingImageManager";
        attrName = "backingImageManagers";
      }
      {
        name = "backups";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "Backup";
        attrName = "backups";
      }
      {
        name = "backupbackingimages";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "BackupBackingImage";
        attrName = "backupBackingImages";
      }
      {
        name = "backuptargets";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "BackupTarget";
        attrName = "backupTargets";
      }
      {
        name = "backupvolumes";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "BackupVolume";
        attrName = "backupVolumes";
      }
      {
        name = "engines";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "Engine";
        attrName = "engines";
      }
      {
        name = "engineimages";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "EngineImage";
        attrName = "engineImages";
      }
      {
        name = "instancemanagers";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "InstanceManager";
        attrName = "instanceManagers";
      }
      {
        name = "nodes";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "Node";
        attrName = "nodes";
      }
      {
        name = "orphans";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "Orphan";
        attrName = "orphans";
      }
      {
        name = "recurringjobs";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "RecurringJob";
        attrName = "recurringJobs";
      }
      {
        name = "replicas";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "Replica";
        attrName = "replicas";
      }
      {
        name = "settings";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "Setting";
        attrName = "settings";
      }
      {
        name = "sharemanagers";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "ShareManager";
        attrName = "shareManagers";
      }
      {
        name = "snapshots";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "Snapshot";
        attrName = "snapshots";
      }
      {
        name = "supportbundles";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "SupportBundle";
        attrName = "supportBundles";
      }
      {
        name = "systembackups";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "SystemBackup";
        attrName = "systemBackups";
      }
      {
        name = "systemrestores";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "SystemRestore";
        attrName = "systemRestores";
      }
      {
        name = "volumes";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "Volume";
        attrName = "volumes";
      }
      {
        name = "volumeattachments";
        group = "longhorn.io";
        version = "v1beta2";
        kind = "VolumeAttachment";
        attrName = "volumeAttachments";
      }
    ];

    resources = {
      "longhorn.io"."v1beta2"."BackingImage" = mkAliasDefinitions options.resources."backingImages";
      "longhorn.io"."v1beta2"."BackingImageDataSource" =
        mkAliasDefinitions
          options.resources."backingImageDataSources";
      "longhorn.io"."v1beta2"."BackingImageManager" =
        mkAliasDefinitions
          options.resources."backingImageManagers";
      "longhorn.io"."v1beta2"."Backup" = mkAliasDefinitions options.resources."backups";
      "longhorn.io"."v1beta2"."BackupBackingImage" =
        mkAliasDefinitions
          options.resources."backupBackingImages";
      "longhorn.io"."v1beta2"."BackupTarget" = mkAliasDefinitions options.resources."backupTargets";
      "longhorn.io"."v1beta2"."BackupVolume" = mkAliasDefinitions options.resources."backupVolumes";
      "longhorn.io"."v1beta2"."Engine" = mkAliasDefinitions options.resources."engines";
      "longhorn.io"."v1beta2"."EngineImage" = mkAliasDefinitions options.resources."engineImages";
      "longhorn.io"."v1beta2"."InstanceManager" = mkAliasDefinitions options.resources."instanceManagers";
      "longhorn.io"."v1beta2"."Node" = mkAliasDefinitions options.resources."nodes";
      "longhorn.io"."v1beta2"."Orphan" = mkAliasDefinitions options.resources."orphans";
      "longhorn.io"."v1beta2"."RecurringJob" = mkAliasDefinitions options.resources."recurringJobs";
      "longhorn.io"."v1beta2"."Replica" = mkAliasDefinitions options.resources."replicas";
      "longhorn.io"."v1beta2"."Setting" = mkAliasDefinitions options.resources."settings";
      "longhorn.io"."v1beta2"."ShareManager" = mkAliasDefinitions options.resources."shareManagers";
      "longhorn.io"."v1beta2"."Snapshot" = mkAliasDefinitions options.resources."snapshots";
      "longhorn.io"."v1beta2"."SupportBundle" = mkAliasDefinitions options.resources."supportBundles";
      "longhorn.io"."v1beta2"."SystemBackup" = mkAliasDefinitions options.resources."systemBackups";
      "longhorn.io"."v1beta2"."SystemRestore" = mkAliasDefinitions options.resources."systemRestores";
      "longhorn.io"."v1beta2"."Volume" = mkAliasDefinitions options.resources."volumes";
      "longhorn.io"."v1beta2"."VolumeAttachment" =
        mkAliasDefinitions
          options.resources."volumeAttachments";

    };

    # make all namespaced resources default to the
    # application's namespace
    defaults = [
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "BackingImage";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "BackingImageDataSource";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "BackingImageManager";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "Backup";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "BackupBackingImage";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "BackupTarget";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "BackupVolume";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "Engine";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "EngineImage";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "InstanceManager";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "Node";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "Orphan";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "RecurringJob";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "Replica";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "Setting";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "ShareManager";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "Snapshot";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "SupportBundle";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "SystemBackup";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "SystemRestore";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "Volume";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "longhorn.io";
        version = "v1beta2";
        kind = "VolumeAttachment";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
    ];
  };
}
