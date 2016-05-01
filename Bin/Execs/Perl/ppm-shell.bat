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
BEGIN { $ENV{TERM} = "dumb" if $^O eq "MSWin32" }
use Term::ReadLine ();
use Text::ParseWords qw(shellwords);

system("ppm", "--version");
exit 1 if $? != 0;

my $term = new Term::ReadLine 'PPM';
my $prompt = "ppm> ";
my $OUT = $term->OUT || \*STDOUT;
while ( defined ($_ = $term->readline($prompt)) ) {
    last if /^(quit|exit)$/;
    my @w = shellwords($_);
    if (@w) {
	system("ppm", @w);
        $term->addhistory($_);
    }
}
print "\n";

__END__
:endofperl
