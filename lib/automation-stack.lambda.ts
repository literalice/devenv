import { Handler } from 'aws-lambda';

type EmptyHandler = Handler<void, string>;
import { EC2Client, ModifyFleetCommand } from '@aws-sdk/client-ec2';
import { CloudFormationClient, ListExportsCommand } from '@aws-sdk/client-cloudformation';

const ec2Client = new EC2Client({});
const cloudformationClient = new CloudFormationClient({});

export const handler: EmptyHandler = async function () {
  const exports = (await cloudformationClient.send(new ListExportsCommand({})));
  const fleetId = exports.Exports?.find((entry) => {
    return entry.Name == 'DevenvFleetId'
  })?.Value;

  const output = ec2Client.send(new ModifyFleetCommand({
    FleetId: fleetId,
    TargetCapacitySpecification: {
      TotalTargetCapacity: Number(process.env.CAPACITY),
    }
  }));

  return JSON.stringify({
      message: `code: ${(await output).Return}`
  });
}
