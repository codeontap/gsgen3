[#ftl]
[#-- Standard inputs --]
[#assign blueprintObject = blueprint?eval]
[#assign credentialsObject = credentials?eval]
[#assign configurationObject = configuration?eval]
[#assign stackOutputsObject = stackOutputs?eval]
[#assign masterDataObject = masterData?eval]

[#-- High level objects --]
[#assign organisationObject = blueprintObject.Organisation]
[#assign accountObject = blueprintObject.Account]
[#assign projectObject = blueprintObject.Project]
[#assign solutionObject = blueprintObject.Solution]
[#assign solutionTiers = solutionObject.Tiers]
[#assign segmentObject = blueprintObject.Segment]

[#-- Reference data --]
[#assign regions = masterDataObject.Regions]
[#assign environments = masterDataObject.Environments]
[#assign categories = masterDataObject.Categories]
[#assign tiers = masterDataObject.Tiers]
[#assign routeTables = masterDataObject.RouteTables]
[#assign networkACLs = masterDataObject.NetworkACLs]
[#assign storage = masterDataObject.Storage]
[#assign processors = masterDataObject.Processors]
[#assign ports = masterDataObject.Ports]
[#assign portMappings = masterDataObject.PortMappings]

[#-- Reference Objects --]
[#assign regionObject = regions[region]]
[#assign projectRegionObject = regions[projectRegion]]
[#assign accountRegionObject = regions[accountRegion]]
[#assign environmentObject = environments[segmentObject.Environment]]
[#assign categoryObject = categories[segmentObject.Category!environmentObject.Category]]

[#-- Key ids/names --]
[#assign organisationId = organisationObject.Id]
[#assign accountId = accountObject.Id]
[#assign projectId = projectObject.Id]
[#assign projectName = projectObject.Name]
[#assign segmentId = segmentObject.Id!environmentObject.Id]
[#assign segmentName = segmentObject.Name!environmentObject.Name]
[#assign regionId = regionObject.Id]
[#assign projectRegionId = projectRegionObject.Id]
[#assign accountRegionId = accountRegionObject.Id]
[#assign environmentId = environmentObject.Id]
[#assign environmentName = environmentObject.Name]
[#assign categoryId = categoryObject.Id]

[#-- Domains --]
[#assign projectDomainStem = (projectObject.Domain.Stem)!"gosource.com.au"]
[#assign segmentDomainBehaviour = (projectObject.Domain.SegmentBehaviour)!""]
[#switch segmentDomainBehaviour]
    [#case "naked"]
        [#assign segmentDomain = projectDomainStem]
        [#break]
    [#case "includeSegmentName"]
        [#assign segmentDomain = segmentName + "." + projectDomainStem]
        [#break]
    [#case "includeProjectId"]
    [#default]
        [#assign segmentDomain = segmentName + "." + projectId + "." + projectDomainStem]
[/#switch]
[#if (projectObject.Domain.CertificateId)??]
    [#assign certificateId = segmentObject.Domain.CertificateId]
[#elseif projectDomainStem != "gosource.com.au"]
    [#assign certificateId = projectId]
[#else]
    [#assign certificateId = accountId]
[/#if]

[#-- Buckets --]
[#assign credentialsBucket = getKey("s3XaccountXcredentials")!"unknown"]
[#assign codeBucket = getKey("s3XaccountXcode")!"unknown"]
[#assign logsBucket = getKey("s3XsegmentXlogs")]
[#assign backupsBucket = getKey("s3XsegmentXbackups")]

[#-- AZ List --]
[#if (segmentObject.AZList)??]
    [#assign azList = segmentObject.AZList]
[#else]
    [#if regionObject.DefaultZones??]
        [#assign azList = regionObject.DefaultZones]
    [#else]
        [#assign azList = ["a", "b"]]
    [/#if]
[/#if]

[#-- Loop optimisation --]
[#assign lastTier = solutionTiers?last]
[#assign firstZone = azList?first]
[#assign lastZone = azList?last]
[#assign zoneCount = azList?size]

[#-- Get stack output --]
[#function getKey key]
    [#list stackOutputsObject as pair]
        [#if pair.OutputKey==key]
            [#return pair.OutputValue]
        [/#if]
    [/#list]
[/#function]

[#-- Solution --]
[#assign sshPerSegment = segmentObject.SSHPerSegment]
[#assign solnMultiAZ = solutionObject.MultiAZ!environmentObject.MultiAZ!false]
[#assign vpc = getKey("vpcXsegmentXvpc")]
[#assign securityGroupNAT = getKey("securityGroupXmgmtXnat")!"none"]

[#-- Get processor configuration --]
[#function getProcessor tier component type]
    [#assign tc = tier.Id + "-" + component.Id]
    [#assign defaultProfile = "default"]
    [#if (component[type].Processor)??]
        [#return component[type].Processor]
    [/#if]
    [#if (solutionObject.Processor[tc])??]
        [#return solutionObject.Processor[tc]]
    [/#if]
    [#if (solutionObject.Processor[type])??]
        [#return solutionObject.Processor[type]]
    [/#if]
    [#if (processors[solutionObject.CapacityProfile][tc])??]
        [#return processors[solutionObject.CapacityProfile][tc]]
    [/#if]
    [#if (processors[solutionObject.CapacityProfile][type])??]
        [#return processors[solutionObject.CapacityProfile][type]]
    [/#if]
    [#if (processors[defaultProfile][tc])??]
        [#return processors[defaultProfile][tc]]
    [/#if]
    [#if (processors[defaultProfile][type])??]
        [#return processors[defaultProfile][type]]
    [/#if]
[/#function]

[#-- Get storage configuration --]
[#function getStorage tier component type]
    [#assign tc = tier.Id + "-" + component.Id]
    [#assign defaultProfile = "default"]
    [#if (component[type].Storage)??]
        [#return component[type].Storage]
    [/#if]
    [#if (solutionObject.Storage[tc])??]
        [#return solutionObject.Storage[tc]]
    [/#if]
    [#if (solutionObject.Storage[type])??]
        [#return solutionObject.Storage[type]]
    [/#if]
    [#if (storage[solutionObject.CapacityProfile][tc])??]
        [#return storage[solutionObject.CapacityProfile][tc]]
    [/#if]
    [#if (storage[solutionObject.CapacityProfile][type])??]
        [#return storage[solutionObject.CapacityProfile][type]]
    [/#if]
    [#if (storage[defaultProfile][tc])??]
        [#return storage[defaultProfile][tc]]
    [/#if]
    [#if (storage[defaultProfile][type])??]
        [#return storage[defaultProfile][type]]
    [/#if]
[/#function]

[#macro createBlockDevices storageProfile]
    [#if (storageProfile.Volumes)?? && (storageProfile.Volumes?size > 0)]
        "BlockDeviceMappings" : [
            [#list storageProfile.Volumes as volume]
                {
                    "DeviceName" : "${volume.Device}",
                    "Ebs" : {
                        "DeleteOnTermination" : true,
                        "Encrypted" : false,
                        "VolumeSize" : "${volume.Size}",
                        "VolumeType" : "gp2"
                    }
                },
            [/#list]
            {
                "DeviceName" : "/dev/sdc",
                "VirtualName" : "ephemeral0"
            },
            {
                "DeviceName" : "/dev/sdt",
                "VirtualName" : "ephemeral1"
            }
        ],
    [/#if]
[/#macro]

{
    "AWSTemplateFormatVersion" : "2010-09-09",
    "Resources" : {
        [#assign count = 0]
        [#list solutionTiers as solutionTier]
            [#assign tier = tiers[solutionTier.Id]]
            [#if solutionTier.Components??]
                [#list solutionTier.Components as component]
                    [#assign slices = component.Slices!solutionTier.Slices!tier.Slices]
                    [#if !(slice??) || (slices?seq_contains(slice))]
                        [#if count > 0],[/#if]
                        [#if component.MultiAZ??] 
                            [#assign multiAZ =  component.MultiAZ]
                        [#else]
                            [#assign multiAZ =  solnMultiAZ]
                        [/#if]
    
                        [#-- Security Group --]
                        [#if ! (component.S3?? || component.SQS??) ]
                            "securityGroupX${tier.Id}X${component.Id}" : {
                                "Type" : "AWS::EC2::SecurityGroup",
                                "Properties" : {
                                    "GroupDescription": "Security Group for ${tier.Name}-${component.Name}",
                                    "VpcId": "${vpc}",
                                    "Tags" : [
                                        { "Key" : "gs:account", "Value" : "${accountId}" },
                                        { "Key" : "gs:project", "Value" : "${projectId}" },
                                        { "Key" : "gs:segment", "Value" : "${segmentId}" },
                                        { "Key" : "gs:environment", "Value" : "${environmentId}" },
                                        { "Key" : "gs:category", "Value" : "${categoryId}" },
                                        { "Key" : "gs:tier", "Value" : "${tier.Id}" },
                                        { "Key" : "gs:component", "Value" : "${component.Id}" },
                                        { "Key" : "Name", "Value" : "${projectName}-${segmentName}-${tier.Name}-${component.Name}" }
                                    ]
                                }
                            },
                        [/#if]

                        [#-- S3 --]
                        [#if component.S3??]
                            [#assign s3 = component.S3]
                            "s3X${tier.Id}X${component.Id}" : {
                                "Type" : "AWS::S3::Bucket",
                                "Properties" : {
                                    [#if s3.Name??]
                                        "BucketName" : "${s3.Name}.${segmentDomain}",
                                    [#else]
                                        "BucketName" : "${component.Name}.${segmentDomain}",
                                    [/#if]
                                    "Tags" : [ 
                                        { "Key" : "gs:account", "Value" : "${accountId}" },
                                        { "Key" : "gs:project", "Value" : "${projectId}" },
                                        { "Key" : "gs:segment", "Value" : "${segmentId}" },
                                        { "Key" : "gs:environment", "Value" : "${environmentId}" },
                                        { "Key" : "gs:category", "Value" : "${categoryId}" },
                                        { "Key" : "gs:tier", "Value" : "${tier.Id}" },
                                        { "Key" : "gs:component", "Value" : "${component.Id}" }
                                    ]
                                    [#if s3.Lifecycle??]
                                        ,"LifecycleConfiguration" : {
                                            "Rules" : [
                                                {
                                                    "Id" : "default",
                                                    [#if s3.Lifecycle.Expiration??]
                                                        "ExpirationInDays" : ${s3.Lifecycle.Expiration},
                                                    [/#if]
                                                    "Status" : "Enabled"
                                                }
                                            ]
                                        }
                                    [/#if]
                                }
                            }
                            [#assign count = count + 1]
                        [/#if]

                        [#-- SQS --]
                        [#if component.SQS??]
                            [#assign sqs = component.SQS]
                            "sqsX${tier.Id}X${component.Id}":{
                                "Type" : "AWS::SQS::Queue",
                                "Properties" : {
                                    [#if sqs.Name??]
                                        "QueueName" : "${sqs.Name}"
                                    [#else]
                                        "QueueName" : "${projectId}-${environmentName}-${component.Name}"
                                    [/#if]
                                    [#if sqs.DelaySeconds??],"DelaySeconds" : ${sqs.DelaySeconds?c}[/#if]
                                    [#if sqs.MaximumMessageSize??],"MaximumMessageSize" : ${sqs.MaximumMessageSize?c}[/#if]
                                    [#if sqs.MessageRetentionPeriod??],"MessageRetentionPeriod" : ${sqs.MessageRetentionPeriod?c}[/#if]
                                    [#if sqs.ReceiveMessageWaitTimeSeconds??],"ReceiveMessageWaitTimeSeconds" : ${sqs.ReceiveMessageWaitTimeSeconds?c}[/#if]
                                    [#if sqs.VisibilityTimeout??],"VisibilityTimeout" : ${sqs.VisibilityTimeout?c}[/#if]
                                }
                            }
                            [#assign count = count + 1]
                        [/#if]
                        
                        [#-- ELB --]
                        [#if component.ELB??]
                            [#assign elb = component.ELB]
                            [#list elb.PortMappings as mapping]
                                "securityGroupIngressX${tier.Id}X${component.Id}X${ports[portMappings[mapping].Source].Port?c}" : {
                                    "Type" : "AWS::EC2::SecurityGroupIngress",
                                    "Properties" : {
                                        "GroupId": {"Ref" : "securityGroupX${tier.Id}X${component.Id}"},
                                        "IpProtocol": "${ports[portMappings[mapping].Source].IPProtocol}", 
                                        "FromPort": "${ports[portMappings[mapping].Source].Port?c}", 
                                        "ToPort": "${ports[portMappings[mapping].Source].Port?c}", 
                                        "CidrIp": "0.0.0.0/0"
                                    }
                                },
                            [/#list]
                            "elbX${tier.Id}X${component.Id}" : {
                                "Type" : "AWS::ElasticLoadBalancing::LoadBalancer",
                                "Properties" : {
                                    [#if multiAZ]
                                        "Subnets" : [
                                            [#list azList as zone]
                                                "${getKey("subnetX"+tier.Id+"X"+zone)}"[#if !(zone == lastZone)],[/#if]
                                            [/#list]
                                        ],
                                        "CrossZone" : true,
                                    [#else]
                                        "Subnets" : [
                                            "${getKey("subnetX"+tier.Id+"X"+firstZone)}"
                                        ],
                                    [/#if]
                                    "Listeners" : [ 
                                        [#list elb.PortMappings as mapping]
                                            {
                                                [#assign source = ports[portMappings[mapping].Source]]
                                                [#assign destination = ports[portMappings[mapping].Destination]]
                                                "LoadBalancerPort" : "${source.Port?c}",
                                                "Protocol" : "${source.Protocol}",
                                                "InstancePort" : "${destination.Port?c}",
                                                "InstanceProtocol" : "${destination.Protocol}"
                                                [#if (source.Certificate)?? && source.Certificate]
                                                    ,"SSLCertificateId" : { 
                                                        "Fn::Join" : [
                                                            "", 
                                                            [
                                                                "arn:aws:iam::", 
                                                                {"Ref" : "AWS::AccountId"}, 
                                                                ":server-certificate/ssl/${certificateId}/${certificateId}-ssl"
                                                            ]
                                                        ]
                                                    }
                                                [/#if]
                                            }
                                            [#if !(mapping == elb.PortMappings?last)],[/#if]
                                        [/#list]
                                    ],
                                    "HealthCheck" : {
                                        [#assign port = ports[portMappings[elb.PortMappings[0]].Destination]]
                                        "Target" : "${(port.HealthCheck.Protocol)!port.Protocol}:${port.Port?c}${(elb.HealthCheck.Path)!port.HealthCheck.Path}",
                                        "HealthyThreshold" : "${(elb.HealthCheck.HealthyThreshold)!port.HealthCheck.HealthyThreshold}",
                                        "UnhealthyThreshold" : "${(elb.HealthCheck.UnhealthyThreshold)!port.HealthCheck.UnhealthyThreshold}",
                                        "Interval" : "${(elb.HealthCheck.Interval)!port.HealthCheck.Interval}",
                                        "Timeout" : "${(elb.HealthCheck.Timeout)!port.HealthCheck.Timeout}"
                                    },
                                    [#if (elb.Logs)?? && (elb.Logs == true)]
                                        "AccessLoggingPolicy" : {
                                            "EmitInterval" : 5,
                                            "Enabled" : true,
                                            "S3BucketName" : "${logsBucket}"
                                        },
                                    [/#if]
                                    "Scheme" : "${((solutionTier.RouteTable!tier.RouteTable) == "external")?string("internet-facing","internal")}",
                                    "SecurityGroups":[ {"Ref" : "securityGroupX${tier.Id}X${component.Id}"} ],
                                    "LoadBalancerName" : "${projectId}-${segmentId}-${tier.Id}-${component.Id}",
                                    "Tags" : [
                                        { "Key" : "gs:account", "Value" : "${accountId}" },
                                        { "Key" : "gs:project", "Value" : "${projectId}" },
                                        { "Key" : "gs:segment", "Value" : "${segmentId}" },
                                        { "Key" : "gs:environment", "Value" : "${environmentId}" },
                                        { "Key" : "gs:category", "Value" : "${categoryId}" },
                                        { "Key" : "gs:tier", "Value" : "${tier.Id}" },
                                        { "Key" : "gs:component", "Value" : "${component.Id}" },
                                        { "Key" : "Name", "Value" : "${projectName}-${segmentName}-${tier.Name}-${component.Name}" } 
                                    ]
                                }
                            }
                            [#assign count = count + 1]
                        [/#if]
        
                        [#-- EC2 --]
                        [#if component.EC2??]
                            [#assign ec2 = component.EC2]
                            [#assign fixedIP = ec2.FixedIP?? && ec2.FixedIP]
                            [#list ec2.Ports as port]
                                "securityGroupIngressX${tier.Id}X${component.Id}X${ports[port].Port?c}" : {
                                    "Type" : "AWS::EC2::SecurityGroupIngress",
                                    "Properties" : {
                                        "GroupId": {"Ref" : "securityGroupX${tier.Id}X${component.Id}"},
                                        "IpProtocol": "${ports[port].IPProtocol}", 
                                        "FromPort": "${ports[port].Port?c}", 
                                        "ToPort": "${ports[port].Port?c}", 
                                        "CidrIp": "0.0.0.0/0"
                                    }
                                },
                            [/#list]
                                    
                            "roleX${tier.Id}X${component.Id}": {
                                "Type" : "AWS::IAM::Role",
                                "Properties" : {
                                    "AssumeRolePolicyDocument" : {
                                        "Version": "2012-10-17",
                                        "Statement": [ 
                                            {
                                                "Effect": "Allow",
                                                "Principal": { "Service": [ "ec2.amazonaws.com" ] },
                                                "Action": [ "sts:AssumeRole" ]
                                            }
                                        ]
                                    },
                                    "Path": "/",
                                    "Policies": [
                                        {
                                            "PolicyName": "${tier.Id}-${component.Id}-basic",
                                            "PolicyDocument" : {
                                                "Version": "2012-10-17",
                                                "Statement": [
                                                    {
                                                        "Resource": [
                                                            "arn:aws:s3:::${codeBucket}",
                                                            "arn:aws:s3:::${logsBucket}"
                                                        ],
                                                        "Action": [
                                                            "s3:List*"
                                                        ],
                                                        "Effect": "Allow"
                                                    },
                                                    {
                                                        "Resource": [
                                                            "arn:aws:s3:::${codeBucket}/*"
                                                        ],
                                                        "Action": [
                                                            "s3:GetObject"
                                                        ],
                                                        "Effect": "Allow"
                                                    },
                                                    {
                                                        "Resource": [
                                                            "arn:aws:s3:::${logsBucket}/*"
                                                        ],
                                                        "Action": [
                                                            "s3:PutObject"
                                                        ],
                                                        "Effect": "Allow"
                                                    }
                                                    [#if getKey("cmkXsegmentXcmk")??]
                                                    ,{
                                                        "Resource": [
                                                            { 
                                                                "Fn::Join" : [
                                                                    "", 
                                                                    [
                                                                        "arn:aws:kms:${regionId}:", 
                                                                        {"Ref" : "AWS::AccountId"}, 
                                                                        ":key/${getKey("cmkXsegmentXcmk")}"
                                                                    ]
                                                                ]
                                                            }
                                                        ],
                                                        "Action": [
                                                            "kms:Decrypt"
                                                        ],
                                                        "Effect": "Allow"
                                                    }
                                                    [/#if]
                                                ]
                                            }
                                        }
                                    ]
                                }
                            },
            
                            "instanceProfileX${tier.Id}X${component.Id}" : {
                                "Type" : "AWS::IAM::InstanceProfile",
                                "Properties" : {
                                    "Path" : "/",
                                    "Roles" : [ 
                                        { "Ref" : "roleX${tier.Id}X${component.Id}" } 
                                    ]
                                }
                            },
            
                            [#assign ec2Count = 0]
                            [#list regionObject.Zones as zone]
                                [#if azList?seq_contains(zone.Id) && (multiAZ || firstZone = zone.Id)]
                                    [#if ec2Count > 0],[/#if]
                                    "ec2InstanceX${tier.Id}X${component.Id}X${zone.Id}": {
                                        "Type": "AWS::EC2::Instance",
                                        "Metadata": {
                                            "AWS::CloudFormation::Init": {
                                                "configSets" : {
                                                    "ec2" : ["dirs", "bootstrap", "puppet"]
                                                },
                                                "dirs": {
                                                    "commands": {
                                                        "01Directories" : {
                                                            "command" : "mkdir --parents --mode=0755 /etc/gosource && mkdir --parents --mode=0755 /opt/gosource/bootstrap && mkdir --parents --mode=0755 /var/log/gosource",
                                                            "ignoreErrors" : "false"
                                                        }
                                                    }
                                                },
                                                "bootstrap": {
                                                    "packages" : {
                                                        "yum" : {
                                                            "aws-cli" : []
                                                        }
                                                    },
                                                    "files" : {
                                                        "/etc/gosource/facts.sh" : {
                                                            "content" : { 
                                                                "Fn::Join" : [
                                                                    "", 
                                                                    [
                                                                        "#!/bin/bash\n",
                                                                        "echo \"gs:accountRegion=${accountRegionId}\"\n",
                                                                        "echo \"gs:account=${accountId}\"\n",
                                                                        "echo \"gs:project=${projectId}\"\n",
                                                                        "echo \"gs:region=${regionId}\"\n",
                                                                        "echo \"gs:segment=${segmentId}\"\n",
                                                                        "echo \"gs:environment=${environmentId}\"\n",
                                                                        "echo \"gs:tier=${tier.Id}\"\n",
                                                                        "echo \"gs:component=${component.Id}\"\n",
                                                                        "echo \"gs:zone=${zone.Id}\"\n",
                                                                        "echo \"gs:name=${projectName}-${segmentName}-${tier.Name}-${component.Name}-${zone.Name}\"\n",
                                                                        "echo \"gs:role=${component.Role}\"\n",
                                                                        "echo \"gs:credentials=${credentialsBucket}\"\n",
                                                                        "echo \"gs:code=${codeBucket}\"\n",
                                                                        "echo \"gs:logs=${logsBucket}\"\n",
                                                                        "echo \"gs:backup=${backupsBucket}\"\n"
                                                                    ]
                                                                ]
                                                            },
                                                            "mode" : "000755"
                                                        },
                                                        "/opt/gosource/bootstrap/fetch.sh" : {
                                                            "content" : { 
                                                                "Fn::Join" : [
                                                                    "", 
                                                                    [
                                                                        "#!/bin/bash -ex\n",
                                                                        "exec > >(tee /var/log/gosource/fetch.log|logger -t gosource-fetch -s 2>/dev/console) 2>&1\n",
                                                                        "REGION=$(/etc/gosource/facts.sh | grep gs:accountRegion= | cut -d '=' -f 2)\n",
                                                                        "CODE=$(/etc/gosource/facts.sh | grep gs:code= | cut -d '=' -f 2)\n",
                                                                        "aws --region ${r"${REGION}"} s3 sync s3://${r"${CODE}"}/bootstrap/centos/ /opt/gosource/bootstrap && chmod 0755 /opt/gosource/bootstrap/*.sh\n"
                                                                    ]
                                                                ]
                                                            },
                                                            "mode" : "000755"
                                                        }
                                                    },
                                                    "commands": {
                                                        "01Fetch" : {
                                                            "command" : "/opt/gosource/bootstrap/fetch.sh",
                                                            "ignoreErrors" : "false"
                                                        },
                                                        "02Initialise" : {
                                                            "command" : "/opt/gosource/bootstrap/init.sh",
                                                            "ignoreErrors" : "false"
                                                        }
                                                        [#if ec2.LoadBalanced]
                                                            ,"03RegisterWithLB" : {
                                                                "command" : "/opt/gosource/bootstrap/register.sh",
                                                                "env" : { 
                                                                    "LOAD_BALANCER" : { "Ref" : "elbXelbX${component.Id}" } 
                                                                },
                                                                "ignoreErrors" : "false"
                                                            }
                                                        [/#if]
                                                    }
                                                },
                                                "puppet": {
                                                    "commands": {
                                                        "01SetupPuppet" : {
                                                            "command" : "/opt/gosource/bootstrap/puppet.sh",
                                                            "ignoreErrors" : "false"
                                                        }
                                                    }
                                                }
                                            }
                                        },
                                        [#assign processorProfile = getProcessor(tier, component, "EC2")]
                                        [#assign storageProfile = getStorage(tier, component, "EC2")]
                                        "Properties": {
                                            [@createBlockDevices storageProfile=storageProfile /]
                                            "DisableApiTermination" : false,
                                            "EbsOptimized" : false,
                                            "IamInstanceProfile" : { "Ref" : "instanceProfileX${tier.Id}X${component.Id}" },
                                            "ImageId": "${regionObject.AMIs.Centos.EC2}",
                                            "InstanceInitiatedShutdownBehavior" : "stop",
                                            "InstanceType": "${processorProfile.Processor}",
                                            "KeyName": "${projectName + sshPerSegment?string("-" + segmentName,"")}",
                                            "Monitoring" : false,
                                            "NetworkInterfaces" : [
                                                {
                                                    "AssociatePublicIpAddress" : ${(((solutionTier.RouteTable!tier.RouteTable) == "external") && !fixedIP)?string("true","false")},
                                                    "DeleteOnTermination" : true,
                                                    "DeviceIndex" : "0",
                                                    "SubnetId" : "${getKey("subnetX"+tier.Id+"X"+zone.Id)}",
                                                    "GroupSet" : [ 
                                                        {"Ref" : "securityGroupX${tier.Id}X${component.Id}"} 
                                                        [#if securityGroupNAT != "none"]
                                                            , "${securityGroupNAT}"
                                                        [/#if] 
                                                    ] 
                                                }
                                            ],
                                            "SourceDestCheck" : true,
                                            "Tags" : [
                                                { "Key" : "gs:account", "Value" : "${accountId}" },
                                                { "Key" : "gs:project", "Value" : "${projectId}" },
                                                { "Key" : "gs:segment", "Value" : "${segmentId}" },
                                                { "Key" : "gs:environment", "Value" : "${environmentId}" },
                                                { "Key" : "gs:category", "Value" : "${categoryId}" },
                                                { "Key" : "gs:tier", "Value" : "${tier.Id}" },
                                                { "Key" : "gs:component", "Value" : "${component.Id}" },
                                                { "Key" : "gs:zone", "Value" : "${zone.Id}" },
                                                { "Key" : "Name", "Value" : "${projectName}-${segmentName}-${tier.Name}-${component.Name}-${zone.Name}" }
                                            ],
                                            "UserData" : { 
                                                "Fn::Base64" : { 
                                                    "Fn::Join" : [
                                                        "", 
                                                        [
                                                            "#!/bin/bash -ex\n",
                                                            "exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1\n",
                                                            "yum install -y aws-cfn-bootstrap\n",
                                                            "# Remainder of configuration via metadata\n",
                                                            "/opt/aws/bin/cfn-init -v",
                                                            "         --stack ", { "Ref" : "AWS::StackName" },
                                                            "         --resource ec2InstanceX${tier.Id}X${component.Id}X${zone.Id}",
                                                            "         --region ${regionId} --configsets ec2\n"
                                                        ]
                                                    ]
                                                }
                                            }
                                        }
                                        [#if ec2.LoadBalanced]
                                            ,"DependsOn" : "elbXelbX${component.Id}"
                                        [/#if]
                                    }
                                    [#if fixedIP]
                                        ,"eipX${tier.Id}X${component.Id}X${zone.Id}": {
                                            "Type" : "AWS::EC2::EIP",
                                            "Properties" : {
                                                "InstanceId" : { "Ref" : "ec2InstanceX${tier.Id}X${component.Id}X${zone.Id}" },
                                                "Domain" : "vpc"
                                            }
                                        }
                                    [/#if]
                                    [#assign ec2Count = ec2Count + 1]
                                [/#if]
                            [/#list]
                            [#assign count = count + 1]
                        [/#if]

                        [#-- ECS --]
                        [#if component.ECS??]
                            [#assign ecs = component.ECS]
                            [#assign processorProfile = getProcessor(tier, component, "ECS")]
                            [#assign maxSize = processorProfile.MaxPerZone]
                            [#if multiAZ]
                                [#assign maxSize = maxSize * zoneCount]
                            [/#if]
                            [#assign storageProfile = getStorage(tier, component, "ECS")]
                            [#assign fixedIP = ecs.FixedIP?? && ecs.FixedIP]
                            [#if ecs.Services??]
                                [#list ecs.Services as service]
                                    [#list service.Containers as container]
                                        [#if container.Ports??]
                                            [#list container.Ports as port]
                                                [#if port?is_hash]
                                                    [#assign portId = port.Id]
                                                [#else]
                                                    [#assign portId = port]
                                                [/#if]
                                                "securityGroupIngressX${tier.Id}X${component.Id}X${ports[portId].Port?c}" : {
                                                    "Type" : "AWS::EC2::SecurityGroupIngress",
                                                    "Properties" : {
                                                        "GroupId": {"Ref" : "securityGroupX${tier.Id}X${component.Id}"},
                                                        "IpProtocol": "${ports[portId].IPProtocol}", 
                                                        "FromPort": "${ports[portId].Port?c}", 
                                                        "ToPort": "${ports[portId].Port?c}", 
                                                        [#if fixedIP && port?is_hash && port.ELB??]
                                                            "SourceSecurityGroupId": "${getKey("securityGroupXelbX"+port.ELB)}"
                                                        [#else]
                                                            "CidrIp": "0.0.0.0/0"
                                                        [/#if]
                                                    }
                                                },
                                            [/#list]
                                        [/#if]
                                    [/#list]
                                [/#list]
                            [#else]
                                [#if ecs.Ports??]
                                    [#list ecs.Ports as port]
                                        [#if port?is_hash]
                                            [#assign portId = port.Id]
                                        [#else]
                                            [#assign portId = port]
                                        [/#if]
                                        "securityGroupIngressX${tier.Id}X${component.Id}X${ports[portId].Port?c}" : {
                                            "Type" : "AWS::EC2::SecurityGroupIngress",
                                            "Properties" : {
                                                "GroupId": {"Ref" : "securityGroupX${tier.Id}X${component.Id}"},
                                                "IpProtocol": "${ports[portId].IPProtocol}", 
                                                "FromPort": "${ports[portId].Port?c}", 
                                                "ToPort": "${ports[portId].Port?c}", 
                                                [#if fixedIP && port?is_hash && port.ELB??]
                                                    "SourceSecurityGroupId": "${getKey("securityGroupXelbX"+port.ELB)}"
                                                [#else]
                                                    "CidrIp": "0.0.0.0/0"
                                                [/#if]
                                            }
                                        },
                                    [/#list]
                                [/#if]
                            [/#if]
                
                            "ecsX${tier.Id}X${component.Id}" : {
                                "Type" : "AWS::ECS::Cluster"
                            },
                            
                            "roleX${tier.Id}X${component.Id}": {
                                "Type" : "AWS::IAM::Role",
                                "Properties" : {
                                    "AssumeRolePolicyDocument" : {
                                        "Version": "2012-10-17",
                                        "Statement": [ 
                                            {
                                                "Effect": "Allow",
                                                "Principal": { "Service": [ "ec2.amazonaws.com" ] },
                                                "Action": [ "sts:AssumeRole" ]
                                            }
                                        ]
                                    },
                                    "Path": "/",
                                    "ManagedPolicyArns" : ["arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"],
                                    "Policies": [
                                        {
                                            "PolicyName": "${tier.Id}-${component.Id}-docker",
                                            "PolicyDocument" : {
                                                "Version": "2012-10-17",
                                                "Statement": [
                                                    {
                                                        "Effect": "Allow",
                                                        "Action": ["s3:GetObject"],
                                                        "Resource": [
                                                            "arn:aws:s3:::${credentialsBucket}/${accountId}/alm/docker/*"
                                                        ]
                                                    },
                                                    [#if fixedIP]
                                                        {
                                                            "Effect" : "Allow",
                                                            "Action" : [
                                                                "ec2:DescribeAddresses",
                                                                "ec2:AssociateAddress"
                                                            ],
                                                            "Resource": "*"
                                                        },
                                                    [/#if]
                                                    {
                                                        "Resource": [
                                                            "arn:aws:s3:::${codeBucket}",
                                                            "arn:aws:s3:::${logsBucket}"
                                                        ],
                                                        "Action": [
                                                            "s3:List*"
                                                        ],
                                                        "Effect": "Allow"
                                                    },
                                                    {
                                                        "Resource": [
                                                            "arn:aws:s3:::${codeBucket}/*"
                                                        ],
                                                        "Action": [
                                                            "s3:GetObject"
                                                        ],
                                                        "Effect": "Allow"
                                                    },
                                                    {
                                                        "Resource": [
                                                            "arn:aws:s3:::${logsBucket}/*"
                                                        ],
                                                        "Action": [
                                                            "s3:PutObject"
                                                        ],
                                                        "Effect": "Allow"
                                                    }
                                                    [#if getKey("cmkXsegmentXcmk")??]
                                                    ,{
                                                        "Resource": [
                                                            { 
                                                                "Fn::Join" : [
                                                                    "", 
                                                                    [
                                                                        "arn:aws:kms:${regionId}:", 
                                                                        {"Ref" : "AWS::AccountId"}, 
                                                                        ":key/${getKey("cmkXsegmentXcmk")}"
                                                                    ]
                                                                ]
                                                            }
                                                        ],
                                                        "Action": [
                                                            "kms:Decrypt"
                                                        ],
                                                        "Effect": "Allow"
                                                    }
                                                    [/#if]
                                                ]
                                            }
                                        }
                                    ]
                                }
                            },
                
                            "instanceProfileX${tier.Id}X${component.Id}" : {
                                "Type" : "AWS::IAM::InstanceProfile",
                                "Properties" : {
                                    "Path" : "/",
                                    "Roles" : [ { "Ref" : "roleX${tier.Id}X${component.Id}" } ]
                                }
                            },
                    
                            "roleX${tier.Id}X${component.Id}Xservice": {
                                "Type" : "AWS::IAM::Role",
                                "Properties" : {
                                    "AssumeRolePolicyDocument" : {
                                        "Version": "2012-10-17",
                                        "Statement": [ 
                                            {
                                                "Effect": "Allow",
                                                "Principal": { "Service": [ "ecs.amazonaws.com" ] },
                                                "Action": [ "sts:AssumeRole" ]
                                            }
                                        ]
                                    },
                                    "Path": "/",
                                    "ManagedPolicyArns" : ["arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"]
                                }
                            },
                    
                            [#if fixedIP]
                                [#list 1..maxSize as index]
                                    "eipX${tier.Id}X${component.Id}X${index}": {
                                        "Type" : "AWS::EC2::EIP",
                                        "Properties" : {
                                            "Domain" : "vpc"
                                        }
                                    },
                                [/#list]
                            [/#if]
                
                            "asgX${tier.Id}X${component.Id}": {
                                "Type": "AWS::AutoScaling::AutoScalingGroup",
                                "Metadata": {
                                    "AWS::CloudFormation::Init": {
                                        "configSets" : {
                                            "ecs" : ["dirs", "bootstrap", "ecs"]
                                        },
                                        "dirs": {
                                            "commands": {
                                                "01Directories" : {
                                                    "command" : "mkdir --parents --mode=0755 /etc/gosource && mkdir --parents --mode=0755 /opt/gosource/bootstrap && mkdir --parents --mode=0755 /var/log/gosource",
                                                    "ignoreErrors" : "false"
                                                }
                                            }
                                        },
                                        "bootstrap": {
                                            "packages" : {
                                                "yum" : {
                                                    "aws-cli" : []
                                                }
                                            },
                                            "files" : {
                                                "/etc/gosource/facts.sh" : {
                                                    "content" : { 
                                                        "Fn::Join" : [
                                                            "", 
                                                            [
                                                                "#!/bin/bash\n",
                                                                "echo \"gs:accountRegion=${accountRegionId}\"\n",
                                                                "echo \"gs:account=${accountId}\"\n",
                                                                "echo \"gs:project=${projectId}\"\n",
                                                                "echo \"gs:region=${regionId}\"\n",
                                                                "echo \"gs:segment=${segmentId}\"\n",
                                                                "echo \"gs:environment=${environmentId}\"\n",
                                                                "echo \"gs:tier=${tier.Id}\"\n",
                                                                "echo \"gs:component=${component.Id}\"\n",
                                                                "echo \"gs:role=${component.Role}\"\n",
                                                                "echo \"gs:credentials=${credentialsBucket}\"\n",
                                                                "echo \"gs:code=${codeBucket}\"\n",
                                                                "echo \"gs:logs=${logsBucket}\"\n",
                                                                "echo \"gs:backup=${backupsBucket}\"\n"
                                                            ]
                                                        ]
                                                    },
                                                    "mode" : "000755"
                                                },
                                                "/opt/gosource/bootstrap/fetch.sh" : {
                                                    "content" : { 
                                                        "Fn::Join" : [
                                                            "", 
                                                            [
                                                                "#!/bin/bash -ex\n",
                                                                "exec > >(tee /var/log/gosource/fetch.log|logger -t gosource-fetch -s 2>/dev/console) 2>&1\n",
                                                                "REGION=$(/etc/gosource/facts.sh | grep gs:accountRegion= | cut -d '=' -f 2)\n",
                                                                "CODE=$(/etc/gosource/facts.sh | grep gs:code= | cut -d '=' -f 2)\n",
                                                                "aws --region ${r"${REGION}"} s3 sync s3://${r"${CODE}"}/bootstrap/centos/ /opt/gosource/bootstrap && chmod 0755 /opt/gosource/bootstrap/*.sh\n"
                                                            ]
                                                        ]
                                                    },
                                                    "mode" : "000755"
                                                }
                                            },
                                            "commands": {
                                                "01Fetch" : {
                                                    "command" : "/opt/gosource/bootstrap/fetch.sh",
                                                    "ignoreErrors" : "false"
                                                },
                                                "02Initialise" : {
                                                    "command" : "/opt/gosource/bootstrap/init.sh",
                                                    "ignoreErrors" : "false"
                                                }
                                                [#if fixedIP]
                                                    ,"03AssignIP" : {
                                                        "command" : "/opt/gosource/bootstrap/eip.sh",
                                                        "env" : { 
                                                            "EIP_ALLOCID" : { 
                                                                "Fn::Join" : [
                                                                    " ", 
                                                                    [
                                                                        [#list 1..maxSize as index]
                                                                            { "Fn::GetAtt" : ["eipX${tier.Id}X${component.Id}X${index}", "AllocationId"] }
                                                                            [#if index != maxSize],[/#if]
                                                                        [/#list]
                                                                    ]
                                                                ]
                                                            }
                                                        },
                                                        "ignoreErrors" : "false"
                                                    }
                                                [/#if]
                                                }
                                            },
                                            "ecs": {
                                                "commands": {
                                                    "01Fluentd" : {
                                                        "command" : "/opt/gosource/bootstrap/fluentd.sh",
                                                        "ignoreErrors" : "false"
                                                    },
                                                    "02ConfigureCluster" : {
                                                        "command" : "/opt/gosource/bootstrap/ecs.sh",
                                                        "env" : { 
                                                        "ECS_CLUSTER" : { "Ref" : "ecsX${tier.Id}X${component.Id}" },
                                                        "ECS_LOG_DRIVER" : "fluentd"
                                                    },
                                                    "ignoreErrors" : "false"
                                                }
                                            }
                                        }
                                    }
                                },
                                "Properties": {
                                    "Cooldown" : "30",
                                    "LaunchConfigurationName": {"Ref": "launchConfigX${tier.Id}X${component.Id}"},
                                    [#if multiAZ]
                                        "MinSize": "${processorProfile.MinPerZone * zoneCount}",
                                        "MaxSize": "${maxSize}",
                                        "DesiredCapacity": "${processorProfile.DesiredPerZone * zoneCount}",
                                        "VPCZoneIdentifier": [ 
                                            [#list azList as zone]
                                                "${getKey("subnetX"+tier.Id+"X"+zone)}"[#if !(zone == lastZone)],[/#if]
                                            [/#list]
                                        ],
                                    [#else]
                                        "MinSize": "${processorProfile.MinPerZone}",
                                        "MaxSize": "${maxSize}",
                                        "DesiredCapacity": "${processorProfile.DesiredPerZone}",
                                        "VPCZoneIdentifier" : ["${getKey("subnetX"+tier.Id+"X"+firstZone)}"],
                                    [/#if]
                                    "Tags" : [
                                        { "Key" : "gs:account", "Value" : "${accountId}", "PropagateAtLaunch" : "True" },
                                        { "Key" : "gs:project", "Value" : "${projectId}", "PropagateAtLaunch" : "True" },
                                        { "Key" : "gs:segment", "Value" : "${segmentId}", "PropagateAtLaunch" : "True" },
                                        { "Key" : "gs:environment", "Value" : "${environmentId}", "PropagateAtLaunch" : "True" },
                                        { "Key" : "gs:category", "Value" : "${categoryId}", "PropagateAtLaunch" : "True" },
                                        { "Key" : "gs:tier", "Value" : "${tier.Id}", "PropagateAtLaunch" : "True" },
                                        { "Key" : "gs:component", "Value" : "${component.Id}", "PropagateAtLaunch" : "True"},
                                        { "Key" : "Name", "Value" : "${projectName}-${segmentName}-${tier.Name}-${component.Name}", "PropagateAtLaunch" : "True" }
                                    ]
                                }
                            },
                    
                            "launchConfigX${tier.Id}X${component.Id}": {
                                "Type": "AWS::AutoScaling::LaunchConfiguration",
                                "Properties": {
                                    "KeyName": "${projectName + sshPerSegment?string("-" + segmentName,"")}",
                                    "ImageId": "${regionObject.AMIs.Centos.ECS}",
                                    "InstanceType": "${processorProfile.Processor}",
                                    [@createBlockDevices storageProfile=storageProfile /]
                                    "SecurityGroups" : [ {"Ref" : "securityGroupX${tier.Id}X${component.Id}"} [#if securityGroupNAT != "none"], "${securityGroupNAT}"[/#if] ], 
                                    "IamInstanceProfile" : { "Ref" : "instanceProfileX${tier.Id}X${component.Id}" },
                                    "AssociatePublicIpAddress" : ${((solutionTier.RouteTable!tier.RouteTable) == "external")?string("true","false")},
                                    [#if (processorProfile.ConfigSet)??]
                                        [#assign configSet = processorProfile.ConfigSet]
                                    [#else]
                                        [#assign configSet = "ecs"]
                                    [/#if]
                                    "UserData" : { 
                                        "Fn::Base64" : { 
                                            "Fn::Join" : [
                                                "", 
                                                [
                                                    "#!/bin/bash -ex\n",
                                                    "exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1\n",
                                                    "yum install -y aws-cfn-bootstrap\n",
                                                    "# Remainder of configuration via metadata\n",
                                                    "/opt/aws/bin/cfn-init -v",
                                                    "         --stack ", { "Ref" : "AWS::StackName" },
                                                    "         --resource asgX${tier.Id}X${component.Id}",
                                                    "         --region ${regionId} --configsets ${configSet}\n"
                                                ]
                                            ]
                                        }
                                    }
                                }
                            }
                            [#assign count = count + 1]
                        [/#if]

                        [#-- ElastiCache --]
                        [#if component.ElastiCache??]
                            [#assign cache = component.ElastiCache]
                            [#assign engine = cache.Engine]
                            [#switch engine]
                                [#case "memcached"]
                                    [#if cache.EngineVersion??]
                                        [#assign engineVersion = cache.EngineVersion]
                                    [#else]
                                        [#assign engineVersion = "1.4.24"]
                                    [/#if]
                                    [#assign familyVersionIndex = engineVersion?last_index_of(".") - 1]
                                    [#assign family = "memcached" + engineVersion[0..familyVersionIndex]]
                                    [#break]
            
                                [#case "redis"]
                                    [#if cache.EngineVersion??]
                                        [#assign engineVersion = cache.EngineVersion]
                                    [#else]
                                        [#assign engineVersion = "2.8.24"]
                                    [/#if]
                                    [#assign familyVersionIndex = engineVersion?last_index_of(".") - 1]
                                    [#assign family = "redis" + engineVersion[0..familyVersionIndex]]
                                    [#break]
                            [/#switch]
                            "securityGroupIngressX${tier.Id}X${component.Id}" : {
                                "Type" : "AWS::EC2::SecurityGroupIngress",
                                "Properties" : {
                                    "GroupId": {"Ref" : "securityGroupX${tier.Id}X${component.Id}"},
                                    "IpProtocol": "${ports[cache.Port].IPProtocol}", 
                                    "FromPort": "${ports[cache.Port].Port?c}", 
                                    "ToPort": "${ports[cache.Port].Port?c}", 
                                    "CidrIp": "0.0.0.0/0"
                                }
                            },
                            "cacheSubnetGroupX${tier.Id}X${component.Id}" : {
                                "Type" : "AWS::ElastiCache::SubnetGroup",
                                "Properties" : {
                                    "Description" : "${projectName}-${segmentName}-${tier.Name}-${component.Name}",
                                    "SubnetIds" : [ 
                                        [#list azList as zone]
                                            "${getKey("subnetX"+tier.Id+"X"+zone)}"[#if !(zone == lastZone)],[/#if]
                                        [/#list]
                                    ]
                                }
                            },
                            "cacheParameterGroupX${tier.Id}X${component.Id}" : {
                                "Type" : "AWS::ElastiCache::ParameterGroup",
                                "Properties" : {
                                    "CacheParameterGroupFamily" : "${family}",
                                    "Description" : "Parameter group for ${tier.Id}-${component.Id}",
                                    "Properties" : {
                                    }
                                }
                            },
                            [#assign processorProfile = getProcessor(tier, component, "ElastiCache")]
                            "cacheX${tier.Id}X${component.Id}":{
                                "Type":"AWS::ElastiCache::CacheCluster",
                                "Properties":{
                                    "Engine": "${cache.Engine}",
                                    "EngineVersion": "${engineVersion}",
                                    "CacheNodeType" : "${processorProfile.Processor}",
                                    "Port" : ${ports[cache.Port].Port?c},
                                    "CacheParameterGroupName": { "Ref" : "cacheParameterGroupX${tier.Id}X${component.Id}" },
                                    "CacheSubnetGroupName": { "Ref" : "cacheSubnetGroupX${tier.Id}X${component.Id}" },
                                    [#if multiAZ]
                                        "AZMode": "cross-az",
                                        "PreferredAvailabilityZones" : [
                                            [#assign countPerZone = processorProfile.CountPerZone]
                                            [#assign zoneCount = 0]
                                            [#list regionObject.Zones as zone]
                                                [#if azList?seq_contains(zone.Id)]
                                                    [#list 1..countPerZone as i]
                                                        [#if zoneCount > 0],[/#if]
                                                        "${zone.AWSZone}"
                                                        [#assign zoneCount = zoneCount + 1]
                                                    [/#list]
                                                [/#if]
                                            [/#list]
                                        ],
                                        "NumCacheNodes" : "${processorProfile.CountPerZone * zoneCount}",
                                    [#else]
                                        "AZMode": "single-az",
                                        [#list regionObject.Zones as zone]
                                            [#if firstZone == zone.Id]
                                                "PreferredAvailabilityZone" : "${zone.AWSZone}",
                                            [/#if]
                                        [/#list]
                                        "NumCacheNodes" : "${processorProfile.CountPerZone}",
                                    [/#if]
                                    [#if (cache.SnapshotRetentionLimit)??]
                                        "SnapshotRetentionLimit" : ${cache.SnapshotRetentionLimit}
                                    [/#if]
                                    "VpcSecurityGroupIds":[
                                        { "Ref" : "securityGroupX${tier.Id}X${component.Id}" }
                                    ],
                                    "Tags" : [
                                        { "Key" : "gs:account", "Value" : "${accountId}" },
                                        { "Key" : "gs:project", "Value" : "${projectId}" },
                                        { "Key" : "gs:segment", "Value" : "${segmentId}" },
                                        { "Key" : "gs:environment", "Value" : "${environmentId}" },
                                        { "Key" : "gs:category", "Value" : "${categoryId}" },
                                        { "Key" : "gs:tier", "Value" : "${tier.Id}" },
                                        { "Key" : "gs:component", "Value" : "${component.Id}" },
                                        { "Key" : "Name", "Value" : "${projectName}-${segmentName}-${tier.Name}-${component.Name}" } 
                                    ]
                                }
                            }
                            [#assign count = count + 1]
                        [/#if]
                        
                        [#-- RDS --]
                        [#if component.RDS??]
                            [#assign db = component.RDS]
                            [#assign engine = db.Engine]
                            [#switch engine]
                                [#case "mysql"]
                                    [#if db.EngineVersion??]
                                        [#assign engineVersion = db.EngineVersion]
                                    [#else]
                                        [#assign engineVersion = "5.6"]
                                    [/#if]
                                    [#assign family = "mysql" + engineVersion]
                                [#break]
                            
                                [#case "postgres"]
                                    [#if db.EngineVersion??]
                                        [#assign engineVersion = db.EngineVersion]
                                    [#else]
                                        [#assign engineVersion = "9.4"]
                                    [/#if]
                                    [#assign family = "postgres" + engineVersion]
                                    [#break]
                            [/#switch]
                            "securityGroupIngressX${tier.Id}X${component.Id}" : {
                                "Type" : "AWS::EC2::SecurityGroupIngress",
                                "Properties" : {
                                    "GroupId": {"Ref" : "securityGroupX${tier.Id}X${component.Id}"},
                                    "IpProtocol": "${ports[db.Port].IPProtocol}", 
                                    "FromPort": "${ports[db.Port].Port?c}", 
                                    "ToPort": "${ports[db.Port].Port?c}", 
                                    "CidrIp": "0.0.0.0/0"
                                }
                            },
                            "rdsSubnetGroupX${tier.Id}X${component.Id}" : {
                                "Type" : "AWS::RDS::DBSubnetGroup",
                                "Properties" : {
                                    "DBSubnetGroupDescription" : "${projectName}-${segmentName}-${tier.Name}-${component.Name}",
                                    "SubnetIds" : [ 
                                        [#list azList as zone]
                                            "${getKey("subnetX"+tier.Id+"X"+zone)}"
                                            [#if !(zone == lastZone)],[/#if]
                                        [/#list]
                                    ],
                                    "Tags" : [
                                        { "Key" : "gs:account", "Value" : "${accountId}" },
                                        { "Key" : "gs:project", "Value" : "${projectId}" },
                                        { "Key" : "gs:segment", "Value" : "${segmentId}" },
                                        { "Key" : "gs:environment", "Value" : "${environmentId}" },
                                        { "Key" : "gs:category", "Value" : "${categoryId}" },
                                        { "Key" : "gs:tier", "Value" : "${tier.Id}" },
                                        { "Key" : "gs:component", "Value" : "${component.Id}" },
                                        { "Key" : "Name", "Value" : "${projectName}-${segmentName}-${tier.Name}-${component.Name}" } 
                                    ]
                                }
                            },
                            "rdsParameterGroupX${tier.Id}X${component.Id}" : {
                                "Type" : "AWS::RDS::DBParameterGroup",
                                "Properties" : {
                                    "Family" : "${family}",
                                    "Description" : "Parameter group for ${tier.Id}-${component.Id}",
                                    "Parameters" : {
                                    },
                                    "Tags" : [
                                        { "Key" : "gs:account", "Value" : "${accountId}" },
                                        { "Key" : "gs:project", "Value" : "${projectId}" },
                                        { "Key" : "gs:segment", "Value" : "${segmentId}" },
                                        { "Key" : "gs:environment", "Value" : "${environmentId}" },
                                        { "Key" : "gs:category", "Value" : "${categoryId}" },
                                        { "Key" : "gs:tier", "Value" : "${tier.Id}" },
                                        { "Key" : "gs:component", "Value" : "${component.Id}" },
                                        { "Key" : "Name", "Value" : "${projectName}-${segmentName}-${tier.Name}-${component.Name}" } 
                                    ]
                                }
                            },
                            "rdsOptionGroupX${tier.Id}X${component.Id}" : {
                                "Type" : "AWS::RDS::OptionGroup",
                                "Properties" : {
                                    "EngineName": "${engine}",
                                    "MajorEngineVersion": "${engineVersion}",
                                    "OptionGroupDescription" : "Option group for ${tier.Id}/${component.Id}",
                                    "OptionConfigurations" : [
                                    ],
                                    "Tags" : [
                                        { "Key" : "gs:account", "Value" : "${accountId}" },
                                        { "Key" : "gs:project", "Value" : "${projectId}" },
                                        { "Key" : "gs:segment", "Value" : "${segmentId}" },
                                        { "Key" : "gs:environment", "Value" : "${environmentId}" },
                                        { "Key" : "gs:category", "Value" : "${categoryId}" },
                                        { "Key" : "gs:tier", "Value" : "${tier.Id}" },
                                        { "Key" : "gs:component", "Value" : "${component.Id}" },
                                        { "Key" : "Name", "Value" : "${projectName}-${segmentName}-${tier.Name}-${component.Name}" } 
                                    ]
                                }
                            },
                            [#assign processorProfile = getProcessor(tier, component, "RDS")]
                            "rdsX${tier.Id}X${component.Id}":{
                                "Type":"AWS::RDS::DBInstance",
                                "Properties":{
                                    "Engine": "${engine}",
                                    "EngineVersion": "${engineVersion}",
                                    "DBInstanceClass" : "${processorProfile.Processor}",
                                    "AllocatedStorage": "${db.Size}",
                                    "StorageType" : "gp2",
                                    "Port" : "${ports[db.Port].Port?c}",
                                    "MasterUsername": "${credentialsObject[tier.Id + "-" + component.Id].Login.Username}",
                                    "MasterUserPassword": "${credentialsObject[tier.Id + "-" + component.Id].Login.Password}",
                                    "BackupRetentionPeriod" : "${db.Backup.RetentionPeriod}",
                                    "DBInstanceIdentifier": "${projectName}-${segmentName}-${tier.Name}-${component.Name}",
                                    "DBName": "${projectName}",
                                    "DBSubnetGroupName": { "Ref" : "rdsSubnetGroupX${tier.Id}X${component.Id}" },
                                    "DBParameterGroupName": { "Ref" : "rdsParameterGroupX${tier.Id}X${component.Id}" },
                                    "OptionGroupName": { "Ref" : "rdsOptionGroupX${tier.Id}X${component.Id}" },
                                    [#if multiAZ]
                                        "MultiAZ": true,
                                    [#else]
                                        [#list regionObject.Zones as zone]
                                            [#if firstZone == zone.Id]
                                                "AvailabilityZone" : "${zone.AWSZone}",
                                            [/#if]
                                        [/#list]
                                    [/#if]
                                    "VPCSecurityGroups":[
                                        { "Ref" : "securityGroupX${tier.Id}X${component.Id}" }
                                    ],
                                    "Tags" : [
                                        { "Key" : "gs:account", "Value" : "${accountId}" },
                                        { "Key" : "gs:project", "Value" : "${projectId}" },
                                        { "Key" : "gs:segment", "Value" : "${segmentId}" },
                                        { "Key" : "gs:environment", "Value" : "${environmentId}" },
                                        { "Key" : "gs:category", "Value" : "${categoryId}" },
                                        { "Key" : "gs:tier", "Value" : "${tier.Id}" },
                                        { "Key" : "gs:component", "Value" : "${component.Id}" },
                                        { "Key" : "Name", "Value" : "${projectName}-${segmentName}-${tier.Name}-${component.Name}" } 
                                    ]
                                }
                            }
                            [#assign count = count + 1]
                        [/#if]
                        [#-- ElasticSearch --]
                        [#if component.ElasticSearch??]
                            [#assign es = component.ElasticSearch]
                            [#assign processorProfile = getProcessor(tier, component, "ElasticSearch")]
                            [#assign storageProfile = getStorage(tier, component, "ElasticSearch")]
                            "esX${tier.Id}X${component.Id}":{
                                "Type" : "AWS::Elasticsearch::Domain",
                                "Properties" : {
                                    "AccessPolicies" : {
                                        "Version": "2012-10-17",
                                        "Statement": [
                                            {
                                                "Sid": "",
                                                "Effect": "Allow",
                                                "Principal": {
                                                    "AWS": "*"
                                                },
                                                "Action": "es:*",
                                                "Resource": "*",
                                                "Condition": {
                                                    "IpAddress": {
                                                        [#assign ipCount = 0]
                                                        "aws:SourceIp": [
                                                            [#list azList as zone]
                                                                [#if (getKey("eipXmgmtXnatX" + zone + "Xip")??)]
                                                                    [#if ipCount > 0],[/#if]
                                                                    "${getKey("eipXmgmtXnatX" + zone + "Xip")}"
                                                                    [#assign ipCount = ipCount + 1]
                                                                [/#if]
                                                            [/#list]
                                                            [#list 1..20 as i]
                                                                [#if (getKey("eipXmgmtXnatXexternalX" + i)??)]
                                                                    [#if ipCount > 0],[/#if]
                                                                    "${getKey("eipXmgmtXnatXexternalX" + i)}"
                                                                    [#assign ipCount = ipCount + 1]
                                                                [/#if]
                                                            [/#list]
                                                        ]
                                                    }
                                                }
                                            }
                                        ]
                                    },
                                    [#if es.AdvancedOptions??]
                                        "AdvancedOptions" : {
                                            [#list es.AdvancedOptions as option]
                                                "${option.Id}" : "${option.Value}"
                                                [#if option.Id != es.AdvancedOptions?last.Id],[/#if]
                                            [/#list]
                                        },
                                    [/#if]
                                    "DomainName" : "${projectName}-${segmentId}-${tier.Id}-${component.Id}",
                                    [#if (storageProfile.Volumes)?? && (storageProfile.Volumes?size > 0)]
                                        [#assign volume = storageProfile.Volumes[0]]
                                        "EBSOptions" : {
                                            "EBSEnabled" : true,
                                            [#if volume.Iops??]"Iops" : ${volume.Iops},[/#if]
                                            "VolumeSize" : ${volume.Size},
                                            [#if volume.Type??]
                                                "VolumeType" : "${volume.Type}"
                                            [#else]
                                                "VolumeType" : "gp2"
                                            [/#if]
                                        },
                                    [/#if]
                                    "ElasticsearchClusterConfig" : {
                                        [#if processorProfile.Master??]
                                            [#assign master = processorProfile.Master]
                                            "DedicatedMasterEnabled" : true,
                                            "DedicatedMasterCount" : ${master.Count},
                                            "DedicatedMasterType" : "${master.Processor}",
                                        [#else]
                                            "DedicatedMasterEnabled" : false,
                                        [/#if]
                                        "InstanceType" : "${processorProfile.Processor}",
                                        "ZoneAwarenessEnabled" : ${multiAZ?string("true","false")},
                                        [#if multiAZ]
                                            "InstanceCount" : ${processorProfile.CountPerZone * zoneCount}
                                        [#else]
                                            "InstanceCount" : ${processorProfile.CountPerZone}
                                        [/#if]
                                    },
                                    [#if (es.Snapshot.Hour)??]
                                        "SnapshotOptions" : {
                                            "AutomatedSnapshotStartHour" : ${es.Snapshot.Hour}
                                        },
                                    [/#if]
                                    "Tags" : [
                                        { "Key" : "gs:account", "Value" : "${accountId}" },
                                        { "Key" : "gs:project", "Value" : "${projectId}" },
                                        { "Key" : "gs:segment", "Value" : "${segmentId}" },
                                        { "Key" : "gs:environment", "Value" : "${environmentId}" },
                                        { "Key" : "gs:category", "Value" : "${categoryId}" },
                                        { "Key" : "gs:tier", "Value" : "${tier.Id}" },
                                        { "Key" : "gs:component", "Value" : "${component.Id}" }
                                    ]
                                }
                            }
                            [#assign count = count + 1]
                        [/#if]
                    [/#if]
                [/#list]
            [/#if]
        [/#list]
    },
    
    "Outputs" : {
        [#assign count = 0]
        [#list solutionObject.Tiers as solutionTier]
            [#assign tier = tiers[solutionTier.Id]]
            [#if solutionTier.Components??]
                [#list solutionTier.Components as component]
                    [#assign slices = component.Slices!solutionTier.Slices!tier.Slices]
                    [#if !(slice??) || (slices?seq_contains(slice))]
                        [#if component.MultiAZ??] 
                            [#assign multiAZ =  component.MultiAZ]
                        [#else]
                            [#assign multiAZ =  solnMultiAZ]
                        [/#if]
                        
                        [#-- Security Group --]
                        [#if ! (component.S3?? || component.SQS??) ]
                            [#if count > 0],[/#if]
                            "securityGroupX${tier.Id}X${component.Id}" : {
                                "Value" : { "Ref" : "securityGroupX${tier.Id}X${component.Id}" }
                            }
                            [#assign count = count + 1]
                        [/#if]
                        
                        [#-- S3 --]
                        [#if component.S3??]
                            [#if count > 0],[/#if]
                            "s3X${tier.Id}X${component.Id}" : {
                                "Value" : { "Ref" : "s3X${tier.Id}X${component.Id}" }
                            },
                            "s3X${tier.Id}X${component.Id}Xurl" : {
                                "Value" : { "Fn::GetAtt" : ["s3X${tier.Id}X${component.Id}", "WebsiteURL"] }
                            }
                            [#assign count = count + 1]
                        [/#if]
                        
                        [#-- SQS --]
                        [#if component.SQS??]
                            [#assign sqs = component.SQS]
                            [#if count > 0],[/#if]
                            "sqsX${tier.Id}X${component.Id}" : {
                                "Value" : { "Fn::GetAtt" : ["sqsX${tier.Id}X${component.Id}", "QueueName"] }
                            },
                            "sqsX${tier.Id}X${component.Id}Xurl" : {
                                "Value" : { "Ref" : "sqsX${tier.Id}X${component.Id}" }
                            },
                            "sqsX${tier.Id}X${component.Id}Xarn" : {
                                "Value" : { "Fn::GetAtt" : ["sqsX${tier.Id}X${component.Id}", "Arn"] }
                            }
                        [/#if]
                        
                        [#-- ELB --]
                        [#if component.ELB??]
                            [#if count > 0],[/#if]
                            "elbX${tier.Id}X${component.Id}" : {
                                "Value" : { "Ref" : "elbX${tier.Id}X${component.Id}" }
                            },
                            "elbX${tier.Id}X${component.Id}Xdns" : {
                                "Value" : { "Fn::GetAtt" : ["elbX${tier.Id}X${component.Id}", "DNSName"] }
                            }
                            [#assign count = count + 1]
                        [/#if]

                        [#-- EC2 --]
                        [#if component.EC2??]
                            [#if count > 0],[/#if]
                            "roleX${tier.Id}X${component.Id}" : {
                                "Value" : { "Ref" : "roleX${tier.Id}X${component.Id}" }
                            },
                            "roleX${tier.Id}X${component.Id}Xarn" : {
                                "Value" : { "Fn::GetAtt" : ["roleX${tier.Id}X${component.Id}", "Arn"] }
                            }
                            [#assign count = count + 1]
                        [/#if]
                        
                        [#-- ECS --]
                        [#if component.ECS??]
                            [#assign ecs = component.ECS]
                            [#if count > 0],[/#if]
                            "ecsX${tier.Id}X${component.Id}" : {
                                "Value" : { "Ref" : "ecsX${tier.Id}X${component.Id}" }
                            },
                            "roleX${tier.Id}X${component.Id}" : {
                                "Value" : { "Ref" : "roleX${tier.Id}X${component.Id}" }
                            },
                            "roleX${tier.Id}X${component.Id}Xarn" : {
                                "Value" : { "Fn::GetAtt" : ["roleX${tier.Id}X${component.Id}", "Arn"] }
                            },
                            "roleX${tier.Id}X${component.Id}Xservice" : {
                                "Value" : { "Ref" : "roleX${tier.Id}X${component.Id}Xservice" }
                            },
                            "roleX${tier.Id}X${component.Id}XserviceXarn" : {
                                "Value" : { "Fn::GetAtt" : ["roleX${tier.Id}X${component.Id}Xservice", "Arn"] }
                            }
                            [#if ecs.FixedIP?? && ecs.FixedIP]
                                [#assign processorProfile = getProcessor(tier, component, "ECS")]
                                [#assign maxSize = processorProfile.MaxPerZone]
                                [#if multiAZ]
                                    [#assign maxSize = maxSize * zoneCount]
                                [/#if]
                                [#list 1..maxSize as index]
                                    ,"eipX${tier.Id}X${component.Id}X${index}Xip": {
                                        "Value" : { "Ref" : "eipX${tier.Id}X${component.Id}X${index}" }
                                    }
                                    ,"eipX${tier.Id}X${component.Id}X${index}Xid": {
                                        "Value" : { "Fn::GetAtt" : ["eipX${tier.Id}X${component.Id}X${index}", "AllocationId"] }
                                    }
                                [/#list]
                            [/#if]
                            [#assign count = count + 1]
                        [/#if]
                        
                        [#-- ElastiCache --]
                        [#if component.ElastiCache??]
                            [#assign cache = component.ElastiCache]
                            [#if cache.Engine == "memcached"]
                                [#if count > 0],[/#if]
                                "cacheX${tier.Id}X${component.Id}Xdns" : {
                                   "Value" : { "Fn::GetAtt" : ["cacheX${tier.Id}X${component.Id}", "ConfigurationEndpoint.Address"] }
                                },
                                "cacheX${tier.Id}X${component.Id}Xport" : {
                                    "Value" : { "Fn::GetAtt" : ["cacheX${tier.Id}X${component.Id}", "ConfigurationEndpoint.Port"] }
                                }
                                [#assign count = count + 1]
                            [/#if]
                        [/#if]
                        
                        [#-- RDS --]
                        [#if component.RDS??]
                            [#if count > 0],[/#if]
                            "rdsX${tier.Id}X${component.Id}Xdns" : {
                                "Value" : { "Fn::GetAtt" : ["rdsX${tier.Id}X${component.Id}", "Endpoint.Address"] }
                            },
                            "rdsX${tier.Id}X${component.Id}Xport" : {
                                "Value" : { "Fn::GetAtt" : ["rdsX${tier.Id}X${component.Id}", "Endpoint.Port"] }
                            },
                            "rdsX${tier.Id}X${component.Id}Xdatabasename" : {
                                "Value" : "${projectName}"
                            },
                            "rdsX${tier.Id}X${component.Id}Xusername" : {
                                "Value" : "${credentialsObject[tier.Id + "-" + component.Id].Login.Username}"
                            },
                            "rdsX${tier.Id}X${component.Id}Xpassword" : {
                                "Value" : "${credentialsObject[tier.Id + "-" + component.Id].Login.Password}"
                            }
                            [#assign count = count + 1]
                        [/#if]

                        [#-- ElasticSearch --]
                        [#if component.ElasticSearch??]
                            [#assign es = component.ElasticSearch]
                            [#if count > 0],[/#if]
                            "esX${tier.Id}X${component.Id}" : {
                                "Value" : { "Ref" : "esX${tier.Id}X${component.Id}" }
                            },
                            "esX${tier.Id}X${component.Id}Xdns" : {
                                "Value" : { "Fn::GetAtt" : ["esX${tier.Id}X${component.Id}", "DomainEndpoint"] }
                            },
                            "esX${tier.Id}X${component.Id}Xarn" : {
                                "Value" : { "Fn::GetAtt" : ["esX${tier.Id}X${component.Id}", "DomainArn"] }
                            }
                            [#assign count = count + 1]
                        [/#if]
                    [/#if]
                [/#list]
            [/#if]
        [/#list]
    }
}
