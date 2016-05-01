###############################################################################
#
# Script:	config.pl
# Purpose:	Fix up Config.pm after a binary installation
#
# Copyright (c) 1999-2005 ActiveState Corp.  All rights reserved.
#
###############################################################################

use File::Basename qw(dirname);

my $prefix = dirname(dirname($^X));
my $libpth = $ENV{LIB};
my $user   = $ENV{USERNAME};
my $file   = $prefix . '\lib\Config.pm';
my $oldfile = $prefix . '\lib\Config.pm~';

$tmp = $ENV{'TEMP'} || $ENV{'tmp'};
if ($^O =~ /MSWin/) {
    $tmp ||= 'c:/temp';
}
else {
    $tmp ||= '/tmp';
}

print 'Configuring Perl ... ' . "\n";

# Remove the "command" value from the file association to prevent the MSI
# "Repair" feature from triggering once an included extension has been
# upgraded by PPM.
if ($^O =~ /MSWin/) {
    require Win32::Registry;
    $::HKEY_CLASSES_ROOT->Open('Perl\shell\Open\command', my $command);
    $command->DeleteValue('command') if $command;
}

my %replacements = (
	archlib			=> "'$prefix\\lib'",
	archlibexp		=> "'$prefix\\lib'",
	bin			=> "'$prefix\\bin'",
	binexp			=> "'$prefix\\bin'",
	cf_by			=> "'ActiveState'",
	installarchlib		=> "'$prefix\\lib'",
	installbin		=> "'$prefix\\bin'",
	installhtmldir		=> "'$prefix\\html'",
	installhtmlhelpdir 	=> "'$prefix\\htmlhelp'",
	installman1dir		=> "''",
	installman3dir		=> "''",
	installprefix		=> "'$prefix'",
	installprefixexp	=> "'$prefix'",
	installprivlib		=> "'$prefix\\lib'",
	installscript		=> "'$prefix\\bin'",
	installsitearch		=> "'$prefix\\site\\lib'",
	installsitebin		=> "'$prefix\\bin'",
	installsitelib		=> "'$prefix\\site\\lib'",
	libpth			=> q('") . join(q(" "), split(/;/, $libpth), $prefix . "\\lib\\CORE") . q("'),
	man1dir			=> "''",
	man1direxp		=> "''",
	man3dir			=> "''",
	man3direxp		=> "''",
	perlpath		=> "'$prefix\\bin\\perl.exe'",
	prefix			=> "'$prefix'",
	prefixexp		=> "'$prefix'",
	privlib			=> "'$prefix\\lib'",
	privlibexp		=> "'$prefix\\lib'",
	scriptdir		=> "'$prefix\\bin'",
	scriptdirexp		=> "'$prefix\\bin'",
	sitearch		=> "'$prefix\\site\\lib'",
	sitearchexp		=> "'$prefix\\site\\lib'",
	sitebin			=> "'$prefix\\site\\bin'",
	sitebinexp		=> "'$prefix\\site\\bin'",
	sitelib			=> "'$prefix\\site\\lib'",
	sitelibexp		=> "'$prefix\\site\\lib'",
	siteprefix		=> "'$prefix\\site'",
	siteprefixexp		=> "'$prefix\\site'",
);

my $pattern = '^(' . join('|', keys %replacements) . ')=.*';

chmod(0644, $file)
    or warn "Unable to chmod(0644, $file) : $!";
    
if(open(FILE, "+<$file")) {
    my @Config;
    while(<FILE>) {
	s/$pattern/$1=$replacements{$1}/;
	push(@Config, $_); 
    }

    seek(FILE, 0, 0);
    truncate(FILE, 0);
    print FILE @Config;
    close(FILE);
    chmod(0444, $file)
	or warn "Unable to chmod(0444, $file) : $!";
}
else {
    print "Unable to open $file : $!\n\n";
    print "Press [Enter] to continue:\n";
    <STDIN>;
    exit 1;
}

###############################################################################
# Config.pm values to propogate when doing an upgrade installation
###############################################################################
my @propagateThese = qw(
	ar
	awk
	bash
	bin
	binexp
	bison
	byacc
	cat
	cc
	cp
	cryptlib
	csh
	date
	echo
	egrep
	emacs
	expr
	find
	flex
	full_csh
	full_sed
	gccversion
	glibpth
	gzip
	incpath
	inews
	ksh
	ld
	lddlflags
	ldflags
	less
	libc
	libpth
	ln
	lns
	loincpth
	lolibpth
	lp
	lpr
	ls
	mail
	mailx
	make
	mkdir
	more
	mv
	mydomain
	myhostname
	myuname
	pager
	rm
	rmail
	sed
	sendmail
	sh
	tar
	touch
	tr
	usrinc
	vi
	xlibpth
	zcat
	zip
);

if(-f $oldfile) {
    mergeConfig($oldfile, $file);
}

###############################################################################
#
###############################################################################
sub mergeConfig {
    my $file1 = shift;
    my $file2 = shift;

    open(FILE1, "<$file1")
	|| do {
		warn "Could not open file $file1 : $!";
		return -1;
	};
    
    my $foundConfigBegin = 0;
    my $foundConfigEnd = 0;
    my %Config1 = ();
    while(<FILE1>) {
	chomp;
	if (!$foundConfigBegin && /^my \$config_sh = <<'!END!';$/) {
	    $foundConfigBegin = 1;
	    next;
	} 
	elsif (!$foundConfigEnd && /^!END!$/) {
	    last;
	}
	next if(!$foundConfigBegin);
	my ($name, $value) = split(/=/, $_, 2);
	if(grep(/$name/, @propagateThese)) {
	    $Config1{$name} = $value;
	}
    }
    close(FILE1);

    open(FILE2, "+<$file2")
	|| do {
		warn "Could not open file $file2 : $!";
		return -1;
	};

    $foundConfigBegin = 0;
    $foundConfigEnd = 0;
    my @Config2 = ();
    while(<FILE2>) {
	my $line = $_;
	chomp($line);
	if (!$foundConfigBegin && $line =~ /^my \$config_sh = <<'!END!';$/) {
	    $foundConfigBegin = 1;
	} 
	elsif (!$foundConfigEnd && $line =~ /^!END!$/) {
	    $foundConfigEnd = 1;
	}
	elsif ($foundConfigBegin && !$foundConfigEnd) {
	    my ($name, $value) = split(/=/, $line, 2);
	    if(exists $Config1{$name} && length($Config1{$name}) > 0) {
		$line = "$name=$Config1{$name}";
	    }
	}
	push(@Config2, $line . "\n");
    }
    truncate(FILE2, 0);
    seek(FILE2, 0, 0);
    print FILE2 (@Config2);
    close(FILE2);
    return; 
}

