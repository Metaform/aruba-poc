#!/bin/bash

#
#  Copyright (c) 2024 Metaform Systems, Inc.
#
#  This program and the accompanying materials are made available under the
#  terms of the Apache License, Version 2.0 which is available at
#  https://www.apache.org/licenses/LICENSE-2.0
#
#  SPDX-License-Identifier: Apache-2.0
#
#  Contributors:
#       Metaform Systems, Inc. - initial API and implementation
#
#

set -euo pipefail

# Parse command line arguments, set --host if provided
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --host) HOST="$2"; shift ;;
        *) shift ;;
    esac
done

# Set default value for HOST if not provided
HOST=${HOST:-localhost}

echo "Seeding data to ingress host $HOST"

###############################################
# SEED ISSUER SERVICE
###############################################

echo
echo
echo "Create dataspace issuer"
DATA_ISSUER='{
            "roles":["admin"],
            "serviceEndpoints":[
              {
                 "type": "IssuerService",
                 "serviceEndpoint": "http://dataspace-issuer-service.poc-issuer.svc.cluster.local:10012/api/issuance/v1alpha/participants/ZGlkOndlYjpkYXRhc3BhY2UtaXNzdWVyLXNlcnZpY2UucG9jLWlzc3Vlci5zdmMuY2x1c3Rlci5sb2NhbCUzQTEwMDE2Omlzc3Vlcg==",
                 "id": "issuer-service-1"
              }
            ],
            "active": true,
            "participantId": "did:web:dataspace-issuer-service.poc-issuer.svc.cluster.local%3A10016:issuer",
            "did": "did:web:dataspace-issuer-service.poc-issuer.svc.cluster.local%3A10016:issuer",
            "key":{
                "keyId": "did:web:dataspace-issuer-service.poc-issuer.svc.cluster.local%3A10016:issuer#key-1",
                "privateKeyAlias": "key-1",
                "keyGeneratorParams":{
                  "algorithm": "EdDSA"
                }
            }
      }'

curl -s --location "http://${HOST}/issuer/cs/api/identity/v1alpha/participants/" \
--header 'Content-Type: application/json' \
--data "$DATA_ISSUER"

## Seed participant data to the issuer service
# Create attestation definition
echo
echo "Create attestation definition (membership)"
curl -s --location "http://${HOST}/issuer/ad/api/admin/v1alpha/participants/ZGlkOndlYjpkYXRhc3BhY2UtaXNzdWVyLXNlcnZpY2UucG9jLWlzc3Vlci5zdmMuY2x1c3Rlci5sb2NhbCUzQTEwMDE2Omlzc3Vlcg==/attestations" \
--header 'Content-Type: application/json' \
--header 'x-api-key: c3VwZXItdXNlcg==.c3VwZXItc2VjcmV0LWtleQo=' \
--data '{
    "attestationType": "membership",
    "configuration": {
    },
    "id": "membership-attestation-def-1"
}'

echo
echo "Create attestation definition (dataprocessor)"
curl -s --location "http://${HOST}/issuer/ad/api/admin/v1alpha/participants/ZGlkOndlYjpkYXRhc3BhY2UtaXNzdWVyLXNlcnZpY2UucG9jLWlzc3Vlci5zdmMuY2x1c3Rlci5sb2NhbCUzQTEwMDE2Omlzc3Vlcg==/attestations" \
--header 'Content-Type: application/json' \
--header 'x-api-key: c3VwZXItdXNlcg==.c3VwZXItc2VjcmV0LWtleQo=' \
--data '{
    "attestationType": "dataprocessor",
    "configuration": {
    },
    "id": "dataprocessor-attestation-def-1"
}'

# Create credential definitions
echo
echo "Create credential definitio (membership)"
curl -s --location "http://${HOST}/issuer/ad/api/admin/v1alpha/participants/ZGlkOndlYjpkYXRhc3BhY2UtaXNzdWVyLXNlcnZpY2UucG9jLWlzc3Vlci5zdmMuY2x1c3Rlci5sb2NhbCUzQTEwMDE2Omlzc3Vlcg==/credentialdefinitions" \
--header 'Content-Type: application/json' \
--header 'x-api-key: c3VwZXItdXNlcg==.c3VwZXItc2VjcmV0LWtleQo=' \
--data '{
    "attestations": [
        "membership-attestation-def-1"
    ],
    "credentialType": "MembershipCredential",
    "id": "membership-credential-def",
    "jsonSchema": "{}",
    "jsonSchemaUrl": "https://example.com/schema/membership-credential.json",
    "mappings": [
        {
            "input": "membershipType",
            "output": "credentialSubject.membershipType",
            "required": "true"
        },
        {
            "input": "membershipStartDate",
            "output": "credentialSubject.membershipStartDate",
            "required": true
        }
    ],
    "rules": [],
    "format": "VC1_0_JWT",
    "validity": "604800"
}'

echo
echo "Create credential definition (dataprocessor)"
curl -s --location "http://${HOST}/issuer/ad/api/admin/v1alpha/participants/ZGlkOndlYjpkYXRhc3BhY2UtaXNzdWVyLXNlcnZpY2UucG9jLWlzc3Vlci5zdmMuY2x1c3Rlci5sb2NhbCUzQTEwMDE2Omlzc3Vlcg==/credentialdefinitions" \
--header 'Content-Type: application/json' \
--header 'x-api-key: c3VwZXItdXNlcg==.c3VwZXItc2VjcmV0LWtleQo=' \
--data '{
    "attestations": [
        "dataprocessor-attestation-def-1"
    ],
    "credentialType": "DataProcessorCredential",
    "id": "dataprocessor-credential-def",
    "jsonSchema": "{}",
    "jsonSchemaUrl": "https://example.com/schema/dataprocessor-credential.json",
    "mappings": [
        {
            "input": "contractVersion",
            "output": "credentialSubject.contractVersion",
            "required": "true"
        },
        {
            "input": "level",
            "output": "credentialSubject.level",
            "required": true
        },
        {
          "input": "id",
          "output": "credentialSubject.id",
          "required": true
        }
    ],
    "rules": [],
    "format": "VC1_0_JWT",
    "validity": "604800"
}'