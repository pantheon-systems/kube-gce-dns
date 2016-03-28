// Copyright © 2016 NAME HERE <EMAIL ADDRESS>
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

package cmd

import (
	"log"

	"github.com/spf13/cobra"
	"k8s.io/kubernetes/pkg/api/unversioned"
	"k8s.io/kubernetes/pkg/util/wait"

	kcache "k8s.io/kubernetes/pkg/client/cache"
	"k8s.io/kubernetes/pkg/client/restclient"
	kclient "k8s.io/kubernetes/pkg/client/unversioned"
	kframework "k8s.io/kubernetes/pkg/controller/framework"
)

// serverCmd represents the server command
var serverCmd = &cobra.Command{
	Use:   "server",
	Short: "Start the server",
	RunE:  runServer,
}

func init() {
	RootCmd.AddCommand(serverCmd)
	serverCmd.PersistentFlags().String("etcd-server", "", "etcd-server for kube")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// serverCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")

}

func runServer(cmd *cobra.Command, args []string) error {

	kubeClient, err := newKubeClient()
	if err != nil {
		return err
	}

	watchForServices(kubeClient)
	return nil
}

func watchForServices(kubeClient *kclient.Client) kcache.Store {
	serviceStore, serviceController := kframework.NewInformer(
		createServiceLW(kubeClient),
		&kapi.Service{},
		resyncPeriod,
		kframework.ResourceEventHandlerFuncs{
			AddFunc:    newService,
			DeleteFunc: removeService,
			UpdateFunc: updateService,
		},
	)
	go serviceController.Run(wait.NeverStop)
	return serviceStore
}

func newService(obj interface{}) {
}

func updateService(oldObj, newObj interface{}) {
}

func removeService(obj interface{}) {
}

func newKubeClient() (*kclient.Client, error) {
	var (
		config    *restclient.Config
		err       error
		masterURL string
	)
	// If the user specified --kube-master-url, expand env vars and verify it.
	if *argKubeMasterURL != "" {
		masterURL, err = expandKubeMasterURL()
		if err != nil {
			return nil, err
		}
	}

	if masterURL != "" && *argKubecfgFile == "" {
		// Only --kube-master-url was provided.
		config = &restclient.Config{
			Host:          masterURL,
			ContentConfig: restclient.ContentConfig{GroupVersion: &unversioned.GroupVersion{Version: "v1"}},
		}
	} else {
		// We either have:
		//  1) --kube-master-url and --kubecfg-file
		//  2) just --kubecfg-file
		//  3) neither flag
		// In any case, the logic is the same.  If (3), this will automatically
		// fall back on the service account token.
		overrides := &kclientcmd.ConfigOverrides{}
		overrides.ClusterInfo.Server = masterURL                                     // might be "", but that is OK
		rules := &kclientcmd.ClientConfigLoadingRules{ExplicitPath: *argKubecfgFile} // might be "", but that is OK
		if config, err = kclientcmd.NewNonInteractiveDeferredLoadingClientConfig(rules, overrides).ClientConfig(); err != nil {
			return nil, err
		}
	}

	log.Infof("Using %s for kubernetes master", config.Host)
	log.Infof("Using kubernetes API %v", config.GroupVersion)
	return kclient.New(config)
}
