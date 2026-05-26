# RDS Full Discovery Data (2026-02-23)

All data captured via AWS CLI. This file is the single source of truth for the RDS import task.

---

## 1. AURORA CLUSTERS (Full JSON)

### 1.1 production-app-2 (Environment: shared-001)

```json
{
    "AllocatedStorage": 1,
    "AvailabilityZones": ["us-east-1c", "us-east-1a", "us-east-1b"],
    "BackupRetentionPeriod": 7,
    "DatabaseName": "",
    "DBClusterIdentifier": "production-app-2",
    "DBClusterParameterGroup": "aurora-postgresql15",
    "DBSubnetGroup": "default-vpc-0204a1f8b5de51941",
    "Status": "available",
    "Endpoint": "production-app-2.cluster-cvw5l7p4adp1.us-east-1.rds.amazonaws.com",
    "ReaderEndpoint": "production-app-2.cluster-ro-cvw5l7p4adp1.us-east-1.rds.amazonaws.com",
    "MultiAZ": true,
    "Engine": "aurora-postgresql",
    "EngineVersion": "15.13",
    "Port": 5432,
    "MasterUsername": "postgres",
    "PreferredBackupWindow": "08:19-08:49",
    "PreferredMaintenanceWindow": "sun:13:00-sun:13:30",
    "ReadReplicaIdentifiers": [],
    "DBClusterMembers": [
        {"DBInstanceIdentifier": "production-app-2-instance-1", "IsClusterWriter": false, "DBClusterParameterGroupStatus": "in-sync", "PromotionTier": 1},
        {"DBInstanceIdentifier": "production-app-2-instance-1-us-east-1b", "IsClusterWriter": true, "DBClusterParameterGroupStatus": "in-sync", "PromotionTier": 1}
    ],
    "VpcSecurityGroups": [{"VpcSecurityGroupId": "sg-05ff12e712f05682f", "Status": "active"}],
    "HostedZoneId": "Z2R2ITUGPM61AM",
    "StorageEncrypted": true,
    "KmsKeyId": "arn:aws:kms:us-east-1:405749097490:key/64b7af79-2853-46e9-b11a-3682cf0cf60c",
    "DbClusterResourceId": "cluster-ISQ3MSUZ7WFUBRU6ZKZG3ZSGYQ",
    "DBClusterArn": "arn:aws:rds:us-east-1:405749097490:cluster:production-app-2",
    "AssociatedRoles": [],
    "IAMDatabaseAuthenticationEnabled": false,
    "ClusterCreateTime": "2020-08-29T23:23:21.120000+00:00",
    "EnabledCloudwatchLogsExports": ["postgresql"],
    "EngineMode": "provisioned",
    "DeletionProtection": true,
    "HttpEndpointEnabled": false,
    "ActivityStreamStatus": "stopped",
    "CopyTagsToSnapshot": true,
    "CrossAccountClone": false,
    "DomainMemberships": [],
    "TagList": [],
    "AutoMinorVersionUpgrade": true,
    "DatabaseInsightsMode": "standard",
    "NetworkType": "IPV4",
    "LocalWriteForwardingStatus": "disabled",
    "EngineLifecycleSupport": "open-source-rds-extended-support"
}
```

### 1.2 demo-prd (Environment: demo-001)

```json
{
    "AllocatedStorage": 1,
    "AvailabilityZones": ["us-east-1c", "us-east-1a", "us-east-1b"],
    "BackupRetentionPeriod": 1,
    "DatabaseName": "",
    "DBClusterIdentifier": "demo-prd",
    "DBClusterParameterGroup": "aurora-postgresql16",
    "DBSubnetGroup": "default-vpc-0204a1f8b5de51941",
    "Status": "available",
    "Endpoint": "demo-prd.cluster-cvw5l7p4adp1.us-east-1.rds.amazonaws.com",
    "ReaderEndpoint": "demo-prd.cluster-ro-cvw5l7p4adp1.us-east-1.rds.amazonaws.com",
    "MultiAZ": false,
    "Engine": "aurora-postgresql",
    "EngineVersion": "16.9",
    "Port": 5432,
    "MasterUsername": "postgres",
    "PreferredBackupWindow": "05:00-05:30",
    "PreferredMaintenanceWindow": "sat:13:00-sat:13:30",
    "ReadReplicaIdentifiers": [],
    "DBClusterMembers": [
        {"DBInstanceIdentifier": "demo-prd-instance-1", "IsClusterWriter": true, "DBClusterParameterGroupStatus": "in-sync", "PromotionTier": 1}
    ],
    "VpcSecurityGroups": [{"VpcSecurityGroupId": "sg-0be66cff163cf3805", "Status": "active"}],
    "HostedZoneId": "Z2R2ITUGPM61AM",
    "StorageEncrypted": true,
    "KmsKeyId": "arn:aws:kms:us-east-1:405749097490:key/64b7af79-2853-46e9-b11a-3682cf0cf60c",
    "DbClusterResourceId": "cluster-46D637ZTUACOQRPEJHUMKJQF6Q",
    "DBClusterArn": "arn:aws:rds:us-east-1:405749097490:cluster:demo-prd",
    "AssociatedRoles": [],
    "IAMDatabaseAuthenticationEnabled": false,
    "ClusterCreateTime": "2020-08-29T15:52:39.284000+00:00",
    "EnabledCloudwatchLogsExports": ["postgresql"],
    "EngineMode": "provisioned",
    "DeletionProtection": true,
    "HttpEndpointEnabled": false,
    "ActivityStreamStatus": "stopped",
    "CopyTagsToSnapshot": true,
    "CrossAccountClone": false,
    "DomainMemberships": [],
    "TagList": [],
    "AutoMinorVersionUpgrade": true,
    "DatabaseInsightsMode": "standard",
    "NetworkType": "IPV4",
    "LocalWriteForwardingStatus": "disabled",
    "EngineLifecycleSupport": "open-source-rds-extended-support"
}
```

### 1.3 atento-001-app-cluster-cluster (Environment: atento-001)

```json
{
    "AllocatedStorage": 1,
    "AvailabilityZones": ["us-east-1c", "us-east-1a", "us-east-1b"],
    "BackupRetentionPeriod": 7,
    "DatabaseName": "",
    "DBClusterIdentifier": "atento-001-app-cluster-cluster",
    "DBClusterParameterGroup": "aurora-postgresql15",
    "DBSubnetGroup": "subnet-group-4app-atento-public",
    "Status": "available",
    "Endpoint": "atento-001-app-cluster-cluster.cluster-cvw5l7p4adp1.us-east-1.rds.amazonaws.com",
    "ReaderEndpoint": "atento-001-app-cluster-cluster.cluster-ro-cvw5l7p4adp1.us-east-1.rds.amazonaws.com",
    "MultiAZ": true,
    "Engine": "aurora-postgresql",
    "EngineVersion": "15.13",
    "Port": 5432,
    "MasterUsername": "postgres",
    "PreferredBackupWindow": "08:19-08:49",
    "PreferredMaintenanceWindow": "sun:13:00-sun:13:30",
    "ReadReplicaIdentifiers": [],
    "DBClusterMembers": [
        {"DBInstanceIdentifier": "atento-001-app-cluster", "IsClusterWriter": true, "DBClusterParameterGroupStatus": "in-sync", "PromotionTier": 1},
        {"DBInstanceIdentifier": "atento-001-app-ro", "IsClusterWriter": false, "DBClusterParameterGroupStatus": "in-sync", "PromotionTier": 1}
    ],
    "VpcSecurityGroups": [{"VpcSecurityGroupId": "sg-0ddb2a65901bac264", "Status": "active"}],
    "HostedZoneId": "Z2R2ITUGPM61AM",
    "StorageEncrypted": true,
    "KmsKeyId": "arn:aws:kms:us-east-1:405749097490:key/64b7af79-2853-46e9-b11a-3682cf0cf60c",
    "DbClusterResourceId": "cluster-XCXSWROK4JUDJATFFUGEDF47WY",
    "DBClusterArn": "arn:aws:rds:us-east-1:405749097490:cluster:atento-001-app-cluster-cluster",
    "AssociatedRoles": [],
    "IAMDatabaseAuthenticationEnabled": false,
    "ClusterCreateTime": "2024-12-01T14:53:44.756000+00:00",
    "EnabledCloudwatchLogsExports": null,
    "EngineMode": "provisioned",
    "DeletionProtection": true,
    "HttpEndpointEnabled": false,
    "ActivityStreamStatus": "stopped",
    "CopyTagsToSnapshot": true,
    "CrossAccountClone": false,
    "DomainMemberships": [],
    "TagList": [],
    "AutoMinorVersionUpgrade": true,
    "DatabaseInsightsMode": "standard",
    "NetworkType": "IPV4",
    "LocalWriteForwardingStatus": "disabled",
    "EngineLifecycleSupport": "open-source-rds-extended-support-disabled"
}
```

---

## 2. AURORA INSTANCES (Full JSON)

### 2.1 production-app-2-instance-1 (reader, shared-001)

```json
{
    "DBInstanceIdentifier": "production-app-2-instance-1",
    "DBInstanceClass": "db.t4g.large",
    "Engine": "aurora-postgresql",
    "DBInstanceStatus": "available",
    "MasterUsername": "postgres",
    "Endpoint": {"Address": "production-app-2-instance-1.cvw5l7p4adp1.us-east-1.rds.amazonaws.com", "Port": 5432, "HostedZoneId": "Z2R2ITUGPM61AM"},
    "AllocatedStorage": 1,
    "InstanceCreateTime": "2020-08-29T23:27:42.180000+00:00",
    "PreferredBackupWindow": "08:19-08:49",
    "BackupRetentionPeriod": 7,
    "DBSecurityGroups": [],
    "VpcSecurityGroups": [{"VpcSecurityGroupId": "sg-05ff12e712f05682f", "Status": "active"}],
    "DBParameterGroups": [{"DBParameterGroupName": "default.aurora-postgresql15", "ParameterApplyStatus": "in-sync"}],
    "AvailabilityZone": "us-east-1a",
    "DBSubnetGroup": {
        "DBSubnetGroupName": "default-vpc-0204a1f8b5de51941",
        "DBSubnetGroupDescription": "Created from the RDS Management Console",
        "VpcId": "vpc-0204a1f8b5de51941",
        "SubnetGroupStatus": "Complete",
        "Subnets": [
            {"SubnetIdentifier": "subnet-049885e873eca0ef5", "SubnetAvailabilityZone": {"Name": "us-east-1b"}},
            {"SubnetIdentifier": "subnet-06eba9179753e73bf", "SubnetAvailabilityZone": {"Name": "us-east-1a"}}
        ]
    },
    "PreferredMaintenanceWindow": "sun:07:00-sun:07:30",
    "PendingModifiedValues": {},
    "MultiAZ": false,
    "EngineVersion": "15.13",
    "AutoMinorVersionUpgrade": true,
    "ReadReplicaDBInstanceIdentifiers": [],
    "LicenseModel": "postgresql-license",
    "OptionGroupMemberships": [{"OptionGroupName": "default:aurora-postgresql-15", "Status": "in-sync"}],
    "PubliclyAccessible": true,
    "StorageType": "aurora",
    "DbInstancePort": 0,
    "DBClusterIdentifier": "production-app-2",
    "StorageEncrypted": true,
    "KmsKeyId": "arn:aws:kms:us-east-1:405749097490:key/64b7af79-2853-46e9-b11a-3682cf0cf60c",
    "DbiResourceId": "db-OD4OGFPMHBESTIFWXSZJJBZMIA",
    "CACertificateIdentifier": "rds-ca-rsa2048-g1",
    "DomainMemberships": [],
    "CopyTagsToSnapshot": false,
    "MonitoringInterval": 60,
    "EnhancedMonitoringResourceArn": "arn:aws:logs:us-east-1:405749097490:log-group:RDSOSMetrics:log-stream:db-OD4OGFPMHBESTIFWXSZJJBZMIA",
    "MonitoringRoleArn": "arn:aws:iam::405749097490:role/rds-monitoring-role",
    "PromotionTier": 1,
    "DBInstanceArn": "arn:aws:rds:us-east-1:405749097490:db:production-app-2-instance-1",
    "IAMDatabaseAuthenticationEnabled": false,
    "DatabaseInsightsMode": "standard",
    "PerformanceInsightsEnabled": true,
    "PerformanceInsightsKMSKeyId": "arn:aws:kms:us-east-1:405749097490:key/64b7af79-2853-46e9-b11a-3682cf0cf60c",
    "PerformanceInsightsRetentionPeriod": 7,
    "EnabledCloudwatchLogsExports": ["postgresql"],
    "DeletionProtection": false,
    "AssociatedRoles": [],
    "TagList": [],
    "CustomerOwnedIpEnabled": false,
    "BackupTarget": "region",
    "NetworkType": "IPV4",
    "CertificateDetails": {"CAIdentifier": "rds-ca-rsa2048-g1", "ValidTill": "2027-01-11T07:00:03+00:00"},
    "DedicatedLogVolume": false,
    "EngineLifecycleSupport": "open-source-rds-extended-support"
}
```

### 2.2 production-app-2-instance-1-us-east-1b (writer, shared-001)

```json
{
    "DBInstanceIdentifier": "production-app-2-instance-1-us-east-1b",
    "DBInstanceClass": "db.t4g.large",
    "Engine": "aurora-postgresql",
    "DBInstanceStatus": "available",
    "MasterUsername": "postgres",
    "Endpoint": {"Address": "production-app-2-instance-1-us-east-1b.cvw5l7p4adp1.us-east-1.rds.amazonaws.com", "Port": 5432, "HostedZoneId": "Z2R2ITUGPM61AM"},
    "AllocatedStorage": 1,
    "InstanceCreateTime": "2020-08-29T23:34:24.849000+00:00",
    "PreferredBackupWindow": "08:19-08:49",
    "BackupRetentionPeriod": 7,
    "DBSecurityGroups": [],
    "VpcSecurityGroups": [{"VpcSecurityGroupId": "sg-05ff12e712f05682f", "Status": "active"}],
    "DBParameterGroups": [{"DBParameterGroupName": "default.aurora-postgresql15", "ParameterApplyStatus": "in-sync"}],
    "AvailabilityZone": "us-east-1b",
    "DBSubnetGroup": {
        "DBSubnetGroupName": "default-vpc-0204a1f8b5de51941",
        "DBSubnetGroupDescription": "Created from the RDS Management Console",
        "VpcId": "vpc-0204a1f8b5de51941",
        "SubnetGroupStatus": "Complete",
        "Subnets": [
            {"SubnetIdentifier": "subnet-049885e873eca0ef5", "SubnetAvailabilityZone": {"Name": "us-east-1b"}},
            {"SubnetIdentifier": "subnet-06eba9179753e73bf", "SubnetAvailabilityZone": {"Name": "us-east-1a"}}
        ]
    },
    "PreferredMaintenanceWindow": "thu:05:12-thu:05:42",
    "PendingModifiedValues": {},
    "MultiAZ": false,
    "EngineVersion": "15.13",
    "AutoMinorVersionUpgrade": true,
    "ReadReplicaDBInstanceIdentifiers": [],
    "LicenseModel": "postgresql-license",
    "OptionGroupMemberships": [{"OptionGroupName": "default:aurora-postgresql-15", "Status": "in-sync"}],
    "PubliclyAccessible": true,
    "StorageType": "aurora",
    "DbInstancePort": 0,
    "DBClusterIdentifier": "production-app-2",
    "StorageEncrypted": true,
    "KmsKeyId": "arn:aws:kms:us-east-1:405749097490:key/64b7af79-2853-46e9-b11a-3682cf0cf60c",
    "DbiResourceId": "db-FZM6FCG4DLCK46BTCKC2X46DOI",
    "CACertificateIdentifier": "rds-ca-rsa2048-g1",
    "DomainMemberships": [],
    "CopyTagsToSnapshot": false,
    "MonitoringInterval": 60,
    "EnhancedMonitoringResourceArn": "arn:aws:logs:us-east-1:405749097490:log-group:RDSOSMetrics:log-stream:db-FZM6FCG4DLCK46BTCKC2X46DOI",
    "MonitoringRoleArn": "arn:aws:iam::405749097490:role/rds-monitoring-role",
    "PromotionTier": 1,
    "DBInstanceArn": "arn:aws:rds:us-east-1:405749097490:db:production-app-2-instance-1-us-east-1b",
    "IAMDatabaseAuthenticationEnabled": false,
    "DatabaseInsightsMode": "standard",
    "PerformanceInsightsEnabled": true,
    "PerformanceInsightsKMSKeyId": "arn:aws:kms:us-east-1:405749097490:key/64b7af79-2853-46e9-b11a-3682cf0cf60c",
    "PerformanceInsightsRetentionPeriod": 7,
    "EnabledCloudwatchLogsExports": ["postgresql"],
    "DeletionProtection": false,
    "AssociatedRoles": [],
    "TagList": [],
    "CustomerOwnedIpEnabled": false,
    "BackupTarget": "region",
    "NetworkType": "IPV4",
    "CertificateDetails": {"CAIdentifier": "rds-ca-rsa2048-g1", "ValidTill": "2027-01-08T05:12:03+00:00"},
    "DedicatedLogVolume": false,
    "EngineLifecycleSupport": "open-source-rds-extended-support"
}
```

### 2.3 demo-prd-instance-1 (writer, demo-001)

```json
{
    "DBInstanceIdentifier": "demo-prd-instance-1",
    "DBInstanceClass": "db.t3.medium",
    "Engine": "aurora-postgresql",
    "DBInstanceStatus": "available",
    "MasterUsername": "postgres",
    "Endpoint": {"Address": "demo-prd-instance-1.cvw5l7p4adp1.us-east-1.rds.amazonaws.com", "Port": 5432, "HostedZoneId": "Z2R2ITUGPM61AM"},
    "AllocatedStorage": 1,
    "InstanceCreateTime": "2020-08-29T15:57:27.381000+00:00",
    "PreferredBackupWindow": "05:00-05:30",
    "BackupRetentionPeriod": 1,
    "DBSecurityGroups": [],
    "VpcSecurityGroups": [{"VpcSecurityGroupId": "sg-0be66cff163cf3805", "Status": "active"}],
    "DBParameterGroups": [{"DBParameterGroupName": "default.aurora-postgresql16", "ParameterApplyStatus": "in-sync"}],
    "AvailabilityZone": "us-east-1a",
    "DBSubnetGroup": {
        "DBSubnetGroupName": "default-vpc-0204a1f8b5de51941",
        "DBSubnetGroupDescription": "Created from the RDS Management Console",
        "VpcId": "vpc-0204a1f8b5de51941",
        "SubnetGroupStatus": "Complete",
        "Subnets": [
            {"SubnetIdentifier": "subnet-049885e873eca0ef5", "SubnetAvailabilityZone": {"Name": "us-east-1b"}},
            {"SubnetIdentifier": "subnet-06eba9179753e73bf", "SubnetAvailabilityZone": {"Name": "us-east-1a"}}
        ]
    },
    "PreferredMaintenanceWindow": "tue:08:10-tue:08:40",
    "PendingModifiedValues": {},
    "MultiAZ": false,
    "EngineVersion": "16.9",
    "AutoMinorVersionUpgrade": true,
    "ReadReplicaDBInstanceIdentifiers": [],
    "LicenseModel": "postgresql-license",
    "OptionGroupMemberships": [{"OptionGroupName": "default:aurora-postgresql-16", "Status": "in-sync"}],
    "PubliclyAccessible": false,
    "StorageType": "aurora",
    "DbInstancePort": 0,
    "DBClusterIdentifier": "demo-prd",
    "StorageEncrypted": true,
    "KmsKeyId": "arn:aws:kms:us-east-1:405749097490:key/64b7af79-2853-46e9-b11a-3682cf0cf60c",
    "DbiResourceId": "db-XIVMSKU5VGWXZF7WYQWCAPWUTM",
    "CACertificateIdentifier": "rds-ca-rsa2048-g1",
    "DomainMemberships": [],
    "CopyTagsToSnapshot": false,
    "MonitoringInterval": 60,
    "EnhancedMonitoringResourceArn": "arn:aws:logs:us-east-1:405749097490:log-group:RDSOSMetrics:log-stream:db-XIVMSKU5VGWXZF7WYQWCAPWUTM",
    "MonitoringRoleArn": "arn:aws:iam::405749097490:role/rds-monitoring-role",
    "PromotionTier": 1,
    "DBInstanceArn": "arn:aws:rds:us-east-1:405749097490:db:demo-prd-instance-1",
    "IAMDatabaseAuthenticationEnabled": false,
    "DatabaseInsightsMode": "standard",
    "PerformanceInsightsEnabled": true,
    "PerformanceInsightsKMSKeyId": "arn:aws:kms:us-east-1:405749097490:key/64b7af79-2853-46e9-b11a-3682cf0cf60c",
    "PerformanceInsightsRetentionPeriod": 7,
    "EnabledCloudwatchLogsExports": ["postgresql"],
    "DeletionProtection": false,
    "AssociatedRoles": [],
    "TagList": [],
    "CustomerOwnedIpEnabled": false,
    "BackupTarget": "region",
    "NetworkType": "IPV4",
    "CertificateDetails": {"CAIdentifier": "rds-ca-rsa2048-g1", "ValidTill": "2027-02-17T08:10:04+00:00"},
    "DedicatedLogVolume": false,
    "EngineLifecycleSupport": "open-source-rds-extended-support"
}
```

### 2.4 atento-001-app-cluster (writer, atento-001)

```json
{
    "DBInstanceIdentifier": "atento-001-app-cluster",
    "DBInstanceClass": "db.t4g.large",
    "Engine": "aurora-postgresql",
    "DBInstanceStatus": "available",
    "MasterUsername": "postgres",
    "Endpoint": {"Address": "atento-001-app-cluster.cvw5l7p4adp1.us-east-1.rds.amazonaws.com", "Port": 5432, "HostedZoneId": "Z2R2ITUGPM61AM"},
    "AllocatedStorage": 1,
    "InstanceCreateTime": "2024-12-01T15:20:28.717000+00:00",
    "PreferredBackupWindow": "08:19-08:49",
    "BackupRetentionPeriod": 7,
    "DBSecurityGroups": [],
    "VpcSecurityGroups": [{"VpcSecurityGroupId": "sg-0ddb2a65901bac264", "Status": "active"}],
    "DBParameterGroups": [{"DBParameterGroupName": "default.aurora-postgresql15", "ParameterApplyStatus": "in-sync"}],
    "AvailabilityZone": "us-east-1a",
    "DBSubnetGroup": {
        "DBSubnetGroupName": "subnet-group-4app-atento-public",
        "DBSubnetGroupDescription": "subnet-group-4app-atento-public",
        "VpcId": "vpc-0331320cef3e08143",
        "SubnetGroupStatus": "Complete",
        "Subnets": [
            {"SubnetIdentifier": "subnet-07019f3ad3f31041a", "SubnetAvailabilityZone": {"Name": "us-east-1a"}},
            {"SubnetIdentifier": "subnet-0d7dad52f3c722622", "SubnetAvailabilityZone": {"Name": "us-east-1b"}}
        ]
    },
    "PreferredMaintenanceWindow": "sat:06:44-sat:07:14",
    "PendingModifiedValues": {},
    "MultiAZ": false,
    "EngineVersion": "15.13",
    "AutoMinorVersionUpgrade": true,
    "ReadReplicaDBInstanceIdentifiers": [],
    "LicenseModel": "postgresql-license",
    "OptionGroupMemberships": [{"OptionGroupName": "default:aurora-postgresql-15", "Status": "in-sync"}],
    "PubliclyAccessible": true,
    "StorageType": "aurora",
    "DbInstancePort": 0,
    "DBClusterIdentifier": "atento-001-app-cluster-cluster",
    "StorageEncrypted": true,
    "KmsKeyId": "arn:aws:kms:us-east-1:405749097490:key/64b7af79-2853-46e9-b11a-3682cf0cf60c",
    "DbiResourceId": "db-Y7PFJXE7YPUYQVYF7J2FE5LZ2A",
    "CACertificateIdentifier": "rds-ca-rsa2048-g1",
    "DomainMemberships": [],
    "CopyTagsToSnapshot": false,
    "MonitoringInterval": 0,
    "PromotionTier": 1,
    "DBInstanceArn": "arn:aws:rds:us-east-1:405749097490:db:atento-001-app-cluster",
    "IAMDatabaseAuthenticationEnabled": false,
    "DatabaseInsightsMode": "standard",
    "PerformanceInsightsEnabled": true,
    "PerformanceInsightsKMSKeyId": "arn:aws:kms:us-east-1:405749097490:key/64b7af79-2853-46e9-b11a-3682cf0cf60c",
    "PerformanceInsightsRetentionPeriod": 7,
    "EnabledCloudwatchLogsExports": null,
    "DeletionProtection": false,
    "AssociatedRoles": [],
    "TagList": [],
    "CustomerOwnedIpEnabled": false,
    "BackupTarget": "region",
    "NetworkType": "IPV4",
    "StorageThroughput": 0,
    "CertificateDetails": {"CAIdentifier": "rds-ca-rsa2048-g1", "ValidTill": "2026-12-13T06:44:11+00:00"},
    "DedicatedLogVolume": false,
    "EngineLifecycleSupport": "open-source-rds-extended-support-disabled"
}
```

### 2.5 atento-001-app-ro (reader, atento-001)

```json
{
    "DBInstanceIdentifier": "atento-001-app-ro",
    "DBInstanceClass": "db.t4g.large",
    "Engine": "aurora-postgresql",
    "DBInstanceStatus": "available",
    "MasterUsername": "postgres",
    "Endpoint": {"Address": "atento-001-app-ro.cvw5l7p4adp1.us-east-1.rds.amazonaws.com", "Port": 5432, "HostedZoneId": "Z2R2ITUGPM61AM"},
    "AllocatedStorage": 1,
    "InstanceCreateTime": "2024-12-01T17:40:30.598000+00:00",
    "PreferredBackupWindow": "08:19-08:49",
    "BackupRetentionPeriod": 7,
    "DBSecurityGroups": [],
    "VpcSecurityGroups": [{"VpcSecurityGroupId": "sg-0ddb2a65901bac264", "Status": "active"}],
    "DBParameterGroups": [{"DBParameterGroupName": "default.aurora-postgresql15", "ParameterApplyStatus": "in-sync"}],
    "AvailabilityZone": "us-east-1b",
    "DBSubnetGroup": {
        "DBSubnetGroupName": "subnet-group-4app-atento-public",
        "DBSubnetGroupDescription": "subnet-group-4app-atento-public",
        "VpcId": "vpc-0331320cef3e08143",
        "SubnetGroupStatus": "Complete",
        "Subnets": [
            {"SubnetIdentifier": "subnet-07019f3ad3f31041a", "SubnetAvailabilityZone": {"Name": "us-east-1a"}},
            {"SubnetIdentifier": "subnet-0d7dad52f3c722622", "SubnetAvailabilityZone": {"Name": "us-east-1b"}}
        ]
    },
    "PreferredMaintenanceWindow": "sat:06:44-sat:07:14",
    "PendingModifiedValues": {},
    "MultiAZ": false,
    "EngineVersion": "15.13",
    "AutoMinorVersionUpgrade": true,
    "ReadReplicaDBInstanceIdentifiers": [],
    "LicenseModel": "postgresql-license",
    "OptionGroupMemberships": [{"OptionGroupName": "default:aurora-postgresql-15", "Status": "in-sync"}],
    "PubliclyAccessible": true,
    "StorageType": "aurora",
    "DbInstancePort": 0,
    "DBClusterIdentifier": "atento-001-app-cluster-cluster",
    "StorageEncrypted": true,
    "KmsKeyId": "arn:aws:kms:us-east-1:405749097490:key/64b7af79-2853-46e9-b11a-3682cf0cf60c",
    "DbiResourceId": "db-VQRHW3V6QELBSUOLKADC5BCVGU",
    "CACertificateIdentifier": "rds-ca-rsa2048-g1",
    "DomainMemberships": [],
    "CopyTagsToSnapshot": false,
    "MonitoringInterval": 0,
    "PromotionTier": 1,
    "DBInstanceArn": "arn:aws:rds:us-east-1:405749097490:db:atento-001-app-ro",
    "IAMDatabaseAuthenticationEnabled": false,
    "DatabaseInsightsMode": "standard",
    "PerformanceInsightsEnabled": true,
    "PerformanceInsightsKMSKeyId": "arn:aws:kms:us-east-1:405749097490:key/64b7af79-2853-46e9-b11a-3682cf0cf60c",
    "PerformanceInsightsRetentionPeriod": 7,
    "EnabledCloudwatchLogsExports": null,
    "DeletionProtection": false,
    "AssociatedRoles": [],
    "TagList": [],
    "CustomerOwnedIpEnabled": false,
    "BackupTarget": "region",
    "NetworkType": "IPV4",
    "StorageThroughput": 0,
    "CertificateDetails": {"CAIdentifier": "rds-ca-rsa2048-g1", "ValidTill": "2026-12-13T06:44:11+00:00"},
    "DedicatedLogVolume": false,
    "EngineLifecycleSupport": "open-source-rds-extended-support-disabled"
}
```

---

## 3. STANDALONE INSTANCES (Full JSON)

### 3.1 beta-db (Environment: beta-001)

```json
{
    "DBInstanceIdentifier": "beta-db",
    "DBInstanceClass": "db.t3.micro",
    "Engine": "postgres",
    "DBInstanceStatus": "available",
    "MasterUsername": "postgres",
    "Endpoint": {"Address": "beta-db.cvw5l7p4adp1.us-east-1.rds.amazonaws.com", "Port": 5432, "HostedZoneId": "Z2R2ITUGPM61AM"},
    "AllocatedStorage": 20,
    "InstanceCreateTime": "2025-08-14T19:26:41.863000+00:00",
    "PreferredBackupWindow": "04:11-04:41",
    "BackupRetentionPeriod": 7,
    "DBSecurityGroups": [],
    "VpcSecurityGroups": [{"VpcSecurityGroupId": "sg-067dc36d901a5b1d0", "Status": "active"}],
    "DBParameterGroups": [{"DBParameterGroupName": "postgresql17", "ParameterApplyStatus": "in-sync"}],
    "AvailabilityZone": "us-east-1a",
    "DBSubnetGroup": {
        "DBSubnetGroupName": "beta-db-subnet-group",
        "DBSubnetGroupDescription": "4Shark-Beta-db-subnet-group",
        "VpcId": "vpc-0968cc73edd5596b0",
        "SubnetGroupStatus": "Complete",
        "Subnets": [
            {"SubnetIdentifier": "subnet-003ad99d0edf1b8f3", "SubnetAvailabilityZone": {"Name": "us-east-1a"}},
            {"SubnetIdentifier": "subnet-0434dbaf2d652fec7", "SubnetAvailabilityZone": {"Name": "us-east-1b"}}
        ]
    },
    "PreferredMaintenanceWindow": "fri:05:25-fri:05:55",
    "PendingModifiedValues": {},
    "MultiAZ": false,
    "EngineVersion": "17.6",
    "AutoMinorVersionUpgrade": true,
    "ReadReplicaDBInstanceIdentifiers": [],
    "LicenseModel": "postgresql-license",
    "Iops": 3000,
    "OptionGroupMemberships": [{"OptionGroupName": "default:postgres-17", "Status": "in-sync"}],
    "PubliclyAccessible": false,
    "StorageType": "gp3",
    "DbInstancePort": 0,
    "StorageEncrypted": true,
    "KmsKeyId": "arn:aws:kms:us-east-1:405749097490:key/64b7af79-2853-46e9-b11a-3682cf0cf60c",
    "DbiResourceId": "db-XZTJACH5ELGE3OYECESWCRELBI",
    "CACertificateIdentifier": "rds-ca-rsa2048-g1",
    "DomainMemberships": [],
    "CopyTagsToSnapshot": true,
    "MonitoringInterval": 0,
    "DBInstanceArn": "arn:aws:rds:us-east-1:405749097490:db:beta-db",
    "IAMDatabaseAuthenticationEnabled": false,
    "DatabaseInsightsMode": "standard",
    "PerformanceInsightsEnabled": false,
    "DeletionProtection": false,
    "AssociatedRoles": [],
    "MaxAllocatedStorage": 1000,
    "TagList": [],
    "CustomerOwnedIpEnabled": false,
    "ActivityStreamStatus": "stopped",
    "BackupTarget": "region",
    "NetworkType": "IPV4",
    "StorageThroughput": 125,
    "CertificateDetails": {"CAIdentifier": "rds-ca-rsa2048-g1", "ValidTill": "2027-02-20T05:25:04+00:00"},
    "DedicatedLogVolume": false,
    "IsStorageConfigUpgradeAvailable": false,
    "EngineLifecycleSupport": "open-source-rds-extended-support-disabled"
}
```

### 3.2 setup-prd-db (Environment: setup)

```json
{
    "DBInstanceIdentifier": "setup-prd-db",
    "DBInstanceClass": "db.t3.micro",
    "Engine": "postgres",
    "DBInstanceStatus": "available",
    "MasterUsername": "postgres",
    "Endpoint": {"Address": "setup-prd-db.cvw5l7p4adp1.us-east-1.rds.amazonaws.com", "Port": 5432, "HostedZoneId": "Z2R2ITUGPM61AM"},
    "AllocatedStorage": 20,
    "InstanceCreateTime": "2025-08-14T19:19:42.147000+00:00",
    "PreferredBackupWindow": "10:11-10:41",
    "BackupRetentionPeriod": 7,
    "DBSecurityGroups": [],
    "VpcSecurityGroups": [{"VpcSecurityGroupId": "sg-0e57cacbcc2424568", "Status": "active"}],
    "DBParameterGroups": [{"DBParameterGroupName": "postgresql16", "ParameterApplyStatus": "in-sync"}],
    "AvailabilityZone": "us-east-1a",
    "DBSubnetGroup": {
        "DBSubnetGroupName": "default-vpc-0204a1f8b5de51941",
        "DBSubnetGroupDescription": "Created from the RDS Management Console",
        "VpcId": "vpc-0204a1f8b5de51941",
        "SubnetGroupStatus": "Complete",
        "Subnets": [
            {"SubnetIdentifier": "subnet-049885e873eca0ef5", "SubnetAvailabilityZone": {"Name": "us-east-1b"}},
            {"SubnetIdentifier": "subnet-06eba9179753e73bf", "SubnetAvailabilityZone": {"Name": "us-east-1a"}}
        ]
    },
    "PreferredMaintenanceWindow": "tue:03:25-tue:03:55",
    "PendingModifiedValues": {},
    "MultiAZ": false,
    "EngineVersion": "16.9",
    "AutoMinorVersionUpgrade": true,
    "ReadReplicaDBInstanceIdentifiers": [],
    "LicenseModel": "postgresql-license",
    "Iops": 3000,
    "OptionGroupMemberships": [{"OptionGroupName": "default:postgres-16", "Status": "in-sync"}],
    "PubliclyAccessible": false,
    "StorageType": "gp3",
    "DbInstancePort": 0,
    "StorageEncrypted": true,
    "KmsKeyId": "arn:aws:kms:us-east-1:405749097490:key/64b7af79-2853-46e9-b11a-3682cf0cf60c",
    "DbiResourceId": "db-V4DAKBCFPMFFQTTIFMWXKLEOYI",
    "CACertificateIdentifier": "rds-ca-rsa2048-g1",
    "DomainMemberships": [],
    "CopyTagsToSnapshot": true,
    "MonitoringInterval": 0,
    "DBInstanceArn": "arn:aws:rds:us-east-1:405749097490:db:setup-prd-db",
    "IAMDatabaseAuthenticationEnabled": false,
    "DatabaseInsightsMode": "standard",
    "PerformanceInsightsEnabled": false,
    "DeletionProtection": false,
    "AssociatedRoles": [],
    "MaxAllocatedStorage": 1000,
    "TagList": [],
    "CustomerOwnedIpEnabled": false,
    "ActivityStreamStatus": "stopped",
    "BackupTarget": "region",
    "NetworkType": "IPV4",
    "StorageThroughput": 125,
    "CertificateDetails": {"CAIdentifier": "rds-ca-rsa2048-g1", "ValidTill": "2027-02-17T03:25:01+00:00"},
    "DedicatedLogVolume": false,
    "IsStorageConfigUpgradeAvailable": false,
    "EngineLifecycleSupport": "open-source-rds-extended-support-disabled"
}
```

---

## 4. SECURITY GROUPS (Full JSON)

### 4.1 sg-05ff12e712f05682f (production-rds-app-2, shared-001)

```json
{
    "GroupId": "sg-05ff12e712f05682f",
    "GroupName": "production-rds-app-2",
    "Description": "RDS production-app-2 external access",
    "VpcId": "vpc-0204a1f8b5de51941",
    "Tags": [{"Key": "Name", "Value": "production-rds-app-2"}],
    "IpPermissions": [
        {
            "IpProtocol": "tcp", "FromPort": 5432, "ToPort": 5432,
            "UserIdGroupPairs": [{"Description": "PGBouncer", "UserId": "405749097490", "GroupId": "sg-027773fe5068c6ab4"}],
            "IpRanges": [
                {"CidrIp": "0.0.0.0/0"}
            ]
        },
        {
            "IpProtocol": "tcp", "FromPort": 0, "ToPort": 0,
            "IpRanges": [{"Description": "VPN - Management VPC", "CidrIp": "10.255.0.0/16"}]
        }
    ],
    "IpPermissionsEgress": [{"IpProtocol": "-1", "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}]
}
```

### 4.2 sg-0be66cff163cf3805 (4Shark-demo-prd-db, demo-001)

```json
{
    "GroupId": "sg-0be66cff163cf3805",
    "GroupName": "4Shark-demo-prd-db",
    "Description": "4Shark-demo-prd-db",
    "VpcId": "vpc-0204a1f8b5de51941",
    "IpPermissions": [
        {
            "IpProtocol": "tcp", "FromPort": 5432, "ToPort": 5432,
            "IpRanges": [{"Description": "rede local da AWS", "CidrIp": "10.254.0.0/16"}]
        }
    ],
    "IpPermissionsEgress": [{"IpProtocol": "-1", "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}]
}
```

### 4.3 sg-0ddb2a65901bac264 (4app-atento-br-teste-rds-sg, atento-001)

```json
{
    "GroupId": "sg-0ddb2a65901bac264",
    "GroupName": "4app-atento-br-teste-rds-sg",
    "Description": "4app-atento-br-teste RDS Security Group",
    "VpcId": "vpc-0331320cef3e08143",
    "IpPermissions": [
        {
            "IpProtocol": "tcp", "FromPort": 5432, "ToPort": 5432,
            "IpRanges": [{"CidrIp": "0.0.0.0/0"}]
        },
        {
            "IpProtocol": "tcp", "FromPort": 6379, "ToPort": 6379,
            "IpRanges": [{"Description": "Elasticache redis", "CidrIp": "0.0.0.0/0"}]
        }
    ],
    "IpPermissionsEgress": [{"IpProtocol": "-1", "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}]
}
```

### 4.4 sg-067dc36d901a5b1d0 (4Shark-Beta-db, beta-001)

```json
{
    "GroupId": "sg-067dc36d901a5b1d0",
    "GroupName": "4Shark-Beta-db",
    "Description": "Created by RDS management console",
    "VpcId": "vpc-0968cc73edd5596b0",
    "IpPermissions": [
        {
            "IpProtocol": "tcp", "FromPort": 5432, "ToPort": 5432,
            "UserIdGroupPairs": [
                {"Description": "PGBouncer", "UserId": "405749097490", "GroupId": "sg-0089864082528d207"},
                {"Description": "VPN Beta", "UserId": "405749097490", "GroupId": "sg-01689947e4f5c6e53"},
                {"Description": "ECS", "UserId": "405749097490", "GroupId": "sg-0607aa031162eae04"}
            ],
            "IpRanges": [{"Description": "rede local aws", "CidrIp": "10.154.0.0/16"}]
        }
    ],
    "IpPermissionsEgress": [{"IpProtocol": "-1", "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}]
}
```

### 4.5 sg-0e57cacbcc2424568 (4Shark-Setup-prd-db, setup)

```json
{
    "GroupId": "sg-0e57cacbcc2424568",
    "GroupName": "4Shark-Setup-prd-db",
    "Description": "Created by RDS management console",
    "VpcId": "vpc-0204a1f8b5de51941",
    "IpPermissions": [
        {
            "IpProtocol": "tcp", "FromPort": 5432, "ToPort": 5432,
            "IpRanges": [{"Description": "rede local da AWS", "CidrIp": "10.254.0.0/16"}]
        }
    ],
    "IpPermissionsEgress": [{"IpProtocol": "-1", "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}]
}
```

---

## 5. DB SUBNET GROUPS (relevant ones only)

### 5.1 default-vpc-0204a1f8b5de51941 (used by shared-001, demo-001, setup)

```json
{
    "DBSubnetGroupName": "default-vpc-0204a1f8b5de51941",
    "DBSubnetGroupDescription": "Created from the RDS Management Console",
    "VpcId": "vpc-0204a1f8b5de51941",
    "Subnets": [
        {"SubnetIdentifier": "subnet-049885e873eca0ef5", "SubnetAvailabilityZone": {"Name": "us-east-1b"}},
        {"SubnetIdentifier": "subnet-06eba9179753e73bf", "SubnetAvailabilityZone": {"Name": "us-east-1a"}}
    ]
}
```

### 5.2 subnet-group-4app-atento-public (used by atento-001)

```json
{
    "DBSubnetGroupName": "subnet-group-4app-atento-public",
    "DBSubnetGroupDescription": "subnet-group-4app-atento-public",
    "VpcId": "vpc-0331320cef3e08143",
    "Subnets": [
        {"SubnetIdentifier": "subnet-07019f3ad3f31041a", "SubnetAvailabilityZone": {"Name": "us-east-1a"}},
        {"SubnetIdentifier": "subnet-0d7dad52f3c722622", "SubnetAvailabilityZone": {"Name": "us-east-1b"}}
    ]
}
```

### 5.3 beta-db-subnet-group (used by beta-001)

```json
{
    "DBSubnetGroupName": "beta-db-subnet-group",
    "DBSubnetGroupDescription": "4Shark-Beta-db-subnet-group",
    "VpcId": "vpc-0968cc73edd5596b0",
    "Subnets": [
        {"SubnetIdentifier": "subnet-003ad99d0edf1b8f3", "SubnetAvailabilityZone": {"Name": "us-east-1a"}},
        {"SubnetIdentifier": "subnet-0434dbaf2d652fec7", "SubnetAvailabilityZone": {"Name": "us-east-1b"}}
    ]
}
```

### 5.4 Other subnet groups (NOT used by current RDS resources)

- `default-vpc-0331320cef3e08143` — VPC atento, 4 subnets (us-east-1a x2, us-east-1b x2)
- `default-vpc-0b51d809d6bd9961e` — 6 subnets (us-east-1a through us-east-1f)
- `default-vpc-3dde0c5b` — 6 subnets (legacy)
- `default-vpc-fadd0f9c` — 2 subnets (legacy)
- `subnet-group-4app-atento-br-teste` — VPC atento, private subnets
- `subnet-group-production-setup` — same VPC as default-vpc-0204a1f8b5de51941, same subnets

---

## 6. PARAMETER GROUPS

### 6.1 Custom parameter groups (managed in shared-resources/ Terraform)

All 4 custom groups have exactly the same 3 user-modified parameters:

| Parameter | Value | Apply Method |
|---|---|---|
| tcp_keepalives_count | 10 | immediate |
| tcp_keepalives_idle | 60 | immediate |
| tcp_keepalives_interval | 30 | immediate |

**Cluster parameter groups:**
- `aurora-postgresql15` (family: aurora-postgresql15) — used by production-app-2, atento-001-app-cluster-cluster
- `aurora-postgresql16` (family: aurora-postgresql16) — used by demo-prd

**Instance parameter groups:**
- `postgresql16` (family: postgres16) — used by setup-prd-db
- `postgresql17` (family: postgres17) — used by beta-db

### 6.2 Default parameter groups in use (NOT managed in Terraform)

- `default.aurora-postgresql15` — instance param group for production-app-2 instances and atento-001 instances
- `default.aurora-postgresql16` — instance param group for demo-prd-instance-1

### 6.3 Deleted orphan parameter groups (2026-02-23)
- aurora-postgresql15-t4g-enhanced
- aurora-postgresql14
- aurora-postgresql17

---

## 7. KMS KEY

```json
{
    "KeyId": "64b7af79-2853-46e9-b11a-3682cf0cf60c",
    "Arn": "arn:aws:kms:us-east-1:405749097490:key/64b7af79-2853-46e9-b11a-3682cf0cf60c",
    "Enabled": true,
    "Description": "Default master key that protects my RDS database volumes when no other key is defined",
    "KeyUsage": "ENCRYPT_DECRYPT",
    "KeyState": "Enabled",
    "Origin": "AWS_KMS",
    "KeyManager": "AWS",
    "KeySpec": "SYMMETRIC_DEFAULT",
    "MultiRegion": false
}
```

**NOTE**: This is an AWS-managed key (KeyManager: AWS). It is NOT a customer-managed key. It does NOT need to be managed in Terraform. All clusters and standalone instances use this same key.

---

## 8. MONITORING ROLE

```json
{
    "RoleName": "rds-monitoring-role",
    "Arn": "arn:aws:iam::405749097490:role/rds-monitoring-role",
    "CreateDate": "2016-12-14T15:52:51+00:00",
    "AssumeRolePolicyDocument": {
        "Version": "2012-10-17",
        "Statement": [{"Sid": "", "Effect": "Allow", "Principal": {"Service": "monitoring.rds.amazonaws.com"}, "Action": "sts:AssumeRole"}]
    },
    "AttachedPolicies": [
        {"PolicyName": "AmazonRDSEnhancedMonitoringRole", "PolicyArn": "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"}
    ]
}
```

Used by instances with MonitoringInterval > 0: production-app-2 instances (60s), demo-prd-instance-1 (60s).
NOT used by: atento-001 instances (0), beta-db (0), setup-prd-db (0).

---

## 9. QUICK REFERENCE TABLE

| Env | Identifier | Type | Engine | Class | Instances | SG | Subnet Group | Param Group (cluster) | Param Group (instance) | Monitoring | Perf Insights | Public | Backup | Del Protection | CW Logs | Lifecycle Support |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| shared-001 | production-app-2 | Aurora | PG 15.13 | db.t4g.large | 2 (writer: us-east-1b, reader: us-east-1a) | sg-05ff12e712f05682f | default-vpc-0204a1f8b5de51941 | aurora-postgresql15 | default.aurora-postgresql15 | 60s | true | true | 7d | true | postgresql | extended-support |
| demo-001 | demo-prd | Aurora | PG 16.9 | db.t3.medium | 1 (writer: us-east-1a) | sg-0be66cff163cf3805 | default-vpc-0204a1f8b5de51941 | aurora-postgresql16 | default.aurora-postgresql16 | 60s | true | false | 1d | true | postgresql | extended-support |
| atento-001 | atento-001-app-cluster-cluster | Aurora | PG 15.13 | db.t4g.large | 2 (writer: us-east-1a, reader: us-east-1b) | sg-0ddb2a65901bac264 | subnet-group-4app-atento-public | aurora-postgresql15 | default.aurora-postgresql15 | 0 | true | true | 7d | true | none | extended-support-disabled |
| beta-001 | beta-db | Standalone | PG 17.6 | db.t3.micro | 1 | sg-067dc36d901a5b1d0 | beta-db-subnet-group | n/a | postgresql17 | 0 | false | false | 7d | false | n/a | extended-support-disabled |
| setup | setup-prd-db | Standalone | PG 16.9 | db.t3.micro | 1 | sg-0e57cacbcc2424568 | default-vpc-0204a1f8b5de51941 | n/a | postgresql16 | 0 | false | false | 7d | false | n/a | extended-support-disabled |

---

## 10. MAINTENANCE WINDOWS

| Resource | Backup Window | Maintenance Window |
|---|---|---|
| production-app-2 (cluster) | 08:19-08:49 | sun:13:00-sun:13:30 |
| production-app-2-instance-1 | 08:19-08:49 | sun:07:00-sun:07:30 |
| production-app-2-instance-1-us-east-1b | 08:19-08:49 | thu:05:12-thu:05:42 |
| demo-prd (cluster) | 05:00-05:30 | sat:13:00-sat:13:30 |
| demo-prd-instance-1 | 05:00-05:30 | tue:08:10-tue:08:40 |
| atento-001-app-cluster-cluster (cluster) | 08:19-08:49 | sun:13:00-sun:13:30 |
| atento-001-app-cluster | 08:19-08:49 | sat:06:44-sat:07:14 |
| atento-001-app-ro | 08:19-08:49 | sat:06:44-sat:07:14 |
| beta-db | 04:11-04:41 | fri:05:25-fri:05:55 |
| setup-prd-db | 10:11-10:41 | tue:03:25-tue:03:55 |
