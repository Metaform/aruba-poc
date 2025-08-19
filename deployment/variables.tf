#
#  Copyright (c) 2023 Contributors to the Eclipse Foundation
#
#  See the NOTICE file(s) distributed with this work for additional
#  information regarding copyright ownership.
#
#  This program and the accompanying materials are made available under the
#  terms of the Apache License, Version 2.0 which is available at
#  https://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#  License for the specific language governing permissions and limitations
#  under the License.
#
#  SPDX-License-Identifier: Apache-2.0
#

variable "pull-policy" {
  type        = string
  description = "Kubernetes ImagePullPolicy for all images"
  default     = "Always"
}

variable "consumer-did" {
  default = "did:web:consumer-identityhub.mvd-consumer-security.svc.cluster.local%3A7083:consumer"
}

variable "provider-did" {
  default = "did:web:provider-identityhub.mvd-provider-security.svc.cluster.local%3A7083:provider"
}

variable "useSVE" {
  type        = bool
  description = "If true, the -XX:UseSVE=0 switch (Scalable Vector Extensions) will be added to the JAVA_TOOL_OPTIONS. Can help on macOs on Apple Silicon processors"
  default     = false
}


variable "ghcr_username" {
  type      = string
  sensitive = false
}

variable "ghcr_pat" {
  type      = string
  sensitive = true
}
