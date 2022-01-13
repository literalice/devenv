import * as path from 'path';
import { Stack, StackProps, Tags, Size } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { Asset } from 'aws-cdk-lib/aws-s3-assets'

export class DevenvStack extends Stack {
  
  fleetId: string;

  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    const capacity = this.node.tryGetContext('devenvTerminated') ? 0 : 1;

    // Machine Image
    const machineImage = ec2.MachineImage.latestAmazonLinux({
      generation: ec2.AmazonLinuxGeneration.AMAZON_LINUX_2,
    });

    const launchTemplateRole = new iam.Role(this, 'LaunchTemplateRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AdministratorAccess'),
      ]
    });

    const kmsKey = kms.Key.fromKeyArn(this, 'SessionManagerKmsKey', this.node.tryGetContext('sessionManagerEncryptKmsKeyArn'));
    kmsKey.grantEncryptDecrypt(launchTemplateRole);

    const vpc = new ec2.Vpc(this, 'DevVPC', {
      cidr: '10.121.0.0/16',
      natGateways: 1,
    });
    Tags.of(vpc).add('Name', 'devenv');

    // Volume
    const homeVolume = new ec2.Volume(this, 'Volume', {
      availabilityZone: vpc.availabilityZones[0],
      volumeType: ec2.EbsDeviceVolumeType.GP3,
      size: Size.gibibytes(128),
      encrypted: true,
    });
    // homeVolume.grantAttachVolume(launchTemplateRole);
    // launchTemplateRole.addToPolicy(new iam.PolicyStatement({
    //   actions: ['ec2:DescribeVolumes'],
    //   resources: [ '*' ]
    // }));
    Tags.of(homeVolume).add('Name', 'devenv');

    // User Data
    const userdata = new Asset(this, 'UserDataAsset', {
      path: path.join(__dirname, '../assets', 'userdata.sh')
    });

    const launchTemplateUserData = ec2.UserData.forLinux();
    const localPath = launchTemplateUserData.addS3DownloadCommand({
      bucket: userdata.bucket,
      bucketKey: userdata.s3ObjectKey,
    });
    launchTemplateUserData.addExecuteFileCommand({
      filePath:localPath,
      arguments: `${homeVolume.volumeId} ${this.node.tryGetContext('userId')}`,
    });
    userdata.grantRead(launchTemplateRole);

    const launchTemplate = new ec2.LaunchTemplate(this, 'LaunchTemplate', {
      machineImage,
      role: launchTemplateRole,
      keyName: this.node.tryGetContext('keyName'),
      userData: launchTemplateUserData,
      ebsOptimized: true,
    });

    const instanceTypes = [
      ec2.InstanceType.of(ec2.InstanceClass.M5AD, ec2.InstanceSize.XLARGE2),
      ec2.InstanceType.of(ec2.InstanceClass.M5D, ec2.InstanceSize.XLARGE2),
    ];

    const cfnLaunchTemplate = launchTemplate.node.defaultChild as ec2.CfnLaunchTemplate;
    const fleet = new ec2.CfnEC2Fleet(this, 'EC2Fleet', {
      launchTemplateConfigs: [{
        launchTemplateSpecification: {
          launchTemplateId: cfnLaunchTemplate.ref,
          version: cfnLaunchTemplate.attrLatestVersionNumber,
        },
        overrides: instanceTypes.map(instanceType => {
          return {
            instanceType: instanceType.toString(),
            availabilityZone: vpc.availabilityZones[0],
          }
        }),
      }],
      targetCapacitySpecification: {
        totalTargetCapacity: capacity,
        defaultTargetCapacityType: 'spot',
      },
    });
    this.fleetId = fleet.attrFleetId;
  }
}
