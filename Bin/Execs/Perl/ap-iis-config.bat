@rem = '--*-Perl-*--
@echo off
if "%OS%" == "Windows_NT" goto WinNT
perl -x -S "%0" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
:WinNT
perl -x -S %0 %*
if NOT "%COMSPEC%" == "%SystemRoot%\system32\cmd.exe" goto endofperl
if %errorlevel% == 9009 echo You do not have Perl in your PATH.
if errorlevel 1 goto script_failed_so_exit_with_non_zero_val 2>nul
goto endofperl
@rem ';
#!perl
#line 15

use strict;
use warnings;

=head1 NAME

ap-iis-config - Configure IIS for ActivePerl

=head1 SYNOPSIS

  ap-iis-config add all
  ap-iis-config delete all
  ap-iis-config list sites

  ap-iis-config add map --ext .cgi --type isapi
  ap-iis-config delete map --ext .plex

  ap-iis-config add vdir --site 1 --name Sample --path C:\www\samples
  ap-iis-config delete vdir --site 2 --name "My Site"

=head1 DESCRIPTION

B<ap-iis-config> is a utility to setup IIS for use with ActivePerl.
It creates and deletes script mappings and virtual directories.

Currently B<ap-iis-config> only supports numeric site ids.  Use the
B<ap-iis-config list sites> command to map site ids to descriptive
names.  The site id 0 can be used to add or remove script mappings
from the webserver root itself (inherited by all websites).

=head1 COMMANDS

All commands support the B<--verbose> option in addition to the
command-specific options listed below.

=cut

use File::Basename qw(dirname);
use Win32;

our $VERSION = 1.0;

our $debug    = grep /^-+debug$/, @ARGV;
our $verbose  = grep /^-+verbose$/, @ARGV;
@ARGV = grep !/^-+(debug|verbose)$/, @ARGV;

Win32::SetChildShowWindow(0);

if (@ARGV && $ARGV[0] eq "msi") {
    unless (-t STDERR) {
	$verbose = 1;
	if (my $tmp = $ENV{TEMP} || $ENV{TMP}) {
	    open(STDERR, ">> $tmp/ActivePerlInstall.log");
	    warn "\n\n", scalar localtime, "\n";
	}
    }
}

unless (Win32::IsAdminUser()) {
    die "$0: Must run with administrator privileges.\n";
}

########################################################################

our $iis_version;

# Don't trust $Config{binexp}; instead strip '\perl.exe' from $^X
our $binexp = dirname($^X);
our $perl_root = dirname($binexp);
our $iis_dir = Win32::GetFolderPath(Win32::CSIDL_SYSTEM) . "\\inetsrv";
our $appcmd = "$iis_dir\\appcmd.exe";
our $inetinfo = "$iis_dir\\inetinfo.exe";
if (-f $inetinfo) {
    ($iis_version) = Win32::GetFileVersion($inetinfo);
}
elsif (-f $appcmd) {
    $iis_version = 7;
}
elsif (@ARGV >= 2 && "$ARGV[0]$ARGV[1]" eq "addall") {
    # IIS may not be installed at all; we know how to install IIS 7
    my(undef, $major, undef, undef, $id) = Win32::GetOSVersion();
    $iis_version = 7 if $id == 2 && $major >= 6;
}
unless ($iis_version) {
    die "Cannot determine IIS version.\n";
}

########################################################################

usage() unless @ARGV >= 2;

our $action = shift;
our $object = shift;

# (Undocumented) "msi" command for MSI installer internal use only
if ($action eq "msi") {
    warn "$0 $action $object @ARGV\n" unless -t STDERR;

    # We don't want to die() and exit with a non-0 exit code
    # under *any* circumstances!
    if ($object eq "uninstall") {
	eval { delete_all() };
    }
    else {
	my($cgi,$isapi,$perlex,$vdir) = map uc, @ARGV;

	my @args;
	push(@args, '--cgi')    if $cgi    eq "YES";
	push(@args, '--isapi')  if $isapi  eq "YES";
	push(@args, '--perlex') if $perlex eq "YES";
	exit 0 unless @args > 0 || $vdir eq "YES";

	# The PerlEx sample directory will not be created if we
	# specify the --site ids explicitly.
	push(@args, qw(--site 0 --site 1)) unless $vdir eq "YES";

	eval { add_all(@args) };
    }
    warn $@ if $@;
    exit 0;
}

if ($action eq "list") {
    die "Object for 'list' must be 'sites'\n"
	unless $object eq "sites";
    list_sites();
    exit 0;
}

usage("Unknown command '$action'\n")
    unless $action =~ /^(add|delete)$/;

usage("Object for '$action' must be one of 'all', 'map', or 'vdir'")
    unless $object =~ /^(all|map|vdir)$/;

########################################################################

do {
    no strict "refs";
    &{"${action}_${object}"}()
};
exit 0;

########################################################################

sub usage {
    require Pod::Usage;
    my %option = (
	-message => shift,
	-exitval => 1,
	-verbose => 1,
    );
    if (defined $action && defined $object) {
	$option{-verbose} = 99;
	$option{-sections} = ["COMMANDS/$action $object"];
    }
    Pod::Usage::pod2usage(\%option);
}

sub get_options {
    require Getopt::Long;
    $SIG{__WARN__} = \&usage;
    Getopt::Long::GetOptions(@_);
    $SIG{__WARN__} = 'DEFAULT';
}

sub appcmd ($) {
    my $cmd = "$appcmd $_[0]";
    warn ">>> $cmd\n" if $debug;

    my $res = `$cmd`;
    $res =~ s,\r,,g;
    warn "$res\n" if $debug;

    if ($cmd =~ /-xml/) {
	require XML::Simple;
	$res = XML::Simple::XMLin($res, ForceArray => 1);
    }
    return $res;
}

########################################################################

=head2 add all

The B<ap-iis-config add all> command will add all applicable script
mappings to both the root configuration and to the default website.

  ap-iis-config add all [--site ID]* [--cgi] [--isapi] [--perlex]

The B<--cgi> option will add a C<*.pl> mapping for F<perl.exe>.  The
B<--isapi> option will add a C<*.plx> mapping for F<perlis.dll>, the
I<Perl for ISAPI plugin>.  The B<--perlex> option will add both
C<*.plex> and C<*.aspl> mappings for the PerlEx plugin.

When no options are specified then all available script mappings will
be configured.

If no B<--site> is specified, then the script mappings will be added
to both the root configuration and to the default web site (sites 0
and 1).  In that case B<ap-iis-config> will also add a virtual
F<PerlEx> directory to the default web site that will point to the
PerlEx samples directory (if PerlEx has been installed).

On Windows Vista and later B<ap-iis-config add all> will attempt to
install IIS7 including the optional CGI and ISAPI modules, as
required.  For older versions of Windows IIS must be installed
manually before running this command.  If IIS is not yet installed,
then B<ap-iis-config> does nothing.

=cut

sub add_all {
    local @ARGV = @_ ? @_ : @ARGV;

    my $default;

    get_options(
	"site"   => \my @site,
	"cgi"    => \my $cgi,
	"isapi"  => \my $isapi,
	"perlex" => \my $perlex,
    );

    $cgi = $isapi = $perlex = 1 unless $cgi || $isapi || $perlex;
    unless (@site) {
	$default = 1;
	@site = (0, 1);
    }

    # Make sure IIS has the required modules installed
    if ($iis_version >= 7) {
	install_iis(-cgi => $cgi, -isapi => ($isapi || $perlex));
	unless (-f $appcmd) {
	    die "Could not install IIS.\n";
	}
    }

    for my $site (@site) {
	if ($cgi) {
	    add_map(-site => $site, -ext => ".pl");
	}
	if ($isapi) {
	    add_map(-site => $site, -ext => ".plx");
	}
	if ($perlex) {
	    add_map(-site => $site, -ext => ".aspl");
	    add_map(-site => $site, -ext => ".plex");
	}
    }

    if ($default && $perlex) {
	# Create virtual directory in default site for PerlEx samples
	add_vdir(-site => 1, -path => "$perl_root\\eg\\PerlEx");
    }
}

=head2 delete all

B<ap-iis-config delete all> will remove all Perl script mappings and
virtual directories.

  ap-iis-config delete all [--site ID]*

If the B<--site> option is not specified then mappings and directories
are removed from the root configuration and default web site only
(sites 0 and 1).  The B<--site> option also supports the B<*> wildcard
argument, which will remove the settings from all sites.

See the description of the B<delete map> and B<delete vdir> for the
definition of I<Perl script mapping> and I<Perl virtual directory>.

=cut

sub delete_all {
    local @ARGV = @_ ? @_ : @ARGV;

    my @site;

    get_options(
	"site"  => \@site,
    );

    @site = (0,1) unless @site;
    if (@site == 1 && $site[0] eq "*") {
	@site = (0, keys %{get_sites()});
    }

    for my $site (@site) {
	delete_map(-site => $site, -ext => "*");
	delete_vdir(-site => $site, -name => "*") if $site;
    }
}

=head2 add map

B<ap-iis-config add map> adds a script mapping to one or more web
sites.

  ap-iis-config add map --ext EXT [--site ID] [--type cgi|isapi|perlex]

By default the mapping is added to the the root configuration (site 0).

The default B<--type> depends on the script extension EXT: for C<--ext
.plx> the default is C<--type isapi>, for C<--ext .plex> and C<--ext
.aspl> the default is C<--type perlex>.  For all other extensions the
default is C<--type cgi>.

=cut

sub add_map {
    local @ARGV = @_ ? @_ : @ARGV;
    my $fail_ok = defined((caller(1))[3]);

    my $ext = ".pl";
    my $type;
    my $site = 0;
    my $dir = "";
    my @verbs;

    get_options(
	"ext=s"   => \$ext,
	"type=s"  => \$type,
	"site=i"  => \$site, # site-ids only for now
#	"dir=s"   => \$dir,
	"verbs=s" => \@verbs, # undocumented for now
    );

    unless ($type) {
	$type = "cgi";
	$type = "isapi"  if $ext eq ".plx";
	$type = "perlex" if $ext eq ".plex" or $ext eq ".aspl";
    }
    unless ($type =~ /^(cgi|isapi|perlex)$/) {
	die "--type '$type' must be one of 'cgi', 'isapi', or 'perlex'.\n";
    }

    my($name,$path,$proc);
    if ($type eq "cgi") {
	$name = "Perl CGI for $ext";
	$path = qq($binexp\\perl.exe);
	$proc = $path =~ /\s/ ? qq("$path") : $path;
	$proc = qq("$proc") if $proc =~ /\s/;
	$proc = qq($proc "%s" %s);
    }
    elsif ($type eq "isapi") {
	$name = "Perl ISAPI for $ext";
	$proc = "$binexp\\perlis.dll";
    }
    elsif ($type eq "perlex") {
	$name = "PerlEx for $ext";
	($proc) = glob("$binexp\\perlex*.dll");
    }

    $path ||= $proc;
    unless (-f $path) {
	return if $fail_ok;
	die "Cannot create '$type' type mapping: '$path' not found.\n";
    }

    unless (@verbs) {
	# In IIS version 4.0 and earlier, the syntax was to list excluded verbs
	# rather than included verbs. In version 5.0, if no verbs are listed, a
	# value of "all verbs" is assumed.
	@verbs = $iis_version < 5 ? qw(PUT DELETE) : qw(GET HEAD POST);
    }

    my $verbs = join(',', map { split /,/ } @verbs);

    if ($iis_version <= 6) {
	my $server = get_site_object($site, $dir, $fail_ok);
	return unless $server;

	# 1 The script is allowed to run in directories given Script
	#   permission. If this value is not set, then the script can only be
	#   executed in directories that are flagged for Execute permission.
	# 4 The server attempts to access the PATH_INFO portion of the URL, as a
	#   file, before starting the scripting engine. If the file can't be
	#   opened, or doesn't exist, an error is returned to the client.
	my $flags = 5;

	my @list = grep { !/^\Q$ext,\E/ } @{$server->{ScriptMaps}};
	$server->{ScriptMaps} = [@list, "$ext,$proc,$flags,$verbs"];
	if ($verbose) {
	    warn "Scriptmaps:\n";
	    warn "  $_\n" for @{$server->{ScriptMaps}};
	    warn "\n";
	}
	$server->SetInfo(); # save!

	# Add Web Server Extension entry
	if ($iis_version == 6) {
	    my $server = get_site_object(0, "", undef);
	    # WebSvcExtRestrictionList entries contain
	    # "AllowDenyFlag,ExtensionPhysicalPath,UIDeletableFlag,GroupID,Description"
	    my @list = @{$server->{WebSvcExtRestrictionList}};
	    # XXX avoid duplicate entries?
	    $server->{WebSvcExtRestrictionList} = [@list, "1,$proc,1,PERL,$name Extension"];
	    $server->SetInfo();
	}
    }
    elsif ($iis_version >= 7) {
	my $module_name = $type eq "cgi" ? "CgiModule" : "IsapiModule";
	unless (get_iis_modules()->{$module_name}) {
	    die "The prerequisite '$module_name' is not installed.\n";
	}

	my $site_name = get_site_name($site);
	unless (defined $site_name) {
	    return if $fail_ok;
	    die "Site '$site' not found.\n";
	}

	$ext =~ s/^\./*./; # ".pl" => "*.pl"

	unlock_site($site);

	# Delete mapping for $name because it is a unique key
	my $cmd;
	$cmd  = "set config ";
	$cmd .= qq("$site_name" ) if $site_name;
	$cmd .= qq(/section:system.webServer/handlers "/-[name='$name']");
	appcmd $cmd;

	# Delete all mappings for $ext because a previous mapping might have
	# used a different name (e.g. remap .pl to CGI instead of ISAPI).
	delete_map(-site => $site, -ext => $ext);

	# Quote "-characters for the sake of cmd.exe commandline parsing
	$proc =~ s/"/\\"/g;

	$cmd  = "set config ";
	$cmd .= qq("$site_name" ) if $site_name;
	$cmd .= "/section:system.webServer/handlers ";
	$cmd .= qq("/+[);
	$cmd .= "name='$name'";
	$cmd .= ",path='$ext'";
	$cmd .= ",verb='$verbs'";
	$cmd .= ",modules='$module_name'";
	$cmd .= ",requireAccess='Script'";
	$cmd .= ",scriptProcessor='$proc'";
	$cmd .= ",resourceType='File'";
	$cmd .= qq(]");
	appcmd $cmd;

	# Remove existing CGI/ISAPI restriction (just in case it
	# currently disabled)
	$cmd  = "set config ";
	$cmd .= qq(/section:system.webServer/security/isapiCgiRestriction );
	$cmd .= qq("/-[path='$proc']");
	appcmd $cmd;

	# Add CGI/ISAPI restriction
	$name =~ s/ for .*//;
	$cmd  = "set config ";
	$cmd .= "/section:system.webServer/security/isapiCgiRestriction ";
	$cmd .= qq("/+[);
	$cmd .= "path='$proc'";
	$cmd .= ",allowed='True'";
	$cmd .= ",description='$name'";
	$cmd .= qq(]");
	appcmd $cmd;

	if ($verbose) {
	    print STDERR "Added map site:$site ";
	    print STDERR "[$site_name] " if $site_name;
	    print STDERR "proc:'$proc' ext:$ext verbs:$verbs\n";
	}
    }
}

=head2 delete map

B<ap-iis-config delete map> removes one or more script mappings from a
website.

  ap-iis-config delete map [--site ID] [--ext EXT]

The default for B<--ext> is C<.pl> and for B<--site> is C<0>.

The B<--ext> option also supports the B<*> wildcard argument, which
will remove all Perl mappings from the site.  A Perl mapping is
defined as one that either maps to a script processor in the current
Perl F<bin> directory, or a script processor that isn't installed
anymore and that matches the regex C<< /\bperl/i >>.

=cut

sub delete_map {
    local @ARGV = @_ ? @_ : @ARGV;
    my $fail_ok = defined((caller(1))[3]);

    my $site = 0;
    my $ext = ".pl";

    get_options(
	"site=i" => \$site, # site-ids only for now
	"ext=s"  => \$ext,
    );

    if ($iis_version <= 6) {
	my $dir = "";
	my $server = get_site_object($site, $dir, $fail_ok);
	return unless $server;

	my @map;
	for (@{$server->{ScriptMaps}}) {
	    my($e,$proc) = split /,/;
	    $proc = $1 if $proc =~ /^"(.*?)"/ or $proc =~ /^(\S*)/;
	    if ($e eq $ext or ($ext eq "*" and $proc =~ /^\Q$binexp\E\\/i or ($proc =~ /\bperl/i && !-f $proc))) {
		print STDERR "Deleted map site:$site ext:$e\n" if $verbose;
		next;
	    }
	    push @map, $_;
	}
	$server->{ScriptMaps} = \@map;
	$server->SetInfo(); # save!
    }
    elsif ($iis_version >= 7) {
	my $site_name = get_site_name($site);
	unless (defined $site_name) {
	    return if $fail_ok;
	    die "Site '$site' not found.\n";
	}

	$ext =~ s/^\./*./; # ".pl" => "*.pl"

	# Remove *all* mappings of $ext that either point to the
	# Perl\bin directory or to a file that no longer exists.
	my $cmd = "list config ";
	$cmd .= qq("$site_name" ) if $site_name;
	$cmd .= "/section:system.webServer/handlers -xml";
	my $xml = appcmd $cmd;
	my $handlers = $xml->{CONFIG}->[0]->{"system.webServer-handlers"}->[0]->{add};

	my $deleted;
	for my $name (keys %$handlers) {
	    my $handler = $handlers->{$name};
	    next unless $ext eq "*" or $ext eq $handler->{path};

	    my $proc = $handler->{scriptProcessor};
	    next unless $proc;
	    $proc = Win32::ExpandEnvironmentStrings($proc);
	    $proc = $1 if $proc =~ /^"(.*?)"/ or $proc =~ /^(\S*)/;
	    next unless $proc =~ /^\Q$binexp\E\\/i or ($proc =~ /\bperl/i && !-f $proc);

	    unlock_site($site);

	    $cmd  = "set config ";
	    $cmd .= qq("$site_name" ) if $site_name;
	    $cmd .= qq(/section:system.webServer/handlers "/-[name='$name']");
	    appcmd $cmd;
	    ++$deleted;

	    if ($verbose) {
		print STDERR "Deleted map site:$site ";
		print STDERR "[$site_name] " if $site_name;
		print STDERR "handler:$name\n";
	    }
	}
	unless ($deleted) {
	    die "No script mappings found for '$ext'.\n" unless $fail_ok;
	}
    }
}

=head2 add vdir

B<ap-iis-config add vdir> will add a virtual directory to a web site.

  ap-iis-config add vdir --path PATH [--side ID] [--name NAME]

The default site ID is 1.  It is not possible to add a virtual
directory to the root configuration (site 0).

The physical PATH must exist.

If the B<--name> option is not specified then the lowest level part of
PATH will be used for the virtual NAME.  For example

  ap-iis-config add vdir --path C:\Perl\eg

is the same as

  ap-iis-config add vdir --site 1 --name eg --path C:\Perl\eg

=cut

sub add_vdir {
    local @ARGV = @_ ? @_ : @ARGV;
    my $fail_ok = defined((caller(1))[3]);
    my $site = 1;
    my $vdir_name;
    my $path;

    get_options(
	"site=i" => \$site, # site-ids only for now
	"name=s" => \$vdir_name,
	"path=s" => \$path, # XXX "dir"?
    );

    die "Cannot add a vdir to site 0.\n" unless $site;
    die "--path not specified.\n" unless defined $path;

    unless (defined $vdir_name) {
	($vdir_name) = $path =~ m,([^\\/]+)$,;
    }

    unless (-d $path) {
	return if $fail_ok;
	die "Directory '$path' not found.\n";
    }

    if ($iis_version <= 6) {
	my $dir = "";
	my $server = get_site_object($site, $dir, $fail_ok);
	return unless $server;

	$server->Delete('IIsWebVirtualDir', $vdir_name);

	my $vdir = $server->Create('IIsWebVirtualDir', $vdir_name);
	unless ($vdir) {
	    return if $fail_ok;
	    die "Can't create vdirr:$vdir_name for site:$site:\n",
		Win32::OLE->LastError, "\n";
	}

	Win32::OLE::with(
	    $vdir,
	    Path                  => $path,
	    AppFriendlyName       => $vdir_name,

	    EnableDirBrowsing     => 0,
	    AccessRead            => 1,
	    AccessWrite           => 0,
	    AccessExecute         => 1,
	    AccessScript          => 0,

	    AccessNoRemoteRead    => 0,
	    AccessNoRemoteScript  => 0,
	    AccessNoRemoteWrite   => 0,
	    AccessNoRemoteExecute => 0,

	    AuthAnonymous         => 1,
	    AuthNTLM              => 1,
	);

	$vdir->AppCreate(1);
	$vdir->SetInfo();

	warn "Added vdir site:$site vdir:$vdir_name path:$path\n" if $verbose;
    }
    elsif ($iis_version >= 7) {
	my $site_name = get_site_name($site);
	unless ($site_name) {
	    return if $fail_ok;
	    die "Site '$site' not found.\n";
	}

	appcmd qq(delete vdir "/vdir.name:$site_name/$vdir_name");
	appcmd qq(add vdir "/app.name:$site_name/" "/path:/$vdir_name" "/physicalPath:$path");
	warn "Added vdir site:$site [$site_name] vdir:$vdir_name path:$path\n" if $verbose;
    }
}

=head2 delete vdir

B<ap-iis-config delete vdir> removes one or more virtual directories
from a web site.

  ap-iis-config delete vdir [--site ID] [--name NAME]

The default site ID is 1.

The B<--name> option also supports the C<*> wildcard argument, which
will remove all virtual Perl directories from the specified site.  A
Perl directory is defined as one whose physical path points anywhere
inside the Perl install directory, for example F<C:\Perl\eg>.

=cut

sub delete_vdir {
    local @ARGV = @_ ? @_ : @ARGV;
    my $fail_ok = defined((caller(1))[3]);

    my $site = 1;
    my $vdir_name;

    get_options(
	"site=i" => \$site, # site-ids only for now
	"name=s" => \$vdir_name,
    );

    die "Cannot delete a vdir from site 0.\n" unless $site;
    die "--name not specified.\n" unless defined $vdir_name;

    if ($iis_version <= 6) {
	my $dir = "";
	my $server = get_site_object($site, $dir, $fail_ok);
	return unless $server;

	my @vdir;
	for (Win32::OLE::in($server)) {
	    next unless lc($_->Class) eq "iiswebvirtualdir";
	    if ($vdir_name eq "*") {
		push(@vdir, $_) if $_->Path =~ /^\Q$perl_root\E\\/i;
	    }
	    elsif ($_->AppFriendlyName eq $vdir_name) {
		push(@vdir, $_);
		last;
	    }
	}
	# XXX warn unless @vdir?
	for my $vdir (@vdir) {
	    my $name = $vdir->AppFriendlyName;
	    $server->Delete("IIsWebVirtualDir", $name);
	    warn "Deleted vdir site:$site vdir:'$name'\n" if $verbose;
	}
    }
    elsif ($iis_version >= 7) {
	my $site_name = get_site_name($site);
	unless ($site_name) {
	    return if $fail_ok;
	    die "Site '$site' not found.\n";
	}

	my @vdir;
	if ($vdir_name eq "*") {
	    my $xml = appcmd qq(list vdir "/app.name:$site_name/" -xml);
	    for my $vdir (@{$xml->{VDIR} || []}) {
		my $path = Win32::ExpandEnvironmentStrings($vdir->{physicalPath});
		push(@vdir, $vdir->{"VDIR.NAME"}) if $path =~ /^\Q$perl_root\E\\/i;
	    }
	}
	else {
	    @vdir = ("$site_name/$vdir_name");
	}
	for my $vdir (@vdir) {
	    appcmd qq(delete vdir "/vdir.name:$vdir");
	    warn "Deleted vdir site:$site [$site_name] vdir:'$vdir'\n" if $verbose;
	}
    }
}

=head2 list sites

B<ap-iis-config list sites> displays a list of all site ids and their
descriptions.

  ap-iis-config list sites

There are no further options for this command.

=cut

sub list_sites {
    if ($iis_version <= 6) {
	my $server = get_site_object(0, "", 0);
	for (Win32::OLE::in($server)) {
	    next unless lc($_->Class) eq "iiswebserver";
	    print "$_->{Name}: $_->{ServerComment}\n";
	}
    }
    elsif ($iis_version >= 7) {
	my $sites = get_sites();
	print "$_: $sites->{$_}\n" for sort {$a <=> $b} keys %$sites;
    }
}

########################################################################

sub get_site_object {
    my($site,$dir,$fail_ok) = @_;
    my $node = "IIS://localhost/W3SVC";
    if ($site) {
	$node .= "/$site/ROOT";
	$node .= "/$dir" if length($dir);
    }

    require Win32::OLE;
    my $server = Win32::OLE->GetObject($node);
    unless (defined($server) || $fail_ok) {
	die "Cannot GetObject($node): ", Win32::OLE->LastError(), "\n";
    }
    return $server;
}

########################################################################

sub install_iis {
    local @ARGV = @_ ? @_ : @ARGV;
    get_options(
	"cgi"    => \my $cgi,
	"isapi"  => \my $isapi,
    );

    my @iis_default_features = qw(
        IIS-WebServerRole
        IIS-WebServer
        IIS-CommonHttpFeatures
        IIS-StaticContent
        IIS-DefaultDocument
        IIS-DirectoryBrowsing
        IIS-HttpErrors
        IIS-HealthAndDiagnostics
        IIS-HttpLogging
        IIS-LoggingLibraries
        IIS-RequestMonitor
        IIS-Security
        IIS-RequestFiltering
        IIS-HttpCompressionStatic
        IIS-WebServerManagementTools
        IIS-ManagementConsole
        WAS-WindowsActivationService
        WAS-ProcessModel
        WAS-NetFxEnvironment
        WAS-ConfigurationAPI
    );

    my @isapi_features = qw(
        IIS-ApplicationDevelopment
        IIS-ASP
        IIS-ISAPIExtensions
    );

    my @cgi_features = qw(
        IIS-ApplicationDevelopment
        IIS-CGI
    );


    my @features;
    # look for iiscore.dll because appcmd.exe is left behind even by a full uninstall
    push(@features, @iis_default_features) unless -f "$iis_dir\\iiscore.dll";

    my $modules = get_iis_modules();
    push(@features, @cgi_features)   if $cgi   && !$modules->{"CgiModule"};
    push(@features, @isapi_features) if $isapi && !$modules->{"IsapiModule"};

    if (@features) {
	warn "Installing IIS 7...\n" if $verbose;
	my $cmd = "start /w pkgmgr /iu:" . join(";", @features);
	warn ">>> $cmd\n" if $debug;
	system($cmd);
	warn "IIS 7 installed.\n" if $verbose;
    }
}

my %site;
sub get_sites {
    unless (keys %site) {
	my $xml = appcmd "list sites -xml";
	%site = map +( $_->{"SITE.ID"}, $_->{"SITE.NAME"} ), @{$xml->{SITE} || []};
    }
    return \%site;
}

sub get_site_name {
    my($site) = @_;
    return "" if $site == 0;
    return get_sites()->{$site};
}

sub get_iis_modules {
    return {} unless -f $appcmd;
    my $xml = appcmd "list config /section:system.webServer/modules -xml";
    return $xml->{CONFIG}->[0]->{"system.webServer-modules"}->[0]->{add};
}

my %unlocked_site;
sub unlock_site {
    my($site) = @_;
    return if $unlocked_site{$site};
    my $site_name = get_site_name($site);
    return unless $site_name;
    appcmd qq(unlock config "$site_name" /section:system.webServer/handlers /commit:apphost);
    $unlocked_site{$site} = 1;
}

__END__
:endofperl
