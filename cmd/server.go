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
	"reflect"
	"strings"
	"time"

	"k8s.io/client-go/1.5/kubernetes"
	"k8s.io/client-go/1.5/pkg/api"
	"k8s.io/client-go/1.5/pkg/api/v1"
	"k8s.io/client-go/1.5/pkg/fields"
	"k8s.io/client-go/1.5/pkg/util/wait"
	"k8s.io/client-go/1.5/tools/cache"
	"k8s.io/client-go/1.5/tools/clientcmd"

	"golang.org/x/net/context"
	"golang.org/x/oauth2/google"
	gdns "google.golang.org/api/dns/v1"

	"github.com/davecgh/go-spew/spew"
	"github.com/spf13/cobra"
)

const (
	// resyncPeriod sets an interval for a full reconciliation of all services and DNS records.
	// NOTE: careful setting this too low, you may hit limits on the google dns API quota.
	resyncPeriod = 60 * time.Minute
	// TTL is the DNS record TTL
	TTL = 300
	// KubeSystemNamespace is the namespace for kube-system (usually kube-system). Services
	// in this namespace will be ignored.
	KubeSystemNamespace = "kube-system"

	add serviceAction = iota
	delete
)

type serviceAction int

var actionStrings = map[serviceAction]string{
	add:    "Add",
	delete: "Delete",
}

type kube2gce struct {
	kubeClient *kubernetes.Clientset
	gceClient  *gdns.Service
	config     config
	zone       string // the gce dns zone
}

// config struct for the server
type config struct {
	// kube cluster to connect to
	kubeAPIServer string
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
		&conf.kubeAPIServer,
		"api",
		"k",
		"",
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
	k2g.watchForServices()

	select {}
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
	_, serviceController := cache.NewInformer(
		cache.NewListWatchFromClient(kg.kubeClient.Core().GetRESTClient(), "services", api.NamespaceAll, fields.Everything()),
		&v1.Service{},
		resyncPeriod,
		cache.ResourceEventHandlerFuncs{
			AddFunc:    kg.addService,
			DeleteFunc: kg.deleteService,
			UpdateFunc: kg.updateService,
		},
	)
	go serviceController.Run(wait.NeverStop)
	return
}

func validateService(ns, name string) bool {
	if ns == KubeSystemNamespace {
		log.Printf("Service '%s' is in restricted namespace %s, skipping.", name, KubeSystemNamespace)
		return false
	}

	if strings.Contains(name, ".") {
		log.Printf("Can't publish service name '%s' dots not allowed", name)
		return false
	}

	return true
}

// publicServiceAddrs pulls the public IP's from the Ingres LB's
func publicServiceAddrs(ingressRouters []v1.LoadBalancerIngress) []string {
	var addrs []string
	if ingress := ingressRouters; ingress != nil {
		for _, lb := range ingress {
			addrs = append(addrs, lb.IP)
		}
	}
	return addrs
}

func (kg kube2gce) addService(obj interface{}) {
	go kg.addOrDeleteService(obj, add)
}

func (kg kube2gce) deleteService(obj interface{}) {
	go kg.addOrDeleteService(obj, delete)
}

func (kg kube2gce) addOrDeleteService(obj interface{}, action serviceAction) {
	s, ok := obj.(*v1.Service)
	if ok == false {
		return
	}

	if validateService(s.Name, s.Namespace) == false {
		return
	}

	addrs := publicServiceAddrs(s.Status.LoadBalancer.Ingress)
	if len(addrs) <= 0 {
		return
	}

	fqdn := fmt.Sprintf("%s.%s.%s.", s.Name, s.Namespace, kg.config.domain)
	newRec := &gdns.ResourceRecordSet{
		Name:    fqdn,
		Rrdatas: addrs,
		Ttl:     int64(TTL),
		Type:    "A",
	}

	var change gdns.Change
	if action == add {
		change = gdns.Change{
			Additions: []*gdns.ResourceRecordSet{newRec},
			Deletions: nil,
		}
	} else {
		change = gdns.Change{
			Additions: nil,
			Deletions: []*gdns.ResourceRecordSet{newRec},
		}
	}

	log.Printf("%s Service %s %v", actionStrings[action], fqdn, addrs)
	go kg.updateDNS(&change)
}

// updateService resolves a services ip list and updates dns if the old and new records differ
func (kg kube2gce) updateService(oldObj, newObj interface{}) {
	s, ok := newObj.(*v1.Service)
	if ok == false {
		return
	}

	if validateService(s.Name, s.Namespace) == false {
		return
	}

	newAddrs := publicServiceAddrs(s.Status.LoadBalancer.Ingress)
	if len(newAddrs) <= 0 {
		return
	}

	fqdn := fmt.Sprintf("%s.%s.%s.", s.Name, s.Namespace, kg.config.domain)
	oldAddrs := publicServiceAddrs(oldObj.(*v1.Service).Status.LoadBalancer.Ingress)

	log.Printf("Got Possible Service update %s", fqdn)

	oldRec := &gdns.ResourceRecordSet{
		Name:    fqdn,
		Rrdatas: oldAddrs,
		Ttl:     int64(TTL),
		Type:    "A",
	}

	newRec := &gdns.ResourceRecordSet{
		Name:    fqdn,
		Rrdatas: newAddrs,
		Ttl:     int64(TTL),
		Type:    "A",
	}

	if reflect.DeepEqual(newAddrs, oldAddrs) {
		log.Printf("old and new service have same addresses, will validate with api. %s %v:%v", fqdn, oldAddrs, newAddrs)
		kg.checkAndUpdateDNS(newRec)
		return
	}

	change := &gdns.Change{
		Additions: []*gdns.ResourceRecordSet{newRec},
		Deletions: []*gdns.ResourceRecordSet{oldRec},
	}
	go kg.updateDNS(change)
}

// updateDNS will delete/add record sets against the GCloud API
func (kg kube2gce) updateDNS(change *gdns.Change) {
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

	log.Printf("Applied change, Add: %s Delete: %s", spew.Sdump(chg.Additions), spew.Sdump(chg.Deletions))
}

// check the google DNS service to see if the record has changed from what kube reports.
// if it has changed then push an update
func (kg kube2gce) checkAndUpdateDNS(newRecord *gdns.ResourceRecordSet) {
	listCall := kg.gceClient.ResourceRecordSets.List(kg.config.project, kg.zone).Name(newRecord.Name)
	rr, err := listCall.Do()
	if err != nil {
		log.Printf("Error while trying to get existing record for %s: %s", newRecord.Name, err)
		return
	}

	change := &gdns.Change{
		Additions: []*gdns.ResourceRecordSet{newRecord},
		Deletions: rr.Rrsets,
	}

	// TODO: add a better compare, that includes type/TTL
	if len(rr.Rrsets) != len(change.Additions) {
		log.Printf("GCE and new record for %s are out of sync, updating", newRecord.Name)
		go kg.updateDNS(change)
		return
	}

	for i, rs := range rr.Rrsets {
		if !reflect.DeepEqual(rs.Rrdatas, change.Additions[i].Rrdatas) {
			log.Printf("Replacing existing record for %s, rrdata has drifted %v != %v",
				newRecord.Name,
				rs.Rrdatas,
				change.Additions[i].Rrdatas)

			go kg.updateDNS(change)
			return
		}
	}

	log.Printf("GCE and new record for %s are in sync", newRecord.Name)
}

// getHostedZone makes sure the zone exists in GCE
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
func newKubeClient() (*kubernetes.Clientset, error) {
	loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()
	configOverrides := &clientcmd.ConfigOverrides{}
	kubeConfig := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(loadingRules, configOverrides)
	config, err := kubeConfig.ClientConfig()
	if err != nil {
		return nil, err
	}

	if conf.kubeAPIServer != "" {
		config.Host = conf.kubeAPIServer
	}
	log.Printf("Using %s for kube api", config.Host)

	client, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, err
	}

	return client, nil
}
