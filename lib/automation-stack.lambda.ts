import { Handler } from 'aws-lambda';

type EmptyHandler = Handler<void, string>;
import { EC2Client, ModifyFleetCommand } from '@aws-sdk/client-ec2';

export const handler: EmptyHandler = async function () {
  const ec2Client = new EC2Client({});
  const output = ec2Client.send(new ModifyFleetCommand({
    FleetId: process.env.FLEET_ID,
    TargetCapacitySpecification: {
      TotalTargetCapacity: Number(process.env.CAPACITY),
    }
  }));

  return JSON.stringify({
      message: `code: ${(await output).Return}`
  });
}
