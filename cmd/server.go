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
	"fmt"
	"log"
	"strings"
	"time"

	"golang.org/x/net/context"
	"golang.org/x/oauth2/google"
	gdns "google.golang.org/api/dns/v1"

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
	TTL          = 300
)

type kube2gce struct {
	kubeClient *kclient.Client
	gceClient  *gdns.Service
	config     config
	zone       string // the gce dns zone
}

// config struct for the server
type config struct {
	// kube cluster to connect to
	kubeApiServer string
	// the domain in gce to publish too
	domain string
	// the GCE project
	project string
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
	serverCmd.Flags().StringVarP(
		&conf.kubeApiServer,
		"kube-api",
		"k",
		"http://127.0.0.1:8001",
		"Api url to use")

	serverCmd.Flags().StringVarP(
		&conf.domain,
		"domain",
		"d",
		"",
		"Domain to register services in gce with")

	serverCmd.Flags().StringVarP(
		&conf.project,
		"project",
		"p",
		"",
		"GCE project")
}

// entrypoint invoked by Cobra when server sub cmd is run
func runServer(cmd *cobra.Command, args []string) error {
	k2g := kube2gce{config: conf}
	kc, err := newKubeClient()
	if err != nil {
		return err
	}
	k2g.kubeClient = kc

	dnsClient, err := newDNSClient()
	if err != nil {
		return err
	}
	k2g.gceClient = dnsClient
	zone, err := k2g.getHostedZone(k2g.config.domain)
	if err != nil {
		return err
	}

	k2g.zone = zone

	log.Println("Starting To watch for service changes")
	// TODO(jesse): we should reconcle or let that be an option
	k2g.watchForServices()

	select {}

	return nil
}

func newDNSClient() (*gdns.Service, error) {
	client, err := google.DefaultClient(context.Background(), gdns.NdevClouddnsReadwriteScope)
	if err != nil {
		return nil, err
	}

	dnsService, err := gdns.New(client)
	if err != nil {
		return nil, err
	}

	return dnsService, nil
}

// the main watcher loop for kube service state changes
// this should not exit just fire service events to their respective handlers
func (kg kube2gce) watchForServices() {
	_, serviceController := kframework.NewInformer(
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
	return
}

func (kg kube2gce) newService(obj interface{}) {
	// ensure this obj is a kube service
	// TODO(jesse): break this up
	if s, ok := obj.(*kapi.Service); ok {
		if s.Namespace == "kube-system" {
			log.Printf("Service '%s' is in kube system, skipping.", s.Name)
			return
		}

		dnsName := fmt.Sprintf("%s.%s", s.Name, s.Namespace)
		log.Printf("Got Possible New Service %s", dnsName)
		if strings.Contains(s.Name, ".") {
			log.Printf("Can't publish service name '%s' dots not allowed")
			return
		}

		// the list of external IP's might be nil or empty.
		if ingress := s.Status.LoadBalancer.Ingress; ingress != nil {
			var addrs []string
			for _, lb := range ingress {
				addrs = append(addrs, lb.IP)
			}
			fqdn := fmt.Sprintf("%s.%s.", dnsName, kg.config.domain)
			kg.publishDNS(fqdn, addrs, TTL)
		}
	}
}

func (kg kube2gce) publishDNS(fqdn string, addresses []string, ttl int) {
	rec := &gdns.ResourceRecordSet{
		Name:    fqdn,
		Rrdatas: addresses,
		Ttl:     int64(ttl),
		Type:    "A",
	}
	change := &gdns.Change{
		Additions: []*gdns.ResourceRecordSet{rec},
	}

	chg, err := kg.gceClient.Changes.Create(kg.config.project, kg.zone, change).Do()
	if err != nil {
		log.Printf("Error creating change: %s", err)
		return
	}

	// wait for change to be acknowledged
	for chg.Status == "pending" {
		time.Sleep(time.Second)

		chg, err = kg.gceClient.Changes.Get(kg.config.project, kg.zone, chg.Id).Do()
		if err != nil {
			log.Printf("Error while trying to get changes: %s", err)
			return
		}
	}

	log.Printf("Registered '%s' with ips '%v' ", fqdn, addresses)
}

func (kg kube2gce) updateService(oldObj, newObj interface{}) {
	kg.removeService(oldObj)
	kg.newService(newObj)
}

func (kg kube2gce) removeService(obj interface{}) {
	if s, ok := obj.(*kapi.Service); ok {
		log.Printf("Got Remove Service %s in %s\n", s.Name, s.Namespace)
	}
}

func (kg kube2gce) getHostedZone(domain string) (string, error) {
	zones, err := kg.gceClient.ManagedZones.List(kg.config.project).Do()
	if err != nil {
		return "", fmt.Errorf("GoogleCloud API call failed: %v", err)
	}

	for _, z := range zones.ManagedZones {
		if strings.HasSuffix(domain+".", z.DnsName) {
			return z.Name, nil
		}
	}

	return "", fmt.Errorf("No matching GoogleCloud domain found for domain %s", domain)
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
