# Copyright (C) 1996, David Muir Sharnoff

package File::Flock;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(lock unlock);

use Carp;

#
# It would be nice if I could use fcntl.ph and
# errno.ph, but alas, that isn't safe.
#
use POSIX qw(EAGAIN ENOENT EEXIST O_EXCL O_CREAT O_RDWR O_WRONLY); 
sub LOCK_SH {1;}
sub LOCK_EX {2;}
sub LOCK_NB {4;}
sub LOCK_UN {8;}

use vars qw($VERSION $debug);

BEGIN	{
	$VERSION = 98.112801;
	$debug = 0;
}

use strict;
no strict qw(refs);

my %locks;
my %lockHandle;
my %shared;
my %pid;
my %rm;

my $gensym = "sym0000";

sub new
{
	my ($pkg, $file, $shared, $nonblocking) = @_;
	lock($file, $shared, $nonblocking) || return undef;
	return bless $pkg, \$file;
}

sub DELETE
{
	my ($this) = @_;
	unlock $$this;
}

sub lock
{
	my ($file, $shared, $nonblocking) = @_;

	$gensym++;
	my $f = "File::Flock::$gensym";

	my $created = 0;
	my $previous = exists $locks{$file};

	# the file may be springing in and out of existance...
	OPEN:
	for(;;) {
		if (-e $file) {
			unless (sysopen($f, $file, O_RDWR)) {
				redo OPEN if $! == ENOENT;
				croak "open $file: $!";
			}
		} else {
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
		my $ihandle;
		eval "\$ihandle = (stat($f))[1]";
		die $@ if $@;

		return 1 if defined $ifile 
			and defined $ihandle 
			and $ifile == $ihandle;

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
			delete $pid{$file};
		}
		if ($created) {
			# oops, a bad thing just happened.  
			# We don't want to block, but we made the file.
			&background_remove($f, $file);
		}
		close($f);
		return 0;
	}
	croak "flock $f $flags: $!";
}

#
# get a lock on a file and remove it if it's empty.  This is to
# remove files that were created just so that they could be locked.
#
# To do this without blocking, defer any files that are locked to the
# the END block.
#
sub background_remove
{
	my ($f, $file) = @_;

	if (flock($f, LOCK_EX|LOCK_NB)) {
		unlink($file)
			if -s $file == 0;
		flock($f, LOCK_UN);
	} else {
		$rm{$file} = 1
			unless exists $rm{$file};
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
	delete $pid{$file};

	my $f = $lockHandle{$file};

	delete $lockHandle{$file};

	return 0 unless defined $f;

	print " $$) " if $debug;
	flock($f, &LOCK_UN)
		or croak "flock $file UN: $!";

	close($f);
	return 1;
}

#
# Unlock any files that are still locked and remove any files
# that were created just so that they could be locked.
#
END {
	my $f;
	for $f (keys %locks) {
		&unlock($f)
			if $pid{$f} == $$;
	}

	my %bgrm;
	for my $file (keys %rm) {
		$gensym++;
		my $f = "File::Flock::$gensym";
		if (sysopen($f, $file, O_RDWR)) {
			if (flock($f, LOCK_EX|LOCK_NB)) {
				unlink($file)
					if -s $file == 0;
				flock($f, LOCK_UN);
			} else {
				$bgrm{$file} = 1;
			}
			close($f);
		}
	}
	if (%bgrm) {
		my $ppid = fork;
		croak "cannot fork" unless defined $ppid;
		my $pppid = $$;
		my $b0 = $0;
		$0 = "$b0: waiting for child ($ppid) to fork()";
		unless ($ppid) {
			my $pid = fork;
			croak "cannot fork" unless defined $pid;
			unless ($pid) {
				for my $file (keys %bgrm) {
					$gensym++;
					my $f = "File::Flock::$gensym";
					if (sysopen($f, $file, O_RDWR)) {
						if (flock($f, LOCK_EX)) {
							unlink($file)
								if -s $file == 0;
							flock($f, LOCK_UN);
						}
						close($f);
					}
				}
				print " $pppid] $pppid)" if $debug;
			}
			kill(9, $$); # exit w/o END or anything else
		}
		waitpid($ppid, 0);
		kill(9, $$); # exit w/o END or anything else
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


