# Copyright (C) 1996, David Muir Sharnoff

package File::Flock;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(lock unlock);

use Carp;
#use FileHandle;

#
# It would be nice if I could use fcntl.ph and
# errno.ph, but alas, that isn't safe.
#
use POSIX qw(EAGAIN ENOENT EEXIST O_EXCL O_CREAT O_RDONLY O_WRONLY); 
sub LOCK_SH {1;}
sub LOCK_EX {2;}
sub LOCK_NB {4;}
sub LOCK_UN {8;}

use vars qw($VERSION $debug);

BEGIN	{
	$VERSION = 96.111802;
	$debug = 0;
}

use strict;
no strict qw(refs);

my %locks;
my %lockHandle;
my %shared;
my %pid;

my $gensym = "sym0000";

sub lock
{
	my ($file, $shared, $nonblocking) = @_;
	#my $f = new FileHandle;

	#$gensym++;
	my $f = "File::Flock::$gensym";

	my $created = 0;
	my $previous = exists $locks{$file};

	# the file may be springing in and out of existance...
	OPEN:
	for(;;) {
		if (-e $file) {
# 			unless ($f->open($file, O_RDONLY)) {
			unless (sysopen($f, $file, O_RDONLY)) {
				redo OPEN if $! == ENOENT;
				croak "open $file: $!";
			}
		} else {
# 			unless ($f->open($file, O_CREAT|O_EXCL|O_WRONLY)) {
			unless (sysopen($f, $file, O_CREAT|O_EXCL|O_WRONLY)) {
				redo OPEN if $! == EEXIST;
				croak "open >$file: $!";
			}
			print " {$$ " if $debug;
			$created = 1;
		}
		last;
	}
	$locks{$file} = $created || $locks{$file} || 0;
	$shared{$file} = $shared;
	$pid{$file} = $$;
	
	$lockHandle{$file} = $f;

	my $flags;

	$flags = $shared ? &LOCK_SH : &LOCK_EX;
	$flags |= &LOCK_NB
		if $nonblocking;
	
	my $r = flock($f, $flags);

	print " ($$ " if $debug and $r;

	if ($r) {
		# let's check to make sure the file wasn't
		# removed on us!

		my $ifile = (stat($file))[1];
		#my $ihandle = (stat($f))[1];
		eval "\$File::Flock::ihandle = (stat($f))[1]";
		die $@ if $@;

		#return 1 if defined $ifile 
			#and defined $ihandle 
			#and $ifile == $handle;

		return 1 if defined $ifile 
			and defined $File::Flock::ihandle 
			and $ifile == $File::Flock::ihandle;

		# oh well, try again
		flock($f, LOCK_UN);
		close($f);
		return lock($file);
	}

	return 1 if $r;
	if ($nonblocking and $! == EAGAIN) {
		if (! $previous) {
			delete $locks{$file};
			delete $lockHandle{$file};
			delete $shared{$file};
		}
		if ($created) {
			# oops, a bad thing just happened.  
			# We don't want to block, but we made the file.
			# so we're going to have to wait around for
			# it.
			&background_remove($f, $file);
		}
		return 0;
	}
	croak "flock $f $flags: $!";
}

sub background_remove
{
	my ($f, $file) = @_;
	#
	# first try to grab it, if that doesn't work, fork off a 
	# child to handle it in the background.
	#
	if (flock($f, LOCK_EX|LOCK_NB)) {
		unlink($file)
			if -s $file == 0;
		flock($f, LOCK_UN);
	} else {
		my $ppid = fork;
		croak "cannot fork" unless defined $ppid;
		my $pppid = $$;
		my $b0 = $0;
		$0 = "$b0: waiting for child ($ppid) to fork()";
		unless ($ppid) {
			my $pid = fork;
			croak "cannot fork" unless defined $pid;
			unless ($pid) {
				$0 = "$b0: unlocking $f";
				flock($f, LOCK_EX);
				unlink($file)
					if -s $file == 0;
				print " $pppid] $pppid)" if $debug;
				flock($f, LOCK_UN);
			}
			exit(0);
		}
		waitpid($ppid, 0);
	}
}

sub unlock
{
	my ($file) = @_;

	croak "no lock on $file" unless exists $locks{$file};
	my $created = $locks{$file};

	if ($created and -s $file == 0) {
		if ($shared{$file}) {
			&background_remove($lockHandle{$file}, $file);
		} else {
			print " $$} " if $debug;
			unlink($file) 
				or croak "unlink $file: $!";
		}
	}
	delete $locks{$file};

	my $f = $lockHandle{$file};

	delete $lockHandle{$file};

	return 0 unless defined $f;

	print " $$) " if $debug;
	flock($f, &LOCK_UN)
		or croak "flock $f UN: $!";

	close($f);
	return 1;
}

END {
	my $f;
	for $f (keys %locks) {
		&unlock($f)
			if $pid{$f} == $$;
	}
}

1;

__DATA__

=head1 NAME

 File::Flock - file locking with flock

=head1 SYNOPSIS

 use File::Flock;

 lock($filename);

 lock($filename, 'shared');

 lock($filename, undef, 'nonblocking');

 lock($filename, 'shared', 'nonblocking');

 unlock($filename);

=head1 DESCRIPTION

Lock files using the flock() call.  If the file to be locked does not
exist, then the file is created.  If the file was created then it will
be removed when it is unlocked assuming it's still an empty file.

=head1 AUTHOR

David Muir Sharnoff, <muir@idiom.com>


