# Copyright 2017-2019 VMware, Inc.
# SPDX-License-Identifier: BSD-2-Clause
package AuctionBidDockerService;

use Moose;
use MooseX::Storage;

use POSIX;
use Services::Service;
use Parameters qw(getParamValue);
use StatsParsers::ParseGC qw( parseGCLog );
use Log::Log4perl qw(get_logger);

use namespace::autoclean;

with Storage( 'format' => 'JSON', 'io' => 'File' );

extends 'Service';

has 'mongosDocker' => (
	is      => 'rw',
	isa     => 'Str',
	default => "",
);

override 'initialize' => sub {
	my ($self) = @_;

	super();
};

sub setMongosDocker {
	my ( $self, $mongosDockerName ) = @_;
	$self->mongosDocker($mongosDockerName);
}

override 'create' => sub {
	my ( $self, $logPath ) = @_;

	my $name     = $self->name;
	my $hostname = $self->host->name;
	my $impl     = $self->getImpl();

	my $logName = "$logPath/CreateAuctionBidDocker-$hostname-$name.log";
	my $applog;
	open( $applog, ">$logName" )
	  || die "Error opening /$logName:$!";

	# The default create doesn't map any volumes
	my %volumeMap;

	# Set environment variables for startup configuration
	my $serviceParamsHashRef =
	  $self->appInstance->getServiceConfigParameters( $self, $self->getParamValue('serviceType') );

	my $threads            = $self->getParamValue('auctionBidServerThreads');
	my $connections        = $self->getParamValue('auctionBidServerJdbcConnections');
	my $tomcatCatalinaBase = $self->getParamValue('bidServiceCatalinaBase');
	my $maxIdle = ceil($self->getParamValue('auctionBidServerJdbcConnections') / 2);
	my $nodeNum = $self->instanceNum;
	my $users = $self->appInstance->getUsers();
	my $maxConnections =
	  ceil( $self->getParamValue('frontendConnectionMultiplier') *
		  $users /
		  ( $self->appInstance->getTotalNumOfServiceType('auctionBidServer') * 1.0 ) );
	if ( $maxConnections < 100 ) {
		$maxConnections = 100;
	}

	my $completeJVMOpts .= $self->getParamValue('auctionBidServerJvmOpts');
	$completeJVMOpts .= " " . $serviceParamsHashRef->{"jvmOpts"};

	if ( $self->getParamValue('logLevel') >= 3 ) {
		$completeJVMOpts .= " -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -Xloggc:$tomcatCatalinaBase/logs/gc.log ";
	}
	$completeJVMOpts .= " -DnodeNumber=$nodeNum ";
	
	my $dbServicesRef = $self->appInstance->getAllServicesByType("dbServer");
	my $dbService     = $dbServicesRef->[0];
	my $dbHostname    = $self->getHostnameForUsedService($dbService);
	my $db            = $dbService->getImpl();
	my $dbPort        = $self->getPortNumberForUsedService( $dbService, $db );
	my $useTLS = 0;
	if ( $self->getParamValue('ssl') && ( $self->appInstance->getTotalNumOfServiceType('webServer') == 0 ) ) {
		$useTLS = 1;
	}
	my %envVarMap;
	$envVarMap{"TOMCAT_JVMOPTS"} = "\"$completeJVMOpts\"";
	$envVarMap{"TOMCAT_THREADS"} = $threads;
	$envVarMap{"TOMCAT_JDBC_CONNECTIONS"} = $connections;
	$envVarMap{"TOMCAT_JDBC_MAXIDLE"} = $maxIdle;
	$envVarMap{"TOMCAT_CONNECTIONS"} = $maxConnections;
	$envVarMap{"TOMCAT_DB_IMPL"} = $db;
	$envVarMap{"TOMCAT_DB_HOSTNAME"} = $dbHostname;
	$envVarMap{"TOMCAT_DB_PORT"} = $dbPort;
	$envVarMap{"TOMCAT_USE_TLS"} = $useTLS;
	$envVarMap{"TOMCAT_HTTP_PORT"} = $self->internalPortMap->{"http"};
	$envVarMap{"TOMCAT_HTTPS_PORT"} = $self->internalPortMap->{"https"};
	$envVarMap{"TOMCAT_SHUTDOWN_PORT"} = $self->internalPortMap->{"shutdown"} ;

	# Create the container
	my %portMap;
	my $directMap = 0;
	foreach my $key ( keys %{ $self->internalPortMap } ) {
		my $port = $self->internalPortMap->{$key};
		$portMap{$port} = $port;
	}

	my $cmd        = "";
	my $entryPoint = "";

	$self->host->dockerRun(
		$applog, $self->name,
		$impl, $directMap, \%portMap, \%volumeMap, \%envVarMap, $self->dockerConfigHashRef,
		$entryPoint, $cmd, $self->needsTty
	);

	close $applog;
};

sub stopInstance {
	my ( $self, $logPath ) = @_;
	my $logger = get_logger("Weathervane::Services::AuctionBidDockerService");
	$logger->debug("stop AuctionBidDockerService");

	my $hostname = $self->host->name;
	my $name     = $self->name;
	my $logName  = "$logPath/StopAuctionBidDocker-$hostname-$name.log";

	my $applog;
	open( $applog, ">$logName" )
	  || die "Error opening /$logName:$!";

	$self->host->dockerStop( $applog, $name );

	close $applog;
}

sub startInstance {
	my ( $self, $logPath ) = @_;
	my $hostname = $self->host->name;
	my $name     = $self->name;
	my $logName  = "$logPath/StartAuctionBidDocker-$hostname-$name.log";

	my $applog;
	open( $applog, ">$logName" )
	  || die "Error opening /$logName:$!";

	if ( $self->host->dockerNetIsHostOrExternal($self->getParamValue('dockerNet') )) {

		# For docker host networking, external ports are same as internal ports
		$self->portMap->{"http"}  = $self->internalPortMap->{"http"};
		$self->portMap->{"https"} = $self->internalPortMap->{"https"};
		$self->portMap->{"shutdown"} = $self->internalPortMap->{"shutdown"};
	}
	else {
		# For bridged networking, ports get assigned at start time
		my $portMapRef = $self->host->dockerPort($name);
		$self->portMap->{"http"}  = $portMapRef->{ $self->internalPortMap->{"http"} };
		$self->portMap->{"https"} = $portMapRef->{ $self->internalPortMap->{"https"} };
		$self->portMap->{"shutdown"} = $portMapRef->{ $self->internalPortMap->{"shutdown"} };
	}

	close $applog;
}

override 'remove' => sub {
	my ( $self, $logPath ) = @_;
	my $logger = get_logger("Weathervane::Services::AuctionBidDockerService");
	$logger->debug("logPath = $logPath");
	my $hostname = $self->host->name;
	my $name     = $self->name;
	my $logName  = "$logPath/RemoveAuctionBidDocker-$hostname-$name.log";

	my $applog;
	open( $applog, ">$logName" )
	  || die "Error opening /$logName:$!";

	$self->host->dockerStopAndRemove( $applog, $name );

	close $applog;
};

sub isUp {
	my ( $self, $applog ) = @_;
	my $hostname = $self->host->name;
	my $port     = $self->portMap->{"http"};

	my $response = `curl -s http://$hostname:$port/auction/healthCheck`;
	print $applog "curl -s http://$hostname:$port/auction/healthCheck\n";
	print $applog "$response\n";

	if ( $response =~ /alive/ ) {
		return 1;
	}
	else {
		return 0;
	}
}

sub isRunning {
	my ( $self, $fileout ) = @_;
	my $name = $self->name;

	return $self->host->dockerIsRunning( $fileout, $name );

}

sub isStopped {
	my ( $self, $fileout ) = @_;
	my $name = $self->name;

	return !$self->host->dockerExists( $fileout, $name );
}

sub setPortNumbers {
	my ( $self ) = @_;
	
	my $serviceType = $self->getParamValue( 'serviceType' );
	my $portOffset = 0;
	my $portMultiplier = $self->appInstance->getNextPortMultiplierByServiceType($serviceType);
	$portOffset = $self->getParamValue( $serviceType . 'PortOffset')
	  + ( $self->getParamValue( $serviceType . 'PortStep' ) * $portMultiplier );
	$self->internalPortMap->{"http"} = 80 + $portOffset;
	$self->internalPortMap->{"https"} = 443 + $portOffset;
	$self->internalPortMap->{"shutdown"} = 8005 + ( $self->getParamValue( $serviceType . 'PortStep' ) * $portMultiplier );
}

sub setExternalPortNumbers {
	my ($self)     = @_;
	my $name       = $self->name;
	
	my $portMapRef = $self->host->dockerPort($name);

	if ( $self->host->dockerNetIsHostOrExternal($self->getParamValue('dockerNet') )) {

		# For docker host networking, external ports are same as internal ports
		$self->portMap->{"http"}  = $self->internalPortMap->{"http"};
		$self->portMap->{"https"} = $self->internalPortMap->{"https"};
		$self->portMap->{"shutdown"} = $self->internalPortMap->{"shutdown"};
	}
	else {
		# For bridged networking, ports get assigned at start time
		$self->portMap->{"http"}  = $portMapRef->{ $self->internalPortMap->{"http"} };
		$self->portMap->{"https"} = $portMapRef->{ $self->internalPortMap->{"https"} };
		$self->portMap->{"shutdown"} = $portMapRef->{ $self->internalPortMap->{"shutdown"} };
	}

}

sub configure {
	my ( $self, $logPath, $users, $suffix ) = @_;

}

sub stopStatsCollection {
	my ($self)   = @_;
	my $port     = $self->portMap->{"http"};
	my $hostname = $self->host->name;
	my $name     = $self->name;

}

sub startStatsCollection {
	my ( $self, $intervalLengthSec, $numIntervals ) = @_;
	my $tomcatCatalinaBase = $self->getParamValue('tomcatCatalinaBase');
	my $setupLogDir        = $self->getParamValue('tmpDir') . "/setupLogs";
	my $name               = $self->name;
	my $hostname           = $self->host->name;


	my $logName = "$setupLogDir/StartStatsCollectionAuctionBidDocker-$hostname-$name.log";

	my $applog;
	open( $applog, ">$logName" )
	  || die "Error opening /$logName:$!";
	$self->host->dockerKill("USR1", $applog, $name);

	close $applog;

}

sub getStatsFiles {
	my ( $self, $destinationPath ) = @_;

	my $tomcatCatalinaBase = $self->getParamValue('tomcatCatalinaBase');
	my $name               = $self->name;
	my $hostname           = $self->host->name;

	my $logpath = "$destinationPath/$name";
	if ( !( -e $logpath ) ) {
		`mkdir -p $logpath`;
	}

	my $logName = "$logpath/GetStatsFilesAuctionBidDocker-$hostname-$name.log";

	my $applog;
	open( $applog, ">$logName" )
	  || die "Error opening /$logName:$!";

	`mv /tmp/$hostname-$name-performanceMonitor.csv $logpath/. 2>&1`;
	`mv /tmp/$hostname-$name-performanceMonitor.json $logpath/. 2>&1`;

	$self->host->dockerCopyFrom( $applog, $name, "$tomcatCatalinaBase/logs/gc*.log", "$logpath/." );

	close $applog;

}

sub cleanStatsFiles {
	my ( $self, $destinationPath ) = @_;

}

sub getLogFiles {
	my ( $self, $destinationPath ) = @_;
	my $logger = get_logger("Weathervane::Services::AuctionBidDockerService");
	$logger->debug("getLogFiles");

	my $tomcatCatalinaBase = $self->getParamValue('tomcatCatalinaBase');
	my $name               = $self->name;
	my $hostname           = $self->host->name;

	my $logpath = "$destinationPath/$name";
	if ( !( -e $logpath ) ) {
		`mkdir -p $logpath`;
	}

	my $logName = "$logpath/AuctionBidDockerLogs-$hostname-$name.log";

	my $applog;
	open( $applog, ">$logName" )
	  || die "Error opening /$logName:$!";

	print $applog $self->host->dockerGetLogs( $applog, $name );

	close $applog;

}

sub cleanLogFiles {
	my ( $self, $destinationPath ) = @_;
	my $logger = get_logger("Weathervane::Services::AuctionBidDockerService");
	$logger->debug("cleanLogFiles");
}

sub parseLogFiles {
	my ($self) = @_;

}

sub getConfigFiles {
	my ( $self, $destinationPath ) = @_;
	my $tomcatCatalinaBase = $self->getParamValue('tomcatCatalinaBase');
	my $name               = $self->name;
	my $hostname           = $self->host->name;

	my $logpath = "$destinationPath/$name";
	if ( !( -e $logpath ) ) {
		`mkdir -p $logpath`;
	}

	my $logName = "$logpath/GetConfigFilesAuctionBidDocker-$hostname-$name.log";

	my $applog;
	open( $applog, ">$logName" )
	  || die "Error opening /$logName:$!";

	$self->host->dockerCopyFrom( $applog, $name, "$tomcatCatalinaBase/conf/*",        "$logpath/." );
	$self->host->dockerCopyFrom( $applog, $name, "$tomcatCatalinaBase/bin/setenv.sh", "$logpath/." );
	close $applog;

}

sub getConfigSummary {
	my ($self) = @_;
	tie( my %csv, 'Tie::IxHash' );
	$csv{"tomcatThreads"}     = $self->getParamValue('appServerThreads');
	$csv{"tomcatConnections"} = $self->getParamValue('appServerJdbcConnections');
	$csv{"tomcatJvmOpts"}     = $self->getParamValue('appServerJvmOpts');
	return \%csv;
}

sub getStatsSummary {
	my ( $self, $statsLogPath, $users ) = @_;
	tie( my %csv, 'Tie::IxHash' );

	my $gcviewerDir     = $self->getParamValue('gcviewerDir');

	# Only parseGc if gcviewer is present
	if ( -f "$gcviewerDir/gcviewer-1.34-SNAPSHOT.jar" ) {

		open( HOSTCSVFILE, ">>$statsLogPath/tomcat_gc_summary.csv" )
		  or die "Can't open $statsLogPath/tomcat_gc_summary.csv : $! \n";
		my $addedHeaders = 0;

		tie( my %accumulatedCsv, 'Tie::IxHash' );
		my $serviceType = $self->getParamValue('serviceType');
		my $servicesRef = $self->appInstance->getAllServicesByType($serviceType);
		my $numServices = $#{$servicesRef} + 1;
		my $csvHashRef;
		foreach my $service (@$servicesRef) {
			my $name    = $service->name;
			my $logPath = $statsLogPath . "/" . $service->host->name . "/$name";
			$csvHashRef = ParseGC::parseGCLog( $logPath, "", $gcviewerDir );

			if ( !$addedHeaders ) {
				print HOSTCSVFILE "Hostname";
				foreach my $key ( keys %$csvHashRef ) {
					print HOSTCSVFILE ",$key";
				}
				print HOSTCSVFILE "\n";

				$addedHeaders = 1;
			}

			print HOSTCSVFILE $service->host->name;
			foreach my $key ( keys %$csvHashRef ) {
				print HOSTCSVFILE "," . $csvHashRef->{$key};
				if ( $csvHashRef->{$key} eq "na" ) {
					next;
				}
				if ( !( exists $accumulatedCsv{"tomcat_$key"} ) ) {
					$accumulatedCsv{"tomcat_$key"} = $csvHashRef->{$key};
				}
				else {
					$accumulatedCsv{"tomcat_$key"} += $csvHashRef->{$key};
				}
			}
			print HOSTCSVFILE "\n";

		}

		# Now turn the total into averages
		foreach my $key ( keys %$csvHashRef ) {
			if ( exists $accumulatedCsv{"tomcat_$key"} ) {
				$accumulatedCsv{"tomcat_$key"} /= $numServices;
			}
		}

		# Now add the key/value pairs to the returned csv
		@csv{ keys %accumulatedCsv } = values %accumulatedCsv;

		close HOSTCSVFILE;
	}
	return \%csv;
}

__PACKAGE__->meta->make_immutable;

1;
