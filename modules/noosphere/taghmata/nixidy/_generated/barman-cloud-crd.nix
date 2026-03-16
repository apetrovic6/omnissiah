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
    "barmancloud.cnpg.io.v1.ObjectStore" = {

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
          type = (globalSubmoduleOf "io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta");
        };
        "spec" = mkOption {
          description = "Specification of the desired behavior of the ObjectStore.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#spec-and-status";
          type = (submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpec");
        };
        "status" = mkOption {
          description = "Most recently observed status of the ObjectStore. This data may not be up to\ndate. Populated by the system. Read-only.\nMore info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#spec-and-status";
          type = (types.nullOr (submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreStatus"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpec" = {

      options = {
        "configuration" = mkOption {
          description = "The configuration for the barman-cloud tool suite";
          type = (submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecConfiguration");
        };
        "instanceSidecarConfiguration" = mkOption {
          description = "The configuration for the sidecar that runs in the instance pods";
          type = (
            types.nullOr (submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfiguration")
          );
        };
        "retentionPolicy" = mkOption {
          description = "RetentionPolicy is the retention policy to be used for backups\nand WALs (i.e. '60d'). The retention policy is expressed in the form\nof `XXu` where `XX` is a positive integer and `u` is in `[dwm]` -\ndays, weeks, months.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "instanceSidecarConfiguration" = mkOverride 1002 null;
        "retentionPolicy" = mkOverride 1002 null;
      };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecConfiguration" = {

      options = {
        "azureCredentials" = mkOption {
          description = "The credentials to use to upload data to Azure Blob Storage";
          type = (
            types.nullOr (submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationAzureCredentials")
          );
        };
        "data" = mkOption {
          description = "The configuration to be used to backup the data files\nWhen not defined, base backups files will be stored uncompressed and may\nbe unencrypted in the object store, according to the bucket default\npolicy.";
          type = (types.nullOr (submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationData"));
        };
        "destinationPath" = mkOption {
          description = "The path where to store the backup (i.e. s3://bucket/path/to/folder)\nthis path, with different destination folders, will be used for WALs\nand for data";
          type = types.str;
        };
        "endpointCA" = mkOption {
          description = "EndpointCA store the CA bundle of the barman endpoint.\nUseful when using self-signed certificates to avoid\nerrors with certificate issuer and barman-cloud-wal-archive";
          type = (types.nullOr (submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationEndpointCA"));
        };
        "endpointURL" = mkOption {
          description = "Endpoint to be used to upload data to the cloud,\noverriding the automatic endpoint discovery";
          type = (types.nullOr types.str);
        };
        "googleCredentials" = mkOption {
          description = "The credentials to use to upload data to Google Cloud Storage";
          type = (
            types.nullOr (submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationGoogleCredentials")
          );
        };
        "historyTags" = mkOption {
          description = "HistoryTags is a list of key value pairs that will be passed to the\nBarman --history-tags option.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "s3Credentials" = mkOption {
          description = "The credentials to use to upload data to S3";
          type = (
            types.nullOr (submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationS3Credentials")
          );
        };
        "serverName" = mkOption {
          description = "The server name on S3, the cluster name is used if this\nparameter is omitted";
          type = (types.nullOr types.str);
        };
        "tags" = mkOption {
          description = "Tags is a list of key value pairs that will be passed to the\nBarman --tags option.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "wal" = mkOption {
          description = "The configuration for the backup of the WAL stream.\nWhen not defined, WAL files will be stored uncompressed and may be\nunencrypted in the object store, according to the bucket default policy.";
          type = (types.nullOr (submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationWal"));
        };
      };

      config = {
        "azureCredentials" = mkOverride 1002 null;
        "data" = mkOverride 1002 null;
        "endpointCA" = mkOverride 1002 null;
        "endpointURL" = mkOverride 1002 null;
        "googleCredentials" = mkOverride 1002 null;
        "historyTags" = mkOverride 1002 null;
        "s3Credentials" = mkOverride 1002 null;
        "serverName" = mkOverride 1002 null;
        "tags" = mkOverride 1002 null;
        "wal" = mkOverride 1002 null;
      };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationAzureCredentials" = {

      options = {
        "connectionString" = mkOption {
          description = "The connection string to be used";
          type = (
            types.nullOr (
              submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationAzureCredentialsConnectionString"
            )
          );
        };
        "inheritFromAzureAD" = mkOption {
          description = "Use the Azure AD based authentication without providing explicitly the keys.";
          type = (types.nullOr types.bool);
        };
        "storageAccount" = mkOption {
          description = "The storage account where to upload data";
          type = (
            types.nullOr (
              submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationAzureCredentialsStorageAccount"
            )
          );
        };
        "storageKey" = mkOption {
          description = "The storage account key to be used in conjunction\nwith the storage account name";
          type = (
            types.nullOr (
              submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationAzureCredentialsStorageKey"
            )
          );
        };
        "storageSasToken" = mkOption {
          description = "A shared-access-signature to be used in conjunction with\nthe storage account name";
          type = (
            types.nullOr (
              submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationAzureCredentialsStorageSasToken"
            )
          );
        };
        "useDefaultAzureCredentials" = mkOption {
          description = "Use the default Azure authentication flow, which includes DefaultAzureCredential.\nThis allows authentication using environment variables and managed identities.";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "connectionString" = mkOverride 1002 null;
        "inheritFromAzureAD" = mkOverride 1002 null;
        "storageAccount" = mkOverride 1002 null;
        "storageKey" = mkOverride 1002 null;
        "storageSasToken" = mkOverride 1002 null;
        "useDefaultAzureCredentials" = mkOverride 1002 null;
      };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationAzureCredentialsConnectionString" = {

      options = {
        "key" = mkOption {
          description = "The key to select";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.";
          type = types.str;
        };
      };

      config = { };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationAzureCredentialsStorageAccount" = {

      options = {
        "key" = mkOption {
          description = "The key to select";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.";
          type = types.str;
        };
      };

      config = { };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationAzureCredentialsStorageKey" = {

      options = {
        "key" = mkOption {
          description = "The key to select";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.";
          type = types.str;
        };
      };

      config = { };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationAzureCredentialsStorageSasToken" = {

      options = {
        "key" = mkOption {
          description = "The key to select";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.";
          type = types.str;
        };
      };

      config = { };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationData" = {

      options = {
        "additionalCommandArgs" = mkOption {
          description = "AdditionalCommandArgs represents additional arguments that can be appended\nto the 'barman-cloud-backup' command-line invocation. These arguments\nprovide flexibility to customize the backup process further according to\nspecific requirements or configurations.\n\nExample:\nIn a scenario where specialized backup options are required, such as setting\na specific timeout or defining custom behavior, users can use this field\nto specify additional command arguments.\n\nNote:\nIt's essential to ensure that the provided arguments are valid and supported\nby the 'barman-cloud-backup' command, to avoid potential errors or unintended\nbehavior during execution.";
          type = (types.nullOr (types.listOf types.str));
        };
        "compression" = mkOption {
          description = "Compress a backup file (a tar file per tablespace) while streaming it\nto the object store. Available options are empty string (no\ncompression, default), `gzip`, `bzip2`, and `snappy`.";
          type = (types.nullOr types.str);
        };
        "encryption" = mkOption {
          description = "Whenever to force the encryption of files (if the bucket is\nnot already configured for that).\nAllowed options are empty string (use the bucket policy, default),\n`AES256` and `aws:kms`";
          type = (types.nullOr types.str);
        };
        "immediateCheckpoint" = mkOption {
          description = "Control whether the I/O workload for the backup initial checkpoint will\nbe limited, according to the `checkpoint_completion_target` setting on\nthe PostgreSQL server. If set to true, an immediate checkpoint will be\nused, meaning PostgreSQL will complete the checkpoint as soon as\npossible. `false` by default.";
          type = (types.nullOr types.bool);
        };
        "jobs" = mkOption {
          description = "The number of parallel jobs to be used to upload the backup, defaults\nto 2";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "additionalCommandArgs" = mkOverride 1002 null;
        "compression" = mkOverride 1002 null;
        "encryption" = mkOverride 1002 null;
        "immediateCheckpoint" = mkOverride 1002 null;
        "jobs" = mkOverride 1002 null;
      };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationEndpointCA" = {

      options = {
        "key" = mkOption {
          description = "The key to select";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.";
          type = types.str;
        };
      };

      config = { };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationGoogleCredentials" = {

      options = {
        "applicationCredentials" = mkOption {
          description = "The secret containing the Google Cloud Storage JSON file with the credentials";
          type = (
            types.nullOr (
              submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationGoogleCredentialsApplicationCredentials"
            )
          );
        };
        "gkeEnvironment" = mkOption {
          description = "If set to true, will presume that it's running inside a GKE environment,\ndefault to false.";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "applicationCredentials" = mkOverride 1002 null;
        "gkeEnvironment" = mkOverride 1002 null;
      };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationGoogleCredentialsApplicationCredentials" = {

      options = {
        "key" = mkOption {
          description = "The key to select";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.";
          type = types.str;
        };
      };

      config = { };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationS3Credentials" = {

      options = {
        "accessKeyId" = mkOption {
          description = "The reference to the access key id";
          type = (
            types.nullOr (
              submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationS3CredentialsAccessKeyId"
            )
          );
        };
        "inheritFromIAMRole" = mkOption {
          description = "Use the role based authentication without providing explicitly the keys.";
          type = (types.nullOr types.bool);
        };
        "region" = mkOption {
          description = "The reference to the secret containing the region name";
          type = (
            types.nullOr (submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationS3CredentialsRegion")
          );
        };
        "secretAccessKey" = mkOption {
          description = "The reference to the secret access key";
          type = (
            types.nullOr (
              submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationS3CredentialsSecretAccessKey"
            )
          );
        };
        "sessionToken" = mkOption {
          description = "The references to the session key";
          type = (
            types.nullOr (
              submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationS3CredentialsSessionToken"
            )
          );
        };
      };

      config = {
        "accessKeyId" = mkOverride 1002 null;
        "inheritFromIAMRole" = mkOverride 1002 null;
        "region" = mkOverride 1002 null;
        "secretAccessKey" = mkOverride 1002 null;
        "sessionToken" = mkOverride 1002 null;
      };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationS3CredentialsAccessKeyId" = {

      options = {
        "key" = mkOption {
          description = "The key to select";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.";
          type = types.str;
        };
      };

      config = { };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationS3CredentialsRegion" = {

      options = {
        "key" = mkOption {
          description = "The key to select";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.";
          type = types.str;
        };
      };

      config = { };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationS3CredentialsSecretAccessKey" = {

      options = {
        "key" = mkOption {
          description = "The key to select";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.";
          type = types.str;
        };
      };

      config = { };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationS3CredentialsSessionToken" = {

      options = {
        "key" = mkOption {
          description = "The key to select";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name of the referent.";
          type = types.str;
        };
      };

      config = { };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecConfigurationWal" = {

      options = {
        "archiveAdditionalCommandArgs" = mkOption {
          description = "Additional arguments that can be appended to the 'barman-cloud-wal-archive'\ncommand-line invocation. These arguments provide flexibility to customize\nthe WAL archive process further, according to specific requirements or configurations.\n\nExample:\nIn a scenario where specialized backup options are required, such as setting\na specific timeout or defining custom behavior, users can use this field\nto specify additional command arguments.\n\nNote:\nIt's essential to ensure that the provided arguments are valid and supported\nby the 'barman-cloud-wal-archive' command, to avoid potential errors or unintended\nbehavior during execution.";
          type = (types.nullOr (types.listOf types.str));
        };
        "compression" = mkOption {
          description = "Compress a WAL file before sending it to the object store. Available\noptions are empty string (no compression, default), `gzip`, `bzip2`,\n`lz4`, `snappy`, `xz`, and `zstd`.";
          type = (types.nullOr types.str);
        };
        "encryption" = mkOption {
          description = "Whenever to force the encryption of files (if the bucket is\nnot already configured for that).\nAllowed options are empty string (use the bucket policy, default),\n`AES256` and `aws:kms`";
          type = (types.nullOr types.str);
        };
        "maxParallel" = mkOption {
          description = "Number of WAL files to be either archived in parallel (when the\nPostgreSQL instance is archiving to a backup object store) or\nrestored in parallel (when a PostgreSQL standby is fetching WAL\nfiles from a recovery object store). If not specified, WAL files\nwill be processed one at a time. It accepts a positive integer as a\nvalue - with 1 being the minimum accepted value.";
          type = (types.nullOr types.int);
        };
        "restoreAdditionalCommandArgs" = mkOption {
          description = "Additional arguments that can be appended to the 'barman-cloud-wal-restore'\ncommand-line invocation. These arguments provide flexibility to customize\nthe WAL restore process further, according to specific requirements or configurations.\n\nExample:\nIn a scenario where specialized backup options are required, such as setting\na specific timeout or defining custom behavior, users can use this field\nto specify additional command arguments.\n\nNote:\nIt's essential to ensure that the provided arguments are valid and supported\nby the 'barman-cloud-wal-restore' command, to avoid potential errors or unintended\nbehavior during execution.";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "archiveAdditionalCommandArgs" = mkOverride 1002 null;
        "compression" = mkOverride 1002 null;
        "encryption" = mkOverride 1002 null;
        "maxParallel" = mkOverride 1002 null;
        "restoreAdditionalCommandArgs" = mkOverride 1002 null;
      };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfiguration" = {

      options = {
        "additionalContainerArgs" = mkOption {
          description = "AdditionalContainerArgs is an optional list of command-line arguments\nto be passed to the sidecar container when it starts.\nThe provided arguments are appended to the container’s default arguments.";
          type = (types.nullOr (types.listOf types.str));
        };
        "env" = mkOption {
          description = "The environment to be explicitly passed to the sidecar";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfigurationEnv"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "logLevel" = mkOption {
          description = "The log level for PostgreSQL instances. Valid values are: `error`, `warning`, `info` (default), `debug`, `trace`";
          type = (types.nullOr types.str);
        };
        "resources" = mkOption {
          description = "Resources define cpu/memory requests and limits for the sidecar that runs in the instance pods.";
          type = (
            types.nullOr (
              submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfigurationResources"
            )
          );
        };
        "retentionPolicyIntervalSeconds" = mkOption {
          description = "The retentionCheckInterval defines the frequency at which the\nsystem checks and enforces retention policies.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "additionalContainerArgs" = mkOverride 1002 null;
        "env" = mkOverride 1002 null;
        "logLevel" = mkOverride 1002 null;
        "resources" = mkOverride 1002 null;
        "retentionPolicyIntervalSeconds" = mkOverride 1002 null;
      };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfigurationEnv" = {

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
              submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfigurationEnvValueFrom"
            )
          );
        };
      };

      config = {
        "value" = mkOverride 1002 null;
        "valueFrom" = mkOverride 1002 null;
      };

    };
    "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfigurationEnvValueFrom" = {

      options = {
        "configMapKeyRef" = mkOption {
          description = "Selects a key of a ConfigMap.";
          type = (
            types.nullOr (
              submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfigurationEnvValueFromConfigMapKeyRef"
            )
          );
        };
        "fieldRef" = mkOption {
          description = "Selects a field of the pod: supports metadata.name, metadata.namespace, `metadata.labels['<KEY>']`, `metadata.annotations['<KEY>']`,\nspec.nodeName, spec.serviceAccountName, status.hostIP, status.podIP, status.podIPs.";
          type = (
            types.nullOr (
              submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfigurationEnvValueFromFieldRef"
            )
          );
        };
        "fileKeyRef" = mkOption {
          description = "FileKeyRef selects a key of the env file.\nRequires the EnvFiles feature gate to be enabled.";
          type = (
            types.nullOr (
              submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfigurationEnvValueFromFileKeyRef"
            )
          );
        };
        "resourceFieldRef" = mkOption {
          description = "Selects a resource of the container: only resources limits and requests\n(limits.cpu, limits.memory, limits.ephemeral-storage, requests.cpu, requests.memory and requests.ephemeral-storage) are currently supported.";
          type = (
            types.nullOr (
              submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfigurationEnvValueFromResourceFieldRef"
            )
          );
        };
        "secretKeyRef" = mkOption {
          description = "Selects a key of a secret in the pod's namespace";
          type = (
            types.nullOr (
              submoduleOf "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfigurationEnvValueFromSecretKeyRef"
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
    "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfigurationEnvValueFromConfigMapKeyRef" = {

      options = {
        "key" = mkOption {
          description = "The key to select.";
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
    "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfigurationEnvValueFromFieldRef" = {

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
    "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfigurationEnvValueFromFileKeyRef" = {

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
    "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfigurationEnvValueFromResourceFieldRef" = {

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
    "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfigurationEnvValueFromSecretKeyRef" = {

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
    "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfigurationResources" = {

      options = {
        "claims" = mkOption {
          description = "Claims lists the names of resources, defined in spec.resourceClaims,\nthat are used by this container.\n\nThis field depends on the\nDynamicResourceAllocation feature gate.\n\nThis field is immutable. It can only be set for containers.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfigurationResourcesClaims"
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
    "barmancloud.cnpg.io.v1.ObjectStoreSpecInstanceSidecarConfigurationResourcesClaims" = {

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
    "barmancloud.cnpg.io.v1.ObjectStoreStatus" = {

      options = {
        "serverRecoveryWindow" = mkOption {
          description = "ServerRecoveryWindow maps each server to its recovery window";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
      };

      config = {
        "serverRecoveryWindow" = mkOverride 1002 null;
      };

    };

  };
in
{
  # all resource versions
  options = {
    resources = {
      "barmancloud.cnpg.io"."v1"."ObjectStore" = mkOption {
        description = "ObjectStore is the Schema for the objectstores API.";
        type = (
          types.attrsOf (
            submoduleForDefinition "barmancloud.cnpg.io.v1.ObjectStore" "objectstores" "ObjectStore"
              "barmancloud.cnpg.io"
              "v1"
          )
        );
        default = { };
      };

    }
    // {
      "objectStores" = mkOption {
        description = "ObjectStore is the Schema for the objectstores API.";
        type = (
          types.attrsOf (
            submoduleForDefinition "barmancloud.cnpg.io.v1.ObjectStore" "objectstores" "ObjectStore"
              "barmancloud.cnpg.io"
              "v1"
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
        name = "objectstores";
        group = "barmancloud.cnpg.io";
        version = "v1";
        kind = "ObjectStore";
        attrName = "objectStores";
      }
    ];

    resources = {
      "barmancloud.cnpg.io"."v1"."ObjectStore" = mkAliasDefinitions options.resources."objectStores";

    };

    # make all namespaced resources default to the
    # application's namespace
    defaults = [
      {
        group = "barmancloud.cnpg.io";
        version = "v1";
        kind = "ObjectStore";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
    ];
  };
}
