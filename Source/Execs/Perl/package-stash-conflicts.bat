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
#!/usr/bin/perl
#line 15

use strict;
use warnings;
# PODNAME: package-stash-conflicts

use Getopt::Long;
use Package::Stash::Conflicts;

my $verbose;
GetOptions( 'verbose|v' => \$verbose );

if ($verbose) {
    Package::Stash::Conflicts->check_conflicts;
}
else {
    my @conflicts = Package::Stash::Conflicts->calculate_conflicts;
    print "$_\n" for map { $_->{package} } @conflicts;
    exit @conflicts;
}

__END__

=pod

=head1 NAME

package-stash-conflicts

=head1 VERSION

version 0.36

=head1 AUTHOR

Jesse Luehrs <doy@tozt.net>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Jesse Luehrs.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

__END__
:endofperl
