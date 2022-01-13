import * as path from 'path';
import { Stack, StackProps } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as nodeLambda from 'aws-cdk-lib/aws-lambda-nodejs';

export class AutomationStack extends Stack {
  constructor(scope: Construct, id: string, fleetId: string, props?: StackProps) {
    super(scope, id, props);

    const launch = new nodeLambda.NodejsFunction(this, 'launch', {
      entry: path.join(__dirname, 'automation-stack.lambda.ts'),
      environment: {
        FLEET_ID: fleetId,
        CAPACITY: '1'
      }
    });
    launch.addToRolePolicy(new iam.PolicyStatement({
      actions: ['ec2:*'],
      resources: [ '*' ]
    }));
    const terminate = new nodeLambda.NodejsFunction(this, 'terminate', {
      entry: path.join(__dirname, 'automation-stack.lambda.ts'),
      environment: {
        FLEET_ID: fleetId,
        CAPACITY: '0'
      }
    });
    terminate.addToRolePolicy(new iam.PolicyStatement({
      actions: ['ec2:*'],
      resources: [ '*' ]
    }));
  }
}