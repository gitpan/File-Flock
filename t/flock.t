#!/usr/local/bin/perl -w

unshift(@INC, ".");

$counter = "/tmp/flt1.$$";
$lock    = "/tmp/flt2.$$";

use File::Flock;
use Carp;
use FileHandle;

STDOUT->autoflush(1);

$children = 8;
$count = 200;
print "1..".($count+$children*2+2)."\n";

my $i;
for $i (1..$children) {
	$p = fork();
	croak unless defined $p;
	$parent = $p;
	last unless $parent;
}

STDOUT->autoflush(1);

if ($parent) {
	print "ok 1\n";
	&write_file($counter, "2");
	&write_file($lock, "");
} else {
	while (! -e $lock) {
		# spin
	}
}

my $c;
while (($c = &read_file($counter)) < $count) {
	if ($c < $count*.25 || $c > $count*.75) {
		lock($lock);
	} else {
		lock($lock, 0, 1) || next;
	}
	$c = &read_file($counter);
	if ($c == $count/3) {
		exit(0) if fork() == 0;
	}
	if ($c < $count) {
		print "ok $c\n";
		$c++;
		&overwrite_file($counter, "$c");
	}
	if ($c == $count/2) {
		unlink($lock)
			or croak "unlink $lock: $!";
	}
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
	unlink($counter);
	if (&read_file($lock) eq 'keepme') 
		{print "ok $c\n";} else {print "not ok $c\n"};
	unlink($lock);
	$c++;
}

if ($parent) {
	$x = '';
	$c = $count+$children+3;
	for (1..$children) {
		wait();
		$status = $? >> 8;
		if ($status) { $x .= "not ok $c\n";} else {$x .= "ok $c\n"}
		$c++;
	}
	print $x;
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

__DATA__

=head1 NAME

	File::Slurp -- single call read & write file routines; read directories

=head1 SYNOPSIS

	use File::Slurp;

	$all_of_it = read_file($filename);
	@all_lines = read_file($filename);

	write_file($filename, @contents)

	overwrite_file($filename, @new_contnts);

	append_file($filename, @additional_contents);

	@files = read_dir($directory);

=head1 DESCRIPTION

These are quickie routines that are meant to save a couple of lines of
code over and over again.  They do not do anything fancy.
 
read_file() does what you would expect.  If you are using its output
in array context, then it returns an array of lines.  If you are calling
it from scalar context, then returns the entire file in a single string.

It croaks()s if it can't open the file.

write_file() creates or overwrites files.

append_file() appends to a file.

overwrite_file() does an in-place update of an existing file or creates
a new file if it didn't already exist.  Write_file will also replace a
file.  The difference is that the first that that write_file() does is 
to trucate the file whereas the last thing that overwrite_file() is to
trucate the file.  Overwrite_file() should be used in situations where
you have a file that always needs to have contents, even in the middle
of an update.

read_dir() returns all of the entries in a directory except for "."
and "..".  It croaks if it cannot open the directory.

=head1 AUTHOR

David Muir Sharnoff <muir@idiom.com>

