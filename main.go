// Copyright © 2016 Pantheon Systems
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import "github.com/pantheon-systems/kube-gce-dns/cmd"

func main() {
	cmd.Execute()
}

/*
 package main

import (
	"k8s.io/kubernetes/pkg/api"
	"k8s.io/kubernetes/pkg/client/unversioned"
	"k8s.io/kubernetes/pkg/fields"
	"k8s.io/kubernetes/pkg/labels"
)

func main() {
	client := unversioned.NewOrDie(&Config{Host: "http://127.0.0.1:8001"})

	pods, err := client.Pods(api.NamespaceDefault).List(labels.Everything(), fields.Everything())
	if err != nil {
		log.fatal(err)
	}

}
*/
