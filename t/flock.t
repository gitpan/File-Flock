#!/usr/bin/perl5.00502 -w -I.

$counter = "/tmp/flt1.$$";
$lock    = "/tmp/flt2.$$";
$lock2   = "/tmp/flt3.$$";
$lock3   = "/tmp/flt4.$$";
$lock4   = "/tmp/flt5.$$";
$lock5   = "/tmp/flt6.$$";
$lock6   = "/tmp/flt7.$$";
$lock7   = "/tmp/flt8.$$";

use File::Flock;
use Carp;
use FileHandle;

STDOUT->autoflush(1);

$children = 6;
$count = 120;
die unless $count % 2 == 0;
die unless $count % 3 == 0;
print "1..".($count*1.5+$children*2+7)."\n";

my $child = 0;
my $i;
for $i (1..$children) {
	$p = fork();
	croak unless defined $p;
	$parent = $p or $child = $i;
	last unless $parent;
}

STDOUT->autoflush(1);

if ($parent) {
	print "ok 1\n";
	&write_file($counter, "2");
	&write_file($lock, "");
	&write_file($lock4, "");
	lock($lock4);
} else {
	my $e;
	while (! -e $lock) {
		# spin
		die if $e++ > 1000000;
	}
	lock($lock3, 'shared');
}

lock($lock2, 'shared');

my $c;
my $ee;
while (($c = &read_file($counter)) < $count) {
	die if $ee++ > 10000000;
	if ($c < $count*.25 || $c > $count*.75) {
		lock($lock);
	} else {
		lock($lock, 0, 1) || next;
	}
	$c = &read_file($counter);

	# make sure each child increments it at least once.
	if ($c < $children+2 && $c != $child+2) {
		unlock($lock);
		next;
	}

	if ($c < $count) {
		print "ok $c\n";
		$c++;
		&overwrite_file($counter, "$c");
	}

	# one of the children will exit (and thus need to clean up)
	if ($c == $count/3) {
		exit(0) if fork() == 0;
	}

	# deal with a missing lock file
	if ($c == $count/2) {
		unlink($lock)
			or croak "unlink $lock: $!";
	}

	# make sure the lock file doesn't get deleted
	if ($c == int($count*.9)) {
		&overwrite_file($lock, "keepme");
	}

	unlock($lock);
}

lock($lock);
$c = &read_file($counter);
print "ok $c\n";
$c++;
&overwrite_file($counter, "$c");
unlock($lock);

if ($c == $count+$children+1) {
	print "ok $c\n";
	$c++;
	if (&read_file($lock) eq 'keepme') 
		{print "ok $c\n";} else {print "not ok $c\n"};
	unlink($lock);
	$c++;
}

unlock($lock2);

if ($parent) {
	lock($lock2);
	unlock($lock2);

	$c = $count+$children+3;

	&write_file($counter, $c);
	unlock($lock4);
}


# okay, now that that's all done, lets try some locks using
# the object interface...

my $start = $c;

for(;;) {
	my $l = new File::Flock $lock4;

	$c = &read_file($counter);

	last if $c > $count/2+$start;

	print "ok $c\n";
	$c++;
	&overwrite_file($counter, "$c");
}
#
# now let's make sure nonblocking works
#
if ($parent) {
	my $e;
	lock $lock6;
	for(;;) {
		lock($lock7, undef, 'nonblocking')
			or last;
		unlock($lock7);
		die if $e++ > 1000;
		sleep(1);
	}
	unlock $lock6;
	lock $counter;
	$c = &read_file($counter);
	print "ok $c\n";
	$c++;
	&overwrite_file($counter, "$c");
	unlock $counter;

} elsif ($child == 1) {
	my $e;
	for(;;) {
		lock($lock6, undef, 'nonblocking')
			or last;
		unlock($lock6);
		die if $e++ > 1000;
		sleep(1);
	}
	lock $lock7;
	lock $lock6;
	lock $counter;
	$c = &read_file($counter);
	print "ok $c\n";
	$c++;
	&overwrite_file($counter, "$c");
	unlock $counter;
	unlock $lock7;
	unlock $lock6;
} 

#
# Shut everything down
#
if ($parent) {
	my $l = new File::Flock $lock3;
	$c = &read_file($counter);
	if ($l) { print "ok $c\n" } else {print "not ok $c\n"}
	$c++;
	unlink($counter);
	unlink($lock4);
	unlink($lock);
	lock($lock5);
	unlock($lock5);
	if (-e $lock5) { print "not ok $c\n" } else {print "ok $c\n"}
	$c++;
	$x = '';
	for (1..$children) {
		wait();
		$status = $? >> 8;
		if ($status) { $x .= "not ok $c\n";} else {$x .= "ok $c\n"}
		$c++;
	}
	$l->unlock();
	print $x;
} else {
	unlock($lock3);
}
exit(0);

sub read_file
{
	my ($file) = @_;

	local(*F);
	my $r;
	my (@r);

	open(F, "<$file") || croak "open $file: $!";
	@r = <F>;
	close(F);

	return @r if wantarray;
	return join("",@r);
}

sub write_file
{
	my ($f, @data) = @_;

	local(*F);

	open(F, ">$f") || croak "open >$f: $!";
	(print F @data) || croak "write $f: $!";
	close(F) || croak "close $f: $!";
	return 1;
}

sub overwrite_file
{
	my ($f, @data) = @_;

	local(*F);

	if (-e $f) {
		open(F, "+<$f") || croak "open +<$f: $!";
	} else {
		open(F, "+>$f") || croak "open >$f: $!";
	}
	(print F @data) || croak "write $f: $!";
	my $where = tell(F);
	croak "could not tell($f): $!"
		unless defined $where;
	truncate(F, $where)
		|| croak "trucate $f at $where: $!";
	close(F) || croak "close $f: $!";
	return 1;
}

sub append_file
{
	my ($f, @data) = @_;

	local(*F);

	open(F, ">>$f") || croak "open >>$f: $!";
	(print F @data) || croak "write $f: $!";
	close(F) || croak "close $f: $!";
	return 1;
}

sub read_dir
{
	my ($d) = @_;

	my (@r);
	local(*D);

	opendir(D,$d) || croak "opendir $d: $!";
	@r = grep($_ ne "." && $_ ne "..", readdir(D));
	closedir(D);
	return @r;
}

1;
