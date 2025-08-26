# Proof-of-Concept Aruba + EDC

## 1. Introduction

## 2. Definition of terms

- _user_: a person interacting with various APIs that one particular _participant_ exposes
- _participant_: a participating entity in a dataspace, e.g. a company or an organization. This is NOT a human being, but rather a legal entity.
- _participantContext_: technically, IdentityHub is multi-tenant, so it could handle multiple participants in one instance. In this PoC, however, each
  participant gets its own IdentityHub instance, so there is only one participantContext per IdentityHub. A _participantContext_ is identified by its
  _participantContextId_, which - for the purposes of this PoC - is identical to the participant's DID.
- _verifiable credential_: a structured, cryptographically verifiable claim about a _participant_ that is issued by an _issuer_ and held by a _holder_. A VC is
  a JSON document, secured by a proof, e.g. a digital signature.
- _issuer_: an entity that issues verifiable credentials to participants. In this PoC, the IssuerService is the issuer. An issuer must be trusted by the participants.
- _holder_: an entity that holds verifiable credentials. In this PoC, the IdentityHub acts as the holder.

## 3. Getting started

### 3.1 Prerequisites

In order to deploy the base components of this PoC, the following things are required:

- a fresh Kubernetes cluster
- NGINX ingress controller installed, e.g. by running:

  ```shell
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.13.0/deploy/static/provider/cloud/deploy.yaml
  ```

- `kubectl` installed on dev machine
- either Terraform or OpenTofu (recommended) installed on dev machine
- a GitHub account and a PAT (needed
  to [authenticate to GHCR](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-to-the-container-registry))
- a POSIX-compliant shell
- this repository cloned locally
- Windows _might_ be supported as base OS, but paths may need to be adapted. I've only tested on macOS.

_All shell commands are assumed to be executed from the repository root unless stated otherwise._

### 3.2 Kubernetes network requirements

This PoC uses an NGINX ingress controller to route HTTP requests to all the individual services and make them accessible
from outside the cluster.

On local Kubernetes development installations _other than KinD_, for example Proxmox or bare metal, the Ingress
Controller service won't automatically get an external IP if the service type is `LoadBalancer` (`ClusterIP` will only
be reachable from inside the cluster), so we need another service to do that. Here, we're using MetalLB.
Note that most cloud providers assign an external IP to the cluster, so MetalLB is not needed there.

Note also, that on KinD the situation is slightly different: there is a
special [installation procedure](https://kind.sigs.k8s.io/docs/user/ingress) when using NGINX ingress with KinD.

### 3.3 Deploy base infrastructure

In order to install the base components (IssuerService and Provisioner agent) on the cluster, simply run

```shell
GH_PAT=ghp_...
GH_USERNAME=...
tofu -chdir=deployment apply -var ghcr_pat=$GH_PAT -var ghcr_username=$GH_USERNAME
```

and confirm by typing `yes`. After Terraform has completed, inspect the pods by typing `kubectl get pods -n poc-issuer`
and `kubectl get pods -n poc-provisioner`. The output should be similar to this:

```shell
NAME                                        READY   STATUS    RESTARTS   AGE
dataspace-issuer-service-5d68c4cdf8-v2r5b   1/1     Running   0          3m25s
issuer-postgres-6cfc666468-5b7ww            1/1     Running   0          3m27s
issuer-vault-0                              1/1     Running   0          3m24s
```

and

```shell
NAME                           READY   STATUS    RESTARTS   AGE
provisioner-5bf555d7dd-87stz   1/1     Running   0          3m32s
```

Note that according to documentation, OpenTofu/Terraform _should_ respect the `$KUBECONFIG` variable, but that doesn't
seem to be the case in all instances. Therefor, the Terraform scripts reference `~/.kube/config` directly.

Finally, some data needs to be seeded by executing the seed script. Here, the Kubernetes external IP is `192.168.1.230`,
replace it to fit your local setup:

```shell
./seed-k8s.sh --host 192.168.1.230
```

executing this script repeatedly will log an error ("ObjectConflict") but that is OK.

### 3.4 Create participants

Onboarding a participant can be done by executing a simple HTTP request, only the participant's name and
its [DID](https://www.w3.org/TR/did-1.0/) is required. For the purposes of this PoC, the DID is constructed as follows:

```something
"did:web:identityhub.<NAME>.svc.cluster.local%3A7083:<NAME>"
```

Note that in production scenarios this will likely be different - DIDs are supposed to be stable identifiers that
_cannot change_ over the lifetime of a participant.

The participant name should be a sequence of alphanumeric characters, starting with a character and without blanks or
special symbols. Again, assuming `192.168.1.230` as the cluster external IP, create the participant by executing

```shell
curl -X POST http://192.168.1.230/provisioner/api/v1/resources \
  -d '{
        "participantName": "aruba07",
        "did": "did:web:identityhub.aruba07.svc.cluster.local%3A7083:aruba07",
        "kubeHost":"192.168.1.230"
      }' \
  -H "content-type: application/json"
```

The provisioner will respond immediately with a list of services that are being provisioned:

```json
{
  "aruba07": "Namespace",
  "controlplane": "Service",
  "controlplane-config": "ConfigMap",
  "dataplane": "Service",
  "dataplane-config": "ConfigMap",
  "did": "Ingress",
  "identityhub": "Ingress",
  "ih-config": "ConfigMap",
  "ingress-controlplane": "Ingress",
  "ingress-dataplane": "Ingress",
  "initdb-config": "ConfigMap",
  "participants": "ConfigMap",
  "postgres": "Deployment",
  "postgres-config": "ConfigMap",
  "postgres-service": "Service",
  "vault": "Service"
}
```

The provisioning process is _asynchronous_. That means, in order to know when the provisioner has finished, we must
inspect the provisioner's logs with `kubectl logs -n poc-provisioner provisioner-XXXXXXXXXX-YYYYY` to see the progress
of the deployment. It should look something like this:

```text
Waiting for deployments [controlplane identityhub dataplane]
Deployment controlplane ready
Deployment identityhub ready
Deployment dataplane ready
Deployments ready in namespace aruba07 -> seeding data
assets created
policies created
contract definitions created
participant created
issuer account created for participant  aruba07
Data seeding complete in namespace aruba07
```

(an alternative would be to wait for individual deployments with
`kubectl wait deployment identityhub --namespace aruba02 --for=condition=available --timeout=60s`)

### 3.5 Requesting a credential

After the participant has been created, it can request verifiable credentials from the IssuerService. For this, we use
the participant's "IdentityApi" to talk to the participant's IdentitHub, which is
basically the management API of the IdentityHub. Again, assuming `"192.168.1.230"` as the cluster external IP, we can
request credentials by executing

```shell
curl --location 'http://192.168.1.239/aruba07/cs/api/identity/v1alpha/participants/ZGlkOndlYjppZGVudGl0eWh1Yi5hcnViYTA3LnN2Yy5jbHVzdGVyLmxvY2FsJTNBNzA4MzphcnViYTA3/credentials/request' \
--header 'Content-Type: application/json' \
--header 'X-Api-Key: c3VwZXItdXNlcg==.c3VwZXItc2VjcmV0LWtleQo=' \
--data '{
    "issuerDid": "did:web:dataspace-issuer-service.poc-issuer.svc.cluster.local%3A10016:issuer",
    "holderPid": "credential-request-1",
    "credentials": [{
        "format": "VC1_0_JWT",
        "type": "MembershipCredential",
        "id": "membership-credential-def"
    },
    {
        "format": "VC1_0_JWT",
        "type": "DataProcessorCredential",
        "id": "dataprocessor-credential-def"
    }]
}'
```

Key elements to note here are:

- the URL contains the base64-encoded identifier of the participant, which should be identical to the participant's DID
- the `issuerDid` determines, where to send the issuance request. technically, in a dataspace, there could be multiple issuers
- the `holderPid` is an arbitrary ID that can be chosen by the (prospective "holder" of the credential)
- each object in the `credentials` array determines, which credential is to be requested. This information is available via the issuer's [Metadata API](https://eclipse-dataspace-dcp.github.io/decentralized-claims-protocol/v1.0-RC4/#issuer-metadata-api), and here, we're requesting two credentials at once. Note that it is also possible to make two individual requests, but the `holderPid` then has to be different each time.

Credential issuance is also an asynchronous process, so the request immediately returns with HTTP 201. After a while, the IdentityHub's logs should display something similar to:

```text
identityhub DEBUG 2025-08-26T06:42:38.697336738 [CredentialRequestManagerImpl] HolderCredentialRequest credential-request-1 is now in state CREATED
identityhub DEBUG 2025-08-26T06:42:39.493424722 Processing 'CREATED' request 'credential-request-1'
identityhub DEBUG 2025-08-26T06:42:39.495968114 [CredentialRequestManagerImpl] HolderCredentialRequest credential-request-1 is now in state REQUESTING
identityhub DEBUG 2025-08-26T06:42:39.915779975 [CredentialRequestManagerImpl] HolderCredentialRequest credential-request-1 is now in state REQUESTED
identityhub DEBUG 2025-08-26T06:42:41.205526897 [StorageAPI] HolderCredentialRequest credential-request-1 is now in state ISSUED
```

From that point forward, the `MembershipCredential` and the `DataProcessorCredential` are held by our participant "aruba05" and can be used for presentation.

## 4. Components and setup

The PoC consists of two main classes of components:

1. , consisting of the IssuerService and the Provisioner agent
2. participant infrastructure, consisting of the Identity Hub, the Control Plane and the Data Plane plus their
   dependencies (primarily PostgreSQL and Vault).

### Base infrastructure

The base infrastructure is deployed once per cluster and consists of the IssuerService and the Provisioner agent. This
is done by running the Terraform/OpenTofu
scripts in the `deployment` folder, see [section 3.3](#33-deploy-base-infrastructure) for details.

#### IssuerService

This is a DCP-compliant issuer service that receives verifiable credential requests from participants and issues the
requested credentials. It is based on
the [reference implementation](https://github.com/eclipse-edc/IdentityHub/blob/main/docs/developer/architecture/issuer/issuance/issuance.process.md)
of the
[Decentralized Claims Protocol](https://eclipse-dataspace-dcp.github.io/decentralized-claims-protocol).

In short, the IssuerService uses so-called `CredentialDefinitions` to generate Verifiable Credentials for participants.
The data, that is being written into the
credentials comes from so-called `AttestationDefinitions` which are linked to the `CredentialDefinitions`. For this PoC,
the data is hardcoded for each
credential type in the
IssuerService's [code base](./launchers/issuerservice/src/main/java/org/eclipse/edc/issuerservice/seed/attestation/),
but in a production
scenario this data would likely come from an external source, e.g. a database or an API.

#### Credential types

In this PoC there are two types of credentials: a `MembershipCredential`, which attests to a participant being an active
member of the dataspace, and a `DataProcessorCredential`, which attests to a participant's access level - either
`"processing"` or `"sensitive"`.

When issuing a `MembershipCredential`, the `MembershipAttestationSource` creates the following credential subject:

```json
{
  "membershipStartDate": "<NOW>",
  "membershipType": "full-member",
  "id": "<PARTICIPANT_ID>"
}
```

When issuing a `DataProcessorCredential`, the `DataProcessorAttestationSource` creates the following credential subject:

```json
{
  "contractVersion": "1.0.0",
  "level": "processing",
  "id": "<PARTICIPANT_ID>"
}
```

These credentials are used to authenticate and authorize DSP/DCP requests from one connector to another. Each new
dataspace member will receive both credentials.

#### Provisioner agent

The provisioner agent is responsible for deploying the participant infrastructure on behalf of an onboarding platform.
It exposes a REST API that can be used to
request the provisioning and the de-provisioning of a new participant by providing the participant's name and DID,
see [section 3.4](#34-create-participants) for
details.

In practice, the provisioner agent will create the following resources for each participant:

- a control plane: this is the connector's DSP endpoint that handles contract negotiations etc.
- a data plane: this is a (very simple) http data plane to transmit example data
- an IdentityHub: this is the credential storage and DCP implementation
- dependencies like a PostgreSQL database and a Vault for secrets storage.

In addition, the provisioner agent also pre-configures each participant with demo data:

- assets, policies and contract definitions
- an account in its IdentityHub, so that the participant may present its credentials to other participants
- an account on the IssuerService, so that the participant may request credentials to be issued

**Asynchronous operation**: Provisioning participant data may take some time, depending on physical hardware and network layout. Currently, the only
way to get notified when a deployment is ready, is to inspect the logs of the provisioner. In production scenarios, that
would likely be handled using an eventing system.

**Multi-tenancy**: In the current PoC, multi-tenancy is implemented by creating a separate Kubernetes namespace for each participant. In
production scenarios, this will likely be different.

## X. References

| Reference                       | Link                                                                    | Used for                                                              |
| ------------------------------- | ----------------------------------------------------------------------- | --------------------------------------------------------------------- |
| Decentralized Claims Protocol   | <https://eclipse-dataspace-dcp.github.io/decentralized-claims-protocol> | Defines the protocol for presenting and issuing Verifiable Credentisl |
| Dataspace Protocol              | <https://eclipse-dataspace-protocol-base.github.io/DataspaceProtocol>   | Standard for data exchange and interoperability in dataspaces         |
| Decentralized Identifiers (DID) | <https://www.w3.org/TR/did-1.0/>                                        | Unique, verifiable digital identifiers                                |
| DID:web method                  | <https://w3c-ccg.github.io/did-method-web/>                             | Method for resolving DIDs using web infrastructure                    |
| Verifiable Credentials 2.0      | <https://www.w3.org/TR/vc-data-model/>                                  | Data model for digital credentials                                    |
