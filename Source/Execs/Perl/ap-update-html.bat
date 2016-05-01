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

my %opt;
if (@ARGV) {
    require Getopt::Long;
    Getopt::Long::GetOptions(
        \%opt,
	'force',
	'verbose',
    ) || usage();
    usage() if @ARGV;

    sub usage {
	(my $progname = $0) =~ s,.*[/\\],,;
	die "Usage: $progname [--force] [--verbose]\n";
    }
}

use ActivePerl::DocTools ();
ActivePerl::DocTools::UpdateHTML(raise_error => 1, %opt);

__END__

=head1 NAME

ap-update-html - Regenerate any out-of-date HTML

=head1 SYNOPSIS

B<ap-update-html> [ B<--force> ] [ B<--verbose> ]

=head1 DESCRIPTION

If new modules has been installed then they might not have had their
documentation converted to HTML yet.  This script will bring the HTML
up-to-date with what modules are installed.

The following command line options are recognized:

=over

=item B<--force>

Force HTML documents to be regenerated even if they appear to be
up-to-date.

=item B<--verbose>

Print noise about what's done while running.

=back

__END__
:endofperl
