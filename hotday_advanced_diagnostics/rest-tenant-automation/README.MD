# 🤖🔃👩‍💻Dynatrace REST Tenant Automation

Python program that create and automates environments via Dynatrace API and Amazon API. This small program will create for each entry in a CSV file an environment, user, user_group, an EC2 Instance with custom deployment, a custom dashboard and a synthetic test. It is highly expandable and modifiable. The results will be written in a JSON file and back into the CSV file. The rows can be controled with control-flags.

## ⚠ TODO Documentation
There has been quite some changes to the application. It has been renamed to RTA for REST Tenant Automation since it supports actions as checking the availability of EasyTravel as well as activating problem patterns via REST, connecting and managing instances on the cloud (via REST and SSH), automating SaaS and Managed tenants.
Library added sudo py -m pip install pexpect
## Features in a Nutshell

- Read and write in a CSV file controled by flags

- Write results in JSON format

- Write results back in the CSV file

  - groupId

  - tenantId

  - ec2 instance id

  - public dns of the ec2 instance

  - tenant token

- Logging
  
- Execute Remote Commands via SSH

- Create an environment, user and user_group

- Create an EC2 Instance with custom deployment **linked to each tenant**

  -  OneAgent bound to the tenant

  - Private Synthetic (and its dependencies e.g. Chromium) also bound to the tenant

  - Docker

  - PolymerShop in Docker (80)

  - BankJobs in Docker

  - EasyTravel (8080/8079), Admin Console (8094) and Angular (9080) configured

- Remove the EC2 Instance and deactivate and remove the tenant.

- Write back in the CSV file (keeping an order and keeping custom rows not needed for the program)

- Control RowFlags (true/false) for rows:

  - skip - Skip the row for the actions
  - isClusterAdmin - to add the User as a cluster admin

- Validate function to read the configuration and print the users in the CSV file.
  

## Prerequisites

python 3

pip install -r requirements.txt

aws account (optional for the ec2-actions)


## How does it work?



The Config File:

This table represents the keys and subkeys of the program:

| KEY           | SUB-KEY               | Value                                                        |
| ------------- | --------------------- | ------------------------------------------------------------ |
| cmc           | cmc_url               | The URL of the Tenant (with protocol and no leading slash)   |
| cmc           | cmc_token             |                                                              |
|               | csv_dir               | the csv directory. In here csv files will be written after an action. |
|               | csv_file              | The csv file to read the information. The program will add rows with information about the status of the action as well as the id of the tenant, usergroup tenant token, ec2 instanceId, ec2 public dns, etc..<br />The file allows also other custom rows and will not modify them. when rewriting. |
|               | log_dir               | The log directory                                            |
|               | log_file              | The log file                                                 |
| aws           | aws_dir               | The AWS directory                                            |
| aws           | user_data             | The file containing the custom deployment. TenantID and TOKEN are variables which will be replaced for each tenant. |
| action_create | create_tenant         | the create tenant action.                                    |
| action_create | create_user_group     | will create a user_group (isClusterAdminGroup) flag will be set if found in the CSV file. |
| action_create | create_user           | will create the user and bind it to the user-group.          |
| action_create | create_allinone_token | A token that is allowed to install oneagents as well as read/write configuration and read environment information. |
| action_create | create_ec2_instance   | Will create an EC2 instance for the tenant                   |
| action_create | fetch_ec2_instance    | Will fetch the public dns name of the ec2 instance           |
| action_create | set_up_env            | sets-up the environment. <br />- Modifies the default application<br />- Publish a custom dashboard pointing to the applications deployed in the ec2 instance<br />- Creates a synthetic test.<br />See set_up_environment function for expanding functionality. |
| action_delete | deactivate_tenant     | deactivates tenant                                           |
| action_delete | remove_tenant         | removes the tenant                                           |
| action_delete | delete_user_group     | deletes the user_group                                       |
| action_delete | delete_user           | deletes the user                                             |
| action_delete | delete_ec2_instance   | deletes the ec2 instance                                     |



## Tenant configuration

Each tenant will end up with its own tenant preconfigured. For expanding the configuration of the tenant take a look at the function *set_up_environment*. This will set up a custom dashboard ponting out to the deployed applications and resources for the session, a custom dashboard, a synthetic test etc.. l. For modifying the template like the dashboard just go to the skel directory and modify the dashboard.json file. 

![](doc\custom-dashboard.png)



## Templates

The templates are in the **skel** directory. 

## Get it running

Just type:

```bash
λ py cmc.py help
----------------------------------------------
Starting Dynatrace CMC Tenant Automation


Dynatrace CMC Tenant Automation
=======================================================
Usage: cmc.py <command>
commands: help     = Prints this options
commands: validate = Validates and prints the config file, reads the CSV file and prints the users and control flags
commands: create   = Creates the tenants, resources and sets-up the environment
commands: remove   = Removes the tenants and deletes the resources
** For more information read the README.md file **
=======================================================

```
and prints out the help or to validate and print the config and the users with their control flags type: 

```bash
py cmc.py validate
```

## Control Flags



**skip** = empty and "false" equals false. Meaning the actions defined in the program (command and config file) will be applied to that user. If it contains True then the user will be skipped.

**isClusterAdminGroup** =  empty and "false" equals false. True will set the user_group for the user to cluster_admin. This user will have access to the CMC and to all tenants.



## CSV Fields (mandatory and optional)

The CSV is a semicolon ; separated file.

The order of the fields is not important nevertheless the program will keep the order when rewriting the results of the actions created. The keys are case sensitive.

| Key                 | Mandatory | default Value            | Description                                                  |
| ------------------- | --------- | ------------------------ | ------------------------------------------------------------ |
| email               | yes       |                          | the email of the person                                      |
| firstName           | yes       |                          | the firstname                                                |
| lastName            | yes       |                          | the lastname                                                 |
| tenantId            | no        | firstName-LastName       | if found in the CSV file can be overwritten                  |
| groupId             | no        | firstName-LastName-group |                                                              |
| skip                | no        | FALSE                    | If found and if "true", the row will be skipped              |
| isClusterAdminGroup | no        | FALSE                    | If found and if "true", the userGroup will be added as an cluster admin. |



## AWS Account

The program uses boto3, which is a library for managing aws resources. This will work automatically if you have AWS cli set up in your environment so you dont have to code it or enter it everytime.

[Here is how to set up your environment credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)

You can set them [programatically](https://boto3.amazonaws.com/v1/documentation/api/latest/guide/configuration.html), but I strongly advice to set them in your environment. Be aware that the AMI instance IDs difer from one region to another, meaning an ubuntu has a different AMI ID for "Europe West" than "Europe East". 

## AWS concurrent running instances limit:

By default AWS has a limit of 20 multiple instances running. You might want to check up that limit in the region before creating the EC2 instances.

## Ideas for Improvement

- Document the flow of the program.
- make a more generic template to add more actions
- parametrize the creation of EC2 instances in its own JSON file. Most part (except from the user-data) is hard-coded.
- The EC2 instaces due the technical requirements are quite large (size large) and have a 30Gig disk due the installing an ActiveGate with Private Monitors capabilities.

## Author
sergio.hinojosa@dynatrace.com
