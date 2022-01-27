import * as path from 'path';
import { Stack, StackProps } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as nodeLambda from 'aws-cdk-lib/aws-lambda-nodejs';

export class AutomationStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    const launch = new nodeLambda.NodejsFunction(this, 'launch', {
      entry: path.join(__dirname, 'automation-stack.lambda.ts'),
      environment: {
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
        CAPACITY: '0'
      }
    });
    terminate.addToRolePolicy(new iam.PolicyStatement({
      actions: ['ec2:*'],
      resources: [ '*' ]
    }));


    // Rule
    const launchRule = new events.Rule(this, 'LaunchRule', {
      schedule: events.Schedule.cron({ hour: '20', minute: '3'}),
    });
    launchRule.addTarget(new targets.LambdaFunction(launch));

    const terminateRule = new events.Rule(this, 'TerminateRule', {
      schedule: events.Schedule.cron({ hour: '15', minute: '9'}),
    });
    terminateRule.addTarget(new targets.LambdaFunction(terminate));
  }
}