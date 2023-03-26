# BirdCount API

API Backend for [birdcount](https://github.com/mlitwin/bird-count)

## Architecture

AWS DynamoDB backend with API Gateway / Lambda

## Development

### Install

brew install terraform

# Raw Notes

https://dynobase.dev/dynamodb-terraform/

aws sts get-caller-identity 


## Schema

        AttributeDefinitions: [
          {"AttributeName": "group", "AttributeType": "S"},
          {"AttributeName": "timestamp", "AttributeType": "N"}
        ]
        KeySchema: [
          {"AttributeName": "group", "KeyType": "HASH"},
          {"AttributeName": "timestamp", "KeyType": "SORT"}
        ]

## Dev
https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/workbench.settingup.install.html - seems cluncky
Use console


https://www.npmjs.com/package/dynamodb-admin - good for localstack