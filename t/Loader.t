# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

use strict;
use warnings;

use Test::More qw(no_plan); 

use Oracle::Loader;
my $class = 'Oracle::Loader';
my $obj = Oracle::Loader->new;
diag("OBJ=$obj...");

isa_ok($obj, $class);

my ($v, @a);
my @md0 = ( qw(read_definition crt_sql crt_ctl
            check_infile create load batch read_log 
            sort_array compressArray report_results report_errors
    )); 
foreach my $m (@md0) {
    $obj->$m if ($m =~ /^(get_|set_)/); 
    can_ok($obj, $m);
}
diag("Test scalar parameter methods...");
my @md1 = (    # '$' - scalar parameter
      qw (cols_ref out_fh)
); 
my %df1 = (    # default values for '$' type parameters
    cols_ref=>undef, out_fh=>undef
);

1;

