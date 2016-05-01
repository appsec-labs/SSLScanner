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
use Config qw(%Config);

my $htmldir = $Config{installhtmldir} || "$Config{prefix}/html";
my $index = "$htmldir/index.html";

die "No HTML docs installed at $htmldir\n"
    unless -f $index;

require ActiveState::Browser;
ActiveState::Browser::open($index);

__END__

=head1 NAME

ap-user-guide - open the ActivePerl User Guide in you browser

=head1 SYNOPSIS

B<ap-user-guide>

=head1 DESCRIPTION

This script opens up the "ActivePerl User Guide" in your web browser.
The user guide will not be available if ActivePerl was installed
without the HTML documentation.  If that's the case you can still use
the L<perldoc> command to read the core documentation and manpages for
the installed modules.

The script does not take any command line options.

=head1 ENVIRONMENT

Set the C<AS_BROWSER> environment variable to override what browser to
use.  See L<ActiveState::Browser> for details.

=head1 SEE ALSO

L<perldoc>, L<ActiveState::Browser>

__END__
:endofperl
