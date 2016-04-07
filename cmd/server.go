// Copyright © 2016 Jesse Nelson <spheromak@gmail.com>
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
	"time"

	"golang.org/x/net/context"
	"golang.org/x/oauth2/google"
	"google.golang.org/api/compute/v1"

	"github.com/davecgh/go-spew/spew"
	"github.com/spf13/cobra"

	kapi "k8s.io/kubernetes/pkg/api"
	kcache "k8s.io/kubernetes/pkg/client/cache"
	kclient "k8s.io/kubernetes/pkg/client/unversioned"
	"k8s.io/kubernetes/pkg/client/unversioned/clientcmd"
	kselector "k8s.io/kubernetes/pkg/fields"

	kframework "k8s.io/kubernetes/pkg/controller/framework"
	"k8s.io/kubernetes/pkg/util/wait"
)

const (
	resyncPeriod = 1 * time.Minute
)

type kube2gce struct {
	kubeClient *kclient.Client
	gceClient  *compute.Client
	config     *config
}

// config struct for the server
type config struct {
	// kube cluster to connect to
	kubeApiServer string
	// the domain in gce to publish too
	domain string
}

var (
	// serverCmd represents the server command
	serverCmd = &cobra.Command{
		Use:   "server",
		Short: "Start the server",
		RunE:  runServer,
	}

	// empty config struct that we load with cobra flags
	conf config
)

func init() {
	RootCmd.AddCommand(serverCmd)
	serverCmd.Flags().StringVar(&conf.kubeApiServer, "kube-api", "", "Api url to use, if running inside of kube this shouldn't be needed")
	serverCmd.Flags().StringVar(&conf.domain, "domain", "", "Domain to register services in gce with")
}

// entrypoint invoked by Cobra when server sub cmd is run
func runServer(cmd *cobra.Command, args []string) error {
	k2g := kube2gce{}
	kc, err := newKubeClient()
	if err != nil {
		return err
	}
	k2g.kubeClient = kc

	gce = newGCEClient()
	if err != nil {
		return err
	}
	k2g.gceClient = gce

	log.Println("Starting To watch for service changes")
	// TODO(jesse): we should reconcle or let that be an option
	k2g.watchForServices()

	select {}

	return nil
}

func newGCEClient() (*compute.Service, error) {

	ctx := context.Background()

	client, err := google.DefaultClient(ctx, compute.ComputeScope)
	if err != nil {
		return nil, err
	}
	computeService, err := compute.New(client)
	if err != nil {
		return nil, err
	}

	return computeService, nil
}

// the main watcher loop for kube service state changes
// this should not exit just fire service evnets to their respective handlers
func (kg *kube2gce) watchForServices() {
	s, serviceController := kframework.NewInformer(
		kcache.NewListWatchFromClient(kg.kubeClient, "services", kapi.NamespaceAll, kselector.Everything()),
		&kapi.Service{},
		resyncPeriod,
		kframework.ResourceEventHandlerFuncs{
			AddFunc:    kg.newService,
			DeleteFunc: kg.removeService,
			UpdateFunc: kg.updateService,
		},
	)
	go serviceController.Run(wait.NeverStop)
	spew.Dump(s)
	return
}

func (kg *kube2gce) newService(obj interface{}) {
	// ensure this obj is a kube service
	if s, ok := obj.(*kapi.Service); ok {
		log.Printf("Got New Service %+v\n", s)
	}
}

func (kg *kube2gce) updateService(oldObj, newObj interface{}) {
	kg.removeService(oldObj)
	kg.newService(newObj)
}

func (kg *kube2gce) removeService(obj interface{}) {
	if s, ok := obj.(*kapi.Service); ok {
		log.Printf("Got Remove Service %+v\n", s)
	}
}

// newKubeClient creates a new Kubernetes API Client
func newKubeClient() (*kclient.Client, error) {
	loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()
	configOverrides := &clientcmd.ConfigOverrides{}
	kubeConfig := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(loadingRules, configOverrides)
	config, err := kubeConfig.ClientConfig()
	if err != nil {
		return nil, err
	}
	if conf.kubeApiServer != "" {
		config.Host = conf.kubeApiServer
	}

	client, err := kclient.New(config)
	if err != nil {
		return nil, err
	}

	return client, nil
}
