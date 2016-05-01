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
#!/usr/bin/perl -w
#line 15

use strict;
use ActivePerl::PPM::limited_inc;

use ActivePerl::PPM::Client;
use ActivePerl::PPM::Web qw(web_ua);
use ActivePerl::PPM::Logger qw(ppm_log);
use ActivePerl::PPM::Util qw(is_cpan_package clean_err join_with update_html_toc);

Win32::SetChildShowWindow(0) if defined &Win32::SetChildShowWindow;

$SIG{__WARN__} = sub { ppm_log("WARNING", $_[0]) };

(my $PROGNAME = $0) =~ s,.*[\\/],,;

my $CMD = shift || 'gui';
$CMD = "version" if $CMD eq "--version";

my $BOX_CHARS;
if ($ENV{ACTIVEPERL_PPM_BOX_CHARS}) {
    $BOX_CHARS = $ENV{ACTIVEPERL_PPM_BOX_CHARS};
}
elsif ($^O eq "MSWin32") {
    $BOX_CHARS = "dos" if -t STDOUT;
}
elsif (($ENV{LC_ALL} || $ENV{LC_CTYPE} || $ENV{LANG} || "") =~ /\bUTF-8\b/)  {
    $BOX_CHARS = "unicode";
}

binmode(STDOUT, ":utf8") if ($BOX_CHARS || "") eq "unicode";

if (@ARGV == 1 && ($ARGV[0] =~ /^--?help/ || $ARGV[0] eq "-?")) {
    $ARGV[0] = $CMD;
    $CMD = "help";
}

my $do_cmd = "do_$CMD";
unless (defined &$do_cmd) {
    require Text::Abbrev;
    my @cmds;
    for my $name (keys %main::) {
	push(@cmds, $name) if $name =~ s/^do_//;
    }
    my $abbrev = Text::Abbrev::abbrev(@cmds);
    if (my $cmd = $abbrev->{$CMD}) {
	$do_cmd = "do_$cmd";
    }
    else {
	require Text::Wrap;
	usage(Text::Wrap::wrap("", "  ",
                  "Unrecognized ppm command '$CMD'; try one of " .
                  join_with("or", sort @cmds)
	      )
	);
    }
}

# This must be initialized before PPM::GUI is used
our $ppm = ActivePerl::PPM::Client->new;

our $bad_proxy;
if (my $proxy = $ENV{http_proxy}) {
    if ($proxy =~ m,^[^?:/@]+(:\d+)?$,) {
	# forgiving; allow http_proxy="<host>:<port>"
	$proxy = $ENV{http_proxy} = "http://$proxy";
    }
    require URI;
    $proxy = URI->new($proxy);
    my $scheme = $proxy->scheme;
    unless ($scheme && $scheme =~ /^https?$/ && $proxy->host) {
	$bad_proxy = qq(Unrecognized proxy setting "$ENV{http_proxy}" ignored.\nThe http_proxy environment variable should be of the form "http://proxy.example.com".);
	print STDERR "$bad_proxy\n";
	ppm_log("WARN", $bad_proxy);
	delete $ENV{http_proxy};
    }
}

eval {
    no strict 'refs';
    ppm_log("INFO", "$PROGNAME $CMD" . (@ARGV ? " @ARGV" : ""));
    &$do_cmd;
};
if ($@) {
    ppm_log("ERR", "$PROGNAME $CMD: $@");
    print STDERR "$PROGNAME $CMD failed: " . clean_err($@) . "\n";
    exit 1;
}
else {
    exit;
}

my $USAGE;
sub usage {
    my $msg = shift;
    if ($msg) {
	$msg .= "\n" unless $msg =~ /\n$/;
	print STDERR $msg;
    }
    $USAGE ||= "<cmd> <arg>...";
    print STDERR "Usage:\t$PROGNAME $USAGE\n";
    print STDERR "\tRun '$PROGNAME help" . ($USAGE =~ /^(\w+)/ ? " $1" : "") . "' to learn more.\n";
    exit 1;
}

sub do_gui {
    if ($^O eq "darwin") {
	unless (@ARGV && $ARGV[0] eq "--from-app") {
	    require Config;
	    system("/usr/bin/open", "$Config::Config{binexp}/PPM.app");
	    die "Failed to open PPM.app" if $? != 0;
	    exit;
	}
    }
    eval { require ActivePerl::PPM::GUI; };
    if ($@) {
	my $err = $@;
	if ($err =~ /^no display name/) {
	    ppm_log("ERR", "$PROGNAME $CMD: $err");
	    $err = clean_err($err);

    	    print STDERR <<EOT;
ppm gui failed: $err

The PPM graphical interface can't be used unless the DISPLAY environment
variable is set up.  Either set it to the name of the X server to connect
to or use $PROGNAME as a command line tool.

Run '$PROGNAME help' to learn how to use this program as a command line tool.
EOT
	    exit 1;
	}
	if ($err =~ /^Can't locate (Tkx|Tcl)\.pm\b/) {
	    ppm_log("ERR", "$PROGNAME $CMD: $err");
	    $err = clean_err($err);
	    print STDERR <<EOT;
The PPM graphical interface is not available for this Perl installation.
Run '$PROGNAME help' to learn how to use this program as a command line tool.
EOT
	    exit 1;
	}
	die $err;
    }
}

sub do_log {
    $USAGE = "log [--errors] [<minutes>]";
    my $errors;
    if (@ARGV) {
	require Getopt::Long;
	Getopt::Long::GetOptions(
	     'errors' => \$errors,
        ) || usage();
    }
    usage() if @ARGV > 1 || (@ARGV && $ARGV[0] !~ /^[1-9]\d*\z/);
    my $min = shift(@ARGV) || 1;

    my $logfile = ActivePerl::PPM::Logger::ppm_logger()->logfile;
    open(my $fh, "<", $logfile) || die "Can't open $logfile: $!";

    print "Last ", ($min == 1 ? "minute" : "$min minutes"), " of $logfile";
    print " errors" if $errors;
    print ":\n\n";

    my @t = (localtime time - $min * 60)[reverse 0..5];
    $t[0] += 1900; # year
    $t[1] ++;      # month
    my $ts = sprintf "%04d-%02d-%02dT%02d:%02d:%02d", @t;

    my $count;
    while (<$fh>) {
	if ($_ gt $ts .. 1) {
	    if (!$errors || (/^\S+ <(\d+)>/ && $1 <= 3)) {
		print;
		$count++;
	    }
	}
    }
    unless ($count) {
	print "*** No logged events ***\n";
    }
}

sub do_version {
    if (@ARGV) {
	$USAGE = "version";
	usage("The $CMD command does not take arguments.");
    }
    require ActivePerl::PPM;
    print "ppm $ActivePerl::PPM::VERSION";
    if (defined &ActivePerl::PRODUCT) {
	print " (" . ActivePerl::PRODUCT() . " " . ActivePerl::BUILD() . ")";
    }
    print "\nCopyright (C) 2013 ActiveState Software Inc.  All rights reserved.\n";
}

sub do_help {
    if (@ARGV > 1) {
	$USAGE = "help [<subcommand>]";
	usage();
    }
    my $pod2text = qq("$^X" -MPod::Text -e "Pod::Text->new->parse_from_filehandle");
    my $pager = $ENV{PAGER} || "more";
    open(my $fh, "<", __FILE__) || die "Can't open " . __FILE__ . ": $!";
    if (@ARGV) {
	my $cmd = shift(@ARGV);
	my $foundit;
	while (<$fh>) {
	    if (/^=item B<ppm \Q$cmd\E\b/o) {
		$foundit++;
		last;
	    }
	}
	if ($foundit) {
	    open(my $out, "| $pod2text | $pager");
	    print $out "=over\n\n";
	    print $out $_;
	    my $over_depth = 0;
	    while (<$fh>) {
		last if /^=item B<ppm (?!\Q$cmd\E\b)/o;
		if (/^=back\b/) {
		    last if $over_depth == 0;
		    $over_depth--;
		}
		elsif (/^=over\b/) {
		    $over_depth++;
		}
		print $out $_;
	    }
	    print $out "\n\n=back\n";
	    close($out);
	}
	else {
	    print "Sorry, no help for '$cmd'\n";
	}
    }
    else {
	use ActivePerl::PPM;
	open(my $out, qq(| $pod2text | $pager));
	while (<$fh>) {
	    s/version \d+\S*/version $ActivePerl::PPM::VERSION/ if /^ppm -/;
	    print $out $_;
	}
	close($out);
    }
}

sub do_config {
    $USAGE = "config <name> [<val>]";
    usage() unless @ARGV;
    if (@ARGV == 1) {
	my $key = shift(@ARGV);
	$key = '*' if $key eq "list";
	if ($key =~ /[*?]/) {
	    my @kv = $ppm->config_list($key);
	    unless (@kv) {
		print "*** no configuration options matching '$key' found ***\n";
		return;
	    }
	    while (@kv) {
		my($k, $v) = splice(@kv, 0, 2);
		next if $k =~ /^_/ && !$ENV{ACTIVEPERL_PPM_DEBUG}; # private stuff
		$v = "<undef>" unless defined $v;
		printf "$k = $v\n";
	    }
	    return;
	}
	my $v = $ppm->config_get($key);
	$v = "<undef>" unless defined $v;
	print "$v\n";
    }
    elsif (@ARGV == 2) {
	usage() unless $ARGV[0] =~ /^\w+(\.\w+)*$/;
	$ppm->config_save(@ARGV);
    }
    else {
	usage();
    }
}

sub do_area {
    my $cmd = shift(@ARGV) || "list";
 AGAIN:
    if ($cmd eq "list") {
	$USAGE = "area list [--csv [ <sep> ]] [--no-header]";
	my $show_header = 1;
	my $csv;
	if (@ARGV) {
	    require Getopt::Long;
	    Getopt::Long::GetOptions(
	        'header!' => \$show_header,
                'csv:s' => \$csv,
            ) || usage();
	    usage() if @ARGV;
	}
	require ActiveState::Table;
	my $tab = ActiveState::Table->new;
	$tab->add_field("name");
	$tab->add_field("pkgs");
	$tab->add_field("lib");
	my $default = $ppm->default_install_area;
	for my $area ($ppm->areas) {
	    my $o = $ppm->area($area);
	    my $name = $area;
	    $name = "$name*" if defined($default) && $name eq $default;
	    $name = "($name)" if $o->readonly;
	    my $pkgs = $o->packages;
	    $pkgs = "n/a" unless defined $pkgs;
	    $tab->add_row({
	        name => $name,
                pkgs => $pkgs,
                lib => $o->lib,
            });
	}
	if (defined($csv)) {
	    $csv = "," if $csv eq "";
	    print $tab->as_csv(null => "", field_separator => $csv, show_header => $show_header);
	}
	else {
	    print $tab->as_box(null => "", show_header => $show_header, show_trailer => 0, align => {pkgs => "right"}, box_chars => $BOX_CHARS, max_width => terminal_width());
	}
    }
    elsif ($cmd eq "init") {
	$USAGE = "area init <area>";
	usage() unless @ARGV == 1;
	my $name = shift(@ARGV);
	$ppm->area($name)->initialize;
    }
    elsif ($cmd eq "sync") {
	$USAGE = "area sync [<area>...]";
	for my $area (map $ppm->area($_), @ARGV ? @ARGV : $ppm->areas) {
	    $area->sync_db;
	}
    }
    else {
	$cmd = _try_abbrev("area", $cmd, qw(list sync init));
	goto AGAIN;
    }
}

sub _try_abbrev {
    my $cmd = shift;
    my $subcmd = shift;
    require Text::Abbrev;
    if (my $full_cmd = Text::Abbrev::abbrev(@_)->{$subcmd}) {
	return $full_cmd;
    }
    $USAGE = "$cmd <cmd> <args>";
    require Text::Wrap;
    usage(Text::Wrap::wrap("", "  ",
              "The $cmd command '$subcmd' isn't recognized; try one of " .
              join_with("or", sort @_)
	 )
    );
}

sub do_list {
    my $area_name;
    my $matching;
    my $show_header = 1;
    my $csv;
    my @fields;
    if (@ARGV) {
	$USAGE = "list [<area>] [--field <field>] [--matching <pattern>] [--csv]";
	require Getopt::Long;
	Getopt::Long::GetOptions(
	   'matching=s' => \$matching,
	   'header!' => \$show_header,
           'fields:s' => sub { push(@fields, split(/\s*,\s*/, $_[1])) },
           'csv:s' => \$csv,
        ) || usage();
	$area_name = shift(@ARGV) if @ARGV;
	usage() if @ARGV;
    }

    my $matching_re = glob2re($matching) if defined($matching);
    $matching = (defined $matching) ? " matching '$matching'" : "";

    unless (@fields) {
	# fields to show by default
	push(@fields, "version", "files", "size");
	push(@fields, "area") unless $area_name;
    }
    unshift(@fields, "name") unless grep $_ eq "name", @fields;

    my @areas = ($area_name ? ($area_name) : $ppm->areas);
    my $in = $area_name ? " in '$area_name' area" : "";

    if (@fields == 1) {
	# just list the names
	my @pkgs = map $_->packages, map $ppm->area($_), @areas;
	@pkgs = grep $_ =~ $matching_re, @pkgs if $matching_re;
	goto NO_PKG_INSTALLED unless @pkgs;
	print "$_\n" for sort @pkgs;
    }
    else {
	require ActiveState::Table;
	my $tab = ActiveState::Table->new;
	$tab->add_field($_) for @fields;

	my %field = map { $_ => 1 } @fields;
	my %db_column = map { $_ => 1 } qw(id name version release_date abstract author ppd_uri);
	my @db_fields = grep $db_column{$_}, @fields;
	unshift(@db_fields, "id") if !$field{id} && $field{files} || $field{size};

	for my $area (map $ppm->area($_), @areas) {
	    for my $pkg ($area->packages(@db_fields)) {
		my %row = map {$_ => shift(@$pkg)} @db_fields;
		next if $matching_re && $row{name} !~ $matching_re;
		if ($row{release_date}) {
		    $row{release_date} =~ s/[T ].*//;  # drop time
		}
		if ($field{files} || $field{size}) {
		    if ($field{size}) {
			my @files = $area->package_files($row{id});
			$row{files} = @files if $field{files};

			require ActiveState::DiskUsage;
			my $size = 0;
			$size += ActiveState::DiskUsage::du($_) for @files;
			$size = sprintf "%.0f KB", $size / 1024 unless defined($csv);
			$row{size} = $size;

			unless (defined $csv) {
			    $row{files} ||= "-" if $field{files};
			    $row{size} = "-" unless @files;
			}
		    }
		    else {
			$row{files} = $area->package_files($row{id});
			$row{files} ||= "-" unless defined $csv;
		    }
		}
		$row{area} = $area->name if $field{area};
		delete $row{id} unless $field{id};
		$tab->add_row(\%row);
	    }
	}
	$tab->sort(sub ($$) { my($a, $b) = @_; $a->[0] cmp $b->[0]})
	    if @areas > 1 && $tab->can("sort");

	if (defined $csv) {
	    $csv = "," if $csv eq "";
	    print $tab->as_csv(null => "", field_separator => $csv, show_header => $show_header);
	}
	elsif (my $rows = $tab->rows) {
	    print $tab->as_box(null => "", show_trailer => 0, show_header => $show_header, align => {files => "right", size => "right"}, box_chars => $BOX_CHARS, max_width => terminal_width());
	    if (1) {
		my $s = ($rows == 1) ? "" : "s";
		print " ($rows package$s installed$in$matching)\n";
	    }
	}
	else {
	NO_PKG_INSTALLED:
	    print STDERR "*** no packages installed$in$matching ***\n";
	}
    }
}

sub glob2re {
    my $glob = shift;
    $glob = "*$glob*" unless $glob =~ /[*?]/;
    my $re = quotemeta($glob);
    $re =~ s/\\\?/./g;
    $re =~ s/\\\*/.*/g;
    $re = "^$re\\z";
    $re =~ s/^\^\.\*//;
    $re =~ s/\.\*\\z\z//;
    return "(?i:$re)";
}

sub terminal_width {
    require Term::ReadKey;
    my($w) = -t STDOUT ? Term::ReadKey::GetTerminalSize() : 80;
    $w ||= 80;
    $w-- if $^O eq "MSWin32";  # can't print on last column
    $w;
}

sub do_query {
    $USAGE = "query <pattern>";
    usage() unless @ARGV == 1;
    @ARGV = ("--matching", @ARGV, "--fields", "name,version,abstract,area");
    return do_list();
}

sub do_files {
    $USAGE = "files <pkg>";
    usage() unless @ARGV == 1;
    my $pkg = shift(@ARGV);
    my $foundit;
    for my $area (map $ppm->area($_), $ppm->areas) {
	next unless $area->initialized;
	my $id = $area->package_id($pkg, sloppy => 1);
	next unless defined($id);
	$foundit++;
	print "$_\n" for $area->package_files($id);
    }
    not_installed($pkg) unless $foundit;
}

sub not_installed {
    my $pkg = shift;
    die "Package '$pkg' is not installed";
}

sub do_verify {
    my %opt;
    if (@ARGV) {
	$USAGE = "verify [--verbose] [<package>]";
	require Getopt::Long;
	Getopt::Long::GetOptions(\%opt,
           'verbose',
        ) || usage();
	$opt{package} = shift(@ARGV) if @ARGV;
	usage() if @ARGV;
    }
    my @areas = grep $_->initialized, map $ppm->area($_), $ppm->areas;
    if ($opt{package}) {
	@areas = grep $_->package_id($opt{package}), @areas;
	not_installed($opt{package}) unless @areas;
    }
    my %status;
    for my $area (@areas) {
	my %s = $area->verify(
            package => $opt{package},
            badfile_cb => sub {
		my $what = shift;
		my $file = shift;
		print "$file: ";
		if ($what eq "wrong_mode") {
		    printf "wrong mode %03o expected %03o\n", @_;
		}
		else {
		    print "$what\n";
		}
            },
	    file_cb => !$opt{verbose} ? undef : sub {
		my($file, $md5, $mode) = @_;
		printf "V %s %s %03o\n", $file, $md5, $mode;
            },
	);
	while (my($k,$v) = each %s) {
	    $status{$k} += $v;
	}
    }
    for my $v (qw(verified missing modified)) {
	next if $v ne "verified" && !$status{$v};
	my $s = $status{$v} == 1 ? "" : "s";
	print "$status{$v} file$s $v.\n";
    }
}

sub uri_hide_passwd {
    my $url = shift;
    return $url unless $url =~ /\@/;
    $url = URI->new($url);
    if (my $ui = $url->userinfo) {
	if ($ui =~ s/:.*/:***/) {
	    $url->userinfo($ui);
	}
    }
    return $url->as_string;
}

sub repo_by_name {
    my $name = shift;
    return unless eval {require PPM::Repositories};
    unless (defined &PPM::Repositories::get) {
	my $repo = $PPM::Repositories::Repositories{$name};
	return($name,$repo->{location});
    }
    my %repo = PPM::Repositories::get($name);
    return unless keys %repo;
    my($url,$url_noarch) = ($repo{packlist}, $repo{packlist_noarch});
    $url ||= $url_noarch;
    undef $url_noarch if $url_noarch && $url_noarch eq $url;
    return($name,$url,$url_noarch);
}

sub do_repo {
    my $cmd = shift(@ARGV) || "list";
 AGAIN:
    if ($cmd eq "list") {
	$USAGE = "repo list [--csv [ <sep> ]] [--no-header]";
	my $show_header = 1;
	my $csv;
	if (@ARGV) {
	    require Getopt::Long;
	    Getopt::Long::GetOptions(
	        'header!' => \$show_header,
                'csv:s' => \$csv,
            ) || usage();
	    usage() if @ARGV;
	}
	require ActiveState::Table;
	my $tab = ActiveState::Table->new;
	$tab->add_field("id");
	$tab->add_field("pkgs");
	$tab->add_field("name");
	my $count = 0;
	for my $repo_id ($ppm->repos) {
	    my $repo = $ppm->repo($repo_id);
	    $tab->add_row({
	        id => $repo_id,
                pkgs => $repo->{enabled} ? $repo->{pkgs} : "n/a",
		name => $repo->{name},
            });
	    $count++ if $repo->{enabled};
	}
	if (defined($csv)) {
	    $csv = "," if $csv eq "";
	    print $tab->as_csv(null => "", field_separator => $csv, show_header => $show_header);
	}
	else {
	    print $tab->as_box(null => "", show_trailer => 0, show_header => $show_header, align => {id => "right", pkgs => "right"}, box_chars => $BOX_CHARS, max_width => terminal_width());
	    my $s = ($count == 1) ? "y" : "ies";
	    $count ||= "no";
	    print " ($count enabled repositor$s)\n";
	}
    }
    elsif ($cmd eq "search") {
	do_search();
    }
    elsif ($cmd eq "sync") {
	$USAGE = "repo sync [--force] [<num>]";
	my $force;
	my $max_ppd;
	if (@ARGV) {
	    require Getopt::Long;
	    Getopt::Long::GetOptions(
	        force => \$force,
                'max-ppd=n' => \$max_ppd,
            ) || usage();
	    usage() if @ARGV > 1;
	}
	my @repo;
	if (@ARGV) {
	    my $repo = $ppm->repo($ARGV[0]);
	    die "No such repo; 'ppm repo list' will print what's available" unless $repo;
	    push(@repo, repo => $repo->{id});
	}
	$ppm->repo_sync(
	    validate => 1,
	    force => $force,
            max_ppd => $max_ppd,
	    @repo,
        );
    }
    elsif ($cmd eq "on" || $cmd eq "off" || $cmd eq "delete" || $cmd eq "describe") {
	$USAGE = "repo $cmd <num>";
	usage() if @ARGV != 1;
	my $repo = $ppm->repo($ARGV[0]);
	die "No such repo; 'ppm repo list' will print what's available" unless $repo;
	if ($cmd eq "delete") {
	    $ppm->repo_delete($repo->{id});
	    print "Repo $repo->{id} deleted.\n";
	}
	elsif ($cmd eq "describe") {
	    require ActiveState::Duration;
	    print "Id: $repo->{id}\n";
	    print "Name: $repo->{name}\n";
	    print "URL: " . uri_hide_passwd($repo->{packlist_uri}) . "\n";
	    print "Enabled: ", ($repo->{enabled} ? "yes" : "no"), "\n";
	    if (my $last_status = $repo->{packlist_last_status_code}) {
		print "Last-Status: $last_status " . HTTP::Status::status_message($last_status) . "\n";
	    }
	    else {
		print "Last-Status: - (never accessed)\n";
	    }
	    if (my $last_access = $repo->{packlist_last_access}) {
		print "Last-Access: ", ActiveState::Duration::ago_eng(time - $last_access), "\n";
	    }
	    if (my $fresh_until = $repo->{packlist_fresh_until}) {
		my $refresh_in = $fresh_until - time;
		if ($refresh_in >= 0) {
		    print "Refresh-In: ", ActiveState::Duration::dur_format_eng($refresh_in), "\n";
		}
		else {
		    print "Refresh-In: overdue\n";
		}
	    }
	    if (my $lastmod = $repo->{packlist_lastmod}) {
		require HTTP::Date;
		print "Last-Modified: ", ActiveState::Duration::ago_eng(time - HTTP::Date::str2time($lastmod)), "\n";
	    }
	}
	else {
	    $ppm->repo_enable($repo->{id}, $cmd eq "on");
	}
    }
    elsif ($cmd eq "add") {
	$USAGE = "repo add <url> [<name>] [--username <user> [--password <password>]]";
	my $user;
	my $pass;
	require Getopt::Long;
	Getopt::Long::GetOptions(
	    'username=s' => \$user,
            'password=s' => \$pass,
        ) || usage();
	if ($user) {
	    $user .= ":$pass" if defined $pass;
	}
	else {
	    usage() if defined $pass;
	}
	my $url = shift(@ARGV) || usage();
	my $url_noarch;
	my $name;
	if (@ARGV) {
	    $name = shift(@ARGV);
	    usage() if @ARGV;
	    if ($url !~ /^[a-z][+\w]+:/ && $name =~ /^[a-z][+\w]+:/) {
		# ppm3 had the arguments reversed, so try that
		($url, $name) = ($name, $url);
	    }
	}
	else {
	    $name = eval { URI->new($url)->host } || $url;
	}
	if ($url =~ /^[a-z][+\w]+:/) {
	    die "PPM3 SOAP repositories are not supported"
		if $url =~ m,\?urn:/,;
	}
	else {
	    if ($url eq "activestate") {
		($name, $url) = ActivePerl::PPM::Client::activestate_repo(
		    $ppm->{ppmarch},
		    $ppm->{activestate_build}
		);
		die "No ActiveState repo for this platform" unless $url;
	    }
	    elsif (-d $url) {
		require URI::file;
		$url = URI::file->new_abs($url);
	    }
	    elsif (($name,$url,$url_noarch) = repo_by_name($url)) {
		# empty
	    }
	    else {
		die "The repository URL must be absolute or a local directory";
	    }
	}
	if ($user) {
	    for ($url, $url_noarch) {
		next unless defined;
		$_ = URI->new($_);
		$_->userinfo($user);
		$_ = $_->as_string;
	    }
	}
	$ppm->repo_dbimage_disable;
	my $id = $ppm->repo_add(name => $name, packlist_uri => $url);
	print "Repo $id added.\n";
	if ($url_noarch) {
	    $id = $ppm->repo_add(name => "$name-noarch", packlist_uri => $url_noarch);
	    print "Repo $id added.\n";
	}
    }
    elsif ($cmd eq "rename") {
	$USAGE = "repo rename <num> <name>";
	usage() if @ARGV < 2;
	my $repo = $ppm->repo(shift(@ARGV));
	die "No such repo; 'ppm repo list' will print what's available" unless $repo;
	$ppm->repo_set_name($repo->{id}, join(" ", @ARGV));
    }
    elsif ($cmd eq "location") {
	$USAGE = "repo location [--no-sync] <num> <url>";
	my $sync = 1;
	require Getopt::Long;
	Getopt::Long::GetOptions(
	    'sync!' => \$sync,
	) || usage();
	usage() if @ARGV != 2;
	my($id, $uri) = @ARGV;
	my $repo = $ppm->repo($id);
	die "No such repo; 'ppm repo list' will print what's available" unless $repo;
	$ppm->repo_set_packlist_uri($repo->{id}, $uri);
	$ppm->repo_sync(repo => $repo->{id}) if $sync;
    }
    elsif ($cmd =~ /^\d+$/) {
	@ARGV = ("describe") unless @ARGV;
	if ($ARGV[0] =~ /^\d+$/) {
	    # avoids infinite recursion
	    $USAGE = "repo <num> <cmd> ...";
	    usage();
	}
	splice(@ARGV, 1, 0, $cmd);
	do_repo();
    }
    elsif ($cmd eq "suggest") {
	my $ppm_repo_ok;
	eval {
	    require PPM::Repositories;
	    $ppm_repo_ok++;
	};
	require ActivePerl;
	my $count = 0;
	my($as_name, $as_url) = ActivePerl::PPM::Client::activestate_repo();
	if ($as_name) {
	    $PPM::Repositories::Repositories{activestate} = {
		Active => 1,
                Type => "PPM4",
                Notes => $as_name,
                location => $as_url,
	    };
	}
	if (defined &PPM::Repositories::list) {
	    for my $name (PPM::Repositories::list()) {
		my %repo = PPM::Repositories::get($name);
		$repo{packlist} = $as_url if $as_url && $name eq "activestate";
		print "\n" if $count;
		print "$PROGNAME repo add $name\n";
		print "   $repo{desc}\n";
		print "   $repo{packlist}\n" if $repo{packlist};
		print "   $repo{packlist_noarch}\n" if $repo{packlist_noarch};
		$count++;
	    }
	}
	else {
	    for my $id (sort keys %PPM::Repositories::Repositories) {
		my $repo = $PPM::Repositories::Repositories{$id};
		next unless $repo->{Active};
		next if $repo->{Type} eq "PPMServer";
		my $o = $repo->{PerlO} || [];
		next if @$o && !grep $_ eq $^O, @$o;
		my $v = $repo->{PerlV} || [];
		my $my_v = ActivePerl::perl_version;
		next if @$v && !grep $my_v =~ /^\Q$_\E\b/, @$v;
		print "\n" if $count;
		print "$PROGNAME repo add $id\n";
		print "   $repo->{Notes}\n";
		print "   $repo->{location}\n";
		$count++;
	    }
	}
	if ($count) {
	    unless ($ppm_repo_ok) {
		print "\n*** Install PPM-Repositories for more suggestions ***\n";
	    }
	}
	else {
	    my $msg = "No suggested repository for this perl";
	    $msg .= "\nInstalling PPM-Repositories might provide some suggestions"
		unless $ppm_repo_ok;
	    die $msg;
	}
    }
    else {
	$cmd = _try_abbrev("repo", $cmd, qw(list location search sync on off delete describe add rename suggest));
	goto AGAIN;
    }
}

sub do_info {
    my %info;

    $ppm->dbh;  # so we can pick up db_file
    for (qw(arch etc db_file)) {
	$info{$_} = $ppm->{$_};
    }

    $info{be_state} = $ppm->be_state;
    $info{be_serial} = web_ua()->be_serial || "<none>";
    $info{box_chars} = $BOX_CHARS || "ascii";
    $info{http_proxy} = $ENV{http_proxy} || "<none>";
    $info{log_file} = ActivePerl::PPM::Logger::ppm_logger()->logfile;

    {
	no warnings 'once';
	require FindBin;
	$info{ppm_path} = "$FindBin::Bin/$FindBin::Script";
    }
    require ActivePerl::PPM;
    $info{ppm_version} = $ActivePerl::PPM::VERSION;
    if (defined &ActivePerl::PRODUCT) {
	require ActivePerl;
	$info{perl} = ActivePerl::PRODUCT() . "-" . ActivePerl::perl_version();
    }
    else {
	$info{perl} = "perl-$^V";
    }
    $info{perl_version} = $];
    $info{perl_path} = $^X;

    if (@ARGV) {
	for my $k (@ARGV) {
	    print "$info{$k}\n";
	}
    }
    else {
	for my $k (sort keys %info) {
	    print "$k = $info{$k}\n";
	}
    }
}

sub print_be_info {
    my %opt = @_;
    $opt{prefix} = "*** " unless defined $opt{prefix};
    if ($ppm->be_state eq "expired") {
	print "$opt{prefix}Your ActivePerl Business Edition subscription seems to have expired.\n";
	print "$opt{prefix}Please visit your account at https://account.activestate.com to\n";
	print "$opt{prefix}renew your subscription.\n";
    }
    else {
	print "$opt{prefix}Please visit http://www.activestate.com/business-edition to learn more\n";
	print "$opt{prefix}about the ActivePerl Business Edition offering.\n";
    }
}

sub do_search {
    $USAGE = "search <pattern>";
    my $sync = 1;
    require Getopt::Long;
    Getopt::Long::GetOptions(
        'sync!' => \$sync,
     ) || usage();
    usage() unless @ARGV == 1;
    my $pattern = shift(@ARGV);
    $ppm->repo_sync if $sync;
    my @fields = ("name", "version", "release_date", "abstract", "repo_id", "cannot_install");
    my @res = $ppm->search($pattern, @fields);
    if (@res) {
	if (@res == 1) {
	    @ARGV = (1);
	    return do_describe();
	}

	my %repo_name;
	for my $id ($ppm->repos) {
	    my $o = $ppm->repo($id);
	    next unless $o->{enabled};
	    $repo_name{$id} = $o->{name} || $id;
	}

	my $cannot_install_count = 0;
	for (@res) {
	    $cannot_install_count++ if $_->[5];
	}

	if ($cannot_install_count) {
	    if ($cannot_install_count == @res) {
		print "*** Warning: None of the matched packages can be installed.\n";
	    }
	    else {
		print "*** Warning: Some of the matched package require a valid Business\n";
		print "*** Edition subscription to be installed.  These are marked with [BE].\n";
	    }
	    print_be_info();
	    print "\n";
	}

	if (@res < 10) {
	    my $count = 0;
	    for (@res) {
		my($name, $version, $date, $abstract, $repo_id, $cannot_install) = @$_;
		$count++;
		print "\n" unless $count == 1;
		print "$count: $name";
		print " [BE]" if $cannot_install && $cannot_install_count != @res;
		print "\n";
		print "   $abstract\n" if $abstract;
		print "   Version: $version\n";
		if ($date) {
		    $date =~ s/[T ].*//;
		    print "   Released: ", $date, "\n";
		}
		print "   Repo: ", ($repo_name{$repo_id} || $repo_id), "\n"
		    if keys %repo_name > 1;
	    }
	}
	else {
	    my $count = 0;
	    my $count_width = length(scalar(@res));
	    for (@res) {
		$count++;
		printf "%*d: %s %s", $count_width, $count, $_->[0], $_->[1];
		print " [BE]" if $_->[5] && $cannot_install_count != @res;
		print "\n";
	    }
	}
    }
    else {
	print "*** no packages matching '$pattern' found ***\n";
    }
}

sub do_describe {
    $USAGE = "describe <num>";
    usage() unless @ARGV == 1;
    my $num = shift(@ARGV);
    $num =~ s/:$//;
    usage unless $num =~ /^\d+$/;
    my $pkg = $ppm->search_lookup($num) ||
	die "*** no package #$num, do a '$PROGNAME search' first ***\n";
    my $pad = " " x (length($num) + 2);
    print "$num: $pkg->{name}";
    if (my $why = $ppm->cannot_install($pkg)) {
	print " *** can't install: $why ***";
    }
    print "\n";
    print "${pad}$pkg->{abstract}\n" if $pkg->{abstract};
    print "${pad}Version: $pkg->{version}\n";
    if (my $date = $pkg->{release_date}) {
	$date =~ s/[T ].*//;
	print "${pad}Released: ", $date, "\n";
    }
    print "${pad}Author: $pkg->{author}\n" if $pkg->{author};
    for my $role (qw(provide require)) {
	for my $feature (sort keys %{$pkg->{$role} || {}}) {
	    next if $feature eq $pkg->{name};
	    (my $pretty_feature = $feature) =~ s/::$//;
	    print "${pad}\u$role: $pretty_feature";
	    if (my $vers = $pkg->{$role}{$feature}) {
		print " version $vers";
		print " or better" if $role eq "require";
	    }
	    print "\n";
	}
    }
    my $repo = $ppm->repo($pkg->{repo_id});
    print "${pad}Repo: $repo->{name}\n";
    if ((my $ppmx = $pkg->codebase_abs) =~ m,^https?://ppm4(?:-be)?\.activestate.com/,) {
	$ppmx =~ s/\.tar\.gz$/.ppmx/;
	print "${pad}Link: $ppmx\n";
    }
    elsif ((my $ppd = $pkg->{ppd_uri}) =~ /\.ppd$/) {
	print "${pad}Link: $ppd\n";
    }
    if (my $name = is_cpan_package($pkg->{name})) {
	print "${pad}CPAN: http://search.cpan.org/dist/$name-$pkg->{version}/\n";
    }
    for my $area ($ppm->areas) {
	my $area_pkg = eval { $ppm->area($area)->package($pkg->{name}) };
	next unless $area_pkg;
	print "${pad}Installed: $area_pkg->{version} ($area)\n";
    }
    return;
}

sub do_tree {
    $USAGE = "tree [<num> | <package>]";
    usage unless @ARGV == 1;
    my $pkg = shift(@ARGV);
    if ($pkg =~ /^\d+$/) {
	my $tmp = $ppm->search_lookup($pkg) ||
	    die "*** no package #$pkg, do a '$PROGNAME search' first ***\n";
	$pkg = $tmp;
    }
    else {
	my $tmp = $ppm->package_best($pkg, 0) ||
	    die "*** no package called $pkg ***\n";
	$pkg = $tmp;
    }
    _tree($pkg, {});
}

sub _tree {
    my($pkg, $seen, $reason, $depth) = @_;
    $depth ||= 0;

    print "  " x $depth, "package ", $pkg->name_version;
    print " provide $reason" if $reason && $reason ne $pkg->{name};
    print "\n";

    if ($seen->{$pkg->name_version}++) {
	return;
    }

    my $require = $pkg->{require};
    if ($require && %$require) {
	my %subpkg;
	for my $feature (sort keys %$require) {
	    print "  " x $depth, "  needs $feature";
	    my $vers = $require->{$feature};
	    if ($vers) {
		print " $vers or better";
	    }

	    my @facts;
	    my $found;
	    for my $area_name ($ppm->areas) {
		my $area = $ppm->area($area_name);
                next unless $area->initialized;
		if (my $have = $area->feature_have($feature)) {
		    $have = 0 if $have eq "0E0";
		    push(@facts, ($have || $vers ? "v$have " : "") . "installed in $area_name area");
		    $found++ if $have >= $vers;
		}
	    }
	    push(@facts, "not installed") unless $found;

	    if (my $subpkg = $ppm->package_best($feature, $vers)) {
		my $h = $subpkg{$subpkg->name_version} ||= {
		    pkg => $subpkg,
		};
		push(@{$h->{reason}}, $feature) if $feature ne $pkg->name;
	    }
	    else {
		push(@facts, "not provided by any repo");
	    }
	    print " (", join_with("and", @facts), ")" if @facts;
	    print "\n";
	}

	for (sort keys %subpkg) {
	    my $h = $subpkg{$_};
	    _tree($h->{pkg}, $seen, join_with("and", @{$h->{reason}}), $depth + 1);
	}
    }
    else {
	print "  " x $depth , "  (no dependencies)\n";
    }
}

sub do_install {
    $USAGE = "install [--force] [--nodeps] [--area <area>] <module> | <url> | <file> | <num>";
    my $force;
    my $area;
    my $nodeps;
    my $sync = 1;
    require Getopt::Long;
    Getopt::Long::GetOptions(
        force => \$force,
	'area=s' => \$area,
	nodeps => \$nodeps,
        'sync!' => \$sync,
     ) || usage();
    usage() unless @ARGV >= 1;
    my @args;
    push(@args, force => 1) if $force;
    push(@args, follow_deps => "none") if $nodeps;

    my $feature = shift(@ARGV);
    eval {
	if ($feature =~ m,^[a-z][+\w]+:[^:],) {
	    usage() if @ARGV;
	    # looks like an absolute URL
            require URI;
	    _install_uri($area, $force, URI->new($feature), @args);
	}
	elsif ($feature =~ /\.(?:ppd|ppmx)$/) {
	    usage() if @ARGV;
	    require URI::file;
	    _install_uri($area, $force, URI::file->new_abs($feature), @args);
	}
	elsif ($feature =~ /^\d+$/) {
	    usage() if @ARGV;
	    my $pkg = $ppm->search_lookup($feature) ||
		die "*** no package #$feature, do a '$PROGNAME search' first ***\n";
	    my @deps = $ppm->packages_missing(want_deps => [$pkg], @args);
	    _install($area, $force, $pkg, @deps);
	}
	else {
	    # search for features in repos
            $ppm->repo_sync if $sync;
	    my @want = map $ppm->feature_fixup_case($_), $feature, @ARGV;
	    _install($area, $force, $ppm->packages_missing(want => \@want, @args));
	}
    };
    if ($@) {
	if ($@ =~ /\bwould downgrade\b/) {
	    $@ =~ s/( at )/; use --force to install regardless$1/;
	}

	if ($@ =~ /File conflict/ && $@ =~ /The package (\S+) has already/) {
	    my $pkg = $1;
	    $@ =~ s/( at )/ Uninstall $pkg, or use --force to allow files\n    to be overwritten.$1/;
	}
	die;
    }
}

sub do_upgrade {
    $USAGE = "upgrade [<pkg> | --install]";
    my $install;
    my $opt_area;
    my $sync = 1;
    if (@ARGV) {
	require Getopt::Long;
	Getopt::Long::GetOptions(
	    'install' => \$install,
	    'area=s' => \$opt_area,
            'sync!' => \$sync,
	) || usage();
	usage() if @ARGV > 1;
    }
    $ppm->area($opt_area) if $opt_area;  # croaks if it doesn't exist
    if (@ARGV && $ARGV[0] =~ /::/) {
	$ppm->repo_sync if $sync;
	my $mod = $ppm->feature_fixup_case($ARGV[0]);
	my $area = $opt_area;
	unless ($area) {
	    # try to locate the area where the package was previously installed (if any)
	    for my $area_name ($ppm->areas) {
		my $a = $ppm->area($area_name);
		if (defined($a->feature_have($mod))) {
		    if ($area_name eq "perl" || $a->readonly) {
			$area = $ppm->default_install_area;
		    }
		    else {
			$area = $area_name;
		    }
		    last;
		}
	    }
	}
	return _install($area, 0, $ppm->packages_missing(want => [[$mod, undef]]));
    }

    $install++ if @ARGV;
    my $pkg_count = 0;
    my $upgrade_count = 0;
    my %shaddow;
    $ppm->repo_sync if $sync;
    for my $area_name ($ppm->areas) {
	my $area = $ppm->area($area_name);
	for ($area->packages("id", "name", "version")) {
	    my($pkg_id, $pkg_name, $pkg_version) = @$_;
	    next if @ARGV && lc($ARGV[0]) ne lc($pkg_name);
	    $pkg_count++;
	    next if $shaddow{$pkg_name}++;
	    eval {
		if (my $best = $ppm->package_best($pkg_name, 0)) {
		    if ($best->{name} eq $pkg_name && $best->{version} ne $pkg_version) {
			my $pkg = $area->package($pkg_id);
			if ($best->better_than($pkg)) {
			    print "$pkg_name $best->{version} (have $pkg_version)\n";
			    $upgrade_count++;
			    if ($install) {
				my $install_area = $opt_area;
				unless ($install_area) {
				    $install_area = $area_name;
				    if ($install_area eq "perl" || $area->readonly) {
					$install_area = $ppm->default_install_area;
					unless ($install_area) {
					    die "No writable install area for the upgrade";
					}
				    }
				}

				# There might be new dependencies that also need to
				# be installed.
				my %requires = $best->requires;
				my @extra = $ppm->packages_missing(
				    have => [$best],
				    want => [map [$_ => $requires{$_}], keys %requires],
				);

				_install($install_area, 0, $best, @extra);
			    }
			}
		    }
		}
	    };
	    if ($@) {
		ppm_log("ERR", $@);
	    }
	}
    }
    if (@ARGV && !$pkg_count) {
	return _install($opt_area, 0, $ppm->packages_missing(want => [[$ARGV[0], undef]]));
    }
    elsif (!$upgrade_count) {
	my $for = @ARGV ? " for $ARGV[0]" : "";
	print STDERR "*** no upgrades available$for ***\n";
    }
}

sub _install_uri {
    my($area, $force, $uri, @args) = @_;

    my $res = web_ua->get($uri);
    unless ($res->is_success) {
	die $res->status_line;
    }

    my $tmp_ppmx;
    if ($uri =~ /\.ppmx$/) {
        # need a file
        require File::Temp;
        $tmp_ppmx = File::Temp->new(
            TEMPLATE => "ppm-XXXXXX",
            SUFFIX => ".ppmx",
            TMPDIR => 1,
        );
        $tmp_ppmx->print($res->content);
        $tmp_ppmx->flush;

        require Archive::Tar;
        my $ppd;
        my $tar = Archive::Tar->new($tmp_ppmx->filename, 1);
        for my $file ($tar->get_files) {
            #print "TAR path: ", $file->full_path, "\n";
            if ($file->name =~ /\.ppd$/) {
                $ppd = $file;
                last;
            }
        }
        die "No PPD found inside $uri" unless $ppd;
        $res->remove_header("Content-Encoding");
        $res->content($ppd->get_content);
    }

    require ActivePerl::PPM::PPD;
    my $cref = $res->decoded_content(ref => 1, default_charset => "none");
    my $pkg = ActivePerl::PPM::Package->new_ppd($$cref,
        arch => $ppm->arch,
	base => $res->base,
        rel_base => $uri,
    );
    unless ($pkg) {
	die "No PPD found _at $uri";
    }
    if (my $codebase = $pkg->{codebase}) {
	$pkg->{ppd_uri} = $uri;
	$pkg->{ppd_etag} = $res->header("ETag");
	$pkg->{ppd_lastmod} = $res->header("Last-Modified");
    }
    else {
	die "The PPD does not provide code to install for this platform";
    }

    if ($tmp_ppmx) {
        require URI::file;
        $pkg->{codebase} = URI::file->new_abs($tmp_ppmx->filename);
    }

    # XXX follow dependencies with the "directory" of $pkg $uri as the
    # first repo to look for additional packages.  This only works for
    # package features.

    _install($area, $force, $pkg, $ppm->packages_missing(want_deps => [$pkg], @args));
}

sub _install {
    my $area = shift;
    my $force = shift;
    unless (@_) {
	print "No missing packages to install\n";
	return;
    }

    unless ($force) {
	my $stop;
	my $stop_be;
	for my $pkg (@_) {
	    if (my $why = $ppm->cannot_install($pkg)) {
		print "Can't install ", $pkg->name_version, ": ", $why, "\n";
		$stop++;
		$stop_be++ if $why =~ /business edition/i;
	    }
	}
	if ($stop) {
	    if ($stop_be) {
		print "\n";
		print_be_info();
	    }
	    return;
	}
    }

    unless ($area) {
	$area = $ppm->default_install_area;
	unless ($area) {
	    my $msg = "All available install areas are readonly.
Run 'ppm help area' to learn how to set up private areas.";
	    require ActiveState::Path;
	    if (ActiveState::Path::find_prog("sudo")) {
		$msg .= "\nYou might also try 'sudo ppm' to raise your privileges.";
	    }
	    die $msg;
	}
	ppm_log("NOTICE", "Installing into $area");
    }
    $area = $ppm->area($area);

    $| = 1;

    my $summary = $ppm->install(packages => \@_, area => $area, force => $force);
    if (my $count = $summary->{count}) {
	for my $what (sort keys %$count) {
	    my $n = $count->{$what} || 0;
	    printf "%4d file%s %s\n", $n, ($n == 1 ? "" : "s"), $what;
	}
    }
}

sub do_remove {
    $USAGE = "remove [--area <area>] [--force] <package> ...";
    my $opt_area;
    my $opt_force;
    require Getopt::Long;
    Getopt::Long::GetOptions(
	'area=s' => \$opt_area,
	'force' => \$opt_force,
     ) || usage();
    usage() unless @ARGV;

    my $removed_count = 0;
    for my $pkg (@ARGV) {
	if ($pkg =~ /^\d+$/) {
	    print "$pkg: not installed\n";
	    next;
	}
	my $area;
	my $pkg_o;
	if ($opt_area) {
	    $area =  $ppm->area($opt_area);
	    $pkg_o = $area->package($pkg, sloppy => 1);
	}
	else {
	    for my $a ($ppm->areas) {
		$area = $ppm->area($a);
		next unless $area->initialized;
		$pkg_o = $area->package($pkg, sloppy => 1);
		if ($pkg_o) {
		    die "Can't remove from 'perl' area without explicit area specification"
			if $a eq "perl";
		    last;
		}
	    }
	}
	unless ($pkg_o) {
	    print "$pkg: not installed\n";
	    next;
	}
	if (lc($pkg_o->{name}) ne lc(do{my $p = $pkg; $p =~ s/::/-/g; $p})) {
	    die "'ppm remove $pkg_o->{name}' will uninstall package providing $pkg";
	}
	unless ($opt_force) {
	    my @d = map $_->name, $ppm->packages_depending_on($pkg_o, $area->name);
	    if (@d) {
		my %args = map { $_ => 1 } @ARGV;
		@d = grep !$args{$_}, @d;
		if (@d) {
		    print "$pkg: required by ", join_with("and", sort @d), "\n";
		    next;
		}
	    }
	}
	eval {
	    $pkg_o->run_script("uninstall", $area, undef, {
	        old_version => $pkg_o->{version},
                packlist => $area->package_packlist($pkg_o->{id}),
            });
	    print "$pkg_o->{name}: ";
	    $area->uninstall($pkg_o->{name});
	};
	if ($@) {
	    print clean_err($@) . "\n";
	}
	else {
	    print "uninstalled\n";
	    $removed_count++;
	}
    }
    if ($removed_count) {
	update_html_toc();
    }
    else {
	die "No packages uninstalled";
    }
}

sub do_profile {
    my $cmd = shift(@ARGV) || "save";
 AGAIN:
    if ($cmd eq "save") {
        $USAGE = "profile save [<file>]";
        my $file = shift(@ARGV);
        usage() if @ARGV;

        my $fh;
        if ($file && $file ne "-") {
            open($fh, ">", $file) || die "Can't create $file: $!";
        }
        else {
            $fh = *STDOUT;
        }

        print $fh $ppm->profile_xml;
    }
    elsif ($cmd eq "restore") {
        $USAGE = "profile restore [<file>]";
        my $file = shift(@ARGV);
        usage() if @ARGV;

        my $fh;
        if ($file && $file ne "-") {
            open($fh, "<", $file) || die "Can't open $file: $!";
        }
        else {
            $file = "stdin";
            $fh = *STDIN;
        }

        my $xml = do { local $/; <$fh> };
        die "No profile data found in $file" unless $xml =~ /<PPMPROFILE\b/;

        $ppm->profile_xml_restore($xml);
    }
    else {
	$cmd = _try_abbrev("profile", $cmd, qw(save restore));
	goto AGAIN;
    }
}

BEGIN {
    # aliases for PPM3 compatibility (mostly)
    *do_update = \&do_upgrade;
    *do_uninstall = \&do_remove;
}

__END__

=head1 NAME

ppm - Perl Package Manager, version 4

=head1 SYNOPSIS

Invoke the graphical user interface:

    ppm
    ppm gui

Install, upgrade and remove packages:

    ppm install [--area <area>] [--force] <pkg> ...
    ppm install [--area <area>] [--force] <module> ...
    ppm install [--area <area>] <url>
    ppm install [--area <area>] <file>.ppmx
    ppm install [--area <area>] <file>.ppd
    ppm install [--area <area>] <num>
    ppm upgrade [--install]
    ppm upgrade [--area <area>] <pkg>
    ppm upgrade [--area <area>] <module>
    ppm remove [--area <area>] [--force] <pkg>

Manage and search install areas:

    ppm area list [--csv] [--no-header]
    ppm area sync
    ppm list [--fields <fieldnames>] [--csv]
    ppm list <area> [--fields <fieldnames>] [--csv]
    ppm files <pkg>
    ppm verify [<pkg>]

Manage and search repositories:

    ppm repo list [--csv] [--no-header]
    ppm repo sync [--force] [<num>]
    ppm repo on <num>
    ppm repo off <num>
    ppm repo describe <num>
    ppm repo add <name>
    ppm repo add <url> [<name>] [--username <user> [--password <passwd>]]
    ppm repo rename <num> <name>
    ppm repo location <num> <url>
    ppm repo suggest
    ppm search <pattern>
    ppm describe <num>
    ppm tree <package>
    ppm tree <num>

Obtain version and copyright information about this program:

    ppm --version
    ppm version

=head1 DESCRIPTION

The C<ppm> program is the package manager for ActivePerl.  It
simplifies the task of locating, installing, upgrading and removing
Perl packages.

Invoking C<ppm> without arguments brings up the graphical user interface,
but ppm can also be used as a command line tool where the first argument
provide the name of the sub-command to invoke.  The following sub-commands
are recognized:

=over

=item B<ppm area init> I<area>

Will initialize the given area so that PPM starts tracking the
packages it contains.

PPM allows for the addition of new install areas, which is useful for
shared ActivePerl installations where the user does not have write
permissions for the I<site> and I<perl> areas.  New install areas are
added by simply setting up new library directories for perl to search,
and PPM will set up install areas to match.  The easiest way to add
library directories for perl is to specify them in the C<PERL5LIB>
environment variable, see L<perlrun> for details.  PPM will create
F<etc>, F<bin>, F<html> directories as needed when installing
packages.  If the last segment of the library directory path is F<lib>
then the other directories will be created as siblings of the F<lib>
directory, otherwise they will be subdirectories.

=item B<ppm area list> [ B<--csv> [ I<sep> ] ] [ B<--no-header> ]

Lists the available install areas.  The list displays the name, number
of installed packages and C<lib> directory location for each install
area.  If that area is read-only, the name appears in parenthesis.  You
will not be able to install packages or remove packages in these areas.
The default install area is marked with a C<*> after its name.

The order of the listed install areas is the order perl uses when
searching for modules.  Modules installed in earlier areas override
modules installed in later ones.

The B<--csv> option selects CSV (comma-separated values) format for the
output. The default field separator can be overridden by the argument
following B<--csv>.

The B<--no-header> option suppresses column headings.

=item B<ppm area sync> [ I<area> ... ]

Synchronizes installed packages, including those installed by means
other than PPM (e.g. the CPAN shell), with the ppm database. PPM
searches the install area(s) for packages, making PPM database entries
if they do not already exist, or dropping entries for packages that no
longer exist.  When used without an I<area> argument, all install areas
are synced.

=item B<ppm config> I<name> [ I<value> ]

Get or set various PPM configuration values.

The following configuration options might be of interest:

=over

=item arch

The architecture of the current database.  For internal use.  Don't change this.

=item repo_dbimage

If set to '1' look for F<package.db.gz> indexes in repositories before looking
for the F<package.xml> file.

=item install_html

If set to '0' don't generate and install the HTML version of the documentation
for the modules installed.  This makes installation considerably faster.

=item gui.*

Various settings for the graphical user interface.

=back

=item B<ppm config list>

List all configuration options currently set.

=item B<ppm describe> I<num>

Shows all properties for a particular package from the last search
result.

=item B<ppm files> I<pkg>

Lists the full path name of the files belonging to the given package,
one line per file.

=item B<ppm help> [ I<subcommand> ]

Prints the documentation for ppm (this file).

=item B<ppm info> [ I<name> ]

List information about ppm and its environment.  With argument print the
value of the given variable.  See also L<ppm config list>.

=item B<ppm install> I<pkg> ... [ B<--area> I<area> ] [ B<--force> ] [ B<--nodeps> ]

=item B<ppm install> I<module> ... [ B<--area> I<area> ] [ B<--force> ] [ B<--nodeps> ]

=item B<ppm install> I<file>.ppmx [ B<--area> I<area> ] [ B<--nodeps> ]

=item B<ppm install> I<file>.ppd [ B<--area> I<area> ] [ B<--nodeps> ]

=item B<ppm install> I<url> [ B<--area> I<area> ] [ B<--nodeps> ]

=item B<ppm install> I<num> [ B<--area> I<area> ] [ B<--nodeps> ]

Install a package and its dependencies.

The argument to B<ppm install> can be the name of a package, the name of
a module provided by the package, the file name or the URL of a PPMX or PPD file,
or the associated number for the package returned by the last C<ppm
search> command.

Package or module names can be repeated to install multiple modules in one go.
These forms can also be intermixed.

If the package or module requested is already installed, PPM installs
nothing.  The B<--force> option can be used to make PPM install a
package even if it's already present.  With B<--force> PPM resolves
file conflicts during package installation or upgrade by allowing
files already installed by other packages to be overwritten and
ownership transferred to the new package.  This may break the package
that originally owned the file.

By default, new packages are installed in the C<site> area, but if the
C<site> area is read only, and there are user-defined areas set up, the
first user-defined area is used as the default instead.  Use the
B<--area> option to install the package into an alternative location.

The B<--nodeps> option makes PPM attempt to install the package
without resolving any dependencies the package might have.

=item B<ppm list> [ I<area> ] [ B<--matching> I<pattern> ]  [ B<--csv> [ I<sep> ] ] [ B<--no-header> ] [ ---fields B<fieldlist> ]

List installed packages.  If the I<area> argument is not provided, list
the content of all install areas.

The B<--matching> option limits the output to only include packages
matching the given I<pattern>.  See B<ppm search> for I<pattern> syntax.

The B<--csv> option selects CSV (comma-separated values) format for the
output. The default field separator can be overridden by the argument
following B<--csv>.

The B<--no-header> option suppress printing of the column headings.

The B<--fields> argument can be used to select what fields to show.
The argument is a comma separated list of the following field names:

=over

=item B<name>

The package name.  This field is always shown, but if specified
alone get rid of the decorative box.

=item B<version>

The version number of the package.

=item B<release_date>

The release date of the package.

=item B<abstract>

A one sentence description of the purpose of the package.

=item B<author>

The package author or maintainer.

=item B<area>

Where the package is installed.

=item B<files>

The number of files installed for the package.

=item B<size>

The combined disk space used for the package.

=item B<ppd_uri>

The location of the package description file.

=back

=item B<ppm log> [ B<--errors> ] [ I<minutes> ]

Print entries from the log for the last few minutes.  By default print
log lines for the last minute.  With B<--errors> option suppress
warnings, trace and debug events.

=item B<ppm profile restore> [ I<filename> ]

Install the packages listed in the given profile file.  If no file is
given try to read the profile from standard input.

=item B<ppm profile save> [ I<filename> ]

Write profile of configured repositories and installed packages to the
given file.  If no file is given then print the profile XML to
standard output.

=item B<ppm query> I<pattern>

Alias for B<ppm list --matching> I<pattern>.  Provided for PPM version
3 compatibility.

=item B<ppm remove> [ B<--area> I<area> ] [ B<--force> ] I<pkg> ...

Uninstalls the specified package.  If I<area> is provided unininstall
from the specified area only.  With B<--force> uninstall even if there
are other packages that depend on features provided by the given
package.

=item B<ppm rep> ...

Alias for B<ppm repo>.  Provided for PPM version 3 compatibility.

=item B<ppm repo>

Alias for B<ppm repo list>.

=item B<ppm repo add> I<name>

Add the named resposity for PPM to fetch packages from.  The names
recognized are shown by the B<ppm repo suggest> command.  Use B<ppm
repo add activestate> if you want to restore the default ActiveState
repo after deleting it.

=item B<ppm repo add> I<url> [ I<name> ] [ B<--username> I<user> [ B<--password> I<password> ]

Set up a new repository for PPM to fetch packages from.

=item B<ppm repo delete> I<num>

Remove repository number I<num>.

=item B<ppm repo describe> I<num>

Show all properties for repository number I<num>.

=item B<ppm repo list> [ B<--csv> [ I<sep> ] ] [ B<--no-header> ]

List the repositories that PPM is currently configured to use.  Use this
to identify which number specifies a particular repository.

The B<--csv> option selects comma-separated values format for the
output. The default field separator can be overridden by the argument
following B<--csv>.

The B<--no-header> option suppress printing of the column headings.


=item B<ppm repo> I<num>

Alias for B<ppm repo describe> I<num>.

=item B<ppm repo> I<num> I<cmd>

Alias for B<ppm repo> I<cmd> I<num>.

=item B<ppm repo off> I<num>

Disable repository number I<num> for B<ppm install> or B<ppm search>.

=item B<ppm repo on> I<num>

Enable repository number I<num> if it has been previously disabled with
B<ppm repo off>.

=item B<ppm repo rename> I<num> I<name>

Change name by which the given repo is known.

=item B<ppm repo location> I<num> I<url>

Change the location of the given repo.  This will make PPM
forget all cached data from the old repository and try to refetch it
from the new location.

=item B<ppm repo search> ...

Alias for B<ppm search>.

=item B<ppm repo suggest>

List some known repositories that can be added with B<ppm add>.  The
list only include repositories that are usable by this perl installation.

=item B<ppm repo sync> [ B<--force> ] [ B<--max-ppd> I<max> ] [ I<num> ]

Synchronize local cache of packages found in the enabled repositories.
With the B<--force> option, download state from remote repositories even
if the local state has not expired yet.  If I<num> is provided, only sync
the given repository.

PPM will need to download every PPD file for repositories that don't
provide a summary file (F<package.xml>).  This can be very slow for
large repositories.  Thus PPM refuses to start the downloads with
repositores linking to more that 100 PPD files unless the B<--max-ppd>
option provides a higher limit.

=item B<ppm search> I<pattern>

Search for packages matching I<pattern> in all enabled repositories.

For I<pattern>, use the wildcard C<*> to match any number of characters
and the wildcard C<?> to match a single character.  For example, to find
packages starting with the string "List" search for C<list*>. Searches
are case insensitive.

If I<pattern> contains C<::>, PPM will search for packages that provide
modules matching the pattern.

If I<pattern> matches the name of a package exactly (case-sensitively),
only that package is shown.  A I<pattern> without wildcards that does
not match any package names exactly is used for a substring search
against available package names (i.e. treated the same as
"B<*>I<pattern>B<*>").

The output format depends on how many packages match.  If there is only
one match, the B<ppm describe> format is used.  If only a few packages
match, limited information is displayed.  If many packages match, only
the package names and version numbers are displayed, one per line.

The number prefixing each entry in search output can be used to look
up full information with B<ppm describe> I<num>, dependencies with
B<ppm tree> I<num> or to install the package with B<ppm install>
I<num>.

=item B<ppm tree> I<package>

=item B<ppm tree> I<num>

Shows all the dependencies (recusively) for a particular package.  The
package can be identified by a package name or the associated number
for the package returned by the last C<ppm search> command.

=item B<ppm uninstall> ...

Alias for B<ppm remove>.

=item B<ppm update> ...

Alias for B<ppm upgrade>.

=item B<ppm upgrade> [ B<--install> ] [ B<--area> I<area> ]

List packages that there are upgrades available for.  With
B<--install> option install the upgrades as well.

=item B<ppm upgrade> [ B<--area> I<area> ] I<pkg>

=item B<ppm upgrade> [ B<--area> I<area> ] I<module>

Upgrades the specified package or module if an upgrade is available in
one of the currently enabled repositories.

If I<area> is given; install the upgrade to the given area instead of the
default.  You are responsible for making sure that the given area isn't
shadowed by another that contains an older version of the upgraded module.  If
so the upgrade would be not effective.

If no I<area> is given, then ppm tries to apply the upgrade to the same area
that the module was previously installed in.  If the module was installed in
a read-only area or not installed, then the default install location is used.

=item B<ppm verify> [ I<pkg> ]

Checks that the installed files are still present and unmodified.  If
the package name is given, only that packages is verified.

=item B<ppm version>

Will print the version of PPM and a copyright notice.

=back

=head1 FILES

The following lists files and directories that PPM uses and creates:

=over

=item F<$HOME/.ActivePerl/$VERSION/>

Directory where PPM keeps its state.  On Windows this directory is
F<$LOCAL_APPDATA/ActiveState/ActivePerl/$VERSION>.  The $VERSION is a string
like "818".

=item F<$HOME/.ActivePerl/$VERSION/ppm-$ARCH.db>

SQLite database where ppm keeps its configuration and caches meta
information about the content of the enabled repositories.

=item F<$HOME/.ActivePerl/ppm4.log>

Log file created to record actions that PPM takes.  On Windows this is
logged to F<$TEMPDIR/ppm4.log>.
On Mac OS X this is logged to F<$HOME/Library/Logs/ppm4.log>.

=item F<$PREFIX/etc/ppm-$NAME-area.db>

SQLite database where PPM tracks packages installed in the install area
under C<$PREFIX>.

=item F<$TEMPDIR/ppm-XXXXXX/>

Temporary directories used during install.  Packages to be installed
are unpacked here.

=item F<*.ppmx>

These files contains a single package that can be installed by PPM.
They are compressed tarballs containing the PPD file for the package
and the F<blib> tree to be installed.

=item F<*.ppd>

XML files containing meta information about packages.  Each package has
its own .ppd file.  See L<ActivePerl::PPM::PPD> for additional
information.

=item F<package.xml>

Meta information about repositories.  When a repository is added, PPM
looks for this file and if present, monitors it too stay in sync with
the state of the repository.

=item F<package.lst>

Same as F<package.xml> but PPM 3 compatible.  PPM will use this file
if F<package.xml> is not available.

=item F<package.db.gz>

The same information as found in F<package.xml> as a compressed SQLite database
image using PPM's internal database schema.  Repositories that provide this image
should also provide an F<package.xml> with the same information.

When only one repo is used it's faster for the client to just download and use
this database image, instead of parsing the F<package.xml> and build the
database from it locally.

=back

=head1 ENVIRONMENT

The following environment variables affect how PPM behaves:

=over

=item C<ACTIVEPERL_PPM_DEBUG>

If set to a TRUE value, makes PPM print more internal diagnostics.

=item C<ACTIVEPERL_PPM_BOX_CHARS>

Select what kind of box drawing characters to use for the C<ppm *
list> outputs.  Valid values are C<ascii>, C<dos> and C<unicode>.  The
default varies.

=item C<ACTIVEPERL_PPM_HOME>

If set, use this directory to store state and configuration
information for PPM.  This defaults to
F<$LOCAL_APPDATA/ActiveState/ActivePerl/$VERSION> on Windows and
F<$HOME/.ActivePerl/$VERSION/> on Unix systems.

=item C<ACTIVEPERL_PPM_LOG_CONS>

If set to a TRUE value, make PPM print any log output to the console as
well.

=item C<DBI_TRACE>

PPM uses L<DBI> to access the internal SQLite databases. Setting
DBI_TRACE allow you to see what queries are performed.  Output goes to
STDERR.  See L<DBI> for further details.

=item C<http_proxy>

PPM uses L<LWP> to access remote repositories.  If you need HTTP
traffic pass via a proxy server to reach the repository, you must set
the C<http_proxy> environment variable.  Some examples:

   Using bash:
       export http_proxy=http://proxy.mycompany.com

   Using cmd.exe:
       set http_proxy=http://username:password@proxy.mycompany.com:8008

See L<LWP::UserAgent/env_proxy> for more.

=back

=head1 SEE ALSO

L<ActivePerl>

L<http://search.cpan.org/dist/PPM-Repositories/>

=head1 COPYRIGHT

Copyright (C) 2013 ActiveState Software Inc.  All rights reserved.

=cut

__END__
:endofperl
