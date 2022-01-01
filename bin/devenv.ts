#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { DevenvStack } from '../lib/devenv-stack';

const app = new cdk.App({
  context: {
    userId: process.env.DEVENV_USER_ID,
    keyName: process.env.DEVENV_KEY_NAME,
    devenvTerminated: process.env.DEVENV_TERMINATED,
    sessionManagerEncryptKmsKeyArn: process.env.SESSION_MANAGER_ENCRYPT_KMS_KEY_ARN,
  }
});
new DevenvStack(app, 'DevenvStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});