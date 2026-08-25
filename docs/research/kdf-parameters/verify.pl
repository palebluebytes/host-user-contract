# reads "password\nhash\n" on stdin — no $ ever reaches systemd-run's expander
use Time::HiRes qw(time);
chomp(my $pw = <STDIN>); chomp(my $st = <STDIN>);
my $t = time;
my $c = crypt($pw, $st);
printf("%s wall=%.3fs\n", (defined $c && $c eq $st) ? "MATCH" : "NOMATCH", time - $t);
