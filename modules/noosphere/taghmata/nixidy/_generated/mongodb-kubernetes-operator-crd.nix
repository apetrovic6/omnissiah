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
    "mongodb.com.v1.ClusterMongoDBRole" = {

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
          description = "ClusterMongoDBRoleSpec defines the desired state of ClusterMongoDBRole.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.ClusterMongoDBRoleSpec"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.ClusterMongoDBRoleSpec" = {

      options = {
        "authenticationRestrictions" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.ClusterMongoDBRoleSpecAuthenticationRestrictions")
            )
          );
        };
        "db" = mkOption {
          description = "";
          type = types.str;
        };
        "privileges" = mkOption {
          description = "";
          type = (
            types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.ClusterMongoDBRoleSpecPrivileges"))
          );
        };
        "role" = mkOption {
          description = "";
          type = types.str;
        };
        "roles" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.ClusterMongoDBRoleSpecRoles")));
        };
      };

      config = {
        "authenticationRestrictions" = mkOverride 1002 null;
        "privileges" = mkOverride 1002 null;
        "roles" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.ClusterMongoDBRoleSpecAuthenticationRestrictions" = {

      options = {
        "clientSource" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "serverAddress" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "clientSource" = mkOverride 1002 null;
        "serverAddress" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.ClusterMongoDBRoleSpecPrivileges" = {

      options = {
        "actions" = mkOption {
          description = "";
          type = (types.listOf types.str);
        };
        "resource" = mkOption {
          description = "";
          type = (submoduleOf "mongodb.com.v1.ClusterMongoDBRoleSpecPrivilegesResource");
        };
      };

      config = { };

    };
    "mongodb.com.v1.ClusterMongoDBRoleSpecPrivilegesResource" = {

      options = {
        "cluster" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "collection" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "db" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "cluster" = mkOverride 1002 null;
        "collection" = mkOverride 1002 null;
        "db" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.ClusterMongoDBRoleSpecRoles" = {

      options = {
        "db" = mkOption {
          description = "";
          type = types.str;
        };
        "role" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDB" = {

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
          description = "";
          type = (submoduleOf "mongodb.com.v1.MongoDBSpec");
        };
        "status" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBStatus"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiCluster" = {

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
          description = "";
          type = (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpec");
        };
        "status" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterStatus"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpec" = {

      options = {
        "additionalMongodConfig" = mkOption {
          description = "AdditionalMongodConfig is additional configuration that can be passed to\neach data-bearing mongod at runtime. Uses the same structure as the mongod\nconfiguration file:\nhttps://docs.mongodb.com/manual/reference/configuration-options/";
          type = (types.nullOr types.attrs);
        };
        "agent" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecAgent"));
        };
        "backup" = mkOption {
          description = "Backup contains configuration options for configuring\nbackup for this MongoDB resource";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecBackup"));
        };
        "cloudManager" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecCloudManager"));
        };
        "clusterDomain" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "clusterSpecList" = mkOption {
          description = "";
          type = (
            types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecList"))
          );
        };
        "connectivity" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecConnectivity"));
        };
        "credentials" = mkOption {
          description = "Name of the Secret holding credentials information";
          type = types.str;
        };
        "duplicateServiceObjects" = mkOption {
          description = "In few service mesh options for ex: Istio, by default we would need to duplicate the\nservice objects created per pod in all the clusters to enable DNS resolution. Users can\nhowever configure their ServiceMesh with DNS proxy(https://istio.io/latest/docs/ops/configuration/traffic-management/dns-proxy/)\nenabled in which case the operator doesn't need to create the service objects per cluster. This options tells the operator\nwhether it should create the service objects in all the clusters or not. By default, if not specified the operator would create the duplicate svc objects.";
          type = (types.nullOr types.bool);
        };
        "externalAccess" = mkOption {
          description = "ExternalAccessConfiguration provides external access configuration.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecExternalAccess"));
        };
        "featureCompatibilityVersion" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "logLevel" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "opsManager" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecOpsManager"));
        };
        "persistent" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "prometheus" = mkOption {
          description = "Prometheus configurations.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecPrometheus"));
        };
        "security" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecSecurity"));
        };
        "statefulSet" = mkOption {
          description = "StatefulSetConfiguration provides the statefulset override for each of the cluster's statefulset\nif \"StatefulSetConfiguration\" is specified at cluster level under \"clusterSpecList\" that takes precedence over\nthe global one";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecStatefulSet"));
        };
        "topology" = mkOption {
          description = "Topology sets the desired cluster topology of MongoDB resources\nIt defaults (if empty or not set) to SingleCluster. If MultiCluster specified,\nthen clusterSpecList field is mandatory and at least one member cluster has to be specified.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "";
          type = types.str;
        };
        "version" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "additionalMongodConfig" = mkOverride 1002 null;
        "agent" = mkOverride 1002 null;
        "backup" = mkOverride 1002 null;
        "cloudManager" = mkOverride 1002 null;
        "clusterDomain" = mkOverride 1002 null;
        "clusterSpecList" = mkOverride 1002 null;
        "connectivity" = mkOverride 1002 null;
        "duplicateServiceObjects" = mkOverride 1002 null;
        "externalAccess" = mkOverride 1002 null;
        "featureCompatibilityVersion" = mkOverride 1002 null;
        "logLevel" = mkOverride 1002 null;
        "opsManager" = mkOverride 1002 null;
        "persistent" = mkOverride 1002 null;
        "prometheus" = mkOverride 1002 null;
        "security" = mkOverride 1002 null;
        "statefulSet" = mkOverride 1002 null;
        "topology" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecAgent" = {

      options = {
        "backupAgent" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecAgentBackupAgent"));
        };
        "logLevel" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "logRotate" = mkOption {
          description = "DEPRECATED please use mongod.logRotate";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecAgentLogRotate"));
        };
        "maxLogFileDurationHours" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "mongod" = mkOption {
          description = "AgentLoggingMongodConfig contain settings for the mongodb processes configured by the agent";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecAgentMongod"));
        };
        "monitoringAgent" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecAgentMonitoringAgent"));
        };
        "readinessProbe" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecAgentReadinessProbe"));
        };
        "startupOptions" = mkOption {
          description = "StartupParameters can be used to configure the startup parameters with which the agent starts. That also contains\nlog rotation settings as defined here:";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "systemLog" = mkOption {
          description = "DEPRECATED please use mongod.systemLog";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecAgentSystemLog"));
        };
      };

      config = {
        "backupAgent" = mkOverride 1002 null;
        "logLevel" = mkOverride 1002 null;
        "logRotate" = mkOverride 1002 null;
        "maxLogFileDurationHours" = mkOverride 1002 null;
        "mongod" = mkOverride 1002 null;
        "monitoringAgent" = mkOverride 1002 null;
        "readinessProbe" = mkOverride 1002 null;
        "startupOptions" = mkOverride 1002 null;
        "systemLog" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecAgentBackupAgent" = {

      options = {
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the BackupAgent processes";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecAgentBackupAgentLogRotate")
          );
        };
      };

      config = {
        "logRotate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecAgentBackupAgentLogRotate" = {

      options = {
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nOM only supports ints";
          type = (types.nullOr types.int);
        };
        "timeThresholdHrs" = mkOption {
          description = "Number of hours after which this MongoDB Agent rotates the log file.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "sizeThresholdMB" = mkOverride 1002 null;
        "timeThresholdHrs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecAgentLogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecAgentMongod" = {

      options = {
        "auditlogRotate" = mkOption {
          description = "LogRotate configures audit log rotation for the mongodb processes";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecAgentMongodAuditlogRotate")
          );
        };
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the mongodb processes";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecAgentMongodLogRotate"));
        };
        "systemLog" = mkOption {
          description = "SystemLog configures system log of mongod";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecAgentMongodSystemLog"));
        };
      };

      config = {
        "auditlogRotate" = mkOverride 1002 null;
        "logRotate" = mkOverride 1002 null;
        "systemLog" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecAgentMongodAuditlogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecAgentMongodLogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecAgentMongodSystemLog" = {

      options = {
        "destination" = mkOption {
          description = "";
          type = types.str;
        };
        "logAppend" = mkOption {
          description = "";
          type = types.bool;
        };
        "path" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecAgentMonitoringAgent" = {

      options = {
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the BackupAgent processes";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecAgentMonitoringAgentLogRotate")
          );
        };
      };

      config = {
        "logRotate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecAgentMonitoringAgentLogRotate" = {

      options = {
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nOM only supports ints";
          type = (types.nullOr types.int);
        };
        "timeThresholdHrs" = mkOption {
          description = "Number of hours after which this MongoDB Agent rotates the log file.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "sizeThresholdMB" = mkOverride 1002 null;
        "timeThresholdHrs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecAgentReadinessProbe" = {

      options = {
        "environmentVariables" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "environmentVariables" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecAgentSystemLog" = {

      options = {
        "destination" = mkOption {
          description = "";
          type = types.str;
        };
        "logAppend" = mkOption {
          description = "";
          type = types.bool;
        };
        "path" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecBackup" = {

      options = {
        "assignmentLabels" = mkOption {
          description = "Assignment Labels set in the Ops Manager";
          type = (types.nullOr (types.listOf types.str));
        };
        "autoTerminateOnDeletion" = mkOption {
          description = "AutoTerminateOnDeletion indicates if the Operator should stop and terminate the Backup before the cleanup,\nwhen the MongoDB CR is deleted";
          type = (types.nullOr types.bool);
        };
        "encryption" = mkOption {
          description = "Encryption settings";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecBackupEncryption"));
        };
        "mode" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "snapshotSchedule" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecBackupSnapshotSchedule"));
        };
      };

      config = {
        "assignmentLabels" = mkOverride 1002 null;
        "autoTerminateOnDeletion" = mkOverride 1002 null;
        "encryption" = mkOverride 1002 null;
        "mode" = mkOverride 1002 null;
        "snapshotSchedule" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecBackupEncryption" = {

      options = {
        "kmip" = mkOption {
          description = "Kmip corresponds to the KMIP configuration assigned to the Ops Manager Project's configuration.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecBackupEncryptionKmip"));
        };
      };

      config = {
        "kmip" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecBackupEncryptionKmip" = {

      options = {
        "client" = mkOption {
          description = "KMIP Client configuration";
          type = (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecBackupEncryptionKmipClient");
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecBackupEncryptionKmipClient" = {

      options = {
        "clientCertificatePrefix" = mkOption {
          description = "A prefix used to construct KMIP client certificate (and corresponding password) Secret names.\nThe names are generated using the following pattern:\nKMIP Client Certificate (TLS Secret):\n  <clientCertificatePrefix>-<CR Name>-kmip-client\nKMIP Client Certificate Password:\n  <clientCertificatePrefix>-<CR Name>-kmip-client-password\n  The expected key inside is called \"password\".";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "clientCertificatePrefix" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecBackupSnapshotSchedule" = {

      options = {
        "clusterCheckpointIntervalMin" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "dailySnapshotRetentionDays" = mkOption {
          description = "Number of days to retain daily snapshots. Setting 0 will disable this rule.";
          type = (types.nullOr types.int);
        };
        "fullIncrementalDayOfWeek" = mkOption {
          description = "Day of the week when Ops Manager takes a full snapshot. This ensures a recent complete backup. Ops Manager sets the default value to SUNDAY.";
          type = (types.nullOr types.str);
        };
        "monthlySnapshotRetentionMonths" = mkOption {
          description = "Number of months to retain weekly snapshots. Setting 0 will disable this rule.";
          type = (types.nullOr types.int);
        };
        "pointInTimeWindowHours" = mkOption {
          description = "Number of hours in the past for which a point-in-time snapshot can be created.";
          type = (types.nullOr types.int);
        };
        "referenceHourOfDay" = mkOption {
          description = "Hour of the day to schedule snapshots using a 24-hour clock, in UTC.";
          type = (types.nullOr types.int);
        };
        "referenceMinuteOfHour" = mkOption {
          description = "Minute of the hour to schedule snapshots, in UTC.";
          type = (types.nullOr types.int);
        };
        "snapshotIntervalHours" = mkOption {
          description = "Number of hours between snapshots.";
          type = (types.nullOr types.int);
        };
        "snapshotRetentionDays" = mkOption {
          description = "Number of days to keep recent snapshots.";
          type = (types.nullOr types.int);
        };
        "weeklySnapshotRetentionWeeks" = mkOption {
          description = "Number of weeks to retain weekly snapshots. Setting 0 will disable this rule";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "clusterCheckpointIntervalMin" = mkOverride 1002 null;
        "dailySnapshotRetentionDays" = mkOverride 1002 null;
        "fullIncrementalDayOfWeek" = mkOverride 1002 null;
        "monthlySnapshotRetentionMonths" = mkOverride 1002 null;
        "pointInTimeWindowHours" = mkOverride 1002 null;
        "referenceHourOfDay" = mkOverride 1002 null;
        "referenceMinuteOfHour" = mkOverride 1002 null;
        "snapshotIntervalHours" = mkOverride 1002 null;
        "snapshotRetentionDays" = mkOverride 1002 null;
        "weeklySnapshotRetentionWeeks" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecCloudManager" = {

      options = {
        "configMapRef" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecCloudManagerConfigMapRef")
          );
        };
      };

      config = {
        "configMapRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecCloudManagerConfigMapRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecList" = {

      options = {
        "clusterName" = mkOption {
          description = "ClusterName is name of the cluster where the MongoDB Statefulset will be scheduled, the\nname should have a one on one mapping with the service-account created in the central cluster\nto talk to the workload clusters.";
          type = (types.nullOr types.str);
        };
        "externalAccess" = mkOption {
          description = "ExternalAccessConfiguration provides external access configuration for Multi-Cluster.";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListExternalAccess")
          );
        };
        "memberConfig" = mkOption {
          description = "MemberConfig allows to specify votes, priorities and tags for each of the mongodb process.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListMemberConfig")
            )
          );
        };
        "members" = mkOption {
          description = "Amount of members for this MongoDB Replica Set";
          type = types.int;
        };
        "podSpec" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListPodSpec"));
        };
        "service" = mkOption {
          description = "this is an optional service, it will get the name \"<rsName>-service\" in case not provided";
          type = (types.nullOr types.str);
        };
        "statefulSet" = mkOption {
          description = "StatefulSetConfiguration holds the optional custom StatefulSet\nthat should be merged into the operator created one.";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListStatefulSet")
          );
        };
      };

      config = {
        "clusterName" = mkOverride 1002 null;
        "externalAccess" = mkOverride 1002 null;
        "memberConfig" = mkOverride 1002 null;
        "podSpec" = mkOverride 1002 null;
        "service" = mkOverride 1002 null;
        "statefulSet" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListExternalAccess" = {

      options = {
        "externalDomain" = mkOption {
          description = "An external domain that is used for exposing MongoDB to the outside world.";
          type = (types.nullOr types.str);
        };
        "externalService" = mkOption {
          description = "Provides a way to override the default (NodePort) Service";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListExternalAccessExternalService"
            )
          );
        };
      };

      config = {
        "externalDomain" = mkOverride 1002 null;
        "externalService" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListExternalAccessExternalService" = {

      options = {
        "annotations" = mkOption {
          description = "A map of annotations that shall be added to the externally available Service.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "spec" = mkOption {
          description = "A wrapper for the Service spec object.";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListMemberConfig" = {

      options = {
        "priority" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "tags" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "votes" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "priority" = mkOverride 1002 null;
        "tags" = mkOverride 1002 null;
        "votes" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListPodSpec" = {

      options = {
        "persistence" = mkOption {
          description = "Note, that this field is used by MongoDB resources only, let's keep it here for simplicity";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListPodSpecPersistence")
          );
        };
        "podTemplate" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "persistence" = mkOverride 1002 null;
        "podTemplate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListPodSpecPersistence" = {

      options = {
        "multiple" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListPodSpecPersistenceMultiple"
            )
          );
        };
        "single" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListPodSpecPersistenceSingle"
            )
          );
        };
      };

      config = {
        "multiple" = mkOverride 1002 null;
        "single" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListPodSpecPersistenceMultiple" = {

      options = {
        "data" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListPodSpecPersistenceMultipleData"
            )
          );
        };
        "journal" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListPodSpecPersistenceMultipleJournal"
            )
          );
        };
        "logs" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListPodSpecPersistenceMultipleLogs"
            )
          );
        };
      };

      config = {
        "data" = mkOverride 1002 null;
        "journal" = mkOverride 1002 null;
        "logs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListPodSpecPersistenceMultipleData" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListPodSpecPersistenceMultipleJournal" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListPodSpecPersistenceMultipleLogs" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListPodSpecPersistenceSingle" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListStatefulSet" = {

      options = {
        "metadata" = mkOption {
          description = "StatefulSetMetadataWrapper is a wrapper around Labels and Annotations";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListStatefulSetMetadata"
            )
          );
        };
        "spec" = mkOption {
          description = "";
          type = types.attrs;
        };
      };

      config = {
        "metadata" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecClusterSpecListStatefulSetMetadata" = {

      options = {
        "annotations" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "labels" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecConnectivity" = {

      options = {
        "replicaSetHorizons" = mkOption {
          description = "ReplicaSetHorizons holds list of maps of horizons to be configured in each of MongoDB processes.\nHorizons map horizon names to the node addresses for each process in the replicaset, e.g.:\n [\n   {\n     \"internal\": \"my-rs-0.my-internal-domain.com:31843\",\n     \"external\": \"my-rs-0.my-external-domain.com:21467\"\n   },\n   {\n     \"internal\": \"my-rs-1.my-internal-domain.com:31843\",\n     \"external\": \"my-rs-1.my-external-domain.com:21467\"\n   },\n   ...\n ]\nThe key of each item in the map is an arbitrary, user-chosen string that\nrepresents the name of the horizon. The value of the item is the host and,\noptionally, the port that this mongod node will be connected to from.";
          type = (types.nullOr (types.listOf types.attrs));
        };
      };

      config = {
        "replicaSetHorizons" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecExternalAccess" = {

      options = {
        "externalDomain" = mkOption {
          description = "An external domain that is used for exposing MongoDB to the outside world.";
          type = (types.nullOr types.str);
        };
        "externalService" = mkOption {
          description = "Provides a way to override the default (NodePort) Service";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecExternalAccessExternalService")
          );
        };
      };

      config = {
        "externalDomain" = mkOverride 1002 null;
        "externalService" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecExternalAccessExternalService" = {

      options = {
        "annotations" = mkOption {
          description = "A map of annotations that shall be added to the externally available Service.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "spec" = mkOption {
          description = "A wrapper for the Service spec object.";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecOpsManager" = {

      options = {
        "configMapRef" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecOpsManagerConfigMapRef"));
        };
      };

      config = {
        "configMapRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecOpsManagerConfigMapRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecPrometheus" = {

      options = {
        "metricsPath" = mkOption {
          description = "Indicates path to the metrics endpoint.";
          type = (types.nullOr types.str);
        };
        "passwordSecretRef" = mkOption {
          description = "Name of a Secret containing a HTTP Basic Auth Password.";
          type = (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecPrometheusPasswordSecretRef");
        };
        "port" = mkOption {
          description = "Port where metrics endpoint will bind to. Defaults to 9216.";
          type = (types.nullOr types.int);
        };
        "tlsSecretKeyRef" = mkOption {
          description = "Name of a Secret (type kubernetes.io/tls) holding the certificates to use in the\nPrometheus endpoint.";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecPrometheusTlsSecretKeyRef")
          );
        };
        "username" = mkOption {
          description = "HTTP Basic Auth Username for metrics endpoint.";
          type = types.str;
        };
      };

      config = {
        "metricsPath" = mkOverride 1002 null;
        "port" = mkOverride 1002 null;
        "tlsSecretKeyRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecPrometheusPasswordSecretRef" = {

      options = {
        "key" = mkOption {
          description = "Key is the key in the secret storing this password. Defaults to \"password\"";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "Name is the name of the secret storing this user's password";
          type = types.str;
        };
      };

      config = {
        "key" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecPrometheusTlsSecretKeyRef" = {

      options = {
        "key" = mkOption {
          description = "Key is the key in the secret storing this password. Defaults to \"password\"";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "Name is the name of the secret storing this user's password";
          type = types.str;
        };
      };

      config = {
        "key" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecSecurity" = {

      options = {
        "authentication" = mkOption {
          description = "Authentication holds various authentication related settings that affect\nthis MongoDB resource.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecSecurityAuthentication"));
        };
        "certsSecretPrefix" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "roleRefs" = mkOption {
          description = "";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "mongodb.com.v1.MongoDBMultiClusterSpecSecurityRoleRefs" "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "roles" = mkOption {
          description = "";
          type = (
            types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecSecurityRoles"))
          );
        };
        "tls" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecSecurityTls"));
        };
      };

      config = {
        "authentication" = mkOverride 1002 null;
        "certsSecretPrefix" = mkOverride 1002 null;
        "roleRefs" = mkOverride 1002 null;
        "roles" = mkOverride 1002 null;
        "tls" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecSecurityAuthentication" = {

      options = {
        "agents" = mkOption {
          description = "Agents contains authentication configuration properties for the agents";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecSecurityAuthenticationAgents")
          );
        };
        "enabled" = mkOption {
          description = "";
          type = types.bool;
        };
        "ignoreUnknownUsers" = mkOption {
          description = "IgnoreUnknownUsers maps to the inverse of auth.authoritativeSet";
          type = (types.nullOr types.bool);
        };
        "internalCluster" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "ldap" = mkOption {
          description = "LDAP Configuration";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecSecurityAuthenticationLdap")
          );
        };
        "modes" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "oidcProviderConfigs" = mkOption {
          description = "Configuration for OIDC providers";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecSecurityAuthenticationOidcProviderConfigs"
              )
            )
          );
        };
        "requireClientTLSAuthentication" = mkOption {
          description = "Clients should present valid TLS certificates";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "agents" = mkOverride 1002 null;
        "ignoreUnknownUsers" = mkOverride 1002 null;
        "internalCluster" = mkOverride 1002 null;
        "ldap" = mkOverride 1002 null;
        "modes" = mkOverride 1002 null;
        "oidcProviderConfigs" = mkOverride 1002 null;
        "requireClientTLSAuthentication" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecSecurityAuthenticationAgents" = {

      options = {
        "automationLdapGroupDN" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "automationPasswordSecretRef" = mkOption {
          description = "SecretKeySelector selects a key of a Secret.";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecSecurityAuthenticationAgentsAutomationPasswordSecretRef"
            )
          );
        };
        "automationUserName" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "clientCertificateSecretRef" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "mode" = mkOption {
          description = "Mode is the desired Authentication mode that the agents will use";
          type = types.str;
        };
      };

      config = {
        "automationLdapGroupDN" = mkOverride 1002 null;
        "automationPasswordSecretRef" = mkOverride 1002 null;
        "automationUserName" = mkOverride 1002 null;
        "clientCertificateSecretRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecSecurityAuthenticationAgentsAutomationPasswordSecretRef" = {

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
    "mongodb.com.v1.MongoDBMultiClusterSpecSecurityAuthenticationLdap" = {

      options = {
        "authzQueryTemplate" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "bindQueryPasswordSecretRef" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecSecurityAuthenticationLdapBindQueryPasswordSecretRef"
            )
          );
        };
        "bindQueryUser" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "caConfigMapRef" = mkOption {
          description = "Allows to point at a ConfigMap/key with a CA file to mount on the Pod";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecSecurityAuthenticationLdapCaConfigMapRef"
            )
          );
        };
        "servers" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "timeoutMS" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "transportSecurity" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "userCacheInvalidationInterval" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "userToDNMapping" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "validateLDAPServerConfig" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "authzQueryTemplate" = mkOverride 1002 null;
        "bindQueryPasswordSecretRef" = mkOverride 1002 null;
        "bindQueryUser" = mkOverride 1002 null;
        "caConfigMapRef" = mkOverride 1002 null;
        "servers" = mkOverride 1002 null;
        "timeoutMS" = mkOverride 1002 null;
        "transportSecurity" = mkOverride 1002 null;
        "userCacheInvalidationInterval" = mkOverride 1002 null;
        "userToDNMapping" = mkOverride 1002 null;
        "validateLDAPServerConfig" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecSecurityAuthenticationLdapBindQueryPasswordSecretRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecSecurityAuthenticationLdapCaConfigMapRef" = {

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
    "mongodb.com.v1.MongoDBMultiClusterSpecSecurityAuthenticationOidcProviderConfigs" = {

      options = {
        "audience" = mkOption {
          description = "Entity that your external identity provider intends the token for.\nEnter the audience value from the app you registered with external Identity Provider.";
          type = types.str;
        };
        "authorizationMethod" = mkOption {
          description = "Configure single-sign-on for human user access to deployments with Workforce Identity Federation.\nFor programmatic, application access to deployments use Workload Identity Federation.\nOnly one Workforce Identity Federation IdP can be configured per MongoDB resource";
          type = types.str;
        };
        "authorizationType" = mkOption {
          description = "Select GroupMembership to grant authorization based on IdP user group membership, or select UserID to grant\nan individual user authorization.";
          type = types.str;
        };
        "clientId" = mkOption {
          description = "Unique identifier for your registered application. Enter the clientId value from the app you\nregistered with an external Identity Provider.\nRequired when selected Workforce Identity Federation authorization method";
          type = (types.nullOr types.str);
        };
        "configurationName" = mkOption {
          description = "Unique label that identifies this configuration. It is case-sensitive and can only contain the following characters:\n - alphanumeric characters (combination of a to z and 0 to 9)\n - hyphens (-)\n - underscores (_)";
          type = types.str;
        };
        "groupsClaim" = mkOption {
          description = "The identifier of the claim that includes the principal's IdP user group membership information.\nRequired when selected GroupMembership as the authorization type, ignored otherwise";
          type = (types.nullOr types.str);
        };
        "issuerURI" = mkOption {
          description = "Issuer value provided by your registered IdP application. Using this URI, MongoDB finds an OpenID Connect Provider\nConfiguration Document, which should be available in the /.wellknown/open-id-configuration endpoint.\nFor MongoDB 8.0+, the combination of issuerURI and audience must be unique across OIDC provider configurations.\nFor other MongoDB versions, the issuerURI itself must be unique.";
          type = types.str;
        };
        "requestedScopes" = mkOption {
          description = "Tokens that give users permission to request data from the authorization endpoint.\nOnly used for Workforce Identity Federation authorization method";
          type = (types.nullOr (types.listOf types.str));
        };
        "userClaim" = mkOption {
          description = "The identifier of the claim that includes the user principal identity.\nAccept the default value unless your IdP uses a different claim.";
          type = types.str;
        };
      };

      config = {
        "clientId" = mkOverride 1002 null;
        "groupsClaim" = mkOverride 1002 null;
        "requestedScopes" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecSecurityRoleRefs" = {

      options = {
        "kind" = mkOption {
          description = "";
          type = types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecSecurityRoles" = {

      options = {
        "authenticationRestrictions" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecSecurityRolesAuthenticationRestrictions"
              )
            )
          );
        };
        "db" = mkOption {
          description = "";
          type = types.str;
        };
        "privileges" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecSecurityRolesPrivileges")
            )
          );
        };
        "role" = mkOption {
          description = "";
          type = types.str;
        };
        "roles" = mkOption {
          description = "";
          type = (
            types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecSecurityRolesRoles"))
          );
        };
      };

      config = {
        "authenticationRestrictions" = mkOverride 1002 null;
        "privileges" = mkOverride 1002 null;
        "roles" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecSecurityRolesAuthenticationRestrictions" = {

      options = {
        "clientSource" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "serverAddress" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "clientSource" = mkOverride 1002 null;
        "serverAddress" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecSecurityRolesPrivileges" = {

      options = {
        "actions" = mkOption {
          description = "";
          type = (types.listOf types.str);
        };
        "resource" = mkOption {
          description = "";
          type = (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecSecurityRolesPrivilegesResource");
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecSecurityRolesPrivilegesResource" = {

      options = {
        "cluster" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "collection" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "db" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "cluster" = mkOverride 1002 null;
        "collection" = mkOverride 1002 null;
        "db" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecSecurityRolesRoles" = {

      options = {
        "db" = mkOption {
          description = "";
          type = types.str;
        };
        "role" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecSecurityTls" = {

      options = {
        "additionalCertificateDomains" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "ca" = mkOption {
          description = "CA corresponds to a ConfigMap containing an entry for the CA certificate (ca.pem)\nused to validate the certificates created already.";
          type = (types.nullOr types.str);
        };
        "enabled" = mkOption {
          description = "DEPRECATED please enable TLS by setting `security.certsSecretPrefix` or `security.tls.secretRef.prefix`.\nEnables TLS for this resource. This will make the operator try to mount a\nSecret with a defined name (<resource-name>-cert).\nThis is only used when enabling TLS on a MongoDB resource, and not on the\nAppDB, where TLS is configured by setting `secretRef.Name`.";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "additionalCertificateDomains" = mkOverride 1002 null;
        "ca" = mkOverride 1002 null;
        "enabled" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecStatefulSet" = {

      options = {
        "metadata" = mkOption {
          description = "StatefulSetMetadataWrapper is a wrapper around Labels and Annotations";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterSpecStatefulSetMetadata"));
        };
        "spec" = mkOption {
          description = "";
          type = types.attrs;
        };
      };

      config = {
        "metadata" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterSpecStatefulSetMetadata" = {

      options = {
        "annotations" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "labels" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterStatus" = {

      options = {
        "backup" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterStatusBackup"));
        };
        "clusterStatusList" = mkOption {
          description = "ClusterStatusList holds a list of clusterStatuses corresponding to each cluster";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBMultiClusterStatusClusterStatusList"));
        };
        "featureCompatibilityVersion" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "lastTransition" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "link" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "observedGeneration" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "phase" = mkOption {
          description = "";
          type = types.str;
        };
        "pvc" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBMultiClusterStatusPvc")));
        };
        "resourcesNotReady" = mkOption {
          description = "";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "mongodb.com.v1.MongoDBMultiClusterStatusResourcesNotReady"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "version" = mkOption {
          description = "";
          type = types.str;
        };
        "warnings" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "backup" = mkOverride 1002 null;
        "clusterStatusList" = mkOverride 1002 null;
        "featureCompatibilityVersion" = mkOverride 1002 null;
        "lastTransition" = mkOverride 1002 null;
        "link" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "observedGeneration" = mkOverride 1002 null;
        "pvc" = mkOverride 1002 null;
        "resourcesNotReady" = mkOverride 1002 null;
        "warnings" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterStatusBackup" = {

      options = {
        "statusName" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBMultiClusterStatusClusterStatusList" = {

      options = {
        "clusterStatuses" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "mongodb.com.v1.MongoDBMultiClusterStatusClusterStatusListClusterStatuses"
              )
            )
          );
        };
      };

      config = {
        "clusterStatuses" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterStatusClusterStatusListClusterStatuses" = {

      options = {
        "clusterName" = mkOption {
          description = "ClusterName is name of the cluster where the MongoDB Statefulset will be scheduled, the\nname should have a one on one mapping with the service-account created in the central cluster\nto talk to the workload clusters.";
          type = (types.nullOr types.str);
        };
        "lastTransition" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "members" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "observedGeneration" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "phase" = mkOption {
          description = "";
          type = types.str;
        };
        "pvc" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "mongodb.com.v1.MongoDBMultiClusterStatusClusterStatusListClusterStatusesPvc"
              )
            )
          );
        };
        "resourcesNotReady" = mkOption {
          description = "";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "mongodb.com.v1.MongoDBMultiClusterStatusClusterStatusListClusterStatusesResourcesNotReady"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "warnings" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "clusterName" = mkOverride 1002 null;
        "lastTransition" = mkOverride 1002 null;
        "members" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "observedGeneration" = mkOverride 1002 null;
        "pvc" = mkOverride 1002 null;
        "resourcesNotReady" = mkOverride 1002 null;
        "warnings" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterStatusClusterStatusListClusterStatusesPvc" = {

      options = {
        "phase" = mkOption {
          description = "";
          type = types.str;
        };
        "statefulsetName" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBMultiClusterStatusClusterStatusListClusterStatusesResourcesNotReady" = {

      options = {
        "errors" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "mongodb.com.v1.MongoDBMultiClusterStatusClusterStatusListClusterStatusesResourcesNotReadyErrors"
              )
            )
          );
        };
        "kind" = mkOption {
          description = "ResourceKind specifies a kind of a Kubernetes resource. Used in status of a Custom Resource";
          type = types.str;
        };
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "errors" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterStatusClusterStatusListClusterStatusesResourcesNotReadyErrors" =
      {

        options = {
          "message" = mkOption {
            description = "";
            type = (types.nullOr types.str);
          };
          "reason" = mkOption {
            description = "";
            type = (types.nullOr types.str);
          };
        };

        config = {
          "message" = mkOverride 1002 null;
          "reason" = mkOverride 1002 null;
        };

      };
    "mongodb.com.v1.MongoDBMultiClusterStatusPvc" = {

      options = {
        "phase" = mkOption {
          description = "";
          type = types.str;
        };
        "statefulsetName" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBMultiClusterStatusResourcesNotReady" = {

      options = {
        "errors" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.MongoDBMultiClusterStatusResourcesNotReadyErrors")
            )
          );
        };
        "kind" = mkOption {
          description = "ResourceKind specifies a kind of a Kubernetes resource. Used in status of a Custom Resource";
          type = types.str;
        };
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "errors" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBMultiClusterStatusResourcesNotReadyErrors" = {

      options = {
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "reason" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "message" = mkOverride 1002 null;
        "reason" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManager" = {

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
          description = "";
          type = (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpec");
        };
        "status" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerStatus"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpec" = {

      options = {
        "adminCredentials" = mkOption {
          description = "AdminSecret is the secret for the first admin user to create\nhas the fields: \"Username\", \"Password\", \"FirstName\", \"LastName\"";
          type = (types.nullOr types.str);
        };
        "applicationDatabase" = mkOption {
          description = "";
          type = (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabase");
        };
        "backup" = mkOption {
          description = "Backup";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackup"));
        };
        "clusterDomain" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "clusterName" = mkOption {
          description = "Deprecated: This has been replaced by the ClusterDomain which should be\nused instead";
          type = (types.nullOr types.str);
        };
        "clusterSpecList" = mkOption {
          description = "";
          type = (
            types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecClusterSpecList"))
          );
        };
        "configuration" = mkOption {
          description = "The configuration properties passed to Ops Manager/Backup Daemon";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "externalConnectivity" = mkOption {
          description = "MongoDBOpsManagerExternalConnectivity if sets allows for the creation of a Service for\naccessing this Ops Manager resource from outside the Kubernetes cluster.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecExternalConnectivity"));
        };
        "internalConnectivity" = mkOption {
          description = "InternalConnectivity if set allows for overriding the settings of the default service\nused for internal connectivity to the OpsManager servers.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecInternalConnectivity"));
        };
        "jvmParameters" = mkOption {
          description = "Custom JVM parameters passed to the Ops Manager JVM";
          type = (types.nullOr (types.listOf types.str));
        };
        "logging" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecLogging"));
        };
        "opsManagerURL" = mkOption {
          description = "OpsManagerURL specified the URL with which the operator and AppDB monitoring agent should access Ops Manager instance (or instances).\nWhen not set, the operator is using FQDN of Ops Manager's headless service `{name}-svc.{namespace}.svc.cluster.local` to connect to the instance. If that URL cannot be used, then URL in this field should be provided for the operator to connect to Ops Manager instances.";
          type = (types.nullOr types.str);
        };
        "replicas" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "security" = mkOption {
          description = "Configure HTTPS.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecSecurity"));
        };
        "statefulSet" = mkOption {
          description = "Configure custom StatefulSet configuration";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecStatefulSet"));
        };
        "topology" = mkOption {
          description = "Topology sets the desired cluster topology of Ops Manager deployment.\nIt defaults (and if not set) to SingleCluster. If MultiCluster specified,\nthen clusterSpecList field is mandatory and at least one member cluster has to be specified.";
          type = (types.nullOr types.str);
        };
        "version" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "adminCredentials" = mkOverride 1002 null;
        "backup" = mkOverride 1002 null;
        "clusterDomain" = mkOverride 1002 null;
        "clusterName" = mkOverride 1002 null;
        "clusterSpecList" = mkOverride 1002 null;
        "configuration" = mkOverride 1002 null;
        "externalConnectivity" = mkOverride 1002 null;
        "internalConnectivity" = mkOverride 1002 null;
        "jvmParameters" = mkOverride 1002 null;
        "logging" = mkOverride 1002 null;
        "opsManagerURL" = mkOverride 1002 null;
        "replicas" = mkOverride 1002 null;
        "security" = mkOverride 1002 null;
        "statefulSet" = mkOverride 1002 null;
        "topology" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabase" = {

      options = {
        "additionalMongodConfig" = mkOption {
          description = "AdditionalMongodConfig are additional configurations that can be passed to\neach data-bearing mongod at runtime. Uses the same structure as the mongod\nconfiguration file:\nhttps://docs.mongodb.com/manual/reference/configuration-options/";
          type = (types.nullOr types.attrs);
        };
        "agent" = mkOption {
          description = "specify configuration like startup flags and automation config settings for the AutomationAgent and MonitoringAgent";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgent"));
        };
        "automationConfig" = mkOption {
          description = "AutomationConfigOverride holds any fields that will be merged on top of the Automation Config\nthat the operator creates for the AppDB. Currently only the process.disabled and logRotate field is recognized.";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAutomationConfig")
          );
        };
        "cloudManager" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseCloudManager")
          );
        };
        "clusterDomain" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "clusterSpecList" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecList")
            )
          );
        };
        "connectivity" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseConnectivity")
          );
        };
        "credentials" = mkOption {
          description = "Name of the Secret holding credentials information";
          type = (types.nullOr types.str);
        };
        "externalAccess" = mkOption {
          description = "ExternalAccessConfiguration provides external access configuration.";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseExternalAccess")
          );
        };
        "featureCompatibilityVersion" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "memberConfig" = mkOption {
          description = "MemberConfig allows to specify votes, priorities and tags for each of the mongodb process.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseMemberConfig")
            )
          );
        };
        "members" = mkOption {
          description = "Amount of members for this MongoDB Replica Set";
          type = (types.nullOr types.int);
        };
        "monitoringAgent" = mkOption {
          description = "Specify configuration like startup flags just for the MonitoringAgent.\nThese take precedence over\nthe flags set in AutomationAgent";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseMonitoringAgent")
          );
        };
        "opsManager" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseOpsManager")
          );
        };
        "passwordSecretKeyRef" = mkOption {
          description = "PasswordSecretKeyRef contains a reference to the secret which contains the password\nfor the mongodb-ops-manager SCRAM-SHA user";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePasswordSecretKeyRef"
            )
          );
        };
        "podSpec" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePodSpec")
          );
        };
        "prometheus" = mkOption {
          description = "Enables Prometheus integration on the AppDB.";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePrometheus")
          );
        };
        "security" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurity")
          );
        };
        "service" = mkOption {
          description = "this is an optional service, it will get the name \"<rsName>-svc\" in case not provided";
          type = (types.nullOr types.str);
        };
        "topology" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "version" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "additionalMongodConfig" = mkOverride 1002 null;
        "agent" = mkOverride 1002 null;
        "automationConfig" = mkOverride 1002 null;
        "cloudManager" = mkOverride 1002 null;
        "clusterDomain" = mkOverride 1002 null;
        "clusterSpecList" = mkOverride 1002 null;
        "connectivity" = mkOverride 1002 null;
        "credentials" = mkOverride 1002 null;
        "externalAccess" = mkOverride 1002 null;
        "featureCompatibilityVersion" = mkOverride 1002 null;
        "memberConfig" = mkOverride 1002 null;
        "members" = mkOverride 1002 null;
        "monitoringAgent" = mkOverride 1002 null;
        "opsManager" = mkOverride 1002 null;
        "passwordSecretKeyRef" = mkOverride 1002 null;
        "podSpec" = mkOverride 1002 null;
        "prometheus" = mkOverride 1002 null;
        "security" = mkOverride 1002 null;
        "service" = mkOverride 1002 null;
        "topology" = mkOverride 1002 null;
        "type" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgent" = {

      options = {
        "backupAgent" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentBackupAgent")
          );
        };
        "logLevel" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "logRotate" = mkOption {
          description = "DEPRECATED please use mongod.logRotate";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentLogRotate")
          );
        };
        "maxLogFileDurationHours" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "mongod" = mkOption {
          description = "AgentLoggingMongodConfig contain settings for the mongodb processes configured by the agent";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentMongod")
          );
        };
        "monitoringAgent" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentMonitoringAgent"
            )
          );
        };
        "readinessProbe" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentReadinessProbe"
            )
          );
        };
        "startupOptions" = mkOption {
          description = "StartupParameters can be used to configure the startup parameters with which the agent starts. That also contains\nlog rotation settings as defined here:";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "systemLog" = mkOption {
          description = "DEPRECATED please use mongod.systemLog";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentSystemLog")
          );
        };
      };

      config = {
        "backupAgent" = mkOverride 1002 null;
        "logLevel" = mkOverride 1002 null;
        "logRotate" = mkOverride 1002 null;
        "maxLogFileDurationHours" = mkOverride 1002 null;
        "mongod" = mkOverride 1002 null;
        "monitoringAgent" = mkOverride 1002 null;
        "readinessProbe" = mkOverride 1002 null;
        "startupOptions" = mkOverride 1002 null;
        "systemLog" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentBackupAgent" = {

      options = {
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the BackupAgent processes";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentBackupAgentLogRotate"
            )
          );
        };
      };

      config = {
        "logRotate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentBackupAgentLogRotate" = {

      options = {
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nOM only supports ints";
          type = (types.nullOr types.int);
        };
        "timeThresholdHrs" = mkOption {
          description = "Number of hours after which this MongoDB Agent rotates the log file.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "sizeThresholdMB" = mkOverride 1002 null;
        "timeThresholdHrs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentLogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentMongod" = {

      options = {
        "auditlogRotate" = mkOption {
          description = "LogRotate configures audit log rotation for the mongodb processes";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentMongodAuditlogRotate"
            )
          );
        };
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the mongodb processes";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentMongodLogRotate"
            )
          );
        };
        "systemLog" = mkOption {
          description = "SystemLog configures system log of mongod";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentMongodSystemLog"
            )
          );
        };
      };

      config = {
        "auditlogRotate" = mkOverride 1002 null;
        "logRotate" = mkOverride 1002 null;
        "systemLog" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentMongodAuditlogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentMongodLogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentMongodSystemLog" = {

      options = {
        "destination" = mkOption {
          description = "";
          type = types.str;
        };
        "logAppend" = mkOption {
          description = "";
          type = types.bool;
        };
        "path" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentMonitoringAgent" = {

      options = {
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the BackupAgent processes";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentMonitoringAgentLogRotate"
            )
          );
        };
      };

      config = {
        "logRotate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentMonitoringAgentLogRotate" = {

      options = {
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nOM only supports ints";
          type = (types.nullOr types.int);
        };
        "timeThresholdHrs" = mkOption {
          description = "Number of hours after which this MongoDB Agent rotates the log file.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "sizeThresholdMB" = mkOverride 1002 null;
        "timeThresholdHrs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentReadinessProbe" = {

      options = {
        "environmentVariables" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "environmentVariables" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAgentSystemLog" = {

      options = {
        "destination" = mkOption {
          description = "";
          type = types.str;
        };
        "logAppend" = mkOption {
          description = "";
          type = types.bool;
        };
        "path" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAutomationConfig" = {

      options = {
        "processes" = mkOption {
          description = "";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAutomationConfigProcesses"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "replicaSet" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAutomationConfigReplicaSet"
            )
          );
        };
      };

      config = {
        "processes" = mkOverride 1002 null;
        "replicaSet" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAutomationConfigProcesses" = {

      options = {
        "disabled" = mkOption {
          description = "";
          type = types.bool;
        };
        "logRotate" = mkOption {
          description = "CrdLogRotate is the crd definition of LogRotate including fields in strings while the agent supports them as float64";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAutomationConfigProcessesLogRotate"
            )
          );
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "logRotate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAutomationConfigProcessesLogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseAutomationConfigReplicaSet" = {

      options = {
        "id" = mkOption {
          description = "Id can be used together with additionalMongodConfig.replication.replSetName\nto manage clusters where replSetName differs from the MongoDBCommunity resource name";
          type = (types.nullOr types.str);
        };
        "settings" = mkOption {
          description = "MapWrapper is a wrapper for a map to be used by other structs.\nThe CRD generator does not support map[string]interface{}\non the top level and hence we need to work around this with\na wrapping struct.";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "id" = mkOverride 1002 null;
        "settings" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseCloudManager" = {

      options = {
        "configMapRef" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseCloudManagerConfigMapRef"
            )
          );
        };
      };

      config = {
        "configMapRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseCloudManagerConfigMapRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecList" = {

      options = {
        "clusterName" = mkOption {
          description = "ClusterName is name of the cluster where the MongoDB Statefulset will be scheduled, the\nname should have a one on one mapping with the service-account created in the central cluster\nto talk to the workload clusters.";
          type = (types.nullOr types.str);
        };
        "externalAccess" = mkOption {
          description = "ExternalAccessConfiguration provides external access configuration for Multi-Cluster.";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListExternalAccess"
            )
          );
        };
        "memberConfig" = mkOption {
          description = "MemberConfig allows to specify votes, priorities and tags for each of the mongodb process.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListMemberConfig"
              )
            )
          );
        };
        "members" = mkOption {
          description = "Amount of members for this MongoDB Replica Set";
          type = types.int;
        };
        "podSpec" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListPodSpec"
            )
          );
        };
        "service" = mkOption {
          description = "this is an optional service, it will get the name \"<rsName>-service\" in case not provided";
          type = (types.nullOr types.str);
        };
        "statefulSet" = mkOption {
          description = "StatefulSetConfiguration holds the optional custom StatefulSet\nthat should be merged into the operator created one.";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListStatefulSet"
            )
          );
        };
      };

      config = {
        "clusterName" = mkOverride 1002 null;
        "externalAccess" = mkOverride 1002 null;
        "memberConfig" = mkOverride 1002 null;
        "podSpec" = mkOverride 1002 null;
        "service" = mkOverride 1002 null;
        "statefulSet" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListExternalAccess" = {

      options = {
        "externalDomain" = mkOption {
          description = "An external domain that is used for exposing MongoDB to the outside world.";
          type = (types.nullOr types.str);
        };
        "externalService" = mkOption {
          description = "Provides a way to override the default (NodePort) Service";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListExternalAccessExternalService"
            )
          );
        };
      };

      config = {
        "externalDomain" = mkOverride 1002 null;
        "externalService" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListExternalAccessExternalService" =
      {

        options = {
          "annotations" = mkOption {
            description = "A map of annotations that shall be added to the externally available Service.";
            type = (types.nullOr (types.attrsOf types.str));
          };
          "spec" = mkOption {
            description = "A wrapper for the Service spec object.";
            type = (types.nullOr types.attrs);
          };
        };

        config = {
          "annotations" = mkOverride 1002 null;
          "spec" = mkOverride 1002 null;
        };

      };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListMemberConfig" = {

      options = {
        "priority" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "tags" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "votes" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "priority" = mkOverride 1002 null;
        "tags" = mkOverride 1002 null;
        "votes" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListPodSpec" = {

      options = {
        "persistence" = mkOption {
          description = "Note, that this field is used by MongoDB resources only, let's keep it here for simplicity";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListPodSpecPersistence"
            )
          );
        };
        "podTemplate" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "persistence" = mkOverride 1002 null;
        "podTemplate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListPodSpecPersistence" = {

      options = {
        "multiple" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListPodSpecPersistenceMultiple"
            )
          );
        };
        "single" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListPodSpecPersistenceSingle"
            )
          );
        };
      };

      config = {
        "multiple" = mkOverride 1002 null;
        "single" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListPodSpecPersistenceMultiple" =
      {

        options = {
          "data" = mkOption {
            description = "";
            type = (
              types.nullOr (
                submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListPodSpecPersistenceMultipleData"
              )
            );
          };
          "journal" = mkOption {
            description = "";
            type = (
              types.nullOr (
                submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListPodSpecPersistenceMultipleJournal"
              )
            );
          };
          "logs" = mkOption {
            description = "";
            type = (
              types.nullOr (
                submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListPodSpecPersistenceMultipleLogs"
              )
            );
          };
        };

        config = {
          "data" = mkOverride 1002 null;
          "journal" = mkOverride 1002 null;
          "logs" = mkOverride 1002 null;
        };

      };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListPodSpecPersistenceMultipleData" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "";
            type = (types.nullOr types.attrs);
          };
          "storage" = mkOption {
            description = "";
            type = (types.nullOr types.str);
          };
          "storageClass" = mkOption {
            description = "";
            type = (types.nullOr types.str);
          };
        };

        config = {
          "labelSelector" = mkOverride 1002 null;
          "storage" = mkOverride 1002 null;
          "storageClass" = mkOverride 1002 null;
        };

      };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListPodSpecPersistenceMultipleJournal" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "";
            type = (types.nullOr types.attrs);
          };
          "storage" = mkOption {
            description = "";
            type = (types.nullOr types.str);
          };
          "storageClass" = mkOption {
            description = "";
            type = (types.nullOr types.str);
          };
        };

        config = {
          "labelSelector" = mkOverride 1002 null;
          "storage" = mkOverride 1002 null;
          "storageClass" = mkOverride 1002 null;
        };

      };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListPodSpecPersistenceMultipleLogs" =
      {

        options = {
          "labelSelector" = mkOption {
            description = "";
            type = (types.nullOr types.attrs);
          };
          "storage" = mkOption {
            description = "";
            type = (types.nullOr types.str);
          };
          "storageClass" = mkOption {
            description = "";
            type = (types.nullOr types.str);
          };
        };

        config = {
          "labelSelector" = mkOverride 1002 null;
          "storage" = mkOverride 1002 null;
          "storageClass" = mkOverride 1002 null;
        };

      };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListPodSpecPersistenceSingle" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListStatefulSet" = {

      options = {
        "metadata" = mkOption {
          description = "StatefulSetMetadataWrapper is a wrapper around Labels and Annotations";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListStatefulSetMetadata"
            )
          );
        };
        "spec" = mkOption {
          description = "";
          type = types.attrs;
        };
      };

      config = {
        "metadata" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseClusterSpecListStatefulSetMetadata" = {

      options = {
        "annotations" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "labels" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseConnectivity" = {

      options = {
        "replicaSetHorizons" = mkOption {
          description = "ReplicaSetHorizons holds list of maps of horizons to be configured in each of MongoDB processes.\nHorizons map horizon names to the node addresses for each process in the replicaset, e.g.:\n [\n   {\n     \"internal\": \"my-rs-0.my-internal-domain.com:31843\",\n     \"external\": \"my-rs-0.my-external-domain.com:21467\"\n   },\n   {\n     \"internal\": \"my-rs-1.my-internal-domain.com:31843\",\n     \"external\": \"my-rs-1.my-external-domain.com:21467\"\n   },\n   ...\n ]\nThe key of each item in the map is an arbitrary, user-chosen string that\nrepresents the name of the horizon. The value of the item is the host and,\noptionally, the port that this mongod node will be connected to from.";
          type = (types.nullOr (types.listOf types.attrs));
        };
      };

      config = {
        "replicaSetHorizons" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseExternalAccess" = {

      options = {
        "externalDomain" = mkOption {
          description = "An external domain that is used for exposing MongoDB to the outside world.";
          type = (types.nullOr types.str);
        };
        "externalService" = mkOption {
          description = "Provides a way to override the default (NodePort) Service";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseExternalAccessExternalService"
            )
          );
        };
      };

      config = {
        "externalDomain" = mkOverride 1002 null;
        "externalService" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseExternalAccessExternalService" = {

      options = {
        "annotations" = mkOption {
          description = "A map of annotations that shall be added to the externally available Service.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "spec" = mkOption {
          description = "A wrapper for the Service spec object.";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseMemberConfig" = {

      options = {
        "priority" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "tags" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "votes" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "priority" = mkOverride 1002 null;
        "tags" = mkOverride 1002 null;
        "votes" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseMonitoringAgent" = {

      options = {
        "startupOptions" = mkOption {
          description = "StartupParameters can be used to configure the startup parameters with which the agent starts. That also contains\nlog rotation settings as defined here:";
          type = (types.attrsOf types.str);
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseOpsManager" = {

      options = {
        "configMapRef" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseOpsManagerConfigMapRef"
            )
          );
        };
      };

      config = {
        "configMapRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseOpsManagerConfigMapRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePasswordSecretKeyRef" = {

      options = {
        "key" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "key" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePodSpec" = {

      options = {
        "persistence" = mkOption {
          description = "Note, that this field is used by MongoDB resources only, let's keep it here for simplicity";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePodSpecPersistence"
            )
          );
        };
        "podTemplate" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "persistence" = mkOverride 1002 null;
        "podTemplate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePodSpecPersistence" = {

      options = {
        "multiple" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePodSpecPersistenceMultiple"
            )
          );
        };
        "single" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePodSpecPersistenceSingle"
            )
          );
        };
      };

      config = {
        "multiple" = mkOverride 1002 null;
        "single" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePodSpecPersistenceMultiple" = {

      options = {
        "data" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePodSpecPersistenceMultipleData"
            )
          );
        };
        "journal" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePodSpecPersistenceMultipleJournal"
            )
          );
        };
        "logs" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePodSpecPersistenceMultipleLogs"
            )
          );
        };
      };

      config = {
        "data" = mkOverride 1002 null;
        "journal" = mkOverride 1002 null;
        "logs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePodSpecPersistenceMultipleData" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePodSpecPersistenceMultipleJournal" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePodSpecPersistenceMultipleLogs" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePodSpecPersistenceSingle" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePrometheus" = {

      options = {
        "metricsPath" = mkOption {
          description = "Indicates path to the metrics endpoint.";
          type = (types.nullOr types.str);
        };
        "passwordSecretRef" = mkOption {
          description = "Name of a Secret containing a HTTP Basic Auth Password.";
          type = (
            submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePrometheusPasswordSecretRef"
          );
        };
        "port" = mkOption {
          description = "Port where metrics endpoint will bind to. Defaults to 9216.";
          type = (types.nullOr types.int);
        };
        "tlsSecretKeyRef" = mkOption {
          description = "Name of a Secret (type kubernetes.io/tls) holding the certificates to use in the\nPrometheus endpoint.";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePrometheusTlsSecretKeyRef"
            )
          );
        };
        "username" = mkOption {
          description = "HTTP Basic Auth Username for metrics endpoint.";
          type = types.str;
        };
      };

      config = {
        "metricsPath" = mkOverride 1002 null;
        "port" = mkOverride 1002 null;
        "tlsSecretKeyRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePrometheusPasswordSecretRef" = {

      options = {
        "key" = mkOption {
          description = "Key is the key in the secret storing this password. Defaults to \"password\"";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "Name is the name of the secret storing this user's password";
          type = types.str;
        };
      };

      config = {
        "key" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabasePrometheusTlsSecretKeyRef" = {

      options = {
        "key" = mkOption {
          description = "Key is the key in the secret storing this password. Defaults to \"password\"";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "Name is the name of the secret storing this user's password";
          type = types.str;
        };
      };

      config = {
        "key" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurity" = {

      options = {
        "authentication" = mkOption {
          description = "Authentication holds various authentication related settings that affect\nthis MongoDB resource.";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityAuthentication"
            )
          );
        };
        "certsSecretPrefix" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "roleRefs" = mkOption {
          description = "";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityRoleRefs"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "roles" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityRoles")
            )
          );
        };
        "tls" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityTls")
          );
        };
      };

      config = {
        "authentication" = mkOverride 1002 null;
        "certsSecretPrefix" = mkOverride 1002 null;
        "roleRefs" = mkOverride 1002 null;
        "roles" = mkOverride 1002 null;
        "tls" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityAuthentication" = {

      options = {
        "agents" = mkOption {
          description = "Agents contains authentication configuration properties for the agents";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityAuthenticationAgents"
            )
          );
        };
        "enabled" = mkOption {
          description = "";
          type = types.bool;
        };
        "ignoreUnknownUsers" = mkOption {
          description = "IgnoreUnknownUsers maps to the inverse of auth.authoritativeSet";
          type = (types.nullOr types.bool);
        };
        "internalCluster" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "ldap" = mkOption {
          description = "LDAP Configuration";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityAuthenticationLdap"
            )
          );
        };
        "modes" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "oidcProviderConfigs" = mkOption {
          description = "Configuration for OIDC providers";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityAuthenticationOidcProviderConfigs"
              )
            )
          );
        };
        "requireClientTLSAuthentication" = mkOption {
          description = "Clients should present valid TLS certificates";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "agents" = mkOverride 1002 null;
        "ignoreUnknownUsers" = mkOverride 1002 null;
        "internalCluster" = mkOverride 1002 null;
        "ldap" = mkOverride 1002 null;
        "modes" = mkOverride 1002 null;
        "oidcProviderConfigs" = mkOverride 1002 null;
        "requireClientTLSAuthentication" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityAuthenticationAgents" = {

      options = {
        "automationLdapGroupDN" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "automationPasswordSecretRef" = mkOption {
          description = "SecretKeySelector selects a key of a Secret.";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityAuthenticationAgentsAutomationPasswordSecretRef"
            )
          );
        };
        "automationUserName" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "clientCertificateSecretRef" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "mode" = mkOption {
          description = "Mode is the desired Authentication mode that the agents will use";
          type = types.str;
        };
      };

      config = {
        "automationLdapGroupDN" = mkOverride 1002 null;
        "automationPasswordSecretRef" = mkOverride 1002 null;
        "automationUserName" = mkOverride 1002 null;
        "clientCertificateSecretRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityAuthenticationAgentsAutomationPasswordSecretRef" =
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
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityAuthenticationLdap" = {

      options = {
        "authzQueryTemplate" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "bindQueryPasswordSecretRef" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityAuthenticationLdapBindQueryPasswordSecretRef"
            )
          );
        };
        "bindQueryUser" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "caConfigMapRef" = mkOption {
          description = "Allows to point at a ConfigMap/key with a CA file to mount on the Pod";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityAuthenticationLdapCaConfigMapRef"
            )
          );
        };
        "servers" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "timeoutMS" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "transportSecurity" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "userCacheInvalidationInterval" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "userToDNMapping" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "validateLDAPServerConfig" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "authzQueryTemplate" = mkOverride 1002 null;
        "bindQueryPasswordSecretRef" = mkOverride 1002 null;
        "bindQueryUser" = mkOverride 1002 null;
        "caConfigMapRef" = mkOverride 1002 null;
        "servers" = mkOverride 1002 null;
        "timeoutMS" = mkOverride 1002 null;
        "transportSecurity" = mkOverride 1002 null;
        "userCacheInvalidationInterval" = mkOverride 1002 null;
        "userToDNMapping" = mkOverride 1002 null;
        "validateLDAPServerConfig" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityAuthenticationLdapBindQueryPasswordSecretRef" =
      {

        options = {
          "name" = mkOption {
            description = "";
            type = types.str;
          };
        };

        config = { };

      };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityAuthenticationLdapCaConfigMapRef" =
      {

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
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityAuthenticationOidcProviderConfigs" =
      {

        options = {
          "audience" = mkOption {
            description = "Entity that your external identity provider intends the token for.\nEnter the audience value from the app you registered with external Identity Provider.";
            type = types.str;
          };
          "authorizationMethod" = mkOption {
            description = "Configure single-sign-on for human user access to deployments with Workforce Identity Federation.\nFor programmatic, application access to deployments use Workload Identity Federation.\nOnly one Workforce Identity Federation IdP can be configured per MongoDB resource";
            type = types.str;
          };
          "authorizationType" = mkOption {
            description = "Select GroupMembership to grant authorization based on IdP user group membership, or select UserID to grant\nan individual user authorization.";
            type = types.str;
          };
          "clientId" = mkOption {
            description = "Unique identifier for your registered application. Enter the clientId value from the app you\nregistered with an external Identity Provider.\nRequired when selected Workforce Identity Federation authorization method";
            type = (types.nullOr types.str);
          };
          "configurationName" = mkOption {
            description = "Unique label that identifies this configuration. It is case-sensitive and can only contain the following characters:\n - alphanumeric characters (combination of a to z and 0 to 9)\n - hyphens (-)\n - underscores (_)";
            type = types.str;
          };
          "groupsClaim" = mkOption {
            description = "The identifier of the claim that includes the principal's IdP user group membership information.\nRequired when selected GroupMembership as the authorization type, ignored otherwise";
            type = (types.nullOr types.str);
          };
          "issuerURI" = mkOption {
            description = "Issuer value provided by your registered IdP application. Using this URI, MongoDB finds an OpenID Connect Provider\nConfiguration Document, which should be available in the /.wellknown/open-id-configuration endpoint.\nFor MongoDB 8.0+, the combination of issuerURI and audience must be unique across OIDC provider configurations.\nFor other MongoDB versions, the issuerURI itself must be unique.";
            type = types.str;
          };
          "requestedScopes" = mkOption {
            description = "Tokens that give users permission to request data from the authorization endpoint.\nOnly used for Workforce Identity Federation authorization method";
            type = (types.nullOr (types.listOf types.str));
          };
          "userClaim" = mkOption {
            description = "The identifier of the claim that includes the user principal identity.\nAccept the default value unless your IdP uses a different claim.";
            type = types.str;
          };
        };

        config = {
          "clientId" = mkOverride 1002 null;
          "groupsClaim" = mkOverride 1002 null;
          "requestedScopes" = mkOverride 1002 null;
        };

      };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityRoleRefs" = {

      options = {
        "kind" = mkOption {
          description = "";
          type = types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityRoles" = {

      options = {
        "authenticationRestrictions" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityRolesAuthenticationRestrictions"
              )
            )
          );
        };
        "db" = mkOption {
          description = "";
          type = types.str;
        };
        "privileges" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityRolesPrivileges"
              )
            )
          );
        };
        "role" = mkOption {
          description = "";
          type = types.str;
        };
        "roles" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityRolesRoles"
              )
            )
          );
        };
      };

      config = {
        "authenticationRestrictions" = mkOverride 1002 null;
        "privileges" = mkOverride 1002 null;
        "roles" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityRolesAuthenticationRestrictions" = {

      options = {
        "clientSource" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "serverAddress" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "clientSource" = mkOverride 1002 null;
        "serverAddress" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityRolesPrivileges" = {

      options = {
        "actions" = mkOption {
          description = "";
          type = (types.listOf types.str);
        };
        "resource" = mkOption {
          description = "";
          type = (
            submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityRolesPrivilegesResource"
          );
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityRolesPrivilegesResource" = {

      options = {
        "cluster" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "collection" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "db" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "cluster" = mkOverride 1002 null;
        "collection" = mkOverride 1002 null;
        "db" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityRolesRoles" = {

      options = {
        "db" = mkOption {
          description = "";
          type = types.str;
        };
        "role" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecApplicationDatabaseSecurityTls" = {

      options = {
        "additionalCertificateDomains" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "ca" = mkOption {
          description = "CA corresponds to a ConfigMap containing an entry for the CA certificate (ca.pem)\nused to validate the certificates created already.";
          type = (types.nullOr types.str);
        };
        "enabled" = mkOption {
          description = "DEPRECATED please enable TLS by setting `security.certsSecretPrefix` or `security.tls.secretRef.prefix`.\nEnables TLS for this resource. This will make the operator try to mount a\nSecret with a defined name (<resource-name>-cert).\nThis is only used when enabling TLS on a MongoDB resource, and not on the\nAppDB, where TLS is configured by setting `secretRef.Name`.";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "additionalCertificateDomains" = mkOverride 1002 null;
        "ca" = mkOverride 1002 null;
        "enabled" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackup" = {

      options = {
        "assignmentLabels" = mkOption {
          description = "Assignment Labels set in the Ops Manager";
          type = (types.nullOr (types.listOf types.str));
        };
        "blockStores" = mkOption {
          description = "";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "mongodb.com.v1.MongoDBOpsManagerSpecBackupBlockStores" "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "enabled" = mkOption {
          description = "Enabled indicates if Backups will be enabled for this Ops Manager.";
          type = types.bool;
        };
        "encryption" = mkOption {
          description = "Encryption settings";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupEncryption"));
        };
        "externalServiceEnabled" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "fileSystemStores" = mkOption {
          description = "";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "mongodb.com.v1.MongoDBOpsManagerSpecBackupFileSystemStores"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "headDB" = mkOption {
          description = "HeadDB specifies configuration options for the HeadDB";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupHeadDB"));
        };
        "jvmParameters" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "logging" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupLogging"));
        };
        "members" = mkOption {
          description = "Members indicate the number of backup daemon pods to create.";
          type = (types.nullOr types.int);
        };
        "opLogStores" = mkOption {
          description = "OplogStoreConfigs describes the list of oplog store configs used for backup";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "mongodb.com.v1.MongoDBOpsManagerSpecBackupOpLogStores" "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "queryableBackupSecretRef" = mkOption {
          description = "QueryableBackupSecretRef references the secret which contains the pem file which is used\nfor queryable backup. This will be mounted into the Ops Manager pod.";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupQueryableBackupSecretRef")
          );
        };
        "s3OpLogStores" = mkOption {
          description = "S3OplogStoreConfigs describes the list of s3 oplog store configs used for backup.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3OpLogStores" "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "s3Stores" = mkOption {
          description = "";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3Stores" "name" [ ]
            )
          );
          apply = attrsToList;
        };
        "statefulSet" = mkOption {
          description = "StatefulSetConfiguration holds the optional custom StatefulSet\nthat should be merged into the operator created one.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupStatefulSet"));
        };
      };

      config = {
        "assignmentLabels" = mkOverride 1002 null;
        "blockStores" = mkOverride 1002 null;
        "encryption" = mkOverride 1002 null;
        "externalServiceEnabled" = mkOverride 1002 null;
        "fileSystemStores" = mkOverride 1002 null;
        "headDB" = mkOverride 1002 null;
        "jvmParameters" = mkOverride 1002 null;
        "logging" = mkOverride 1002 null;
        "members" = mkOverride 1002 null;
        "opLogStores" = mkOverride 1002 null;
        "queryableBackupSecretRef" = mkOverride 1002 null;
        "s3OpLogStores" = mkOverride 1002 null;
        "s3Stores" = mkOverride 1002 null;
        "statefulSet" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupBlockStores" = {

      options = {
        "assignmentLabels" = mkOption {
          description = "Assignment Labels set in the Ops Manager";
          type = (types.nullOr (types.listOf types.str));
        };
        "mongodbResourceRef" = mkOption {
          description = "";
          type = (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupBlockStoresMongodbResourceRef");
        };
        "mongodbUserRef" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupBlockStoresMongodbUserRef")
          );
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "assignmentLabels" = mkOverride 1002 null;
        "mongodbUserRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupBlockStoresMongodbResourceRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "namespace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupBlockStoresMongodbUserRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupEncryption" = {

      options = {
        "kmip" = mkOption {
          description = "Kmip corresponds to the KMIP configuration assigned to the Ops Manager Project's configuration.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupEncryptionKmip"));
        };
      };

      config = {
        "kmip" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupEncryptionKmip" = {

      options = {
        "server" = mkOption {
          description = "KMIP Server configuration";
          type = (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupEncryptionKmipServer");
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupEncryptionKmipServer" = {

      options = {
        "ca" = mkOption {
          description = "CA corresponds to a ConfigMap containing an entry for the CA certificate (ca.pem)\nused for KMIP authentication";
          type = types.str;
        };
        "url" = mkOption {
          description = "KMIP Server url in the following format: hostname:port\nValid examples are:\n  10.10.10.3:5696\n  my-kmip-server.mycorp.com:5696\n  kmip-svc.svc.cluster.local:5696";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupFileSystemStores" = {

      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupHeadDB" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupLogging" = {

      options = {
        "LogBackAccessRef" = mkOption {
          description = "LogBackAccessRef points at a ConfigMap/key with the logback access configuration file to mount on the Pod";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupLoggingLogBackAccessRef")
          );
        };
        "LogBackRef" = mkOption {
          description = "LogBackRef points at a ConfigMap/key with the logback configuration file to mount on the Pod";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupLoggingLogBackRef"));
        };
      };

      config = {
        "LogBackAccessRef" = mkOverride 1002 null;
        "LogBackRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupLoggingLogBackAccessRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupLoggingLogBackRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupOpLogStores" = {

      options = {
        "assignmentLabels" = mkOption {
          description = "Assignment Labels set in the Ops Manager";
          type = (types.nullOr (types.listOf types.str));
        };
        "mongodbResourceRef" = mkOption {
          description = "";
          type = (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupOpLogStoresMongodbResourceRef");
        };
        "mongodbUserRef" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupOpLogStoresMongodbUserRef")
          );
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "assignmentLabels" = mkOverride 1002 null;
        "mongodbUserRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupOpLogStoresMongodbResourceRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "namespace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupOpLogStoresMongodbUserRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupQueryableBackupSecretRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3OpLogStores" = {

      options = {
        "assignmentLabels" = mkOption {
          description = "Assignment Labels set in the Ops Manager";
          type = (types.nullOr (types.listOf types.str));
        };
        "customCertificate" = mkOption {
          description = "Set this to \"true\" to use the appDBCa as a CA to access S3.\nDeprecated: This has been replaced by CustomCertificateSecretRefs,\nIn the future all custom certificates, which includes the appDBCa\nfor s3Config should be configured in CustomCertificateSecretRefs instead.";
          type = (types.nullOr types.bool);
        };
        "customCertificateSecretRefs" = mkOption {
          description = "CustomCertificateSecretRefs is a list of valid Certificate Authority certificate secrets\nthat apply to the associated S3 bucket.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3OpLogStoresCustomCertificateSecretRefs"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "irsaEnabled" = mkOption {
          description = "This is only set to \"true\" when a user is running in EKS and is using AWS IRSA to configure\nS3 snapshot store. For more details refer this: https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/";
          type = (types.nullOr types.bool);
        };
        "mongodbResourceRef" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3OpLogStoresMongodbResourceRef"
            )
          );
        };
        "mongodbUserRef" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3OpLogStoresMongodbUserRef")
          );
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "pathStyleAccessEnabled" = mkOption {
          description = "";
          type = types.bool;
        };
        "s3BucketEndpoint" = mkOption {
          description = "";
          type = types.str;
        };
        "s3BucketName" = mkOption {
          description = "";
          type = types.str;
        };
        "s3RegionOverride" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "s3SecretRef" = mkOption {
          description = "S3SecretRef is the secret that contains the AWS credentials used to access S3\nIt is optional because the credentials can be provided via AWS IRSA";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3OpLogStoresS3SecretRef")
          );
        };
      };

      config = {
        "assignmentLabels" = mkOverride 1002 null;
        "customCertificate" = mkOverride 1002 null;
        "customCertificateSecretRefs" = mkOverride 1002 null;
        "irsaEnabled" = mkOverride 1002 null;
        "mongodbResourceRef" = mkOverride 1002 null;
        "mongodbUserRef" = mkOverride 1002 null;
        "s3RegionOverride" = mkOverride 1002 null;
        "s3SecretRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3OpLogStoresCustomCertificateSecretRefs" = {

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
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3OpLogStoresMongodbResourceRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "namespace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3OpLogStoresMongodbUserRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3OpLogStoresS3SecretRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3Stores" = {

      options = {
        "assignmentLabels" = mkOption {
          description = "Assignment Labels set in the Ops Manager";
          type = (types.nullOr (types.listOf types.str));
        };
        "customCertificate" = mkOption {
          description = "Set this to \"true\" to use the appDBCa as a CA to access S3.\nDeprecated: This has been replaced by CustomCertificateSecretRefs,\nIn the future all custom certificates, which includes the appDBCa\nfor s3Config should be configured in CustomCertificateSecretRefs instead.";
          type = (types.nullOr types.bool);
        };
        "customCertificateSecretRefs" = mkOption {
          description = "CustomCertificateSecretRefs is a list of valid Certificate Authority certificate secrets\nthat apply to the associated S3 bucket.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3StoresCustomCertificateSecretRefs"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "irsaEnabled" = mkOption {
          description = "This is only set to \"true\" when a user is running in EKS and is using AWS IRSA to configure\nS3 snapshot store. For more details refer this: https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/";
          type = (types.nullOr types.bool);
        };
        "mongodbResourceRef" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3StoresMongodbResourceRef")
          );
        };
        "mongodbUserRef" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3StoresMongodbUserRef")
          );
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "pathStyleAccessEnabled" = mkOption {
          description = "";
          type = types.bool;
        };
        "s3BucketEndpoint" = mkOption {
          description = "";
          type = types.str;
        };
        "s3BucketName" = mkOption {
          description = "";
          type = types.str;
        };
        "s3RegionOverride" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "s3SecretRef" = mkOption {
          description = "S3SecretRef is the secret that contains the AWS credentials used to access S3\nIt is optional because the credentials can be provided via AWS IRSA";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3StoresS3SecretRef"));
        };
      };

      config = {
        "assignmentLabels" = mkOverride 1002 null;
        "customCertificate" = mkOverride 1002 null;
        "customCertificateSecretRefs" = mkOverride 1002 null;
        "irsaEnabled" = mkOverride 1002 null;
        "mongodbResourceRef" = mkOverride 1002 null;
        "mongodbUserRef" = mkOverride 1002 null;
        "s3RegionOverride" = mkOverride 1002 null;
        "s3SecretRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3StoresCustomCertificateSecretRefs" = {

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
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3StoresMongodbResourceRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "namespace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3StoresMongodbUserRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupS3StoresS3SecretRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupStatefulSet" = {

      options = {
        "metadata" = mkOption {
          description = "StatefulSetMetadataWrapper is a wrapper around Labels and Annotations";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecBackupStatefulSetMetadata"));
        };
        "spec" = mkOption {
          description = "";
          type = types.attrs;
        };
      };

      config = {
        "metadata" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecBackupStatefulSetMetadata" = {

      options = {
        "annotations" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "labels" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecClusterSpecList" = {

      options = {
        "backup" = mkOption {
          description = "Backup contains settings to override from top-level `spec.backup` for this member cluster.\nIf the value is not set here, then the value is taken from `spec.backup`.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecClusterSpecListBackup"));
        };
        "clusterDomain" = mkOption {
          description = "Cluster domain to override the default *.svc.cluster.local if the default cluster domain has been changed on a cluster level.";
          type = (types.nullOr types.str);
        };
        "clusterName" = mkOption {
          description = "ClusterName is name of the cluster where the Ops Manager Statefulset will be scheduled.\nThe operator is using ClusterName to find API credentials in `mongodb-kubernetes-operator-member-list` config map to use for this member cluster.\nIf the credentials are not found, then the member cluster is considered unreachable and ignored in the reconcile process.";
          type = types.str;
        };
        "configuration" = mkOption {
          description = "The configuration properties passed to Ops Manager and Backup Daemon in this cluster.\nIf specified (not empty) then this field overrides `spec.configuration` field entirely.\nIf not specified, then `spec.configuration` field is used for the Ops Manager and Backup Daemon instances in this cluster.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "externalConnectivity" = mkOption {
          description = "MongoDBOpsManagerExternalConnectivity if sets allows for the creation of a Service for\naccessing Ops Manager instances in this member cluster from outside the Kubernetes cluster.\nIf specified (even if provided empty) then this field overrides `spec.externalConnectivity` field entirely.\nIf not specified, then `spec.externalConnectivity` field is used for the Ops Manager and Backup Daemon instances in this cluster.";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecClusterSpecListExternalConnectivity")
          );
        };
        "jvmParameters" = mkOption {
          description = "JVM parameters to pass to Ops Manager and Backup Daemon instances in this member cluster.\nIf specified (not empty) then this field overrides `spec.jvmParameters` field entirely.\nIf not specified, then `spec.jvmParameters` field is used for the Ops Manager and Backup Daemon instances in this cluster.";
          type = (types.nullOr (types.listOf types.str));
        };
        "members" = mkOption {
          description = "Number of Ops Manager instances in this member cluster.";
          type = types.int;
        };
        "statefulSet" = mkOption {
          description = "Configure custom StatefulSet configuration to override in Ops Manager's statefulset in this member cluster.\nIf specified (even if provided empty) then this field overrides `spec.externalConnectivity` field entirely.\nIf not specified, then `spec.externalConnectivity` field is used for the Ops Manager and Backup Daemon instances in this cluster.";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecClusterSpecListStatefulSet")
          );
        };
      };

      config = {
        "backup" = mkOverride 1002 null;
        "clusterDomain" = mkOverride 1002 null;
        "configuration" = mkOverride 1002 null;
        "externalConnectivity" = mkOverride 1002 null;
        "jvmParameters" = mkOverride 1002 null;
        "statefulSet" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecClusterSpecListBackup" = {

      options = {
        "assignmentLabels" = mkOption {
          description = "Assignment Labels set in the Ops Manager";
          type = (types.nullOr (types.listOf types.str));
        };
        "headDB" = mkOption {
          description = "HeadDB specifies configuration options for the HeadDB";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecClusterSpecListBackupHeadDB")
          );
        };
        "jvmParameters" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "members" = mkOption {
          description = "Members indicate the number of backup daemon pods to create.";
          type = types.int;
        };
        "statefulSet" = mkOption {
          description = "StatefulSetConfiguration specified optional overrides for backup datemon statefulset.";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecClusterSpecListBackupStatefulSet")
          );
        };
      };

      config = {
        "assignmentLabels" = mkOverride 1002 null;
        "headDB" = mkOverride 1002 null;
        "jvmParameters" = mkOverride 1002 null;
        "statefulSet" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecClusterSpecListBackupHeadDB" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecClusterSpecListBackupStatefulSet" = {

      options = {
        "metadata" = mkOption {
          description = "StatefulSetMetadataWrapper is a wrapper around Labels and Annotations";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecClusterSpecListBackupStatefulSetMetadata"
            )
          );
        };
        "spec" = mkOption {
          description = "";
          type = types.attrs;
        };
      };

      config = {
        "metadata" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecClusterSpecListBackupStatefulSetMetadata" = {

      options = {
        "annotations" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "labels" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecClusterSpecListExternalConnectivity" = {

      options = {
        "annotations" = mkOption {
          description = "Annotations is a list of annotations to be directly passed to the Service object.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "clusterIP" = mkOption {
          description = "ClusterIP IP that will be assigned to this Service when creating a ClusterIP type Service";
          type = (types.nullOr types.str);
        };
        "externalTrafficPolicy" = mkOption {
          description = "ExternalTrafficPolicy mechanism to preserve the client source IP.\nOnly supported on GCE and Google Kubernetes Engine.";
          type = (types.nullOr types.str);
        };
        "loadBalancerIP" = mkOption {
          description = "LoadBalancerIP IP that will be assigned to this LoadBalancer.";
          type = (types.nullOr types.str);
        };
        "port" = mkOption {
          description = "Port in which this `Service` will listen to, this applies to `NodePort`.";
          type = (types.nullOr types.int);
        };
        "type" = mkOption {
          description = "Type of the `Service` to be created.";
          type = types.str;
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "clusterIP" = mkOverride 1002 null;
        "externalTrafficPolicy" = mkOverride 1002 null;
        "loadBalancerIP" = mkOverride 1002 null;
        "port" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecClusterSpecListStatefulSet" = {

      options = {
        "metadata" = mkOption {
          description = "StatefulSetMetadataWrapper is a wrapper around Labels and Annotations";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecClusterSpecListStatefulSetMetadata")
          );
        };
        "spec" = mkOption {
          description = "";
          type = types.attrs;
        };
      };

      config = {
        "metadata" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecClusterSpecListStatefulSetMetadata" = {

      options = {
        "annotations" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "labels" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecExternalConnectivity" = {

      options = {
        "annotations" = mkOption {
          description = "Annotations is a list of annotations to be directly passed to the Service object.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "clusterIP" = mkOption {
          description = "ClusterIP IP that will be assigned to this Service when creating a ClusterIP type Service";
          type = (types.nullOr types.str);
        };
        "externalTrafficPolicy" = mkOption {
          description = "ExternalTrafficPolicy mechanism to preserve the client source IP.\nOnly supported on GCE and Google Kubernetes Engine.";
          type = (types.nullOr types.str);
        };
        "loadBalancerIP" = mkOption {
          description = "LoadBalancerIP IP that will be assigned to this LoadBalancer.";
          type = (types.nullOr types.str);
        };
        "port" = mkOption {
          description = "Port in which this `Service` will listen to, this applies to `NodePort`.";
          type = (types.nullOr types.int);
        };
        "type" = mkOption {
          description = "Type of the `Service` to be created.";
          type = types.str;
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "clusterIP" = mkOverride 1002 null;
        "externalTrafficPolicy" = mkOverride 1002 null;
        "loadBalancerIP" = mkOverride 1002 null;
        "port" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecInternalConnectivity" = {

      options = {
        "annotations" = mkOption {
          description = "Annotations is a list of annotations to be directly passed to the Service object.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "clusterIP" = mkOption {
          description = "ClusterIP IP that will be assigned to this Service when creating a ClusterIP type Service";
          type = (types.nullOr types.str);
        };
        "externalTrafficPolicy" = mkOption {
          description = "ExternalTrafficPolicy mechanism to preserve the client source IP.\nOnly supported on GCE and Google Kubernetes Engine.";
          type = (types.nullOr types.str);
        };
        "loadBalancerIP" = mkOption {
          description = "LoadBalancerIP IP that will be assigned to this LoadBalancer.";
          type = (types.nullOr types.str);
        };
        "port" = mkOption {
          description = "Port in which this `Service` will listen to, this applies to `NodePort`.";
          type = (types.nullOr types.int);
        };
        "type" = mkOption {
          description = "Type of the `Service` to be created.";
          type = types.str;
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "clusterIP" = mkOverride 1002 null;
        "externalTrafficPolicy" = mkOverride 1002 null;
        "loadBalancerIP" = mkOverride 1002 null;
        "port" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecLogging" = {

      options = {
        "LogBackAccessRef" = mkOption {
          description = "LogBackAccessRef points at a ConfigMap/key with the logback access configuration file to mount on the Pod";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecLoggingLogBackAccessRef"));
        };
        "LogBackRef" = mkOption {
          description = "LogBackRef points at a ConfigMap/key with the logback configuration file to mount on the Pod";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecLoggingLogBackRef"));
        };
      };

      config = {
        "LogBackAccessRef" = mkOverride 1002 null;
        "LogBackRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecLoggingLogBackAccessRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecLoggingLogBackRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecSecurity" = {

      options = {
        "certsSecretPrefix" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "tls" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecSecurityTls"));
        };
      };

      config = {
        "certsSecretPrefix" = mkOverride 1002 null;
        "tls" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecSecurityTls" = {

      options = {
        "ca" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "secretRef" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecSecurityTlsSecretRef"));
        };
      };

      config = {
        "ca" = mkOverride 1002 null;
        "secretRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecSecurityTlsSecretRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecStatefulSet" = {

      options = {
        "metadata" = mkOption {
          description = "StatefulSetMetadataWrapper is a wrapper around Labels and Annotations";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerSpecStatefulSetMetadata"));
        };
        "spec" = mkOption {
          description = "";
          type = types.attrs;
        };
      };

      config = {
        "metadata" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerSpecStatefulSetMetadata" = {

      options = {
        "annotations" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "labels" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerStatus" = {

      options = {
        "applicationDatabase" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerStatusApplicationDatabase"));
        };
        "backup" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerStatusBackup"));
        };
        "opsManager" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerStatusOpsManager"));
        };
      };

      config = {
        "applicationDatabase" = mkOverride 1002 null;
        "backup" = mkOverride 1002 null;
        "opsManager" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerStatusApplicationDatabase" = {

      options = {
        "backup" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBOpsManagerStatusApplicationDatabaseBackup")
          );
        };
        "clusterStatusList" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "mongodb.com.v1.MongoDBOpsManagerStatusApplicationDatabaseClusterStatusList"
              )
            )
          );
        };
        "configServerCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "featureCompatibilityVersion" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "lastTransition" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "link" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "members" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "mongodsPerShardCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "mongosCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "observedGeneration" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "phase" = mkOption {
          description = "";
          type = types.str;
        };
        "pvc" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.MongoDBOpsManagerStatusApplicationDatabasePvc")
            )
          );
        };
        "resourcesNotReady" = mkOption {
          description = "";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "mongodb.com.v1.MongoDBOpsManagerStatusApplicationDatabaseResourcesNotReady"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "shardCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "sizeStatusInClusters" = mkOption {
          description = "MongodbShardedSizeStatusInClusters describes the number and sizes of replica sets members deployed across member clusters";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBOpsManagerStatusApplicationDatabaseSizeStatusInClusters"
            )
          );
        };
        "version" = mkOption {
          description = "";
          type = types.str;
        };
        "warnings" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "backup" = mkOverride 1002 null;
        "clusterStatusList" = mkOverride 1002 null;
        "configServerCount" = mkOverride 1002 null;
        "featureCompatibilityVersion" = mkOverride 1002 null;
        "lastTransition" = mkOverride 1002 null;
        "link" = mkOverride 1002 null;
        "members" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "mongodsPerShardCount" = mkOverride 1002 null;
        "mongosCount" = mkOverride 1002 null;
        "observedGeneration" = mkOverride 1002 null;
        "pvc" = mkOverride 1002 null;
        "resourcesNotReady" = mkOverride 1002 null;
        "shardCount" = mkOverride 1002 null;
        "sizeStatusInClusters" = mkOverride 1002 null;
        "warnings" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerStatusApplicationDatabaseBackup" = {

      options = {
        "statusName" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerStatusApplicationDatabaseClusterStatusList" = {

      options = {
        "clusterName" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "members" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "clusterName" = mkOverride 1002 null;
        "members" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerStatusApplicationDatabasePvc" = {

      options = {
        "phase" = mkOption {
          description = "";
          type = types.str;
        };
        "statefulsetName" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerStatusApplicationDatabaseResourcesNotReady" = {

      options = {
        "errors" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "mongodb.com.v1.MongoDBOpsManagerStatusApplicationDatabaseResourcesNotReadyErrors"
              )
            )
          );
        };
        "kind" = mkOption {
          description = "ResourceKind specifies a kind of a Kubernetes resource. Used in status of a Custom Resource";
          type = types.str;
        };
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "errors" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerStatusApplicationDatabaseResourcesNotReadyErrors" = {

      options = {
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "reason" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "message" = mkOverride 1002 null;
        "reason" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerStatusApplicationDatabaseSizeStatusInClusters" = {

      options = {
        "configServerMongodsInClusters" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.int));
        };
        "mongosCountInClusters" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.int));
        };
        "shardMongodsInClusters" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.int));
        };
        "shardOverridesInClusters" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
      };

      config = {
        "configServerMongodsInClusters" = mkOverride 1002 null;
        "mongosCountInClusters" = mkOverride 1002 null;
        "shardMongodsInClusters" = mkOverride 1002 null;
        "shardOverridesInClusters" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerStatusBackup" = {

      options = {
        "clusterStatusList" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.MongoDBOpsManagerStatusBackupClusterStatusList")
            )
          );
        };
        "lastTransition" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "observedGeneration" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "phase" = mkOption {
          description = "";
          type = types.str;
        };
        "pvc" = mkOption {
          description = "";
          type = (
            types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBOpsManagerStatusBackupPvc"))
          );
        };
        "resourcesNotReady" = mkOption {
          description = "";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "mongodb.com.v1.MongoDBOpsManagerStatusBackupResourcesNotReady"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "version" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "warnings" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "clusterStatusList" = mkOverride 1002 null;
        "lastTransition" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "observedGeneration" = mkOverride 1002 null;
        "pvc" = mkOverride 1002 null;
        "resourcesNotReady" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
        "warnings" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerStatusBackupClusterStatusList" = {

      options = {
        "clusterName" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "replicas" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "clusterName" = mkOverride 1002 null;
        "replicas" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerStatusBackupPvc" = {

      options = {
        "phase" = mkOption {
          description = "";
          type = types.str;
        };
        "statefulsetName" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerStatusBackupResourcesNotReady" = {

      options = {
        "errors" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.MongoDBOpsManagerStatusBackupResourcesNotReadyErrors")
            )
          );
        };
        "kind" = mkOption {
          description = "ResourceKind specifies a kind of a Kubernetes resource. Used in status of a Custom Resource";
          type = types.str;
        };
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "errors" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerStatusBackupResourcesNotReadyErrors" = {

      options = {
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "reason" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "message" = mkOverride 1002 null;
        "reason" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerStatusOpsManager" = {

      options = {
        "clusterStatusList" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.MongoDBOpsManagerStatusOpsManagerClusterStatusList")
            )
          );
        };
        "lastTransition" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "observedGeneration" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "phase" = mkOption {
          description = "";
          type = types.str;
        };
        "pvc" = mkOption {
          description = "";
          type = (
            types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBOpsManagerStatusOpsManagerPvc"))
          );
        };
        "replicas" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "resourcesNotReady" = mkOption {
          description = "";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "mongodb.com.v1.MongoDBOpsManagerStatusOpsManagerResourcesNotReady"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "url" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "version" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "warnings" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "clusterStatusList" = mkOverride 1002 null;
        "lastTransition" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "observedGeneration" = mkOverride 1002 null;
        "pvc" = mkOverride 1002 null;
        "replicas" = mkOverride 1002 null;
        "resourcesNotReady" = mkOverride 1002 null;
        "url" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
        "warnings" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerStatusOpsManagerClusterStatusList" = {

      options = {
        "clusterName" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "replicas" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "clusterName" = mkOverride 1002 null;
        "replicas" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerStatusOpsManagerPvc" = {

      options = {
        "phase" = mkOption {
          description = "";
          type = types.str;
        };
        "statefulsetName" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBOpsManagerStatusOpsManagerResourcesNotReady" = {

      options = {
        "errors" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.MongoDBOpsManagerStatusOpsManagerResourcesNotReadyErrors")
            )
          );
        };
        "kind" = mkOption {
          description = "ResourceKind specifies a kind of a Kubernetes resource. Used in status of a Custom Resource";
          type = types.str;
        };
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "errors" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBOpsManagerStatusOpsManagerResourcesNotReadyErrors" = {

      options = {
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "reason" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "message" = mkOverride 1002 null;
        "reason" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearch" = {

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
          description = "";
          type = (submoduleOf "mongodb.com.v1.MongoDBSearchSpec");
        };
        "status" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchStatus"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchSpec" = {

      options = {
        "logLevel" = mkOption {
          description = "Configure verbosity of mongot logs. Defaults to INFO if not set.";
          type = (types.nullOr types.str);
        };
        "persistence" = mkOption {
          description = "Configure MongoDB Search's persistent volume. If not defined, the operator will request 10GB of storage.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchSpecPersistence"));
        };
        "prometheus" = mkOption {
          description = "Configure prometheus metrics endpoint in mongot. If not set, the metrics endpoint will be disabled.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchSpecPrometheus"));
        };
        "resourceRequirements" = mkOption {
          description = "Configure resource requests and limits for the MongoDB Search pods.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchSpecResourceRequirements"));
        };
        "security" = mkOption {
          description = "Configure security settings of the MongoDB Search server that MongoDB database is connecting to when performing search queries.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchSpecSecurity"));
        };
        "source" = mkOption {
          description = "MongoDB database connection details from which MongoDB Search will synchronize data to build indexes.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchSpecSource"));
        };
        "statefulSet" = mkOption {
          description = "StatefulSetSpec which the operator will apply to the MongoDB Search StatefulSet at the end of the reconcile loop. Use to provide necessary customizations,\nwhich aren't exposed as fields in the MongoDBSearch.spec.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchSpecStatefulSet"));
        };
        "version" = mkOption {
          description = "Optional version of MongoDB Search component (mongot). If not set, then the operator will set the most appropriate version of MongoDB Search.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "logLevel" = mkOverride 1002 null;
        "persistence" = mkOverride 1002 null;
        "prometheus" = mkOverride 1002 null;
        "resourceRequirements" = mkOverride 1002 null;
        "security" = mkOverride 1002 null;
        "source" = mkOverride 1002 null;
        "statefulSet" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchSpecPersistence" = {

      options = {
        "multiple" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchSpecPersistenceMultiple"));
        };
        "single" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchSpecPersistenceSingle"));
        };
      };

      config = {
        "multiple" = mkOverride 1002 null;
        "single" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchSpecPersistenceMultiple" = {

      options = {
        "data" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchSpecPersistenceMultipleData"));
        };
        "journal" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchSpecPersistenceMultipleJournal"));
        };
        "logs" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchSpecPersistenceMultipleLogs"));
        };
      };

      config = {
        "data" = mkOverride 1002 null;
        "journal" = mkOverride 1002 null;
        "logs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchSpecPersistenceMultipleData" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchSpecPersistenceMultipleJournal" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchSpecPersistenceMultipleLogs" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchSpecPersistenceSingle" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchSpecPrometheus" = {

      options = {
        "port" = mkOption {
          description = "Port where metrics endpoint will be exposed on. Defaults to 9946.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "port" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchSpecResourceRequirements" = {

      options = {
        "claims" = mkOption {
          description = "Claims lists the names of resources, defined in spec.resourceClaims,\nthat are used by this container.\n\nThis is an alpha field and requires enabling the\nDynamicResourceAllocation feature gate.\n\nThis field is immutable. It can only be set for containers.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "mongodb.com.v1.MongoDBSearchSpecResourceRequirementsClaims"
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
    "mongodb.com.v1.MongoDBSearchSpecResourceRequirementsClaims" = {

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
    "mongodb.com.v1.MongoDBSearchSpecSecurity" = {

      options = {
        "tls" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchSpecSecurityTls"));
        };
      };

      config = {
        "tls" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchSpecSecurityTls" = {

      options = {
        "certificateKeySecretRef" = mkOption {
          description = "CertificateKeySecret is a reference to a Secret containing a private key and certificate to use for TLS.\nThe key and cert are expected to be PEM encoded and available at \"tls.key\" and \"tls.crt\".\nThis is the same format used for the standard \"kubernetes.io/tls\" Secret type, but no specific type is required.";
          type = (submoduleOf "mongodb.com.v1.MongoDBSearchSpecSecurityTlsCertificateKeySecretRef");
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBSearchSpecSecurityTlsCertificateKeySecretRef" = {

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
    "mongodb.com.v1.MongoDBSearchSpecSource" = {

      options = {
        "external" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchSpecSourceExternal"));
        };
        "mongodbResourceRef" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchSpecSourceMongodbResourceRef"));
        };
        "passwordSecretRef" = mkOption {
          description = "SecretKeyRef is a reference to a value in a given secret in the same\nnamespace. Based on:\nhttps://kubernetes.io/docs/reference/generated/kubernetes-api/v1.15/#secretkeyselector-v1-core";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchSpecSourcePasswordSecretRef"));
        };
        "username" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "external" = mkOverride 1002 null;
        "mongodbResourceRef" = mkOverride 1002 null;
        "passwordSecretRef" = mkOverride 1002 null;
        "username" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchSpecSourceExternal" = {

      options = {
        "hostAndPorts" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "keyfileSecretRef" = mkOption {
          description = "mongod keyfile used to connect to the external MongoDB deployment";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchSpecSourceExternalKeyfileSecretRef")
          );
        };
        "tls" = mkOption {
          description = "TLS configuration for the external MongoDB deployment";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchSpecSourceExternalTls"));
        };
      };

      config = {
        "hostAndPorts" = mkOverride 1002 null;
        "keyfileSecretRef" = mkOverride 1002 null;
        "tls" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchSpecSourceExternalKeyfileSecretRef" = {

      options = {
        "key" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "key" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchSpecSourceExternalTls" = {

      options = {
        "ca" = mkOption {
          description = "CA is a reference to a Secret containing the CA certificate that issued mongod's TLS certificate.\nThe CA certificate is expected to be PEM encoded and available at the \"ca.crt\" key.";
          type = (submoduleOf "mongodb.com.v1.MongoDBSearchSpecSourceExternalTlsCa");
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBSearchSpecSourceExternalTlsCa" = {

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
    "mongodb.com.v1.MongoDBSearchSpecSourceMongodbResourceRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "namespace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchSpecSourcePasswordSecretRef" = {

      options = {
        "key" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "key" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchSpecStatefulSet" = {

      options = {
        "metadata" = mkOption {
          description = "StatefulSetMetadataWrapper is a wrapper around Labels and Annotations";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSearchSpecStatefulSetMetadata"));
        };
        "spec" = mkOption {
          description = "";
          type = types.attrs;
        };
      };

      config = {
        "metadata" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchSpecStatefulSetMetadata" = {

      options = {
        "annotations" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "labels" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchStatus" = {

      options = {
        "lastTransition" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "observedGeneration" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "phase" = mkOption {
          description = "";
          type = types.str;
        };
        "pvc" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBSearchStatusPvc")));
        };
        "resourcesNotReady" = mkOption {
          description = "";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "mongodb.com.v1.MongoDBSearchStatusResourcesNotReady" "name" [ ]
            )
          );
          apply = attrsToList;
        };
        "version" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "warnings" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "lastTransition" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "observedGeneration" = mkOverride 1002 null;
        "pvc" = mkOverride 1002 null;
        "resourcesNotReady" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
        "warnings" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchStatusPvc" = {

      options = {
        "phase" = mkOption {
          description = "";
          type = types.str;
        };
        "statefulsetName" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBSearchStatusResourcesNotReady" = {

      options = {
        "errors" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.MongoDBSearchStatusResourcesNotReadyErrors")
            )
          );
        };
        "kind" = mkOption {
          description = "ResourceKind specifies a kind of a Kubernetes resource. Used in status of a Custom Resource";
          type = types.str;
        };
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "errors" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSearchStatusResourcesNotReadyErrors" = {

      options = {
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "reason" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "message" = mkOverride 1002 null;
        "reason" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpec" = {

      options = {
        "additionalMongodConfig" = mkOption {
          description = "AdditionalMongodConfig is additional configuration that can be passed to\neach data-bearing mongod at runtime. Uses the same structure as the mongod\nconfiguration file:\nhttps://docs.mongodb.com/manual/reference/configuration-options/";
          type = (types.nullOr types.attrs);
        };
        "agent" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecAgent"));
        };
        "backup" = mkOption {
          description = "Backup contains configuration options for configuring\nbackup for this MongoDB resource";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecBackup"));
        };
        "cloudManager" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecCloudManager"));
        };
        "clusterDomain" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "configServerCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "configSrv" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrv"));
        };
        "configSrvPodSpec" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvPodSpec"));
        };
        "connectivity" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConnectivity"));
        };
        "credentials" = mkOption {
          description = "Name of the Secret holding credentials information";
          type = types.str;
        };
        "duplicateServiceObjects" = mkOption {
          description = "In few service mesh options for ex: Istio, by default we would need to duplicate the\nservice objects created per pod in all the clusters to enable DNS resolution. Users can\nhowever configure their ServiceMesh with DNS proxy(https://istio.io/latest/docs/ops/configuration/traffic-management/dns-proxy/)\nenabled in which case the operator doesn't need to create the service objects per cluster. This options tells the operator\nwhether it should create the service objects in all the clusters or not. By default, if not specified the operator would create the duplicate svc objects.";
          type = (types.nullOr types.bool);
        };
        "externalAccess" = mkOption {
          description = "ExternalAccessConfiguration provides external access configuration.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecExternalAccess"));
        };
        "featureCompatibilityVersion" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "logLevel" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "memberConfig" = mkOption {
          description = "MemberConfig allows to specify votes, priorities and tags for each of the mongodb process.";
          type = (types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBSpecMemberConfig")));
        };
        "members" = mkOption {
          description = "Amount of members for this MongoDB Replica Set";
          type = (types.nullOr types.int);
        };
        "mongodsPerShardCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "mongos" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongos"));
        };
        "mongosCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "mongosPodSpec" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosPodSpec"));
        };
        "opsManager" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecOpsManager"));
        };
        "persistent" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "podSpec" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecPodSpec"));
        };
        "prometheus" = mkOption {
          description = "Prometheus configurations.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecPrometheus"));
        };
        "security" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecSecurity"));
        };
        "service" = mkOption {
          description = "DEPRECATED please use `spec.statefulSet.spec.serviceName` to provide a custom service name.\nthis is an optional service, it will get the name \"<rsName>-service\" in case not provided";
          type = (types.nullOr types.str);
        };
        "shard" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShard"));
        };
        "shardCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "shardOverrides" = mkOption {
          description = "ShardOverrides allow for overriding the configuration of a specific shard.\nIt replaces deprecated spec.shard.shardSpecificPodSpec field. When spec.shard.shardSpecificPodSpec is still defined then\nspec.shard.shardSpecificPodSpec is applied first to the particular shard and then spec.shardOverrides is applied on top\nof that (if defined for the same shard).";
          type = (types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverrides")));
        };
        "shardPodSpec" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardPodSpec"));
        };
        "shardSpecificPodSpec" = mkOption {
          description = "ShardSpecificPodSpec allows you to provide a Statefulset override per shard.\nDEPRECATED please use spec.shard.shardOverrides instead";
          type = (types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBSpecShardSpecificPodSpec")));
        };
        "statefulSet" = mkOption {
          description = "StatefulSetConfiguration provides the statefulset override for each of the cluster's statefulset\nif \"StatefulSetConfiguration\" is specified at cluster level under \"clusterSpecList\" that takes precedence over\nthe global one";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecStatefulSet"));
        };
        "topology" = mkOption {
          description = "Topology sets the desired cluster topology of MongoDB resources\nIt defaults (if empty or not set) to SingleCluster. If MultiCluster specified,\nthen clusterSpecList field is mandatory and at least one member cluster has to be specified.";
          type = (types.nullOr types.str);
        };
        "type" = mkOption {
          description = "";
          type = types.str;
        };
        "version" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "additionalMongodConfig" = mkOverride 1002 null;
        "agent" = mkOverride 1002 null;
        "backup" = mkOverride 1002 null;
        "cloudManager" = mkOverride 1002 null;
        "clusterDomain" = mkOverride 1002 null;
        "configServerCount" = mkOverride 1002 null;
        "configSrv" = mkOverride 1002 null;
        "configSrvPodSpec" = mkOverride 1002 null;
        "connectivity" = mkOverride 1002 null;
        "duplicateServiceObjects" = mkOverride 1002 null;
        "externalAccess" = mkOverride 1002 null;
        "featureCompatibilityVersion" = mkOverride 1002 null;
        "logLevel" = mkOverride 1002 null;
        "memberConfig" = mkOverride 1002 null;
        "members" = mkOverride 1002 null;
        "mongodsPerShardCount" = mkOverride 1002 null;
        "mongos" = mkOverride 1002 null;
        "mongosCount" = mkOverride 1002 null;
        "mongosPodSpec" = mkOverride 1002 null;
        "opsManager" = mkOverride 1002 null;
        "persistent" = mkOverride 1002 null;
        "podSpec" = mkOverride 1002 null;
        "prometheus" = mkOverride 1002 null;
        "security" = mkOverride 1002 null;
        "service" = mkOverride 1002 null;
        "shard" = mkOverride 1002 null;
        "shardCount" = mkOverride 1002 null;
        "shardOverrides" = mkOverride 1002 null;
        "shardPodSpec" = mkOverride 1002 null;
        "shardSpecificPodSpec" = mkOverride 1002 null;
        "statefulSet" = mkOverride 1002 null;
        "topology" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecAgent" = {

      options = {
        "backupAgent" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecAgentBackupAgent"));
        };
        "logLevel" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "logRotate" = mkOption {
          description = "DEPRECATED please use mongod.logRotate";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecAgentLogRotate"));
        };
        "maxLogFileDurationHours" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "mongod" = mkOption {
          description = "AgentLoggingMongodConfig contain settings for the mongodb processes configured by the agent";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecAgentMongod"));
        };
        "monitoringAgent" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecAgentMonitoringAgent"));
        };
        "readinessProbe" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecAgentReadinessProbe"));
        };
        "startupOptions" = mkOption {
          description = "StartupParameters can be used to configure the startup parameters with which the agent starts. That also contains\nlog rotation settings as defined here:";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "systemLog" = mkOption {
          description = "DEPRECATED please use mongod.systemLog";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecAgentSystemLog"));
        };
      };

      config = {
        "backupAgent" = mkOverride 1002 null;
        "logLevel" = mkOverride 1002 null;
        "logRotate" = mkOverride 1002 null;
        "maxLogFileDurationHours" = mkOverride 1002 null;
        "mongod" = mkOverride 1002 null;
        "monitoringAgent" = mkOverride 1002 null;
        "readinessProbe" = mkOverride 1002 null;
        "startupOptions" = mkOverride 1002 null;
        "systemLog" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecAgentBackupAgent" = {

      options = {
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the BackupAgent processes";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecAgentBackupAgentLogRotate"));
        };
      };

      config = {
        "logRotate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecAgentBackupAgentLogRotate" = {

      options = {
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nOM only supports ints";
          type = (types.nullOr types.int);
        };
        "timeThresholdHrs" = mkOption {
          description = "Number of hours after which this MongoDB Agent rotates the log file.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "sizeThresholdMB" = mkOverride 1002 null;
        "timeThresholdHrs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecAgentLogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecAgentMongod" = {

      options = {
        "auditlogRotate" = mkOption {
          description = "LogRotate configures audit log rotation for the mongodb processes";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecAgentMongodAuditlogRotate"));
        };
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the mongodb processes";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecAgentMongodLogRotate"));
        };
        "systemLog" = mkOption {
          description = "SystemLog configures system log of mongod";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecAgentMongodSystemLog"));
        };
      };

      config = {
        "auditlogRotate" = mkOverride 1002 null;
        "logRotate" = mkOverride 1002 null;
        "systemLog" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecAgentMongodAuditlogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecAgentMongodLogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecAgentMongodSystemLog" = {

      options = {
        "destination" = mkOption {
          description = "";
          type = types.str;
        };
        "logAppend" = mkOption {
          description = "";
          type = types.bool;
        };
        "path" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBSpecAgentMonitoringAgent" = {

      options = {
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the BackupAgent processes";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecAgentMonitoringAgentLogRotate"));
        };
      };

      config = {
        "logRotate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecAgentMonitoringAgentLogRotate" = {

      options = {
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nOM only supports ints";
          type = (types.nullOr types.int);
        };
        "timeThresholdHrs" = mkOption {
          description = "Number of hours after which this MongoDB Agent rotates the log file.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "sizeThresholdMB" = mkOverride 1002 null;
        "timeThresholdHrs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecAgentReadinessProbe" = {

      options = {
        "environmentVariables" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "environmentVariables" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecAgentSystemLog" = {

      options = {
        "destination" = mkOption {
          description = "";
          type = types.str;
        };
        "logAppend" = mkOption {
          description = "";
          type = types.bool;
        };
        "path" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBSpecBackup" = {

      options = {
        "assignmentLabels" = mkOption {
          description = "Assignment Labels set in the Ops Manager";
          type = (types.nullOr (types.listOf types.str));
        };
        "autoTerminateOnDeletion" = mkOption {
          description = "AutoTerminateOnDeletion indicates if the Operator should stop and terminate the Backup before the cleanup,\nwhen the MongoDB CR is deleted";
          type = (types.nullOr types.bool);
        };
        "encryption" = mkOption {
          description = "Encryption settings";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecBackupEncryption"));
        };
        "mode" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "snapshotSchedule" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecBackupSnapshotSchedule"));
        };
      };

      config = {
        "assignmentLabels" = mkOverride 1002 null;
        "autoTerminateOnDeletion" = mkOverride 1002 null;
        "encryption" = mkOverride 1002 null;
        "mode" = mkOverride 1002 null;
        "snapshotSchedule" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecBackupEncryption" = {

      options = {
        "kmip" = mkOption {
          description = "Kmip corresponds to the KMIP configuration assigned to the Ops Manager Project's configuration.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecBackupEncryptionKmip"));
        };
      };

      config = {
        "kmip" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecBackupEncryptionKmip" = {

      options = {
        "client" = mkOption {
          description = "KMIP Client configuration";
          type = (submoduleOf "mongodb.com.v1.MongoDBSpecBackupEncryptionKmipClient");
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBSpecBackupEncryptionKmipClient" = {

      options = {
        "clientCertificatePrefix" = mkOption {
          description = "A prefix used to construct KMIP client certificate (and corresponding password) Secret names.\nThe names are generated using the following pattern:\nKMIP Client Certificate (TLS Secret):\n  <clientCertificatePrefix>-<CR Name>-kmip-client\nKMIP Client Certificate Password:\n  <clientCertificatePrefix>-<CR Name>-kmip-client-password\n  The expected key inside is called \"password\".";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "clientCertificatePrefix" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecBackupSnapshotSchedule" = {

      options = {
        "clusterCheckpointIntervalMin" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "dailySnapshotRetentionDays" = mkOption {
          description = "Number of days to retain daily snapshots. Setting 0 will disable this rule.";
          type = (types.nullOr types.int);
        };
        "fullIncrementalDayOfWeek" = mkOption {
          description = "Day of the week when Ops Manager takes a full snapshot. This ensures a recent complete backup. Ops Manager sets the default value to SUNDAY.";
          type = (types.nullOr types.str);
        };
        "monthlySnapshotRetentionMonths" = mkOption {
          description = "Number of months to retain weekly snapshots. Setting 0 will disable this rule.";
          type = (types.nullOr types.int);
        };
        "pointInTimeWindowHours" = mkOption {
          description = "Number of hours in the past for which a point-in-time snapshot can be created.";
          type = (types.nullOr types.int);
        };
        "referenceHourOfDay" = mkOption {
          description = "Hour of the day to schedule snapshots using a 24-hour clock, in UTC.";
          type = (types.nullOr types.int);
        };
        "referenceMinuteOfHour" = mkOption {
          description = "Minute of the hour to schedule snapshots, in UTC.";
          type = (types.nullOr types.int);
        };
        "snapshotIntervalHours" = mkOption {
          description = "Number of hours between snapshots.";
          type = (types.nullOr types.int);
        };
        "snapshotRetentionDays" = mkOption {
          description = "Number of days to keep recent snapshots.";
          type = (types.nullOr types.int);
        };
        "weeklySnapshotRetentionWeeks" = mkOption {
          description = "Number of weeks to retain weekly snapshots. Setting 0 will disable this rule";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "clusterCheckpointIntervalMin" = mkOverride 1002 null;
        "dailySnapshotRetentionDays" = mkOverride 1002 null;
        "fullIncrementalDayOfWeek" = mkOverride 1002 null;
        "monthlySnapshotRetentionMonths" = mkOverride 1002 null;
        "pointInTimeWindowHours" = mkOverride 1002 null;
        "referenceHourOfDay" = mkOverride 1002 null;
        "referenceMinuteOfHour" = mkOverride 1002 null;
        "snapshotIntervalHours" = mkOverride 1002 null;
        "snapshotRetentionDays" = mkOverride 1002 null;
        "weeklySnapshotRetentionWeeks" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecCloudManager" = {

      options = {
        "configMapRef" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecCloudManagerConfigMapRef"));
        };
      };

      config = {
        "configMapRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecCloudManagerConfigMapRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrv" = {

      options = {
        "additionalMongodConfig" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "agent" = mkOption {
          description = "Configuring logRotation is not allowed under this section.\nPlease use the most top level resource fields for this; spec.Agent";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvAgent"));
        };
        "clusterSpecList" = mkOption {
          description = "";
          type = (
            types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecList"))
          );
        };
      };

      config = {
        "additionalMongodConfig" = mkOverride 1002 null;
        "agent" = mkOverride 1002 null;
        "clusterSpecList" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvAgent" = {

      options = {
        "backupAgent" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvAgentBackupAgent"));
        };
        "logLevel" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "logRotate" = mkOption {
          description = "DEPRECATED please use mongod.logRotate";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvAgentLogRotate"));
        };
        "maxLogFileDurationHours" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "mongod" = mkOption {
          description = "AgentLoggingMongodConfig contain settings for the mongodb processes configured by the agent";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvAgentMongod"));
        };
        "monitoringAgent" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvAgentMonitoringAgent"));
        };
        "readinessProbe" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvAgentReadinessProbe"));
        };
        "startupOptions" = mkOption {
          description = "StartupParameters can be used to configure the startup parameters with which the agent starts. That also contains\nlog rotation settings as defined here:";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "systemLog" = mkOption {
          description = "DEPRECATED please use mongod.systemLog";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvAgentSystemLog"));
        };
      };

      config = {
        "backupAgent" = mkOverride 1002 null;
        "logLevel" = mkOverride 1002 null;
        "logRotate" = mkOverride 1002 null;
        "maxLogFileDurationHours" = mkOverride 1002 null;
        "mongod" = mkOverride 1002 null;
        "monitoringAgent" = mkOverride 1002 null;
        "readinessProbe" = mkOverride 1002 null;
        "startupOptions" = mkOverride 1002 null;
        "systemLog" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvAgentBackupAgent" = {

      options = {
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the BackupAgent processes";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvAgentBackupAgentLogRotate"));
        };
      };

      config = {
        "logRotate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvAgentBackupAgentLogRotate" = {

      options = {
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nOM only supports ints";
          type = (types.nullOr types.int);
        };
        "timeThresholdHrs" = mkOption {
          description = "Number of hours after which this MongoDB Agent rotates the log file.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "sizeThresholdMB" = mkOverride 1002 null;
        "timeThresholdHrs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvAgentLogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvAgentMongod" = {

      options = {
        "auditlogRotate" = mkOption {
          description = "LogRotate configures audit log rotation for the mongodb processes";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvAgentMongodAuditlogRotate"));
        };
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the mongodb processes";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvAgentMongodLogRotate"));
        };
        "systemLog" = mkOption {
          description = "SystemLog configures system log of mongod";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvAgentMongodSystemLog"));
        };
      };

      config = {
        "auditlogRotate" = mkOverride 1002 null;
        "logRotate" = mkOverride 1002 null;
        "systemLog" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvAgentMongodAuditlogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvAgentMongodLogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvAgentMongodSystemLog" = {

      options = {
        "destination" = mkOption {
          description = "";
          type = types.str;
        };
        "logAppend" = mkOption {
          description = "";
          type = types.bool;
        };
        "path" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvAgentMonitoringAgent" = {

      options = {
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the BackupAgent processes";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvAgentMonitoringAgentLogRotate")
          );
        };
      };

      config = {
        "logRotate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvAgentMonitoringAgentLogRotate" = {

      options = {
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nOM only supports ints";
          type = (types.nullOr types.int);
        };
        "timeThresholdHrs" = mkOption {
          description = "Number of hours after which this MongoDB Agent rotates the log file.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "sizeThresholdMB" = mkOverride 1002 null;
        "timeThresholdHrs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvAgentReadinessProbe" = {

      options = {
        "environmentVariables" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "environmentVariables" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvAgentSystemLog" = {

      options = {
        "destination" = mkOption {
          description = "";
          type = types.str;
        };
        "logAppend" = mkOption {
          description = "";
          type = types.bool;
        };
        "path" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecList" = {

      options = {
        "clusterName" = mkOption {
          description = "ClusterName is name of the cluster where the MongoDB Statefulset will be scheduled, the\nname should have a one on one mapping with the service-account created in the central cluster\nto talk to the workload clusters.";
          type = (types.nullOr types.str);
        };
        "externalAccess" = mkOption {
          description = "ExternalAccessConfiguration provides external access configuration for Multi-Cluster.";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListExternalAccess")
          );
        };
        "memberConfig" = mkOption {
          description = "MemberConfig allows to specify votes, priorities and tags for each of the mongodb process.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListMemberConfig")
            )
          );
        };
        "members" = mkOption {
          description = "Amount of members for this MongoDB Replica Set";
          type = types.int;
        };
        "podSpec" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListPodSpec"));
        };
        "service" = mkOption {
          description = "this is an optional service, it will get the name \"<rsName>-service\" in case not provided";
          type = (types.nullOr types.str);
        };
        "statefulSet" = mkOption {
          description = "StatefulSetConfiguration holds the optional custom StatefulSet\nthat should be merged into the operator created one.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListStatefulSet"));
        };
      };

      config = {
        "clusterName" = mkOverride 1002 null;
        "externalAccess" = mkOverride 1002 null;
        "memberConfig" = mkOverride 1002 null;
        "podSpec" = mkOverride 1002 null;
        "service" = mkOverride 1002 null;
        "statefulSet" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListExternalAccess" = {

      options = {
        "externalDomain" = mkOption {
          description = "An external domain that is used for exposing MongoDB to the outside world.";
          type = (types.nullOr types.str);
        };
        "externalService" = mkOption {
          description = "Provides a way to override the default (NodePort) Service";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListExternalAccessExternalService"
            )
          );
        };
      };

      config = {
        "externalDomain" = mkOverride 1002 null;
        "externalService" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListExternalAccessExternalService" = {

      options = {
        "annotations" = mkOption {
          description = "A map of annotations that shall be added to the externally available Service.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "spec" = mkOption {
          description = "A wrapper for the Service spec object.";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListMemberConfig" = {

      options = {
        "priority" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "tags" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "votes" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "priority" = mkOverride 1002 null;
        "tags" = mkOverride 1002 null;
        "votes" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListPodSpec" = {

      options = {
        "persistence" = mkOption {
          description = "Note, that this field is used by MongoDB resources only, let's keep it here for simplicity";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListPodSpecPersistence")
          );
        };
        "podTemplate" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "persistence" = mkOverride 1002 null;
        "podTemplate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListPodSpecPersistence" = {

      options = {
        "multiple" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListPodSpecPersistenceMultiple"
            )
          );
        };
        "single" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListPodSpecPersistenceSingle"
            )
          );
        };
      };

      config = {
        "multiple" = mkOverride 1002 null;
        "single" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListPodSpecPersistenceMultiple" = {

      options = {
        "data" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListPodSpecPersistenceMultipleData"
            )
          );
        };
        "journal" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListPodSpecPersistenceMultipleJournal"
            )
          );
        };
        "logs" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListPodSpecPersistenceMultipleLogs"
            )
          );
        };
      };

      config = {
        "data" = mkOverride 1002 null;
        "journal" = mkOverride 1002 null;
        "logs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListPodSpecPersistenceMultipleData" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListPodSpecPersistenceMultipleJournal" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListPodSpecPersistenceMultipleLogs" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListPodSpecPersistenceSingle" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListStatefulSet" = {

      options = {
        "metadata" = mkOption {
          description = "StatefulSetMetadataWrapper is a wrapper around Labels and Annotations";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListStatefulSetMetadata")
          );
        };
        "spec" = mkOption {
          description = "";
          type = types.attrs;
        };
      };

      config = {
        "metadata" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvClusterSpecListStatefulSetMetadata" = {

      options = {
        "annotations" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "labels" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvPodSpec" = {

      options = {
        "persistence" = mkOption {
          description = "Note, that this field is used by MongoDB resources only, let's keep it here for simplicity";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvPodSpecPersistence"));
        };
        "podTemplate" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "persistence" = mkOverride 1002 null;
        "podTemplate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvPodSpecPersistence" = {

      options = {
        "multiple" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvPodSpecPersistenceMultiple"));
        };
        "single" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvPodSpecPersistenceSingle"));
        };
      };

      config = {
        "multiple" = mkOverride 1002 null;
        "single" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvPodSpecPersistenceMultiple" = {

      options = {
        "data" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvPodSpecPersistenceMultipleData")
          );
        };
        "journal" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvPodSpecPersistenceMultipleJournal")
          );
        };
        "logs" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecConfigSrvPodSpecPersistenceMultipleLogs")
          );
        };
      };

      config = {
        "data" = mkOverride 1002 null;
        "journal" = mkOverride 1002 null;
        "logs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvPodSpecPersistenceMultipleData" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvPodSpecPersistenceMultipleJournal" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvPodSpecPersistenceMultipleLogs" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConfigSrvPodSpecPersistenceSingle" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecConnectivity" = {

      options = {
        "replicaSetHorizons" = mkOption {
          description = "ReplicaSetHorizons holds list of maps of horizons to be configured in each of MongoDB processes.\nHorizons map horizon names to the node addresses for each process in the replicaset, e.g.:\n [\n   {\n     \"internal\": \"my-rs-0.my-internal-domain.com:31843\",\n     \"external\": \"my-rs-0.my-external-domain.com:21467\"\n   },\n   {\n     \"internal\": \"my-rs-1.my-internal-domain.com:31843\",\n     \"external\": \"my-rs-1.my-external-domain.com:21467\"\n   },\n   ...\n ]\nThe key of each item in the map is an arbitrary, user-chosen string that\nrepresents the name of the horizon. The value of the item is the host and,\noptionally, the port that this mongod node will be connected to from.";
          type = (types.nullOr (types.listOf types.attrs));
        };
      };

      config = {
        "replicaSetHorizons" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecExternalAccess" = {

      options = {
        "externalDomain" = mkOption {
          description = "An external domain that is used for exposing MongoDB to the outside world.";
          type = (types.nullOr types.str);
        };
        "externalService" = mkOption {
          description = "Provides a way to override the default (NodePort) Service";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecExternalAccessExternalService"));
        };
      };

      config = {
        "externalDomain" = mkOverride 1002 null;
        "externalService" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecExternalAccessExternalService" = {

      options = {
        "annotations" = mkOption {
          description = "A map of annotations that shall be added to the externally available Service.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "spec" = mkOption {
          description = "A wrapper for the Service spec object.";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMemberConfig" = {

      options = {
        "priority" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "tags" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "votes" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "priority" = mkOverride 1002 null;
        "tags" = mkOverride 1002 null;
        "votes" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongos" = {

      options = {
        "additionalMongodConfig" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "agent" = mkOption {
          description = "Configuring logRotation is not allowed under this section.\nPlease use the most top level resource fields for this; spec.Agent";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosAgent"));
        };
        "clusterSpecList" = mkOption {
          description = "";
          type = (
            types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBSpecMongosClusterSpecList"))
          );
        };
      };

      config = {
        "additionalMongodConfig" = mkOverride 1002 null;
        "agent" = mkOverride 1002 null;
        "clusterSpecList" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosAgent" = {

      options = {
        "backupAgent" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosAgentBackupAgent"));
        };
        "logLevel" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "logRotate" = mkOption {
          description = "DEPRECATED please use mongod.logRotate";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosAgentLogRotate"));
        };
        "maxLogFileDurationHours" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "mongod" = mkOption {
          description = "AgentLoggingMongodConfig contain settings for the mongodb processes configured by the agent";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosAgentMongod"));
        };
        "monitoringAgent" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosAgentMonitoringAgent"));
        };
        "readinessProbe" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosAgentReadinessProbe"));
        };
        "startupOptions" = mkOption {
          description = "StartupParameters can be used to configure the startup parameters with which the agent starts. That also contains\nlog rotation settings as defined here:";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "systemLog" = mkOption {
          description = "DEPRECATED please use mongod.systemLog";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosAgentSystemLog"));
        };
      };

      config = {
        "backupAgent" = mkOverride 1002 null;
        "logLevel" = mkOverride 1002 null;
        "logRotate" = mkOverride 1002 null;
        "maxLogFileDurationHours" = mkOverride 1002 null;
        "mongod" = mkOverride 1002 null;
        "monitoringAgent" = mkOverride 1002 null;
        "readinessProbe" = mkOverride 1002 null;
        "startupOptions" = mkOverride 1002 null;
        "systemLog" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosAgentBackupAgent" = {

      options = {
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the BackupAgent processes";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosAgentBackupAgentLogRotate"));
        };
      };

      config = {
        "logRotate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosAgentBackupAgentLogRotate" = {

      options = {
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nOM only supports ints";
          type = (types.nullOr types.int);
        };
        "timeThresholdHrs" = mkOption {
          description = "Number of hours after which this MongoDB Agent rotates the log file.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "sizeThresholdMB" = mkOverride 1002 null;
        "timeThresholdHrs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosAgentLogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosAgentMongod" = {

      options = {
        "auditlogRotate" = mkOption {
          description = "LogRotate configures audit log rotation for the mongodb processes";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosAgentMongodAuditlogRotate"));
        };
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the mongodb processes";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosAgentMongodLogRotate"));
        };
        "systemLog" = mkOption {
          description = "SystemLog configures system log of mongod";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosAgentMongodSystemLog"));
        };
      };

      config = {
        "auditlogRotate" = mkOverride 1002 null;
        "logRotate" = mkOverride 1002 null;
        "systemLog" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosAgentMongodAuditlogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosAgentMongodLogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosAgentMongodSystemLog" = {

      options = {
        "destination" = mkOption {
          description = "";
          type = types.str;
        };
        "logAppend" = mkOption {
          description = "";
          type = types.bool;
        };
        "path" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBSpecMongosAgentMonitoringAgent" = {

      options = {
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the BackupAgent processes";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosAgentMonitoringAgentLogRotate"));
        };
      };

      config = {
        "logRotate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosAgentMonitoringAgentLogRotate" = {

      options = {
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nOM only supports ints";
          type = (types.nullOr types.int);
        };
        "timeThresholdHrs" = mkOption {
          description = "Number of hours after which this MongoDB Agent rotates the log file.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "sizeThresholdMB" = mkOverride 1002 null;
        "timeThresholdHrs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosAgentReadinessProbe" = {

      options = {
        "environmentVariables" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "environmentVariables" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosAgentSystemLog" = {

      options = {
        "destination" = mkOption {
          description = "";
          type = types.str;
        };
        "logAppend" = mkOption {
          description = "";
          type = types.bool;
        };
        "path" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBSpecMongosClusterSpecList" = {

      options = {
        "clusterName" = mkOption {
          description = "ClusterName is name of the cluster where the MongoDB Statefulset will be scheduled, the\nname should have a one on one mapping with the service-account created in the central cluster\nto talk to the workload clusters.";
          type = (types.nullOr types.str);
        };
        "externalAccess" = mkOption {
          description = "ExternalAccessConfiguration provides external access configuration for Multi-Cluster.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosClusterSpecListExternalAccess"));
        };
        "memberConfig" = mkOption {
          description = "MemberConfig allows to specify votes, priorities and tags for each of the mongodb process.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.MongoDBSpecMongosClusterSpecListMemberConfig")
            )
          );
        };
        "members" = mkOption {
          description = "Amount of members for this MongoDB Replica Set";
          type = types.int;
        };
        "podSpec" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosClusterSpecListPodSpec"));
        };
        "service" = mkOption {
          description = "this is an optional service, it will get the name \"<rsName>-service\" in case not provided";
          type = (types.nullOr types.str);
        };
        "statefulSet" = mkOption {
          description = "StatefulSetConfiguration holds the optional custom StatefulSet\nthat should be merged into the operator created one.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosClusterSpecListStatefulSet"));
        };
      };

      config = {
        "clusterName" = mkOverride 1002 null;
        "externalAccess" = mkOverride 1002 null;
        "memberConfig" = mkOverride 1002 null;
        "podSpec" = mkOverride 1002 null;
        "service" = mkOverride 1002 null;
        "statefulSet" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosClusterSpecListExternalAccess" = {

      options = {
        "externalDomain" = mkOption {
          description = "An external domain that is used for exposing MongoDB to the outside world.";
          type = (types.nullOr types.str);
        };
        "externalService" = mkOption {
          description = "Provides a way to override the default (NodePort) Service";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecMongosClusterSpecListExternalAccessExternalService"
            )
          );
        };
      };

      config = {
        "externalDomain" = mkOverride 1002 null;
        "externalService" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosClusterSpecListExternalAccessExternalService" = {

      options = {
        "annotations" = mkOption {
          description = "A map of annotations that shall be added to the externally available Service.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "spec" = mkOption {
          description = "A wrapper for the Service spec object.";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosClusterSpecListMemberConfig" = {

      options = {
        "priority" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "tags" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "votes" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "priority" = mkOverride 1002 null;
        "tags" = mkOverride 1002 null;
        "votes" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosClusterSpecListPodSpec" = {

      options = {
        "persistence" = mkOption {
          description = "Note, that this field is used by MongoDB resources only, let's keep it here for simplicity";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosClusterSpecListPodSpecPersistence")
          );
        };
        "podTemplate" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "persistence" = mkOverride 1002 null;
        "podTemplate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosClusterSpecListPodSpecPersistence" = {

      options = {
        "multiple" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecMongosClusterSpecListPodSpecPersistenceMultiple"
            )
          );
        };
        "single" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosClusterSpecListPodSpecPersistenceSingle")
          );
        };
      };

      config = {
        "multiple" = mkOverride 1002 null;
        "single" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosClusterSpecListPodSpecPersistenceMultiple" = {

      options = {
        "data" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecMongosClusterSpecListPodSpecPersistenceMultipleData"
            )
          );
        };
        "journal" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecMongosClusterSpecListPodSpecPersistenceMultipleJournal"
            )
          );
        };
        "logs" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecMongosClusterSpecListPodSpecPersistenceMultipleLogs"
            )
          );
        };
      };

      config = {
        "data" = mkOverride 1002 null;
        "journal" = mkOverride 1002 null;
        "logs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosClusterSpecListPodSpecPersistenceMultipleData" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosClusterSpecListPodSpecPersistenceMultipleJournal" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosClusterSpecListPodSpecPersistenceMultipleLogs" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosClusterSpecListPodSpecPersistenceSingle" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosClusterSpecListStatefulSet" = {

      options = {
        "metadata" = mkOption {
          description = "StatefulSetMetadataWrapper is a wrapper around Labels and Annotations";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosClusterSpecListStatefulSetMetadata")
          );
        };
        "spec" = mkOption {
          description = "";
          type = types.attrs;
        };
      };

      config = {
        "metadata" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosClusterSpecListStatefulSetMetadata" = {

      options = {
        "annotations" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "labels" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosPodSpec" = {

      options = {
        "persistence" = mkOption {
          description = "Note, that this field is used by MongoDB resources only, let's keep it here for simplicity";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosPodSpecPersistence"));
        };
        "podTemplate" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "persistence" = mkOverride 1002 null;
        "podTemplate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosPodSpecPersistence" = {

      options = {
        "multiple" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosPodSpecPersistenceMultiple"));
        };
        "single" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosPodSpecPersistenceSingle"));
        };
      };

      config = {
        "multiple" = mkOverride 1002 null;
        "single" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosPodSpecPersistenceMultiple" = {

      options = {
        "data" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosPodSpecPersistenceMultipleData")
          );
        };
        "journal" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosPodSpecPersistenceMultipleJournal")
          );
        };
        "logs" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecMongosPodSpecPersistenceMultipleLogs")
          );
        };
      };

      config = {
        "data" = mkOverride 1002 null;
        "journal" = mkOverride 1002 null;
        "logs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosPodSpecPersistenceMultipleData" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosPodSpecPersistenceMultipleJournal" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosPodSpecPersistenceMultipleLogs" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecMongosPodSpecPersistenceSingle" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecOpsManager" = {

      options = {
        "configMapRef" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecOpsManagerConfigMapRef"));
        };
      };

      config = {
        "configMapRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecOpsManagerConfigMapRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "name" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecPodSpec" = {

      options = {
        "persistence" = mkOption {
          description = "Note, that this field is used by MongoDB resources only, let's keep it here for simplicity";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecPodSpecPersistence"));
        };
        "podTemplate" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "persistence" = mkOverride 1002 null;
        "podTemplate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecPodSpecPersistence" = {

      options = {
        "multiple" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecPodSpecPersistenceMultiple"));
        };
        "single" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecPodSpecPersistenceSingle"));
        };
      };

      config = {
        "multiple" = mkOverride 1002 null;
        "single" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecPodSpecPersistenceMultiple" = {

      options = {
        "data" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecPodSpecPersistenceMultipleData"));
        };
        "journal" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecPodSpecPersistenceMultipleJournal"));
        };
        "logs" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecPodSpecPersistenceMultipleLogs"));
        };
      };

      config = {
        "data" = mkOverride 1002 null;
        "journal" = mkOverride 1002 null;
        "logs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecPodSpecPersistenceMultipleData" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecPodSpecPersistenceMultipleJournal" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecPodSpecPersistenceMultipleLogs" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecPodSpecPersistenceSingle" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecPrometheus" = {

      options = {
        "metricsPath" = mkOption {
          description = "Indicates path to the metrics endpoint.";
          type = (types.nullOr types.str);
        };
        "passwordSecretRef" = mkOption {
          description = "Name of a Secret containing a HTTP Basic Auth Password.";
          type = (submoduleOf "mongodb.com.v1.MongoDBSpecPrometheusPasswordSecretRef");
        };
        "port" = mkOption {
          description = "Port where metrics endpoint will bind to. Defaults to 9216.";
          type = (types.nullOr types.int);
        };
        "tlsSecretKeyRef" = mkOption {
          description = "Name of a Secret (type kubernetes.io/tls) holding the certificates to use in the\nPrometheus endpoint.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecPrometheusTlsSecretKeyRef"));
        };
        "username" = mkOption {
          description = "HTTP Basic Auth Username for metrics endpoint.";
          type = types.str;
        };
      };

      config = {
        "metricsPath" = mkOverride 1002 null;
        "port" = mkOverride 1002 null;
        "tlsSecretKeyRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecPrometheusPasswordSecretRef" = {

      options = {
        "key" = mkOption {
          description = "Key is the key in the secret storing this password. Defaults to \"password\"";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "Name is the name of the secret storing this user's password";
          type = types.str;
        };
      };

      config = {
        "key" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecPrometheusTlsSecretKeyRef" = {

      options = {
        "key" = mkOption {
          description = "Key is the key in the secret storing this password. Defaults to \"password\"";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "Name is the name of the secret storing this user's password";
          type = types.str;
        };
      };

      config = {
        "key" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecSecurity" = {

      options = {
        "authentication" = mkOption {
          description = "Authentication holds various authentication related settings that affect\nthis MongoDB resource.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecSecurityAuthentication"));
        };
        "certsSecretPrefix" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "roleRefs" = mkOption {
          description = "";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "mongodb.com.v1.MongoDBSpecSecurityRoleRefs" "name" [ ]
            )
          );
          apply = attrsToList;
        };
        "roles" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBSpecSecurityRoles")));
        };
        "tls" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecSecurityTls"));
        };
      };

      config = {
        "authentication" = mkOverride 1002 null;
        "certsSecretPrefix" = mkOverride 1002 null;
        "roleRefs" = mkOverride 1002 null;
        "roles" = mkOverride 1002 null;
        "tls" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecSecurityAuthentication" = {

      options = {
        "agents" = mkOption {
          description = "Agents contains authentication configuration properties for the agents";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecSecurityAuthenticationAgents"));
        };
        "enabled" = mkOption {
          description = "";
          type = types.bool;
        };
        "ignoreUnknownUsers" = mkOption {
          description = "IgnoreUnknownUsers maps to the inverse of auth.authoritativeSet";
          type = (types.nullOr types.bool);
        };
        "internalCluster" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "ldap" = mkOption {
          description = "LDAP Configuration";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecSecurityAuthenticationLdap"));
        };
        "modes" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "oidcProviderConfigs" = mkOption {
          description = "Configuration for OIDC providers";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.MongoDBSpecSecurityAuthenticationOidcProviderConfigs")
            )
          );
        };
        "requireClientTLSAuthentication" = mkOption {
          description = "Clients should present valid TLS certificates";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "agents" = mkOverride 1002 null;
        "ignoreUnknownUsers" = mkOverride 1002 null;
        "internalCluster" = mkOverride 1002 null;
        "ldap" = mkOverride 1002 null;
        "modes" = mkOverride 1002 null;
        "oidcProviderConfigs" = mkOverride 1002 null;
        "requireClientTLSAuthentication" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecSecurityAuthenticationAgents" = {

      options = {
        "automationLdapGroupDN" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "automationPasswordSecretRef" = mkOption {
          description = "SecretKeySelector selects a key of a Secret.";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecSecurityAuthenticationAgentsAutomationPasswordSecretRef"
            )
          );
        };
        "automationUserName" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "clientCertificateSecretRef" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "mode" = mkOption {
          description = "Mode is the desired Authentication mode that the agents will use";
          type = types.str;
        };
      };

      config = {
        "automationLdapGroupDN" = mkOverride 1002 null;
        "automationPasswordSecretRef" = mkOverride 1002 null;
        "automationUserName" = mkOverride 1002 null;
        "clientCertificateSecretRef" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecSecurityAuthenticationAgentsAutomationPasswordSecretRef" = {

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
    "mongodb.com.v1.MongoDBSpecSecurityAuthenticationLdap" = {

      options = {
        "authzQueryTemplate" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "bindQueryPasswordSecretRef" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecSecurityAuthenticationLdapBindQueryPasswordSecretRef"
            )
          );
        };
        "bindQueryUser" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "caConfigMapRef" = mkOption {
          description = "Allows to point at a ConfigMap/key with a CA file to mount on the Pod";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecSecurityAuthenticationLdapCaConfigMapRef")
          );
        };
        "servers" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "timeoutMS" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "transportSecurity" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "userCacheInvalidationInterval" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "userToDNMapping" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "validateLDAPServerConfig" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "authzQueryTemplate" = mkOverride 1002 null;
        "bindQueryPasswordSecretRef" = mkOverride 1002 null;
        "bindQueryUser" = mkOverride 1002 null;
        "caConfigMapRef" = mkOverride 1002 null;
        "servers" = mkOverride 1002 null;
        "timeoutMS" = mkOverride 1002 null;
        "transportSecurity" = mkOverride 1002 null;
        "userCacheInvalidationInterval" = mkOverride 1002 null;
        "userToDNMapping" = mkOverride 1002 null;
        "validateLDAPServerConfig" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecSecurityAuthenticationLdapBindQueryPasswordSecretRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBSpecSecurityAuthenticationLdapCaConfigMapRef" = {

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
    "mongodb.com.v1.MongoDBSpecSecurityAuthenticationOidcProviderConfigs" = {

      options = {
        "audience" = mkOption {
          description = "Entity that your external identity provider intends the token for.\nEnter the audience value from the app you registered with external Identity Provider.";
          type = types.str;
        };
        "authorizationMethod" = mkOption {
          description = "Configure single-sign-on for human user access to deployments with Workforce Identity Federation.\nFor programmatic, application access to deployments use Workload Identity Federation.\nOnly one Workforce Identity Federation IdP can be configured per MongoDB resource";
          type = types.str;
        };
        "authorizationType" = mkOption {
          description = "Select GroupMembership to grant authorization based on IdP user group membership, or select UserID to grant\nan individual user authorization.";
          type = types.str;
        };
        "clientId" = mkOption {
          description = "Unique identifier for your registered application. Enter the clientId value from the app you\nregistered with an external Identity Provider.\nRequired when selected Workforce Identity Federation authorization method";
          type = (types.nullOr types.str);
        };
        "configurationName" = mkOption {
          description = "Unique label that identifies this configuration. It is case-sensitive and can only contain the following characters:\n - alphanumeric characters (combination of a to z and 0 to 9)\n - hyphens (-)\n - underscores (_)";
          type = types.str;
        };
        "groupsClaim" = mkOption {
          description = "The identifier of the claim that includes the principal's IdP user group membership information.\nRequired when selected GroupMembership as the authorization type, ignored otherwise";
          type = (types.nullOr types.str);
        };
        "issuerURI" = mkOption {
          description = "Issuer value provided by your registered IdP application. Using this URI, MongoDB finds an OpenID Connect Provider\nConfiguration Document, which should be available in the /.wellknown/open-id-configuration endpoint.\nFor MongoDB 8.0+, the combination of issuerURI and audience must be unique across OIDC provider configurations.\nFor other MongoDB versions, the issuerURI itself must be unique.";
          type = types.str;
        };
        "requestedScopes" = mkOption {
          description = "Tokens that give users permission to request data from the authorization endpoint.\nOnly used for Workforce Identity Federation authorization method";
          type = (types.nullOr (types.listOf types.str));
        };
        "userClaim" = mkOption {
          description = "The identifier of the claim that includes the user principal identity.\nAccept the default value unless your IdP uses a different claim.";
          type = types.str;
        };
      };

      config = {
        "clientId" = mkOverride 1002 null;
        "groupsClaim" = mkOverride 1002 null;
        "requestedScopes" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecSecurityRoleRefs" = {

      options = {
        "kind" = mkOption {
          description = "";
          type = types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBSpecSecurityRoles" = {

      options = {
        "authenticationRestrictions" = mkOption {
          description = "";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.MongoDBSpecSecurityRolesAuthenticationRestrictions")
            )
          );
        };
        "db" = mkOption {
          description = "";
          type = types.str;
        };
        "privileges" = mkOption {
          description = "";
          type = (
            types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBSpecSecurityRolesPrivileges"))
          );
        };
        "role" = mkOption {
          description = "";
          type = types.str;
        };
        "roles" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBSpecSecurityRolesRoles")));
        };
      };

      config = {
        "authenticationRestrictions" = mkOverride 1002 null;
        "privileges" = mkOverride 1002 null;
        "roles" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecSecurityRolesAuthenticationRestrictions" = {

      options = {
        "clientSource" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "serverAddress" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "clientSource" = mkOverride 1002 null;
        "serverAddress" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecSecurityRolesPrivileges" = {

      options = {
        "actions" = mkOption {
          description = "";
          type = (types.listOf types.str);
        };
        "resource" = mkOption {
          description = "";
          type = (submoduleOf "mongodb.com.v1.MongoDBSpecSecurityRolesPrivilegesResource");
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBSpecSecurityRolesPrivilegesResource" = {

      options = {
        "cluster" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "collection" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "db" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "cluster" = mkOverride 1002 null;
        "collection" = mkOverride 1002 null;
        "db" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecSecurityRolesRoles" = {

      options = {
        "db" = mkOption {
          description = "";
          type = types.str;
        };
        "role" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBSpecSecurityTls" = {

      options = {
        "additionalCertificateDomains" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
        "ca" = mkOption {
          description = "CA corresponds to a ConfigMap containing an entry for the CA certificate (ca.pem)\nused to validate the certificates created already.";
          type = (types.nullOr types.str);
        };
        "enabled" = mkOption {
          description = "DEPRECATED please enable TLS by setting `security.certsSecretPrefix` or `security.tls.secretRef.prefix`.\nEnables TLS for this resource. This will make the operator try to mount a\nSecret with a defined name (<resource-name>-cert).\nThis is only used when enabling TLS on a MongoDB resource, and not on the\nAppDB, where TLS is configured by setting `secretRef.Name`.";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "additionalCertificateDomains" = mkOverride 1002 null;
        "ca" = mkOverride 1002 null;
        "enabled" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShard" = {

      options = {
        "additionalMongodConfig" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "agent" = mkOption {
          description = "Configuring logRotation is not allowed under this section.\nPlease use the most top level resource fields for this; spec.Agent";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardAgent"));
        };
        "clusterSpecList" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBSpecShardClusterSpecList")));
        };
      };

      config = {
        "additionalMongodConfig" = mkOverride 1002 null;
        "agent" = mkOverride 1002 null;
        "clusterSpecList" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardAgent" = {

      options = {
        "backupAgent" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardAgentBackupAgent"));
        };
        "logLevel" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "logRotate" = mkOption {
          description = "DEPRECATED please use mongod.logRotate";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardAgentLogRotate"));
        };
        "maxLogFileDurationHours" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "mongod" = mkOption {
          description = "AgentLoggingMongodConfig contain settings for the mongodb processes configured by the agent";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardAgentMongod"));
        };
        "monitoringAgent" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardAgentMonitoringAgent"));
        };
        "readinessProbe" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardAgentReadinessProbe"));
        };
        "startupOptions" = mkOption {
          description = "StartupParameters can be used to configure the startup parameters with which the agent starts. That also contains\nlog rotation settings as defined here:";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "systemLog" = mkOption {
          description = "DEPRECATED please use mongod.systemLog";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardAgentSystemLog"));
        };
      };

      config = {
        "backupAgent" = mkOverride 1002 null;
        "logLevel" = mkOverride 1002 null;
        "logRotate" = mkOverride 1002 null;
        "maxLogFileDurationHours" = mkOverride 1002 null;
        "mongod" = mkOverride 1002 null;
        "monitoringAgent" = mkOverride 1002 null;
        "readinessProbe" = mkOverride 1002 null;
        "startupOptions" = mkOverride 1002 null;
        "systemLog" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardAgentBackupAgent" = {

      options = {
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the BackupAgent processes";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardAgentBackupAgentLogRotate"));
        };
      };

      config = {
        "logRotate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardAgentBackupAgentLogRotate" = {

      options = {
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nOM only supports ints";
          type = (types.nullOr types.int);
        };
        "timeThresholdHrs" = mkOption {
          description = "Number of hours after which this MongoDB Agent rotates the log file.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "sizeThresholdMB" = mkOverride 1002 null;
        "timeThresholdHrs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardAgentLogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardAgentMongod" = {

      options = {
        "auditlogRotate" = mkOption {
          description = "LogRotate configures audit log rotation for the mongodb processes";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardAgentMongodAuditlogRotate"));
        };
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the mongodb processes";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardAgentMongodLogRotate"));
        };
        "systemLog" = mkOption {
          description = "SystemLog configures system log of mongod";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardAgentMongodSystemLog"));
        };
      };

      config = {
        "auditlogRotate" = mkOverride 1002 null;
        "logRotate" = mkOverride 1002 null;
        "systemLog" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardAgentMongodAuditlogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardAgentMongodLogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardAgentMongodSystemLog" = {

      options = {
        "destination" = mkOption {
          description = "";
          type = types.str;
        };
        "logAppend" = mkOption {
          description = "";
          type = types.bool;
        };
        "path" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBSpecShardAgentMonitoringAgent" = {

      options = {
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the BackupAgent processes";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardAgentMonitoringAgentLogRotate"));
        };
      };

      config = {
        "logRotate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardAgentMonitoringAgentLogRotate" = {

      options = {
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nOM only supports ints";
          type = (types.nullOr types.int);
        };
        "timeThresholdHrs" = mkOption {
          description = "Number of hours after which this MongoDB Agent rotates the log file.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "sizeThresholdMB" = mkOverride 1002 null;
        "timeThresholdHrs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardAgentReadinessProbe" = {

      options = {
        "environmentVariables" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "environmentVariables" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardAgentSystemLog" = {

      options = {
        "destination" = mkOption {
          description = "";
          type = types.str;
        };
        "logAppend" = mkOption {
          description = "";
          type = types.bool;
        };
        "path" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBSpecShardClusterSpecList" = {

      options = {
        "clusterName" = mkOption {
          description = "ClusterName is name of the cluster where the MongoDB Statefulset will be scheduled, the\nname should have a one on one mapping with the service-account created in the central cluster\nto talk to the workload clusters.";
          type = (types.nullOr types.str);
        };
        "externalAccess" = mkOption {
          description = "ExternalAccessConfiguration provides external access configuration for Multi-Cluster.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardClusterSpecListExternalAccess"));
        };
        "memberConfig" = mkOption {
          description = "MemberConfig allows to specify votes, priorities and tags for each of the mongodb process.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.MongoDBSpecShardClusterSpecListMemberConfig")
            )
          );
        };
        "members" = mkOption {
          description = "Amount of members for this MongoDB Replica Set";
          type = types.int;
        };
        "podSpec" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardClusterSpecListPodSpec"));
        };
        "service" = mkOption {
          description = "this is an optional service, it will get the name \"<rsName>-service\" in case not provided";
          type = (types.nullOr types.str);
        };
        "statefulSet" = mkOption {
          description = "StatefulSetConfiguration holds the optional custom StatefulSet\nthat should be merged into the operator created one.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardClusterSpecListStatefulSet"));
        };
      };

      config = {
        "clusterName" = mkOverride 1002 null;
        "externalAccess" = mkOverride 1002 null;
        "memberConfig" = mkOverride 1002 null;
        "podSpec" = mkOverride 1002 null;
        "service" = mkOverride 1002 null;
        "statefulSet" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardClusterSpecListExternalAccess" = {

      options = {
        "externalDomain" = mkOption {
          description = "An external domain that is used for exposing MongoDB to the outside world.";
          type = (types.nullOr types.str);
        };
        "externalService" = mkOption {
          description = "Provides a way to override the default (NodePort) Service";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecShardClusterSpecListExternalAccessExternalService"
            )
          );
        };
      };

      config = {
        "externalDomain" = mkOverride 1002 null;
        "externalService" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardClusterSpecListExternalAccessExternalService" = {

      options = {
        "annotations" = mkOption {
          description = "A map of annotations that shall be added to the externally available Service.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "spec" = mkOption {
          description = "A wrapper for the Service spec object.";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "spec" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardClusterSpecListMemberConfig" = {

      options = {
        "priority" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "tags" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "votes" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "priority" = mkOverride 1002 null;
        "tags" = mkOverride 1002 null;
        "votes" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardClusterSpecListPodSpec" = {

      options = {
        "persistence" = mkOption {
          description = "Note, that this field is used by MongoDB resources only, let's keep it here for simplicity";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardClusterSpecListPodSpecPersistence")
          );
        };
        "podTemplate" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "persistence" = mkOverride 1002 null;
        "podTemplate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardClusterSpecListPodSpecPersistence" = {

      options = {
        "multiple" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecShardClusterSpecListPodSpecPersistenceMultiple"
            )
          );
        };
        "single" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardClusterSpecListPodSpecPersistenceSingle")
          );
        };
      };

      config = {
        "multiple" = mkOverride 1002 null;
        "single" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardClusterSpecListPodSpecPersistenceMultiple" = {

      options = {
        "data" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecShardClusterSpecListPodSpecPersistenceMultipleData"
            )
          );
        };
        "journal" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecShardClusterSpecListPodSpecPersistenceMultipleJournal"
            )
          );
        };
        "logs" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecShardClusterSpecListPodSpecPersistenceMultipleLogs"
            )
          );
        };
      };

      config = {
        "data" = mkOverride 1002 null;
        "journal" = mkOverride 1002 null;
        "logs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardClusterSpecListPodSpecPersistenceMultipleData" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardClusterSpecListPodSpecPersistenceMultipleJournal" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardClusterSpecListPodSpecPersistenceMultipleLogs" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardClusterSpecListPodSpecPersistenceSingle" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardClusterSpecListStatefulSet" = {

      options = {
        "metadata" = mkOption {
          description = "StatefulSetMetadataWrapper is a wrapper around Labels and Annotations";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardClusterSpecListStatefulSetMetadata")
          );
        };
        "spec" = mkOption {
          description = "";
          type = types.attrs;
        };
      };

      config = {
        "metadata" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardClusterSpecListStatefulSetMetadata" = {

      options = {
        "annotations" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "labels" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverrides" = {

      options = {
        "additionalMongodConfig" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "agent" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesAgent"));
        };
        "clusterSpecList" = mkOption {
          description = "";
          type = (
            types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecList"))
          );
        };
        "memberConfig" = mkOption {
          description = "Process configuration override for this shard. Used in SingleCluster only. The number of items specified must be >= spec.mongodsPerShardCount or spec.shardOverride.members.";
          type = (
            types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesMemberConfig"))
          );
        };
        "members" = mkOption {
          description = "Number of member nodes in this shard. Used only in SingleCluster. For MultiCluster the number of members is specified in ShardOverride.ClusterSpecList.";
          type = (types.nullOr types.int);
        };
        "podSpec" = mkOption {
          description = "The following override fields work for SingleCluster only. For MultiCluster - fields from specific clusters are used.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesPodSpec"));
        };
        "shardNames" = mkOption {
          description = "";
          type = (types.listOf types.str);
        };
        "statefulSet" = mkOption {
          description = "Statefulset override for this particular shard.";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesStatefulSet"));
        };
      };

      config = {
        "additionalMongodConfig" = mkOverride 1002 null;
        "agent" = mkOverride 1002 null;
        "clusterSpecList" = mkOverride 1002 null;
        "memberConfig" = mkOverride 1002 null;
        "members" = mkOverride 1002 null;
        "podSpec" = mkOverride 1002 null;
        "statefulSet" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesAgent" = {

      options = {
        "backupAgent" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesAgentBackupAgent"));
        };
        "logLevel" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "logRotate" = mkOption {
          description = "DEPRECATED please use mongod.logRotate";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesAgentLogRotate"));
        };
        "maxLogFileDurationHours" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "mongod" = mkOption {
          description = "AgentLoggingMongodConfig contain settings for the mongodb processes configured by the agent";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesAgentMongod"));
        };
        "monitoringAgent" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesAgentMonitoringAgent"));
        };
        "readinessProbe" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesAgentReadinessProbe"));
        };
        "startupOptions" = mkOption {
          description = "StartupParameters can be used to configure the startup parameters with which the agent starts. That also contains\nlog rotation settings as defined here:";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "systemLog" = mkOption {
          description = "DEPRECATED please use mongod.systemLog";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesAgentSystemLog"));
        };
      };

      config = {
        "backupAgent" = mkOverride 1002 null;
        "logLevel" = mkOverride 1002 null;
        "logRotate" = mkOverride 1002 null;
        "maxLogFileDurationHours" = mkOverride 1002 null;
        "mongod" = mkOverride 1002 null;
        "monitoringAgent" = mkOverride 1002 null;
        "readinessProbe" = mkOverride 1002 null;
        "startupOptions" = mkOverride 1002 null;
        "systemLog" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesAgentBackupAgent" = {

      options = {
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the BackupAgent processes";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesAgentBackupAgentLogRotate")
          );
        };
      };

      config = {
        "logRotate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesAgentBackupAgentLogRotate" = {

      options = {
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nOM only supports ints";
          type = (types.nullOr types.int);
        };
        "timeThresholdHrs" = mkOption {
          description = "Number of hours after which this MongoDB Agent rotates the log file.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "sizeThresholdMB" = mkOverride 1002 null;
        "timeThresholdHrs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesAgentLogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesAgentMongod" = {

      options = {
        "auditlogRotate" = mkOption {
          description = "LogRotate configures audit log rotation for the mongodb processes";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesAgentMongodAuditlogRotate")
          );
        };
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the mongodb processes";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesAgentMongodLogRotate"));
        };
        "systemLog" = mkOption {
          description = "SystemLog configures system log of mongod";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesAgentMongodSystemLog"));
        };
      };

      config = {
        "auditlogRotate" = mkOverride 1002 null;
        "logRotate" = mkOverride 1002 null;
        "systemLog" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesAgentMongodAuditlogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesAgentMongodLogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesAgentMongodSystemLog" = {

      options = {
        "destination" = mkOption {
          description = "";
          type = types.str;
        };
        "logAppend" = mkOption {
          description = "";
          type = types.bool;
        };
        "path" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesAgentMonitoringAgent" = {

      options = {
        "logRotate" = mkOption {
          description = "LogRotate configures log rotation for the BackupAgent processes";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesAgentMonitoringAgentLogRotate")
          );
        };
      };

      config = {
        "logRotate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesAgentMonitoringAgentLogRotate" = {

      options = {
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nOM only supports ints";
          type = (types.nullOr types.int);
        };
        "timeThresholdHrs" = mkOption {
          description = "Number of hours after which this MongoDB Agent rotates the log file.";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "sizeThresholdMB" = mkOverride 1002 null;
        "timeThresholdHrs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesAgentReadinessProbe" = {

      options = {
        "environmentVariables" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "environmentVariables" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesAgentSystemLog" = {

      options = {
        "destination" = mkOption {
          description = "";
          type = types.str;
        };
        "logAppend" = mkOption {
          description = "";
          type = types.bool;
        };
        "path" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecList" = {

      options = {
        "clusterName" = mkOption {
          description = "ClusterName is name of the cluster where the MongoDB Statefulset will be scheduled, the\nname should have a one on one mapping with the service-account created in the central cluster\nto talk to the workload clusters.";
          type = (types.nullOr types.str);
        };
        "memberConfig" = mkOption {
          description = "MemberConfig allows to specify votes, priorities and tags for each of the mongodb process.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListMemberConfig")
            )
          );
        };
        "members" = mkOption {
          description = "Amount of members for this MongoDB Replica Set";
          type = (types.nullOr types.int);
        };
        "podSpec" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListPodSpec")
          );
        };
        "statefulSet" = mkOption {
          description = "StatefulSetConfiguration holds the optional custom StatefulSet\nthat should be merged into the operator created one.";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListStatefulSet")
          );
        };
      };

      config = {
        "clusterName" = mkOverride 1002 null;
        "memberConfig" = mkOverride 1002 null;
        "members" = mkOverride 1002 null;
        "podSpec" = mkOverride 1002 null;
        "statefulSet" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListMemberConfig" = {

      options = {
        "priority" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "tags" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "votes" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "priority" = mkOverride 1002 null;
        "tags" = mkOverride 1002 null;
        "votes" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListPodSpec" = {

      options = {
        "persistence" = mkOption {
          description = "Note, that this field is used by MongoDB resources only, let's keep it here for simplicity";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListPodSpecPersistence"
            )
          );
        };
        "podTemplate" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "persistence" = mkOverride 1002 null;
        "podTemplate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListPodSpecPersistence" = {

      options = {
        "multiple" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListPodSpecPersistenceMultiple"
            )
          );
        };
        "single" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListPodSpecPersistenceSingle"
            )
          );
        };
      };

      config = {
        "multiple" = mkOverride 1002 null;
        "single" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListPodSpecPersistenceMultiple" = {

      options = {
        "data" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListPodSpecPersistenceMultipleData"
            )
          );
        };
        "journal" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListPodSpecPersistenceMultipleJournal"
            )
          );
        };
        "logs" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListPodSpecPersistenceMultipleLogs"
            )
          );
        };
      };

      config = {
        "data" = mkOverride 1002 null;
        "journal" = mkOverride 1002 null;
        "logs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListPodSpecPersistenceMultipleData" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListPodSpecPersistenceMultipleJournal" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListPodSpecPersistenceMultipleLogs" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListPodSpecPersistenceSingle" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListStatefulSet" = {

      options = {
        "metadata" = mkOption {
          description = "StatefulSetMetadataWrapper is a wrapper around Labels and Annotations";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListStatefulSetMetadata"
            )
          );
        };
        "spec" = mkOption {
          description = "";
          type = types.attrs;
        };
      };

      config = {
        "metadata" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesClusterSpecListStatefulSetMetadata" = {

      options = {
        "annotations" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "labels" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesMemberConfig" = {

      options = {
        "priority" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "tags" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "votes" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "priority" = mkOverride 1002 null;
        "tags" = mkOverride 1002 null;
        "votes" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesPodSpec" = {

      options = {
        "persistence" = mkOption {
          description = "Note, that this field is used by MongoDB resources only, let's keep it here for simplicity";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesPodSpecPersistence"));
        };
        "podTemplate" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "persistence" = mkOverride 1002 null;
        "podTemplate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesPodSpecPersistence" = {

      options = {
        "multiple" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesPodSpecPersistenceMultiple")
          );
        };
        "single" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesPodSpecPersistenceSingle")
          );
        };
      };

      config = {
        "multiple" = mkOverride 1002 null;
        "single" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesPodSpecPersistenceMultiple" = {

      options = {
        "data" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesPodSpecPersistenceMultipleData")
          );
        };
        "journal" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesPodSpecPersistenceMultipleJournal"
            )
          );
        };
        "logs" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesPodSpecPersistenceMultipleLogs")
          );
        };
      };

      config = {
        "data" = mkOverride 1002 null;
        "journal" = mkOverride 1002 null;
        "logs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesPodSpecPersistenceMultipleData" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesPodSpecPersistenceMultipleJournal" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesPodSpecPersistenceMultipleLogs" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesPodSpecPersistenceSingle" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesStatefulSet" = {

      options = {
        "metadata" = mkOption {
          description = "StatefulSetMetadataWrapper is a wrapper around Labels and Annotations";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardOverridesStatefulSetMetadata"));
        };
        "spec" = mkOption {
          description = "";
          type = types.attrs;
        };
      };

      config = {
        "metadata" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardOverridesStatefulSetMetadata" = {

      options = {
        "annotations" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "labels" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardPodSpec" = {

      options = {
        "persistence" = mkOption {
          description = "Note, that this field is used by MongoDB resources only, let's keep it here for simplicity";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardPodSpecPersistence"));
        };
        "podTemplate" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "persistence" = mkOverride 1002 null;
        "podTemplate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardPodSpecPersistence" = {

      options = {
        "multiple" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardPodSpecPersistenceMultiple"));
        };
        "single" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardPodSpecPersistenceSingle"));
        };
      };

      config = {
        "multiple" = mkOverride 1002 null;
        "single" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardPodSpecPersistenceMultiple" = {

      options = {
        "data" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardPodSpecPersistenceMultipleData"));
        };
        "journal" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardPodSpecPersistenceMultipleJournal")
          );
        };
        "logs" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardPodSpecPersistenceMultipleLogs"));
        };
      };

      config = {
        "data" = mkOverride 1002 null;
        "journal" = mkOverride 1002 null;
        "logs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardPodSpecPersistenceMultipleData" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardPodSpecPersistenceMultipleJournal" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardPodSpecPersistenceMultipleLogs" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardPodSpecPersistenceSingle" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardSpecificPodSpec" = {

      options = {
        "persistence" = mkOption {
          description = "Note, that this field is used by MongoDB resources only, let's keep it here for simplicity";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardSpecificPodSpecPersistence"));
        };
        "podTemplate" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "persistence" = mkOverride 1002 null;
        "podTemplate" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardSpecificPodSpecPersistence" = {

      options = {
        "multiple" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardSpecificPodSpecPersistenceMultiple")
          );
        };
        "single" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardSpecificPodSpecPersistenceSingle")
          );
        };
      };

      config = {
        "multiple" = mkOverride 1002 null;
        "single" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardSpecificPodSpecPersistenceMultiple" = {

      options = {
        "data" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardSpecificPodSpecPersistenceMultipleData")
          );
        };
        "journal" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodb.com.v1.MongoDBSpecShardSpecificPodSpecPersistenceMultipleJournal"
            )
          );
        };
        "logs" = mkOption {
          description = "";
          type = (
            types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecShardSpecificPodSpecPersistenceMultipleLogs")
          );
        };
      };

      config = {
        "data" = mkOverride 1002 null;
        "journal" = mkOverride 1002 null;
        "logs" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardSpecificPodSpecPersistenceMultipleData" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardSpecificPodSpecPersistenceMultipleJournal" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardSpecificPodSpecPersistenceMultipleLogs" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecShardSpecificPodSpecPersistenceSingle" = {

      options = {
        "labelSelector" = mkOption {
          description = "";
          type = (types.nullOr types.attrs);
        };
        "storage" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "storageClass" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "labelSelector" = mkOverride 1002 null;
        "storage" = mkOverride 1002 null;
        "storageClass" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecStatefulSet" = {

      options = {
        "metadata" = mkOption {
          description = "StatefulSetMetadataWrapper is a wrapper around Labels and Annotations";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBSpecStatefulSetMetadata"));
        };
        "spec" = mkOption {
          description = "";
          type = types.attrs;
        };
      };

      config = {
        "metadata" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBSpecStatefulSetMetadata" = {

      options = {
        "annotations" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "labels" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBStatus" = {

      options = {
        "backup" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBStatusBackup"));
        };
        "configServerCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "featureCompatibilityVersion" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "lastTransition" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "link" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "members" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "mongodsPerShardCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "mongosCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "observedGeneration" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "phase" = mkOption {
          description = "";
          type = types.str;
        };
        "pvc" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBStatusPvc")));
        };
        "resourcesNotReady" = mkOption {
          description = "";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "mongodb.com.v1.MongoDBStatusResourcesNotReady" "name" [ ]
            )
          );
          apply = attrsToList;
        };
        "shardCount" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "sizeStatusInClusters" = mkOption {
          description = "MongodbShardedSizeStatusInClusters describes the number and sizes of replica sets members deployed across member clusters";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBStatusSizeStatusInClusters"));
        };
        "version" = mkOption {
          description = "";
          type = types.str;
        };
        "warnings" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "backup" = mkOverride 1002 null;
        "configServerCount" = mkOverride 1002 null;
        "featureCompatibilityVersion" = mkOverride 1002 null;
        "lastTransition" = mkOverride 1002 null;
        "link" = mkOverride 1002 null;
        "members" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "mongodsPerShardCount" = mkOverride 1002 null;
        "mongosCount" = mkOverride 1002 null;
        "observedGeneration" = mkOverride 1002 null;
        "pvc" = mkOverride 1002 null;
        "resourcesNotReady" = mkOverride 1002 null;
        "shardCount" = mkOverride 1002 null;
        "sizeStatusInClusters" = mkOverride 1002 null;
        "warnings" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBStatusBackup" = {

      options = {
        "statusName" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBStatusPvc" = {

      options = {
        "phase" = mkOption {
          description = "";
          type = types.str;
        };
        "statefulsetName" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBStatusResourcesNotReady" = {

      options = {
        "errors" = mkOption {
          description = "";
          type = (
            types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBStatusResourcesNotReadyErrors"))
          );
        };
        "kind" = mkOption {
          description = "ResourceKind specifies a kind of a Kubernetes resource. Used in status of a Custom Resource";
          type = types.str;
        };
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "errors" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBStatusResourcesNotReadyErrors" = {

      options = {
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "reason" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "message" = mkOverride 1002 null;
        "reason" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBStatusSizeStatusInClusters" = {

      options = {
        "configServerMongodsInClusters" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.int));
        };
        "mongosCountInClusters" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.int));
        };
        "shardMongodsInClusters" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.int));
        };
        "shardOverridesInClusters" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.attrs));
        };
      };

      config = {
        "configServerMongodsInClusters" = mkOverride 1002 null;
        "mongosCountInClusters" = mkOverride 1002 null;
        "shardMongodsInClusters" = mkOverride 1002 null;
        "shardOverridesInClusters" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBUser" = {

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
          description = "";
          type = (submoduleOf "mongodb.com.v1.MongoDBUserSpec");
        };
        "status" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBUserStatus"));
        };
      };

      config = {
        "apiVersion" = mkOverride 1002 null;
        "kind" = mkOverride 1002 null;
        "metadata" = mkOverride 1002 null;
        "status" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBUserSpec" = {

      options = {
        "connectionStringSecretName" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "db" = mkOption {
          description = "";
          type = types.str;
        };
        "mongodbResourceRef" = mkOption {
          description = "";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBUserSpecMongodbResourceRef"));
        };
        "passwordSecretKeyRef" = mkOption {
          description = "SecretKeyRef is a reference to a value in a given secret in the same\nnamespace. Based on:\nhttps://kubernetes.io/docs/reference/generated/kubernetes-api/v1.15/#secretkeyselector-v1-core";
          type = (types.nullOr (submoduleOf "mongodb.com.v1.MongoDBUserSpecPasswordSecretKeyRef"));
        };
        "roles" = mkOption {
          description = "";
          type = (
            types.nullOr (coerceAttrsOfSubmodulesToListByKey "mongodb.com.v1.MongoDBUserSpecRoles" "name" [ ])
          );
          apply = attrsToList;
        };
        "username" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "connectionStringSecretName" = mkOverride 1002 null;
        "mongodbResourceRef" = mkOverride 1002 null;
        "passwordSecretKeyRef" = mkOverride 1002 null;
        "roles" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBUserSpecMongodbResourceRef" = {

      options = {
        "name" = mkOption {
          description = "";
          type = types.str;
        };
        "namespace" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "namespace" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBUserSpecPasswordSecretKeyRef" = {

      options = {
        "key" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "key" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBUserSpecRoles" = {

      options = {
        "db" = mkOption {
          description = "";
          type = types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBUserStatus" = {

      options = {
        "db" = mkOption {
          description = "";
          type = types.str;
        };
        "lastTransition" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "observedGeneration" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "phase" = mkOption {
          description = "";
          type = types.str;
        };
        "project" = mkOption {
          description = "";
          type = types.str;
        };
        "pvc" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBUserStatusPvc")));
        };
        "resourcesNotReady" = mkOption {
          description = "";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey "mongodb.com.v1.MongoDBUserStatusResourcesNotReady" "name" [ ]
            )
          );
          apply = attrsToList;
        };
        "roles" = mkOption {
          description = "";
          type = (
            types.nullOr (coerceAttrsOfSubmodulesToListByKey "mongodb.com.v1.MongoDBUserStatusRoles" "name" [ ])
          );
          apply = attrsToList;
        };
        "username" = mkOption {
          description = "";
          type = types.str;
        };
        "warnings" = mkOption {
          description = "";
          type = (types.nullOr (types.listOf types.str));
        };
      };

      config = {
        "lastTransition" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "observedGeneration" = mkOverride 1002 null;
        "pvc" = mkOverride 1002 null;
        "resourcesNotReady" = mkOverride 1002 null;
        "roles" = mkOverride 1002 null;
        "warnings" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBUserStatusPvc" = {

      options = {
        "phase" = mkOption {
          description = "";
          type = types.str;
        };
        "statefulsetName" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodb.com.v1.MongoDBUserStatusResourcesNotReady" = {

      options = {
        "errors" = mkOption {
          description = "";
          type = (
            types.nullOr (types.listOf (submoduleOf "mongodb.com.v1.MongoDBUserStatusResourcesNotReadyErrors"))
          );
        };
        "kind" = mkOption {
          description = "ResourceKind specifies a kind of a Kubernetes resource. Used in status of a Custom Resource";
          type = types.str;
        };
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "errors" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBUserStatusResourcesNotReadyErrors" = {

      options = {
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "reason" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "message" = mkOverride 1002 null;
        "reason" = mkOverride 1002 null;
      };

    };
    "mongodb.com.v1.MongoDBUserStatusRoles" = {

      options = {
        "db" = mkOption {
          description = "";
          type = types.str;
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunity" = {

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
          description = "MongoDBCommunitySpec defines the desired state of MongoDB";
          type = (types.nullOr (submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpec"));
        };
        "status" = mkOption {
          description = "MongoDBCommunityStatus defines the observed state of MongoDB";
          type = (types.nullOr (submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunityStatus"));
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
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpec" = {

      options = {
        "additionalConnectionStringConfig" = mkOption {
          description = "Additional options to be appended to the connection string. These options apply to the entire resource and to each user.";
          type = (types.nullOr types.attrs);
        };
        "additionalMongodConfig" = mkOption {
          description = "AdditionalMongodConfig is additional configuration that can be passed to\neach data-bearing mongod at runtime. Uses the same structure as the mongod\nconfiguration file: https://www.mongodb.com/docs/manual/reference/configuration-options/";
          type = (types.nullOr types.attrs);
        };
        "agent" = mkOption {
          description = "AgentConfiguration sets options for the MongoDB automation agent";
          type = (types.nullOr (submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecAgent"));
        };
        "arbiters" = mkOption {
          description = "Arbiters is the number of arbiters to add to the Replica Set.\nIt is not recommended to have more than one arbiter per Replica Set.\nMore info: https://www.mongodb.com/docs/manual/tutorial/add-replica-set-arbiter/";
          type = (types.nullOr types.int);
        };
        "automationConfig" = mkOption {
          description = "AutomationConfigOverride is merged on top of the operator created automation config. Processes are merged\nby name. Currently Only the process.disabled field is supported.";
          type = (
            types.nullOr (submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecAutomationConfig")
          );
        };
        "clusterDomain" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "featureCompatibilityVersion" = mkOption {
          description = "FeatureCompatibilityVersion configures the feature compatibility version that will\nbe set for the deployment";
          type = (types.nullOr types.str);
        };
        "memberConfig" = mkOption {
          description = "MemberConfig";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecMemberConfig")
            )
          );
        };
        "members" = mkOption {
          description = "Members is the number of members in the replica set";
          type = (types.nullOr types.int);
        };
        "prometheus" = mkOption {
          description = "Prometheus configurations.";
          type = (
            types.nullOr (submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecPrometheus")
          );
        };
        "replicaSetHorizons" = mkOption {
          description = "ReplicaSetHorizons Add this parameter and values if you need your database\nto be accessed outside of Kubernetes. This setting allows you to\nprovide different DNS settings within the Kubernetes cluster and\nto the Kubernetes cluster. The Kubernetes Operator uses split horizon\nDNS for replica set members. This feature allows communication both\nwithin the Kubernetes cluster and from outside Kubernetes.";
          type = (types.nullOr (types.listOf types.attrs));
        };
        "security" = mkOption {
          description = "Security configures security features, such as TLS, and authentication settings for a deployment";
          type = (submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurity");
        };
        "statefulSet" = mkOption {
          description = "StatefulSetConfiguration holds the optional custom StatefulSet\nthat should be merged into the operator created one.";
          type = (
            types.nullOr (submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecStatefulSet")
          );
        };
        "type" = mkOption {
          description = "Type defines which type of MongoDB deployment the resource should create";
          type = types.str;
        };
        "users" = mkOption {
          description = "Users specifies the MongoDB users that should be configured in your deployment";
          type = (
            coerceAttrsOfSubmodulesToListByKey "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecUsers"
              "name"
              [ ]
          );
          apply = attrsToList;
        };
        "version" = mkOption {
          description = "Version defines which version of MongoDB will be used";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "additionalConnectionStringConfig" = mkOverride 1002 null;
        "additionalMongodConfig" = mkOverride 1002 null;
        "agent" = mkOverride 1002 null;
        "arbiters" = mkOverride 1002 null;
        "automationConfig" = mkOverride 1002 null;
        "clusterDomain" = mkOverride 1002 null;
        "featureCompatibilityVersion" = mkOverride 1002 null;
        "memberConfig" = mkOverride 1002 null;
        "members" = mkOverride 1002 null;
        "prometheus" = mkOverride 1002 null;
        "replicaSetHorizons" = mkOverride 1002 null;
        "statefulSet" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecAgent" = {

      options = {
        "auditLogRotate" = mkOption {
          description = "AuditLogRotate if enabled, will enable AuditLogRotate for all processes.";
          type = (
            types.nullOr (submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecAgentAuditLogRotate")
          );
        };
        "logFile" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "logLevel" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "logRotate" = mkOption {
          description = "LogRotate if enabled, will enable LogRotate for all processes.";
          type = (
            types.nullOr (submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecAgentLogRotate")
          );
        };
        "maxLogFileDurationHours" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "systemLog" = mkOption {
          description = "SystemLog configures system log of mongod";
          type = (
            types.nullOr (submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecAgentSystemLog")
          );
        };
      };

      config = {
        "auditLogRotate" = mkOverride 1002 null;
        "logFile" = mkOverride 1002 null;
        "logLevel" = mkOverride 1002 null;
        "logRotate" = mkOverride 1002 null;
        "maxLogFileDurationHours" = mkOverride 1002 null;
        "systemLog" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecAgentAuditLogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecAgentLogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecAgentSystemLog" = {

      options = {
        "destination" = mkOption {
          description = "";
          type = types.str;
        };
        "logAppend" = mkOption {
          description = "";
          type = types.bool;
        };
        "path" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecAutomationConfig" = {

      options = {
        "processes" = mkOption {
          description = "";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecAutomationConfigProcesses"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
        "replicaSet" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecAutomationConfigReplicaSet"
            )
          );
        };
      };

      config = {
        "processes" = mkOverride 1002 null;
        "replicaSet" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecAutomationConfigProcesses" = {

      options = {
        "disabled" = mkOption {
          description = "";
          type = types.bool;
        };
        "logRotate" = mkOption {
          description = "CrdLogRotate is the crd definition of LogRotate including fields in strings while the agent supports them as float64";
          type = (
            types.nullOr (
              submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecAutomationConfigProcessesLogRotate"
            )
          );
        };
        "name" = mkOption {
          description = "";
          type = types.str;
        };
      };

      config = {
        "logRotate" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecAutomationConfigProcessesLogRotate" = {

      options = {
        "includeAuditLogsWithMongoDBLogs" = mkOption {
          description = "set to 'true' to have the Automation Agent rotate the audit files along\nwith mongodb log files";
          type = (types.nullOr types.bool);
        };
        "numTotal" = mkOption {
          description = "maximum number of log files to have total";
          type = (types.nullOr types.int);
        };
        "numUncompressed" = mkOption {
          description = "maximum number of log files to leave uncompressed";
          type = (types.nullOr types.int);
        };
        "percentOfDiskspace" = mkOption {
          description = "Maximum percentage of the total disk space these log files should take up.\nThe string needs to be able to be converted to float64";
          type = (types.nullOr types.str);
        };
        "sizeThresholdMB" = mkOption {
          description = "Maximum size for an individual log file before rotation.\nThe string needs to be able to be converted to float64.\nFractional values of MB are supported.";
          type = types.str;
        };
        "timeThresholdHrs" = mkOption {
          description = "maximum hours for an individual log file before rotation";
          type = types.int;
        };
      };

      config = {
        "includeAuditLogsWithMongoDBLogs" = mkOverride 1002 null;
        "numTotal" = mkOverride 1002 null;
        "numUncompressed" = mkOverride 1002 null;
        "percentOfDiskspace" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecAutomationConfigReplicaSet" = {

      options = {
        "id" = mkOption {
          description = "Id can be used together with additionalMongodConfig.replication.replSetName\nto manage clusters where replSetName differs from the MongoDBCommunity resource name";
          type = (types.nullOr types.str);
        };
        "settings" = mkOption {
          description = "MapWrapper is a wrapper for a map to be used by other structs.\nThe CRD generator does not support map[string]interface{}\non the top level and hence we need to work around this with\na wrapping struct.";
          type = (types.nullOr types.attrs);
        };
      };

      config = {
        "id" = mkOverride 1002 null;
        "settings" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecMemberConfig" = {

      options = {
        "priority" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "tags" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "votes" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
      };

      config = {
        "priority" = mkOverride 1002 null;
        "tags" = mkOverride 1002 null;
        "votes" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecPrometheus" = {

      options = {
        "metricsPath" = mkOption {
          description = "Indicates path to the metrics endpoint.";
          type = (types.nullOr types.str);
        };
        "passwordSecretRef" = mkOption {
          description = "Name of a Secret containing a HTTP Basic Auth Password.";
          type = (
            submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecPrometheusPasswordSecretRef"
          );
        };
        "port" = mkOption {
          description = "Port where metrics endpoint will bind to. Defaults to 9216.";
          type = (types.nullOr types.int);
        };
        "tlsSecretKeyRef" = mkOption {
          description = "Name of a Secret (type kubernetes.io/tls) holding the certificates to use in the\nPrometheus endpoint.";
          type = (
            types.nullOr (
              submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecPrometheusTlsSecretKeyRef"
            )
          );
        };
        "username" = mkOption {
          description = "HTTP Basic Auth Username for metrics endpoint.";
          type = types.str;
        };
      };

      config = {
        "metricsPath" = mkOverride 1002 null;
        "port" = mkOverride 1002 null;
        "tlsSecretKeyRef" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecPrometheusPasswordSecretRef" = {

      options = {
        "key" = mkOption {
          description = "Key is the key in the secret storing this password. Defaults to \"password\"";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "Name is the name of the secret storing this user's password";
          type = types.str;
        };
      };

      config = {
        "key" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecPrometheusTlsSecretKeyRef" = {

      options = {
        "key" = mkOption {
          description = "Key is the key in the secret storing this password. Defaults to \"password\"";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "Name is the name of the secret storing this user's password";
          type = types.str;
        };
      };

      config = {
        "key" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurity" = {

      options = {
        "authentication" = mkOption {
          description = "";
          type = (
            types.nullOr (
              submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityAuthentication"
            )
          );
        };
        "roles" = mkOption {
          description = "User-specified custom MongoDB roles that should be configured in the deployment.";
          type = (
            types.nullOr (
              types.listOf (submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityRoles")
            )
          );
        };
        "tls" = mkOption {
          description = "TLS configuration for both client-server and server-server communication";
          type = (
            types.nullOr (submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityTls")
          );
        };
      };

      config = {
        "authentication" = mkOverride 1002 null;
        "roles" = mkOverride 1002 null;
        "tls" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityAuthentication" = {

      options = {
        "agentCertificateSecretRef" = mkOption {
          description = "AgentCertificateSecret is a reference to a Secret containing the certificate and the key for the automation agent\nThe secret needs to have available:\n- certificate under key: \"tls.crt\"\n- private key under key: \"tls.key\"\nIf additionally, tls.pem is present, then it needs to be equal to the concatenation of tls.crt and tls.key";
          type = (
            types.nullOr (
              submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityAuthenticationAgentCertificateSecretRef"
            )
          );
        };
        "agentMode" = mkOption {
          description = "AgentMode contains the authentication mode used by the automation agent.";
          type = (types.nullOr types.str);
        };
        "ignoreUnknownUsers" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "modes" = mkOption {
          description = "Modes is an array specifying which authentication methods should be enabled.";
          type = (types.listOf types.str);
        };
      };

      config = {
        "agentCertificateSecretRef" = mkOverride 1002 null;
        "agentMode" = mkOverride 1002 null;
        "ignoreUnknownUsers" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityAuthenticationAgentCertificateSecretRef" =
      {

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
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityRoles" = {

      options = {
        "authenticationRestrictions" = mkOption {
          description = "The authentication restrictions the server enforces on the role.";
          type = (
            types.nullOr (
              types.listOf (
                submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityRolesAuthenticationRestrictions"
              )
            )
          );
        };
        "db" = mkOption {
          description = "The database of the role.";
          type = types.str;
        };
        "privileges" = mkOption {
          description = "The privileges to grant the role.";
          type = (
            types.listOf (
              submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityRolesPrivileges"
            )
          );
        };
        "role" = mkOption {
          description = "The name of the role.";
          type = types.str;
        };
        "roles" = mkOption {
          description = "An array of roles from which this role inherits privileges.";
          type = (
            types.nullOr (
              coerceAttrsOfSubmodulesToListByKey
                "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityRolesRoles"
                "name"
                [ ]
            )
          );
          apply = attrsToList;
        };
      };

      config = {
        "authenticationRestrictions" = mkOverride 1002 null;
        "roles" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityRolesAuthenticationRestrictions" = {

      options = {
        "clientSource" = mkOption {
          description = "";
          type = (types.listOf types.str);
        };
        "serverAddress" = mkOption {
          description = "";
          type = (types.listOf types.str);
        };
      };

      config = { };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityRolesPrivileges" = {

      options = {
        "actions" = mkOption {
          description = "";
          type = (types.listOf types.str);
        };
        "resource" = mkOption {
          description = "Resource specifies specifies the resources upon which a privilege permits actions.\nSee https://www.mongodb.com/docs/manual/reference/resource-document for more.";
          type = (
            submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityRolesPrivilegesResource"
          );
        };
      };

      config = { };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityRolesPrivilegesResource" = {

      options = {
        "anyResource" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "cluster" = mkOption {
          description = "";
          type = (types.nullOr types.bool);
        };
        "collection" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "db" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "anyResource" = mkOverride 1002 null;
        "cluster" = mkOverride 1002 null;
        "collection" = mkOverride 1002 null;
        "db" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityRolesRoles" = {

      options = {
        "db" = mkOption {
          description = "DB is the database the role can act on";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name is the name of the role";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityTls" = {

      options = {
        "caCertificateSecretRef" = mkOption {
          description = "CaCertificateSecret is a reference to a Secret containing the certificate for the CA which signed the server certificates\nThe certificate is expected to be available under the key \"ca.crt\"";
          type = (
            types.nullOr (
              submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityTlsCaCertificateSecretRef"
            )
          );
        };
        "caConfigMapRef" = mkOption {
          description = "CaConfigMap is a reference to a ConfigMap containing the certificate for the CA which signed the server certificates\nThe certificate is expected to be available under the key \"ca.crt\"\nThis field is ignored when CaCertificateSecretRef is configured";
          type = (
            types.nullOr (
              submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityTlsCaConfigMapRef"
            )
          );
        };
        "certificateKeySecretRef" = mkOption {
          description = "CertificateKeySecret is a reference to a Secret containing a private key and certificate to use for TLS.\nThe key and cert are expected to be PEM encoded and available at \"tls.key\" and \"tls.crt\".\nThis is the same format used for the standard \"kubernetes.io/tls\" Secret type, but no specific type is required.\nAlternatively, an entry tls.pem, containing the concatenation of cert and key, can be provided.\nIf all of tls.pem, tls.crt and tls.key are present, the tls.pem one needs to be equal to the concatenation of tls.crt and tls.key";
          type = (
            types.nullOr (
              submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityTlsCertificateKeySecretRef"
            )
          );
        };
        "enabled" = mkOption {
          description = "";
          type = types.bool;
        };
        "optional" = mkOption {
          description = "Optional configures if TLS should be required or optional for connections";
          type = (types.nullOr types.bool);
        };
      };

      config = {
        "caCertificateSecretRef" = mkOverride 1002 null;
        "caConfigMapRef" = mkOverride 1002 null;
        "certificateKeySecretRef" = mkOverride 1002 null;
        "optional" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityTlsCaCertificateSecretRef" = {

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
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityTlsCaConfigMapRef" = {

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
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecSecurityTlsCertificateKeySecretRef" = {

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
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecStatefulSet" = {

      options = {
        "metadata" = mkOption {
          description = "StatefulSetMetadataWrapper is a wrapper around Labels and Annotations";
          type = (
            types.nullOr (submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecStatefulSetMetadata")
          );
        };
        "spec" = mkOption {
          description = "";
          type = types.attrs;
        };
      };

      config = {
        "metadata" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecStatefulSetMetadata" = {

      options = {
        "annotations" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "labels" = mkOption {
          description = "";
          type = (types.nullOr (types.attrsOf types.str));
        };
      };

      config = {
        "annotations" = mkOverride 1002 null;
        "labels" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecUsers" = {

      options = {
        "additionalConnectionStringConfig" = mkOption {
          description = "Additional options to be appended to the connection string.\nThese options apply only to this user and will override any existing options in the resource.";
          type = (types.nullOr types.attrs);
        };
        "connectionStringSecretAnnotations" = mkOption {
          description = "ConnectionStringSecretAnnotations is the annotations of the secret object created by the operator which exposes the connection strings for the user.";
          type = (types.nullOr (types.attrsOf types.str));
        };
        "connectionStringSecretName" = mkOption {
          description = "ConnectionStringSecretName is the name of the secret object created by the operator which exposes the connection strings for the user.\nIf provided, this secret must be different for each user in a deployment.";
          type = (types.nullOr types.str);
        };
        "connectionStringSecretNamespace" = mkOption {
          description = "ConnectionStringSecretNamespace is the namespace of the secret object created by the operator which exposes the connection strings for the user.";
          type = (types.nullOr types.str);
        };
        "db" = mkOption {
          description = "DB is the database the user is stored in. Defaults to \"admin\"";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "Name is the username of the user";
          type = types.str;
        };
        "passwordSecretRef" = mkOption {
          description = "PasswordSecretRef is a reference to the secret containing this user's password";
          type = (
            types.nullOr (
              submoduleOf "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecUsersPasswordSecretRef"
            )
          );
        };
        "roles" = mkOption {
          description = "Roles is an array of roles assigned to this user";
          type = (
            coerceAttrsOfSubmodulesToListByKey "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecUsersRoles"
              "name"
              [ ]
          );
          apply = attrsToList;
        };
        "scramCredentialsSecretName" = mkOption {
          description = "ScramCredentialsSecretName appended by string \"scram-credentials\" is the name of the secret object created by the mongoDB operator for storing SCRAM credentials\nThese secrets names must be different for each user in a deployment.";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "additionalConnectionStringConfig" = mkOverride 1002 null;
        "connectionStringSecretAnnotations" = mkOverride 1002 null;
        "connectionStringSecretName" = mkOverride 1002 null;
        "connectionStringSecretNamespace" = mkOverride 1002 null;
        "db" = mkOverride 1002 null;
        "passwordSecretRef" = mkOverride 1002 null;
        "scramCredentialsSecretName" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecUsersPasswordSecretRef" = {

      options = {
        "key" = mkOption {
          description = "Key is the key in the secret storing this password. Defaults to \"password\"";
          type = (types.nullOr types.str);
        };
        "name" = mkOption {
          description = "Name is the name of the secret storing this user's password";
          type = types.str;
        };
      };

      config = {
        "key" = mkOverride 1002 null;
      };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunitySpecUsersRoles" = {

      options = {
        "db" = mkOption {
          description = "DB is the database the role can act on";
          type = types.str;
        };
        "name" = mkOption {
          description = "Name is the name of the role";
          type = types.str;
        };
      };

      config = { };

    };
    "mongodbcommunity.mongodb.com.v1.MongoDBCommunityStatus" = {

      options = {
        "currentMongoDBArbiters" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "currentMongoDBMembers" = mkOption {
          description = "";
          type = types.int;
        };
        "currentStatefulSetArbitersReplicas" = mkOption {
          description = "";
          type = (types.nullOr types.int);
        };
        "currentStatefulSetReplicas" = mkOption {
          description = "";
          type = types.int;
        };
        "message" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
        "mongoUri" = mkOption {
          description = "";
          type = types.str;
        };
        "phase" = mkOption {
          description = "";
          type = types.str;
        };
        "version" = mkOption {
          description = "";
          type = (types.nullOr types.str);
        };
      };

      config = {
        "currentMongoDBArbiters" = mkOverride 1002 null;
        "currentStatefulSetArbitersReplicas" = mkOverride 1002 null;
        "message" = mkOverride 1002 null;
        "version" = mkOverride 1002 null;
      };

    };

  };
in
{
  # all resource versions
  options = {
    resources = {
      "mongodb.com"."v1"."ClusterMongoDBRole" = mkOption {
        description = "ClusterMongoDBRole is the Schema for the clustermongodbroles API.";
        type = (
          types.attrsOf (
            submoduleForDefinition "mongodb.com.v1.ClusterMongoDBRole" "clustermongodbroles"
              "ClusterMongoDBRole"
              "mongodb.com"
              "v1"
          )
        );
        default = { };
      };
      "mongodb.com"."v1"."MongoDB" = mkOption {
        description = "";
        type = (
          types.attrsOf (
            submoduleForDefinition "mongodb.com.v1.MongoDB" "mongodb" "MongoDB" "mongodb.com" "v1"
          )
        );
        default = { };
      };
      "mongodb.com"."v1"."MongoDBMultiCluster" = mkOption {
        description = "";
        type = (
          types.attrsOf (
            submoduleForDefinition "mongodb.com.v1.MongoDBMultiCluster" "mongodbmulticluster"
              "MongoDBMultiCluster"
              "mongodb.com"
              "v1"
          )
        );
        default = { };
      };
      "mongodb.com"."v1"."MongoDBOpsManager" = mkOption {
        description = "The MongoDBOpsManager resource allows you to deploy Ops Manager within your Kubernetes cluster";
        type = (
          types.attrsOf (
            submoduleForDefinition "mongodb.com.v1.MongoDBOpsManager" "opsmanagers" "MongoDBOpsManager"
              "mongodb.com"
              "v1"
          )
        );
        default = { };
      };
      "mongodb.com"."v1"."MongoDBSearch" = mkOption {
        description = "";
        type = (
          types.attrsOf (
            submoduleForDefinition "mongodb.com.v1.MongoDBSearch" "mongodbsearch" "MongoDBSearch" "mongodb.com"
              "v1"
          )
        );
        default = { };
      };
      "mongodb.com"."v1"."MongoDBUser" = mkOption {
        description = "";
        type = (
          types.attrsOf (
            submoduleForDefinition "mongodb.com.v1.MongoDBUser" "mongodbusers" "MongoDBUser" "mongodb.com" "v1"
          )
        );
        default = { };
      };
      "mongodbcommunity.mongodb.com"."v1"."MongoDBCommunity" = mkOption {
        description = "MongoDBCommunity is the Schema for the mongodbs API";
        type = (
          types.attrsOf (
            submoduleForDefinition "mongodbcommunity.mongodb.com.v1.MongoDBCommunity" "mongodbcommunity"
              "MongoDBCommunity"
              "mongodbcommunity.mongodb.com"
              "v1"
          )
        );
        default = { };
      };

    }
    // {
      "clusterMongoDBRoles" = mkOption {
        description = "ClusterMongoDBRole is the Schema for the clustermongodbroles API.";
        type = (
          types.attrsOf (
            submoduleForDefinition "mongodb.com.v1.ClusterMongoDBRole" "clustermongodbroles"
              "ClusterMongoDBRole"
              "mongodb.com"
              "v1"
          )
        );
        default = { };
      };
      "mongoDB" = mkOption {
        description = "";
        type = (
          types.attrsOf (
            submoduleForDefinition "mongodb.com.v1.MongoDB" "mongodb" "MongoDB" "mongodb.com" "v1"
          )
        );
        default = { };
      };
      "mongoDBCommunity" = mkOption {
        description = "MongoDBCommunity is the Schema for the mongodbs API";
        type = (
          types.attrsOf (
            submoduleForDefinition "mongodbcommunity.mongodb.com.v1.MongoDBCommunity" "mongodbcommunity"
              "MongoDBCommunity"
              "mongodbcommunity.mongodb.com"
              "v1"
          )
        );
        default = { };
      };
      "mongoDBMultiCluster" = mkOption {
        description = "";
        type = (
          types.attrsOf (
            submoduleForDefinition "mongodb.com.v1.MongoDBMultiCluster" "mongodbmulticluster"
              "MongoDBMultiCluster"
              "mongodb.com"
              "v1"
          )
        );
        default = { };
      };
      "mopsmanagers" = mkOption {
        description = "The MongoDBOpsManager resource allows you to deploy Ops Manager within your Kubernetes cluster";
        type = (
          types.attrsOf (
            submoduleForDefinition "mongodb.com.v1.MongoDBOpsManager" "opsmanagers" "MongoDBOpsManager"
              "mongodb.com"
              "v1"
          )
        );
        default = { };
      };
      "mongoDBSearch" = mkOption {
        description = "";
        type = (
          types.attrsOf (
            submoduleForDefinition "mongodb.com.v1.MongoDBSearch" "mongodbsearch" "MongoDBSearch" "mongodb.com"
              "v1"
          )
        );
        default = { };
      };
      "mongoDBUsers" = mkOption {
        description = "";
        type = (
          types.attrsOf (
            submoduleForDefinition "mongodb.com.v1.MongoDBUser" "mongodbusers" "MongoDBUser" "mongodb.com" "v1"
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
        name = "clustermongodbroles";
        group = "mongodb.com";
        version = "v1";
        kind = "ClusterMongoDBRole";
        attrName = "clusterMongoDBRoles";
      }
      {
        name = "mongodb";
        group = "mongodb.com";
        version = "v1";
        kind = "MongoDB";
        attrName = "mongoDB";
      }
      {
        name = "mongodbmulticluster";
        group = "mongodb.com";
        version = "v1";
        kind = "MongoDBMultiCluster";
        attrName = "mongoDBMultiCluster";
      }
      {
        name = "opsmanagers";
        group = "mongodb.com";
        version = "v1";
        kind = "MongoDBOpsManager";
        attrName = "mopsmanagers";
      }
      {
        name = "mongodbsearch";
        group = "mongodb.com";
        version = "v1";
        kind = "MongoDBSearch";
        attrName = "mongoDBSearch";
      }
      {
        name = "mongodbusers";
        group = "mongodb.com";
        version = "v1";
        kind = "MongoDBUser";
        attrName = "mongoDBUsers";
      }
      {
        name = "mongodbcommunity";
        group = "mongodbcommunity.mongodb.com";
        version = "v1";
        kind = "MongoDBCommunity";
        attrName = "mongoDBCommunity";
      }
    ];

    resources = {
      "mongodb.com"."v1"."ClusterMongoDBRole" =
        mkAliasDefinitions
          options.resources."clusterMongoDBRoles";
      "mongodb.com"."v1"."MongoDB" = mkAliasDefinitions options.resources."mongoDB";
      "mongodbcommunity.mongodb.com"."v1"."MongoDBCommunity" =
        mkAliasDefinitions
          options.resources."mongoDBCommunity";
      "mongodb.com"."v1"."MongoDBMultiCluster" =
        mkAliasDefinitions
          options.resources."mongoDBMultiCluster";
      "mongodb.com"."v1"."MongoDBOpsManager" = mkAliasDefinitions options.resources."mopsmanagers";
      "mongodb.com"."v1"."MongoDBSearch" = mkAliasDefinitions options.resources."mongoDBSearch";
      "mongodb.com"."v1"."MongoDBUser" = mkAliasDefinitions options.resources."mongoDBUsers";

    };

    # make all namespaced resources default to the
    # application's namespace
    defaults = [
      {
        group = "mongodb.com";
        version = "v1";
        kind = "MongoDB";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "mongodb.com";
        version = "v1";
        kind = "MongoDBMultiCluster";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "mongodb.com";
        version = "v1";
        kind = "MongoDBOpsManager";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "mongodb.com";
        version = "v1";
        kind = "MongoDBSearch";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "mongodb.com";
        version = "v1";
        kind = "MongoDBUser";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
      {
        group = "mongodbcommunity.mongodb.com";
        version = "v1";
        kind = "MongoDBCommunity";
        default.metadata.namespace = lib.mkDefault config.namespace;
      }
    ];
  };
}
