package Oracle::Loader;

my  $VERSION = '1.11';
use strict;
use Carp;
use File::Basename;
use IO::File;

use Debug::EchoMessage qw(debug echoMSG set_param disp_param);

my $Debugging = 0;
my $modname = "Oracle::Loader";
# use Class::Struct;

=head1 NAME

Oracle::Loader - Perl extension for creating Oracle PL/SQL and control
file.

=head1 SYNOPSIS

  use Oracle::Loader;

  $ldr = Oracle::Loader->new;
  $ldr = Oracle::Loader->new(%args);
  $ldr->init;                     # only sets vbm(N),direct(N),reset(Y)
  $ldr->init(%args);              # set variables based on hash array
  $ldr->sync(%args);              # syncronize variables 
  $ldr->disp_param;               # display parameters 
  $ldr->crt_sql;                  # create PL/SQL file 
  $ldr->crt_ctl;                  # create control file 
  $ldr->crt_sql($crf,$fh,$apd,$tab,$rst);
  $ldr->crt_sql($crf,$fn,$apd,$tab,$rst);
  $ldr->crt_ctl($crf,$fh,$apd,$dat,$rst);
  $ldr->crt_ctl($crf,$fn,$apd,$dat,$rst);
  $ldr->create($typ,$cns,$sfn,$phm);
  $ldr->load($typ,$cns,$ctl,$phm,$log);
  $ldr->batch($typ,$cns,$sdr,$phm,$ext);
  $ldr->report_results($typ,$cns,$sdr,$ofn,$ext);
  $ldr->report_errors($typ,$cns,$sdr,$ofn,$ext);
  $ldr->read_log($sub,$log,$rno);

=head1 DESCRIPTION

The Loader module creates data definition language (DDL) codes 
for creating tables and control file to be used to load data 
into Oracle tables. It creates DDL codes based on column definitons 
contained in an array or read from a definition file. It also has 
reporting functions to generate SQL*Load error reports and load
result reports. 

The column definition array could be built from Data::Describe module.
It is actually an array with hash members and contains these hash 
elements ('col', 'typ', 'wid', 'max', 'min', 'dec', 'dft', 'req',
and 'dsp') for each column. The subscripts in the array are in 
the format of $ary[$col_seq]{$hash_ele}. The hash elements
are:

  col - column name
  typ - column type, 'N' for numeric, 'C' for characters, 
        'D' for date
  max - maximum length of the record in the column
  wid - column width. It is the max of the column length. If 
        'wid' presents, the max and min are not needed.
  min - minimum length of the record in the column
  dec - maximun decimal length of the record in the column
  dft - date format string, e.g., YYYY/MM/DD, 
        MON/DD/YYYY HH24:MI:SS
  req - whether there is null or zero length records in the 
        column only 'NOT NULL' is shown
  dsp - column description 

The module will use column definitons to create DDL codes and control
file using I<crt_sql> and I<crt_ctl> methods.

=cut

=head1 METHODS

=over 4

=item * the constructor new(%args)

Without any input, i.e., new(), the constructor generates an empty 
object. If any argument is provided, the constructor expects them in
the hash array format, i.e., in pairs of key and value. 

Input variables:

  %args - configuration parameters. The args are

    sql_fn    -  pl/sql file name
    ctl_fn    -  SQL*Loader control file name
    dat_fn    -  data file name for SQL*Loader
    bad_fn    -  bad file name for SQL*Loader
    dis_fn    -  discard file name for SQL*Loader
    def_fn    -  column definition file name
    def_ex    -  definition file name extent
    log_fn    -  log file name for SQL*Loader
    spool     -  spooling file name
    dbtab     -  Oracle table name
    dbts      -  Oracle tablespace name
    dbsid     -  Oracle SID/Database alias
    dbhome    -  Oracle home directory
    dbconn    -  Oracle connection string
    dbusr     -  Oracle user
    dbpwd     -  Oracle password
    ts_iext   -  tablespace initial extent
    ts_next   -  tablespace next extent
    db_type   -  database type: Oracle, MSSQL
    append    -  Y/N/O to append to sql and ctl files
    drop      -  Y/N to drop table in sql and
                         #     to append in ctl files
    vbm       -  Y/N to display more message
    direct    -  using direct load method in SQL*Loader
    overwrite -  over write existing sql and ctl files
    src_dir   -  directory where def files stored
    DirSep    -  directory separator
    commit    -  whether to create tables and load data in
                 batch load
    reset     -  whether to reset values when new value is
                 passed in.
    relax_req - relax constraint/requirement for creating tables
    add_center - add center number to every plate
    _counter   - internal counter
    study_number - study number

    cols_ref  - ref to column array
    out_fh    - output sql file handle
    conn      - connection array - ["DBI:Oracle:$db",$usr,$pwd]

Variables used or routines called:

  None

How to use:

   my $obj = new Oracle::Loader;      # or
      $obj = Oracle::Loader->new;     # or
      $obj = Oracle::Loader->new(
        dbconn=>"usr/pwd\@db",def_fn=>'myDef.txt');

Return: new empty or initialized class object.

The I<%args> can contain:

=cut

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->init(@_);
}

=over 4

=item * init(%attr)

Input variables:

  %attr - argument hash array 

Variables used or methods called: 

  None 

How to use:

  # use default value to initialize the object
  $self->init; 
  $self->init(%a); # use %a to initialize

Return: the initialized object.

This method initiates the parameters for the object. 

=back

=cut

sub init {
    my ($s, %args) = @_;
    foreach my $k (keys %args) { $s->{$k}=$args{$k}; }
    my $v1 ='conn,direct,reset,vbm,append,DirSep,commit,db_type,';
       $v1 .= 'relax_req';
    my $v2 = 'Oracle,N,Y,N,N,/,N,Oracle,Y';
    my @a = split /,/,$v1;
    my @b = split /,/,$v2;
    for my $i (0..$#a) { 
        my $k = $a[$i]; 
        $s->{$k}  = $b[$i] if ! exists $s->{$k};
        $args{$k} = $b[$i] if ! exists $args{$k};
    }
    $s->echoMSG("  - Initializing variables in $modname...");
    $s->sync(%args);
    return $s;
}

=over 4

=item * sync (%args)

Input variables:

  %args - argument hash array 

Variables used or methods called: 

  Debug::EchoMessage
    set_param - get parameter value from an array

How to use:

  # use default value to syncronile the object
  $self->sync; 
  $self->sync(%a); # use %a to syncronize

Return: the initialized object.

This method syncronizes the parameters. 

=back

=cut

sub _set_param {
    my $s = (ref $_[0]) ? shift : Oracle::Loader->new;
    my ($k, $r) = @_;
    return "" if ref($r) !~ /^(HASH|ARRAY)/;
    my $v = $s->set_param($k,$r); # get value from the $r
    # we check the parent object as well if $v is null
       $v = $s->set_param($k,$s) if $v =~ /^\s*$/; 
    $s->{$k} = $v;   # preserve the value
    return $v;
}

sub sync {
    my ($s, %args) = @_;
    # SYNC rule: the inputs will overwrite the defaults

    my $vbm = $s->_set_param('vbm',\%args); 
    my $rst = $s->_set_param('reset',\%args);
       $rst = ($rst eq 'Y') ? 1 : 0;
    my $sid = $s->_set_param('dbsid',\%args);
    my $ohm = $s->_set_param('dbhome',\%args); 
    # sync Oracle connection parameters
    my $cs  = $s->_set_param('dbconn', \%args);
    my ($usr, $pwd, $db) = ("","","");
    if ($cs =~ m{(\w+)/(\w+)\@(\w+)}) { ($usr,$pwd,$db) = ($1,$2,$3); }
    $usr = $s->_set_param('dbusr',\%args) if ! $usr; 
    $pwd = $s->_set_param('dbpwd',\%args) if ! $pwd; 
    $sid = (!$sid && exists $ENV{ORACLE_SID}) ? $ENV{ORACLE_SID} : $sid;
    $ohm = (!$ohm && exists $ENV{ORACLE_HOME})? $ENV{ORACLE_HOME}: $ohm;
    $usr = (!$usr && exists $ENV{USER})? $ENV{USER}: $usr;
    $db  = (($db ne $sid) && $db) ? $db : ($sid ? $sid : $db); 
    $s->{dbconn} = "$usr/$pwd\@$db";
    $s->{conn} = ["DBI:Oracle:$db",$usr,$pwd]; 
    $s->{dbusr} = $usr; 
    $s->{dbpwd} = $pwd;
    $s->{dbsid} = $db;
    $s->{dbhome} = $ohm;

    # sync file names 
    my $dat = $s->_set_param('dat_fn',\%args); 
    my $sql = $s->_set_param('sql_fn',\%args); 
    my $def = $s->_set_param('def_fn',\%args); 
    my $log = $s->_set_param('log_fn',\%args); 
    my $dis = $s->_set_param('dis_fn',\%args); 
    my $bad = $s->_set_param('bad_fn',\%args); 
    my $ctl = $s->_set_param('ctl_fn',\%args); 
    my $tab = $s->_set_param('dbtab',\%args); 
    my ($bnm,$dir,$typ);
    if ($dat||$def) {
        ($bnm,$dir,$typ)=fileparse($dat,'\.\w+$') if ($dat);
        ($bnm,$dir,$typ)=fileparse($def,'\.\w+$') if ($def);
        my $rfn = "$dir$bnm";
        if ($rst) { 
            $s->{log_fn} = "${rfn}.log";
            $s->{dis_fn} = "${rfn}.dis";
            $s->{bad_fn} = "${rfn}.bad";
        }
        $s->{log_fn} = "${rfn}.log" if ! $log;
        $s->{dis_fn} = "${rfn}.dis" if ! $dis;
        $s->{bad_fn} = "${rfn}.bad" if ! $bad;
        $s->{dat_fn} = "${rfn}.dat" if ! $dat;
        $s->{dbtab}  = "$bnm"       if ! $tab;
        $s->{sql_fn} = "${rfn}.sql" if ! $sql;
        $s->{ctl_fn} = "${rfn}.ctl" if ! $ctl;
        # check the file size of the input data file
        # 1mb=1048576 bytes
        if (-f $dat) {
            my $MB=1048576;
            my $fsz = -s $dat; 
            my $sz = (int $fsz/1024) + 1;
            my($sz1,$sz2);
            if ( $sz > 1024) { 
                $sz1 = sprintf "%dm", (int $sz/1024) + 1; 
                $sz2 = sprintf "%dk", ((int $sz/1024) + 1)*10; 
            } else {
                $sz1 = sprintf "%dk", $sz; 
                $sz2 = sprintf "%dk", int ($sz/10); 
            }
            $s->{ts_iext} = "$sz1";
            $s->{ts_next} = "$sz2";
        }
    }
    if ($s->{sql_fn}) {
        ($bnm,$dir,$typ)=fileparse($s->{sql_fn},'\.\w+$');
        if (!$s->{spool}||$rst)  { $s->{spool} = "$dir${bnm}.lst"; }
        if (!$s->{dbtab} && !$dat) {
            if (!$s->{dbtab}) { $s->{dbtab} = $bnm; }
        }
    }
    foreach my $k (keys %args) {
        $s->{$k} = $args{$k} if ! exists $s->{$k}; 
    }
    return $s;
}


=over 4

=item * read_definitoin ($dfn, $typ) 

Input variables: 

  $dfn - definition file name. If not specified, 
         I<param->def_fn> method will be called.
  $typ - definition file type. Not implemented at 
         this version.

Variables used or methods called: None.

  param->def_fn - get definition file name
  param->reset  - reset parameters?
  cols_ref      - get/set column reference

How to use:

  $self->read_definition($fn); 

Return: none.

This method reads a column definition file and sets the definition
column array. It espects the definiton file to contain one column 
definition per line with vertical bar delimiting the definition. 
Here are the definitions: 

  1. SAS Dataset Name and Path|
  2. ASCII File Name and Path|
  3. Variable Name|
  4. Variable Length|
  5. Variable Type (1=num 2=char 3=date)|
  6. Variable Date Format|
  7. Variable Label|
  8. All Values Exist?

Here is an example:

  #SAS|ASCII|VarName|VarLength|VarType|DateFmt|VarLabel|NotNull
  ||STUDYNO|3|number||Study Number|not null
  ||CENTERNO|3|number||Center Number|
  ||PATIENTS|7|number||Center Patients|
  ||VISITS|7|number||Center Patients|
  ||RECORDS|7|number||Center Patients|
  ||Fax_In|6.1|number||Mean # Days from Visit to Fax In|
  ||DB_Entry|6.1|number||Mean # Days from Visit to DB entry|
  ||DB_Clean|6.1|number||Mean # Days from Visit to DB clean|
  ||clean_now|5.1|number||Percent Records Clean Now|
  ||job_id|9|number||Report Job number|not null

=back

=cut

sub read_definition {
    my $self = shift; 
    my $dfn  = shift if ($_[0]);  # definition file name
    my $typ  = shift if ($_[0]);  # definition file type
       $dfn  = $self->{def_fn} if !$dfn; 
    my $rst  = $self->{reset}; 
    $self->{def_fn} = $dfn     if $rst; 
    if (!$dfn) { croak "No definition file name is specified."; }
    if (! -f $dfn) { croak "Could not find definition file - $dfn."; }
    $self->echoMSG("  - Defining column array from $dfn...");
    open DEF, "<$dfn" or croak "Could not open file - $dfn: $!";
    my (@a,@r);
    my $i = -1;                   # def column index
    my @T=();  $T[1]='N'; $T[2]='C'; $T[3]='D';
    my %T=();  $T{'Y'}='NOT NULL';   $T{'N'}="";
    while (<DEF>) {
        chomp;
        next if ($_ =~ /^#/);     # skip comment lines
        next if (!$_);            # skip empty lines
        ++$i;
        # 0 - SAS Dataset Name and Path
        # 1 - ASCII File Name and Path
        # 2 - Variable Name
        # 3 - Variable Length
        # 4 - Variable Type (1=num 2=char 3=date)
        # 5 - Variable Date Format
        # 6 - Variable Label
        # 7 - All Values Exist?
        @a=split /\|/, $_;
        $r[$i]{'col'} = $a[2]; 
        if ($a[3] =~ /(\d+)\.(\d+)/) {    # such as 6.2
            $r[$i]{'wid'} = $1;
            $r[$i]{'dec'} = $2;
        } else {                          # such as 6
            $r[$i]{'wid'} = $a[3];
            $r[$i]{'dec'} = 0;
        }
        $a[4] = "" if ! defined($a[4]); 
        $a[4] =~ s/\s*(.*)\s*/$1/;     # trim spaces
        if ($a[4] =~ /^(1|2|3)$/) { 
            $r[$i]{'typ'} = $T[$a[4]];
        } else {
            $r[$i]{'typ'} = $a[4];
        }
        if ($a[5] =~ /^MMDDYY10/) {
            $r[$i]{'dft'} = "MM/DD/YYYY";  
        } elsif ($a[5] =~ /YYMMDD10/) {
            $r[$i]{'dft'} = "YYYY/MM/DD";  
        } elsif ($a[5] =~ /MMDDYY8/) {
            $r[$i]{'dft'} = "MM/DD/YY";  
        } elsif ($a[5] =~ /YYMMDD8/) {
            $r[$i]{'dft'} = "YY/MM/DD";  
        } else {
            $r[$i]{'dft'} = $a[5];  
        }
        $r[$i]{'dsp'} = $a[6];
        $a[7] = "" if ! defined($a[7]); 
        $a[7] =~ s/\s*(.*)\s*/$1/;     # trim spaces
        if ($a[7] =~ /^(Y|N)$/) { 
            $r[$i]{'req'} = $T{$a[7]};
        } else {
            $r[$i]{'req'} = $a[7];
        }
        if (uc($a[2]) =~  /^(DFCREATE|DFMODIFY)/) {
            $r[$i]{'typ'} = 'DATE';
            $r[$i]{'dft'} = "YYYY/MM/DD HH24:MI:SS";
        }
    }
    close DEF;
    $self->{cols_ref} = \@r;
    return $self->{cols_ref};
}

=over 4

=item * crt_sql($arf,$ofn,$apd,$tab,$rst,$drp) 

Input variables:

  $arf - array ref containing column definitions.
         If not specified, it defaults to I<cols_ref>. 
  $ofn - output file name. The file will contains
         the sql codes. It defaults to I<out_fh> or
         I<sql_fn>.
  $apd - whether to append if the output file 
         exists. It defaults to I<param->append>.
  $tab - database table name. It defaults to
         I<param->dbtab>.
  $rst - whether to reset parameters based on the
         specified parameters here. It defaults to
         I<param->reset>.
  $drp - whether to drop the table before create it.
         The default is 'Y'. 

Variables used or methods called: 

  param  - get parameters

How to use:

  $self->crt_sql($arf, 'mysql.sql','Y', 'mytab'); 

Return: create PL/SQL codes for creating Oracle tables.

This method creates PL/SQL codes based on the columns defined in
the definition array. You can access the array reference as
${$arf}[$i]{$k}. The $k could be 'col', 'typ', 'wid', 'max', 'min', 
'dec', 'dft', and 'req'. Some special keys are stored in the first
element of the array, i.e., ${$arf}[0].  They are

  table_name - table name. It is used as the last 
               resource in getting a table name.  
  table_desc - table title/description used to 
               create table comments. 

=back

=cut

sub crt_sql {
    my $self     = shift; 
    # initialize variables and check inputs 
    #   (ColRef,SQLFN,Appd,OraTab,ReSet)
    my($crf,$fh,$fn,$appd,$tab,$rst,$drp)=
        $self->_getInputs('crt_sql',@_);
    # print "$crf,$fh,$fn,$appd,$tab,$rst\n";

    if (exists ${$crf}[0]{'table_name'}) {
        $tab = ${$crf}[0]{'table_name'} if !$tab;
    }

    my $counter = 0;
       $counter = $self->{_counter} if exists $self->{_counter}; 
    my ($bnm,$dir,$typ)=fileparse($fn,'\.\w+$');
    my $lst = "$dir${bnm}.lst";
    my $st = localtime(time);

    my $txt = "";                             # SQL codes
    if ($fn) { $txt .= "REM file name: $fn\n"; 
    } else {   $txt .= "REM\n"; }
    $txt .= "REM created at $st\n";
    $txt .= "REM created by Oracle::Loader->crt_sql\nREM\n";
    if ($appd eq 'Y') {
        if ($counter==1) { $txt .= "spool $lst\n"; }
    } else {
        $txt .= "spool $lst\n"; 
    }

    if ($drp eq 'Y') {
        $txt .= "DROP TABLE $tab;\n";
    } else {
        $txt .= "-- DROP TABLE $tab;\n";
    }
    $txt .= "CREATE TABLE $tab (\n";

    my $fmt = "    %-15s %-23s %12s\n";
    my ($col,$wid,$dft,$req,$otp,$orq,$dec,$dsp);
    my $rlx = $self->set_param('relax_req', $self); 
    my $ts_iext = $self->set_param('ts_iext', $self); 
    my $ts_next = $self->set_param('ts_next', $self); 
    my $dbts    = $self->set_param('dbts', $self); 
    for my $i (0..$#{$crf}) {          # loop thru each column
        $col = uc(${$crf}[$i]{'col'}); # column name
        $col = "\"$col\"";
        $typ = uc(${$crf}[$i]{'typ'}); # column type
        if ($typ =~ /^N$/) { $typ = 'NUMBER'; }
        if ($typ =~ /^D$/) { $typ = 'DATE'; }
        if ($typ =~ /^C$/) { $typ = 'VARCHAR2'; }
        $wid = "";
        if (${$crf}[$i]{'wid'}) {      # use 'wid' first 
            $wid = uc(${$crf}[$i]{'wid'}); # column width
        } 
        if (!$wid) {                   # use 'max' 
            $wid = uc(${$crf}[$i]{'max'}); # column width
        }
        $dft = uc(${$crf}[$i]{'dft'}); # column type
        $req = uc(${$crf}[$i]{'req'}); # requirement/constraint
        $dec = uc(${$crf}[$i]{'dec'}); # decimal 
        $otp = "";                     # Oracle type
        # print "$col:$typ:$wid:$dec:$req\n";
        if ($dec ne "" && $wid && $typ =~ /^N/i) {
            if ($wid > $dec) { $wid .= ",$dec"; }
            # print "--$col:$wid\n";
        } 
        if ($wid && $typ !~ /^D/i) { $otp = "$typ($wid)";
        } else { $otp = $typ; }
        $orq="";
        if ($req && $typ !~ /^D/i && ("$rlx" ne 'Y' || 
            $col =~ /(^ID|ID$)/) ) { $orq = $req; }
        if ($i == $#{$crf}) { 
            my $t = "";
            if ($ts_iext || $ts_next) {
                $t .= "STORAGE (\n";
                if ($ts_iext) {
                    $t .= "  INITIAL " . $ts_iext . "\n";
                }
                if ($ts_next) {
                    $t .= "  NEXT    " . $ts_next . "\n";
                }
                $t .= ");\n";
            }
            if ($dbts) {
                $txt .=  sprintf $fmt, $col, $otp, $orq . ')';
                $txt .= "TABLESPACE " . $dbts . "\n";
                if ($t) { $txt .= $t; } else { $txt .= ";\n"; }
            } else {
                $txt .=  sprintf $fmt, $col, $otp, $orq . ');';
            }
            $txt .= "GRANT SELECT ON $tab TO PUBLIC;\n";
        } else {
            $txt .= sprintf $fmt, $col, $otp, $orq . ',';
        }
    }
    if (exists ${$crf}[0]{'table_desc'}) {
        $dsp = ${$crf}[0]{'table_desc'}; 
        $dsp =~ s/\'/ /g;              # change single quote to blank
        $dsp =~ s/\&/and/g;            # change & sign to 'and'
        $txt .= "COMMENT ON TABLE ${tab} IS\n  '$dsp'}';\n";
    }
    # create comment for columns
    for my $i (0..$#{$crf}) {          # loop thru each column
        $col = uc(${$crf}[$i]{'col'}); # column name
        $dsp = ${$crf}[$i]{'dsp'};     # column description 
        $dsp =~ s/\'/ /g   if $dsp;    # change single quote to blank
        $dsp =~ s/\&/and/g if $dsp;    # change & sign to 'and'
        next if !$dsp;
        $txt .= "COMMENT ON COLUMN ${tab}.$col IS\n  '$dsp';\n";
    }
    if ($appd eq 'Y') {
        if ($counter eq 'N') { $txt .= "spool off\nexit\n"; }
    } else { $txt .= "spool off\nexit\n"; }
    print $fh $txt;
    $fh->close;
}

=over 4

=item * crt_ctl ($arf, $ofn, $apd, $dat, $rst, $drp) 

Input variables:

  $arf - array ref containing column definitions.
         If not specified, it defaults to I<cols_ref>. 
  $ofn - output file name. The file will contains
         the sql codes. It defaults to I<out_fh>
         or I<ctl_fn>.
  $apd - whether to append if the output file 
         exists. It defaults to I<param->append>.
  $dat - input data file name. It defaults to
         I<param->dat_fn>.
  $rst - whether to reset parameters based on the
         specified parameters here. It defaults to
         I<param->reset>.
  $drp - whether drop records before appending

Variables used or methods called: 

  param  - get parameters

How to use:

  $self->crt_sql($arf, 'mysql.ctl','N', 'mytxt.dat'); 

Return: create control file to be used by sql*loader.

This method creates a SQL*Loader control file. 

=back

=cut

sub crt_ctl {
    my $self     = shift; 
    # initialize variables and check inputs 
    #   (ColRef,FH/CTLFN,Appd,DataFile,ReSet)
    my($crf,$fh,$fn,$appd,$dat,$rst,$drp)=
        $self->_getInputs('crt_ctl',@_);
    if (!-f $dat) { carp "Input data file - $dat does not exist."; }

    my ($bnm,$dir,$typ);
    if ($dat) {
        ($bnm,$dir,$typ)=fileparse($dat,'\.\w+$');
    } else {
        ($bnm,$dir,$typ)=fileparse($fn,'\.\w+$');
    }
    my $bad = "$dir${bnm}.bad";
    my $dis = "$dir${bnm}.dis";
    my $log = "$dir${bnm}.log";
    my $tab = $self->set_param('dbtab',$self);
    if ($rst) {
        $self->set_param('bad_fn',$self,$bad);
        $self->set_param('dis_fn',$self,$dis);
        $self->set_param('log_fn',$self,$log);
    }
    $self->set_param('dbtab',$self,$bnm) if !$tab;
    $tab = $self->set_param('dbtab',$self);
    if (!$tab) { carp "Oracle table name is not specified."; }

    my $fmt = "    %-15s %-23s %-2s\n";
    my $st = localtime(time);
    my $direct = $self->set_param('direct',$self);

    # start constructing control file
    my $txt = "";                             # SQL codes
    # if ($fn) { $txt .= "# file name: $fn\n"; 
    # } else {   $txt .= "#\n"; }
    # $txt .= "# created at $st\n";
    # $txt .= "# created by Oracle::Loader->crt_ctl\n#\n";
    if ($direct eq 'Y') {
        $txt .= "OPTIONS (ERRORS=1000,SILENT=FEEDBACK,DIRECT=TRUE)\n";
        $txt .= "UNRECOVERABLE";
    } else {
        $txt .= "OPTIONS (ERRORS=1000,SILENT=FEEDBACK)\n";
    }
    $txt .= "LOAD DATA\nINFILE \'$dat\'\nBADFILE \'$bad\'\n";
    $txt .= "DISCARDFILE \'$dis\'\n";
    # $txt .= "LOGFILE \'$log\'\n";
    if ($drp eq 'Y') { 
        $txt .= "REPLACE INTO TABLE $tab\n";
    } else {
        $txt .= "APPEND INTO TABLE $tab\n";
    }
    $txt .= "FIELDS TERMINATED BY \"|\" OPTIONALLY ENCLOSED BY ";
    $txt .= "\"'\"\n    TRAILING NULLCOLS\n";
    $txt .= "(\n";
    my ($col,$wid,$dft,$req,$otp,$dec);
    for my $i (0..$#{$crf}) {          # loop thru each column
        $col = uc(${$crf}[$i]{'col'}); # column name
        $col = "\"$col\"";
        $typ = uc(${$crf}[$i]{'typ'}); # column type
        if ($typ =~ /^N$/) { $typ = 'NUMBER'; }
        if ($typ =~ /^D$/) { $typ = 'DATE'; }
        if ($typ =~ /^C$/) { $typ = 'VARCHAR2'; }
        $wid = "";
        if (${$crf}[$i]{'wid'}) {      # use 'wid' first 
            $wid = uc(${$crf}[$i]{'wid'}); # column width
        } 
        if (!$wid) {                   # use 'max' 
            $wid = uc(${$crf}[$i]{'max'}); # column width
        }
        $dft = uc(${$crf}[$i]{'dft'}); # column type
        $req = uc(${$crf}[$i]{'req'}); # requirement/constraint
        $dec = uc(${$crf}[$i]{'dec'}); # decimal 
        $dft = uc(${$crf}[$i]{'dft'}); # date format
        if ($dec >=0 && $wid && $typ =~ /^N/i) {
            if ($wid > $dec) { $wid .= ",$dec"; }
        } 
        $otp = "";                     # Oracle type
        if ($wid && $typ =~ /^CHAR/i) { $otp = lc("$typ($wid)");
        } elsif ( $typ =~ /^D/i) {      $otp = lc($typ); }
        if ($typ =~ /^D/ && $dft) {
            $otp .= " \"$dft\" NULLIF $col=BLANKS";
        }
        # if ($req && $typ !~ /^D/i) { $otp .= "  $req"; }
        if ($i == $#{$crf}) { 
            $txt .= sprintf $fmt, $col, $otp, ')';
            $txt .= "\n";
        } else {
           $txt .= sprintf $fmt, $col, $otp, ',';
        }
    }
    print $fh $txt;
    $fh->close;
}

=over 4

=item * check_infile ($ctl,$typ) 

Input variables:

  $ctl - control file name
  $typ - routine type: load, create, etc.

Variables used or methods called: 

  echoMSG   - echo messages

How to use:

  $self->check_infile($inf);

Return: boolean, i.e., 1 for OK, 0 for not OK.

This method checks whether there is INFILE parameter in control file,
whether the infile exisit and has non-zero size.

=back

=cut

sub check_infile {
    my $self     = shift; 
    my ($ctl,$typ) = @_;
    #
    # 05/07/2002: htu - added check on infile
    my $msg = "    no CTL file specified."; 
    $self->echoMSG($msg) if !$ctl;
    return 0 if !$ctl;
    open CTL, "<$ctl" or croak "ERR: Could not open $ctl: $!\n";
    my $inf = "";    # infile name 
    while (<CTL>) {
        if ($_ =~ /^INFILE\s+\'(.*)\'/i) {
            $inf = $1; last;
        }
    }
    close CTL;
    if ($inf && !-f $inf) {
        $msg = "    INFILE $inf does not exist.\n    $typ: skipped.";
        $self->echoMSG($msg);
        return 0;
    }
    if ($inf && -z $inf) {
        $msg = "    INFILE $inf is empty.\n    $typ: abandoned.";
        $self->echoMSG($msg);
        return 0;
    }
    if (!$inf) {
        $msg = "WARNNING: could not find INFILE file name in $ctl.";
        $self->echoMSG($msg);
    }
    return 1;
}

=over 4

=item * create ($typ, $cns, $sfn, $phm) 

Input variables:

  $typ - DB type: Oracle, MSSQL, etc. It defaults to
         Oracle
  $cns - connection string: usr/pwd@db
  $sfn - sql file name
  $phm - program (sqlldr) home directory 

Variables used or methods called: 

  param   - class method to get parameters

How to use:

  $self->create; 
  $self->create('', 'usr/pwd@db'); 

Return: None. 

This method creates the tables by running SQL*Plus or other program
corresponding to its database. 

=back

=cut

sub create {
    my $self     = shift; 
    #   creat: $typ, $cns, $sfn, $phm
    #   $typ - DB type: Oracle, MSSQL,
    #   $cns - connection string: usr/pwd@db
    #   $sfn - sql file name
    #   $phm - program (sqlldr) home directory 
    # 
    my ($typ,$cns,$sfn,$hmd)=$self->_getInput2('create', @_);
    $self->echoMSG("  - Creating $typ tables\n    using $sfn...");
    # 05/07/2002: htu - added for infile checking
    my $ctl = $self->{ctl_fn};
    return if (!$self->check_infile($ctl, 'create'));
    if (!$cns) {
        $self->echoMSG("ERR: no connection string is defined.");
        return;
    }
    my $DirSep = $self->set_param('DirSep',$self);
    my $vbm    = $self->set_param('vbm',$self);
    my $cmd = join $DirSep, $hmd, "bin", "sqlplus";
       $cmd .= " -s $cns \@$sfn ";
    # my @a=($sps, " -s ", "$cns ", "\@$sfn");
    # system (@a);
    if ($vbm eq 'Y') {
        my $tmp=$cmd;
        $tmp =~ s{(\w+)/(\w+)\@}{$1/\*\*\*\@};
        $tmp =~ s{( \@)}{\n        $1}g;
        print "    CMD: $tmp\n";
    } 
    open CMD, "$cmd |" or croak "Could not run sqlplus: $!\n";
    my @a = <CMD>;
    close CMD;
    if ($vbm eq 'Y') {
        for my $i (0..$#a) { print $a[$i]; }
    }
}

=over 4

=item * load ($typ, $cns, $ctl, $phm, $log) 

Input variables:

  $typ - DB type: Oracle, MSSQL, etc. It defaults to
         Oracle
  $cns - connection string: usr/pwd@db
  $ctl - control file name
  $phm - program (sqlldr) home directory 
  $log - log file name

Variables used or methods called: 

  param   - class method to get parameters

How to use:

  $self->load; 
  $self->load('', 'usr/pwd@db'); 

Return: None. 

This method loads that data into a corresponding table. For Oracle, 
sqlldr is used to load the data into the table. 

=back

=cut

sub load {
    my $self     = shift; 
    #    load: $typ, $cns, $ctl, $phm, $log
    #   $typ - DB type: Oracle, MSSQL,
    #   $cns - connection string: usr/pwd@db
    #   $ctl - control file name
    #   $phm - program (sqlldr) home directory 
    #   $log - log file name
    # 
    my ($typ,$cns,$ctl,$hmd,$log)=$self->_getInput2('load', @_);
    my $msg = "  - Loading data into $typ tables\n    using $ctl...\n";
       $msg .= "    logging in $log...";
    $self->echoMSG($msg);
    return if (!$self->check_infile($ctl,'load')); 
    if (!$cns) {
        $self->echoMSG("ERR: no connection string is specified.");
        return;
    }
    my $cmd = "";        # loader program
    my $DirSep = $self->set_param('DirSep',$self);
    my $vbm    = $self->set_param('vbm',$self);
    if ($typ eq "Oracle")     { 
        $cmd  = join $DirSep, $hmd, "bin", "sqlldr";
        $cmd .= " $cns control=$ctl log=$log 2>&1";
        $ENV{'ORACLE_HOME'} = $hmd; 
        $ENV{'PATH'} = "$hmd/bin:$hmd/lib:/usr/bin:/usr/local/bin:."; 
        $ENV{'LD_LIBRARY_PATH'} = "$hmd/lib"; 
    } elsif ($typ eq "MSSQL") { 
        $cmd = join "\\", $hmd, "bin", "osql";
    } 
    if ($vbm eq 'Y') {
        my $tmp=$cmd;
        $tmp =~ s{(\w+)/(\w+)\@}{$1/\*\*\*\@};
        $tmp =~ s{(\w+)=}{\n        $1=}g;
        print "    CMD: $tmp\n";
    } 
    open CMD, "$cmd |" or croak "Could not run sqlldr: $!\n";
    my @a = <CMD>;
    close CMD;
    if ($vbm eq 'Y') {
        for my $i (0..$#a) { print $a[$i]; }
    }
}

=over 4

=item * batch ($typ, $cns, $sdr, $phm, $ext)

Input variables:

  $typ - DB type: Oracle, MSSQL, etc. It defaults to
         Oracle
  $cns - connection string: usr/pwd@db
  $sdr - source directory containing all the definition files
  $phm - program (sqlplus, sqlldr, etc.) home directory 
  $ext - definition file extension such as "def", "var", etc.
         It uses 'def_ex' if it is set, otherwise default to
         'def'.

Variables used or methods called: 

  param   - class method to get parameters
  crt_sql - create PL/SQL codes
  crt_ctl - create Oracle control file

How to use:

  $self->batch; 
  $self->batch('', 'usr/pwd@db', '/my/load/dir'); 

Return: None. 

This method calls I<read_definition>, I<crt_sql>, I<crt_ctl>, 
I<create>, I<load> methods to run through all the definition files
in a source directory. 

=back

=cut

sub batch {
    my $self     = shift; 
    #   batch: $typ, $cns, $sdr, $phm, $ext
    #   $typ - database type: Oracle, MSSQL
    #   $cns - connection string: usr/pwd@db
    #   $sdr - source directory containing all the definition files
    #   $phm - program (sqlplus, sqlldr, etc.) home directory 
    #   $ext - definition file extension such as "def", "var", etc.
    #
    my ($typ,$cns,$sdr,$hmd,$ext)=$self->_getInput2('batch', @_);
    if (!-d $sdr) { croak "Could not find source directory - $sdr."; }
    $self->echoMSG("  - Batch loading data from $sdr...");
    # get a list of def file names
    my $DirSep = $self->set_param('DirSep',$self);
    my $vbm    = $self->set_param('vbm',$self);
    my $overwrite= $self->set_param('overwrite',$self);
    my $sql_fn = $self->set_param('sql_fn',$self);
    opendir(DIR, "$sdr") || 
        croak "Unable to open directory - $sdr: $!\n";
    my $dsp = $DirSep;
    my @fn = map "$sdr$dsp$_", grep /$ext$/, readdir DIR; 
    closedir DIR;
    if (!@fn) {
        print "    No definition files in $sdr!\n"; 
        return;
    }
    my $apd_cur = $self->set_param('append',$self);
    my $rst_cur = $self->set_param('reset',$self);
    my $dbtab_cur = $self->set_param('dbtab',$self);
    my $dat_fn_cur = $self->set_param('dat_fn',$self);
    my $def_fn_cur = $self->set_param('def_fn',$self);
    my $sql_fn_cur = $self->set_param('sql_fn',$self);
    my $ctl_fn_cur = $self->set_param('ctl_fn',$self);
    my $log_fn_cur = $self->set_param('log_fn',$self);
    $self->set_param('append',$self, 'Y');
    $self->set_param('reset',$self, 'Y');

    unlink $sql_fn if $overwrite eq 'Y' && -f $sql_fn;
    my ($bnm,$dir,$suf,$sfn,$ctl,$phm,$log);
    $phm = $self->set_param('dbhome',$self);
    my $dbtab = $self->set_param('dbtab',$self);
    for my $i (0..$#fn) {
        if ($vbm eq 'Y') { printf " %2d $fn[$i]\n", $i; }
        $self->read_definition($fn[$i]);
        $self->{dbtab} = "";
        $self->{_counter} = $i+1;
        if ($i==$#fn) { $self->{_counter} = 'N'; }
        $self->sync;
        if ($self->{append} eq 'Y' && $i==0) { 
            unlink $self->{sql_fn};
        }
        $self->crt_sql;
        $self->crt_ctl;
    }
    if ($self->{append} eq 'Y') {     # only one pl/sql program to run
        if ($self->{commit} eq 'Y') { $self->create; }
    }
    if ($self->{commit} eq 'Y') {
        for my $i (0..$#fn) {
            ($bnm,$dir,$suf)=fileparse($fn[$i],'\.\w+$');
            $sfn = "$dir${bnm}.sql";
            $ctl = "$dir${bnm}.ctl";
            $log = "$dir${bnm}.log";
            # we need to create table one by one
            if ($self->{append} ne 'Y') { 
                # creat: $typ, $cns, $sfn, $phm
                $self->create($typ,$cns,$sfn,$phm); 
            }
            # load: $typ, $cns, $ctl, $phm, $log
            $self->load($typ,$cns,$ctl,$phm,$log);
        }
    }
    $self->{append} = $apd_cur;
    $self->{reset}  = $rst_cur;
    $self->{dbtab}  = $dbtab_cur;
    $self->{dat_fn} = $dat_fn_cur;
    $self->{def_fn} = $def_fn_cur;
    $self->{sql_fn} = $sql_fn_cur;
    $self->{ctl_fn} = $ctl_fn_cur;
    $self->{log_fn} = $log_fn_cur;
}

=over 4

=item * read_log ($typ, $ifn, $rno)

Input variables:

  $typ - type of information that is extracted from the log file.
         The types are: result or error
  $ifn - log file name
  $rno - record number

Variables used or methods called: 

  param   - class method to get parameters
  sort_array    - sort a numeric array 
  compressArray - compress an array of numbers 
                  into a list of range or comma 
                  delimited numbers

How to use:

  $self->read_log('','mylog.log');

Return: None. 

This method reads a SQL*Loader log file and return loading result or
loading errors based on request. 

=back

=cut

sub read_log {
    my $self     = shift; 
    my ($typ, $ifn, $rno) = @_;
    # Input variables:
    #   $typ - type of information that is extracted from the log file.
    #          The types are: result or error
    #   $ifn - log file name
    #   $rno - record number
    #
    if (!-f $ifn) { 
        carp "WARNING: file - $ifn does not exist!";
        return;
    }
    my $msg = sprintf "   %3d reading $ifn...", $rno;
    $self->echoMSG($msg);
    # Purpose: extract load result from SQL*Loader log file and
    #   generate a bar delimited record with the following columns:
    #    1 - Success Rate
    #    2 - Oracle table name
    #    3 - Rows successfully loaded
    #    4 - Rows not loaded due to data errors
    #    5 - Rows not loaded because all WHEN clauses were failed
    #    6 - Rows not loaded because all fields were null
    #    7 - Total logical records skipped
    #    8 - Total logical records read
    #    9 - Total logical records rejected
    #   10 - Total logical records discarded
    #   11 - Start time
    #   12 - End time
    #   13 - Elapsed time
    #   14 - CPU time
    #
    my $hdr = "";
    if ($typ eq 'result') {
        $hdr  = "# Table columns:\n#    1 - Success Rate\n";
        $hdr .= "#    2 - Oracle table name\n";
        $hdr .= "#    3 - Rows successfully loaded\n";
        $hdr .= "#    4 - Rows not loaded due to data errors\n";
        $hdr .= "#    5 - Rows not loaded because all WHEN ";
        $hdr .= "clauses were failed\n";
        $hdr .= "#    6 - Rows not loaded because all fields ";
        $hdr .= "were null\n";
        $hdr .= "#    7 - Total logical records skipped\n";
        $hdr .= "#    8 - Total logical records read\n";
        $hdr .= "#    9 - Total logical records rejected\n";
        $hdr .= "#   10 - Total logical records discarded\n";
        $hdr .= "#   11 - Start time\n#   12 - End time\n";
        $hdr .= "#   13 - Elapsed time\n#   14 - CPU time";
    } else {
        $hdr = "SQL*Loader error report\n";
        $hdr .= "=" x length($hdr) . "\n"; 
        $hdr .= "# Output format:\n";
        $hdr .= "# ORA-#####   counts\n";
        $hdr .= "# ORA-#####:tabname:colname (count) record range\n";
    }
    my %A = (); my @B = (); my %C = ();
    $C{'Jan'} = 1;   $C{'Feb'} = 2;   $C{'Mar'} = 3;   $C{'Apr'} = 4;  
    $C{'May'} = 5;   $C{'Jun'} = 6;   $C{'Jul'} = 7;   $C{'Aug'} = 8;  
    $C{'Sep'} = 9;   $C{'Oct'} = 10;  $C{'Nov'} = 11;  $C{'Dec'} = 12;  
    open LOGF, "<$ifn" or croak "Could not open file - $ifn"; 
    my ($rec,$rec_no,$rec_dsp,$j,$tn,$cn);
    if ($typ eq 'error') {
        while (<LOGF>) {
            next if (!$_ || /^#/);   # skip empty and comment lines 
        # Record 4: Rejected - Error on table S090P035.
        # ORA-01401: inserted value too large for column
        #
        # Record 27: Rejected - Error on table S090P001, column CONS_TM.
        # ORA-01401: inserted value too large for column
            if (/^Record\s*(\d+):\s*(.+)/) {  # reserve record info
                $rec_no = $1;              # record number 
                $rec_dsp = $2;             # reason for being rejected
                if ($rec_dsp =~ /table (.*),/) { $tn = $1; }
                if ($rec_dsp =~ /column (.*)\./) { $cn = $1; }
            }
            if (/^(ORA-\d+):\s*(.+)/) {
                $j = $1;                   # error number
                $A{$j}{'dsp'} = $2;        # error descriptions
                $A{$j}{'id'}  = $j;
                ++$A{$j}{'cnt'};           # counts for the same errors
                if ($A{$j}{'rng'}) {       # record range 
                    $A{$j}{'rng'} .= ",$rec_no";
                } else { $A{$j}{'rng'} = $rec_no; } 
                $A{$j}{'tn'} = $tn; 
                $A{$j}{'cn'} = $cn; 
            }
        }
    } else { 
        for my $i (0..13) { $B[$i] = 0; }; 
        while (<LOGF>) {
            next if (!$_ || /^#/);   # skip empty and comment lines 
            # get Oracle table name. It has the following format:
            # Table S025P036:
            if ($_ =~ /^Table\s*(.*):$/) { $B[1] = $1; next; }
            #   3 Rows successfully loaded.
            if ($_ =~ /\s*(\d+)\s*Row(s?) successfully loaded\.$/) {
                $B[2] = $1; next; 
            }
            #  2 Rows not loaded due to data errors.
            if (/due to data errors\.$/ && /^\s*(\d+)/ )
            {   $B[3] = $1; next; }
            #  0 Rows not loaded because all WHEN clauses were failed.
            if (/all WHEN clauses were failed\.$/ && /^\s*(\d+)/) {
                $B[4] = $1; next; 
            }
            #   0 Rows not loaded because all fields were null.
            if (/all fields were null\.$/ && /^\s*(\d+)/) {
                $B[5] = $1; next; 
            }
            # Total logical records skipped:          0
            if (/^Total logical records skipped:\s*(\d+)/) {
                $B[6] = $1; next;
            }
            # Total logical records read:             5
            if (/^Total logical records read:\s*(\d+)/) {
                $B[7] = $1; next;
            }
            # Total logical records rejected:         2
            if (/^Total logical records rejected:\s*(\d+)/) {
                $B[8] = $1; next;
            }
            # Total logical records discarded:        0
            if (/^Total logical records discarded:\s*(\d+)/) {
                $B[9] = $1; next;
            }
            # Run began on Fri Jan 26 22:23:15 2001
            if (/^Run began on/) {
                if (/(\w+) (\d\d) (\d\d):(\d\d):(\d\d) (\d{1,4})$/) {
                    $B[10] = sprintf "%04d/%02d/%02d %02d:%02d:%02d", 
                        $6, $C{$1}, $2, $3, $4, $5; 
                } else { $B[10] = ""; }
                next; 
            }
            # Run ended on Fri Jan 26 22:23:16 2001
            if (/^Run ended on/) {
                if (/(\w+) (\d\d) (\d\d):(\d\d):(\d\d) (\d{1,4})$/) {
                    $B[11] = sprintf "%04d/%02d/%02d %02d:%02d:%02d", 
                        $6, $C{$1}, $2, $3, $4, $5; 
                } else { $B[11] = ""; }
                next;
            }
            # Elapsed time was:     00:00:01.11
            if ($_ =~ /^Elapsed time was:\s*(.+)/) {
                $B[12] = $1; next;
            }
            # CPU time was:         00:00:00.10
            if ($_ =~ /^CPU time was:\s*(.+)/) {
                $B[13] = $1; next;
            }
        }   # end of while (<LOGF>)
    }
    close LOGF;
    my $rst = "";
    if ($typ eq 'result') { 
        if ($B[7] == 0) { $B[0] = sprintf('%6s', ''); 
        } else {
            $B[0] = sprintf('%6.2f', $B[2] / $B[7] * 100);
        }
        $rst = $B[0];
        for my $i (1..$#B) { $rst .=  "|$B[$i]"; }
        # print "\@B: @B\n";
    } else { 
        # use Data::Subs wq(sort_array compressArray); 
        my $i = 0; 
        if (%A) {
            $rst = "$ifn\n" . "-" x length($ifn) . "\n"; 
        }
        foreach my $k (sort keys %A) {
            my @a1 = split ",", $A{$k}{'rng'}; 
            next if (!@a1);
            ++$i;
            if ($i>1) { $rst .= "\n"; }
            sort_array(\@a1);
            # print "RNG: $A{$k}{'rng'}\n";
            # print "\@a1: @a1\n";
            $rst .= sprintf "%-10s%6d\n", $k, $A{$k}{'cnt'}; 
            $rst .= sprintf "%-10s:%s\n", $k, $A{$k}{'dsp'};
            $rst .= sprintf "%-10s:%-10s:%-10s (%3d) %s\n", $k, 
                    $A{$k}{'tn'}, $A{$k}{'cn'}, $A{$k}{'cnt'}, 
                    &compressArray(\@a1);
        }
        # print "\%A: " . (keys %A) . "\n";
    }
    if ($rno<=0) { $rst = "$hdr\n$rst"; } 
    if ($rst) { 
        return "$rst\n";
    }
}

sub sort_array {
    my ($arf, $ord) = @_;
    # Input variables:
    #   arr - array containing numbers
    #   ord - sort order: default - ascending; other is decending
    # Local variables:
    #   i,j - loop indexes
    #   tmp - temp variable
    # Global variables used: None
    # Global variables modified/defined:
    #   arr - sorted array
    # Return: None
    #
    my ($j, $tmp);
    for my $i (1..$#{$arf}) {
        if ($ord) {                    # sort numbers in decending order
            for ($j=$i; ${$arf}[$j] > ${$arf}[$j-1]; --$j) {
                if ($j <= 1) { last; } # j=1 has been compared
                $tmp = ${$arf}[$j];
                ${$arf}[$j] = ${$arf}[$j-1];
                ${$arf}[$j-1] = $tmp;
            }
        } else {
            # sort numbers in ascending order
            for ($j = $i; ${$arf}[$j-1] > ${$arf}[$j]; --$j) {
                $tmp = ${$arf}[$j];
                ${$arf}[$j] = ${$arf}[$j-1];
                ${$arf}[$j-1] = $tmp;
            }
        }
    }
    return;
}

sub compressArray {
    my ($arf) = @_;
    # Input variables:
    #   arr - numeric array sorted ascendingly
    # Local variables:
    #
    # Global variables used: None
    # Global variables modified: None
    # Calls-To: None
    # Return: a string
    #
    my $S = ${$arf}[0];
    my $k = 0;
    for my $i (1..$#{$arf}) {
        my $j = $i - 1;
        # skip the second one if it is the same number as the
        # previous one.
        next if (${$arf}[$i] == ${$arf}[$j]);
        if (${$arf}[$i] == (${$arf}[$j] + 1)) {  # if they are adjacent
            if ($i == $#{$arf}) {
                if (substr($S, length($S)-1, 1) ne '-') {
                    $S .= "-${$arf}[$i]"; next;
                } else {
                    $S .= ${$arf}[$i]; next;
                }
            }
            ++$k;
            if (substr($S, length($S)-1, 1) eq '-') {
                next;
            }
            $S .= '-';
        } else {                              # if they are separate
            if ($k) {
                $S .= "${$arf}[$j],${$arf}[$i]";
            } else {
                $S .= ",${$arf}[$i]";
            }
            $k = 0;
        }
    }
    return $S;
}


=over 4

=item * report_results ($typ, $cns, $sdr, $ofn, $ext)

Input variables:

  $typ - database type: Oracle, MSSQL
  $cns - connection string: usr/pwd@db
  $sdr - source directory containing all the 
         definition files
  $ofn - output file name  
  $ext - log file extension such as "log", "lst",
         etc.

Variables used or methods called: 

  param    - class method to get parameters
  read_log - read an Oracle log file

How to use:

  $self->report_results;

Return: None. 

This method reads all the SQL*Loader log files in a load directory
and generates a nice report with the following fields:

   1 - Success Rate
   2 - Oracle table name
   3 - Rows successfully loaded
   4 - Rows not loaded due to data errors
   5 - Rows not loaded because all WHEN clauses were 
       failed
   6 - Rows not loaded because all fields were null
   7 - Total logical records skipped
   8 - Total logical records read
   9 - Total logical records rejected
  10 - Total logical records discarded
  11 - Start time
  12 - End time
  13 - Elapsed time
  14 - CPU time

=back

=cut

sub report_results {
    my $self     = shift; 
    #   get_load_results: $typ, $cns, $sdr, $ofn, $ext
    #   $typ - database type: Oracle, MSSQL
    #   $cns - connection string: usr/pwd@db
    #   $sdr - source directory containing all the definition files
    #   $ofn - output file name  
    #   $ext - log file extension such as "log", "lst", etc.
    #
    my ($typ,$cns,$sdr,$ofn,$ext)=
          $self->_getInput2('report_results', @_);
    if (!-d $sdr) { croak "Could not find source directory - $sdr."; }
    $self->echoMSG("  + Getting load results for log files in $sdr");
    # get a list of def file names
    opendir(DIR, "$sdr") || 
        croak "Unable to open directory - $sdr: $!\n";
    my $dsp = $self->set_param('DirSep', $self);
    my @fn = map "$sdr$dsp$_", grep /$ext$/, readdir DIR; 
    closedir DIR;
    if (!@fn) {
        print "    No log files in $sdr!\n"; 
        return;
    }
    my $rpt = (index($ofn, '\/')>-1)?$ofn:join $dsp, $sdr, $ofn;
    # open the output file 
    if (-f $rpt && $self->{overwrite} eq 'Y' && $self->{append} ne 'Y') {
        unlink $rpt;
    }
    $self->echoMSG("    to report file $rpt...");
    open OUT, ">>$rpt" or croak "Could not open output file - $rpt.";
    for my $i (0..$#fn) {
        if (-z $fn[$i]) {
            print OUT "# WARNING: no content in $fn[$i]\n";
            next;
        }
        print OUT $self->read_log('result', $fn[$i], $i); 
    }
    close OUT;
}

=over 4

=item * report_errors ($typ, $cns, $sdr, $ofn, $ext)

Input variables:

  $typ - database type: Oracle, MSSQL
  $cns - connection string: usr/pwd@db
  $sdr - source directory containing all the 
         definition files
  $ofn - output file name  
  $ext - log file extension such as "log", "lst",
         etc.

Variables used or methods called: 

  param    - class method to get parameters
  read_log - read an Oracle log file

How to use:

  $self->report_errors;

Return: None. 

This method reads all the SQL*Loader log files in a load directory
and generates a nice error report with the following information:

  SQL*Loader error report
  ========================
  # Output format:
  # ORA-#####   counts
  # ORA-#####:table_name:colum_name (count) record range

=back

=cut

sub report_errors {
    my $self     = shift; 
    #   report_erros: $typ, $cns, $sdr, $ofn, $ext
    #   $typ - database type: Oracle, MSSQL
    #   $cns - connection string: usr/pwd@db
    #   $sdr - source directory containing all the definition files
    #   $ofn - output file name  
    #   $ext - definition file extension such as "def", "var", etc.
    #
    my ($typ,$cns,$sdr,$ofn,$ext)=
          $self->_getInput2('report_errors', @_);
    if (!-d $sdr) { croak "Could not find source directory - $sdr."; }
    $self->echoMSG("  + Getting load errors from $sdr");
    # get a list of def file names
    opendir(DIR, "$sdr") || 
        croak "Unable to open directory - $sdr: $!\n";
    my $dsp = $self->set_param('DirSep', $self);
    my @fn = map "$sdr$dsp$_", grep /$ext$/, readdir DIR; 
    closedir DIR;
    if (!@fn) {
        print "    No definition files in $sdr!\n"; 
        return;
    }
    my $rpt = (index($ofn, '\/')>-1)?$ofn:join $dsp, $sdr, $ofn;
    # open the output file 
    if (-f $rpt && $self->{overwrite} eq 'Y' && $self->{append} ne 'Y') {
        unlink $rpt;
    }
    $self->echoMSG("    to report file $rpt...");
    open OUT, ">>$rpt" or croak "Could not open output file - $rpt.";
    for my $i (0..$#fn) {
        print OUT $self->read_log('error', $fn[$i], $i); 
    }
    close OUT;
}

sub _list_vars {
    my $vs  = "cols_ref,out_fh,sql_fn,ctl_fn,dat_fn,bad_fn,dis_fn,";
       $vs .= "log_fn,def_fn,reset,dbsid,dbusr,dbpwd,dbhome,conn,";
       $vs .= "direct,spool,dbtab,dbts,ts_iext,ts_next,src_dir,";
       $vs .= "append,vbm,Oracle,CSV,overwrite,dbconn,DirSep,commit,";
       $vs .= "db_type,relax_req,add_center,study_number,drop,def_ex";
    my @vars = split /,/, $vs;
    wantarray ? @vars : \@vars;
} 

sub set_dbconn {
    my $self = shift;
    my $cns  = shift;    # in usr/pwd@db
    my @a   = split /\//, $cns;   
    my @b   = split /\@/, $a[1];
    my ($usr, $pwd, $sid) = ($a[0], $b[0], $b[1]);
    $self->set_param('dbusr',$self,$usr);
    $self->set_param('dbpwd',$self,$pwd);
    $self->set_param('dbsid',$self,$sid);
    $self->set_param('dbconn',$self,"$usr/$pwd\@$sid");
    $self->set_param('conn',$self,["DBI:Oracle:$sid",$usr,$pwd]);
}

sub _getInputs {
    my $self     = shift; 
    my $sub      = shift;
    # initialize variables and check inputs 
    #   (ColRef,FN,Appd,DataFile/OraTab,Reset)
    # crt_sql: (ColRef,SQLFN,Appd,OraTab,ReSet,Drop)
    # crt_ctl: (ColRef,FH/CTLFN,Appd,DataFile,ReSet,Drop)
    my $reset = $_[4] if (defined($_[4]));       # Y or N
    my $drp   = $_[5] if (defined($_[5]));       # Y or N
       $drp   = $self->{drop} if !$drp;
       $drp   = 'Y'       if !$drp;
    my $rst = 0;                                 # 1 or 0
    if ($reset) { $rst = ($reset eq 'Y')?1:0;
    } else      { $rst = ($self->{reset} eq 'Y')?1:0; }
    my $crf = "";               # array ref for column def array 
       # 1st input: ColRef
       $crf = shift 
         if (ref($_[0]) eq 'ARRAY' || ($_[0] && $_[0] =~ /.*=ARRAY/)); 
    if ($rst) {
         # uncomment the following line if you want to re-set cols_ref
         # every time a ref to pass througj crt_sql or crt_ctl
         $self->{cols_ref} = $crf if ($crf);
    }
       $crf = $self->{cols_ref} if (!$crf);       # or use obj value
    my $fh  = "";                               # 2nd input: FH or 
       $fh  = shift if ($_[0] && (ref($_[0]) =~ /^(GLOB|IO::Handle)/ ||
           $_[0] =~ /.*=(GLOB|IO::Handle)/)); 
    if ($rst) { $self->{out_fh} = $fh if ($fh); }
       $fh  = $self->{out_fh} if (!$fh);          # or use obj value
    my $fn  = "";                               # 2nd input: FN
       $fn  = shift if ($_[0] && $_[0] !~ /^(Y|N|O)$/i ); # use input 
    my $appd = "";                              # 3rd input: Y/N/O
       $appd = uc shift if ($_[0]);             # change to upper case 
    if ($rst) { $self->{append} = $appd if ($appd); }
       $appd = $self->{append} if (!$appd);         # get it from init
    my $dat = "";                               # 4th input: DataFile
       $dat = shift if ($_[0]);                 # use input 
    if ($sub eq 'crt_ctl') {
       if ($rst) { $self->{dat_fn} = $dat if ($dat); }
       $dat = $self->{dat_fn} if (!$dat);           # or use obj value
       if ($rst) { $self->{ctl_fn} = $fn if ($fn); }
       $fn  = $self->{ctl_fn} if (!$fn);            # use obj value
        if (!$dat && $fn) {
            my ($bnm,$dir,$typ)=fileparse($fn,'\.\w+$');
            $dat = "$dir${bnm}.dat";
        }
       if ($rst) { $self->{dat_fn} = $dat if ($dat); }
    } else {
       # in crt_sql, we are expecting oracle table name
       if ($rst) { $self->{dbtab} = $dat if ($dat); }
       $dat = $self->{dbtab} if (!$dat);
       if ($rst) { $self->{sql_fn} = $fn if ($fn); }
       $fn  = $self->{sql_fn} if (!$fn);            # use obj value
    }
    if (!$fh) {          # if file handler still not being defined 
        if ($fn) {       # if a file name is specified
            # check the existance of the file
            if (-f $fn && $appd eq 'N') {
                if ($self->{overwrite} eq 'Y') {
                    unlink $fn;
                } else {
                    croak "File $fn exist!";
                }
            }
            if ($appd eq 'Y' && $sub ne 'crt_ctl') {
                # append to the file
                $fh = new IO::File ">>$fn";
            } else {
                $fh = new IO::File ">$fn";
            }
        } else {
            $fh = *STDOUT;
        }
    } 
    $self->echoMSG("  - Creating $fn ($sub)...");
    return ($crf,$fh,$fn,$appd,$dat,$rst,$drp); 
}

sub _getInput2 {
    my $self = shift; 
    my $sub  = shift;
    # Input variables:
    #              creat: $typ, $cns, $sfn, $phm
    #               load: $typ, $cns, $ctl, $phm, $log
    #              batch: $typ, $cns, $sdr, $phm, $ext
    #       load_results: $typ, $cns, $sdr, $ofn, $ext
    #        load_errors: $typ, $cns, $sdr, $ofn, $ext
    #
    #   output var names: $typ, $cns, $ctl, $hmd, $log
    #   $typ - DB type: Oracle, MSSQL,
    #   $cns - connection string: usr/pwd@db
    #   $sfn/$ctl/$sdr - sql/control file name/source directory
    #   $phm - program (sqlldr) home directory 
    #   $log - log file name
    # 
    my $rst = ($self->{reset} eq 'Y')?1:0;
    my $typ = "Oracle";  # database type default to Oracle
       $typ = shift if ($_[0]);
    my $cns = "";        # connection string usr/pwd@db
       $cns = shift if ($_[0]);
       $cns = $self->{dbconn} if (!$cns);
    if ($cns ne $self->{dbconn} && $rst) { $self->set_dbconn($cns); }
    my $ctl = "";        # control file name
       $ctl = shift if ($_[0]); 
    if ($sub eq 'create') {          # get SQL file name
       $ctl = $self->{sql_fn} if (!$ctl); 
       if ($ctl ne $self->{sql_fn} && $rst) { $self->{sql_fn} = $ctl; }
    } elsif ($sub =~ /^(batch|report_results|report_errors)/) {
       $ctl = $self->{src_dir} if (!$ctl); 
       if ($sub =~ /^(batch)/) { 
           if ($ctl ne $self->{src_dir} && $rst) { $self->{src_dir} = $ctl ; }
       }
    } else {
       $ctl = $self->{ctl_fn} if (!$ctl); 
       if ($ctl ne $self->{ctl_fn} && $rst) { $self->{ctl_fn} = $ctl; }
    }
    my $hmd = "";        # Oracle home directory
       $hmd = shift if ($_[0]);
    my $log = "";        # log file name
       $log = shift if ($_[0]);
    if ($sub eq 'load') {
       $log = $self->{log_fn} if (!$log); 
       if ($log ne $self->{log_fn} && $rst) { $self->{log_fn} = $log; }
    } elsif ($sub eq "batch") {
       $log = $self->{def_ex}; 
       $log = "def" if !$log;
    } elsif ($sub =~ /^(report_results|report_errors)/) {
       $log = "log";
    }
    if ($sub !~ /^(report_results|report_errors)/) {
        if ($typ eq "Oracle")     { $hmd = $self->{dbhome} if (!$hmd); 
            if ($hmd ne $self->{dbhome} && $rst) { $self->{dbhome} = $hmd; }
        } elsif ($typ eq "MSSQL") { $hmd = $self->{msshome} if (!$hmd);
            if ($hmd ne $self->{msshome} && $rst) { $self->{msshome} = $hmd; }
        } else {                    $hmd = ""; }
    }
    if (!$hmd) { 
        my $e1 = "rpt";
        if ($sub =~ /^(report_results)/) { $e1 = "rst";
        } elsif ($sub =~ /^(report_errors)/) { $e1 = "err"; }
        if ($self->{study_number}) {
            $hmd = sprintf "S%03d_ldr.$e1", $self->{study_number};
        } else {
            my @a = split /\//, $ctl;
            $hmd = "$a[$#a-1]_ldr.$e1";
        }
    } 
    return ($typ, $cns, $ctl, $hmd, $log);
}


1;   # ensure that the module can be successfully used.

__END__


=head1 FAQ

=head2 What are the parameters?

            CSV = []                            
         DirSep = /                             
         Oracle = [DBI:Oracle:orcl,usrid,userpwd]
     add_center =                               
         append = N                             
         bad_fn = /dlb/data/S083/load/s083p001.bad
       cols_ref = ARRAY(0x1787a4)               
         commit = N                             
           conn = ConnType::CSV,ConnType::Oracle
         ctl_fn = /dlb/data/S083/load/s083p001.ctl
         dat_fn = /dlb/data/S083/load/s083p001.dat
        db_type = Oracle                        
         dbconn = usrid/userpwd@orcl          
         dbhome = /export/home/oracle7          
          dbpwd = userpwd                       
          dbsid = orcl                          
          dbtab = p083p001                      
           dbts = data_ts                       
          dbusr = userid                       
         def_fn = /dlb/data/S083/load/s083p001.def
         direct = N                             
         dis_fn = /dlb/data/S083/load/s083p001.dis
         log_fn = /dlb/data/S083/load/s083p001.log
         out_fh =                               
      overwrite = Y                             
      relax_req = Y                             
          reset = Y                             
          spool = /tmp/xx_tst.lst               
         sql_fn = /tmp/xx_tst.sql               
        src_dir =                               
   study_number =                               
        ts_iext = 21k                           
        ts_next = 2k                            
            vbm = Y                             

=over 4

=item * database parameters

Currently only two connection types are available: CSV and Oracle. 
None of them has been implemented to use in creating tables or loading
data. This consideration is intended to be implemented in the future
versions. 
  
You can get the connection information using these methods:

    # create the loader object
    $ldr = new Oracle::Loader;
    # get connection array reference
    $a = $ldr->{conn};   
    # output the contents
    print "@$a\n";

You can set the connection using these methods:

    $ldr->{conn} = ["DBI:CSV:f_dir=/tmp"]; # or
    $ldr->{conn} = ["DBI:Oracle:sidxx"), "usrid", "usrpwd"];
    $ldr->sync;
  Or 
    $ldr->{dbconn} = "usrid/usrpwd@db";
    $ldr->sync;
  Or
    $ldr->{dbsid} = 'sidxx';
    $ldr->{dbusr} = 'orausr';
    $ldr->{dbpwd} = 'orapwd';
    $ldr->sync;

Other database parameters:

    # set Oracle tablespace name
    $ldr->{dbts} = 'USER_DATA'; 
    # set tablespace intial extent
    $ldr->{ts_iext} = '10k'; 
    # set tablespace next extent
    $ldr->{ts_next} = '5k';
    # set table name
    $ldr->{dbtab} = 's083ae'; 
    # set database type
    $ldr->{db_type} = 'Oracle';
    # database executable home directory
    $ldr->{dbhome} = '/export/home/oracle7';

=item * input/output file names

There are two ways to run this program: in single or batch mode.
If it runs in single mode the input file name defined in I<def_fn>
is used; otherwise, the definiton files in the source directory are
searched. The source directory is defined through parameter 
I<src_dir>. These are the parameters related to input files:

    # set definition file name
    $ldr->{def_fn} = '/tmp/load/s083p001.def';
    # set source directory containing all the definition files
    $ldr->{src_dir} = '/data/S083/load'; 

The important parameter is I<cols_ref>. This parameter is re-set by
running I<read_definition> method. If we did not set I<def_fn> or
I<src_dir>, we can set I<cols_ref> parameter directly, and the action
methods such as I<crt_sql> and I<crt_ctl> will use the array referenced
by I<cols_ref> parameter to create SQL and control files. You could use
Data::Describe module to form column definitions and pass the reference
to I<cols_ref> in the Loader. 

These are the parameters related to SQL file:

    # set sql file name
    $ldr->{sql_fn} = '/tmp/xx_tst.sql';
    # set spool file name 
    $ldr->{spool} =  '/tmp/xx_tst.lst';

The only parameters related to report file names are I<study_number> 
and I<src_dir>. If no report file name is specified in 
I<report_results> or I<report_errors> methods, the report file name 
is formed using I<study_number>. If no I<study_number>, then the 
directory name one level above I<src_dir> is used. For instance, if 
we have

    $ldr->{study_number} = '90';
    $ldr->{src_dir} = '/tmp/S083/load'; 

then the report file names are 'S090_ldr.rst' and 'S090_ldr.err' for 
result report and error report respectively. The report files will be 
resided under '/tmp/S083/load'. If we reset the I<study_number> to 
null, then the report file names will be 'S083_ldr.rst' and 
'S083_ldr.err' for result and error reports respectively. 

These are the parameters related to control file:

    # set control file name
    $ldr->{ctl_fn} = '/tmp/load/s083p001.ctl';
    # set data file name for SQL*Loader
    $ldr->{dat_fn} = '/tmp/load/s083p001.dat';
    # set discard file name
    $ldr->{dis_fn} = '/tmp/load/s083p001.dis';
    # set bad file name
    $ldr->{bad_fn} = '/tmp/load/s083p001.bad';
    # set log file name
    $ldr->{log_fn} = '/tmp/load/s083p001.log';

If an output file handler is defined, the SQL codes or control codes
will be written to the file handler. The I<sql_fn> or I<ctl_fn> will
be ignored.

=item * boolean parameters

The boolean parameters are used to turn on or off some of the features
or functions this program have. They use Y or N (or null). Here is a 
list of the parameters (the first one is the default value):

  add_center (N/Y): whether to add center number or 
                    foreign key to all the tables.
      append (N/Y): whether to append the output to 
                    existing file such as SQL or 
                    control file.
      commit (N/Y): whether to actually create tables 
                    and load data into the tables.
      direct (N/Y): whether to use direct path in 
                    SQL*Loader to load data into the 
                    tables.
   overwrite (N/Y): whether to over write existing files 
                    if they already exist. 
   relax_req (Y/N): whether to relax the constraints 
                    defined in the definition file. If 
                    yes, then only the constraints in 
                    column names containing 'ID' are 
                    enabled.
       reset (Y/N): whether to re-set the parameters if 
                    new values are passed in through a 
                    method such as I<crt_sql>, I<crt_ctl>, 
                    I<load>, I<create>, etc.
         vbm (N/Y): whether to display more information 
                    about the progress.                             

=item * miscellaneous parameters

We only have one miscellaneous parameter, i.e., I<DirSep>. It is 
currently set to '/' for Unix system. It could be determined by 
using Perl special variable - '$^O' ('$OSNAME'). Here is how to 
change it to NT directory separater:  

    $ldr->{DirSep} = '\\';

=back

=head2 How to create a Loader object? 

You can create an empty Loader object using the following methods:

  $ldr = Oracle::Loader->new();
  $ldr = new Oracle::Loader;

If you have an hash array %p containing all the parameters, you use 
the array to initialize the object: 

  $ldr->init(%p);

You can create your hash array to define your object attributes 
as the following:

  %p = (
    'vbm'       => 'Y',    # use verbose mode 
     'cols_ref' => \@C,    # array_ref for col defs
    );
  $ldr = Oracle::Loader->new(%p);

=head2 How to change the array references in the display object

You can pass data and column definition array references to display
objects using the object constructor I<new> or using the I<set> methods:

  $ldr = Oracle::Loader->new($arf, $crf); 
  $ldr->{data_ref} = \@new_array;
  $ldr->{cols_ref} = \@new_defs;     


=head2 How to access the object?

You can get the information from the object through all the 
methods described above without providing a value for the parameters. 

=head2 Future Implementation

Although it seems a simple task, it requires a lot of thinking to get
it working in an object-oriented frame. Intented future implementation
includes 

=over 4

=item * add MSSQL type so that it can create T-SQL codes and DTS codes

=item * a debugger option

A method can also be implemented to turn on/off the debugger. 

=item * a logger option

This option will allow output and/or debbuging information to be 
logged.

=back

=head1 CODING HISTORY

=over 4

=item * Version 0.01

12/10/2000 (htu) - Initial coding

=item * Version 1.00

02/15/2001 (htu) - major restructuring

=item * Version 1.01

02/15/2001 (htu) - quote Oracle key words

=item * Version 1.02

02/15/2004 - removed dependence from Data::subs
for sort_array and compressArray methods.

=item * Version 1.03

6/15/2004 (htu) - added pre-requisite module Class::Struct in the test
script.

=item * Version 1.04

7/19/2004 (htu) - removed some unrelated inline comments and try to 
find out why it failed the test on CPAN while it runs ok on my 
computer.

=item * Version 1.05

Commented out all the tests in Loader.t to see if it fails CPAN tests.

=item * Version 1.06

The problem is the './t/Loader.t' in MANIFEST. CPAN takes it when
it is entered as 't/Loader.t'.

=item * Version 1.10

Remove Class::Struct implementaiton since this PM does not work as
expected with new Class::Struct.

=item * Version 1.11

Added Debug::EchoMessage as pre-requisit for testing.


=back

=head1 SEE ALSO (some of docs that I check often)

Data::Describe, perltoot(1), perlobj(1), perlbot(1), perlsub(1), 
perldata(1),
perlsub(1), perlmod(1), perlmodlib(1), perlref(1), perlreftut(1).

=head1 AUTHOR

Copyright (c) 2000-2001 Hanming Tu.  All rights reserved.

This package is free software and is provided "as is" without express
or implied warranty.  It may be used, redistributed and/or modified
under the terms of the Perl Artistic License (see
http://www.perl.com/perl/misc/Artistic.html)

=cut

