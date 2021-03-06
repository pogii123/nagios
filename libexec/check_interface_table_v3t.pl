#!/usr/bin/perl
# nagios: -epn

# ------------------------------------------------------------------------
# Program: interfacetable_v3t
# Version: 0.04-1
# Author:  Yannick Charton - tontonitch-pro@yahoo.fr
# License: GPLv3
# Copyright (c) 2009-2012 Yannick Charton (http://www.tontonitch.com)

# COPYRIGHT:
# This software and the additional scripts provided with this software are
# Copyright (c) 2009-2012 Yannick Charton (tontonitch-pro@yahoo.fr)
# (Except where explicitly superseded by other copyright notices)
#
# LICENSE:
# This work is made available to you under the terms of version 3 of
# the GNU General Public License. A copy of that license should have
# been provided with this software.
# If not, see <http://www.gnu.org/licenses/>.
#
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# Nagios and the Nagios logo are registered trademarks of Ethan Galstad.
# ------------------------------------------------------------------------

use strict;
use warnings;

use lib ('/usr/local/nagios/libexec');
use lib ('/usr/local/interfacetable_v3t/lib');
use Net::SNMP qw(oid_base_match);
use Config::General;
use Data::Dumper;
  $Data::Dumper::Sortkeys = 1;
use Getopt::Long qw(:config no_ignore_case no_ignore_case_always bundling_override);
use utils qw(%ERRORS $TIMEOUT); # gather variables from utils.pm
use GeneralUtils;
use Settings;
use SnmpUtils;

# ========================================================================
# VARIABLES
# ========================================================================

# ------------------------------------------------------------------------
# global variable definitions
# ------------------------------------------------------------------------
use vars qw($PROGNAME $REVISION $CONTACT $TIMEOUT);
$PROGNAME       = $0;
$REVISION       = '0.04-1';
$CONTACT        = 'tontonitch-pro@yahoo.fr';
#$TIMEOUT       = 120;
#my %ERRORS     = ('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);
my %ERRORCODES  = (0=>'OK',1=>'WARNING',2=>'CRITICAL',3=>'UNKNOWN',4=>'DEPENDENT');
my %COLORS      = ('HighLight' => '#81BEF7');
my $UMASK       = "0000";
my $TMPDIR      = File::Spec->tmpdir();         # define cache directory or use /tmp
my $STARTTIME   = time ();                      # time of program start

# ------------------------------------------------------------------------
# OIDs definitions
# ------------------------------------------------------------------------

# Standard OIDs
# ------------------------------------------------------------------------
my $oid_sysDescr        = ".1.3.6.1.2.1.1.1.0";
my $oid_sysUpTime       = ".1.3.6.1.2.1.1.3.0";
my $oid_sysContact      = ".1.3.6.1.2.1.1.4.0";
my $oid_sysName         = ".1.3.6.1.2.1.1.5.0";
my $oid_sysLocation     = ".1.3.6.1.2.1.1.6.0";

my $oid_ifDescr         = ".1.3.6.1.2.1.2.2.1.2";     # + ".<index>"
my $oid_ifAlias         = ".1.3.6.1.2.1.31.1.1.1.18"; # + ".<index>"
my $oid_ifSpeed         = ".1.3.6.1.2.1.2.2.1.5";     # + ".<index>"
my $oid_ifSpeed_64      = ".1.3.6.1.2.1.31.1.1.1.15"; # + ".<index>"

my $oid_ifPhysAddress   = ".1.3.6.1.2.1.2.2.1.6";     # + ".<index>"
my $oid_ifAdminStatus   = ".1.3.6.1.2.1.2.2.1.7";     # + ".<index>"
my $oid_ifOperStatus    = ".1.3.6.1.2.1.2.2.1.8";     # + ".<index>"
#my $oid_ifLastChange    = ".1.3.6.1.2.1.2.2.1.9";     # + ".<index>", not used
my $oid_ifDuplexStatus  = ".1.3.6.1.2.1.10.7.2.1.19"; # + ".<index>"
my $oid_ipAdEntIfIndex  = ".1.3.6.1.2.1.4.20.1.2";    # + ".<IP address>"
my $oid_ipAdEntNetMask  = ".1.3.6.1.2.1.4.20.1.3";    # + ".<index>"
my $oid_ifVlanName      = '.1.3.6.1.2.1.47.1.2.1.1.2'; # + ".<index>"

#dot1dBridge: .1.3.6.1.2.1.17
my $oid_stp_ifindex_map = '.1.3.6.1.2.1.17.1.4.1.2';  # map from dot1base port table to SNMP ifindex table
my $oid_stp_portstate   = '.1.3.6.1.2.1.17.2.15.1.3'; # stp port states
my %stp_portstate_readable = (0=>'unknown',1=>'disabled',2=>'blocking',3=>'listening',4=>'learning',5=>'forwarding',6=>'broken');

# RFC1213 - Extracts about in/out stats
# in_octet:     The total number of octets received on the interface, including framing characters.
# in_error:     The number of inbound packets that contained errors preventing them from being deliverable to a
#               higher-layer protocol.
# in_discard:   The number of inbound packets which were chosen to be discarded even though no errors had been
#               detected to prevent their being deliverable to a higher-layer protocol. One possible reason for
#               discarding such a packet could be to free up buffer space.
# out_octet:    The total number of octets transmitted out of the interface, including framing characters.
# out_error:    The number of outbound packets that could not be transmitted because of errors.
# out_discard:  The number of outbound packets which were chosen to be discarded even though no errors had been
#               detected to prevent their being transmitted. One possible reason for discarding such a packet could
#               be to free up buffer space.
my $oid_in_octet_table          = '1.3.6.1.2.1.2.2.1.10';    # + ".<index>"
my $oid_in_error_table          = '1.3.6.1.2.1.2.2.1.14';    # + ".<index>"
my $oid_in_discard_table        = '1.3.6.1.2.1.2.2.1.13';    # + ".<index>"
my $oid_out_octet_table         = '1.3.6.1.2.1.2.2.1.16';    # + ".<index>"
my $oid_out_error_table         = '1.3.6.1.2.1.2.2.1.20';    # + ".<index>"
my $oid_out_discard_table       = '1.3.6.1.2.1.2.2.1.19';    # + ".<index>"
my $oid_in_octet_table_64       = '1.3.6.1.2.1.31.1.1.1.6';  # + ".<index>"
my $oid_out_octet_table_64      = '1.3.6.1.2.1.31.1.1.1.10'; # + ".<index>"

# Cisco specific OIDs
# ------------------------------------------------------------------------
my $oid_cisco_type              = '.1.3.6.1.4.1.9.5.1.2.16.0'; # ex: WS-C3550-48-SMI
my $oid_cisco_serial            = '.1.3.6.1.4.1.9.5.1.2.19.0'; # ex: CAT0645Z0HB
# NOT USED - my $oid_locIfIntBitsSec = '1.3.6.1.4.1.9.2.2.1.1.6';   # need to append integer for specific interface
# NOT USED - my $oid_locIfOutBitsSec = '1.3.6.1.4.1.9.2.2.1.1.8';   # need to append integer for specific interface
# NOT USED - my $cisco_ports         = '.1.3.6.1.4.1.9.5.1.3.1.1.14.1'; # number of ports of the switch
my $oid_cisco_ifVlanPort         = '.1.3.6.1.4.1.9.9.68.1.2.2.1.2'; # + ".?.<index>"

# For use in Cisco CATOS special hacks - NOT USED YET
# my $oid_cisco_port_name_table               = '.1.3.6.1.4.1.9.5.1.4.1.1.4';    # table of port names (the ones you set with 'set port name')
# my $oid_cisco_port_ifindex_map              = '.1.3.6.1.4.1.9.5.1.4.1.1.11';   # map from cisco port table to normal SNMP ifindex table
# my $oid_cisco_port_linkfaultstatus_table    = '.1.3.6.1.4.1.9.5.1.4.1.1.22.';  # see table below for possible codes
# my $oid_cisco_port_operstatus_table         = '.1.3.6.1.4.1.9.5.1.4.1.1.6.';   # see table below for possible values
# my $oid_cisco_port_addoperstatus_table      = '.1.3.6.1.4.1.9.5.1.4.1.1.23.';  # see table below for possible codes
# my %cisco_port_linkfaultstatus = (1=>'up',2=>'nearEndFault',3=>'nearEndConfigFail',4=>'farEndDisable',5=>'farEndFault',6=>'farEndConfigFail',7=>'otherFailure');
# my %cisco_port_operstatus      = (0=>'operstatus:unknown',1=>'operstatus:other',2=>'operstatus:ok',3=>'operstatus:minorFault',4=>'operstatus:majorFault');
# my %cisco_port_addoperstatus   = (0=>'other',1=>'connected',2=>'standby',3=>'faulty',4=>'notConnected',5=>'inactive',6=>'shutdown',7=>'dripDis',8=>'disable',9=>'monitor',10=>'errdisable',11=>'linkFaulty',12=>'onHook',13=>'offHook',14=>'reflector');

# HP specific OIDs
# ------------------------------------------------------------------------
my $oid_hp_ifVlanPort          = '.1.3.6.1.4.1.11.2.14.11.5.1.7.1.15.3.1.2';   # + ".<index>"
# Or? ifVlan = ".1.3.6.1.4.1.11.2.14.11.5.1.7.1.15.1.1.1";
#TODO my $oid_hp_ifDuplexStatus      = '.1.3.6.1.4.1.11.2.14.11.5.1.7.1.3.1.1.10';   # + ".<index>"
#TODO my %hp_ifDuplexStatus          = (1=>'HD10',2=>'HD10',3=>'FD10',4=>'FD100',5=>'auto neg');

# Juniper Netscreen specific OIDs (from NETSCREEN-INTERFACE/ZONE/VSYS-MIB)
# ------------------------------------------------------------------------
my $oid_juniper_nsIfIndex               = '.1.3.6.1.4.1.3224.9.1.1.1'; # + ".<index>"
my $oid_juniper_nsIfName                = '.1.3.6.1.4.1.3224.9.1.1.2'; # + ".<index>"
my $oid_juniper_nsIfDescr               = '.1.3.6.1.4.1.3224.9.1.1.22'; # + ".<index>"
my $oid_juniper_nsIfZone                = '.1.3.6.1.4.1.3224.9.1.1.4'; # + ".<index>"
my $oid_juniper_nsIfVsys                = '.1.3.6.1.4.1.3224.9.1.1.3'; # + ".<index>"
my $oid_juniper_nsIfStatus              = '.1.3.6.1.4.1.3224.9.1.1.5'; # + ".<index>"
my $oid_juniper_nsIfIp                  = '.1.3.6.1.4.1.3224.9.1.1.6'; # + ".<index>"
my $oid_juniper_nsIfNetmask             = '.1.3.6.1.4.1.3224.9.1.1.7'; # + ".<index>"
my $oid_juniper_nsIfMode                = '.1.3.6.1.4.1.3224.9.1.1.10'; # + ".<index>"
my $oid_juniper_nsIfMAC                 = '.1.3.6.1.4.1.3224.9.1.1.11'; # + ".<index>"

my $oid_juniper_nsIfMngTelnet           = '.1.3.6.1.4.1.3224.9.1.1.12'; # + ".<index>"
my $oid_juniper_nsIfMngSCS              = '.1.3.6.1.4.1.3224.9.1.1.13'; # + ".<index>"
my $oid_juniper_nsIfMngWEB              = '.1.3.6.1.4.1.3224.9.1.1.14'; # + ".<index>"
my $oid_juniper_nsIfMngSSL              = '.1.3.6.1.4.1.3224.9.1.1.15'; # + ".<index>"
my $oid_juniper_nsIfMngSNMP             = '.1.3.6.1.4.1.3224.9.1.1.16'; # + ".<index>"
my $oid_juniper_nsIfMngGlobal           = '.1.3.6.1.4.1.3224.9.1.1.17'; # + ".<index>"
my $oid_juniper_nsIfMngGlobalPro        = '.1.3.6.1.4.1.3224.9.1.1.18'; # + ".<index>"
my $oid_juniper_nsIfMngPing             = '.1.3.6.1.4.1.3224.9.1.1.19'; # + ".<index>"
my $oid_juniper_nsIfMngIdentReset       = '.1.3.6.1.4.1.3224.9.1.1.20'; # + ".<index>"

#NOT USED YET
#my $oid_juniper_nsIfMonPlyDeny          = '.1.3.6.1.4.1.3224.9.4.1.3'; # + ".<index>"
#my $oid_juniper_nsIfMonAuthFail         = '.1.3.6.1.4.1.3224.9.4.1.4'; # + ".<index>"
#my $oid_juniper_nsIfMonUrlBlock         = '.1.3.6.1.4.1.3224.9.4.1.5'; # + ".<index>"
#my $oid_juniper_nsIfMonTrMngQueue       = '.1.3.6.1.4.1.3224.9.4.1.6'; # + ".<index>"
#my $oid_juniper_nsIfMonTrMngDrop        = '.1.3.6.1.4.1.3224.9.4.1.7'; # + ".<index>"
#my $oid_juniper_nsIfMonEncFail          = '.1.3.6.1.4.1.3224.9.4.1.8'; # + ".<index>"
#my $oid_juniper_nsIfMonNoSa             = '.1.3.6.1.4.1.3224.9.4.1.9'; # + ".<index>"
#my $oid_juniper_nsIfMonNoSaPly          = '.1.3.6.1.4.1.3224.9.4.1.10'; # + ".<index>"
#my $oid_juniper_nsIfMonSaInactive       = '.1.3.6.1.4.1.3224.9.4.1.11'; # + ".<index>"
#my $oid_juniper_nsIfMonSaPolicyDeny     = '.1.3.6.1.4.1.3224.9.4.1.12'; # + ".<index>"

my $oid_juniper_nsZoneCfgId             = '.1.3.6.1.4.1.3224.8.1.1.1.1'; # + ".<index>"
my $oid_juniper_nsZoneCfgName           = '.1.3.6.1.4.1.3224.8.1.1.1.2'; # + ".<index>"
my $oid_juniper_nsZoneCfgType           = '.1.3.6.1.4.1.3224.8.1.1.1.3'; # + ".<index>"

my $oid_juniper_nsVsysCfgId             = '.1.3.6.1.4.1.3224.15.1.1.1.1'; # + ".<index>"
my $oid_juniper_nsVsysCfgName           = '.1.3.6.1.4.1.3224.15.1.1.1.2'; # + ".<index>"

# ------------------------------------------------------------------------
# Other global variables
# ------------------------------------------------------------------------
my %ghOptions = ();
my %ghSNMPOptions = ();
my %quadmask2dec = (
    '0.0.0.0'         => 0, '128.0.0.0'        => 1, '192.0.0.0'        => 2,
    '224.0.0.0'       => 3, '240.0.0.0'        => 4, '248.0.0.0'        => 5,
    '252.0.0.0'       => 6, '254.0.0.0'        => 7, '255.0.0.0'        => 8,
    '255.128.0.0'     => 9, '255.192.0.0'      => 10, '255.224.0.0'     => 11,
    '255.240.0.0'     => 12, '255.248.0.0'     => 13, '255.252.0.0'     => 14,
    '255.254.0.0'     => 15, '255.255.0.0'     => 16, '255.255.128.0'   => 17,
    '255.255.192.0'   => 18, '255.255.224.0'   => 19, '255.255.240.0'   => 20,
    '255.255.248.0'   => 21, '255.255.252.0'   => 22, '255.255.254.0'   => 23,
    '255.255.255.0'   => 24, '255.255.255.128' => 25, '255.255.255.192' => 26,
    '255.255.255.224' => 27, '255.255.255.240' => 28, '255.255.255.248' => 29,
    '255.255.255.252' => 30, '255.255.255.254' => 31, '255.255.255.255' => 32,
);

# ------------------------------------------------------------------------
# Other global initializations
# ------------------------------------------------------------------------

my $grefaAllIndizes;                                 # Sorted array which holds all interface indexes
my $gUsedDelta                       = 0;            # time delta for bandwidth calculations (really used)

my $gInitialRun                      = 0;            # Flag that will be set if there exists no interface information file
my $gNoHistory                       = 0;            # Flag that will be set in case there's no valid historical dataset
my $gDifferenceCounter               = 0;            # Number of changes. This variable is used in the exitcode algorithm
my $gIfLoadWarnCounter               = 0;            # counter for interfaces with warning load. This variable is used in the exitcode algorithm
my $gIfLoadCritCounter               = 0;            # counter for interfaces with critical load. This variable is used in the exitcode algorithm
my $gPktErrWarnCounter               = 0;
my $gPktErrCritCounter               = 0;
my $gPktDiscardWarnCounter           = 0;
my $gPktDiscardCritCounter           = 0;
my $gNumberOfInterfaces              = 0;            # Total number of interfaces including vlans ...
my $gNumberOfFreeInterfaces          = 0;            # in "check_for_unused_interfaces" counted number of free interfaces
my $gNumberOfFreeUpInterfaces        = 0;            # in "check_for_unused_interfaces" counted number of free interfaces with status AdminUp
my $gNumberOfInterfacesWithoutTrunk  = 0;            # in "check_for_unused_interfaces" counted number of interfaces WITHOUT trunk ports
my $gInterfacesWithoutTrunk          = {};           # in "check_for_unused_interfaces" we use this for counting
my $gNumberOfPerfdataInterfaces      = 0;            # in "EvaluateInterfaces" counted number of interfaces we collect perfdata for
my $gPerfdata                        = "";           # performancedata

my $gShortCacheTimer                 = 0;            # Short cache timer are calculated by check_options
my $gLongCacheTimer                  = 0;            # Long cache timer are calculated by check_options
my $gText;                                           # Plugin Output ...
my $gChangeText;                                     # Contains data of changes in interface properties
my $grefhSNMP;                                       # Temp snmp structure
my $grefhFile;                                       # Properties from the interface file
my $grefhCurrent;                                    # Properties from current interface states
my $grefhListOfChanges               = undef;        # List all the changes for long plugin output

# ========================================================================
# FUNCTION DECLARATIONS
# ========================================================================
sub check_options();

# ========================================================================
# MAIN
# ========================================================================

# Get command line options and adapt default values in %ghOptions
check_options();

# Set the timeout
logger(1, "Set global plugin timeout to ${TIMEOUT}s");
alarm($TIMEOUT);
$SIG{ALRM} = sub {
  logger(0, "Plugin timed out (${TIMEOUT}s).\nYou may need to extend the plugin timeout by using the -t option.");
  exit $ERRORS{"UNKNOWN"};
};

# ------------------------------------------------------------------------
# Initializations depending on options
# ------------------------------------------------------------------------

my $gFile =  normalize($ghOptions{'hostdisplay'}).'-Interfacetable';    # create uniq file name without extension
my $gInterfaceInformationFile = "$ghOptions{'statedir'}/$gFile.txt";    # file where we store interface information table

# If --snapshot is set, we dont track changes
$ghOptions{'snapshot'} and $gInitialRun = 1;

# ------------------------------------------------------------------------
# Info table initializations
# ------------------------------------------------------------------------
my $gInfoTableHTML;                                      # Generated HTML code of the Info table
my $grefAoHInfoTableHeader = [                           # Header for the colomns of the Info table
    {   Title => 'Name',                Enabled => 1 },
    {   Title => 'Uptime',              Enabled => 1 },
    {   Title => 'System Information',  Enabled => 1 },
    {   Title => 'Type',                Enabled => 0 },
    {   Title => 'Serial',              Enabled => 0 },
    {   Title => 'Location',            Enabled => 1 },
    {   Title => 'Contact',             Enabled => 1 },
    {   Title => 'Ports',               Enabled => 1 },
    {   Title => 'Delta (bandwidth calculations)', Enabled => 1 },
];
if ($ghOptions{'nodetype'} eq "cisco") {
    # show some specific cisco info in the info table: type and serial
    $grefAoHInfoTableHeader->[3]{Enabled} = 1;
    $grefAoHInfoTableHeader->[4]{Enabled} = 1;
}
my $grefAoHInfoTableData;                                # Contents of the Info table (Uptime, SysDescr, ...)

# ------------------------------------------------------------------------
# Interface table initializations
# ------------------------------------------------------------------------
my $gInterfaceTableHTML;                                 # Html code of the interface table
my $grefAoHInterfaceTableHeader = [                      # Header for the cols of the html table
    {   Title => 'Index',        Dataname => 'index',           Datatype => 'other',    Tablesort => 'sortable-numeric',            Enabled => 1 }, #0
    {   Title => 'Name',         Dataname => 'ifName',          Datatype => 'other',    Tablesort => 'sortable-text',               Enabled => 1 }, #1
    {   Title => 'Alias',        Dataname => 'ifAlias',         Datatype => 'property', Tablesort => 'sortable-text',               Enabled => 1 }, #2
    {   Title => 'Admin status', Dataname => 'ifAdminStatus',   Datatype => 'property', Tablesort => 'sortable-text',               Enabled => 1 }, #3
    {   Title => 'Oper status',  Dataname => 'ifOperStatus',    Datatype => 'property', Tablesort => 'sortable-text',               Enabled => 1 }, #4
    {   Title => 'Speed',        Dataname => 'ifSpeedReadable', Datatype => 'property', Tablesort => 'sortable-sortNetworkSpeed',   Enabled => 1 }, #5
    {   Title => 'Duplex',       Dataname => 'ifDuplexStatus',  Datatype => 'property', Tablesort => 'sortable-text',               Enabled => 0 }, #6
    {   Title => 'Stp',          Dataname => 'ifStpState',      Datatype => 'property', Tablesort => 'sortable-text',               Enabled => 0 }, #7
    {   Title => 'Vlan',         Dataname => 'ifVlanNames',     Datatype => 'property', Tablesort => 'sortable-numeric',            Enabled => 0 }, #8
    {   Title => 'Zone',         Dataname => 'nsIfZone',        Datatype => 'property', Tablesort => 'sortable-text',               Enabled => 0 }, #9
    {   Title => 'Vsys',         Dataname => 'nsIfVsys',        Datatype => 'property', Tablesort => 'sortable-text',               Enabled => 0 }, #10
    {   Title => 'Permitted management', Dataname => 'nsIfMng', Datatype => 'property', Tablesort => 'sortable-text',               Enabled => 0 }, #11
    {   Title => 'Load In',      Dataname => 'ifLoadIn',        Datatype => 'load',     Tablesort => 'sortable-numeric',            Enabled => 1 }, #12
    {   Title => 'Load Out',     Dataname => 'ifLoadOut',       Datatype => 'load',     Tablesort => 'sortable-numeric',            Enabled => 1 }, #13
    {   Title => 'IP',           Dataname => 'ifIpInfo',        Datatype => 'property', Tablesort => 'sortable-sortIPAddress',      Enabled => 1 }, #14
    {   Title => 'bpsIn',        Dataname => 'bpsIn',           Datatype => 'load',     Tablesort => 'sortable-sortNetworkTraffic', Enabled => 1 }, #15
    {   Title => 'bpsOut',       Dataname => 'bpsOut',          Datatype => 'load',     Tablesort => 'sortable-sortNetworkTraffic', Enabled => 1 }, #16
    {   Title => 'Pkt errors',   Dataname => 'pktErrDiscard',   Datatype => 'load',     Tablesort => 'sortable-sortPktErrors',      Enabled => 1 }, #17
    {   Title => 'Last traffic', Dataname => 'ifLastTraffic',   Datatype => 'other',    Tablesort => 'sortable-sortDuration',       Enabled => 1 }, #18
    {   Title => 'Actions',      Dataname => 'actions',         Datatype => 'other',    Tablesort => '',                            Enabled => 1 }, #19
];
my $grefAoHInterfaceTableData;                           # Contents of the interface table (Uptime, OperStatus, ...)

# show duplex mode
if ($ghOptions{'duplex'}) {$grefAoHInterfaceTableHeader->[6]->{Enabled} = 1;}
# show Spanning Tree port state
if ($ghOptions{'stp'}) {$grefAoHInterfaceTableHeader->[7]->{Enabled} = 1;}
# show VLANs per port
if ($ghOptions{'vlan'}) {$grefAoHInterfaceTableHeader->[8]->{Enabled} = 1;}
# show Netscreen specific info
if ($ghOptions{'nodetype'} eq "netscreen") {
    $grefAoHInterfaceTableHeader->[9]->{Enabled} = 1;
    $grefAoHInterfaceTableHeader->[10]->{Enabled} = 1;
    $grefAoHInterfaceTableHeader->[11]->{Enabled} = 1;
}

# ------------------------------------------------------------------------
# Configuration table initializations
# ------------------------------------------------------------------------
my $gConfigTableHTML;                                      # Generated HTML code of the Config table
my $grefAoHConfigTableHeader = [                           # Header for the colomns of the Config table
    {   Title => 'Parameter',           Enabled => 1 },
    {   Title => 'Result',              Enabled => 1 },
];
my $grefAoHConfigTableData;                                # Contents of the Config table

# ------------------------------------------------------------------------------
# Check host and snmp service reachability
# ------------------------------------------------------------------------------

# get uptime of the host - no caching !

logger(1, "Check that the target \"$ghOptions{hostquery}\" is reachable via snmp");
$grefhCurrent->{MD}->{Node}->{sysUpTime} = GetDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,[ "$oid_sysUpTime" ],$ghOptions{'cachedir'},0);
if (!defined $grefhCurrent->{MD}->{Node}->{sysUpTime} or $grefhCurrent->{MD}->{Node}->{sysUpTime} eq "") {
    logger(0, "Could not read sysUpTime information from host \"$ghOptions{hostquery}\" with snmp");
    exit $ERRORS{"CRITICAL"};
}

# ------------------------------------------------------------------------------
# Read historical data (from state file)
# ------------------------------------------------------------------------------

# read all interfaces and their properties into the hash
$grefhFile = ReadInterfaceInformationFile ("$gInterfaceInformationFile");
logger(5, "Data from files -> grefhFile:".Dumper($grefhFile));

# ------------------------------------------------------------------------------
# Read node related data (from snmp/cache)
# ------------------------------------------------------------------------------

# get sysDescr, sysName and other info for the info table. caching the long parameter
logger(1, "Retrieve target system information");
$grefhSNMP = GetMultipleDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,[ "$oid_sysDescr","$oid_sysName","$oid_sysContact","$oid_sysLocation" ],$ghOptions{'cachedir'},$gLongCacheTimer);
$grefhCurrent->{MD}->{Node}->{sysDescr} = "$grefhSNMP->{$oid_sysDescr}";
$grefhCurrent->{MD}->{Node}->{sysName}  = "$grefhSNMP->{$oid_sysName}";
$grefhCurrent->{MD}->{Node}->{sysContact} = "$grefhSNMP->{$oid_sysContact}";
$grefhCurrent->{MD}->{Node}->{sysLocation}  = "$grefhSNMP->{$oid_sysLocation}";
if ($ghOptions{'nodetype'} eq "cisco") {
    $grefhSNMP = GetMultipleDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,[ "$oid_cisco_type","$oid_cisco_serial" ],$ghOptions{'cachedir'},$gLongCacheTimer);
    $grefhCurrent->{MD}->{Node}->{cisco_type}   = "$grefhSNMP->{$oid_cisco_type}";
    $grefhCurrent->{MD}->{Node}->{cisco_serial} = "$grefhSNMP->{$oid_cisco_serial}";
}

# ------------------------------------------------------------------------------
# Read interface related data (from snmp/cache)
# ------------------------------------------------------------------------------

# Gather interface indexes, descriptions, and mac addresses, to generate unique
# and reformatted interface names.
Get_InterfaceNames ();

# Gather interface administration status
Get_AdminStatus ();

# Gather interface operational status
Get_OperStatus ();

# Gather interface ip addresses and masks
if ($ghOptions{'nodetype'} ne "netscreen") {
   Get_IpAddress_SubnetMask ();
}

# Gather interface traffics (in/out and packet errors/discards)
Get_Traffic ();

# Gather interface admin status, speed, alias and vlan
Get_Speed_Duplex_Alias_Vlan ($grefhCurrent);

# Gather Spanning Tree specific info (--stp)
if ($ghOptions{'stp'}) {
    Get_Stp ();
}

# Gather Juniper Netscreen specific info (--nodetype=netscreen)
if ($ghOptions{'nodetype'} eq "netscreen") {
    Get_Netscreen ();
}

logger(5, "Get interface info -> generated hash\ngrefhCurrent:".Dumper($grefhCurrent));

# ------------------------------------------------------------------------------
# Include / Exclude interfaces
# ------------------------------------------------------------------------------

# Save inclusion/exclusion information of each interface in the metadata
# 3 levels of inclusion/exclusion:
#  * global (exclude/include)
#     + globally include/exclude interfaces to be monitored
#     + excluded interfaces are represented by black overlayed rows in the
#       interface table
#     + by default, all the interfaces are included in this tracking. Excluding
#       an interface from that tracking is usually done for the interfaces that
#       we don't want any tracking (e.g. loopback interfaces)
#  * traffic tracking (exclude-traffic/include-traffic)
#     + include/exclude interfaces from traffic tracking
#     + traffic tracking consists in a check of the bandwidth usage of the interface,
#       and the error/discard packets.
#     + excluded interfaces are represented by a dark grey (css dependent)
#       cell style in the interface table
#     + by default, all the interfaces are included in this tracking. Excluding
#       an interface from that tracking is usually done for the interfaces known as
#       problematic (high traffic load) and consequently for which we don't want
#       load tracking
#  * property tracking (exclude-property/include-property)
#     + include/exclude interfaces from property tracking.
#     + property tracking consists in the check of any changes in the properties of
#       an interface, properties specified via the --track-property option.
#     + excluded interfaces are represented by a dark grey (css dependent)
#       cell style in the interface table
#     + by default, only the "operstatus" property is tracked. For the operstatus
#       property, the exclusion of an interface is usually done when the interface can
#       be down for normal reasons (ex: interfaces connected to printers sometime in
#       standby mode)

$grefhCurrent = EvaluateInterfaces (
    $ghOptions{'exclude'},
    $ghOptions{'include'},
    $ghOptions{'exclude-traffic'},
    $ghOptions{'include-traffic'},
    $ghOptions{'exclude-property'},
    $ghOptions{'include-property'}
    );
#logger(5, "Interface inclusions / exclusions -> generated hash\ngrefhCurrent:".Dumper($grefhCurrent));

# ------------------------------------------------------------------------------
# Create interface information table data
# ------------------------------------------------------------------------------

# sort ifIndex by number
@$grefaAllIndizes = sort { $a <=> $b }
    keys (%{$grefhCurrent->{MD}->{Map}->{IndexToName}});
logger(5, "Interface information table data -> generated array\ngrefaAllIndizes:".Dumper($grefaAllIndizes));

my $basetime = CleanAndSelectHistoricalDataset();
if (defined $basetime) {
    CalculateBps($basetime);
    EvaluatePackets($basetime);
} else {
    $gNoHistory = 1;
}

# ------------------------------------------------------------------------------
# write interface information file
# ------------------------------------------------------------------------------

# remember the counted interfaces
$grefhCurrent->{MD}->{Node}->{ports} = ${gNumberOfInterfacesWithoutTrunk};
$grefhCurrent->{MD}->{Node}->{freeports} = ${gNumberOfFreeInterfaces};
$grefhCurrent->{MD}->{Node}->{adminupfree} = ${gNumberOfFreeUpInterfaces};

# first run - the hash from the file is empty because we had no file before
# fill it up with all interface intormation and with the index tables
#
# we take a separate field where we remember the last reset
# of the entire file
if (not $grefhFile->{TableReset}) {
    $grefhFile->{TableReset} = scalar localtime time ();
    $grefhFile->{If} = $grefhCurrent->{If};
    logger(1, "Initial run -> $grefhFile->{TableReset}");
}

# Fill up the MD tree (MD = MetaData) - here we store all variable
# settings
$grefhFile->{MD} = $grefhCurrent->{MD};

WriteConfigFileNew ("$gInterfaceInformationFile",$grefhFile);

# ------------------------------------------------------------------------------
# STDOUT
# ------------------------------------------------------------------------------

# If there are changes in the table write it to stdout
if ($gChangeText) {
    $gText = $gChangeText . "$gNumberOfInterfacesWithoutTrunk interface(s)";
} else {
    $gText = "$gNumberOfInterfacesWithoutTrunk interface(s)"
}

#logger(5, "gInterfacesWithoutTrunk: " . Dumper (%{$gInterfacesWithoutTrunk}));
for my $switchport (keys %{$gInterfacesWithoutTrunk}) {
    if ($gInterfacesWithoutTrunk->{$switchport}) {
        # this port is free
        $gNumberOfFreeInterfaces++
    }
}
#TODO go critical...
if ( $gNumberOfFreeInterfaces >= 0 ) {
    logger(1, "---->>> ports: $gNumberOfInterfacesWithoutTrunk, free: $gNumberOfFreeInterfaces");
    $gText .= ", $gNumberOfFreeInterfaces free";
}

if ( $gNumberOfFreeUpInterfaces > 0 ) {
    $gText .= ", $gNumberOfFreeUpInterfaces AdminUp and free";
}

if ( $gNumberOfPerfdataInterfaces > 0 and $ghOptions{'enableperfdata'}) {
    $gText .= ", $gNumberOfPerfdataInterfaces graphed";         # thd
}

# ------------------------------------------------------------------------------
# Create host information table data
# ------------------------------------------------------------------------------

$grefAoHInfoTableData->[0]->[0]->{Value} = "$grefhCurrent->{MD}->{Node}->{sysName}";
$grefAoHInfoTableData->[0]->[1]->{Value} = TimeDiff (1,$grefhCurrent->{MD}->{Node}->{sysUpTime} / 100); # start at 1 because else we get "NoData"
$grefAoHInfoTableData->[0]->[2]->{Value} = "$grefhCurrent->{MD}->{Node}->{sysDescr}";
if ($ghOptions{'nodetype'} eq "cisco") {
    $grefAoHInfoTableData->[0]->[3]->{Value} = "$grefhCurrent->{MD}->{Node}->{cisco_type}";
    $grefAoHInfoTableData->[0]->[4]->{Value} = "$grefhCurrent->{MD}->{Node}->{cisco_serial}";
    $grefAoHInfoTableData->[0]->[5]->{Value} = "$grefhCurrent->{MD}->{Node}->{sysLocation}";
    $grefAoHInfoTableData->[0]->[6]->{Value} = "$grefhCurrent->{MD}->{Node}->{sysContact}";
    $grefAoHInfoTableData->[0]->[7]->{Value} = "ports:&nbsp;$gNumberOfInterfacesWithoutTrunk free:&nbsp;$gNumberOfFreeInterfaces";
    $grefAoHInfoTableData->[0]->[7]->{Value} .= "<br>AdminUpFree:&nbsp;$gNumberOfFreeUpInterfaces";
    if ($gUsedDelta) {$grefAoHInfoTableData->[0]->[8]->{Value} = "configured: $ghOptions{'delta'}s (+".($ghOptions{'delta'}/3)."s)<br>used: ${gUsedDelta}s" }
    else { $grefAoHInfoTableData->[0]->[8]->{Value} = "configured: $ghOptions{'delta'} (+".($ghOptions{'delta'}/3)."s)<br>used: no data to compare with"; }
} else {
    $grefAoHInfoTableData->[0]->[3]->{Value} = "$grefhCurrent->{MD}->{Node}->{sysLocation}";
    $grefAoHInfoTableData->[0]->[4]->{Value} = "$grefhCurrent->{MD}->{Node}->{sysContact}";
    $grefAoHInfoTableData->[0]->[5]->{Value} = "ports:&nbsp;$gNumberOfInterfacesWithoutTrunk free:&nbsp;$gNumberOfFreeInterfaces";
    $grefAoHInfoTableData->[0]->[5]->{Value} .= "<br>AdminUpFree:&nbsp;$gNumberOfFreeUpInterfaces";
    if ($gUsedDelta) {$grefAoHInfoTableData->[0]->[6]->{Value} = "configured: $ghOptions{'delta'}s (+".($ghOptions{'delta'}/3)."s)<br>used: ${gUsedDelta}s" }
    else { $grefAoHInfoTableData->[0]->[6]->{Value} = "configured: $ghOptions{'delta'} (+".($ghOptions{'delta'}/3)."s)<br>used: no data to compare with"; }
}

# ------------------------------------------------------------------------------
# Create config information table data
# ------------------------------------------------------------------------------

$grefAoHConfigTableData->[0] = [ {Value => "Globally excluded interfaces"}, {Value => ""} ];
$grefAoHConfigTableData->[1] = [ {Value => "Excluded interfaces from traffic tracking"}, {Value => ""} ];
$grefAoHConfigTableData->[2] = [ {Value => "Excluded interfaces from property tracking"}, {Value => ""} ];
$grefAoHConfigTableData->[3] = [ {Value => "Interface traffic load thresholds"},
    {Value => "warning at $ghOptions{'warning-load'}%, critical at $ghOptions{'critical-load'}%"} ];
$grefAoHConfigTableData->[4] = [ {Value => "Interface packet error/discard thresholds"},
    {Value => "errors: warning at $ghOptions{'warning-pkterr'} pkts/s, critical at $ghOptions{'critical-pkterr'} pkts/s; discards: warning at $ghOptions{'warning-pktdiscard'} pkts/s, critical at $ghOptions{'critical-pktdiscard'} pkts/s"} ];
$grefAoHConfigTableData->[5] = [ {Value => "Interface property tracked"}, {Value => join(", ",@{$ghOptions{'track-property'}})} ];
$grefAoHConfigTableData->[6] = [ {Value => "Interface property change thresholds"}, {Value => ""} ];
if ( $ghOptions{'warning-property'} > 0 ) {
    $grefAoHConfigTableData->[6]->[1]->{Value} .= "warning for $ghOptions{'warning-property'} change(s), ";
} else {
    $grefAoHConfigTableData->[6]->[1]->{Value} .= "no warning threshold, ";
}
if ( $ghOptions{'critical-property'} > 0 ) {
    $grefAoHConfigTableData->[6]->[1]->{Value} .= "critical for $ghOptions{'critical-property'} change(s)";
} else {
    $grefAoHConfigTableData->[6]->[1]->{Value} .= "no critical threshold";
}

# Loop through all interfaces
for my $ifName (keys %{$grefhCurrent->{MD}->{If}}) {
    # Denormalize interface name
    my $ifNameReadable = denormalize ($ifName);
    # Update the config table
    if ($grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedTrack} eq "true") {
        $grefAoHConfigTableData->[0]->[1]->{Value} ne "" and $grefAoHConfigTableData->[0]->[1]->{Value} .= ", ";
        $grefAoHConfigTableData->[0]->[1]->{Value} .= "$ifNameReadable";
    }
    if ($grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedLoadTrack} eq "true") {
        $grefAoHConfigTableData->[1]->[1]->{Value} ne "" and $grefAoHConfigTableData->[1]->[1]->{Value} .= ", ";
        $grefAoHConfigTableData->[1]->[1]->{Value} .= "$ifNameReadable";
    }
    if ($grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedPropertyTrack} eq "true") {
        $grefAoHConfigTableData->[2]->[1]->{Value} ne "" and $grefAoHConfigTableData->[2]->[1]->{Value} .= ", ";
        $grefAoHConfigTableData->[2]->[1]->{Value} .= "$ifNameReadable";
    }
}
$grefAoHConfigTableData->[0]->[1]->{Value} eq "" and $grefAoHConfigTableData->[0]->[1]->{Value} = "none";
$grefAoHConfigTableData->[1]->[1]->{Value} eq "" and $grefAoHConfigTableData->[1]->[1]->{Value} = "none";
$grefAoHConfigTableData->[2]->[1]->{Value} eq "" and $grefAoHConfigTableData->[2]->[1]->{Value} = "none";



#
# Generate Html Table
# do not compare ifName and ifIndex because they can change during reboot
# Field list: index,ifName,ifAlias,ifAdminStatus,ifOperStatus,ifSpeedReadable,ifDuplexStatus,ifVlanNames,ifLoadIn,ifLoadOut,ifIpInfo,bpsIn,bpsOut,ifLastTraffic
#
$grefAoHInterfaceTableData = GenerateInterfaceTableData ($grefAoHInterfaceTableHeader,$ghOptions{'track-property'});

# ------------------------------------------------------------------------------
# Create HTML tables
# ------------------------------------------------------------------------------

my $EndTime = time ();
my $TimeDiff = $EndTime-$STARTTIME;

# If current run is the first run we dont compare data
if ( $gInitialRun ) {
    logger(1, "Initial run -> Setting DifferenceCounter to zero.");
    $gDifferenceCounter = 0;
    #$gText = "$gNumberOfInterfacesWithoutTrunk interface(s)";
    $gText = "Initial run...";
} elsif ( $gNoHistory ){
    logger(1, "No history -> Setting DifferenceCounter to zero.");
    $gDifferenceCounter = 0;
    $gText = "No valid historical dataset...";
} else {
    logger(1, "Differences: $gDifferenceCounter");
    if ($gDifferenceCounter > 0) {
        if ($ghOptions{'outputshort'}) {
            $gText .= ", $gDifferenceCounter change(s)";
        } else {
            $gText .= ", $gDifferenceCounter change(s):";
            for my $field ( keys %{$grefhListOfChanges} ) {
                if (not $field =~ /^load|^warning-pkterr$|^critical-pkterr$|^warning-pktdiscard$|^critical-pktdiscard$/i) {
                    $gText .= " $field - @{$grefhListOfChanges->{$field}}";
                }
            }
        }
    }
}

# Create "small" information table
$gInfoTableHTML = Convert2HtmlTable (1,$grefAoHInfoTableHeader,$grefAoHInfoTableData,"infotable","");

# Create "big" interface table
$gInterfaceTableHTML   = Convert2HtmlTable (1,$grefAoHInterfaceTableHeader,$grefAoHInterfaceTableData,"interfacetable","#81BEF7");

# Create configuration table
$gConfigTableHTML = Convert2HtmlTable (2,$grefAoHConfigTableHeader,$grefAoHConfigTableData,"configtable","");

# ------------------------------------------------------------------------------
# Calculate exitcode and exit this program
# ------------------------------------------------------------------------------

# $gDifferenceCounter contains the number of changes which
# were made in the interface configurations
my $ExitCode = mcompare ({
    Value       => $gDifferenceCounter,
    Warning     => $ghOptions{'warning-property'},
    Critical    => $ghOptions{'critical-property'}
});

#if ($gNumberOfFreeUpInterfaces > 0) {
#    $ExitCode = $ERRORS{'WARNING'} if ($ExitCode ne $ERRORS{'CRITICAL'});
#}

# Load
if ($gIfLoadWarnCounter > 0 ) {
    $ExitCode = $ERRORS{'WARNING'} if ($ExitCode ne $ERRORS{'CRITICAL'});
    if ($ghOptions{'outputshort'}) {
        $gText .= ", load warning (>$ghOptions{'warning-load'}%): $gIfLoadWarnCounter";
    } else {
        $gText .= ", $gIfLoadWarnCounter warning load(s) (>$ghOptions{'warning-load'}%): @{$grefhListOfChanges->{loadwarning}}";
    }
}
if ($gIfLoadCritCounter > 0 ) {
    $ExitCode = $ERRORS{'CRITICAL'};
    if ($ghOptions{'outputshort'}) {
        $gText .= ", load critical (>$ghOptions{'critical-load'}%): $gIfLoadCritCounter";
    } else {
        $gText .= ", $gIfLoadCritCounter critical load(s) (>$ghOptions{'critical-load'}%): @{$grefhListOfChanges->{loadcritical}}";
    }
}

# Packet errors
if ($gPktErrWarnCounter > 0 ) {
    $ExitCode = $ERRORS{'WARNING'} if ($ExitCode ne $ERRORS{'CRITICAL'});
    if ($ghOptions{'outputshort'}) {
        $gText .= ", error pkts/s warning (>$ghOptions{'warning-pkterr'}): $gPktErrWarnCounter";
    } else {
        $gText .= ", $gPktErrWarnCounter warning error pkts/s (>$ghOptions{'warning-pkterr'}): @{$grefhListOfChanges->{'warning-pkterr'}}";
    }
}

if ($gPktErrCritCounter > 0 ) {
    $ExitCode = $ERRORS{'CRITICAL'};
    if ($ghOptions{'outputshort'}) {
        $gText .= ", error pkts/s critical (>$ghOptions{'critical-pkterr'}): $gPktErrCritCounter";
    } else {
        $gText .= ", $gPktErrCritCounter critical error pkts/s (>$ghOptions{'critical-pkterr'}): @{$grefhListOfChanges->{'critical-pkterr'}}";
    }
}

# Packet discards
if ($gPktDiscardWarnCounter > 0 ) {
    $ExitCode = $ERRORS{'WARNING'} if ($ExitCode ne $ERRORS{'CRITICAL'});
    if ($ghOptions{'outputshort'}) {
        $gText .= ", discard pkts/s warning (>$ghOptions{'warning-pktdiscard'}): $gPktDiscardWarnCounter";
    } else {
        $gText .= ", $gPktDiscardWarnCounter discard pkts/s (>$ghOptions{'warning-pktdiscard'}): @{$grefhListOfChanges->{'warning-pktdiscard'}}";
    }
}

if ($gPktDiscardCritCounter > 0 ) {
    $ExitCode = $ERRORS{'CRITICAL'};
    if ($ghOptions{'outputshort'}) {
        $gText .= ", discard pkts/s critical (>$ghOptions{'critical-pktdiscard'}): $gPktDiscardCritCounter";
    } else {
        $gText .= ", $gPktDiscardCritCounter discard pkts/s (>$ghOptions{'critical-pktdiscard'}): @{$grefhListOfChanges->{'critical-pktdiscard'}}";
    }
}

# Append html table link to text
$gText = $gText . ' <a href="' . $ghOptions{'htmltableurl'} . "/" . $gFile . ".html" . '" target="'.$ghOptions{'htmltablelinktarget'}.'">[details]</a>';

if ($ghOptions{'nodetype'} eq "cisco" and $grefhCurrent->{MD}->{cisco_type} and $grefhCurrent->{MD}->{cisco_serial}) {
    $gText = "$grefhCurrent->{MD}->{cisco_type} ($grefhCurrent->{MD}->{cisco_serial}): ". $gText;
}

# Write Html Table
WriteHtmlFile ({
    InfoTable       => $gInfoTableHTML,
    InterfaceTable  => $gInterfaceTableHTML,
    ConfigTable     => $gConfigTableHTML,
    Dir             => $ghOptions{'htmltabledir'},
    FileName        => "$ghOptions{'htmltabledir'}/$gFile".'.html'
});

# Write perfdata
if ( $gNumberOfPerfdataInterfaces > 0 and not $gInitialRun and not $gNoHistory and $ghOptions{'enableperfdata'}) {
    perfdataout();
}

# Print Text and exit with the correct exitcode
ExitPlugin ({
    ExitCode    =>  $ExitCode,
    Text        =>  $gText,
    Fields      =>  $gDifferenceCounter
});

# This code should never be reached
exit $ERRORS{"UNKNOWN"};

# ------------------------------------------------------------------------
#      MAIN ENDS HERE
# ------------------------------------------------------------------------

# ------------------------------------------------------------------------------
#      FUNCTIONS
# ------------------------------------------------------------------------------
# List:
# * ReadInterfaceInformationFile
# * ReadConfigFileNew
# * WriteConfigFileNew
# * Get_InterfaceNames
# * Get_IpAddress_SubnetMask
# * Get_Traffic
# * perfdataout
# * WriteHtmlFile
# * mcompare
# * GenerateInterfaceTableData
# * EvaluateInterfaces
# * Get_AdminStatus
# * Get_OperStatus
# * Get_TrafficInOut
# * Get_IfErrInOut
# * Get_IfDiscardInOut
# * CleanAndSelectHistoricalDataset
# * CalculateBps
# * EvaluatePackets
# * Get_Speed_Duplex_Alias_Vlan
# * Get_Stp
# * Get_Netscreen
# * ConvertSpeedToReadable
# * ConvertIfStatusToReadable
# * ConvertIfStatusToNumber
# * ConvertIfDuplexStatusToReadable
# * TimeDiff
# * colorcode
# * check_for_unused_interfaces
# * Convert2HtmlTable
# * ExitPlugin
# * print_usage
# * print_help
# * print_defaults
# * print_revision
# * support
# * check_options
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# ReadInterfaceInformationFile
# ------------------------------------------------------------------------------
# Description:
# Read all interfaces and its properties into the hash $grefhFile
# ------------------------------------------------------------------------------
sub ReadInterfaceInformationFile {

    my $InterfaceInformationFile = shift;
    my $grefhFile;

    # read all properties from the state file - store into $grefhFile
    if (-r "$InterfaceInformationFile") {
        logger(1, "Found a readable state file \"$InterfaceInformationFile\"");
        $grefhFile = ReadConfigFileNew ("$InterfaceInformationFile");

        # check that the state file is not an old formated file, generated by a previous version
        # of the plugin
        if (not $grefhFile->{Version} or $grefhFile->{Version} ne "$REVISION" ) {
            unlink ("$InterfaceInformationFile");   # delete the old file
            for (keys %$grefhFile) { delete $grefhFile->{$_}; }  # purge the $grefhFile hash
            logger(1, "Found a state file generated by another version of the plugin. Reinitialize the state file and the interface table now");
            WriteConfigFileNew ("$InterfaceInformationFile",$grefhCurrent);
            $gInitialRun = 1;
        } elsif ($grefhCurrent->{MD}->{Node}->{sysUpTime} < $grefhFile->{MD}->{Node}->{sysUpTime}) {
            # check if the node has just rebooted
            logger(1, "The node has been restarted (sysUpTime retrieved is smaller than the one in the state file). Any cache timers are disactivated for that run");
            $gShortCacheTimer = 0;
            $gLongCacheTimer  = 0;
            logger(1, "The node has been restarted (sysUpTime retrieved is smaller than the one in the state file). Purging the counters from history as not usable anymore");
            delete $grefhFile->{History};  # purge the History part in $grefhFile hash
        }

        # detect if the user has just changed between using the 64bits option or not.
        # In case of change, purge the history datasets as they are not correct anymore
        $grefhCurrent->{MD}->{CachedInfo}->{'64bits'} = $ghSNMPOptions{'64bits'};
        if (defined $grefhFile->{MD}->{CachedInfo}->{'64bits'} and $ghSNMPOptions{'64bits'} != $grefhFile->{MD}->{CachedInfo}->{'64bits'}) {
            logger(1, "Detected a change in the use of the --64bits option. Purging the counters from history as not usable anymore");
            delete $grefhFile->{History};  # purge the History part in $grefhFile hash
        }
    } else {
        # the file with interface information was not found - this is the first
        # run of the program or it was deleted before.
        # Create a new one and store the sysUptime immediately
        logger(1, "No readable state file \"$InterfaceInformationFile\" found, creating a new one");
        WriteConfigFileNew ("$InterfaceInformationFile",$grefhCurrent);
        $gInitialRun = 1;
    }
    return $grefhFile;
}

# ------------------------------------------------------------------------------
# ReadConfigFileNew
# ------------------------------------------------------------------------------
# Description:
# Read config file with the perl Config::General Module
#
#   http://search.cpan.org/search?query=Config%3A%3AGeneral&mode=all
#
# ------------------------------------------------------------------------------
sub ReadConfigFileNew {

    my $ConfigFile = shift;
    logger(2, "Reading config file: $ConfigFile");

    my $refoConfig; # object definition for the config
    my $refhConfig; # hash reference returned

    # return undef if file is not readable
    unless (-r "$ConfigFile") {
        logger(2, "Config file \"$ConfigFile\" not readable");
        return $refhConfig;
    }

    # Initialize ConfigFile Read Process (create object)
    eval {
        $refoConfig = new Config::General (
            -ConfigFile             => "$ConfigFile",
            -UseApacheInclude       => "false",
            -MergeDuplicateBlocks   => "false",
            -InterPolateVars        => "false",
            -SplitPolicy            => 'equalsign'
        );
    };
    if($@) {
        # it's not successfull so remove the bad config file and try again.
        logger(1, "CONFIG READ FAIL: create new one ($ConfigFile).");
        unlink "$ConfigFile";
        return $refhConfig;
    }

    # Read Config File
    %$refhConfig = $refoConfig->getall;

    # return reference
    return $refhConfig;
}

# ------------------------------------------------------------------------------
# WriteConfigFileNew
# ------------------------------------------------------------------------------
# Description:
# --- write a hash reference to a file
# --- see ReadConfigFileNew ---------
#
# $gFile = full qulified filename with path
# $refhStruct = hash reference
# ------------------------------------------------------------------------------
sub WriteConfigFileNew {
    my $ConfigFile   =   shift;
    my $refhStruct   =   shift;
    logger(3, "File to write: $ConfigFile");

    use File::Basename;

    my $refoConfig; # object definition for the config
    my $Directory = dirname ($ConfigFile);

    # Initialize ConfigFile Read Process (create object)
    $refoConfig = new Config::General (
        -ConfigPath             => "$Directory",
        -UseApacheInclude       => "false",
        -MergeDuplicateBlocks   => "false",
        -InterPolateVars        => "false",
        -SplitPolicy            => 'equalsign'
    );

    # Write Config File
    if (-f "$ConfigFile" and not -w "$ConfigFile") {
        logger(0, "Unable to write to file $ConfigFile $!\n");
        exit $ERRORS{"UNKNOWN"};
    }

    umask "$UMASK";
    $refhStruct->{Version} = $REVISION;
    $refoConfig->save_file("$ConfigFile", $refhStruct);
    logger(1, "Wrote interface data to file: $ConfigFile");

    return 0;
}

# ------------------------------------------------------------------------------
# Get_InterfaceNames
# ------------------------------------------------------------------------------
# Description:
# This function gather interface indexes, descriptions, and mac addresses, to
# generate unique and reformatted interface names. Interface names are the identifiant
# to retrieve any interface related information.
# This function also push to the grefhCurrent hash:
# - Some if info:
#  * name
#  * index
#  * mac address
# - Some map relations:
#  * name to index
#  * index to name
#  * name to description
# ------------------------------------------------------------------------------
# Function call:
#  Get_InterfaceNames();
# Arguments:
#  None
# Output:
#  None
# ------------------------------------------------------------------------------
sub Get_InterfaceNames {

    my $refaIfDescriptionLines  = ();
    my $refaIfPhysAddressLines  = ();
    my $refhIfDescriptionCounts = {};   # For duplicates counting
    my $refhIfPhysAddressCounts = {};   # For duplicates counting
    my $refhIfPhysAddressIndex  = {};   # To map the physical address to the index.
                                        # Used only when appending the mac address to the interface description
    my $Name = "";                      # Name of the interface. Formatted to be unique, based on interface description
                                        # and index / mac address

    # Get info from snmp
    #------------------------------------------

    # get all interface descriptions
    $refaIfDescriptionLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_ifDescr,$ghOptions{'cachedir'},0);
    if ($#$refaIfDescriptionLines < 0 ) {
        logger(0, "Could not read ifDescr information from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_ifDescr\n");
        exit $ERRORS{"UNKNOWN"};
    }

    # get all interface mac addresses
    $refaIfPhysAddressLines = ($ghOptions{'usemacaddr'}) ? GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_ifPhysAddress,$ghOptions{'cachedir'},0)
        : GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_ifPhysAddress,$ghOptions{'cachedir'},$gLongCacheTimer);
    if ($#$refaIfPhysAddressLines < 0 ) {
        logger(0, "Could not read ifPhysAddress information from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_ifPhysAddress\n");
        exit $ERRORS{"UNKNOWN"};
    }

    # Look for duplicate values
    #------------------------------------------

    # Find interface description duplicates
    for (@$refaIfDescriptionLines) {
        my ($Index,$Value) = split / /,$_,2;
        $Index =~ s/^.*\.//g;           # remove all but the index
        $Value =~ s/\s+$//g;            # remove invisible chars from the end
        unless(defined $refhIfDescriptionCounts->{"$Value"}){
            $refhIfDescriptionCounts->{"$Value"} = 0;
        }
        $refhIfDescriptionCounts->{"$Value"}++;
    }

    # Find physical address duplicates
    for (@$refaIfPhysAddressLines) {
        my ($Index,$Value) = split / /,$_,2;
        $Index =~ s/^.*\.//g;           # remove all but the index
        $Value =~ s/\s+$//g;            # remove invisible chars from the end
        unless(defined $refhIfPhysAddressCounts->{"$Value"}){
            $refhIfPhysAddressCounts->{"$Value"} = 0;
        }
        $refhIfPhysAddressCounts->{"$Value"}++;
        $refhIfPhysAddressIndex->{"$Index"} = "$Value";
    }

    #
    #------------------------------------------

    # Example of $refaIfDescriptionLines
    #    TOADD
    for (@$refaIfDescriptionLines) {
        my ($Index,$Desc) = split / /,$_,2;
        $Index =~ s/^.*\.//g;           # remove all but the index
        $Desc =~ s/\s+$//g;             # remove invisible chars from the end
        my $MacAddr = (defined $refhIfPhysAddressIndex->{$Index}) ? "$refhIfPhysAddressIndex->{$Index}" : "";

        logger(2, "Index=$Index Descr=\"$Desc\" (long cache: $gLongCacheTimer)");

        # Interface name formatting
        # -----------------------------------------------------------

        my $Name = "$Desc";
        # 1. check an empty interface description
        # this occurs on some devices (e.g. HP procurve switches)
        if ("$Desc" eq "") {
            # Set the name as "Port $index"
            # read the MAC address of the interface - independend if it has one or not
            $Name = "Port $Index";
            logger(2, "  Interface with index $Index has no description.\nName is set to $Name");
        } else {

            # 2. append the index to duplicate interface descriptions. Index is better than mac address as in lots of cases the
            # same mac address can be used for multiples interfaces (if there is a mac address...)
            # Example of nodes in that case: Dell Powerconnect Switches 53xx, 54xx, 60xx and 62xx: same interface name 'Ethernet Interface'
            # However, be sure to fix the interface index (see the node type documentation). If not fixed, this could lead to problems
            # where index is changed during reboot and duplicate interface names
            if ($refhIfDescriptionCounts->{"$Name"} > 1) {
                if ($ghOptions{usemacaddr}) {
                    logger(2, "  Duplicate interface description detected. Option \"usemacaddr\" used, checking mac address unicity...");
                    # check if we got a unique MAC Address associated to the interface
                    if ($refhIfPhysAddressCounts->{"$MacAddr"} < 2) {
                        $Name = "$Name ($MacAddr)";
                        logger(2, "  Mac address is unique. Appending the mac address. Name will be now \"$Name\"");
                    } else {
                        # overwise take the index
                        $Name = "$Desc ($Index)";
                        logger(2, "  Mac address is NOT unique. Appending the index. Name will be now \"$Name\"");
                    }
                } else {
                    $Name = "$Desc ($Index)";
                    logger(2, "  Duplicate interface description detected. Appending the index. Name will be now \"$Name\"");
                }
            }

            # 3. Known long of problematic interface names
            if ($Name =~ /^Adaptive Security Appliance '(.*)' interface$/) {
                #Cisco ASA 55xx series
                $Name="$1";
                logger(2, "  Interface name matching Cisco ASA interface pattern, name reduced to \"$Name\"");
            }
            elsif ($Name =~ /^(.*)[,;] Product.*$/) {
                #old AIX interfaces
                $Name="$1";
                logger(2, "  Interface name matching old AIX interface pattern, name reduced to \"$Name\"");
            }
            elsif ($Name =~ /^(.*) Ethernet Layer Intel .* Ethernet$/) {
                #Nokia firewall (Checkpoint IPSO Firewall)
                #Possibilities seem to be:
                # Ethernet Layer Intel 10/100 Ethernet
                # Ethernet Layer Intel Gigabit Ethernet
                $Name="$1";
                logger(2, "  Interface name matching long interface descriptions on a Nokia firewall, name reduced to \"$Name\"");
            }
            elsif ($Name =~ /^Firewall Services Module '(.*)' interface$/) {
                #Firewall Services Module in Cisco Catalyst 6500 Series Switch or Cisco 7600 Internet Router
                $Name="FWSM $1";
                logger(2, "  Interface name matching a Cisco Firewall Services Module interface pattern, name reduced to \"$Name\"");
            }

            # Detect long name, which may be reduced for a cleaner interface table
            my $name_warning_length = 30;
            if (length($Name) > $name_warning_length) {
                logger(2, "  Interface name quite long! (> $name_warning_length). Name: \"$Name\"");
            }
        }

        logger(2, "  ifName=\"$Name\" (normalized: \"".normalize ($Name)."\")");

        # normalize the interface name and description to not get into trouble
        # with special characters and how Config::General handles blanks
        $Name = normalize ($Name);
        $Desc = normalize ($Desc);

        # create new trees in the MetaData hash & the Interface hash, which
        # store interface index, description and mac address.
        # This is used later for displaying the html table
        $grefhCurrent->{MD}->{Map}->{NameToIndex}->{"$Name"} = "$Index";
        $grefhCurrent->{MD}->{Map}->{NameToDescr}->{"$Name"} = "$Desc";
        $grefhCurrent->{MD}->{Map}->{DescrToName}->{"$Desc"} = "$Name";
        $grefhCurrent->{MD}->{Map}->{IndexToName}->{"$Index"} = "$Name";
        $grefhCurrent->{If}->{$Name}->{index}   = "$Index";
        $grefhCurrent->{If}->{$Name}->{ifName} = "$Name";
        $grefhCurrent->{If}->{$Name}->{ifDescr} = "$Desc";
        $grefhCurrent->{If}->{$Name}->{ifMacAddr} = "$MacAddr";

    }
    return 0;
}

# ------------------------------------------------------------------------------
# Get_IpAddress_SubnetMask
# ------------------------------------------------------------------------------
# Description:
# This function extract ip addresses out of snmpwalk lines
# This function also push to the grefhCurrent hash:
# - Some if info:
#  * name
#  * index
#  * mac address
# ------------------------------------------------------------------------------
# Function call:
#  Get_IpAddress_SubnetMask();
# Arguments:
#  None
# Output:
#  None
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------
# extract ip addresses out of snmpwalk lines
#
# # snmpwalk -Oqn -c public -v 1 router IP-MIB::ipAdEntIfIndex
# .1.3.6.1.2.1.4.20.1.2.172.31.92.91 15
# .1.3.6.1.2.1.4.20.1.2.172.31.92.97 15
# .1.3.6.1.2.1.4.20.1.2.172.31.99.76 15
# .1.3.6.1.2.1.4.20.1.2.193.83.153.254 29
# .1.3.6.1.2.1.4.20.1.2.193.154.197.192 14
#
# # snmpwalk -Oqn -v 1 -c public router IP-MIB::ipAdEntNetMask
# .1.3.6.1.2.1.4.20.1.3.172.31.92.91 255.255.255.255
# .1.3.6.1.2.1.4.20.1.3.172.31.92.97 255.255.255.255
#
# ------------------------------------------------------------------------
sub Get_IpAddress_SubnetMask {
    my $refaIPLines;        # Lines returned from snmpwalk storing ip addresses
    my $refaNetMaskLines;   # Lines returned from snmpwalk storing physical addresses

    # Get info from snmp/cache
    #------------------------------------------

    # get all interface ip info - resulting table can be empty
    $refaIPLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_ipAdEntIfIndex,$ghOptions{'cachedir'},0);

    # store all ip information in the hash to avoid reading the netmask
    # again in the next run
    $grefhCurrent->{MD}->{CachedInfo}->{IpInfo} = join (";",@$refaIPLines);

    # remove all invisible chars incl. \r and \n
    $grefhCurrent->{MD}->{CachedInfo}->{IpInfo} =~ s/[\000-\037]|[\177-\377]//g;

    # get the subnet masks with caching 0 only if the ip addresses
    # have changed - resulting table can be empty
    if (defined $grefhFile->{MD}->{CachedInfo}->{IpInfo} and $grefhCurrent->{MD}->{CachedInfo}->{IpInfo} eq $grefhFile->{MD}->{CachedInfo}->{IpInfo}) {
        $refaNetMaskLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_ipAdEntNetMask,$ghOptions{'cachedir'},$gLongCacheTimer);
    } else {
        $refaNetMaskLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_ipAdEntNetMask,$ghOptions{'cachedir'},0);
    }

    # Get info from snmp/cache
    #------------------------------------------

    # Example lines:
    # .1.3.6.1.2.1.4.20.1.2.172.31.99.76 15
    # .1.3.6.1.2.1.4.20.1.2.193.83.153.254 29
    for (@$refaIPLines) {
        my ($IpAddress,$Index) = split / /,$_,2;        # blank splits OID & ifIndex
        $IpAddress  =~  s/^.*1\.4\.20\.1\.2\.//;        # remove up to the ip address
        $Index          =~  s/\D//g;                    # remove all but numbers

        # extract the netmask
        # $refaNetMaks looks like this:
        # $VAR1 = [
        #          '.1.3.6.1.2.1.4.20.1.3.10.1.1.4 255.255.0.0',
        #          '.1.3.6.1.2.1.4.20.1.3.10.2.1.4 255.255.0.0',
        #          '.1.3.6.1.2.1.4.20.1.3.172.30.1.4 255.255.0.0
        #        ];

        my ($Tmp,$NetMask) = split (" ",join ("",grep /$IpAddress /,@$refaNetMaskLines),2);
        unless (defined $NetMask) {$NetMask = "";}
        $NetMask =~ s/\s+$//;    # remove invisible chars from the end
        logger(2, "Index: $Index,\tIpAddress: $IpAddress,\tNetmask: $NetMask");
        if (defined $quadmask2dec{"$NetMask"}) {$NetMask = $quadmask2dec{"$NetMask"};}

        # get the interface name stored before from the index table
        my $Name = $grefhCurrent->{MD}->{Map}->{IndexToName}->{"$Index"};

        #Check that a mapping was possible between the ip info and an interface
        if ($Name) {

            logger(3, "IP info mapped to interface \"$Name\"");
            # separate multiple IP Adresses with a blank
            # blank is good because the WEB browser can break lines
            if ($grefhCurrent->{If}->{"$Name"}->{ifIpInfo}) {
                $grefhCurrent->{If}->{"$Name"}->{ifIpInfo} =
                $grefhCurrent->{If}->{"$Name"}->{ifIpInfo}." "
            }
            # now we are finished with the puzzle of getting ip and subnet mask
            # add IpInfo as property to the interface
            my $IpInfo = "$IpAddress";
            if ($NetMask) {$IpInfo .= "/$NetMask";}
            $grefhCurrent->{If}->{"$Name"}->{ifIpInfo} .= $IpInfo;

            # check if the IP address has changed to its first run
            my $FirstIpInfo = $grefhFile->{If}->{"$Name"}->{ifIpInfo};
            unless ($FirstIpInfo) {$FirstIpInfo = "";}

            # disable caching of this interface if ip information has changed
            if ("$IpInfo" ne "$FirstIpInfo") {
                $grefhCurrent->{MD}->{If}->{"$Name"}->{CacheTimer} = 0;
                $grefhCurrent->{MD}->{If}->{"$Name"}->{CacheTimerComment} =
                    "caching is disabled because of first or current IpInfo";
            }
        } else {
            logger(3, "Cannot map the IP info to any existing interface: no corresponding interface index. Skipping IP info.");
        }
    }

    return 0;
}


# ------------------------------------------------------------------------------
# Get_Traffic
# ------------------------------------------------------------------------------
# Description: gather interface traffics (in/out and packet errors/discards)
# ------------------------------------------------------------------------------
# Function call:
#  Get_Traffic();
# Arguments:
#  None
# Output:
#  None
# ------------------------------------------------------------------------------
sub Get_Traffic {
    my $refaOctetInLines;                               # Lines returned from snmpwalk storing ifOctetsIn
    my $refaOctetOutLines;                              # Lines returned from snmpwalk storing ifOctetsOut
    my $refaInErrorsLines;                              # Lines returned from snmpwalk storing ifPktsInErr
    my $refaOutErrorsLines;                             # Lines returned from snmpwalk storing ifPktsOutErr
    my $refaInDiscardsLines;                            # Lines returned from snmpwalk storing ifPktsInDiscard
    my $refaOutDiscardLines;                            # Lines returned from snmpwalk storing ifPktsOutDiscard

    # Get info from snmp/cache
    #------------------------------------------

    # change to 64 bit counters if option is set :
    if ($ghSNMPOptions{'64bits'}) {
    $oid_out_octet_table  = $oid_out_octet_table_64;
    $oid_in_octet_table   = $oid_in_octet_table_64;
    }

    # get all interface in/out traffic octet counters - no caching !
    # -> Octets in
    $refaOctetInLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_in_octet_table,$ghOptions{'cachedir'},0);
    if ($#$refaOctetInLines < 0 ) {
        logger(0, "Could not read ifOctetIn information from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_in_octet_table\n");
        exit $ERRORS{"UNKNOWN"};
    }
    # -> Octets out
    $refaOctetOutLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_out_octet_table,$ghOptions{'cachedir'},0);
    if ($#$refaOctetOutLines < 0 ) {
        logger(0, "Could not read ifOctetOut information from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_out_octet_table\n");
        exit $ERRORS{"UNKNOWN"};
    }

    # get all interface in/out packet error/discarded octet counters - no caching !
    # -> Packet errors in
    $refaInErrorsLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_in_error_table,$ghOptions{'cachedir'},0);
    if ($#$refaInErrorsLines < 0 ) {
        logger(0, "Could not read ifInErrors information from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_in_error_table\n");
        exit $ERRORS{"UNKNOWN"};
    }
    # -> Packet errors out
    $refaOutErrorsLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_out_error_table,$ghOptions{'cachedir'},0);
    if ($#$refaOutErrorsLines < 0 ) {
        logger(0, "Could not read ifOutErrors information from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_out_error_table\n");
        exit $ERRORS{"UNKNOWN"};
    }
    # -> Packet discards in
    $refaInDiscardsLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_in_discard_table,$ghOptions{'cachedir'},0);
    if ($#$refaInDiscardsLines < 0 ) {
        logger(0, "Could not read ifInDiscards information from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_in_discard_table\n");
        exit $ERRORS{"UNKNOWN"};
    }
    # -> Packet discards out
    $refaOutDiscardLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_out_discard_table,$ghOptions{'cachedir'},0);
    if ($#$refaOutDiscardLines < 0 ) {
        logger(0, "Could not read ifOutDiscards information from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_out_discard_table\n");
        exit $ERRORS{"UNKNOWN"};
    }

    # post-processing interface octet counters
    #------------------------------------------

    Get_TrafficInOut ($refaOctetInLines, "OctetsIn", "BitsIn");
    Get_TrafficInOut ($refaOctetOutLines, "OctetsOut", "BitsOut");
    Get_IfErrInOut ($refaInErrorsLines, "PktsInErr");
    Get_IfErrInOut ($refaOutErrorsLines, "PktsOutErr");
    Get_IfDiscardInOut ($refaInDiscardsLines, "PktsInDiscard");
    Get_IfDiscardInOut ($refaOutDiscardLines, "PktsOutDiscard");

    return 0;
}



# ------------------------------------------------------------------------
# write performance data
# perfdataout ();
# --------------------------------------------------------------------
# Grapher: pnp4nagios, nagiosgrapher, netwaysgrapherv2
# Format:
#    * full : generated performance data include plugin related stats,
#             interface status, interface load stats, and packet error stats
#    * loadonly : generated performance data include plugin related stats,
#                 interface status, and interface load stats
#    * globalonly : generated performance data include only plugin related stats
# ------------------------------------------------------------------------
sub perfdataout {

    #------  Pnp4nagios and (for the moment) Netwaysgrapherv2  ------#
    if ( $ghOptions{'grapher'} eq  "pnp4nagios" ) {

        # plugin related stats
        $gPerfdata .= "Interface_global::check_interface_table_global::".
            "time=${TimeDiff}s;;;; ".
            "uptime=$grefhCurrent->{MD}->{Node}->{sysUpTime}s;;;; ".
            "watched=${gNumberOfPerfdataInterfaces};;;; ".
            "useddelta=${gUsedDelta}s;;;; ".
            "ports=${gNumberOfInterfacesWithoutTrunk};;;; ".
            "freeports=${gNumberOfFreeInterfaces};;;; ".
            "adminupfree=${gNumberOfFreeUpInterfaces};;;; ";

        # interface status, and interface load stats
        unless ($ghOptions{'perfdataformat'} eq 'generalonly') {

            # $grefaAllIndizes is a indexed and sorted list of all interfaces
            for my $InterfaceIndex (@$grefaAllIndizes) {
                # Get normalized interface name (key for If data structure)
                my $Name = $grefhCurrent->{MD}->{Map}->{IndexToName}->{$InterfaceIndex};

                if ($grefhCurrent->{MD}->{If}->{$Name}->{ExcludedTrack} eq "false"
                    and defined $grefhCurrent->{MD}->{IfCounters}->{$Name}->{OctetsIn}
                    and $grefhCurrent->{If}->{$Name}->{ifLoadExceedIfSpeed} eq "false") {
                    my $port = sprintf("%03d", $InterfaceIndex);
                    #my $servicename = "Port$port";
                    my $servicename = "If_" . trim(denormalize($Name));
                    $servicename =~ s/[: ]/_/g;
                    $servicename =~ s/[()']//g;
                    my $perfdata = "";
                    #Add interface status if available
                    if (defined $grefhCurrent->{If}->{$Name}->{ifOperStatus}) {
                        if ($ghOptions{'portperfunit'} eq "octet") {
                            $perfdata .= "${servicename}::check_interface_table_port_octet::" . # servicename::plugin
                                "OperStatus=".ConvertIfStatusToNumber("$grefhCurrent->{If}->{$Name}->{ifOperStatus}").";;;0; " .
                                "OctetsIn=$grefhCurrent->{MD}->{IfCounters}->{$Name}->{OctetsIn}c;;;0; " .
                                "OctetsOut=$grefhCurrent->{MD}->{IfCounters}->{$Name}->{OctetsOut}c;;;0; ";
                        } else {
                            $perfdata .= "${servicename}::check_interface_table_port_bit::" . # servicename::plugin
                                "OperStatus=".ConvertIfStatusToNumber("$grefhCurrent->{If}->{$Name}->{ifOperStatus}").";;;0; " .
                                "BitsIn=$grefhCurrent->{MD}->{IfCounters}->{$Name}->{BitsIn}c;;;0; " .
                                "BitsOut=$grefhCurrent->{MD}->{IfCounters}->{$Name}->{BitsOut}c;;;0; ";
                        }
                        #Add pkt errors/discards if available and wanted
                        unless ($ghOptions{'perfdataformat'} eq 'loadonly') {
                            if (defined $grefhCurrent->{MD}->{IfCounters}->{$Name}->{PktsInErr}) {
                                $perfdata .= "PktsInErr=$grefhCurrent->{MD}->{IfCounters}->{$Name}->{PktsInErr}c;;;0; " .
                                    "PktsOutErr=$grefhCurrent->{MD}->{IfCounters}->{$Name}->{PktsOutErr}c;;;0; " .
                                    "PktsInDiscard=$grefhCurrent->{MD}->{IfCounters}->{$Name}->{PktsInDiscard}c;;;0; " .
                                    "PktsOutDiscard=$grefhCurrent->{MD}->{IfCounters}->{$Name}->{PktsOutDiscard}c;;;0; ";
                            }
                        }
                    }

                    logger(2, "collected perfdata: $Name\t$perfdata");
                    $gPerfdata .= "$perfdata";
                }
            }
        }
        # write perfdata to a spoolfile in perfdatadir instead of in plugin output
        if($ghOptions{'perfdatadir'}) {
            if(!defined($ghOptions{perfdataservicedesc})) {
                logger(0, "please specify --perfdataservicedesc when you want to use --perfdatadir to output perfdata.");
                exit $ERRORS{"UNKNOWN"};
            }
            # PNP Data example: (without the linebreaks)
            # DATATYPE::SERVICEPERFDATA\t
            # TIMET::$TIMET$\t
            # HOSTNAME::$HOSTNAME$\t                       -| this relies on getting the same hostname as in Icinga from -H or -h
            # SERVICEDESC::$SERVICEDESC$\t
            # SERVICEPERFDATA::$SERVICEPERFDATA$\t
            # SERVICECHECKCOMMAND::$SERVICECHECKCOMMAND$\t -| not needed (interfacetables uses own templates)
            # HOSTSTATE::$HOSTSTATE$\t                     -|
            # HOSTSTATETYPE::$HOSTSTATETYPE$\t              | not available here
            # SERVICESTATE::$SERVICESTATE$\t                | so its skipped
            # SERVICESTATETYPE::$SERVICESTATETYPE$         -|

            # build the output
            my $lPerfoutput;
            $lPerfoutput .= "DATATYPE::SERVICEPERFDATA\tTIMET::$STARTTIME";
            $lPerfoutput .= "\tHOSTNAME::".$ghOptions{'hostdisplay'};
            $lPerfoutput .= "\tSERVICEDESC::".$ghOptions{perfdataservicedesc};
            $lPerfoutput .= "\tSERVICEPERFDATA::".$gPerfdata;
            $lPerfoutput .= "\n";

            # delete the perfdata so it is not printed to Nagios/Icinga
            $gPerfdata = "";

            # flush to spoolfile
            my $filename = $ghOptions{perfdatadir} . "/interfacetables_v3t.$STARTTIME";
            umask "$UMASK";
            open (OUT,">>$filename") or die "cannot open $filename $!";
            flock (OUT, 2) or die "cannot flock $filename ($!)"; # get exclusive lock;

            print OUT $lPerfoutput;

            close(OUT);
        }

    #------  Nagiosgrapher  ------#
    } elsif ( $ghOptions{'grapher'} eq  "nagiosgrapher" ) {

        # Set the perfdata file
        my $filename = $ghOptions{perfdatadir} . "/service-perfdata.$STARTTIME";
        umask "$UMASK";
        open (OUT,">>$filename") or die "cannot open $filename $!";
        flock (OUT, 2) or die "cannot flock $filename ($!)"; # get exclusive lock;

        # plugin related stats
        print OUT "$grefhCurrent->{MD}->{Node}->{sysName}\t";  # hostname
        print OUT "Interface_global";                  # servicename
        print OUT "\t\t";                              # pluginoutput
        print OUT "time=${TimeDiff}s;;;; ";            # performancedata
        print OUT "uptime=$grefhCurrent->{MD}->{Node}->{sysUpTime}s;;;; ";
        print OUT "watched=${gNumberOfPerfdataInterfaces};;;; ";
        print OUT "useddelta=${gUsedDelta}s;;;; ";
        print OUT "ports=${gNumberOfInterfacesWithoutTrunk};;;; ";
        print OUT "freeports=${gNumberOfFreeInterfaces};;;; ";
        print OUT "adminupfree=${gNumberOfFreeUpInterfaces};;;; ";
        print OUT "\t$STARTTIME\n";                    # unix timestamp

        # interface status, and interface load stats
        unless ($ghOptions{'perfdataformat'} eq 'generalonly') {

            # $grefaAllIndizes is a indexed and sorted list of all interfaces
            for my $InterfaceIndex (@$grefaAllIndizes) {
                # Get normalized interface name (key for If data structure)
                my $Name = $grefhCurrent->{MD}->{Map}->{IndexToName}->{$InterfaceIndex};

                if ($grefhCurrent->{MD}->{If}->{$Name}->{ExcludedTrack} eq "false"
                    and defined $grefhCurrent->{MD}->{IfCounters}->{$Name}->{OctetsIn}
                    and $grefhCurrent->{If}->{$Name}->{ifLoadExceedIfSpeed} eq "false") {

                    my $servicename = "If_" . trim(denormalize($Name));
                    $servicename =~ s/[: ]/_/g;
                    $servicename =~ s/[()']//g;

                    my $perfdata = "";
                    #Add interface status if available
                    if (defined $grefhCurrent->{If}->{$Name}->{ifOperStatus}) {
                        if ($ghOptions{'portperfunit'} eq "octet") {
                            $perfdata .= "${servicename}::check_interface_table_port_octet::" . # servicename::plugin
                                "OperStatus=".ConvertIfStatusToNumber("$grefhCurrent->{If}->{$Name}->{ifOperStatus}").";;;0; " .
                                "OctetsIn=$grefhCurrent->{MD}->{IfCounters}->{$Name}->{OctetsIn}c;;;0; " .
                                "OctetsOut=$grefhCurrent->{MD}->{IfCounters}->{$Name}->{OctetsOut}c;;;0; ";
                        } else {
                            $perfdata .= "${servicename}::check_interface_table_port_bit::" . # servicename::plugin
                                "OperStatus=".ConvertIfStatusToNumber("$grefhCurrent->{If}->{$Name}->{ifOperStatus}").";;;0; " .
                                "BitsIn=$grefhCurrent->{MD}->{IfCounters}->{$Name}->{BitsIn}c;;;0; " .
                                "BitsOut=$grefhCurrent->{MD}->{IfCounters}->{$Name}->{BitsOut}c;;;0; ";
                        }
                        #Add pkt errors/discards if available and wanted
                        unless ($ghOptions{'perfdataformat'} eq 'loadonly') {
                            if (defined $grefhCurrent->{MD}->{IfCounters}->{$Name}->{PktsInErr}) {
                                $perfdata .= "PktsInErr=$grefhCurrent->{MD}->{IfCounters}->{$Name}->{PktsInErr}c;;;0; " .
                                    "PktsOutErr=$grefhCurrent->{MD}->{IfCounters}->{$Name}->{PktsOutErr}c;;;0; " .
                                    "PktsInDiscard=$grefhCurrent->{MD}->{IfCounters}->{$Name}->{PktsInDiscard}c;;;0; " .
                                    "PktsOutDiscard=$grefhCurrent->{MD}->{IfCounters}->{$Name}->{PktsOutDiscard}c;;;0; ";
                            }
                        }
                    }

                    # Print into perfdata output file
                    logger(2, "collected perfdata: $Name\t$perfdata");
                    print OUT "$grefhCurrent->{MD}->{Node}->{sysName}\t";  # hostname
                    print OUT "$servicename";                      # servicename
                    print OUT "\t\t";                              # pluginoutput
                    if ($grefhFile->{If}->{$Name}->{ifAlias} ne '') {
                        print OUT ' ' . trim(denormalize($grefhFile->{If}->{$Name}->{ifAlias}));
                    }
                    print OUT "$perfdata";                         # performancedata
                    print OUT "\t$STARTTIME\n";                    # unix timestamp
                }
            } # for $InterfaceIndex
        }

        # close the perfdata output file
        close (OUT);
    }
    return 0;
}

# ------------------------------------------------------------------------
# write performance data to a spool file
# perfdataout_spool ();
# --------------------------------------------------------------------
# Grapher: pnp4nagios or format compatible
# ------------------------------------------------------------------------

sub perfdataout_spool {
    if($ghOptions{'grapher'} eq  "pnp4nagios") {
        if(!defined($ghOptions{perfdataservicedesc})) {
            print STDERR "please specify --perfdataservicedesc when you want to use --perfdatadir to output perfdata\n";
            exit 3;
        }
        # PNP Data example: (without the linebreaks)
        # DATATYPE::SERVICEPERFDATA\t
        # TIMET::$TIMET$\t
        # HOSTNAME::$HOSTNAME$\t                       -| this relies on getting the same hostname as in Icinga from -H or -h
        # SERVICEDESC::$SERVICEDESC$\t
        # SERVICEPERFDATA::$SERVICEPERFDATA$\t
        # SERVICECHECKCOMMAND::$SERVICECHECKCOMMAND$\t -| not needed (interfacetables uses own templates)
        # HOSTSTATE::$HOSTSTATE$\t                     -|
        # HOSTSTATETYPE::$HOSTSTATETYPE$\t              | not available here
        # SERVICESTATE::$SERVICESTATE$\t                | so its skipped
        # SERVICESTATETYPE::$SERVICESTATETYPE$         -|

        # build the output
        my $lPerfoutput;
        $lPerfoutput .= "DATATYPE::SERVICEPERFDATA\tTIMET::$STARTTIME";
        $lPerfoutput .= "\tHOSTNAME::".$ghOptions{'hostdisplay'};
        $lPerfoutput .= "\tSERVICEDESC::".$ghOptions{perfdataservicedesc};
        $lPerfoutput .= "\tSERVICEPERFDATA::".$gPerfdata;
        $lPerfoutput .= "\n";

        # delete the perfdata so it is not printed to Nagios/Icinga
        $gPerfdata = "";

        # flush to spoolfile
        my $filename = $ghOptions{perfdatadir} . "/interfacetables_v3t.$STARTTIME";
        umask "$UMASK";
        open (OUT,">>$filename") or die "cannot open $filename $!";
        flock (OUT, 2) or die "cannot flock $filename ($!)"; # get exclusive lock;

        print OUT $lPerfoutput;

        close(OUT);
    }
    else {
        die "Perfdata Spool Output not available for grapher ".$ghOptions{'grapher'};
    }
}

# ------------------------------------------------------------------------
# Create interface table html table file
# This file will be visible on the browser
#
# WriteHtmlFile ({
#    InfoTable           => $gInfoTableHTML,
#    InterfaceTable      => $gInterfaceTableHTML,
#    ConfigTable         => $gConfigTableHTML,
#    Dir                 => $ghOptions{'htmltabledir'},
#    FileName            => $ghOptions{'htmltabledir'}/$gFile".'.html'
# });
#
# ------------------------------------------------------------------------
sub WriteHtmlFile {

    my $refhStruct = shift;

    umask "$UMASK";

                not -d $refhStruct->{Dir} and MyMkdir($refhStruct->{Dir});

    open (OUT,">$refhStruct->{FileName}") or die "cannot $refhStruct->{FileName} $!";
        # -- Header --
        print OUT '<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1" />
    <title>Interfacetable_v3t - ' . $grefhCurrent->{MD}->{Node}->{sysName} . '</title>
    <link rel="stylesheet" type="text/css" href="../css/' . $ghOptions{'css'} . '.css">
    <link rel="stylesheet" type="text/css" href="../css/button.css">
    <script type="text/javascript" src="../js/functions.js"></script>
    <script type="text/javascript" src="../js/tablesort.js"></script>
    <script type="text/javascript" src="../js/customsort.js"></script>
  </head>
<body>';
        # -- Body header --
        print OUT '<div width=98% align=center>';
        print OUT '    <div id="header">
        <div class="buttons">
            <a href="' . $ghOptions{htmltableurl} . '/index.php">
                <img src="../img/house.png" alt="node selector"/>
                node selector
            </a>
        </div>
        <div>';
        #print OUT '            <a href="' , $ghOptions{'accessmethod'} , '://' , $ghOptions{'hostquery'} , '">' , $ghOptions{'hostquery'} , '</a> updated: ' , scalar localtime $EndTime , ' (' , $EndTime-$STARTTIME , ' sec.)';
        print OUT '
        ' , $ghOptions{'hostquery'} , ' updated: ' , scalar localtime $EndTime , ' (' , $EndTime-$STARTTIME , ' sec.)';
        print OUT '
            <span class="button2">';
        while ( my ($key, $value) = each(%{$ghOptions{'accessmethod'}}) ) {
            if ($key =~ /^http$|^https$/) {
                print OUT '<a class="accessmethod" href=" ' . $value . '" target="_blank">' . $key . '</a>';
            } else {
                print OUT '<a class="accessmethod" href=" ' . $value . '">' . $key . '</a>';
            }
        }
        print OUT '
            </span>
        </div>
    </div>
    <br>';

        # -- Tables --
        print OUT '    <div id="info">
        <a name="topinfotable">Node information</a>' .
        $refhStruct->{InfoTable} . '
    </div>
    <br>
    <div id="interface">
        <a name=topinterfacetable>Interface information</a>' .
        $refhStruct->{InterfaceTable} . '
        <div id="toplink">
            <a href="#topinterfacetable">Back to top</a>
        </div>
    </div>
    <br>';
        if ( $ghOptions{configtable} ) {
        print OUT '    <div id="config">
        <a name=topconfigtable>Configuration information</a>' .
        $refhStruct->{ConfigTable} . '
    </div>
    <br>';
        }
        # -- Body footer --
        print OUT '
        <div class="buttons">
        <a class="green" href="javascript:history.back();">
            <img src="../img/arrow_left.png" alt="back"/>
            back
        </a>
        <a class="red" href="' . $ghOptions{reseturl} . '/InterfaceTableReset_v3t.cgi?Command=rm&What=' . $gInterfaceInformationFile . '">
            <img src="../img/arrow_refresh.png" alt="reset table"/>
            reset table
        </a>
    </div>
    <div id="footer">
        interfacetable_v3t ' . $REVISION . '
    </div>
</div>
<br>
</body>
</html>';
    close (OUT);
    logger(1, "HTML table file created: $refhStruct->{FileName}");
    return 0;
}

# ------------------------------------------------------------------------
# Purpose:
#   calc exit code
# ------------------------------------------------------------------------
sub mcompare {

    my $refhStruct = shift;

    my $ExitCode = $ERRORS{"OK"};

    $refhStruct->{Warning} and $refhStruct->{Value} >= $refhStruct->{Warning}
        and $ExitCode = $ERRORS{"WARNING"};

    $refhStruct->{Critical} and $refhStruct->{Value} >= $refhStruct->{Critical}
        and $ExitCode = $ERRORS{"CRITICAL"};

    return $ExitCode;
}

# ------------------------------------------------------------------------
# Compare data from refhFile and refhCurrent and create the csv data for
# html table.
# ------------------------------------------------------------------------
sub GenerateInterfaceTableData {

    my $refAoHInterfaceTableHeader  = shift;
    my $refaToCompare               = shift;            # Array of fields which should be included from change tracking
    my $iLineCounter                = 0;                # Fluss Variable (ah geh ;-) )
    my $refaContentForHtmlTable;                        # This is the final data structure which we pass to Convert2HtmlTable

    my $grefaInterfaceTableFields;
    foreach my $Cell ( @$grefAoHInterfaceTableHeader ) {
    #    foreach my $Cell ( @$Line ) {
            if ($Cell->{'Enabled'}) {
                push(@$grefaInterfaceTableFields,$Cell->{'Dataname'});
            }
    #    }
    }

    # Print a header for debug information
    logger(2, "x"x50);

    # Print tracking info
    logger(5, "Available fields:".Dumper($refAoHInterfaceTableHeader));
    logger(5, "Tracked fields:".Dumper($refaToCompare));

    # $grefaAllIndizes is a indexed and sorted list of all interfaces
    for my $InterfaceIndex (@$grefaAllIndizes) {

        # Current field ID
        my $iFieldCounter = 0;

        # Get normalized interface name (key for If data structure)
        my $Name = $grefhCurrent->{MD}->{Map}->{IndexToName}->{$InterfaceIndex};

        # Skip the interface if config table enabled
        if ($ghOptions{configtable} and $grefhCurrent->{MD}->{If}->{$Name}->{ExcludedTrack} eq "true") {
            next;
        }

        # This is the If datastructure from the interface information file
        my $refhInterFaceDataFile     = $grefhFile->{If}->{$Name};

        # This is the current measured If datastructure
        my $refhInterFaceDataCurrent  = $grefhCurrent->{If}->{$Name};

        # This variable used for exittext
        $gNumberOfInterfaces++;

        foreach my $Header ( @$refAoHInterfaceTableHeader ) {
            next if (not $Header->{'Enabled'});

            my $ChangeTime;
            my $LastChangeInfo          = "";
            #my $CellColor;
            my $CellBackgroundColor;
            my $CellStyle;
            my $CellContent;
            my $CurrentFieldContent     = "";
            my $FileFieldContent        = "";
            my $FieldType               = ""; # 'property' or 'load'

            if (defined $refhInterFaceDataCurrent->{"$Header->{Dataname}"}) {
                # This is used to calculate the id (used for displaying the html table)
                $CurrentFieldContent  = $refhInterFaceDataCurrent->{"$Header->{Dataname}"};
                # Delete the first and last "blank"
                $CurrentFieldContent =~ s/^ //;
                $CurrentFieldContent =~ s/ $//;
            }
            if (defined $refhInterFaceDataFile->{"$Header->{Dataname}"}) {
                $FileFieldContent = $refhInterFaceDataFile->{"$Header->{Dataname}"};
                # Delete the first and last "blank"
                $FileFieldContent =~ s/^ //;
                $FileFieldContent =~ s/ $//;
            }

            # Flag if the current status of this field should be compared with the
            # "snapshoted" status.
            my $CompareThisField = grep (/$Header->{Dataname}/i, @$refaToCompare);

            # some fields have a change time property in the interface information file.
            # if the change time exists we store this and write into html table
            $ChangeTime = $grefhFile->{MD}->{If}->{$Name}->{$Header->{Dataname}."ChangeTime"};

            # If interface is excluded or this is the initial run we don't lookup for
            # data changes
            if ($gInitialRun)  {
                $CompareThisField = 0;
                $CellStyle = "cellInitialRun";
            } elsif ($grefhCurrent->{MD}->{If}->{$Name}->{ExcludedTrack} eq "true") {
                $CompareThisField = 0;
                $CellStyle = "cellExcluded";
            } elsif (($grefhCurrent->{MD}->{If}->{$Name}->{ExcludedLoadTrack} eq "true") && ( $Header->{'Datatype'} eq "load" )) {
                $CompareThisField = 0;
                $CellStyle = "cellNotTracked";
            } elsif (($grefhCurrent->{MD}->{If}->{$Name}->{ExcludedPropertyTrack} eq "true") && ( $Header->{'Datatype'} eq "property" ) && ($CompareThisField == 1)) {
                $CompareThisField = 0;
                $CellStyle = "cellNotTracked";
            } elsif (defined $grefhCurrent->{If}->{$Name}->{$Header->{Dataname}."OutOfRange"}) {
                $CellBackgroundColor = $grefhCurrent->{If}->{$Name}->{$Header->{Dataname}."OutOfRange"};
            }

            # Set LastChangeInfo to this Format "(since 0d 0h 43m)"
            if ( defined $ChangeTime and $ghOptions{trackduration} ) {
                $ChangeTime = TimeDiff ("$ChangeTime",time());
                $LastChangeInfo = "(since $ChangeTime)";
            }

            if ( $CompareThisField  ) {
                logger(2, "Compare \"".denormalize($Name)."($Header->{Dataname})\" now=\"$CurrentFieldContent\" file=\"$FileFieldContent\"");
                if ( $CurrentFieldContent eq $FileFieldContent ) {
                    # Field content has NOT changed
                    $CellContent = denormalize ( $CurrentFieldContent );
                    $CellStyle = "cellTrackedOk";
                } else {
                    # Field content has changed ...
                    $CellContent = "now: " . denormalize( $CurrentFieldContent ) . "$LastChangeInfo was: " . denormalize ( $FileFieldContent );
                    if ($ghOptions{verbose} or $ghOptions{'warning-property'} > 0 or $ghOptions{'critical-property'} > 0) {
                        $gChangeText .= "(" . denormalize ($Name) .
                            ") $Header->{Dataname} now <b>$CurrentFieldContent</b> (was: <b>$FileFieldContent</b>)<br>";
                    }
                    $CellStyle = "cellTrackedChange";
                    $gDifferenceCounter++;

                    # Update the list of changes
                    if ( defined $refhInterFaceDataCurrent->{"ifAlias"} and $refhInterFaceDataCurrent->{"ifAlias"} ne "" ) {
                        push @{$grefhListOfChanges->{"$Header->{Dataname}"}}, trim(denormalize($Name))." (".trim(denormalize($refhInterFaceDataCurrent->{"ifAlias"})).")";
                    } else {
                        push @{$grefhListOfChanges->{"$Header->{Dataname}"}}, trim(denormalize($Name));
                    }
                }
            } else {
                # Filed will not be compared, just write the current field - value in the table.
                logger(2, "Not comparing $Header->{Dataname} on interface ".denormalize($Name));
                $CellContent = denormalize( $CurrentFieldContent );
            }

            # Actions field
            if (grep (/$Header->{Dataname}/i, "Actions")) {
                # Graphing solution link - one link per line/interface/port
                if ($grefhCurrent->{MD}->{If}->{$Name}->{ExcludedTrack} eq "false"
                    and defined $grefhCurrent->{MD}->{IfCounters}->{$Name}->{OctetsIn}
                    and $ghOptions{'enableperfdata'}) {
                        #my $servicename = 'Port' . sprintf("%03d", $InterfaceIndex);
                        my $servicename = "If_" . trim(denormalize($Name));
                        $servicename =~ s/#/%23/g;
                        $servicename =~ s/[: ]/_/g;
                        $servicename =~ s/[()']//g;
                        if ($ghOptions{'grapher'} eq  "pnp4nagios") {
                            $CellContent .= '<a href="' .
                                           $ghOptions{'grapherurl'} . '/graph?host=' . $ghOptions{'hostdisplay'} . '&srv=' . $servicename .
                                           '"><img src="' .
                                           '../img/chart.png' .
                                           '" alt="Trends" /></a>';
                        } elsif ($ghOptions{'grapher'} eq  "nagiosgrapher") {
                            $CellContent .= '<a href="' .
                                           #$ghOptions{'grapherurl'} . '/graphs.cgi?host=' . $ghOptions{'hostdisplay'} . '&srv=' . $servicename . '&page_act=[1]+Interface+traffic' .
                                           $ghOptions{'grapherurl'} . '/graphs.cgi?host=' . $ghOptions{'hostdisplay'} . '&srv=' . $servicename .
                                           '"><img src="' .
                                           '../img/chart.png' .
                                           '" alt="Trends" /></a>';
                        } elsif ($ghOptions{'grapher'} eq  "netwaysgrapherv2") {
                            $CellContent .= '<a href="' .
                                           $ghOptions{'grapherurl'} . '/graphs.cgi?host=' . $ghOptions{'hostdisplay'} . '&srv=' . $servicename .
                                           '"><img src="' .
                                           '../img/chart.png' .
                                           '" alt="Trends" /></a>';
                        }
                }
                # Retrieve detailed interface info via snmp link
                if ($ghOptions{'ifdetails'} and $grefhCurrent->{MD}->{If}->{$Name}->{ExcludedTrack} eq "false") {
                    $CellContent .= '<a href="xxxxxxxxxxxx.cgi?' .
                                   'host=' . $ghOptions{'hostquery'} .
                                   '&ifindex=' . $InterfaceIndex .
                                   '"><img src="' .
                                   '../img/binocular.png' .
                                   '" alt="Details" /></a>';
                }
            }

            # Write an empty cell content if CellContent is empty
            # This is for visual purposes
            not $CellContent and $CellContent = '&nbsp';

            # Store cell content in table
            $refaContentForHtmlTable->[ $iLineCounter ]->[ $iFieldCounter ]->{"Value"} = "$CellContent";

            # Change font color
            #  defined $CellColor and
            #  $refaContentForHtmlTable->[ $iLineCounter ]->[ $iFieldCounter ]->{Font} =
            #  $CellColor;
            # Change background color
            defined $CellBackgroundColor and
              $refaContentForHtmlTable->[ $iLineCounter ]->[ $iFieldCounter ]->{Background} = $CellBackgroundColor;
            # Change cell style
            defined $CellStyle and
              $refaContentForHtmlTable->[ $iLineCounter ]->[ $iFieldCounter ]->{Style} = $CellStyle;

            $iFieldCounter++;
        } # for Header

        $iLineCounter++;
    } # for $InterfaceIndex

    # Print a footer for debug information
    logger(5, " List of changes -> generated hash of array\ngrefhListOfChanges:".Dumper ($grefhListOfChanges));
    logger(2, "x"x50);

    return $refaContentForHtmlTable;
}

# ------------------------------------------------------------------------
# This function includes or excludes interfaces from:
#  * interface traffic load tracking
#  * interface property(ies) change tracking
#
# Interface traffic load tracking:
# All interfaces which are excluded using -e or --exclude will be
# excluded from traffic measurement (main check). Property(ies) tracking is
# implicitely disabled on such an interface.
#
# Interface property(ies) change tracking
# All the interfaces which are included in the traffic load tracking are
# automatically added to the interface properti(es) tracking list.
#
#   Indicated must be the interface name (ifDescr)
#   -e "3COM Etherlink PCI"
#
#   It is possible to exclude all interfaces
#   -e "ALL"
#
#   It is possible to exclude all interfaces but include one
#   -e "ALL" -i "3COM Etherlink PCI"
#
# It isnt neccessary to include ALL. By default, all the interfaces are
# included.
#
# The interface information file will be altered as follows:
#
# <MD>
#    <If>
#        <3COMQ20EtherlinkQ20PCI>
#            CacheTimer               3600
#            ExcludedLoadTrack        false
#            ExcludedPropertyTrack    true
#            ifOperStatusChangeTime   1151586678
#        </3COMQ20EtherlinkQ20PCI>
#    </If>
# </MD>
#
# ------------------------------------------------------------------------
sub EvaluateInterfaces {

    my $ExcludeTrackList = shift;
    my $IncludeTrackList = shift;
    my $ExcludeLoadTrackList = shift;
    my $IncludeLoadTrackList = shift;
    my $ExcludePropertyTrackList = shift;
    my $IncludePropertyTrackList = shift;

    if (defined $ExcludeTrackList) { logger(2, "ExcludeTrackList: " . join(", ",@{$ExcludeTrackList})); }
    if (defined $IncludeTrackList) { logger(2, "IncludeTrackList: " . join(", ",@{$IncludeTrackList})); }
    if (defined $ExcludeLoadTrackList) { logger(2, "ExcludeLoadTrackList: " . join(", ",@{$ExcludeLoadTrackList})); }
    if (defined $IncludeLoadTrackList) { logger(2, "IncludeLoadTrackList: " . join(", ",@{$IncludeLoadTrackList})); }
    if (defined $ExcludePropertyTrackList) { logger(2, "ExcludePropertyTrackList: " . join(", ",@{$ExcludePropertyTrackList})); }
    if (defined $IncludePropertyTrackList) { logger(2, "IncludePropertyTrackList: " . join(", ",@{$IncludePropertyTrackList})); }

    # Loop through all interfaces
    for my $ifName (keys %{$grefhCurrent->{MD}->{If}}) {

        # Denormalize interface name
        my $ifNameReadable = denormalize ($ifName);
        my $ifAliasReadable = denormalize ($grefhCurrent->{If}->{"$ifName"}->{ifAlias});

        #----- Includes or excludes interfaces from all tracking -----#

        # By default, don't exclude the interface
        $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedTrack} = "false";
        $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedLoadTrack} = "false";
        $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedPropertyTrack} = "false";

        # Exclude "temporary interfaces"
        # After a reboot of a node, the description of some interfaces seems to have the following format for
        # a short duration: <ifDescr>_0x<MAC address>
        # Don't know yet if this is related to the script logic of if this is really what is returned by
        # the snmp request. Nothing about that in the RFC (RFC1213)... Need some tests.
        # Anyway, skipping these interfaces...
        if ("$ifNameReadable" =~ /_0x/) {
            logger(1, "-- exclude \"temporary interface\" \"$ifNameReadable\"");
            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedTrack} = "true";
            next;
        }

        # Process the interface exclusion list
        for my $ExcludeString (@$ExcludeTrackList) {
            if ($ghOptions{regexp}) {
                if ($ghOptions{'alias-matching'}) {
                    if ("${ifNameReadable}" =~ /$ExcludeString/i or "${ifAliasReadable}" =~ /$ExcludeString/i or "$ExcludeString" eq "ALL") {
                        logger(1, "-- exclude ($ExcludeString) interface \"$ifNameReadable\" (Alias: \"$ifAliasReadable\") globally");
                        $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedTrack} = "true";
                    }
                } else {
                    if ("${ifNameReadable}" =~ /$ExcludeString/i or "$ExcludeString" eq "ALL") {
                        logger(1, "-- exclude ($ExcludeString) interface \"$ifNameReadable\" globally");
                        $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedTrack} = "true";
                    }
                }
            } else {
                if ($ghOptions{'alias-matching'}) {
                    if ("${ifNameReadable}" eq "$ExcludeString" or "${ifAliasReadable}" eq "$ExcludeString" or "$ExcludeString" eq "ALL") {
                        logger(1, "-- exclude ($ExcludeString) interface \"$ifNameReadable\" (Alias: \"$ifAliasReadable\") globally");
                        $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedTrack} = "true";
                    }
                } else {
                    if ("${ifNameReadable}" eq "$ExcludeString" or "$ExcludeString" eq "ALL") {
                        logger(1, "-- exclude ($ExcludeString) interface \"$ifNameReadable\" globally");
                        $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedTrack} = "true";
                    }
                }
            }
        }

        # Process the interface inclusion list
        # Inclusions are done after exclusions to be able to include a
        # subset of a group of interfaces which were excluded previously
        for my $IncludeString (@$IncludeTrackList) {
            if ($ghOptions{regexp}) {
                if ($ghOptions{'alias-matching'}) {
                    if ("${ifNameReadable}" =~ /$IncludeString/i or "${ifAliasReadable}" =~ /$IncludeString/i or "$IncludeString" eq "ALL") {
                        logger(1, "++ include ($IncludeString) interface \"$ifNameReadable\" (Alias: \"$ifAliasReadable\") globally");
                        $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedTrack} = "false";
                    }
                } else {
                    if ("${ifNameReadable}" =~ /$IncludeString/i or "$IncludeString" eq "ALL") {
                        logger(1, "++ include ($IncludeString) interface \"$ifNameReadable\" globally");
                        $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedTrack} = "false";
                    }
                }
            } else {
                if ($ghOptions{'alias-matching'}) {
                    if ("${ifNameReadable}" eq "$IncludeString" or "${ifAliasReadable}" eq "$IncludeString" or "$IncludeString" eq "ALL") {
                        logger(1, "++ include ($IncludeString) interface \"$ifNameReadable\" (Alias: \"$ifAliasReadable\") globally");
                        $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedTrack} = "false";
                    }
                } else {
                    if ("${ifNameReadable}" eq "$IncludeString" or "$IncludeString" eq "ALL") {
                        logger(1, "++ include ($IncludeString) interface \"$ifNameReadable\" globally");
                        $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedTrack} = "false";
                    }
                }
            }
        }

        # Update the counter if needed
        if ($grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedTrack} eq "false") {
            $gNumberOfPerfdataInterfaces++;
        }

        #----- Includes or excludes interfaces from traffic load tracking -----#

        # For the interfaces included (for which the traffic load is tracked), enable property(ies)
        # tracking depending on the exclude and/or include property tracking port list
        if ($grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedTrack} eq "false") {

            # Process the interface exclusion list
            for my $ExcludeString (@$ExcludeLoadTrackList) {
                if ($ghOptions{regexp}) {
                    if ($ghOptions{'alias-matching'}) {
                        if ("${ifNameReadable}" =~ /$ExcludeString/i or "${ifAliasReadable}" =~ /$ExcludeString/i or "$ExcludeString" eq "ALL") {
                            logger(1, "-- exclude ($ExcludeString) interface \"$ifNameReadable\" (Alias: \"$ifAliasReadable\") from traffic load tracking");
                            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedLoadTrack} = "true";
                        }
                    } else {
                        if ("${ifNameReadable}" =~ /$ExcludeString/i or "$ExcludeString" eq "ALL") {
                            logger(1, "-- exclude ($ExcludeString) interface \"$ifNameReadable\" from traffic load tracking");
                            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedLoadTrack} = "true";
                        }
                    }
                } else {
                    if ($ghOptions{'alias-matching'}) {
                        if ("${ifNameReadable}" eq "$ExcludeString" or "${ifAliasReadable}" eq "$ExcludeString" or "$ExcludeString" eq "ALL") {
                            logger(1, "-- exclude ($ExcludeString) interface \"$ifNameReadable\" (Alias: \"$ifAliasReadable\") from traffic load tracking");
                            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedLoadTrack} = "true";
                        }
                    } else {
                        if ("${ifNameReadable}" eq "$ExcludeString" or "$ExcludeString" eq "ALL") {
                            logger(1, "-- exclude ($ExcludeString) interface \"$ifNameReadable\" from traffic load tracking");
                            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedLoadTrack} = "true";
                        }
                    }
                }
            }

            # Process the interface inclusion list
            # Inclusions are done after exclusions to be able to include a
            # subset of a group of interfaces which were excluded previously
            for my $IncludeString (@$IncludeLoadTrackList) {
                if ($ghOptions{regexp}) {
                    if ($ghOptions{'alias-matching'}) {
                        if ("${ifNameReadable}" =~ /$IncludeString/i or "${ifAliasReadable}" =~ /$IncludeString/i or "$IncludeString" eq "ALL") {
                            logger(1, "++ include ($IncludeString) interface \"$ifNameReadable\" (Alias: \"$ifAliasReadable\") from traffic load tracking");
                            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedLoadTrack} = "false";
                        }
                    } else {
                        if ("${ifNameReadable}" =~ /$IncludeString/i or "$IncludeString" eq "ALL") {
                            logger(1, "++ include ($IncludeString) interface \"$ifNameReadable\" from traffic load tracking");
                            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedLoadTrack} = "false";
                        }
                    }
                } else {
                    if ($ghOptions{'alias-matching'}) {
                        if ("${ifNameReadable}" eq "$IncludeString" or "${ifAliasReadable}" eq "$IncludeString" or "$IncludeString" eq "ALL") {
                            logger(1, "++ include ($IncludeString) interface \"$ifNameReadable\" (Alias: \"$ifAliasReadable\") from traffic load tracking");
                            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedLoadTrack} = "false";
                        }
                    } else {
                        if ("${ifNameReadable}" eq "$IncludeString" or "$IncludeString" eq "ALL") {
                            logger(1, "++ include ($IncludeString) interface \"$ifNameReadable\" from traffic load tracking");
                            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedLoadTrack} = "false";
                        }
                    }
                }
            }
        } else {
            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedLoadTrack} = "true";
        }

        #----- Includes or excludes interfaces from property change tracking -----#

        # For the interfaces included (for which the traffic load is tracked), enable property(ies)
        # tracking depending on the exclude and/or include property tracking port list
        if ($grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedTrack} eq "false") {

            # Process the interface exclusion list
            for my $ExcludeString (@$ExcludePropertyTrackList) {
                if ($ghOptions{regexp}) {
                    if ($ghOptions{'alias-matching'}) {
                        if ("${ifNameReadable}" =~ /$ExcludeString/i or "${ifAliasReadable}" =~ /$ExcludeString/i or "$ExcludeString" eq "ALL") {
                            logger(1, "-- exclude ($ExcludeString) interface \"$ifNameReadable\" (Alias: \"$ifAliasReadable\") from property change tracking");
                            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedPropertyTrack} = "true";
                        }
                    } else {
                        if ("${ifNameReadable}" =~ /$ExcludeString/i or "$ExcludeString" eq "ALL") {
                            logger(1, "-- exclude ($ExcludeString) interface \"$ifNameReadable\" from property change tracking");
                            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedPropertyTrack} = "true";
                        }
                    }
                } else {
                    if ($ghOptions{'alias-matching'}) {
                        if ("${ifNameReadable}" eq "$ExcludeString" or "${ifAliasReadable}" eq "$ExcludeString" or "$ExcludeString" eq "ALL") {
                            logger(1, "-- exclude ($ExcludeString) interface \"$ifNameReadable\" (Alias: \"$ifAliasReadable\") from property change tracking");
                            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedPropertyTrack} = "true";
                        }
                    } else {
                        if ("${ifNameReadable}" eq "$ExcludeString" or "$ExcludeString" eq "ALL") {
                            logger(1, "-- exclude ($ExcludeString) interface \"$ifNameReadable\" from property change tracking");
                            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedPropertyTrack} = "true";
                        }
                    }
                }
            }

            # Process the interface inclusion list
            # Inclusions are done after exclusions to be able to include a
            # subset of a group of interfaces which were excluded previously
            for my $IncludeString (@$IncludePropertyTrackList) {
                if ($ghOptions{regexp}) {
                    if ($ghOptions{'alias-matching'}) {
                        if ("${ifNameReadable}" =~ /$IncludeString/i or "${ifAliasReadable}" =~ /$IncludeString/i or "$IncludeString" eq "ALL") {
                            logger(1, "++ include ($IncludeString) interface \"$ifNameReadable\" (Alias: \"$ifAliasReadable\") from property change tracking");
                            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedPropertyTrack} = "false";
                        }
                    } else {
                        if ("${ifNameReadable}" =~ /$IncludeString/i or "$IncludeString" eq "ALL") {
                            logger(1, "++ include ($IncludeString) interface \"$ifNameReadable\" from property change tracking");
                            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedPropertyTrack} = "false";
                        }
                    }
                } else {
                    if ($ghOptions{'alias-matching'}) {
                        if ("${ifNameReadable}" eq "$IncludeString" or "${ifAliasReadable}" eq "$IncludeString" or "$IncludeString" eq "ALL") {
                            logger(1, "++ include ($IncludeString) interface \"$ifNameReadable\" (Alias: \"$ifAliasReadable\") from property change tracking");
                            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedPropertyTrack} = "false";
                        }
                    } else {
                        if ("${ifNameReadable}" eq "$IncludeString" or "$IncludeString" eq "ALL") {
                            logger(1, "++ include ($IncludeString) interface \"$ifNameReadable\" from property change tracking");
                            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedPropertyTrack} = "false";
                        }
                    }
                }
            }
        } else {
            $grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedPropertyTrack} = "true";
        }

    } # for each interface
    return $grefhCurrent;
}


# ------------------------------------------------------------------------
# get ifAdminStatus
# ------------------------------------------------------------------------
sub Get_AdminStatus {

    my $refaIfAdminStatusLines;       # Lines returned from snmpwalk storing ifAdminStatus

    # get all interface adminstatus - no caching !
    $refaIfAdminStatusLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_ifAdminStatus,$ghOptions{'cachedir'},0);
    if ($#$refaIfAdminStatusLines < 0 ) {
        logger(0, "Could not read ifAdminStatus table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_ifAdminStatus\n");
        exit $ERRORS{"UNKNOWN"};
    }
    my $refhIfAdminStatus = ();
    foreach (@$refaIfAdminStatusLines) {
        $refhIfAdminStatus->{"$1"}=$2 if /$oid_ifAdminStatus\.([0-9]*) (.*)$/;
    }

    # loop through all found interfaces
    for my $ifName (keys %{$grefhCurrent->{If}}) {

        # Extract the index out of the MetaData
        my $Index = $grefhCurrent->{MD}->{Map}->{NameToIndex}->{"$ifName"};
        logger(2, "Index=$Index ($ifName)");

        # Store ifAdminStatus converted from a digit to "up" or "down"
        $grefhCurrent->{If}->{"$ifName"}->{ifAdminStatus} =
            ConvertIfStatusToReadable ($refhIfAdminStatus->{"$Index"});
        logger(2, "  AdminStatus=".$grefhCurrent->{If}->{"$ifName"}->{ifAdminStatus});
    }
    return 0;
}

# ------------------------------------------------------------------------
# get ifOperStatus
# ------------------------------------------------------------------------
sub Get_OperStatus {

    my $refaOperStatusLines;       # Lines returned from snmpwalk storing ifOperStatus

    # get all interface operstatus - no caching !
    $refaOperStatusLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_ifOperStatus,$ghOptions{'cachedir'},0);
    if ($#$refaOperStatusLines < 0 ) {
        logger(0, "Could not read ifOperStatus information from host \"$ghOptions{'hostquery'}\" with snmp.\nCheck the access to the oid $oid_ifOperStatus\n");
        exit $ERRORS{"UNKNOWN"};
    }

    # Example of $refaOperStatusLines
    #    .1.3.6.1.2.1.2.2.1.8.1 up
    #    .1.3.6.1.2.1.2.2.1.8.2 down
    for (@$refaOperStatusLines) {
        my ($Index,$OperStatusNow) = split / /,$_,2;
        $Index =~ s/^.*\.//g;           # remove all but the index
        $OperStatusNow =~ s/\s+$//g;    # remove invisible chars from the end
        $OperStatusNow = ConvertIfStatusToReadable("$OperStatusNow");
        my $ifName = $grefhCurrent->{MD}->{Map}->{IndexToName}->{"$Index"};

        logger(2, "Index=$Index ($ifName)");

        # Store the oper status as property of the current interface
        $grefhCurrent->{If}->{"$ifName"}->{ifOperStatus} = "$OperStatusNow";

        # Retrieve adminstatus for special rules
        my $AdminStatusNow = $grefhCurrent->{If}->{"$ifName"}->{ifAdminStatus};

        #
        # Store a CacheTimer (seconds) where we cache the next
        # reads from the net - we have the following possibilities
        #
        # ifOperStatus:
        #
        # Current state | first state  |  CacheTimer
        # -----------------------------------------
        # up              up              $gShortCacheTimer
        # up              down            0
        # down            down            $gLongCacheTimer
        # down            up              0
        # other           *               0
        # *               other           0
        #
        # One exception to that logic is the "Changed" flag. If this
        # is set we detected a change on an interface property and do not
        # cache !
        #
        my $OperStatusFile = $grefhFile->{If}->{"$ifName"}->{ifOperStatus};
        unless ($OperStatusFile) {$OperStatusFile = "";}
        logger(2, "  Now=\"$OperStatusNow\" File=\"$OperStatusFile\"");
        # set cache timer for further reads
        if ("$OperStatusNow" eq "up" and "$OperStatusFile" eq "up") {
            $grefhCurrent->{MD}->{If}->{"$ifName"}->{CacheTimer} = $gShortCacheTimer;
        } elsif ("$OperStatusNow" eq "down" and "$OperStatusFile" eq "down") {
            $grefhCurrent->{MD}->{If}->{"$ifName"}->{CacheTimer} = $gLongCacheTimer;
        } else {
            $grefhCurrent->{MD}->{If}->{"$ifName"}->{CacheTimer} = 0;
            $grefhCurrent->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeText} =
                "Old = \"$OperStatusFile\", Current = \"$OperStatusNow\" ";
        }
        logger(2, "  CacheTimer=".$grefhCurrent->{MD}->{If}->{"$ifName"}->{CacheTimer});

        # remember change time of the interface property
        if ($grefhFile->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeTime}) {
            $grefhCurrent->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeTime} =
                $grefhFile->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeTime}
        } else {
            $grefhCurrent->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeTime} = time;
        }

        #
        # Some rules with ifOperStatus
        #
        # Between initial ifOperStatus and current ifOperStatus
        # current ifOperStatus | initial ifOperStatus | action
        # ---------------------------------------------------------------------
        # up                   | *                    | no alarm and update ifOperStatus initial state
        # *                    | empty,down           | no alarm and update ifOperStatus initial state
        #
        # Between current ifOperStatus and current ifAdminStatus
        # current ifOperStatus | current ifAdminStatus | action
        # ---------------------------------------------------------------------
        # down                 | *                     | no alarm and update ifOperStatus initial state
        #

        # track changes of the oper status
        if ("$OperStatusNow" eq "$OperStatusFile") {   # no changes to its first state
            # delete the changed flag and reset the time when it was changed
            if ($grefhFile->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeText}) {
                delete $grefhCurrent->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeText};
                $grefhCurrent->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeTime} = time;
            }
        }
        # ifOperstatus has changed to up, no alert
        elsif ("$OperStatusNow" eq "up") {
            # update the state in the status file
            $grefhFile->{If}->{"$ifName"}->{ifOperStatus} = "$OperStatusNow";
            # delete the changed flag and reset the time when it was changed
            if ($grefhFile->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeText}) {
                delete $grefhCurrent->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeText};
                $grefhCurrent->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeTime} = time;
            }
        }
        # ifOperstatus has changed from 'empty' or 'down'
        elsif ("$OperStatusFile" eq "" or "$OperStatusFile" eq "down") {
            # update the state in the status file
            $grefhFile->{If}->{"$ifName"}->{ifOperStatus} = "$OperStatusNow";
            # delete the changed flag and reset the time when it was changed
            if ($grefhFile->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeText}) {
                delete $grefhCurrent->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeText};
                $grefhCurrent->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeTime} = time;
            }
        }
        # ifOperstatus has changed to 'down' and ifAdminstatus is 'down'
        elsif ("$OperStatusNow" eq "down" and "$AdminStatusNow" eq "down") {
            # update the state in the status file
            $grefhFile->{If}->{"$ifName"}->{ifOperStatus} = "$OperStatusNow";
            # delete the changed flag and reset the time when it was changed
            if ($grefhFile->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeText}) {
                delete $grefhCurrent->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeText};
                $grefhCurrent->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeTime} = time;
            }
        }
        # ifOperstatus has changed, alerting
        else {
            # flag if changes already tracked
            if (not $grefhFile->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeText}) {
                $grefhCurrent->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeTime} = time;
            }

            # remember the change every run of this program, this is useful if the
            # ifOperStatus changes from "up" to "testing" to "down"
            $grefhCurrent->{MD}->{If}->{"$ifName"}->{ifOperStatusChangeText} =
                "Old = \"$OperStatusFile\", Current = \"$OperStatusNow\" ";
        }

    }
    return 0;
}

# ------------------------------------------------------------------------
# get trafic in octets (ifInOctets / ifOutOctets)
# ------------------------------------------------------------------------
sub Get_TrafficInOut {

    my $refaOctetLines = shift;
    my $WhatOctet = shift;
    my $WhatBit = shift;

    # Example of $refaOctetLines
    #    .1.3.6.1.2.1.2.2.1.10.2 2510821601
    #    .1.3.6.1.2.1.2.2.1.10.3 0
    for (@$refaOctetLines) {
        my ($Index,$Octets) = split / /,$_,2;
        $Index =~ s/^.*\.//g;    # remove all but the index
        $Octets =~ s/\s+$//g;    # remove invisible chars from the end
        my $Bits = $Octets * 8;  # convert in bits
        logger(2, "Index=$Index\tOctets=$Octets");

        # Store the octets of the current interface
        if (defined $grefhCurrent->{MD}->{Map}->{IndexToName}->{"$Index"}) {
            my $ifName = $grefhCurrent->{MD}->{Map}->{IndexToName}->{"$Index"};
            $grefhCurrent->{MD}->{IfCounters}->{"$ifName"}->{"$WhatOctet"} = "$Octets";
            $grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{"$WhatOctet"} = "$Octets";
            # Store the bits of the current interface
            $grefhCurrent->{MD}->{IfCounters}->{"$ifName"}->{"$WhatBit"} = "$Bits";
        } else {
            logger(3, "Cannot map the traffic statistic to any existing interface: no corresponding interface index. Skipping...");
        }
    }
    return 0;
}

# ------------------------------------------------------------------------
# get trafic in bits (ifInOctets / ifOutOctets)
# ------------------------------------------------------------------------
sub Get_IfErrInOut {

    my $refaIfErrLines = shift;
    my $What = shift;

    # Example of $refaIfErrLines
    #    .1.3.6.1.2.1.2.2.1.14.1 201
    #    .1.3.6.1.2.1.2.2.1.14.2 0
    for (@$refaIfErrLines) {
        my ($Index,$IfErr) = split / /,$_,2;
        $Index =~ s/^.*\.//g;    # remove all but the index
        $IfErr =~ s/\s+$//g;    # remove invisible chars from the end
        logger(2, "Index=$Index\tErr=$IfErr");

        # Store the Errors of the current interface
        if (defined $grefhCurrent->{MD}->{Map}->{IndexToName}->{"$Index"}) {
            my $ifName = $grefhCurrent->{MD}->{Map}->{IndexToName}->{"$Index"};
            $grefhCurrent->{MD}->{IfCounters}->{"$ifName"}->{"$What"} = "$IfErr";
            $grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{"$What"} = "$IfErr";
        } else {
            logger(3, "Cannot map the packet errors statistic to any existing interface: no corresponding interface index. Skipping...");
        }
    }
    return 0;
}

# ------------------------------------------------------------------------
# get packet discards (ifInDiscards/ifOutDiscards)
# ------------------------------------------------------------------------
sub Get_IfDiscardInOut {

    my $refaIfDiscardLines = shift;
    my $What = shift;

    # Example of $refaIfDiscardLines
    #    .1.3.6.1.2.1.2.2.1.13.1 201
    #    .1.3.6.1.2.1.2.2.1.13.2 0
    for (@$refaIfDiscardLines) {
        my ($Index,$IfDiscard) = split / /,$_,2;
        $Index =~ s/^.*\.//g;    # remove all but the index
        $IfDiscard =~ s/\s+$//g;    # remove invisible chars from the end
        logger(2, "Index=$Index\tDiscard=$IfDiscard");

        # Store the Discards of the current interface
        if (defined $grefhCurrent->{MD}->{Map}->{IndexToName}->{"$Index"}) {
            my $ifName = $grefhCurrent->{MD}->{Map}->{IndexToName}->{"$Index"};
            $grefhCurrent->{MD}->{IfCounters}->{"$ifName"}->{"$What"} = "$IfDiscard";
            $grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{"$What"} = "$IfDiscard";
        } else {
            logger(3, "Cannot map the packet discards statistic to any existing interface: no corresponding interface index. Skipping...");
        }
    }
    return 0;
}

# ------------------------------------------------------------------------
# clean outdated historical data statistics and select the one eligible
# for bandwitdh calculation
# ------------------------------------------------------------------------
sub CleanAndSelectHistoricalDataset {

    #logger(5, "perfdata dirty:\n".Dumper($grefhFile));

    my $firsttime = $STARTTIME;

    # loop through all historical perfdata
    logger(1, "Clean/select historical datasets");
    for my $time (sort keys %{$grefhFile->{History}}) {
        if (($STARTTIME - ($ghOptions{'delta'} + $ghOptions{'delta'} / 3)) > $time) {
            # delete anything older than starttime - (delta + a bit buffer)
            # so we keep a sliding window following us
            delete $grefhFile->{History}->{$time};
            logger(1, " outdated perfdata cleanup: $time");
        } elsif ($time < $firsttime) {
            # chose the oldest dataset to compare with
            $firsttime = $time;
            $gUsedDelta = $STARTTIME - $firsttime;
            logger(1, " now ($STARTTIME) - comparetimestamp ($time) = used delta ($gUsedDelta)");
            last;
        } else {
            # no dataset (left) to compare with
            # no further calculations if we run for the first time.
            $firsttime = undef;
            logger(1, " no dataset (left) to compare with, bandwitdh calculations will not be done");
        }
    }
    return $firsttime;
}

# ------------------------------------------------------------------------
# calculate rate / bandwidth usage within a specified period
# ------------------------------------------------------------------------
sub CalculateBps {
    my $firsttime = shift;
    # check if the counter is back to 0 after 2^32 / 2^64.
    # First set the modulus depending on highperf counters or not
    my $overfl_mod = ($ghSNMPOptions{'64bits'}) ? 18446744073709551616 : 4294967296;

    # $grefaAllIndizes is a indexed and sorted list of all interfaces
    logger(2, "x"x50);
    logger(2, "Load calculations");
    for my $Index (@$grefaAllIndizes) {

        # Get normalized interface name (key for If data structure)
        my $ifName = $grefhCurrent->{MD}->{Map}->{IndexToName}->{$Index};
        logger(2, " ifName: $ifName (index: $Index)");

        # Skip interface if excluded
        if ($grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedTrack} eq "true") {
            logger(2, "  -> excluded interface, skipping");
            next;
        }

        # Skip interface if no load stats
        if (not defined $grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{OctetsIn}
            or not defined $grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{OctetsOut}) {
            logger(2, "  -> not load statistics, skipping");
            next;
        }

        # ---------- Bandwidth calculation -----------

        my $overfl      = 0;
        my $bpsIn       = 0;
        my $bpsOut      = 0;

        # be sure that history exist
        # then check if the counter is back to 0 after 2^32 / 2^64.
        if (defined $grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{OctetsIn}
            and defined $grefhFile->{History}->{$firsttime}->{IfCounters}->{"$ifName"}->{OctetsIn}){
                $overfl = ($grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{OctetsIn} >=
                    $grefhFile->{History}->{$firsttime}->{IfCounters}->{"$ifName"}->{OctetsIn} ) ? 0 : $overfl_mod;
                $bpsIn = ($grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{OctetsIn} -
                    $grefhFile->{History}->{$firsttime}->{IfCounters}->{"$ifName"}->{OctetsIn} + $overfl) / $gUsedDelta * 8;
        }

        # be sure that history exist
        # then check if the counter is back to 0 after 2^32 / 2^64.
        if (defined $grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{OctetsOut}
            and defined $grefhFile->{History}->{$firsttime}->{IfCounters}->{"$ifName"}->{OctetsOut}){
                $overfl = ($grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{OctetsOut} >=
                    $grefhFile->{History}->{$firsttime}->{IfCounters}->{"$ifName"}->{OctetsOut} ) ? 0 : $overfl_mod;
                $bpsOut = ($grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{OctetsOut} -
                    $grefhFile->{History}->{$firsttime}->{IfCounters}->{"$ifName"}->{OctetsOut} + $overfl) / $gUsedDelta * 8;
        }

        # bandwidth usage in percent of (configured/negotiated) interface speed
        $grefhCurrent->{If}->{$ifName}->{ifLoadExceedIfSpeed} = "false";
        if ($grefhCurrent->{If}->{$ifName}->{ifSpeed} > 0) {
            my $ifLoadIn  = 100 * $bpsIn  / $grefhCurrent->{If}->{$ifName}->{ifSpeed};
            my $ifLoadOut = 100 * $bpsOut / $grefhCurrent->{If}->{$ifName}->{ifSpeed};
            $grefhCurrent->{If}->{$ifName}->{ifLoadIn}  = sprintf("%.2f", $ifLoadIn);
            $grefhCurrent->{If}->{$ifName}->{ifLoadOut} = sprintf("%.2f", $ifLoadOut);

            # Check abnormal load compared to interface speed
            if ($grefhCurrent->{If}->{$ifName}->{ifLoadIn} > 115 or $grefhCurrent->{If}->{$ifName}->{ifLoadOut} > 115) {
                logger(2, "  -> load exceeds 115% of the interface speed, related alerts and perfdata disabled");
                $grefhCurrent->{If}->{$ifName}->{ifLoadExceedIfSpeed} = "true";
            }

            # check interface utilization in percent

            if ($grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedLoadTrack} eq "false") {
                if ($ifLoadIn > 0 or $ifLoadOut > 0) {
                    if ($grefhCurrent->{If}->{$ifName}->{ifLoadExceedIfSpeed} eq "false") {
                        # just traffic light color codes for the lame
                        if ($ifLoadIn > $ghOptions{'critical-load'} or $ifLoadOut > $ghOptions{'critical-load'}) {
                            if ( defined $grefhCurrent->{If}->{$ifName}->{"ifAlias"} and $grefhCurrent->{If}->{$ifName}->{"ifAlias"} ne "" ) {
                                push @{$grefhListOfChanges->{loadcritical}}, trim(denormalize($ifName))." (".trim(denormalize($grefhCurrent->{If}->{$ifName}->{"ifAlias"})).")";
                            } else {
                                push @{$grefhListOfChanges->{loadcritical}}, trim(denormalize($ifName));
                            }
                            $gIfLoadCritCounter++;
                        } elsif ($ifLoadIn > $ghOptions{'warning-load'} or $ifLoadOut > $ghOptions{'warning-load'}) {
                            if ( defined $grefhCurrent->{If}->{$ifName}->{"ifAlias"} and $grefhCurrent->{If}->{$ifName}->{"ifAlias"} ne "" ) {
                                push @{$grefhListOfChanges->{loadwarning}}, trim(denormalize($ifName))." (".trim(denormalize($grefhCurrent->{If}->{$ifName}->{"ifAlias"})).")";
                            } else {
                                push @{$grefhListOfChanges->{loadwarning}}, trim(denormalize($ifName));
                            }
                            $gIfLoadWarnCounter++;
                        }
                    } else {
                        logger(2, "  -> interface load exceeds interface speed, load will be ignored");
                    }
                    $grefhCurrent->{If}->{$ifName}->{ifLoadInOutOfRange} = colorcode($ifLoadIn, $ghOptions{'warning-load'}, $ghOptions{'critical-load'});
                    $grefhCurrent->{If}->{$ifName}->{ifLoadOutOutOfRange} = colorcode($ifLoadOut, $ghOptions{'warning-load'}, $ghOptions{'critical-load'});
                }
            }
        } else {
            $grefhCurrent->{If}->{$ifName}->{ifLoadIn} = 0;
            $grefhCurrent->{If}->{$ifName}->{ifLoadOut} = 0;
        }
        logger(2, "  -> speed=".$grefhCurrent->{If}->{$ifName}->{ifSpeed}.", ".
            "loadin=".$grefhCurrent->{If}->{$ifName}->{ifLoadIn}.", ".
            "loadout=".$grefhCurrent->{If}->{$ifName}->{ifLoadOut});

        #print OUT "BandwidthUsageIn=${bpsIn}bps;0;0;0;$grefhCurrent->{If}->{$ifName}->{ifSpeed} ";
        #print OUT "BandwidthUsageOut=${bpsOut}bps;0;0;0;$grefhCurrent->{If}->{$ifName}->{ifSpeed} ";

        my $SpeedUnitOut='';
        my $SpeedUnitIn='';
        if ($ghOptions{human}) {
            # human readable bandwidth usage in (G/M/K)bits per second
            $SpeedUnitIn=' bps';
            if ($bpsIn > 1000000000) {        # in Gbit/s = 1000000000 bit/s
                  $bpsIn = $bpsIn / 1000000000;
                  $SpeedUnitIn=' Gbps';
            } elsif ($bpsIn > 1000000) {      # in Mbit/s = 1000000 bit/s
                  $bpsIn = $bpsIn / 1000000;
                  $SpeedUnitIn=' Mbps';
            } elsif ($bpsIn > 1000) {         # in Kbits = 1000 bit/s
                  $bpsIn = $bpsIn / 1000;
                  $SpeedUnitIn=' Kbps';
            }

            $SpeedUnitOut=' bps';
            if ($bpsOut > 1000000000) {       # in Gbit/s = 1000000000 bit/s
                  $bpsOut = $bpsOut / 1000000000;
                  $SpeedUnitOut=' Gbps';
            } elsif ($bpsOut > 1000000) {     # in Mbit/s = 1000000 bit/s
                  $bpsOut = $bpsOut / 1000000;
                  $SpeedUnitOut=' Mbps';
            } elsif ($bpsOut > 1000) {        # in Kbit/s = 1000 bit/s
                  $bpsOut = $bpsOut / 1000;
                  $SpeedUnitOut=' Kbps';
            }
        }

        $grefhCurrent->{If}->{$ifName}->{bpsIn} = sprintf("%.2f$SpeedUnitIn", $bpsIn);
        $grefhCurrent->{If}->{$ifName}->{bpsOut} = sprintf("%.2f$SpeedUnitOut", $bpsOut);

        # ---------- Last traffic calculation -----------

        # remember last traffic time
        if ($bpsIn > 0 or $bpsOut > 0) { # there is traffic now, remember it
            $grefhCurrent->{MD}->{If}->{$ifName}->{LastTraffic} = $STARTTIME;
            #logger(1, "setze neuen wert!!! LastTraffic: ", $STARTTIME);
        } elsif (not defined $grefhFile->{MD}->{If}->{$ifName}->{LastTraffic}) {
            #if ($gInitialRun) {
            #    # initialize on the first run
            #    $grefhCurrent->{MD}->{If}->{$ifName}->{LastTraffic} = $STARTTIME;
            #} else {
                $grefhCurrent->{MD}->{If}->{$ifName}->{LastTraffic} = 0;
            #}
            #logger(1, "grefhCurrent->{MD}->{If}->{$ifName}->{LastTraffic}: not defined");
        } else { # no traffic now, dont forget the old value
            $grefhCurrent->{MD}->{If}->{$ifName}->{LastTraffic} = $grefhFile->{MD}->{If}->{$ifName}->{LastTraffic};
            #$grefhCurrent->{MD}->{If}->{$ifName}->{LastTraffic} = $STARTTIME;
            #logger(1, "merke alten wert!!! LastTraffic: ", $grefhFile->{MD}->{If}->{$ifName}->{LastTraffic});
        }
        # Set LastTrafficInfo to this Format "0d 0h 43m" and compare the critical and warning levels for "unused interface"
        ($grefhCurrent->{If}->{$ifName}->{ifLastTraffic}, my $LastTrafficStatus) =
            TimeDiff ($grefhCurrent->{MD}->{If}->{$ifName}->{LastTraffic}, $STARTTIME,
                $ghOptions{lasttrafficwarn}, $ghOptions{lasttrafficcrit});

        # ---------- Last traffic calculation -----------

        # ifUsage variable:
        #   * -1  -> interface used, unknown last traffic
        #   * 0   -> interface used, last traffic is < crit duration
        #   * 1   -> interface unused, last traffic is >= crit duration

        logger(2, "Last traffic calculation");
        if ($LastTrafficStatus == $ERRORS{'CRITICAL'}) {
            logger(2, "  -> interface unused, last traffic is >= crit duration");
            # this means "no traffic seen during the last LastTrafficCrit seconds"
            $grefhCurrent->{If}->{$ifName}->{ifLastTrafficOutOfRange} = "red";
            $grefhCurrent->{If}->{$ifName}->{ifUsage} = 1; # interface unused
        } elsif ($LastTrafficStatus == $ERRORS{'WARNING'}) {
            logger(2, "  -> interface used, last traffic is < crit duration");
            # this means "no traffic seen during the last LastTrafficWarn seconds"
            $grefhCurrent->{If}->{$ifName}->{ifLastTrafficOutOfRange} = "yellow";
            $grefhCurrent->{If}->{$ifName}->{ifUsage} = 0; # interface used
        } elsif ($LastTrafficStatus == $ERRORS{'UNKNOWN'}) {
            logger(2, "  -> interface used, unknown last traffic");
            # this means "no traffic seen during the last LastTrafficWarn seconds"
            $grefhCurrent->{If}->{$ifName}->{ifLastTrafficOutOfRange} = "orange";
            $grefhCurrent->{If}->{$ifName}->{ifUsage} = -1; # interface unused
        } else {
            logger(2, "  -> interface used, last traffic is < crit duration");
            # this means "there is traffic on the interface during the last LastTrafficWarn seconds"
            $grefhCurrent->{If}->{$ifName}->{ifUsage} = 0; # interface used
        }
        check_for_unused_interfaces ($ifName, $grefhCurrent->{If}->{$ifName}->{ifUsage});

    }
    logger(2, "x"x50);
    #logger(5, "grefhCurrent: " . Dumper ($grefhCurrent));
    #logger(5, "grefhFile: " . Dumper ($grefhFile));
    #logger(5, "grefhCurrent: " . Dumper ($grefhCurrent->{If}));
    #logger(5, "grefhFile: " . Dumper ($grefhFile->{If}));

    return 0;
}

# ------------------------------------------------------------------------
# evaluate packets within a specified period
# ------------------------------------------------------------------------
sub EvaluatePackets {
    my $firsttime = shift;
    # check if the counter is back to 0 after 2^32 / 2^64.
    # First set the modulus depending on highperf counters or not
    #my $overfl_mod = defined ($o_highperf) ? 18446744073709551616 : 4294967296;
    my $overfl_mod = 4294967296;

    # $grefaAllIndizes is a indexed and sorted list of all interfaces
    for my $Index (@$grefaAllIndizes) {

        # Get normalized interface name (key for If data structure)
        my $ifName = $grefhCurrent->{MD}->{Map}->{IndexToName}->{$Index};
        if ($grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedTrack} eq "true") {
            next;
        }

        my $overfl              = 0;
        my $ppsErrIn            = 0;
        my $ppsErrOut           = 0;
        my $ppsDiscardIn        = 0;
        my $ppsDiscardOut       = 0;

        # be sure that history exist
        # then check if the counter is back to 0 after 2^32 / 2^64.
        if (defined $grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{PktsInErr}
            and defined $grefhFile->{History}->{$firsttime}->{IfCounters}->{"$ifName"}->{PktsInErr}){
                $overfl = ($grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{PktsInErr} >=
                    $grefhFile->{History}->{$firsttime}->{IfCounters}->{"$ifName"}->{PktsInErr} ) ? 0 : $overfl_mod;
                $ppsErrIn = ($grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{PktsInErr} -
                    $grefhFile->{History}->{$firsttime}->{IfCounters}->{"$ifName"}->{PktsInErr} + $overfl) / $gUsedDelta;
        }
        if (defined $grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{PktsOutErr}
            and defined $grefhFile->{History}->{$firsttime}->{IfCounters}->{"$ifName"}->{PktsOutErr}){
                $overfl = ($grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{PktsOutErr} >=
                    $grefhFile->{History}->{$firsttime}->{IfCounters}->{"$ifName"}->{PktsOutErr} ) ? 0 : $overfl_mod;
                $ppsErrOut = ($grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{PktsOutErr} -
                    $grefhFile->{History}->{$firsttime}->{IfCounters}->{"$ifName"}->{PktsOutErr} + $overfl) / $gUsedDelta;
        }
        if (defined $grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{PktsInDiscard}
            and defined $grefhFile->{History}->{$firsttime}->{IfCounters}->{"$ifName"}->{PktsInDiscard}){
                $overfl = ($grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{PktsInDiscard} >=
                    $grefhFile->{History}->{$firsttime}->{IfCounters}->{"$ifName"}->{PktsInDiscard} ) ? 0 : $overfl_mod;
                $ppsDiscardIn = ($grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{PktsInDiscard} -
                    $grefhFile->{History}->{$firsttime}->{IfCounters}->{"$ifName"}->{PktsInDiscard} + $overfl) / $gUsedDelta;
        }
        if (defined $grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{PktsOutDiscard}
            and defined $grefhFile->{History}->{$firsttime}->{IfCounters}->{"$ifName"}->{PktsOutDiscard}){
                $overfl = ($grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{PktsOutDiscard} >=
                    $grefhFile->{History}->{$firsttime}->{IfCounters}->{"$ifName"}->{PktsOutDiscard} ) ? 0 : $overfl_mod;
                $ppsDiscardOut = ($grefhFile->{History}->{$STARTTIME}->{IfCounters}->{"$ifName"}->{PktsOutDiscard} -
                    $grefhFile->{History}->{$firsttime}->{IfCounters}->{"$ifName"}->{PktsOutDiscard} + $overfl) / $gUsedDelta;
        }

        # compare against thresholds
        my $pwarn = 0;
        my $pcrit = 0;
        $grefhCurrent->{If}->{$ifName}->{ppsErrIn}  = sprintf("%.2f", $ppsErrIn);
        $grefhCurrent->{If}->{$ifName}->{ppsErrOut} = sprintf("%.2f", $ppsErrOut);
        if ($grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedLoadTrack} eq "false" and ($ppsErrIn > 0 or $ppsErrOut > 0)) {
            # just traffic light color codes for the lame
            if ($ghOptions{'critical-pkterr'} >= 0 and ($ppsErrIn > $ghOptions{'critical-pkterr'} or $ppsErrOut > $ghOptions{'critical-pkterr'})) {
                if ( defined $grefhCurrent->{If}->{$ifName}->{"ifAlias"} and $grefhCurrent->{If}->{$ifName}->{"ifAlias"} ne "" ) {
                    push @{$grefhListOfChanges->{'critical-pkterr'}}, trim(denormalize($ifName))." (".trim(denormalize($grefhCurrent->{If}->{$ifName}->{"ifAlias"})).")";
                } else {
                    push @{$grefhListOfChanges->{'critical-pkterr'}}, trim(denormalize($ifName));
                }
                $gPktErrCritCounter++;
                $pcrit++;
            } elsif ($ghOptions{'warning-pkterr'} >= 0 and ($ppsErrIn > $ghOptions{'warning-pkterr'} or $ppsErrOut > $ghOptions{'warning-pkterr'})) {
                if ( defined $grefhCurrent->{If}->{$ifName}->{"ifAlias"} and $grefhCurrent->{If}->{$ifName}->{"ifAlias"} ne "" ) {
                    push @{$grefhListOfChanges->{'warning-pkterr'}}, trim(denormalize($ifName))." (".trim(denormalize($grefhCurrent->{If}->{$ifName}->{"ifAlias"})).")";
                } else {
                    push @{$grefhListOfChanges->{'warning-pkterr'}}, trim(denormalize($ifName));
                }
                $gPktErrWarnCounter++;
                $pwarn++;
            }
            $grefhCurrent->{If}->{$ifName}->{ppsErrInOutOfRange} = colorcode($ppsErrIn, $ghOptions{'warning-pkterr'}, $ghOptions{'critical-pkterr'});
            $grefhCurrent->{If}->{$ifName}->{ppsErrOutOutOfRange} = colorcode($ppsErrOut, $ghOptions{'warning-pkterr'}, $ghOptions{'critical-pkterr'});
        }
        $grefhCurrent->{If}->{$ifName}->{ppsDiscardIn}  = sprintf("%.2f", $ppsDiscardIn);
        $grefhCurrent->{If}->{$ifName}->{ppsDiscardOut} = sprintf("%.2f", $ppsDiscardOut);
        if ($grefhCurrent->{MD}->{If}->{$ifName}->{ExcludedLoadTrack} eq "false" and ($ppsDiscardIn > 0 or $ppsDiscardOut > 0)) {
            # just traffic light color codes for the lame
            if ($ghOptions{'critical-pktdiscard'} >= 0 and ($ppsDiscardIn > $ghOptions{'critical-pktdiscard'} or $ppsDiscardOut > $ghOptions{'critical-pktdiscard'})) {
                if ( defined $grefhCurrent->{If}->{$ifName}->{"ifAlias"} and $grefhCurrent->{If}->{$ifName}->{"ifAlias"} ne "" ) {
                    push @{$grefhListOfChanges->{'critical-pktdiscard'}}, trim(denormalize($ifName))." (".trim(denormalize($grefhCurrent->{If}->{$ifName}->{"ifAlias"})).")";
                } else {
                    push @{$grefhListOfChanges->{'critical-pktdiscard'}}, trim(denormalize($ifName));
                }
                $gPktDiscardCritCounter++;
                $pcrit++;
            } elsif ($ghOptions{'warning-pktdiscard'} >= 0 and ($ppsDiscardIn > $ghOptions{'warning-pktdiscard'} or $ppsDiscardOut > $ghOptions{'warning-pktdiscard'})) {
                if ( defined $grefhCurrent->{If}->{$ifName}->{"ifAlias"} and $grefhCurrent->{If}->{$ifName}->{"ifAlias"} ne "" ) {
                    push @{$grefhListOfChanges->{'warning-pktdiscard'}}, trim(denormalize($ifName))." (".trim(denormalize($grefhCurrent->{If}->{$ifName}->{"ifAlias"})).")";
                } else {
                    push @{$grefhListOfChanges->{'warning-pktdiscard'}}, trim(denormalize($ifName));
                }
                $gPktDiscardWarnCounter++;
                $pwarn++;
            }
            $grefhCurrent->{If}->{$ifName}->{ppsDiscardInOutOfRange} = colorcode($ppsDiscardIn, $ghOptions{'warning-pktdiscard'}, $ghOptions{'critical-pktdiscard'});
            $grefhCurrent->{If}->{$ifName}->{ppsDiscardOutOutOfRange} = colorcode($ppsDiscardOut, $ghOptions{'warning-pktdiscard'}, $ghOptions{'critical-pktdiscard'});
        }
        # totals field
        $grefhCurrent->{If}->{$ifName}->{pktErrDiscard} = sprintf("%.1f/%.1f/%.1f/%.1f", $ppsErrIn, $ppsErrOut, $ppsDiscardIn, $ppsDiscardOut);
        if ($pcrit > 0) {
            $grefhCurrent->{If}->{$ifName}->{pktErrDiscardOutOfRange} = 'red';
        } elsif ($pwarn > 0) {
            $grefhCurrent->{If}->{$ifName}->{pktErrDiscardOutOfRange} = 'yellow';
        }
    }

    return 0;
}


# ------------------------------------------------------------------------
# walk through each interface and read ifAdminStatus, ifSpeed and ifAlias,
# ifVlan, ifDuplexStatus
# ------------------------------------------------------------------------
sub Get_Speed_Duplex_Alias_Vlan {

    # get ifDuplexStatus table
    my $refhIfDuplexStatus = ();
    if ($ghOptions{'duplex'}) {
        my $refaIfDuplexStatus = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_ifDuplexStatus,$ghOptions{'cachedir'},0);
        if ($#$refaIfDuplexStatus < 0 ) {
            logger(0, "Could not read ifDuplexStatus table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_ifDuplexStatus\n");
            exit $ERRORS{"UNKNOWN"};
        }
        foreach (@$refaIfDuplexStatus) {
            $refhIfDuplexStatus->{"$1"}=$2 if /$oid_ifDuplexStatus\.([0-9]*) (.*)$/;
        }
    }

    # get ifAlias table - returned result can be empty
    my $refaIfAlias = ($ghOptions{'alias-matching'}) ? GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_ifAlias,$ghOptions{'cachedir'},0)
        : GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_ifAlias,$ghOptions{'cachedir'},$gLongCacheTimer);
    my $refhIfAlias = ();
    foreach (@$refaIfAlias) {
        $refhIfAlias->{"$1"}=$2 if /$oid_ifAlias\.([0-9]*) (.*)$/;
    }

    # get ifSpeed table
    my $refaIfSpeed = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_ifSpeed,$ghOptions{'cachedir'},0);
    if ($#$refaIfSpeed < 0 ) {
        logger(0, "Could not read ifSpeed table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_ifSpeed\n");
        exit $ERRORS{"UNKNOWN"};
    }
    my $refhIfSpeed = ();
    foreach (@$refaIfSpeed) {
        $refhIfSpeed->{"$1"}=$2 if /$oid_ifSpeed\.([0-9]*) ([0-9]*)/;
    }

    my $refhIfSpeed64 = ();
    if ($ghSNMPOptions{'64bits'}) {
        # get ifSpeed64 table
        my $refaIfSpeed64 = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_ifSpeed_64,$ghOptions{'cachedir'},0);
        if ($#$refaIfSpeed64 < 0 ) {
            logger(0, "Could not read ifSpeed64 table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_ifSpeed_64\n");
            exit $ERRORS{"UNKNOWN"};
        }
        $refhIfSpeed64 = ();
        foreach (@$refaIfSpeed64) {
            $refhIfSpeed64->{"$1"}=$2 if /$oid_ifSpeed_64\.([0-9]*) ([0-9]*)/;
        }
    }

    # loop through all found interfaces
    for my $ifName (keys %{$grefhCurrent->{If}}) {

        # Extract the index out of the MetaData
        my $Index           = $grefhCurrent->{MD}->{Map}->{NameToIndex}->{"$ifName"};
        logger(2, "Index=$Index ($ifName)");

        # Get the speed in normal or highperf speed counters
        if (not defined $refhIfSpeed->{"$Index"} or $refhIfSpeed->{"$Index"} eq ""){
            $refhIfSpeed->{"$Index"} = -1;
        }
        if ($refhIfSpeed->{"$Index"} >= 4294967294) { # Too high for this counter (cf IF-MIB)
            if ($ghSNMPOptions{'64bits'} && $refhIfSpeed64->{"$Index"} != 0) {
                $refhIfSpeed->{"$Index"} = $refhIfSpeed64->{"$Index"} * 1000000;
            } elsif (! $ghSNMPOptions{'64bits'}) {
                logger(1, " --->>> WARNING");
                logger(1, " $ifName($Index) -> interface speed exceeding standard counters (oid_ifSpeed.$Index: ".$refhIfSpeed->{"$Index"}.")");
                logger(1, " $ifName($Index) -> not using highperf mib (--64bits): interface load calculation could be wrong for interface $ifName($Index) !!!");
            }
        }

        # Store ifSpeed in a machine and human readable format
        $grefhCurrent->{If}->{"$ifName"}->{ifSpeed} =
            ($refhIfSpeed->{"$Index"});
        $grefhCurrent->{If}->{"$ifName"}->{ifSpeedReadable} =
            ConvertSpeedToReadable ($refhIfSpeed->{"$Index"});

        # Store ifAlias normalized to not get into trouble with special chars
        if (defined $refhIfAlias->{"$Index"}) {
            $grefhCurrent->{If}->{"$ifName"}->{ifAlias} = normalize ($refhIfAlias->{"$Index"});
        } else {
            $grefhCurrent->{If}->{"$ifName"}->{ifAlias} = '';
        }

        logger(2, "  Speed=".$grefhCurrent->{If}->{"$ifName"}->{ifSpeedReadable}."\t".
            "Alias=\"".$grefhCurrent->{If}->{"$ifName"}->{ifAlias}."\"");

        # Store ifDuplexStatus converted from a digit to string
        if ($ghOptions{'duplex'}) {
            # Store ifDuplexStatus converted from a digit to string
            $grefhCurrent->{If}->{"$ifName"}->{ifDuplexStatus} =
                ConvertIfDuplexStatusToReadable ($refhIfDuplexStatus->{"$Index"});
            logger(2, "  ifDuplexStatus=" . $grefhCurrent->{If}->{"$ifName"}->{ifDuplexStatus});
        }

        if ($ghOptions{vlan}) { # show VLANs per port
            # clear ifVlanNames
            $grefhCurrent->{If}->{"$ifName"}->{ifVlanNames} = '';
        }
    }

    if ($ghOptions{vlan}) { # show VLANs per port

        my $VlanNames = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_ifVlanName,$ghOptions{'cachedir'},0);

        # store Vlan names in a hash
        my %vlanname;
        foreach my $tmp ( @$VlanNames ) {
            my ($oid, @name) = split(/ /, $tmp);
            chomp(@name);
            $vlanname{$oid} = "@name";
            $vlanname{$oid} =~ tr/"<>/'../; #"
        }

        if ($ghOptions{'nodetype'} eq "cisco") {
            my $VlanPortCisco = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_cisco_ifVlanPort,$ghOptions{'cachedir'},0);
            if (defined $VlanPortCisco and @$VlanPortCisco > 0) {
                foreach my $tmp ( @$VlanPortCisco ) {
                    my ($oid, $vlan) = split(/ /, $tmp);
                    chomp($vlan);
                    my @oid = split(/\./, $oid);
                    my $port = $oid[-1];
                    my $ifName = $grefhCurrent->{MD}->{Map}->{IndexToName}->{$port};

                    # store ifVlanNames
                    if((defined $ifName) and ($ifName ne '')) {
                        $grefhCurrent->{If}->{"$ifName"}->{ifVlanNames} .= $vlan. " ";
                        logger(2, "  Vlan=" . $grefhCurrent->{If}->{"$ifName"}->{ifVlanNames});
                    }
                }
            }
        } elsif ($ghOptions{'nodetype'} eq "hp") {
            my $VlanPortHP = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_hp_ifVlanPort,$ghOptions{'cachedir'},0);
            if (defined $VlanPortHP and @$VlanPortHP > 0) {
                foreach my $tmp ( @$VlanPortHP ) {
                    my ($oid, $port) = split(/ /, $tmp);
                    chomp($port);
                    my @oid = split(/\./, $oid);
                    my $vlan = $oid[-2];
                    my $ifName = $grefhCurrent->{MD}->{Map}->{IndexToName}->{$port};

                    # store ifVlanNames
                    if((defined $ifName) and ($ifName ne '')) {
                        $grefhCurrent->{If}->{"$ifName"}->{ifVlanNames} .= $vlanname{"$oid_ifVlanName.$vlan"}. " ";
                        logger(2, "  Vlan=" . $grefhCurrent->{If}->{"$ifName"}->{ifVlanNames});
                    }
                }
            }
        }
    }

    return 0;
}

# ------------------------------------------------------------------------
#
# ------------------------------------------------------------------------
sub Get_Stp {
    my $refaSTPIfIndexMapLines;                         # Lines returned from snmpwalk storing stp port->ifindex map table
    my $refaSTPPortStateLines;                          # Lines returned from snmpwalk storing stp port states

    # get stp port->ifindex map table
    $refaSTPIfIndexMapLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_stp_ifindex_map,$ghOptions{'cachedir'},0);
    if ($#$refaSTPIfIndexMapLines < 0 ) {
        logger(0, "Could not read STP port-index map table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_stp_ifindex_map\n");
        exit $ERRORS{"UNKNOWN"};
    }
    for (@$refaSTPIfIndexMapLines) {
        if (/$oid_stp_ifindex_map\.([0-9]*) ([0-9]*)/) {
            $grefhCurrent->{MD}->{Map}->{dot1dBridge}->{StpIndexToIndex}->{"$1"} = $2;
            $grefhCurrent->{MD}->{Map}->{dot1dBridge}->{IndexToStpIndex}->{"$2"} = $1;
            $grefhCurrent->{MD}->{Map}->{dot1dBridge}->{NameToStpIndex}->{"$grefhCurrent->{MD}->{Map}->{IndexToName}->{$2}"} = $1;
            $grefhCurrent->{MD}->{Map}->{dot1dBridge}->{StpIndexToName}->{"$1"} = "$grefhCurrent->{MD}->{Map}->{IndexToName}->{$2}";
        }
    }

    $refaSTPPortStateLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_stp_portstate,$ghOptions{'cachedir'},0);
    if ($#$refaSTPPortStateLines < 0 ) {
        logger(0, "Could not read STP port state table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_stp_portstate\n");
        exit $ERRORS{"UNKNOWN"};
    }

    for (@$refaSTPPortStateLines) {
        my ($Index,$Portstate) = split / /,$_,2;
        $Index =~ s/^.*\.//g;    # remove all but the index
        $Portstate =~ s/\s+$//g;    # remove invisible chars from the end

        if (defined $grefhCurrent->{MD}->{Map}->{dot1dBridge}->{StpIndexToName}->{$Index}) {
            my $ifName = $grefhCurrent->{MD}->{Map}->{dot1dBridge}->{StpIndexToName}->{$Index};
            defined $stp_portstate_readable{"$Portstate"} and $Portstate = $stp_portstate_readable{"$Portstate"};
            logger(2, "IfName=\"$ifName\", StpIndex=\"$Index\", StpPortstate=\"$Portstate\"");

            # Store the Portstate as property of the current interface
            $grefhCurrent->{If}->{"$ifName"}->{ifStpState} = "$Portstate";
        }
    }
    return 0;

}

# ------------------------------------------------------------------------
#
# ------------------------------------------------------------------------
sub Get_Netscreen {
    my $refhNsIfNetmask = ();
    my $refhNsZone = ();
    my $refhNsVsys = ();
    my $refhNsIfMng = ();

    my $refaNsIfNameLines;
    my $refaNsIfIpLines;                # Lines returned from snmpwalk storing ip addresses
    my $refaNsIfNetmaskLines;           # Lines returned from snmpwalk storing physical addresses
    my $refaNsZoneCfgNameLines;
    my $refaNsIfZoneLines;
    my $refaNsVsysCfgNameLines;
    my $refaNsIfVsysLines;
    my $refaNsIfMngTelnetLines;         # Permitted management: Telnet
    my $refaNsIfMngSCSLines;            # Permitted management: SCS
    my $refaNsIfMngWEBLines;            # Permitted management: WEB
    my $refaNsIfMngSSLLines;            # Permitted management: SSL
    my $refaNsIfMngSNMPLines;           # Permitted management: SNMP
    my $refaNsIfMngGlobalLines;         # Permitted management: Global
    my $refaNsIfMngGlobalProLines;      # Permitted management: GlobalPro
    my $refaNsIfMngPingLines;           # Permitted management: Ping
    my $refaNsIfMngIdentResetLines;     # Permitted management: IdentReset

    # get netscreen interface name and build a map table with the standard interface description
    $refaNsIfNameLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_juniper_nsIfName,$ghOptions{'cachedir'},0);
    if ($#$refaNsIfNameLines < 0 ) {
        logger(0, "Could not read the Netscreen nsIfName table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_juniper_nsIfName\n");
        exit $ERRORS{"UNKNOWN"};
    }
    for (@$refaNsIfNameLines) {
        my ($Index,$Value) = split / /,$_,2;
        $Index =~ s/^.*\.//g;           # remove all but the index
        $Value =~ s/\s+$//g;            # remove invisible chars from the end
        $Value = normalize ($Value);
        if (defined $grefhCurrent->{MD}->{Map}->{DescrToName}->{"$Value"}) {
            my $ifName = $grefhCurrent->{MD}->{Map}->{DescrToName}->{"$Value"};
            $grefhCurrent->{MD}->{Map}->{Netscreen}->{NameToNsIfIndex}->{"$ifName"} = $Index;
            $grefhCurrent->{MD}->{Map}->{Netscreen}->{NsIfIndexToName}->{$Index} = "$ifName";
        }
    }

    # IP/Netmask
    ## get info from snmp/cache
    $refaNsIfIpLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_juniper_nsIfIp,$ghOptions{'cachedir'},0);
    if ($#$refaNsIfIpLines < 0 ) {
        logger(0, "Could not read Netscreen nsIfIp information from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_juniper_nsIfIp\n");
        exit $ERRORS{"UNKNOWN"};
    }

    # store all ip information in the hash to avoid reading the netmask
    # again in the next run
    $grefhCurrent->{MD}->{CachedInfo}->{IpInfo} = join (";",@$refaNsIfIpLines);

    # remove all invisible chars incl. \r and \n
    $grefhCurrent->{MD}->{CachedInfo}->{IpInfo} =~ s/[\000-\037]|[\177-\377]//g;

    # get the subnet masks with caching 0 only if the ip addresses
    # have changed
    if (defined $grefhFile->{MD}->{CachedInfo}->{IpInfo} and $grefhCurrent->{MD}->{CachedInfo}->{IpInfo} eq $grefhFile->{MD}->{CachedInfo}->{IpInfo}) {
        $refaNsIfNetmaskLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_juniper_nsIfNetmask,$ghOptions{'cachedir'},$gLongCacheTimer);
    } else {
        $refaNsIfNetmaskLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_juniper_nsIfNetmask,$ghOptions{'cachedir'},0);
    }
    for (@$refaNsIfNetmaskLines) {
        my ($Index,$Value) = split / /,$_,2;
        $Index =~ s/^.*\.//g;           # remove all but the index
        $Value =~ s/\s+$//g;            # remove invisible chars from the end
        $refhNsIfNetmask->{"$Index"} = "$Value";
    }

    for (@$refaNsIfIpLines) {
        my ($Index,$IpAddress) = split / /,$_,2;        # blank splits OID & ifIndex
        $Index      =~  s/^$oid_juniper_nsIfIp\.//;     # remove all but numbers
        $Index      =~  s/\D//g;                        # remove all but numbers

        # extract the netmask
        my $NetMask = (defined $refhNsIfNetmask->{$Index}) ? $refhNsIfNetmask->{$Index} : "";

        logger(2, "Index: $Index,\tIpAddress: $IpAddress,\tNetmask: $NetMask");
        if (defined $quadmask2dec{"$NetMask"}) {$NetMask = $quadmask2dec{"$NetMask"};}

        # get the interface name stored before from the index table
        # check that a mapping was possible between the ip info and an interface
        if (defined $grefhCurrent->{MD}->{Map}->{Netscreen}->{NsIfIndexToName}->{$Index}) {
            my $Name = $grefhCurrent->{MD}->{Map}->{Netscreen}->{NsIfIndexToName}->{$Index};

            # separate multiple IP Adresses with a blank
            # blank is good because the WEB browser can break lines
            if ($grefhCurrent->{If}->{"$Name"}->{ifIpInfo}) {
                $grefhCurrent->{If}->{"$Name"}->{ifIpInfo} =
                $grefhCurrent->{If}->{"$Name"}->{ifIpInfo}." "
            }
            # now we are finished with the puzzle of getting ip and subnet mask
            # add IpInfo as property to the interface
            my $IpInfo = "$IpAddress";
            if ($NetMask) {$IpInfo .= "/$NetMask";}
            $grefhCurrent->{If}->{"$Name"}->{ifIpInfo} .= $IpInfo;

            # check if the IP address has changed to its first run
            my $FirstIpInfo = $grefhFile->{If}->{"$Name"}->{ifIpInfo};
            unless ($FirstIpInfo) {$FirstIpInfo = "";}

            # disable caching of this interface if ip information has changed
            if ("$IpInfo" ne "$FirstIpInfo") {
                $grefhCurrent->{MD}->{If}->{"$Name"}->{CacheTimer} = 0;
                $grefhCurrent->{MD}->{If}->{"$Name"}->{CacheTimerComment} =
                    "caching is disabled because of first or current IpInfo";
            }
        } else {
            logger(3, "Cannot map the IP info to any existing interface: no corresponding interface index. Skipping IP info.");
        }
    }

    # Zones
    ## get netscreen zone id and name
    $refaNsZoneCfgNameLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_juniper_nsZoneCfgName,$ghOptions{'cachedir'},0);
    if ($#$refaNsZoneCfgNameLines < 0 ) {
        logger(0, "Could not read the Netscreen nsZoneCfgName table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_juniper_nsZoneCfgName\n");
        exit $ERRORS{"UNKNOWN"};
    }
    for (@$refaNsZoneCfgNameLines) {
        my ($Index,$Value) = split / /,$_,2;
        $Index =~ s/^.*\.//g;           # remove all but the index
        $Value =~ s/\s+$//g;            # remove invisible chars from the end
        $refhNsZone->{"$Index"} = "$Value";
    }
    ## get netscreen zone id for all interfaces
    $refaNsIfZoneLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_juniper_nsIfZone,$ghOptions{'cachedir'},0);
    if ($#$refaNsIfZoneLines < 0 ) {
        logger(0, "Could not read the Netscreen nsIfZone table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_juniper_nsIfZone\n");
        exit $ERRORS{"UNKNOWN"};
    }
    for (@$refaNsIfZoneLines) {
        my ($Index,$Value) = split / /,$_,2;
        $Index =~ s/^.*\.//g;           # remove all but the index
        $Value =~ s/\s+$//g;            # remove invisible chars from the end
        if (defined $grefhCurrent->{MD}->{Map}->{Netscreen}->{NsIfIndexToName}->{$Index}) {
            $grefhCurrent->{If}->{"$grefhCurrent->{MD}->{Map}->{Netscreen}->{NsIfIndexToName}->{$Index}"}->{nsIfZone} = "$refhNsZone->{$Value}";
            logger(2, "Index: $Index (" . $grefhCurrent->{MD}->{Map}->{Netscreen}->{NsIfIndexToName}->{$Index} . "),\tnsIfZone: " . $refhNsZone->{$Value});
        }
    }

    # Vsys
    ## get netscreen vsys id and name
    $refaNsVsysCfgNameLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_juniper_nsVsysCfgName,$ghOptions{'cachedir'},0);
    if ($#$refaNsVsysCfgNameLines < 0 ) {
        logger(0, "Could not read the Netscreen nsZoneCfgName table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_juniper_nsVsysCfgName\n");
        exit $ERRORS{"UNKNOWN"};
    }
    for (@$refaNsVsysCfgNameLines) {
        my ($Index,$Value) = split / /,$_,2;
        $Index =~ s/^.*\.//g;           # remove all but the index
        $Value =~ s/\s+$//g;            # remove invisible chars from the end
        $refhNsVsys->{"$Index"} = "$Value";
    }
    ## get netscreen zone id for all interfaces
    $refaNsIfVsysLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_juniper_nsIfVsys,$ghOptions{'cachedir'},0);
    if ($#$refaNsIfVsysLines < 0 ) {
        logger(0, "Could not read the Netscreen nsIfVsys table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_juniper_nsIfVsys\n");
        exit $ERRORS{"UNKNOWN"};
    }
    for (@$refaNsIfVsysLines) {
        my ($Index,$Value) = split / /,$_,2;
        $Index =~ s/^.*\.//g;           # remove all but the index
        $Value =~ s/\s+$//g;            # remove invisible chars from the end
        if (defined $grefhCurrent->{MD}->{Map}->{Netscreen}->{NsIfIndexToName}->{$Index}) {
            $grefhCurrent->{If}->{"$grefhCurrent->{MD}->{Map}->{Netscreen}->{NsIfIndexToName}->{$Index}"}->{nsIfVsys} = "$refhNsVsys->{$Value}";
            logger(2, "Index: $Index (" . $grefhCurrent->{MD}->{Map}->{Netscreen}->{NsIfIndexToName}->{$Index} . "),\tnsIfVsys: " . $refhNsVsys->{$Value});
        }
    }

    # Management protocols
    # get permitted management protocols
    ## Telnet
    $refaNsIfMngTelnetLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_juniper_nsIfMngTelnet,$ghOptions{'cachedir'},0);
    if ($#$refaNsIfMngTelnetLines < 0 ) {
        logger(0, "Could not read Netscreen nsIfMngTelnet table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_juniper_nsIfMngTelnet\n");
        exit $ERRORS{"UNKNOWN"};
    }
    ## SCS
    $refaNsIfMngSCSLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_juniper_nsIfMngSCS,$ghOptions{'cachedir'},0);
    if ($#$refaNsIfMngSCSLines < 0 ) {
        logger(0, "Could not read Netscreen nsIfMngSCS table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_juniper_nsIfMngSCS\n");
        exit $ERRORS{"UNKNOWN"};
    }
    ##WEB
    $refaNsIfMngWEBLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_juniper_nsIfMngWEB,$ghOptions{'cachedir'},0);
    if ($#$refaNsIfMngWEBLines < 0 ) {
        logger(0, "Could not read Netscreen nsIfMngWEB table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_juniper_nsIfMngWEB\n");
        exit $ERRORS{"UNKNOWN"};
    }
    ##SSL
    $refaNsIfMngSSLLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_juniper_nsIfMngSSL,$ghOptions{'cachedir'},0);
    if ($#$refaNsIfMngSSLLines < 0 ) {
        logger(0, "Could not read Netscreen nsIfMngSSL table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_juniper_nsIfMngSSL\n");
        exit $ERRORS{"UNKNOWN"};
    }
    ##SNMP
    $refaNsIfMngSNMPLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_juniper_nsIfMngSNMP,$ghOptions{'cachedir'},0);
    if ($#$refaNsIfMngSNMPLines < 0 ) {
        logger(0, "Could not read Netscreen nsIfMngSNMP table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_juniper_nsIfMngSNMP\n");
        exit $ERRORS{"UNKNOWN"};
    }
    ##Global
    $refaNsIfMngGlobalLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_juniper_nsIfMngGlobal,$ghOptions{'cachedir'},0);
    if ($#$refaNsIfMngGlobalLines < 0 ) {
        logger(0, "Could not read Netscreen nsIfMngGlobal table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_juniper_nsIfMngGlobal\n");
        exit $ERRORS{"UNKNOWN"};
    }
    ##GlobalPro
    $refaNsIfMngGlobalProLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_juniper_nsIfMngGlobalPro,$ghOptions{'cachedir'},0);
    if ($#$refaNsIfMngGlobalProLines < 0 ) {
        logger(0, "Could not read Netscreen nsIfMngGlobalPro table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_juniper_nsIfMngGlobalPro\n");
        exit $ERRORS{"UNKNOWN"};
    }
    ##Ping
    $refaNsIfMngPingLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_juniper_nsIfMngPing,$ghOptions{'cachedir'},0);
    if ($#$refaNsIfMngPingLines < 0 ) {
        logger(0, "Could not read Netscreen nsIfMngPing table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_juniper_nsIfMngPing\n");
        exit $ERRORS{"UNKNOWN"};
    }
    ##IdentReset
    $refaNsIfMngIdentResetLines = GetTableDataWithSnmp ($ghOptions{'hostquery'},\%ghSNMPOptions,$oid_juniper_nsIfMngIdentReset,$ghOptions{'cachedir'},0);
    if ($#$refaNsIfMngIdentResetLines < 0 ) {
        logger(0, "Could not read Netscreen nsIfMngIdentReset table from host \"$ghOptions{'hostquery'}\" with snmp\nCheck the access to the oid $oid_juniper_nsIfMngIdentReset\n");
        exit $ERRORS{"UNKNOWN"};
    }

    foreach (@$refaNsIfMngTelnetLines) {
        my ($Index,$Value) = split / /,$_,2;
        $Index =~ s/^.*\.//g;    # remove all but the index
        $Value =~ s/\s+$//g;    # remove invisible chars from the end
        $refhNsIfMng->{"$Index"} = "" if not defined $refhNsIfMng->{"$Index"};

        # Add the protocol if permitted
        if ($Value) {
            $refhNsIfMng->{"$Index"} .= ", " if $refhNsIfMng->{"$Index"} ne "";
            $refhNsIfMng->{"$Index"} .= "Telnet";
        }
    }
    foreach (@$refaNsIfMngSCSLines) {
        my ($Index,$Value) = split / /,$_,2;
        $Index =~ s/^.*\.//g;    # remove all but the index
        $Value =~ s/\s+$//g;    # remove invisible chars from the end
        $refhNsIfMng->{"$Index"} = "" if not defined $refhNsIfMng->{"$Index"};

        # Add the protocol if permitted
        if ($Value) {
            $refhNsIfMng->{"$Index"} .= ", " if $refhNsIfMng->{"$Index"} ne "";
            $refhNsIfMng->{"$Index"} .= "SCS";
        }
    }
    foreach (@$refaNsIfMngWEBLines) {
        my ($Index,$Value) = split / /,$_,2;
        $Index =~ s/^.*\.//g;    # remove all but the index
        $Value =~ s/\s+$//g;    # remove invisible chars from the end
        $refhNsIfMng->{"$Index"} = "" if not defined $refhNsIfMng->{"$Index"};

        # Add the protocol if permitted
        if ($Value) {
            $refhNsIfMng->{"$Index"} .= ", " if $refhNsIfMng->{"$Index"} ne "";
            $refhNsIfMng->{"$Index"} .= "WEB";
        }
    }
    foreach (@$refaNsIfMngSSLLines) {
        my ($Index,$Value) = split / /,$_,2;
        $Index =~ s/^.*\.//g;    # remove all but the index
        $Value =~ s/\s+$//g;    # remove invisible chars from the end
        $refhNsIfMng->{"$Index"} = "" if not defined $refhNsIfMng->{"$Index"};

        # Add the protocol if permitted
        if ($Value) {
            $refhNsIfMng->{"$Index"} .= ", " if $refhNsIfMng->{"$Index"} ne "";
            $refhNsIfMng->{"$Index"} .= "SSL";
        }
    }
    foreach (@$refaNsIfMngSNMPLines) {
        my ($Index,$Value) = split / /,$_,2;
        $Index =~ s/^.*\.//g;    # remove all but the index
        $Value =~ s/\s+$//g;    # remove invisible chars from the end
        $refhNsIfMng->{"$Index"} = "" if not defined $refhNsIfMng->{"$Index"};

        # Add the protocol if permitted
        if ($Value) {
            $refhNsIfMng->{"$Index"} .= ", " if $refhNsIfMng->{"$Index"} ne "";
            $refhNsIfMng->{"$Index"} .= "SNMP";
        }
    }
    foreach (@$refaNsIfMngGlobalLines) {
        my ($Index,$Value) = split / /,$_,2;
        $Index =~ s/^.*\.//g;    # remove all but the index
        $Value =~ s/\s+$//g;    # remove invisible chars from the end
        $refhNsIfMng->{"$Index"} = "" if not defined $refhNsIfMng->{"$Index"};

        # Add the protocol if permitted
        if ($Value) {
            $refhNsIfMng->{"$Index"} .= ", " if $refhNsIfMng->{"$Index"} ne "";
            $refhNsIfMng->{"$Index"} .= "Global";
        }
    }
    foreach (@$refaNsIfMngGlobalProLines) {
        my ($Index,$Value) = split / /,$_,2;
        $Index =~ s/^.*\.//g;    # remove all but the index
        $Value =~ s/\s+$//g;    # remove invisible chars from the end
        $refhNsIfMng->{"$Index"} = "" if not defined $refhNsIfMng->{"$Index"};

        # Add the protocol if permitted
        if ($Value) {
            $refhNsIfMng->{"$Index"} .= ", " if $refhNsIfMng->{"$Index"} ne "";
            $refhNsIfMng->{"$Index"} .= "GlobalPro";
        }
    }
    foreach (@$refaNsIfMngPingLines) {
        my ($Index,$Value) = split / /,$_,2;
        $Index =~ s/^.*\.//g;    # remove all but the index
        $Value =~ s/\s+$//g;    # remove invisible chars from the end
        $refhNsIfMng->{"$Index"} = "" if not defined $refhNsIfMng->{"$Index"};

        # Add the protocol if permitted
        if ($Value) {
            $refhNsIfMng->{"$Index"} .= ", " if $refhNsIfMng->{"$Index"} ne "";
            $refhNsIfMng->{"$Index"} .= "Ping";
        }
    }
    foreach (@$refaNsIfMngIdentResetLines) {
        my ($Index,$Value) = split / /,$_,2;
        $Index =~ s/^.*\.//g;    # remove all but the index
        $Value =~ s/\s+$//g;    # remove invisible chars from the end
        $refhNsIfMng->{"$Index"} = "" if not defined $refhNsIfMng->{"$Index"};

        # Add the protocol if permitted
        if ($Value) {
            $refhNsIfMng->{"$Index"} .= ", " if $refhNsIfMng->{"$Index"} ne "";
            $refhNsIfMng->{"$Index"} .= "IdentReset";
        }
    }
    for my $Index (keys %$refhNsIfMng) {
        if (defined $grefhCurrent->{MD}->{Map}->{Netscreen}->{NsIfIndexToName}->{$Index}) {
            $grefhCurrent->{If}->{"$grefhCurrent->{MD}->{Map}->{Netscreen}->{NsIfIndexToName}->{$Index}"}->{nsIfMng} = "$refhNsIfMng->{$Index}";
            logger(2, "Index: $Index (" . $grefhCurrent->{MD}->{Map}->{Netscreen}->{NsIfIndexToName}->{$Index} . "),\tnsIfMng: " . $refhNsIfMng->{$Index});
        }
    }

    return 0;

}

# ------------------------------------------------------------------------
# get the interface speed as integer and convert it to a readable format
# return a string
# ------------------------------------------------------------------------
sub ConvertSpeedToReadable {
    my $Speed = shift;
    if ($Speed > 999999999) {
        $Speed = sprintf ("%0.2f Gbit",$Speed/1000000000);
    } elsif ($Speed > 999999) {
        $Speed = sprintf ("%0.2f Mbit",$Speed/1000000);
    } elsif ($Speed > 999) {
        $Speed = sprintf ("%0.2f kbit",$Speed/1000);
    } elsif ($Speed > 0) {
        $Speed = sprintf ("%0.2f bit",$Speed);
    } else {
        $Speed = "";
    }
    return $Speed;
}
# ------------------------------------------------------------------------
# get the interface administrative/operational status as integer or string and convert
# it to a readable format - return a string
#
# http://www.faqs.org/rfcs/rfc2863.html
#
#    ifAdminStatus OBJECT-TYPE
#        SYNTAX  INTEGER {
#                up(1),      -- ready to pass packets
#                down(2),
#                testing(3)  -- in some test mode
#        }
#
#    ifOperStatus OBJECT-TYPE
#        SYNTAX  INTEGER {
#                up(1),        -- ready to pass packets
#                down(2),
#                testing(3),   -- in some test mode
#                unknown(4),   -- status can not be determined
#                              -- for some reason.
#                dormant(5),
#                notPresent(6),    -- some component is missing
#                lowerLayerDown(7) -- down due to state of
#                                  -- lower-layer interface(s)
#        ]
# ------------------------------------------------------------------------
sub ConvertIfStatusToReadable {
    my $status = shift;
    my %status_conversion = ( 1=>'up', 2=>'down', 3=>'testing', 4=>'unknown', 5=>'dormant', 6=>'notPresent', 7=>'lowerLayerDown');
    if ($status =~ /^(1|2|3|4|5|6|7)$/) {
        $status = $status_conversion{$status};
    } else {
        # we do nothing and leave the original status
    }
    return $status;
}
sub ConvertIfStatusToNumber {
    my $status = shift;
    my %status_conversion = ( 'up'=>1,'down'=>2,'testing'=>3,'unknown'=>4,'dormant'=>5,'notPresent'=>6,'lowerLayerDown'=>7 );
    if ($status =~ /^(up|down|testing|unknown|dormant|notPresent|lowerLayerDown)$/) {
        $status = $status_conversion{$status};
    } else {
        # we do nothing and leave the original status
        ## we return an empty string
        #$status = '';
    }
    return $status;
}

# ------------------------------------------------------------------------
# get the interface duplex status as integer or string and convert
# it to a readable format - return a string
#
# http://www.faqs.org/rfcs/rfc3635.html (EtherLike MIB)
#
#    dot3StatsDuplexStatus OBJECT-TYPE
#        SYNTAX  INTEGER {
#                    unknown(1),
#                    halfDuplex(2),
#                    fullDuplex(3)
#        }
# ------------------------------------------------------------------------
sub ConvertIfDuplexStatusToReadable {
    my $status = shift;
    my %status_conversion = ( 1=>'unknown', 2=>'half', 3=>'full');
    if (defined $status) {
        if ($status =~ /^(1|2|3)$/) {
            $status = $status_conversion{$status};
        } else {
            # we do nothing and leave the original status
        }
    } else {
        $status = '';
    }
    return $status;
}

# ------------------------------------------------------------------------
# calculate time diff of unix epoch seconds and return it in
# a readable format
#
# my $x = TimeDiff ("1150100854","1150234567");
# print $x;   # $x equals to 1d 13h 8m
#
# ------------------------------------------------------------------------
sub TimeDiff {
    my ($StartTime, $EndTime, $warn, $crit) = @_;

    my $Days  = 0;
    my $Hours = 0;
    my $Min   = 0;
    my $Status   = $ERRORS{'UNKNOWN'};
    my $TimeDiff = $EndTime - $StartTime;

    my $Rest;

    my $String = "(NoData)"; # default text (unknown/error)

    # check start not 0
    if ($StartTime == 0) {
        return wantarray ? ('(NoData)', $ERRORS{'UNKNOWN'}) : '(NoData)';
    }

    # check start must be before end
    if ($EndTime < $StartTime) {
        return wantarray ? ('(NoData)', $ERRORS{'UNKNOWN'}) : '(NoData)';
    }

    # check if there is no traffic for $crit or $warn seconds
    if (defined $warn and defined $crit) {
        if ($TimeDiff > $crit) {
            $Status = $ERRORS{'CRITICAL'};
        } elsif ($TimeDiff > $warn) {
            $Status = $ERRORS{'WARNING'};
        } else {
            $Status = $ERRORS{'OK'};
        }
    } else {
        $Status = $ERRORS{'OK'};
    }

    $Days = int ($TimeDiff / 86400);
    $Rest = $TimeDiff - ($Days * 86400);

    if ($Rest < 0) {
        $Days = 0;
        $Hours = int ($TimeDiff / 3600);
    } else {
        $Hours = int ($Rest / 3600);
    }

    $Rest = $Rest - ($Hours * 3600);

    if ($Rest < 0) {
        $Hours = 0;
        $Min = int ($TimeDiff / 60);
    } else {
        $Min = int ($Rest / 60);
    }

    #logger(1, "warn: $warn, crit: $crit, diff: $TimeDiff, status: $Status");
    return wantarray ? ("${Days}d ${Hours}h ${Min}m", $Status) : "${Days}d ${Hours}h ${Min}m";
}

# ------------------------------------------------------------------------
# colorcode function to give a html color code between green and red for a given percent value
# ------------------------------------------------------------------------
sub colorcode {
    my $current = shift;
    my $warning = shift;
    my $critical = shift;
    my $colorcode;

    # just traffic light color codes for the lame
    if ($current < $warning) {            # green / ok
        $colorcode = 'green';
    } elsif ($current < $critical) {       # yellow / warn
        $colorcode = 'yellow';
    } else {                          # red / crit
        $colorcode = 'red';
    }

    if ($ghOptions{'ifloadgradient'}) {
        # its cool to have a gradient from green over yellow to red representing the percent value
        # the gradient goes from
        #   #00FF00 (green) at 0 % over
        #   #FFFF00 (yellow) at $warn % to
        #   #FF0000 (red) at $crit % and over

        # first adjust the percent value according to the given warning and critical levels
        my $green  = 255;
        my $red    = 0;
        if ($current > 0) {
            if (($current <= $warning) && ($current < $critical)) {
                $green  = 255;
                $red    = $current * 255 / $warning;
            } elsif ($current <= $critical) {
                $green  = 255 - ( $current * 255 / $critical );
                $red    = 255;
            } elsif ($current > $critical) {
                $green  = 0;
                $red    = 255;
            }
        }
        $colorcode = sprintf "%2.2x%2.2x%2.2x", $red, $green, 0;
        logger(3, " colorcode: $colorcode, current: $current, red: $red, green: $green");
    }
    return $colorcode;
}

# ------------------------------------------------------------------------
# check_for_unused_interfaces
#  * arg 1: name (ifName) of the interface
#  * arg 2: free???
#     . -1  -> interface used, unknown last traffic
#     . 0   -> interface used, last traffic is < crit duration
#     . 1   -> interface unused, last traffic is >= crit duration
# ------------------------------------------------------------------------
sub check_for_unused_interfaces {
    my ($ifName, $free) = @_;

    if ($grefhCurrent->{If}->{"$ifName"}->{ifSpeed}) {
        # Interface has a speed property, that can be a physical interface

        if ($ifName =~ /Ethernet(\d+)Q2F(\d+)Q2F(\d+)/) {
            # we look for ethernet ports (and decide if it is a stacked switch), x/x/x format
            if (not defined $gInterfacesWithoutTrunk->{"$1/$2/$3"}) {
                $gInterfacesWithoutTrunk->{"$1/$2/$3"} = $free;
                $gNumberOfInterfacesWithoutTrunk++;
                # look for free ports with admin status up
                if ($free and $grefhCurrent->{If}->{"$ifName"}->{ifAdminStatus} eq 'up') {
                    $grefhCurrent->{If}->{$ifName}->{ifLastTrafficOutOfRange} = "yellow";
                    $gNumberOfFreeUpInterfaces++;
                }
            }
        } elsif ($ifName =~ /Ethernet(\d+)Q2F(\d+)/) {
            # we look for ethernet ports (and decide if it is a stacked switch), x/x format
            if (not defined $gInterfacesWithoutTrunk->{"$1/$2"}) {
                $gInterfacesWithoutTrunk->{"$1/$2"} = $free;
                $gNumberOfInterfacesWithoutTrunk++;
                # look for free ports with admin status up
                if ($free and $grefhCurrent->{If}->{"$ifName"}->{ifAdminStatus} eq 'up') {
                    $grefhCurrent->{If}->{$ifName}->{ifLastTrafficOutOfRange} = "yellow";
                    $gNumberOfFreeUpInterfaces++;
                }
            }
        } elsif (not $ifName =~ /^vif|Loopback|^lo/i) {
            # we look for all interfaces having speed property but not looking like a virtual interface
            if (not defined $gInterfacesWithoutTrunk->{"$ifName"}) {
                $gInterfacesWithoutTrunk->{"$ifName"} = $free;
                $gNumberOfInterfacesWithoutTrunk++;
                # look for free ports with admin status up
                if ($free and $grefhCurrent->{If}->{"$ifName"}->{ifAdminStatus} eq 'up') {
                    $grefhCurrent->{If}->{$ifName}->{ifLastTrafficOutOfRange} = "yellow";
                    $gNumberOfFreeUpInterfaces++;
                }
            }
        }
    }
    logger(1, "ifName: $ifName\tFreeUp: $gNumberOfFreeUpInterfaces\tWithoutTrunk: $gNumberOfInterfacesWithoutTrunk");
}

# ------------------------------------------------------------------------------
# Convert2HtmlTable
# This function generates a html table
# ------------------------------------------------------------------------------
# Function call:
#  $gHtml = Convert2HtmlTable ($tableType, $refAoHHeader,$refAoAoHLines,$cssClass);
# Arguments:
#  0 : number representing the properties of the table to generate:
#       1 : enable header line
#       2 : enable first column
#      exemple: 3 = header line and first column enabled
#      default is 1.
#  1 : ref to an AoH. Each hash correspond to a header of the table
#        * Link
#        * Tip
#  2 : ref to an AoAoH. Each subarray corresponds to an interface
#      (a table row) and contains a hash for each column
#      hash keys can be:
#        * InterfaceGraphURL
#        * Background
#        * Style
#        * Value
#  3 : css class to use for the table
#      available ones are: infotable, interfacetable
# Output:
#  0 : string containing all the html code corresponding to a table
# ------------------------------------------------------------------------------
# Exemple 1: InfoTable
#
# refAoHHeader:
# $VAR1 = [
#          { 'Enabled' => 1, 'Tip' => 'Tip Test', 'Title' => 'Name' },
#          { 'Enabled' => 1, 'Title' => 'Uptime' },
#          { 'Enabled' => 1, 'Title' => 'System Information' },
#          { 'Enabled' => 0, 'Link' => 'Link Test', 'Title' => 'Type' },
#          { 'Enabled' => 0, 'Title' => 'Serial' },
#          { 'Enabled' => 1, 'Title' => 'Ports' },
#          { 'Enabled' => 1, 'Title' => 'delta seconds used for bandwidth calculations' }
#        ];
#
# refAoAoHLines:
# $VAR1 = [
#           [
#             { 'Value' => 'snoopy.localdomain' },
#             { 'Value' => '0d&nbsp;2h&nbsp;39m' },
#             { 'Value' => 'Linux snoopy.localdomain 2.6.32-220.2.1.el6.x86_64 #1 SMP Fri Dec 23 02:21:33 CST 2011 x86_64' },
#             { 'Value' => 'ports:&nbsp;1 free:&nbsp;0 AdminUpFree:&nbsp;0' },
#             { 'Value' => '600' }
#           ]
#         ];
#
# HTML:
#<a name=top></a>
#<br><span>
#<table class=infotable>
#<th>Name</th><th>Uptime</th><th>System Information</th><th>Ports</th><th>delta seconds used for bandwidth calculations</th><tr>
#<td >snoopy.localdomain</td>
#<td >0d&nbsp;1h&nbsp;39m</td>
#<td >Linux snoopy.localdomain 2.6.32-220.2.1.el6.x86_64 #1 SMP Fri Dec 23 02:21:33 CST 2011 x86_64</td>
#<td >ports:&nbsp;1 free:&nbsp;0 AdminUpFree:&nbsp;0</td>
#<td >600</td></tr></table></td></tr><br>
# ------------------------------------------------------------------------------
# Exemple 2: InterfaceTable
#
# refAoHHeader:
# $VAR1 = [
#          { 'Dataname' => 'index', 'Enabled' => 1, 'Title' => 'Index' },
#          { 'Dataname' => 'ifDescr', 'Enabled' => 1, 'Title' => 'Description' },
#          { 'Dataname' => 'ifAlias', 'Enabled' => 1, 'Title' => 'Alias' },
#          { 'Dataname' => 'ifAdminStatus', 'Enabled' => 1, 'Title' => 'Admin status' },
#          { 'Dataname' => 'ifOperStatus', 'Enabled' => 1, 'Title' => 'Oper status' },
#          { 'Dataname' => 'ifSpeedReadable', 'Enabled' => 1, 'Title' => 'Speed' },
#          { 'Dataname' => 'ifDuplexStatus', 'Enabled' => 1, 'Title' => 'Duplex' },
#          { 'Dataname' => 'ifVlanNames', 'Enabled' => 0, 'Title' => 'Vlan' },
#          { 'Dataname' => 'ifLoadIn', 'Enabled' => 1, 'Title' => 'Load In' },
#          { 'Dataname' => 'ifLoadOut', 'Enabled' => 1, 'Title' => 'Load Out' },
#          { 'Dataname' => 'ifIpInfo', 'Enabled' => 1, 'Title' => 'IP' },
#          { 'Dataname' => 'bpsIn', 'Enabled' => 1, 'Title' => 'bpsIn' },
#          { 'Dataname' => 'bpsOut', 'Enabled' => 1, 'Title' => 'bpsOut' },
#          { 'Dataname' => 'pktErrDiscard', 'Enabled' => 1, 'Tip' => 'TipTest', 'Title' => 'Pkt errors' },
#          { 'Dataname' => 'ifLastTraffic', 'Enabled' => 1, 'Title' => 'Last traffic' },
#          { 'Dataname' => 'actions', 'Enabled' => 1, 'Title' => 'Actions' }
#        ];
#
#
# refAoAoHLines:
# $VAR1 = [
#           [
#             { 'Value' => '1' },
#             { 'Value' => 'lo' },
#             { 'Value' => '&nbsp' },
#             { 'Value' => 'up' },
#             { 'Style' => 'cellTrackedOk', 'Value' => 'up' },
#             { 'Value' => '10.00 Mbit' },
#             { 'Value' => '&nbsp' },
#             { 'Background' => '00ff00', 'Value' => '0.01' },
#             { 'Background' => '00ff00', 'Value' => '0.01' },
#             { 'Value' => '127.0.0.1/255.0.0.0' },
#             { 'Value' => '939.46 bps' },
#             { 'Value' => '939.46 bps' },
#             { 'Value' => '0.0/0.0/0.0/0.0' },
#             { 'Value' => '0d&nbsp;0h&nbsp;0m' },
#             { 'Value' => '&nbsp<a href="/pnp4nagios/graph?host=127.0.0.1&srv=If_lo"><img src="../img/chart.png" alt="Trends" /></a>&nbsp' }
#           ],
#           [
#             { 'Value' => '2' },
#             { 'Value' => 'eth0' },
#             { 'Value' => '&nbsp' },
#             { 'Value' => 'up' },
#             { 'Style' => 'cellTrackedOk', 'Value' => 'up' },
#             { 'Value' => '100.00 Mbit' },
#             { 'Value' => 'full' },
#             { 'Background' => '00ff00', 'Value' => '0.00' },
#             { 'Background' => '00ff00', 'Value' => '0.00' },
#             { 'Value' => '192.168.1.92/255.255.255.0' },
#             { 'Value' => '1.80 Kbps' },
#             { 'Value' => '1.60 Kbps' },
#             { 'Value' => '0.0/0.0/0.0/0.0' },
#             { 'Value' => '0d&nbsp;0h&nbsp;0m' },
#             { 'Value' => '&nbsp<a href="/pnp4nagios/graph?host=127.0.0.1&srv=If_eth0"><img src="../img/chart.png" alt="Trends" /></a>&nbsp' }
#           ]
#         ];
#
# HTML:
#<a name=top></a>
#<br><span>
#<table class=interfacetable onMouseOver="javascript:trackTableHighlight(event, '#81BEF7');" onMouseOut="javascript:highlightTableRow(0);">
#<th>Index</th><th>Description</th><th>Alias</th><th>Admin status</th><th>Oper status</th><th>Speed</th><th>Duplex</th><th>Load In</th><th>Load Out</th><th>IP</th><th>bpsIn</th><th>bpsOut</th><th>Pkt errors</th><th>Last traffic</th><th>Actions</th><tr>
#<td >1</td>
#<td >lo</td>
#<td >&nbsp</td>
#<td >up</td>
#<td  class="cellTrackedOk">up</td>
#<td >10.00 Mbit</td>
#<td >&nbsp</td>
#<td  bgcolor="00ff00">0.02</td>
#<td  bgcolor="00ff00">0.02</td>
#<td >127.0.0.1/255.0.0.0</td>
#<td >2.26 Kbps</td>
#<td >2.26 Kbps</td>
#<td >0.0/0.0/0.0/0.0</td>
#<td >0d&nbsp;0h&nbsp;0m</td>
#<td >&nbsp<a href="/pnp4nagios/graph?host=127.0.0.1&srv=If_lo"><img src="../img/chart.png" alt="Trends" /></a>&nbsp</td></tr><tr>
#<td >2</td>
#<td >eth0</td>
#<td >&nbsp</td>
#<td >up</td>
#<td  class="cellTrackedOk">up</td>
#<td >10.00 Mbit</td>
#<td >half</td>
#<td  bgcolor="00ff00">0.02</td>
#<td  bgcolor="00ff00">0.02</td>
#<td >192.168.1.92/255.255.255.0</td>
#<td >2.09 Kbps</td>
#<td >2.08 Kbps</td>
#<td >0.0/0.0/0.0/0.0</td>
#<td >0d&nbsp;0h&nbsp;0m</td>
#<td >&nbsp<a href="/pnp4nagios/graph?host=127.0.0.1&srv=If_eth0"><img src="../img/chart.png" alt="Trends" /></a>&nbsp</td></tr></table></td></tr><br>
# ------------------------------------------------------------------------------
sub Convert2HtmlTable {
    my $tableType  = shift;       # Type of table to generate
    my $refAoHHeader = shift;     # Header contains the HTML table header as array
    my $refAoAoHLines  = shift;   # Reference to array of table lines
    my $cssClass   = shift;       # Css class to use for the table
    my $highlightColor = shift;   # Color used to highlight. Disactivated if no color

    my $refaProperties;           # List of properties from each line
    my $HTML;                     # HTML Content back to the caller
    my $HTMLTable;                # HTML Table code only

    my $headerLineEnabled = $tableType%2;
    my $firstColumnEnabled = int($tableType/2);

    logger(3, "x"x50);
    logger(5, "refAoHHeader: " . Dumper ($refAoHHeader));
    logger(5, "refAoAoHLines: " . Dumper ($refAoAoHLines));

    if ($#$refAoAoHLines >= 0) {

        # ------------------------------------------------------------------
        # Build HTML format and table header
        $HTML .= '<table';
        $HTML .= " class=\"$cssClass no-arrow\"";
        if ($highlightColor ne "") {
            $HTML .= ' onMouseOver="javascript:trackTableHighlight(event, ' . "'" . $highlightColor . "'" . ');" onMouseOut="javascript:highlightTableRow(0);"';
        }
        $HTML .= '>'."\n";

        if ($headerLineEnabled) {
            # ------------------------------------------------------------------
            # Build html table title header
            $HTMLTable .= "<tr";
            my $trTagclose = '>';
            foreach my $Cell ( @$refAoHHeader ) {
                if ($Cell->{'Enabled'}) {
                    my $Title;
                    my $SpecialCellFormat = "";

                    $HTMLTable .= $trTagclose;
                    $trTagclose = '';

                    # Sorting
                    if ( defined $Cell->{'Tablesort'} and $Cell->{'Tablesort'} ne '') {
                        $SpecialCellFormat .= " class=\"$Cell->{'Tablesort'}\"";
                    }

                    # Tips
                    if ( defined $Cell->{Tip} and $ghOptions{'enabletips'}) {
                        #TODO
                        #$HTMLTable .= ' onclick="DoNav(\''.$Cell->{InterfaceGraphURL}. '\');"';
                    }

                    # if we got a title write into cell
                    if ( defined $Cell->{Title} and  $Cell->{Title} ne " ") {
                        $Title = $Cell->{Title};
                    } else {
                    # otherwise print the error
                        $Title = "ERROR: No name!";
                    }

                    # if a link is indicated
                    if ( defined $Cell->{Link} ) {
                        $Title = '<a href="' . $Cell->{Link} . '">' . $Title . '</a>';
                    }

                    # finally build the table line;
                    $HTMLTable .= "\n" . '<th' . $SpecialCellFormat . '>' . $Title . '</th>';
                }
            }
            $HTMLTable .= "</tr>";
        }

        # ------------------------------------------------------------------
        # Build html table content
        foreach my $Line ( @$refAoAoHLines ) {
            logger(5, "Line: " . Dumper ($Line));
            # start table line
            $HTMLTable .= "<tr";
            my $trTagclose = '>';

            my $cellCounter = 0;
            foreach my $Cell ( @$Line ) {

                $cellCounter += 1;
                my $Value;
                my $SpecialCellFormat      = "";
                #my $SpecialTextFormatHead  = "";
                #my $SpecialTextFormatFoot  = "";

                if ( defined $Cell->{InterfaceGraphURL} ) {
                    if($ghOptions{'enableperfdata'} and $ghOptions{'grapher'} ne "nagiosgrapher" ){         # thd
                        $HTMLTable .= ' onclick="DoNav(\''.$Cell->{InterfaceGraphURL}. '\');" >';
                    }
                    $trTagclose = '';
                }
                $HTMLTable .= $trTagclose;
                $trTagclose = '';
                #logger(1, "HTMLTable: $HTMLTable \nCell: $Cell->{InterfaceGraphURL}");
                # if background is defined
                if ( defined $Cell->{Background} ) {
                    $SpecialCellFormat .= ' bgcolor="'.$Cell->{Background}.'"';
                }

                # if first column enabled
                if ( $firstColumnEnabled and $cellCounter == 1 ) {
                    defined $Cell->{Style} ? $Cell->{Style} = "cellFirstColumn " . $Cell->{Style} : $Cell->{Style} = "cellFirstColumn";
                }

                # if style is defined
                if ( defined $Cell->{Style} ) {
                    $SpecialCellFormat .= ' class="'.$Cell->{Style}.'"';
                }

                # if a special font is indicated
                #if ( defined $Cell->{Font} ) {
                #    $SpecialTextFormatHead .= $Cell->{Font};
                #    $SpecialTextFormatFoot .= '</font>';
                #}

                # if we got a value write into cell
                if ( defined $Cell->{Value} and  $Cell->{Value} ne " ") {
                    $Value = $Cell->{Value};
                } else {
                # otherwise create a empty cell
                    $Value = "&nbsp;";
                }

                # if a link is indicated
                if ( defined $Cell->{Link} ) {
                    $Value = '<a href="' . $Cell->{Link} . '">' . $Value . '</a>';
                }

                # finally build the table line;
                $HTMLTable .= "\n" . '<td ' .
                    $SpecialCellFormat . '>' .
                    #$SpecialTextFormatHead .
                    $Value .
                    #$SpecialTextFormatFoot .
                    '</td>';
            }
            # end table line
            $HTMLTable .= "</tr>";
        }
        $HTMLTable .= "</table>";
        $HTML .= "$HTMLTable</td></tr><br>";
    } else {
        $HTML.='<a href=JavaScript:history.back();>No data to display</a>'."\n";
    }
    logger(3, "Geneated HTML: $HTML");
    logger(3, "x"x50);

    return $HTML;
}

# ------------------------------------------------------------------------------
# ExitPlugin
# Print correct output text and exit this plugin now
# ------------------------------------------------------------------------------
sub ExitPlugin {

    my $refhStruct = shift;

    # --------------------------------------------------------------------
    # when we have UNKNOWN the exit code and the text can
    # be overwritten from the command line with the options
    # -UnknownExit and -UnknownText
    #
    # Example for CRITICAL (code=2):
    #
    # ...itd_check_xxxxx.pl -UnknownExit 2 -UnknownText "Error getting data"
    #
    if ($refhStruct->{ExitCode} == $ERRORS{'UNKNOWN'}) {
        $refhStruct->{ExitCode} = $refhStruct->{UnknownExit};
        $refhStruct->{Text}     = $refhStruct->{UnknownText};
    }

    print $refhStruct->{Text};
    if ($ghOptions{'enableperfdata'} and $basetime and $gPerfdata) {
        print " | ";
        print "$gPerfdata";
    }
    print "\n";

    exit $refhStruct->{ExitCode};
}

# ------------------------------------------------------------------------
# various functions reporting plugin information & usages
# ------------------------------------------------------------------------
sub print_usage () {
  print <<EOUS;

  Usage:

    * basic usage:
      $PROGNAME [-vvvvv] -H <hostname/IP> [-h <host alias>] [-2] [-C <community string>]
        [--exclude <globally excluded interface list>] [--include <globally included interface list>]
        [--warning <warning load prct>,<warning pkterr/s>,<warning pktdiscard/s>]
        [--critical <critical load prct>,<critical pkterr/s>,<critical pktdiscard/s>]
        [--track-property <tracked property list>] [--include-property <property tracking interface inclusion list>]
        [--exclude-property <property tracking interface exclusion list>] [--warning-property <warning property change counter>]
        [--critical-property <critical property change counter>] [-r] [-f]

    * advanced usage:
      $PROGNAME [-vvvvv] [-t <timeout>] -H <hostname/IP> [-h <host alias>] [-2] [-C <community string>]
        [--domain <transport domain>] [-P <port>] [--nodetype <type>]
        [-e <globally excluded interface list>] [-i <globally included interface list>]
        [--et <traffic tracking interface exclusion list>] [--it <traffic tracking interface inclusion list>]
        [--wt <warning load prct>,<warning pkterr/s>,<warning pktdiscard/s>]
        [--ct <critical load prct>,<critical pkterr/s>,<critical pktdiscard/s>]
        [--tp <property list>] [--ip <property tracking interface inclusion list>] [--ep <property tracking interface exclusion list>]
        [--wp <warning property change counter>] [--cp <critical property change counter>] [-r] [-f]
        [--cachedir <caching directory>] [--statedir <state files directory>] [--(no)duplex] [--(no)stp]
        [--(no)vlan] [--accessmethod <method>[:<target>]] [--htmltabledir <system path to html interface tables>]
        [--htmltableurl <url to html interface tables>] [--htmltablelinktarget <target window>] [-d <delta>] [--ifs <separator>]
        [--cache <cache retention time>] [--reseturl <url to reset cgi>] [--(no)ifloadgradient]
        [--(no)human] [--(no)snapshot] [-g <grapher solution>] [--grapherurl <url to grapher>]
        [--portperfunit <unit>] [--perfdataformat <format>] [--outputshort]
        [--snmp-timeout <timeout>] [--snmp-retries <number of retries>]
        [--(no)configtable] [--(no)unixsnmp]

    * other usages:
      $PROGNAME [--help | -?]
      $PROGNAME [--version | -V]
      $PROGNAME [--showdefaults | -D]

  General options:
    -?, --help
        Show this help page
    -V, --version
        Plugin version
    -v, --verbose
        Verbose mode. Can be specified multiple times to increase the verbosity (max 3 times).
    -D, --showdefaults
        Print the option default values

  Plugin common options:
    -H, --hostquery (required)
        Specifies the remote host to poll.
    -h, --hostdisplay (optional)
        Specifies the hostname to display in the HTML link.
        If omitted, it takes the value of 
         * NAGIOS_HOSTNAME evironment variable in case environment macros are enabled in 
           nagios.cfg/icinga.cfg
         * or if not the value of the hostquery variable (-H, --hostquery)
    -r, --regexp (optional)
        Interface names and property names for some other options will be interpreted as
        regular expressions.
    --outputshort (optional)
        Reduce the verbosity of the plugin output. If used, the plugin only returns
        general counts (nb ports, nb changes,...). This is close to the way the
        previous versions of the plugin was working.
        In this version of the plugin, by default the plugin returns
         + general counts (nb ports, nb changes,...)
         + what changes has been detected
         + what interface(s) suffer(s) from high load.

  Global interface inclusions/exclusions
    -e, --exclude (optional)
        * Comma separated list of interfaces globally excluded from the monitoring.
          Excluding an interface from that tracking is usually done for the interfaces that
          we don't want any tracking. For exemple:
           + virtual interfaces
           + loopback interfaces
        * Excluded interfaces are represented by black overlayed rows in the interface table
        * Excluding an interface globally will also exclude it from any tracking (traffic and
          property tracking).
    -i, --include (optional)
        * Comma separated list of interfaces globally included in the monitoring.
        * By default, all the interfaces are included.
        * There are some cases where you need to include an interface which is part
          of a group of previously excluded interfaces.

  Traffic checks (load & packet errors/discards)
    --et, --exclude-traffic (optional)
        * Comma separated list of interfaces excluded from traffic checks
          (load & packet errors/discards). Can be used to exclude:
           + interfaces known as problematic (high traffic load)
        * Excluded interfaces are represented by a dark grey (css dependent)
          cell style in the interface table
    --it, --include-traffic (optional)
        * Comma separated list of interfaces included for traffic checks
          (load & packet errors/discards).
        * By default, all the interfaces are included.
        * There are some case where you need to include an interface which is part
          of a group of previously excluded interfaces.
    --wt, --warning-traffic, --warning (optional)
        * Interface traffic load percentage leading to a warning alert
        * Format:
           --warning-traffic <load%>,<pkterr/s>,<pktdiscard/s>
           ex: --warning-traffic 70,100,100
    --ct, --critical-traffic, --critical (optional)
        * Interface traffic load percentage leading to a critical alert
        * Format:
           --critical-traffic <load%>,<pkterr/s>,<pktdiscard/s>
           ex: --critical-traffic 95,1000,1000

  Property checks (interface property changes)
    --tp, --track-property (optional)
        List of tracked properties. Values can be:
          Standard:
            * 'ifAlias'            : the interface alias
            * 'ifAdminStatus'      : the administrative status of the interface
            * 'ifOperStatus'       : the operational status of the interface
            * 'ifSpeedReadable'    : the speed of the interface
            * 'ifStpState'         : the Spanning Tree state of the interface
            * 'ifDuplexStatus'     : the operation mode of the interface (duplex mode)
            * 'ifVlanNames'        : the vlan on which the interface was associated
            * 'ifIpInfo'           : the ip configuration for the interface
          Netscreen specific:
            * 'nsIfZone'           : the security zone name an interface belongs to
            * 'nsIfVsys'           : the virtual system name an interface belongs to
            * 'nsIfMng'            : the management protocols permitted on the interface
        Default is 'ifOperStatus' only
        Exemple: --tp='ifOperStatus,nsIfMng'
    --ep, --exclude-property (optional)
        * Comma separated list of interfaces excluded from the property tracking.
        * For the 'ifOperStatus' property, the exclusion of an interface is usually
          done when the interface can be down for normal reasons (ex: interfaces
          connected to printers sometime in standby mode)
        * Excluded interfaces are represented by a dark grey (css dependent)
          cell style in the interface table
    --ip, --include-property (optional)
        * Comma separated list of interfaces included in the property tracking.
        * By default, all the interfaces that are tracked are included.
        * There are some case where you need to include an interface which is part
          of a group of previously excluded interfaces.
    --wp, --warning-property (optional)
        Number of property changes before leading to a warning alert
    --cp, --critical-property (optional)
        Number of property changes before leading to a critical alert

  Snmp options:
    -C, --community (required)
        Specifies the snmp v1 community string. Other snmp versions are not
        implemented yet.
    -2, --v2c
        Use snmp v2c
    -l, --login=LOGIN ; -x, --passwd=PASSWD
        Login and auth password for snmpv3 authentication
        If no priv password exists, implies AuthNoPriv
    -X, --privpass=PASSWD
        Priv password for snmpv3 (AuthPriv protocol)
    -L, --protocols=<authproto>,<privproto>
        <authproto> : Authentication protocol (md5|sha : default md5)
        <privproto> : Priv protocole (des|aes : default des)
    --domain
        SNMP transport domain. Can be: udp (default), tcp, udp6, tcp6.
        Specifying a transport domain also change the default port according
        to that selected transport domain. Use --port to overwrite the port.
    -P, --port=PORT
        SNMP port (Default 161)
    --64bits
        Use SNMP 64 bits counters
    --max-repetitions=integer
        Available only for snmp v2c/v3. Increasing this value may enhance snmp query performances
        by gathering more results at one time. Setting it to 1 would disable the use of get-bulk.
    --snmp-timeout
        Define the Transport Layer timeout for the snmp queries (default is 2s). Value can be from
        1 to 60. Note: multiply it by the snmp-retries+1 value to calculate the complete timeout.
    --snmp-retries
        Define the number of times to retry sending a SNMP message (default is 2). Value can be
        from 0 to 20.
    --(no)unixsnmp
        Use unix snmp utilities for snmp requests (table/bulk requests), in place of perl bindings
        Default is to use perl bindings

  Graphing options:
    -f, --enableperfdata (optional)
        Enable port performance data, default is port perfdata disabled
    --perfdataformat (optional)
        Define which performance data will be generated.
        Can be:
         * full : generated performance data include plugin related stats,
                  interface status, interface load stats, and packet error stats
         * loadonly : generated performance data include plugin related stats,
                      interface status, and interface load stats
         * globalonly : generated performance data include only plugin related stats
        Default is full.
        'loadonly' should be used in case of too many interfaces and consequently too much performance
        data which cannot fit in the nagios plugin output buffer. By default, its size is 8k and
        can be extended by modifying MAX_PLUGIN_OUTPUT_LENGTH in the nagios sources.
    --perfdatadir (optional)
        When specified, the performance data are also written directly to a file, in the specified
        location. Please use the same hostname as in Icinga/Nagios for -H or -h.
    --perfdataservicedesc (optional)
        Specify additional parameters for output performance data to PNP
        (only used when using --perfdatadir and --grapher pnp4nagios). Optional in case environment 
        macros are enabled in nagios.cfg/icinga.cfg
    -g, --grapher (optional)
        Specify the used graphing solution.
        Can be pnp4nagios, nagiosgrapher or netwaysgrapherv2.
    --grapherurl (optional)
        Graphing system url. Default values are:
        Ex: /pnp4nagios
    --portperfunit (optional)
        In/out traffic in perfdata could be reported in octets or in bits.
        Possible values: bit or octet

  Other options:
    --cachedir (optional)
        Sets the directory where snmp responses are cached.
    --statedir (optional)
        Sets the directory where the interface states are stored.
    --(no)duplex (optional)
        Add the duplex mode property for each interface in the interface table.
    --(no)stp (optional)
        Add the stp state property for each interface in the interface table.
        BE AWARE that it based on the dot1base mib, which is incomplete in specific cases:
         * Cisco device using pvst / multiple vlan stp
    --(no)vlan (optional)
        Add the vlan attribution property for each interface in the interface table.
    --nodetype (optional)
        Specify the node type, for specific information to be printed / specific oids to be used
        Values can be: standard (default), cisco, hp, netscreen
    --accessmethod (optional)
        Access method for a shortcut to the host in the HTML page.
        Format is : <method>[:<target>]
        Where method can be: ssh, telnet, http or https.
        Ex: --accessmethod="http:http://my_netapp_fas/na_admin"
        Can be called multiple times for multiple shortcuts.
    --htmltabledir (optional)
        Specifies the directory in the file system where HTML interface table are stored.
    --htmltableurl (optional)
        Specifies the URL by which the interface table are accessible.
    --htmltablelinktarget (optional)
        Specifies the windows or the frame where the [details] link will load the generated html page.
        Possible values are: _blank, _self, _parent, _top, or a frame name. Default is _self. For
        exemple, can be set to _blank to open the details view in a new window.
    --delta | -d (optional)
        Set the delta used for interface throuput calculation. In seconds.
    --ifs (optional)
        Input field separator. The specified separator is used for all options allowing
        a list to be specified.
    --cache (optional)
        Define the retention time of the cached data. In seconds.
    --reseturl (optional)
        Specifies the URL to the tablereset program.
    --(no)ifloadgradient (optional)
        Enable color gradient from green over yellow to red for the load percentage
        representation. Default is enabled.
    --(no)human (optional)
        Translate bandwidth usage in human readable format (G/M/K bps). Default is enabled.
    --(no)snapshot (optional)
        Force the plugin to run like if it was the first launch. Cached data will be
        ignored. Default is enabled.
    --timeout (optional)
        Define the global timeout limit of the plugin. By default, the nagios plugin
        global timeout is taken (default is 15s)
    --css (optional)
        Define the css stylesheet used by the generated html files.
        Can be: classical, icinga, icinga-alternate1 or nagiosxi
    --config (optional)
        Specify a config file to load.
    --(no)configtable
        Enable/disable configuration table on the generated HTML page. Also, if enabled, the
        globally excluded interfaces are not shown in the interface table anymore (interesting in
        case of lots of excluded interfaces)
        Enabled by default.

  Notes:
    - For options --exclude, --include, --exclude-traffic, --include-traffic, --track-property,
      --exclude-property, --include-property and --accessmethod:
       * These options can be used multiple times, the lists of interfaces/properties
         will be concatenated.
       * The separator can be changed using the --ifs option.
    - The manual is included in this plugin in pod format. To read it, use the perldoc
      program (if not installed, just intall the perl-doc package):
      perldoc ./check_interface_table_v3t.pl

EOUS

}
sub print_defaults () {
  print "\nDefault option values:\n";
  print "----------------------\n\n";
  print "General options:\n\n";
  print Dumper(\%ghOptions);
  print "\nSnmp options:\n\n";
  print Dumper(\%ghSNMPOptions);
}
sub print_help () {
  print "Copyright (c) 2009-2012 Yannick Charton\n\n";
  print "\n";
  print "  Check various statistics of network interfaces \n";
  print "\n";
  print_usage();
  support();
}
sub print_revision ($$) {
  my $commandName = shift;
  my $pluginRevision = shift;
  $pluginRevision =~ s/^\$Revision: //;
  $pluginRevision =~ s/ \$\s*$//;
  print "$commandName ($pluginRevision)\n";
  print "This nagios plugin comes with ABSOLUTELY NO WARRANTY. You may redistribute\ncopies of this plugin under the terms of the GNU General Public License version 3 (GPLv3).\n";
}
sub support () {
  my $support='Send email to tontonitch-pro@yahoo.fr if you have questions\nregarding the use of this plugin. \nPlease include version information with all correspondence (when possible,\nuse output from the -V option of the plugin itself).\n';
  $support =~ s/@/\@/g;
  $support =~ s/\\n/\n/g;
  print $support;
}

# ------------------------------------------------------------------------
# command line options processing
# ------------------------------------------------------------------------
sub check_options () {
    my %commandline = ();
    my %configfile = ();
    my @params = (
        #------- general options --------#
        'help|?',
        'verbose|v+',
        'showdefaults|D',                        # print all option default values
        #--- plugin specific options ----#
        'hostquery|H=s',
        'hostdisplay|h=s',
        'cachedir=s',                           # caching directory
        'statedir=s',                           # interface table state directory
        'accessmethod=s@',                      # access method for the link to the host in the HTML page
        'htmltabledir=s',                       # interface table HTML directory
        'htmltableurl=s',                       # interface table URL location
        'htmltablelinktarget=s',                # interface table link target attribute for the plugin output
        'alias-matching!',                      # interface exclusion/inclusion also check against ifAlias (not only ifDescr)
        'exclude|e=s@',                         # list of interfaces globally excluded
        'include|i=s@',                         # list of interfaces globally included
        'community=s',                          # community string
        'delta|d=i',                            # interface throuput delta in seconds
        'ifs=s',                                # input field separator
        'usemacaddr',                           # use mac address (if unique) instead of index when reformatting duplicate interface description
        'cache=s',                              # cache timer
        'reseturl=s',                           # URL to tablereset program
        'duplex!',                              # Add Duplex mode info for each interface
        'stp!',                                 # Add Spanning Tree Protocol info for each interface
        'vlan!',                                # Add vlan attribution info for each interface
        'nodetype=s',                           # Specify the node type, for specific information to be printed / specific oids to be used
                                                #  Values can be: standard (default), cisco, catalyst, hp, netscreen
        'ifloadgradient!',                      # color gradient from green over yellow to red representing the load percentage
        'human!',                               # translate bandwidth usage in human readable format (G/M/K bps)
        'snapshot!',
        'version|V',
        'regexp|r',
        'timeout=i',                            # global plugin timeout
        'outputshort',                          # the plugin only returns general counts (nb ports, nb changes,...).
                                                # By default, the plugin returns general counts (nb ports, nb changes,...)
                                                # + what changes has been detected
        #------ traffic tracking --------#
        'exclude-traffic|et=s@',                # list of interfaces excluded from the load tracking
        'include-traffic|it=s@',                # list of interfaces included in the load tracking
        'warning-traffic|warning|wt=s',
        'critical-traffic|critical|ct=s',
        #------ property tracking -------#
        'track-property|tp=s@',                 # list of tracked properties
        'exclude-property|ep=s@',               # list of interfaces excluded from the property tracking
        'include-property|ip=s@',               # list of interfaces included in the property tracking
        'warning-property|wp=i',
        'critical-property|cp=i',
        #------- performance data -------#
        'enableperfdata|f',                     # enable port performance data, default is port perfdata disabled
        'portperfunit=s',                       # bit|octet: in/out traffic in perfdata could be reported in octets or in bits
        'perfdataformat=s',                     # define which performance data will be generated.
        'perfdatadir=s',                        # where to write perfdata files directly for netways nagios grapher v1
        'perfdataservicedesc=s',                # servicedescription in Nagios/Icinga so that PNP uses the correct name for its files
        'grapher|g=s',                          # graphing system. Can be pnp4nagios, nagiosgrapher or netwaysgrapherv2
        'grapherurl=s',                         # graphing system url. By default, this is adapted for pnp4nagios standard install: /pnp4nagios
        #-------- SNMP related ----------#
        'domain=s',                             # SNMP transport domain
        'port|P=i',                             # SNMP port
        'community|C=s',                        # Specifies the snmp v1/v2c community string.
        'v2c|2',                                # Use snmp v2c
        'login|l=s',                            # Login for snmpv3 authentication
        'passwd|x=s',                           # Password for snmpv3 authentication
        'privpass|X=s',                         # Priv password for snmpv3 (AuthPriv protocol)
        'protocols|L=s',                        # Format: <authproto>,<privproto>;
        'snmp-timeout=i',                       # timeout for snmp requests
        'snmp-retries=i',                       # retries for snmp requests
        '64bits',                               # Use 64 bits counters
        'max-repetitions=i',                    # Max-repetitions tells the get-bulk command to attempt up to M get-next operations to retrieve the remaining objects.
        'unixsnmp!',                            # Use unix snmp utilities in some cases, in place of perl bindings
        #------- other features ---------#
        'config=s',                             # Configuration file
        'css=s',                                # Used css stylesheet
        'ifdetails',                            # Link to query interface info - not yet functional
        'configtable!',                         # Enable or not the configuration table
        #------- deprecated options ---------#
        'cisco',                                # replaced by --nodetype=cisco
        );

    # gathering commandline options
    if (! GetOptions(\%commandline, @params)) {
        print_help();
        exit $ERRORS{UNKNOWN};
    }
    # deprecated options
    if (exists $commandline{cisco}) {
        logger(0, "Option \"--cisco\" is deprecated. Use \"--nodetype=cisco\" instead.");
        exit $ERRORS{"UNKNOWN"};
    }

    #====== Configuration hashes ======#
    # Default values: general options
    %ghOptions = (
        #------- general options --------#
        'help'                      => 0,
        'verbose'                   => 0,
        'showdefaults'              => 0,
        #--- plugin specific options ----#
        'hostquery'                 => '',
        'hostdisplay'               => '',
        'cachedir'                  => "/tmp/.ifCache",
        'statedir'                  => "/tmp/.ifState",
        'accessmethod'              => undef,
        'htmltabledir'              => "/usr/local/interfacetable_v3t/share/tables",
        'htmltableurl'              => "/interfacetable_v3t/tables",
        'htmltablelinktarget'       => "_self",
        'alias-matching'            => 0,
        'exclude'                   => undef,
        'include'                   => undef,
        'delta'                     => 600,
        'ifs'                       => ',',
        'usemacaddr'                => 0,
        'cache'                     => 3600,
        'reseturl'                  => "/interfacetable_v3t/cgi-bin",
        'duplex'                    => 0,
        'stp'                       => 0,
        'vlan'                      => 0,
        'nodetype'                  => "standard",
        'ifloadgradient'            => 1,
        'human'                     => 1,
        'snapshot'                  => 0,
        'regexp'                    => 0,
        'timeout'                   => $TIMEOUT,
        'outputshort'               => 0,
        #------ traffic tracking --------#
        'exclude-traffic'           => undef,
        'include-traffic'           => undef,
        'warning-traffic'           => "151,1000,1000",
        'critical-traffic'          => "171,5000,5000",
        #------ property tracking -------#
        'track-property'            => ['ifOperStatus'],     # can be compared: ifAdminStatus, ifOperStatus, ifSpeedReadable, ifDuplexStatus, ifVlanNames, ifIpInfo
        'exclude-property'          => undef,
        'include-property'          => undef,
        'warning-property'          => 0,
        'critical-property'         => 0,
        #------- performance data -------#
        'enableperfdata'            => 0,
        'portperfunit'              => "bit",
        'perfdataformat',           => "full",
        'perfdatadir',              => undef,
        'perfdataservicedesc',      => undef,
        'grapher'                   => "pnp4nagios",
        'grapherurl'                => "/pnp4nagios",
        #------- other features ---------#
        'config'                    => '',
        'css'                       => "icinga",             # Used css stylesheet. Can be classical, icinga or nagiosxi.
        'ifdetails'                 => 0,
        'configtable'               => 1
    );
    # Default values: snmp options
    %ghSNMPOptions = (
        'domain'                    => "udp",
        'port'                      => 161,
        'community'                 => "public",
        'version'                   => "1",         # 1, 2c, 3
        'login'                     => "",
        'passwd'                    => "",
        'privpass'                  => "",
        'authproto'                 => "md5",       # md5, sha
        'privproto'                 => "des",       # des, aes
        'timeout'                   => 2,
        'retries'                   => 2,
        '64bits'                    => 0,
        'max-repetitions'           => undef,
        'unixsnmp'                  => 0
    );

    # process config file first, as command line options overwrite them
    if (exists $commandline{'config'}) {
        parseConfigFile("$commandline{'config'}", \%configfile);
        foreach my $key (keys %configfile) {
            if (exists $ghOptions{$key}) {
                $ghOptions{$key} = "$configfile{$key}";
            }
        }
    }

    ### mandatory commandline options: hostquery
    # applying commandline options

    #------- general options --------#
    if (exists $commandline{verbose}) {
        $ghOptions{'verbose'} = $commandline{verbose};
        setLoglevel($commandline{verbose});
    }
    if (exists $commandline{version}) {
        print_revision($PROGNAME, $REVISION);
        exit $ERRORS{OK};
    }
    if (exists $commandline{help}) {
        print_help();
        exit $ERRORS{OK};
    }
    if (exists $commandline{showdefaults}) {
        print_defaults();
        exit $ERRORS{OK};
    }

    #--- plugin specific options ----#
    if (exists $commandline{ifs}) {
        $ghOptions{'ifs'} = "$commandline{ifs}";
    }
    if (exists $commandline{usemacaddr}) {
        $ghOptions{'usemacaddr'} = "$commandline{usemacaddr}";
    }
    if (! exists $commandline{'hostquery'}) {
        logger(0, "host to query not defined (-H)\n");
        print_help();
        exit $ERRORS{UNKNOWN};
    } else {
        $ghOptions{'hostquery'} = "$commandline{hostquery}";
    }
    if (exists $commandline{hostdisplay}) {
        $ghOptions{'hostdisplay'} = "$commandline{hostdisplay}";
    } elsif (defined $ENV{'NAGIOS_HOSTNAME'} and $ENV{'NAGIOS_HOSTNAME'} ne "") {
        $ghOptions{'hostdisplay'} = $ENV{'NAGIOS_HOSTNAME'};
    } elsif (defined $ENV{'ICINGA_HOSTNAME'} and $ENV{'ICINGA_HOSTNAME'} ne "") {
        $ghOptions{'hostdisplay'} = $ENV{'ICINGA_HOSTNAME'};
    } else {
        $ghOptions{'hostdisplay'} = "$commandline{hostquery}";
    }
    if (exists $commandline{cachedir}) {
        $ghOptions{'cachedir'} = "$commandline{cachedir}";
    }
    $ghOptions{'cachedir'} = "$ghOptions{'cachedir'}/$commandline{hostquery}";
    -d "$ghOptions{'cachedir'}" or MyMkdir ("$ghOptions{'cachedir'}");
    if (exists $commandline{statedir}) {
        $ghOptions{'statedir'} = "$commandline{statedir}";
    }
    $ghOptions{'statedir'} = "$ghOptions{'statedir'}/$commandline{hostquery}";
    -d "$ghOptions{'statedir'}" or MyMkdir ("$ghOptions{'statedir'}");

    # accessmethod(s)
    if (exists $commandline{'accessmethod'}) {
        my @tmparray = split("$ghOptions{ifs}", join("$ghOptions{ifs}",@{$commandline{'accessmethod'}}));
        my %tmphash = ();
        for (@tmparray) {
            my ($method,$target) = split /:/,$_,2;
            if ($method =~ /^ssh$|^telnet$|^http$|^https$/) {
                $tmphash{"$method"} = ($target) ? "$target" : "$method://$ghOptions{'hostquery'}";
            } else {
                logger(0, "Specified accessmethod \"$method\" (in \"$_\") is not valid. Valid accessmethods are: ssh, telnet, http and https.");
                exit $ERRORS{"UNKNOWN"};
            }
        }
        $ghOptions{'accessmethod'} = \%tmphash;
    }

    # organizing global interface exclusion/inclusion
    if (exists $commandline{'exclude'}) {
        my @tmparray = split("$ghOptions{ifs}", join("$ghOptions{ifs}",@{$commandline{'exclude'}}));
        $ghOptions{'exclude'} = \@tmparray;
    }
    if (exists $commandline{'include'}) {
        my @tmparray = split("$ghOptions{ifs}", join("$ghOptions{ifs}",@{$commandline{'include'}}));
        $ghOptions{'include'} = \@tmparray;
    }
    if (exists $commandline{'alias-matching'}) {
        $ghOptions{'alias-matching'} = $commandline{'alias-matching'};
    }
    if (exists $commandline{regexp}) {
        $ghOptions{'regexp'} = $commandline{regexp};
    }
    if (exists $commandline{htmltabledir}) {
        $ghOptions{'htmltabledir'} = "$commandline{htmltabledir}";
    }
    if (exists $commandline{htmltableurl}) {
        $ghOptions{'htmltableurl'} = "$commandline{htmltableurl}";
    }
    if (exists $commandline{htmltablelinktarget}) {
        $ghOptions{'htmltablelinktarget'} = "$commandline{htmltablelinktarget}";
    }
    if (exists $commandline{delta}) {
        $ghOptions{'delta'} = "$commandline{delta}";
    }
    if (exists $commandline{cache}) {
        $ghOptions{'cache'} = "$commandline{cache}";
    }
    # ------------------------------------------------------------------------
    # extract two cache timers out of the commandline --cache option
    #
    # Examples:
    #   --cache 150              $gShortCacheTimer = 150 and $Long... = 300
    #   --cache 3600,86400       $gShortCacheTimer = 3600 and $Long...= 86400
    #
    # ------------------------------------------------------------------------
    # only one number entered
    if ($ghOptions{'cache'} =~ /^\d+$/) {
        $gShortCacheTimer = $ghOptions{'cache'};
        $gLongCacheTimer  = 2*$gShortCacheTimer;
    # two numbers entered - separated with a comma
    } elsif ($ghOptions{'cache'} =~ /^\d+$ghOptions{'ifs'}\d+$/) {
        ($gShortCacheTimer,$gLongCacheTimer) = split (/$ghOptions{'ifs'}/,$ghOptions{'cache'});
    } else {
        logger(0, "Wrong cache timer specified\n");
        exit $ERRORS{"UNKNOWN"};
    }
    logger(1, "Set ShortCacheTimer = $gShortCacheTimer and LongCacheTimer = $gLongCacheTimer");
    if (exists $commandline{reseturl}) {
        $ghOptions{'reseturl'} = "$commandline{reseturl}";
    }
    if (exists $commandline{ifloadgradient}) {
        $ghOptions{'ifloadgradient'} = $commandline{ifloadgradient};
    }
    if (exists $commandline{human}) {
        $ghOptions{'human'} = $commandline{human};
    }
    if (exists $commandline{duplex}) {
        $ghOptions{'duplex'} = $commandline{duplex};
    }
    if (exists $commandline{stp}) {
        $ghOptions{'stp'} = $commandline{stp};
    }
    if (exists $commandline{nodetype}) {
        if ($commandline{nodetype} =~ /^cisco$|^hp$|^netscreen$/i) {
            $ghOptions{'nodetype'} = $commandline{nodetype};
        } else {
            logger(0, "Specified nodetype \"$commandline{nodetype}\" is not valid. Valid nodetypes are: cisco, hp, netscreen.");
            exit $ERRORS{"UNKNOWN"};
        }
    }
    if (exists $commandline{vlan} and $ghOptions{'nodetype'} =~ /^cisco$|^hp$/i) {
        $ghOptions{'vlan'} = $commandline{vlan};
    } else {
        $ghOptions{'vlan'} = 0;
    }
    if (exists $commandline{snapshot}) {
        $ghOptions{'snapshot'} = $commandline{snapshot};
    }
    if (exists $commandline{timeout}) {
        $ghOptions{'timeout'} = $commandline{timeout};
        $TIMEOUT = $ghOptions{'timeout'};
    }
    if (exists $commandline{outputshort}) {
        $ghOptions{'outputshort'} = 1;
    }

    #------ property tracking -------#
    # organizing tracked fields
    if (exists $commandline{'track-property'}) {
        my @tmparray = split("$ghOptions{ifs}", join("$ghOptions{ifs}",@{$commandline{'track-property'}}));
        $ghOptions{'track-property'} = \@tmparray;
    }
    # organizing excluded/included interfaces for property(ies) tracking
    if (exists $commandline{'exclude-property'}) {
        my @tmparray = split("$ghOptions{ifs}", join("$ghOptions{ifs}",@{$commandline{'exclude-property'}}));
        $ghOptions{'exclude-property'} = \@tmparray;
    }
    if (exists $commandline{'include-property'}) {
        my @tmparray = split("$ghOptions{ifs}", join("$ghOptions{ifs}",@{$commandline{'include-property'}}));
        $ghOptions{'include-property'} = \@tmparray;
    }
    if (exists $commandline{'warning-property'}) {
        $ghOptions{'warning-property'} = $commandline{'warning-property'};
    }
    if (exists $commandline{'critical-property'}) {
        $ghOptions{'critical-property'} = $commandline{'critical-property'};
    }

    #------ traffic tracking -------#
    # organizing excluded/included interfaces for traffic tracking
    if (exists $commandline{'exclude-traffic'}) {
        my @tmparray = split("$ghOptions{ifs}", join("$ghOptions{ifs}",@{$commandline{'exclude-traffic'}}));
        $ghOptions{'exclude-traffic'} = \@tmparray;
    }
    if (exists $commandline{'include-traffic'}) {
        my @tmparray = split("$ghOptions{ifs}", join("$ghOptions{ifs}",@{$commandline{'include-traffic'}}));
        $ghOptions{'include-traffic'} = \@tmparray;
    }
    if (exists $commandline{'warning-traffic'}) {
        $ghOptions{'warning-traffic'} = "$commandline{'warning-traffic'}";
    }
    my @tmparray2=split(/,/,$ghOptions{'warning-traffic'});
    if ($#tmparray2 != 2) {
        logger(0, "3 warning levels needed! (i.e. --warning-traffic 151,0,0)");
        exit $ERRORS{"UNKNOWN"};
    }
    $ghOptions{'warning-load'} = $tmparray2[0];
    $ghOptions{'warning-load'} =~ s/%$//;
    $ghOptions{'warning-pkterr'} = $tmparray2[1];
    $ghOptions{'warning-pktdiscard'} = $tmparray2[2];
    if (exists $commandline{'critical-traffic'}) {
        $ghOptions{'critical-traffic'} = "$commandline{'critical-traffic'}";
    }
    my @tmparray3=split(/,/,$ghOptions{'critical-traffic'});
    if ($#tmparray3 != 2) {
        logger(0, "3 critical levels needed! (i.e. --critical-traffic 171,0,0)");
        exit $ERRORS{"UNKNOWN"};
    }
    $ghOptions{'critical-load'} = $tmparray3[0];
    $ghOptions{'critical-load'} =~ s/%$//;
    $ghOptions{'critical-pkterr'} = $tmparray3[1];
    $ghOptions{'critical-pktdiscard'} = $tmparray3[2];

    #------- performance data -------#
    if (exists $commandline{grapher}) {
        if ($commandline{grapher} =~ /^pnp4nagios$|^nagiosgrapher$|^netwaysgrapherv2$/i) {
            $ghOptions{'grapher'} = "$commandline{grapher}";
        } else {
            logger(0, "Specified grapher solution \"$commandline{grapher}\" is not valid. Valid graphers are: pnp4nagios, nagiosgrapher, netwaysgrapherv2.");
            exit $ERRORS{"UNKNOWN"};
        }
    }
    if (exists $commandline{grapherurl}) {
        $ghOptions{'grapherurl'} = "$commandline{grapherurl}";
    }
    if (exists $commandline{enableperfdata}) {
        $ghOptions{'enableperfdata'} = 1;
    }
    if (exists $commandline{portperfunit}) {
        if ($commandline{portperfunit} =~ /^bit$|^octet$/i) {
            $ghOptions{'portperfunit'} = "$commandline{portperfunit}";
        } else {
            logger(0, "Specified performance data unit \"$commandline{portperfunit}\" is not valid. Valid units are: bit, octet.");
            exit $ERRORS{"UNKNOWN"};
        }
    }
    if (exists $commandline{perfdataformat}) {
        if ($commandline{perfdataformat} =~ /^full$|^loadonly$|^generalonly$/i) {
            $ghOptions{'perfdataformat'} = "$commandline{perfdataformat}";
        } else {
            logger(0, "Specified performance data format \"$commandline{perfdataformat}\" is not valid. Valid formats are: full, loadonly, generalonly.");
            exit $ERRORS{"UNKNOWN"};
        }
    }
    if (exists $commandline{perfdatadir}) {
        $ghOptions{'perfdatadir'} = "$commandline{perfdatadir}";
    }
    if (exists $commandline{perfdataservicedesc}) {
        $ghOptions{'perfdataservicedesc'} = "$commandline{perfdataservicedesc}";
    } elsif (defined $ENV{'NAGIOS_SERVICEDESC'} and $ENV{'NAGIOS_SERVICEDESC'} ne "") {
        $ghOptions{'perfdataservicedesc'} = $ENV{'NAGIOS_SERVICEDESC'};
    }  elsif (defined $ENV{'ICINGA_SERVICEDESC'} and $ENV{'ICINGA_SERVICEDESC'} ne "") {
        $ghOptions{'perfdataservicedesc'} = $ENV{'ICINGA_SERVICEDESC'};
    }
    if ($ghOptions{'enableperfdata'} and $ghOptions{'grapher'} eq "nagiosgrapher" and not defined $ghOptions{'perfdatadir'}) {
        logger(0, "As you use nagiosgrapher as the grapher solution, you need to specify a perfdatadir");
        exit $ERRORS{"UNKNOWN"};
    }

    #------- other features ---------#
    if (exists $commandline{css}) {
        $ghOptions{'css'} = "$commandline{css}";
    }
    if (! -e "$ghOptions{'htmltabledir'}/../css/$ghOptions{'css'}.css") {
        logger(0, "Could not find the css file: $ghOptions{'htmltabledir'}/../css/$ghOptions{'css'}.css");
        exit $ERRORS{"UNKNOWN"};
    }
    if (exists $commandline{ifdetails}) {
        $ghOptions{'ifdetails'} = 1;
    }
    if (exists $commandline{configtable}) {
        $ghOptions{'configtable'} = $commandline{configtable};
    }

    #-------- SNMP related ----------#
    if ((exists $commandline{'login'} || exists $commandline{'passwd'}) && (exists $commandline{'community'} || exists $commandline{'v2c'})) {
        logger(0, "Can't mix snmp v1,2c,3 protocols!\n");
        print_usage();
        exit $ERRORS{"UNKNOWN"};
    }
    if (exists $commandline{v2c}) {
        $ghSNMPOptions{'version'} = "2";
    } elsif (exists $commandline{login}) {
        $ghSNMPOptions{'version'} = "3";
    } else {
        $ghSNMPOptions{'version'} = "1";
    }
    if (exists $commandline{'max-repetitions'}) {
        $ghSNMPOptions{'max-repetitions'} = $commandline{'max-repetitions'};
    }
    if (exists $commandline{domain}) {
        if ($commandline{domain} =~ /^udp$|^tcp$|^udp6$|^tcp6$/i) {
            $ghSNMPOptions{'domain'} = "$commandline{domain}";
            if ($commandline{domain} eq "udp") {
                $ghSNMPOptions{'port'} = 161;
            } elsif ($commandline{domain} eq "tcp") {
                $ghSNMPOptions{'port'} = 1161;
            } elsif ($commandline{domain} eq "udp6") {
                $ghSNMPOptions{'port'} = 10161;
            } elsif ($commandline{domain} eq "tcp6") {
                $ghSNMPOptions{'port'} = 1611;
            }
        } else {
            logger(0, "Specified transport domain \"$commandline{domain}\" is not valid. Valid domains are: udp, tcp, udp6, tcp6.");
            exit $ERRORS{"UNKNOWN"};
        }
    }
    if (exists $commandline{port}) {
        $ghSNMPOptions{'port'} = "$commandline{port}";
    }
    if (exists $commandline{community}) {
        $ghSNMPOptions{'community'} = "$commandline{community}";
    }
    if (exists $commandline{login}) {
        $ghSNMPOptions{'login'} = "$commandline{login}";
    }
    if (exists $commandline{passwd}) {
        $ghSNMPOptions{'passwd'} = "$commandline{passwd}";
    }
    if (exists $commandline{privpass}) {
        $ghSNMPOptions{'privpass'} = "$commandline{privpass}";
    }
    if (exists $commandline{'protocols'}) {
        if (!exists $commandline{'login'}) {
            logger(0, "Put snmp V3 login info with protocols!\n");
            print_usage();
            exit $ERRORS{"UNKNOWN"};
        }
        my @v3proto=split(/,/,$commandline{'protocols'});
        if ((defined ($v3proto[0])) && ($v3proto[0] ne "")) {
            $ghSNMPOptions{'authproto'} = $v3proto[0];
        }
        if (defined ($v3proto[1])) {
            $ghSNMPOptions{'privproto'} = $v3proto[1];
        }
        if ((defined ($v3proto[1])) && (!exists $commandline{'privpass'})) {
            logger(0, "Put snmp V3 priv login info with priv protocols!\n");
            print_usage();
            exit $ERRORS{"UNKNOWN"};
        }
    }
    if (exists $commandline{'snmp-timeout'}) {
        $ghSNMPOptions{'timeout'} = "$commandline{'snmp-timeout'}";
    }
    if (exists $commandline{'snmp-retries'}) {
        $ghSNMPOptions{'retries'} = "$commandline{'snmp-retries'}";
    }
    if (exists $commandline{'64bits'}) {
        $ghSNMPOptions{'64bits'} = 1;
    }
    # Check snmpv2c or v3 with 64 bit counters
    if ( $ghSNMPOptions{'64bits'} && $ghSNMPOptions{'version'} == 1) {
        logger(0, "Can't get 64 bit counters with snmp version 1\n");
        print_usage();
        exit $ERRORS{"UNKNOWN"}
    }
    if ($ghSNMPOptions{'64bits'}) {
        if (eval "require bigint") {
            use bigint;
        } else {
            logger(0, "Need bigint module for 64 bit counters\n");
            print_usage();
            exit $ERRORS{"UNKNOWN"}
        }
    }
    if (exists $commandline{'unixsnmp'}) {
        $ghSNMPOptions{'unixsnmp'} = $commandline{'unixsnmp'};
    }

    # print the options in command line, and the resulting full option hash
    logger(5, "commandline: \n".Dumper(\%commandline));
    logger(5, "general options: \n".Dumper(\%ghOptions));
    logger(5, "snmp options: \n".Dumper(\%ghSNMPOptions));
}

__END__

=head1 NAME

  check_interface_table_v3t.pl - nagios plugin for monitoring network devices

=head1 SYNOPSIS

=head2 Basic usage

  check_interface_table_v3t.pl [-vvv] -H <hostname/IP> [-h <host alias>] [-2] [-C <community string>]
    [--exclude <globally excluded interface list>] [--include <globally included interface list>]
    [--warning <warning load prct>,<warning pkterr/s>,<warning pktdiscard/s>]
    [--critical <critical load prct>,<critical pkterr/s>,<critical pktdiscard/s>]
    [--track-property <tracked property list>] [--include-property <property tracking interface inclusion list>]
    [--exclude-property <property tracking interface exclusion list>] [--warning-property <warning property change counter>]
    [--critical-property <critical property change counter>] [-r] [-f]

=head2 Advanced usage

  check_interface_table_v3t.pl [-vvv] [-t <timeout>] -H <hostname/IP> [-h <host alias>] [-2] [-C <community string>]
    [--domain <transport domain>] [--P <port>]
    [-e <globally excluded interface list>] [-i <globally included interface list>]
    [--et <traffic tracking interface exclusion list>] [--it <traffic tracking interface inclusion list>]
    [--wt <warning load prct>,<warning pkterr/s>,<warning pktdiscard/s>]
    [--ct <critical load prct>,<critical pkterr/s>,<critical pktdiscard/s>]
    [--tp <property list>] [--ip <property tracking interface inclusion list>] [--ep <property tracking interface exclusion list>]
    [--wp <warning property change counter>] [--cp <critical property change counter>] [-r] [-f]
    [--cachedir <caching directory>] [--statedir <state files directory>] [--(no)duplex] [--(no)stp]
    [--(no)vlan] [--nodetype] [--accessmethod <method>] [--htmltabledir <system path to html interface tables>]
    [--htmltableurl <url to html interface tables>] [-d <delta>] [--ifs <separator>]
    [--cache <cache retention time>] [--reseturl <url to reset cgi>] [--(no)ifloadgradient]
    [--(no)human] [--(no)snapshot] [-g <grapher solution>] [--grapherurl <url to grapher>]
    [--portperfunit <unit>] [--perfdataformat <format>] [--outputshort]

=head1 DESCRIPTION

=head2 Introduction

B<check_interface_table_v3t.pl> is a Nagios(R) plugin that allows you to monitor
the network devices of various nodes (e.g. router, switch, server) without knowing
each interface in detail. Only the hostname (or ip address) and the snmp community
string are required.

  Simple Example:
  C<# check_interface_table_v3t.pl -H server1 -C public>

  Output:
  C<<a href="/nagios/interfacetable/server1-Interfacetable.html">total 3 interface(s)</a>>

The output is a HTML link to a web page which shows all interfaces in a table.

=head2 Theory of operation

The perl program polls the remote machine in a highly efficient manner.
It collects all data from all interfaces and stores these data into "state" files in a
specific directory (ex: /tmp/.ifState).

Each host (option -H) holds one text file:
  # ls /tmp/.ifState/*.txt
  /tmp/.ifState/server1-Interfacetable.txt

When the program is called twice, three times, etc. it retrieves new
information from the network and compares it against this state file.


B<!!!!! ALL FOLLOWING DOCUMENTATION ARE OBSOLETE AND NEED TO BE UPDATED !!!!!>
B<!!!!! ALL FOLLOWING DOCUMENTATION ARE OBSOLETE AND NEED TO BE UPDATED !!!!!>
B<!!!!! ALL FOLLOWING DOCUMENTATION ARE OBSOLETE AND NEED TO BE UPDATED !!!!!>


=head1 PREREQUISITS

This chapter describes the operating system prerequisits to get this program
running:

=head2 net-snmp software

The B<snmpwalk> command must be available on your operating system.

Test your snmpwalk output with a command like:

  # snmpwalk -Oqn -v 1 -c public router.itdesign.at | head -3
    .1.3.6.1.2.1.1.1.0 Cisco IOS Software, 2174 Software Version 11.7(3c), REL.
    SOFTWARE (fc2)Technical Support: http://www.cisco.com/techsupport
    Copyright (c) 1986-2005 by Cisco Systems, Inc.
    Compiled Mon 22-Oct-03 9:46 by antonio
    .1.3.6.1.2.1.1.2.0 .1.3.6.1.4.1.9.1.620
    .1.3.6.1.2.1.1.3.0 9:11:09:19.48

  snmpwalk parameters:
    -Oqn -v 1 ............ some noise (please read "man snmpwalk")
    -c public  ........... snmp community string
    router.itdesign.at ... host where you do the snmp queries

B<snmpwalk> is part of the net-snmp suit (http://net-snmp.sourceforge.net/).
Some more unix commands to find it:

  # whereis snmpwalk
  snmpwalk: /usr/bin/snmpwalk /usr/share/man/man1/snmpwalk.1.gz

  # which snmpwalk
  /usr/bin/snmpwalk

  # rpm -qa | grep snmp
  net-snmp-5.3.0.1-25.15

  # rpm -ql net-snmp-5.3.0.1-25.15 | grep snmpwalk
  /usr/bin/snmpwalk
  /usr/share/man/man1/snmpwalk.1.gz

=head2 PERL v5 installed

You need a working perl 5.x installation. Currently we use V5.8.8 under
SUSE Linux Enterprise Server 10 SP1 for development. We know that it works
with other versions, too.

Get your perl version with:
  # perl -V

=head2 PERL modules

=head3 PERL Net::SNMP library

B<Net::SNMP> is the perl's snmp library. Some ideas to see if it is installed:

  For RedHat, Fedora, SuSe:
  # rpm -qa|grep -i perl|grep -i snmp
  perl-Net-SNMP-5.2.0-12.2

  # find /usr -name SNMP.pm
  /usr/lib/perl5/vendor_perl/5.8.8/Net/SNMP.pm

  if it is not installed please check your operating systems packages or install it
  from CPAN: http://search.cpan.org/search?query=Net%3A%3ASNMP&mode=all

=head3 PERL Config::General library

B<Config::General> is used to write all interface information data back to the
file system.

This perl library should be available via the package management tool of your
system distribution.

  For Debian distribution:
  # apt-get install libconfig-general-perl

  CPAN page: http://search.cpan.org/search?query=Config%3A%3AGeneral&mode=all

=head3 PERL Data::Dumper library

B<Data::Dumper> is used to easily dump hashes and arrays in some parts of the debug.

This perl library should be available via the package management tool of your
system distribution.

  For Debian distribution:
  # apt-get install libdata-dump-perl

  CPAN page: http://search.cpan.org/search?query=Data%3A%3ADumper&mode=all

=head3 PERL Getopt::Long library

B<Getopt::Long> is used to handle the commandline options of the plugin.

This perl library should already be available on your system.

  For Debian distribution:
  # apt-get install libdata-dump-perl

  CPAN page: http://search.cpan.org/search?query=Getopt%3A%3ALong&mode=all

=head2 CGI script to reset the interface table

If everything is working fine you need the possibility to reset the interface table.
Often it is necessary that someone changes ip addresses or other properties. These
changes are necessary and you want to update (=reset) the table.

Resetting the table means to delete the state file (ex: in /tmp/.ifState).

Withing this kit you find an example shell script which does this job for you.
To install this cgi script do the following:

  1) Copy the cgi script to the correct location on your WEB server
  # cp -i InterfaceTableReset_v3t.cgi /usr/local/nagios/sbin

  2) Check permissions
  # ls -l /usr/local/nagios/sbin/InterfaceTableReset_v3t.cgi
  -rwxr-xr-x 1 nagios nagios 2522 Nov 16 13:14 /usr/local/nagios/sbin/Inte...

  3) Prepare the /etc/sudoers file so that the web server's account can call
  the cgi script (as shell script)
    Suse linux based distrib:
        # visudo
        wwwrun ALL=(ALL) NOPASSWD: /usr/local/nagios/sbin/InterfaceTableReset_v3t.cgi
    Debian based distrib:
        # visudo
        www-data ALL=(ALL) NOPASSWD: /usr/local/nagios/sbin/InterfaceTableReset_v3t.cgi

The above unix commands are tested with apache2 installed and nagios v3 compiled
into /usr/local/nagios.

Note: please send me an email if you have information from other operating systems
on these details. I will update the documentation.

=head2 Configure Nagios 3.x to display HTML links in Plugin Output

In Nagios version 3.x there is html output per default disabled.

  1) Edit cgi.cfg and set this option to zero
      escape_html_tags=0

cgi.cfg is located in your configuration directory. (ex: /usr/local/nagios/etc)

=head1 OPTIONS

=head2 Basic options

=head3 --help | -?

 Show this help page

=head3 --man | --manual

 Print the manual

=head3 --version | -V

 Plugin version

=head3 --verbose | -v

 Verbose mode. Can be specified multiple times to increase the verbosity (max 3 times).

=head3 --showdefaults | -D

 Print the option default values

=head3 --hostquery | -H (required)

 No default
 Specifies the remote host to poll.

=head3 --hostdisplay | -h (optional)

 Default = <hostquery>
 Specifies the remote host to display in the HTML link.
 If omitted, it defaults to the host with -H

 Example:
    check_interface_table_v3t.pl -h firewall -H srv-itd-99.itdesign.at -C mkjz65a

 This option is maybe useful when you want to poll a host with -H and display
 another link for it.

=head3 --community (required)

 Default = public
 Specifies the snmp v1 community string. Other snmp versions are not
 implemented yet.

=head3 --exclude | -e (optional)

 Comma separated list of interfaces excluded from load tracking (main check). Can
 be used to exclude:
  * virtual or loopback interfaces
  * flapping interfaces

 Example:
    ... -H router -C public -e Dialer0,BVI20,FastEthernet0

 Note: if --regexp is not used, the interface descriptions must match exactly!

=head3 --include | -i (optional)

 Comma separated list of interfaces included in load tracking (main check). By
 default, all the interfaces are included. But there are some case where you
 need to include an interface which is part of a group of previously excluded
 interfaces.

 Example:
    ... -H router -C public -i FastEthernet0,FastEthernet1

 Note: if --regexp is not used, the interface descriptions must match exactly!

=head3 --track | -t (optional)

 List of tracked properties. Values can be:
  * 'ifAdminStatus'      : the administrative status of the interface
  * 'ifOperStatus'       : the operational status of the interface
  * 'ifSpeedReadable'    : the speed of the interface
  * 'ifDuplexStatus'     : the operation mode of the interface (duplex mode)
  * 'ifVlanNames'        : the vlan on which the interface was associated
  * 'ifIpInfo'           : the ip configuration for the interface
 Default is 'ifOperStatus'
 Note: interface traffic load(s) is not considered as a property, and is always
       monitored following defined thresholds.

=head3 --regexp | -r (optional)

 Interface names and property names for some other options will be interpreted as
 regular expressions.

=head3 --warning | -w (optional)

 Must be a positive integer number. Changes in the interface table are compared
 against this threshold.
 Example:
    ... -H server1 -C public -w 1
 Leads to WARNING (exit code 1) when one or more interface properties were
 changed.

=head3 --critical | -c (optional)

 Must be a positive integer number. Changes in the interface table are compared
 against this threshold.
 Example:
    ... -H server1 -C public -c 1
 Leads to CRITICAL (exit code 2) when one or more interface properties were
 changed.

=head3 --warning-load | -W (optional)

 Interface traffic load percentage leading to a warning alert

=head3 --critical-load | -C (optional)

 Interface traffic load percentage leading to a critical alert

=head3 --enableperfdata | -f (optional)

 Enable performance data, default is port perfdata disabled

=head3 --grapher (optional)

 Specify the used graphing solution.
 Can be pnp4nagios, nagiosgrapher or netwaysgrapherv2.

=head3 --outputshort (optional)

 Reduce the verbosity of the plugin output. If used, the plugin only returns
 general counts (nb ports, nb changes,...). This is close to the way the
 previous versions of the plugin was working.

 In this version of the plugin, by default the plugin returns
   + general counts (nb ports, nb changes,...)
   + what changes has been detected
   + what interface(s) suffer(s) from high load.

=head2 Advanced options

=head3 --cachedir (optional)

 Sets the directory where snmp responses are cached.

=head3 --statedir (optional)

 Sets the directory where the interface states are stored.

=head3 --vlan (optional)

 Add the vlan attribution property for each interface in the interface table.

=head3 --nodetype (optional)

 Add cisco specific info in the information table.

=head3 --accessmethod (optional)

 Access method for the link to the host in the HTML page.
 Can be ssh or telnet.

=head3 --htmltabledir (optional)

 Specifies the directory in the file system where HTML interface table are stored.
=head3 --htmltableurl (optional)

 Specifies the URL by which the interface table are accessible.
=head3 --delta | -d (optional)

 Set the delta used for interface throuput calculation. In seconds.
=head3 --ifs (optional)

 Input field separator. The specified separator is used for all options allowing
 a list to be specified.

=head3 --cache (optional)

 Define the retention time of the cached data. In seconds.

=head3 --reseturl (optional)

 Specifies the URL to the tablereset program.

=head3 --(no)ifloadgradient (optional)

 Enable color gradient from green over yellow to red for the load percentage
 representation.

=head3 --(no)human (optional)

 Translate bandwidth usage in human readable format (G/M/K bps).

=head3 --(no)snapshot (optional)

 Force the plugin to run like if it was the first launch. Cached data will be
 ignored.

=head3 --timeout (optional)

 Define the timeout limit of the plugin.

=head3 --exclude-property | -E (optional)

 Comma separated list of interfaces excluded from the property tracking.

=head3 --include-property | -I (optional)

 Comma separated list of interfaces included in the property tracking.
 By default, all the interfaces that are included in the load tracking (-i option) are
 also included in the property tracking.
 Also, there are some case where you need to include an interface which is part of a
 group of previously excluded interfaces. In this case, you need to proviously exclude
 all/part the interfaces using -E, then includes some of them back using -I.

=head3 --portperfunit (optional)

 In/out traffic in perfdata could be reported in octets or in bits.
 Possible values: bit or octet

=head3 --grapherurl (optional)

 Graphing system url. Default values are:
  * pnp4nagios       : /pnp4nagios
  * nagiosgrapher    : /nagios/cgi-bin (?)
  * netwaysgrapherv2 : /nagios/cgi-bin (?)

=head1 ATTENTION - KNOWN ISSUES

=head2 Interaction with Nagios

If you use this program with Nagios then it is typically called in the "nagios"
users context. This means that the user "nagios" must have the correct permissions
to write all required files into the filesystem (see chapter "Theory of operation").

=head2 Reset table

The "reset table button" is the next challenge. Clicking in the web browser means to
trigger the "InterfaceTableReset_v3t.cgi" script which then tries to remove the state
file.

 If this does not work please check the following:

 * correct directory and permissions of InterfaceTableReset_v3t.cgi
 * correct entry in the /etc/sudoers file
 * look at /var/log/messages or /var/log/secure to see what "sudo" calls
 * look at the web servers access and error log files

=head2 /tmp cleanup

Some operating systems clean up the /tmp directory during reboot (I know that
OpenBSD does this). This leads to the problem that the /tmp/.ifState directory
is deleted and you loose your interface information states. The solution for
this is to set the -StateDir <directory> switch from command line.

=head2 umask on file and directory creation

This program generats some files and directories on demand:

  /tmp/.ifState ... directory with table states
  /tmp/.ifCache ... directory with caching data
  /usr/local/nagios/share/interfacetable ... directory with html tables

To avoid file system conflicts we simply set the umask to 0000 so that all
files and directories are created with everyone read/write permissions.

If you don't want this - change the $UMASK variable in this program and
test it very carefully - especially under the account where the program is
executed.

  Example:

  # su - nagios
  nagios> check_interface_table_v3t.pl -H <host> -C <community string> -Debug 1

=head1 LICENSE

This program was demonstrated by ITdesign during the Nagios conference in
Nuernberg (Germany) on the 12th of october 2007. Normally it is part of the
commercial suite of monitoring add ons around Nagios from ITdesign.
This version is free software under the terms and conditions of GPLV3.

Netways had adapted it to include performance data and calculate bandwidth
usage, making some features mentioned in the COMMERCIAL version available in
the GPL version (version 2 of the plugin)
available in this GPL version.

The 3rd version (by Yannnick Charton) (version v3t, to make the distinction w
ith other possible v3 versions) brings lots of enhancements and new features
to the v2 version. See the README and CHANGELOG files for more information.

Copyright (C) [2007]  [ITdesign Software Projects & Consulting GmbH]
Copyright (C) [2009]  [Netways GmbH]
Copyright (C) [2009-2012]  [Yannick Charton]

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public License along
with this program; if not, see <http://www.gnu.org/licenses/>.

=head1 CONTACT INFORMATION

 Yannick Charton
 Email: tontonitch-pro@yahoo.fr
 Website: www.tontonitch.com

=cut

# vi: set ts=4 sw=4 expandtab :
