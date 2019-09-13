# Copyright (c) 2017 VMware, Inc. All Rights Reserved.
# 
# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
# Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
# Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
# INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
package KubernetesCluster;

use Moose;
use MooseX::Storage;
use ComputeResources::Cluster;
use VirtualInfrastructures::VirtualInfrastructure;
use WeathervaneTypes;
use Log::Log4perl qw(get_logger);

use namespace::autoclean;
use Utils qw(runCmd);
no if $] >= 5.017011, warnings => 'experimental::smartmatch';

with Storage( 'format' => 'JSON', 'io' => 'File' );

extends 'Cluster';

has 'kubectlTopPodRunning' => (
	is      => 'rw',
	isa     => 'Int',
	default => 0,
);

has 'kubectlTopNodeRunning' => (
	is      => 'rw',
	isa     => 'Int',
	default => 0,
);

override 'initialize' => sub {
	my ( $self, $paramHashRef ) = @_;
		
	super();
};

override 'registerService' => sub {
	my ( $self, $serviceRef ) = @_;
	my $console_logger = get_logger("Console");
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	my $servicesRef    = $self->servicesRef;

	my $name = $serviceRef->name;
	$logger->debug( "Registering service $name with cluster ", $self->name );

	push @$servicesRef, $serviceRef;

};

sub kubernetesCreateNamespace {
	my ( $self, $namespaceName ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesCreateNamespace: namespace $namespaceName");

	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	# First check if the namespace already exists
	my $cmd;
	$cmd = "kubectl get namespace --kubeconfig=$kubeconfigFile $contextString $namespaceName";
	my ($cmdFailed, $outString) = runCmd($cmd);
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	my @lines = split /\n/, $outString;
	foreach my $line (@lines) {
		if ($line =~ /^$namespaceName/) {
			# namespace already exists
			return;
		}	
	}
	
	$cmd = "kubectl create namespace --kubeconfig=$kubeconfigFile $contextString $namespaceName";
	($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesCreateNamespace failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
}

sub kubernetesGetAll {
	my ( $self, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesGetAll in namespace $namespace");

	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}
	
	my $cmd;
	$cmd = "kubectl get all --namespace=$namespace -o wide --kubeconfig=$kubeconfigFile $contextString";
	my ($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesGetAll failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	return $outString;
}

sub kubernetesDeleteAll {
	my ( $self, $resourceType, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesDeleteAll with resourceType $resourceType in namespace $namespace");

	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	my $cmd;
	$cmd = "kubectl delete $resourceType --all --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString";
	my ($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesDeleteAll failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	
}

sub kubernetesDeleteAllWithLabel {
	my ( $self, $selector, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesDeleteAllWithLabel with label $selector in namespace $namespace");

	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	my $cmd;
	my $outString;
	my $cmdFailed;
	$cmd = "kubectl delete all --selector=$selector --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString";
	($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesDeleteAllWithLabel delete all failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	$cmd = "kubectl delete configmap --selector=$selector --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString";
	($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesDeleteAllWithLabel delete configmap failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	
}

sub kubernetesDeleteAllWithLabelAndResourceType {
	my ( $self, $selector, $resourceType, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesDeleteAllWithLabelAndResourceType with resourceType $resourceType, label $selector in namespace $namespace");

	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	my $cmd;
	$cmd = "kubectl delete $resourceType --selector=$selector --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString";
	my ($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesDeleteAllWithLabelAndResourceType failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	
}

sub kubernetesDelete {
	my ( $self, $resourceType, $resourceName, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesDelete resourceName $resourceName of type $resourceType in namespace $namespace");

	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	my $cmd;
	$cmd = "kubectl delete $resourceType $resourceName --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString";
	my ($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		if ( !($outString =~ /NotFound/) ) {
			$logger->error("kubernetesDelete failed: $cmdFailed");
		}
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	
}

sub kubernetesDeleteAllForCluster {
	my ( $self ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesDeleteAllForCluster");

	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";
	}

	my $cmd;
	my $outString;
	my $cmdFailed;
	$cmd = "kubectl get namespaces -o=jsonpath='{.items[*].metadata.name}' --kubeconfig=$kubeconfigFile $contextString";
	($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesDeleteAllForCluster get namespaces failed: $cmdFailed");
		return 0;
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");

	my @namespaceNames = split /\s+/, $outString;
	if ($#namespaceNames < 0) {
		$logger->debug("kubernetesDeleteAllForCluster: There are no namespaces.");
		return 1;
	}
	my $initialRemaining = 0;
	foreach my $namespace (@namespaceNames) {
		if ($namespace =~ /^auctionw/) {
			$cmd = "kubectl get deployment,statefulset,service,configmap,pod -o=jsonpath='{.items[*].metadata.name}' --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString";
			($cmdFailed, $outString) = runCmd($cmd);
			if ($cmdFailed) {
				$logger->error("kubernetesDeleteAllForCluster initial get failed namespace $namespace: $cmdFailed");
			} else {
				$logger->debug("Command: $cmd");
				$logger->debug("Output: $outString");

				my @remaining = split /\s+/, $outString;
				my $numRemaining = $#remaining + 1;
				$logger->debug("kubernetesDeleteAllForCluster namespace $namespace initial remaining items : $numRemaining");
				$initialRemaining += $numRemaining;
				if ($numRemaining == 0) {
					next;
				}
				_kubernetesDeleteAllForClusterHelper($logger, "deployment", "--namespace=$namespace --kubeconfig=$kubeconfigFile $contextString");
				_kubernetesDeleteAllForClusterHelper($logger, "statefulset", "--namespace=$namespace --kubeconfig=$kubeconfigFile $contextString");
				_kubernetesDeleteAllForClusterHelper($logger, "service", "--namespace=$namespace --kubeconfig=$kubeconfigFile $contextString");
				_kubernetesDeleteAllForClusterHelper($logger, "configmap", "--namespace=$namespace --kubeconfig=$kubeconfigFile $contextString");
			}
		}
	}

	if ($initialRemaining == 0) {
		$logger->debug("kubernetesDeleteAllForCluster no items found to delete.");
		return 1;
	}

	my $loopCount = 1;
	while ($loopCount <= 15) { # 15 x 20s = 5 minutes
		$logger->debug("kubernetesDeleteAllForCluster wait for no items remaining, loop $loopCount");
		my $loopExit = 1;
		foreach my $namespace (@namespaceNames) {
			if ($namespace =~ /^auctionw/) {
				$cmd = "kubectl get deployment,statefulset,service,configmap,pod -o=jsonpath='{.items[*].metadata.name}' --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString";
				($cmdFailed, $outString) = runCmd($cmd);
				if ($cmdFailed) {
					$logger->error("kubernetesDeleteAllForCluster loop get failed namespace $namespace: $cmdFailed");
				} else {
					$logger->debug("Command: $cmd");
					$logger->debug("Output: $outString");

					my @remaining = split /\s+/, $outString;
					my $numRemaining = $#remaining + 1;
					$logger->debug("kubernetesDeleteAllForCluster namespace $namespace remaining items : $numRemaining");
					if ($numRemaining > 0) {
						$loopExit = 0;
						last;
					}
				}
			}
		}
		if ($loopExit) {
			$logger->debug("kubernetesDeleteAllForCluster success.");
			return 1;
		}
		sleep 20;
		$loopCount++;
	}
	$logger->debug("kubernetesDeleteAllForCluster unsuccessful, items remain.");
	return 0;
}


sub _kubernetesDeleteAllForClusterHelper {
	my ( $logger, $type, $appendCmdStr ) = @_;

	#safety check
	if (!$appendCmdStr || !($appendCmdStr =~ /namespace=auctionw/)) {
		$logger->error("kubernetesDeleteAllForClusterHelper invalid namespace in appendCmdStr $appendCmdStr");
		return;
	}

	my $cmd = "kubectl get $type -o=jsonpath='{.items[*].metadata.name}' $appendCmdStr";
	my ($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesDeleteAllForClusterHelper get $type failed: $cmdFailed");
	} else {
		$logger->debug("Command: $cmd");
		$logger->debug("Output: $outString");

		my @names = split /\s+/, $outString;
		foreach my $name (@names) {
			$cmd = "kubectl delete $type $name $appendCmdStr";
			($cmdFailed, $outString) = runCmd($cmd);
			if ($cmdFailed) {
				$logger->error("kubernetesDeleteAllForClusterHelper delete service failed: $cmdFailed");
			}
		}
	}
}

# Does a kubectl exec in the first pod where the impl label matches  
# serviceImplName.  It does the exec in the container with the same name.
sub kubernetesExecOne {
	my ( $self, $serviceTypeImpl, $commandString, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	my $console_logger = get_logger("Console");
	$logger->debug("kubernetesExecOne exec $commandString for serviceTypeImpl $serviceTypeImpl, namespace $namespace");

	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	# Get the list of pods
	my $cmd;
	my $outString;
	my $cmdFailed;
	$cmd = "kubectl get pod -o=jsonpath='{.items[*].metadata.name}' --selector=impl=$serviceTypeImpl --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString";
	($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesExecOne get pod failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	my @names = split /\s+/, $outString;
	if ($#names < 0) {
		$console_logger->error("kubernetesExecOne: There are no pods with label $serviceTypeImpl in namespace $namespace");
		exit(-1);
	}
	
	# Get the name of the first pod
	my $podName = $names[0];
	
	$cmd = "kubectl exec -c $serviceTypeImpl --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString $podName -- $commandString";
	($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->info("kubernetesExecOne exec failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	
	return ($cmdFailed, $outString);
	
}

# Does a kubectl exec in all p[ods] where the impl label matches  
# serviceImplName.  It does the exec in the container with the same name.
sub kubernetesExecAll {
	my ( $self, $serviceTypeImpl, $commandString, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	my $console_logger = get_logger("Console");
	$logger->debug("kubernetesExecAll exec $commandString for serviceTypeImpl $serviceTypeImpl, namespace $namespace");

	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	# Get the list of pods
	my $cmd;
	my $outString;
	my $cmdFailed;
	$cmd = "kubectl get pod -o=jsonpath='{.items[*].metadata.name}' --selector=impl=$serviceTypeImpl --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString";
	($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesExecAll get pod failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	my @names = split /\s+/, $outString;
	if ($#names < 0) {
		$console_logger->error("kubernetesExecOne: There are no pods with label $serviceTypeImpl in namespace $namespace");
		exit(-1);
	}
	
	foreach my $podName (@names) { 	
		$cmd = "kubectl exec -c $serviceTypeImpl --namespace=$namespace $podName --kubeconfig=$kubeconfigFile $contextString -- $commandString";
		($cmdFailed, $outString) = runCmd($cmd);
		if ($cmdFailed) {
			$logger->error("kubernetesExecAll exec failed: $cmdFailed");
		}
		$logger->debug("Command: $cmd");
		$logger->debug("Output: $outString");
	}
}

sub kubernetesApply {
	my ( $self, $fileName, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesApply apply file $fileName in namespace $namespace");

	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	my $cmd;
	$cmd = "kubectl apply -f $fileName --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString";
	my ($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesApply failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
}

sub kubernetesGetLbIP {
	my ( $self, $svcName, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesGetLbIP for $svcName");

	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	my $cmd;
	$cmd = "kubectl get svc $svcName --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString -o=jsonpath=\"{.status.loadBalancer.ingress[*]['ip', 'hostname']}\"";
	$logger->debug("Command: $cmd");
	# Wait for ip to be provisioned
	# ToDo: Need a timeout here.
	my $ip = "";
	my $cmdFailed;
	my $retries = 40;
	while (!$ip && ($retries > 0)) {
		($cmdFailed, $ip) = runCmd($cmd);
	  	if ($cmdFailed)	{
	  		$logger->error("Error getting IP for wkldcontroller loadbalancer: error = $cmdFailed");
			return ($cmdFailed, $ip);
	  	}
	  	if (!$ip) {
	  		sleep 30;
	  		$retries--;
	  	} else {
			$logger->debug("Called kubernetesGetLbIP: got $ip");
	  	}
	}
	if (!$ip) {
		$cmdFailed = "Didn't get LoadBalancer IP/Hostname in 20 minutes";
		return ($cmdFailed, $ip);
	}
	
	# If the returned value is a hostname then convert it to an IP address
	if ($ip =~ /[A-Za-z]/) {
		$logger->debug("LoadBalancer access is a hostname.  Convert it to an IP");
		$retries = 40;
		my $realIp = "";
		$cmd = "dig +short $ip";
		$logger->debug("Command: $cmd");
		while (!$realIp && ($retries > 0)) {
			($cmdFailed, $realIp) = $self->kubernetesExecOne($svcName, $cmd, $namespace);
		  	if ($cmdFailed)	{
		  		$logger->error("Error getting LoadBalancer IP for hostname $ip: error = $cmdFailed");
				return ($cmdFailed, $ip);
	  		}
		  	if (!$realIp) {
		  		sleep 30;
		  		$retries--;
		  	} else {
				$logger->debug("Called kubernetesGetLbIP: converting $ip to IP got $realIp");
				my @ips = split(/\n/, $realIp);
				$ip = $ips[0];
	  		}
		}
	}
	if (!$ip) {
		$cmdFailed = "Didn't get IP for LoadBalancer Hostname in 20 minutes";
		return ($cmdFailed, $ip);
	}

	$logger->debug("Called kubernetesGetLbIP: Returning IP $ip");
	return ($cmdFailed, $ip);
}

sub kubernetesGetNodeIPs {
	my ( $self ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesGetNodeIPs ");

	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	my $cmd;
	$cmd = "kubectl get node --kubeconfig=$kubeconfigFile $contextString -o=jsonpath='{.items[*].status.addresses[?(@.type == \"ExternalIP\")].address}'";
	my ($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesGetNodeIPs failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	
	my @ips = split /\s/, $outString;
	if ($#ips < 0) {
		$logger->warn("kubernetesGetNodeIPs: There are no node IPs");
	}

	return \@ips;	
}

sub kubernetesGetNodeIPsForPodSelector {
	my ( $self, $selector ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesGetNodeIPsForPodSelector ");

	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	my $cmd;
	$cmd = "kubectl get pod --selector=$selector --all-namespaces --kubeconfig=$kubeconfigFile $contextString -o=jsonpath='{.items[*].status.hostIP}'";
	my ($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesGetNodeIPsForPodSelector failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	
	my @ips = split /\s/, $outString;
	if ($#ips < 0) {
		$logger->warn("kubernetesGetNodeIPsForPodSelector: There are no node IPs");
	}
	
	# Remove duplicates
	my @uniqueIps;
	for my $ip (@ips) {
		if (!($ip ~~ @uniqueIps)) {
			push @uniqueIps, $ip;
		}
	}
	return \@uniqueIps;	
}

sub kubernetesGetNodePortForPortNumber {
	my ( $self, $labelString, $portNumber, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesGetNodePortForPortNumber LabelString $labelString, port $portNumber, namespace $namespace");

	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	my $cmd;
	$cmd = "kubectl get service --selector=$labelString -o=jsonpath='{range .items[*]}{.spec.ports[*].port}{\",\"}{.spec.ports[*].nodePort}{\"\\n\"}{end}' --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString";
	my ($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesGetNodePortForPortNumber failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	
	my @lines = split /\n/, $outString;
	if ($#lines < 0) {
		$logger->error("kubernetesGetNodePortForPortNumber: There are no services with label $labelString in namespace $namespace");
		return "";
	}
	
	my $line = $lines[0];
	my @portLists = split /,/, $line;
	if ($#portLists < 1) {
		$logger->error("kubernetesGetNodePortForPortNumber: There are no nodePorts on services with label $labelString in namespace $namespace");
		return "";
	}

	my @ports = split /\s+/, $portLists[0];
	my @nodePorts = split /\s+/, $portLists[1];
	if ($#ports != $#nodePorts) {
		$logger->error("kubernetesGetNodePortForPortNumber: There are not nodePorts for every port on the services with label $labelString in namespace $namespace");
		return "";
	}
	
	my $index = 0;
	foreach 	my $port (@ports) {
		if ($port == $portNumber) {
			return $nodePorts[$index];
		}
		$index++;
	}

	$logger->error("kubernetesGetNodePortForPortNumber: There is no port $portNumber on the services with label $labelString in namespace $namespace");
	return "";
		
}

sub kubernetesGetSizeForPVC {
	my ( $self, $pvcName, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesGetSizeForPVC pvcName kubernetesGetSizeForPVC, namespace $namespace");

	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	my $cmd;
	$cmd = "kubectl get pvc $pvcName -o=jsonpath='{.spec.resources.requests.storage}' --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString";
	my ($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->info("kubernetesGetSizeForPVC failed: $cmdFailed");
		return "";
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	
	if ($outString =~ /not\sfound/) {
		$logger->info("kubernetesGetSizeForPVC: There are no pvcs named $pvcName in namespace $namespace");
		return "";		
	}

	$logger->info("kubernetesGetSizeForPVC: Returning $outString for pvcName $pvcName in namespace $namespace");
	return $outString;
		
}

sub kubernetesAreAllPodRunningWithNum {
	my ( $self, $podLabelString, $namespace, $num ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	my $console_logger = get_logger("Console");
	$logger->debug("kubernetesAreAllPodRunningWithNum podLabelString $podLabelString, namespace $namespace, num $num");

	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	my $cmd;
	$cmd = "kubectl get pod --selector=$podLabelString -o=jsonpath='{.items[*].status.phase}' --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString";
	my ($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesAreAllPodRunningWithNum failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");

	my @stati = split /\s+/, $outString;
	if ($#stati < 0) {
		$logger->debug("kubernetesAreAllPodRunningWithNum: There are no pods with label $podLabelString in namespace $namespace");
		return 0;
	}
	
	my $numFound = $#stati + 1;
	if ($numFound != $num) {
		$logger->debug("kubernetesAreAllPodRunningWithNum: Found $numFound of $num pods with label $podLabelString in namespace $namespace");
		return 0;
	}
	
	foreach my $status (@stati) { 
		if ($status eq "Pending") {
			# check if Pending status is due to FailedScheduling, which will prevent the pod from achieving "Running" status
			$cmd = "kubectl describe pod --selector=$podLabelString --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString | grep -A 4 Events";
			($cmdFailed, $outString) = runCmd($cmd);
			if ($cmdFailed) {
				$logger->error("kubernetesAreAllPodRunningWithNum failed: $cmdFailed");
			} else {
				$logger->debug("Command: $cmd");
				$logger->debug("Output: $outString");
				if (($outString =~ /FailedScheduling/) && !($outString =~ /PersistentVolumeClaims/)){
					$console_logger->error("Error running kubernetes pod : FailedScheduling podLabelString $podLabelString, namespace $namespace");
					$logger->debug("kubernetesAreAllPodRunningWithNum FailedScheduling podLabelString $podLabelString, namespace $namespace, output:\n$outString");
					return (0, "FailedScheduling");
				}
			}
		}
		if ($status ne "Running") {
			$logger->debug("kubernetesAreAllPodRunningWithNum: Found a non-running pod: $status");
			return 0;
		}	
	}
	
	# make sure all of the endpoints have been created in the associated service
	$cmd = "kubectl get endpoints --selector=$podLabelString -o=jsonpath='{.items[*].subsets[*].addresses[*].ip}' --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString | wc -w";
	($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesAreAllPodRunningWithNum failed: $cmdFailed");
	} else {
		$logger->debug("Command: $cmd");
		$logger->debug("Output: $outString");
		if ($num != $outString) {
			$logger->debug("kubernetesAreAllPodRunningWithNum: Not all endpoints have been created. Found $outString, expected $num");
			return 0;
		}	
	}
	
	$logger->debug("kubernetesAreAllPodRunningWithNum: All pods are running");
	return 1;
}

sub kubernetesAreAllPodUpWithNum {
	my ( $self, $serviceTypeImpl, $commandString, $namespace, $findString, $num ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	my $console_logger = get_logger("Console");
	$logger->debug("kubernetesAreAllPodUpWithNum exec $commandString for serviceTypeImpl $serviceTypeImpl, namespace $namespace, findString $findString, num $num");

	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	my $cmd;
	my $outString;	
	my $cmdFailed;
	$cmd = "kubectl get pod -o=jsonpath='{.items[*].metadata.name}' --selector=impl=$serviceTypeImpl --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString";
	($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesAreAllPodUpWithNum get pod failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	my @names = split /\s+/, $outString;
	if ($#names < 0) {
		$console_logger->error("kubernetesAreAllPodUpWithNum: There are no pods with label $serviceTypeImpl in namespace $namespace");
		exit(-1);
	}
	
	my $numFound = $#names + 1;
	if ($numFound != $num) {
		$logger->debug("kubernetesAreAllPodUpWithNum: Found $numFound of $num pods with label $serviceTypeImpl in namespace $namespace");
		return 0;
	}
	
	foreach my $podName (@names) { 	
		$cmd = "kubectl exec -c $serviceTypeImpl --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString $podName -- $commandString";
		($cmdFailed, $outString) = runCmd($cmd);
		$logger->debug("Command: $cmd");
		$logger->debug("Output: $outString");
		if ($cmdFailed) {
			$logger->debug("kubernetesAreAllPodUpWithNum not up on pod $podName: $outString");
			return 0;
		}
		if ( !($findString eq '') && !($outString =~ /$findString/) ) {
			$logger->debug("kubernetesAreAllPodUpWithNum: No match of $findString to Output on pod $podName");
			return 0;
		}	
	}
	$logger->debug("kubernetesAreAllPodUpWithNum: Matched $findString to $num pods");
	return 1;
}

sub kubernetesDoPodsExist {
	my ( $self, $podLabelString, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesDoPodsExist podLabelString $podLabelString, namespace $namespace");

	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	my $cmd;
	$cmd = "kubectl get pod --selector=$podLabelString -o=jsonpath='{.items[*].status.phase}' --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString";
	my ($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesDoPodsExist failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");

	my @stati = split /\s+/, $outString;
	if ($#stati < 0) {
		$logger->debug("kubernetesDoPodsExist: There are no pods with label $podLabelString in namespace $namespace");
		return 0;
	}

	return 1;
}

sub kubernetesCopyFromFirst {
	my ( $self, $podLabelString, $containerName, $namespace, $sourceFile, $destFile ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	my $console_logger = get_logger("Console");
	$logger->debug("kubernetesGetLogs podLabelString $podLabelString, namespace $namespace");
	
	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	# Get the list of pods
	my $cmd;
	my $outString;
	my $cmdFailed;
	$cmd = "kubectl get pod -o=jsonpath='{.items[*].metadata.name}' --selector=$podLabelString --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString";
	($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesGetLogs get pod failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	my @names = split /\s+/, $outString;
	if ($#names < 0) {
		$console_logger->error("kubernetesCopyFromFirst: There are no pods with label $podLabelString in namespace $namespace");
		exit(-1);
	}
	
	my $podName = $names[0];
	$cmd = "kubectl cp -c $containerName  --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString $podName:$sourceFile $destFile";
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesCopyFromFirst failed: $cmdFailed");
	}
	
	return 1;
}

sub kubernetesGetLogs {
	my ( $self, $podLabelString, $serviceTypeImpl, $namespace, $destinationPath ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	my $console_logger = get_logger("Console");
	$logger->debug("kubernetesGetLogs podLabelString $podLabelString, namespace $namespace");
	
	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	# Get the list of pods
	my $cmd;
	my $outString;
	my $cmdFailed;
	$cmd = "kubectl get pod -o=jsonpath='{.items[*].metadata.name}' --selector=impl=$serviceTypeImpl --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString";
	($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesGetLogs get pod failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	my @names = split /\s+/, $outString;
	if ($#names < 0) {
		$logger->debug("kubernetesGetLogs: There are no pods with label $serviceTypeImpl in namespace $namespace");
		return 0; #this can happen in the cleanupAfterFailure path
	}
	
	my $maxLogLines = $self->getParamValue('maxLogLines');

	foreach my $podName (@names) {
		if ($maxLogLines > 0) {
			$cmd = "kubectl logs --tail $maxLogLines -c $serviceTypeImpl --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString $podName";
		} else {
			$cmd = "kubectl logs -c $serviceTypeImpl --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString $podName";
		}
		($cmdFailed, $outString) = runCmd($cmd);
		if ($cmdFailed) {
			$logger->error("kubernetesGetLogs logs failed: $cmdFailed");
		}

		$logger->debug("Command: $cmd");
		my $logName          = "$destinationPath/${podName}.log";
		my $applog;
		open( $applog, ">$logName" )
	  	||	 die "Error opening $logName:$!";
	  			
		print $applog $outString;
	
		close $applog;

	}
	
	return 1;
}

sub kubernetesFollowLogsFirstPod {
	my ( $self, $podLabelString, $containerName, $namespace, $outFile ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	my $console_logger = get_logger("Console");
	$logger->debug("kubernetesFollowLogs podLabelString $podLabelString, namespace $namespace");
	
	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	# Get the list of pods
	my $cmd;
	my $outString;
	my $cmdFailed;
	$cmd = "kubectl get pod -o=jsonpath='{.items[*].metadata.name}' --selector=$podLabelString --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString";
	($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesFollowLogs get pod failed: $cmdFailed");
	}
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	my @names = split /\s+/, $outString;
	if ($#names < 0) {
		$console_logger->error("kubernetesFollowLogs: There are no pods with label $podLabelString in namespace $namespace");
		exit(-1);
	}
	
	my $podName = $names[0];
	$cmd = "kubectl logs -c $containerName --follow --namespace=$namespace --kubeconfig=$kubeconfigFile $contextString $podName > $outFile";
	($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("kubernetesFollowLogs logs failed: $cmdFailed");
	}
}

sub kubernetesTopPodAllNamespaces {
	my ( $self, $intervalSec, $destinationPath ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	my $console_logger = get_logger("Console");
	$logger->debug("kubernetesTopPodAllNamespaces intervalSec $intervalSec, destinationPath $destinationPath");
	
	if ($self->kubectlTopPodRunning) {
		return;
	}
	$self->kubectlTopPodRunning(1);
	
	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	# Fork a process to run in the background
	my $pid = fork();
	if ( !defined $pid ) {
			$console_logger->error("Couldn't fork a process: $!");
			exit(-1);
	} elsif ( $pid == 0 ) {

		open( FILE, ">$destinationPath/kubectl_top_pod-all-ns.txt" )
			 or die "Couldn't open $destinationPath/kubectl_top_pod--all-ns.txt: $!";		
		
		my $end;
		local $SIG{HUP} = sub { $end = 1 };
		until ($end) {
			my $cmd;
			my $outString;
			my $cmdFailed;
			$cmd = "kubectl top pod --heapster-scheme=https --all-namespaces --kubeconfig=$kubeconfigFile $contextString";
			($cmdFailed, $outString) = runCmd($cmd, 0);
			if ($cmdFailed) {
				$logger->info("kubernetesTopPodAllNamespaces top pod failed: $cmdFailed");
			}
			my $time;
			$cmd = "date -u";
			($cmdFailed, $time) = runCmd($cmd);
			if ($cmdFailed) {
				$logger->info("kubernetesTopPodAllNamespaces date failed: $cmdFailed");
			}
			chomp($time);
			print FILE "$time\n";
			print FILE $outString;
			sleep $intervalSec;
		}
		close FILE;
		$logger->info("kubernetesTopPodAllNamespaces exit");
		exit;
	}
	$self->kubectlTopPodRunning($pid);
	$logger->info("kubernetesTopPod started pid $pid");

}

sub kubernetesTopNode {
	my ( $self, $intervalSec, $destinationPath ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	my $console_logger = get_logger("Console");
	$logger->debug("kubernetesTopNode intervalSec $intervalSec, destinationPath $destinationPath");
	
	if ($self->kubectlTopNodeRunning) {
		return;
	}
	$self->kubectlTopNodeRunning(1);
	
	my $kubeconfigFile = $self->getParamValue('kubeconfigFile');
	my $context = $self->getParamValue('kubeconfigContext');
	my $contextString = "";
	if ($context) {
	  $contextString = "--context=$context";	
	}

	# Fork a process to run in the background
	my $pid = fork();
	if ( !defined $pid ) {
			$console_logger->error("Couldn't fork a process: $!");
			exit(-1);
	} elsif ( $pid == 0 ) {

		open( FILE, ">$destinationPath/kubectl_top_node.txt" )
			 or die "Couldn't open $destinationPath/kubectl_top_node.txt: $!";		

		my $end;
		local $SIG{HUP} = sub { $end = 1 };
		until ($end) {
			my $cmd;
			my $outString;
			my $cmdFailed;
			$cmd = "kubectl top node --heapster-scheme=https --kubeconfig=$kubeconfigFile $contextString";
			($cmdFailed, $outString) = runCmd($cmd, 0);
			if ($cmdFailed) {
				$logger->info("kubernetesTopNode top node failed: $cmdFailed");
			}
			my $time;
			$cmd = "date -u";
			($cmdFailed, $time) = runCmd($cmd);
			if ($cmdFailed) {
				$logger->info("kubernetesTopPodAllNamespaces date failed: $cmdFailed");
			}
			chomp($time);
			print FILE "$time\n";
			print FILE $outString;
			sleep $intervalSec;
		}
		$logger->info("kubernetesTopNode exit");
		close FILE;
		exit;
	}
	$self->kubectlTopNodeRunning($pid);
	$logger->info("kubernetesTopNode started pid $pid");

}

sub kubernetesStopTops {
	my ( $self ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	my $console_logger = get_logger("Console");
	my $pidPod = $self->kubectlTopPodRunning;
	my $pidNode = $self->kubectlTopNodeRunning;
	$logger->debug("kubernetesStopTops pids Pod:$pidPod Node:$pidNode");

	if ($pidPod > 1) {
		$self->kubectlTopPodRunning(0);
		$logger->debug("kubernetesStopTops TopPod SIG HUP to pid $pidPod");
		kill HUP => $pidPod;
		waitpid $pidPod, 0;
		$logger->debug("kubernetesStopTops TopPod pid $pidPod stopped");
	}

	if ($pidNode > 1) {
		$self->kubectlTopNodeRunning(0);
		$logger->debug("kubernetesStopTops TopNode SIG HUP to pid $pidNode");
		kill HUP => $pidNode;
		waitpid $pidNode, 0;
		$logger->debug("kubernetesStopTops TopNode pid $pidNode stopped");
	}
}

override 'startStatsCollection' => sub {
	my ( $self, $intervalLengthSec, $numIntervals, $tmpDir ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");

	my $destinationDir = "$tmpDir/statistics/kubernetes";
	my $cmd;
	$cmd = "mkdir -p $destinationDir";
	my ($cmdFailed, $outString) = runCmd($cmd);
	if ($cmdFailed) {
		$logger->error("startStatsCollection failed: $cmdFailed");
		return;
	}

	$self->kubernetesTopPodAllNamespaces(15, $destinationDir);
	$self->kubernetesTopNode(15, $destinationDir);
};

override 'stopStatsCollection' => sub {
	my ( $self ) = @_;
	$self->kubernetesStopTops();
};


__PACKAGE__->meta->make_immutable;

1;
